import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../../core/constants/math_constants.dart';
import '../models/ast_node.dart';
import '../models/calc_error.dart';
import '../models/calc_value.dart';
import '../models/math_context.dart';
import 'algebra_solver_engine.dart';
import 'calculus_engine.dart';
import 'cancellation_token.dart';
import 'complex_math.dart';
import 'decimal_math.dart';
import 'gamma_combinatorics.dart';
import 'transcendental_engine.dart';

/// A chain of bound variables (`x` inside `∫ … dx`, `d/dx`, table rows).
final class _Scope {
  const _Scope(this.name, this.value, this.parent);
  final String name;
  final CalcValue value;
  final _Scope? parent;

  CalcValue? lookup(String key) {
    for (_Scope? s = this; s != null; s = s.parent) {
      if (s.name == key) return s.value;
    }
    return null;
  }
}

/// Master tree walker: evaluates an [AstNode] and dispatches to the
/// specialised engines (transcendental, gamma, calculus, complex, matrix,
/// Base-N).
final class AstEvaluator {
  AstEvaluator({
    this.context = const MathContext(),
    Map<String, CalcValue>? variables,
    CancellationToken? token,
    math.Random? random,
  })  : variables = variables ?? const <String, CalcValue>{},
        token = token ?? CancellationToken.none,
        _random = random ?? math.Random();

  final MathContext context;

  /// Stored variables (`Ans`, `M`, `A`..`Z`, `x`, `MatA` …).
  final Map<String, CalcValue> variables;

  final CancellationToken token;

  /// Source of `Rand`.
  final math.Random _random;

  final Expando<String> _displayOverrides = Expando<String>('display');

  static final Rational _hundred = Rational.fromInt(100);
  static final BigInt _b0 = BigInt.zero;
  static final BigInt _b1 = BigInt.one;
  static final RegExp _decimalLiteral = RegExp(r'^(\d+\.?\d*|\.\d+)(E[+-]?\d+)?$');

  /// Largest number of terms of a `Σ` or `Π`.
  static final BigInt maxSeriesTerms = BigInt.from(10000000);

  /// What the first pass of [_settled] got at each node that does not give
  /// the same answer twice: the result of a numerical method (`∫`, `d/dx`)
  /// with the distance it may be off by, or a random number. Only what was
  /// computed outside the body of a numerical method is kept. The term of a
  /// `Σ` or `Π` visits its nodes once per index, hence a list per node; every
  /// pass reads it from the start ([_cursor]).
  final Map<AstNode, List<(Decimal, Decimal)>> _numerical = Map<AstNode, List<(Decimal, Decimal)>>.identity();
  final Map<AstNode, int> _cursor = Map<AstNode, int>.identity();

  /// Whether the running evaluation used a value that is not good to the
  /// full working precision (`∫`, `d/dx`, a non-integer factorial).
  bool _approximated = false;

  /// Nesting depth of `∫` / `d/dx` bodies being sampled.
  int _sampling = 0;

  /// Second pass of [_settled]: numerical results are replayed, moved by
  /// their error bound.
  bool _nudging = false;

  /// Special display string of [value] (e.g. the `m × 10^E` form of a
  /// log-Stirling factorial), if it has one.
  String? displayOverrideFor(CalcValue value) => _displayOverrides[value];

  /// Evaluates [node].
  CalcValue evaluate(AstNode node) {
    token.throwIfCancelled();
    return _settled(() => _eval(node, null));
  }

  /// Evaluates [node] with `variable = value` bound on top of [variables].
  CalcValue evaluateWith(AstNode node, String variable, CalcValue value) {
    token.throwIfCancelled();
    final scope = _Scope(variable, value, null);
    return _settled(() => _eval(node, scope));
  }

  // ------------------------------------------------- precision of the result

  /// Runs an evaluation and cuts the result back to the digits it can be
  /// trusted to.
  ///
  /// `∫` and `d/dx` are numerical methods, good for about
  /// [CalculusEngine.resultPrecision] digits (a non-integer factorial for
  /// [GammaCombinatorics.gammaDigits]), and whatever is computed from them is
  /// no better: `∫(0, π, sin(x)²) + 3e^(−1/2)` would print 34 digits of which
  /// 14 are right, and `Ans` would carry the other 20 into the next line.
  /// How much of the final value is affected depends on what happened to the
  /// numerical result on the way - adding 512 costs nothing, subtracting a
  /// close number costs nearly everything - so it is measured: the
  /// expression is evaluated a second time with every numerical result moved
  /// by its error bound, and the digits the two runs share are kept. The
  /// second run reuses the integrals and derivatives; it only repeats the
  /// arithmetic around them.
  CalcValue _settled(CalcValue Function() run) {
    _numerical.clear();
    _cursor.clear();
    _approximated = false;
    _sampling = 0;
    _nudging = false;
    final value = run();
    if (!_approximated || _displayOverrides[value] != null) return value;
    CalcValue? nudged;
    _nudging = true;
    _cursor.clear();
    try {
      nudged = run();
    } on CancelledEvaluationError {
      rethrow;
    } on CalcError {
      // The moved value left the domain (the root of a result that was
      // exactly 0, ...). `nudged` stays null: fall back to the precision of
      // the method.
    } finally {
      _nudging = false;
    }
    return _shared(value, nudged);
  }

  /// [value] reduced to what it has in common with [nudged].
  static CalcValue _shared(CalcValue value, CalcValue? nudged) {
    switch (value) {
      case DecimalVal(value: final d):
        final other = switch (nudged) {
          DecimalVal(value: final n) => n,
          RationalVal(value: final n) => Dec.fromRational(n),
          _ => null,
        };
        return DecimalVal(_sharedDigits(d, other));
      case ComplexVal(:final real, :final imag):
        final other = nudged is ComplexVal ? nudged : null;
        return ComplexVal(_sharedDigits(real, other?.real), _sharedDigits(imag, other?.imag));
      case MatrixVal(:final grid):
        final other =
            nudged is MatrixVal && nudged.rows == grid.length && nudged.cols == grid.first.length ? nudged.grid : null;
        return MatrixVal(<List<Decimal>>[
          for (var r = 0; r < grid.length; r++)
            <Decimal>[for (var c = 0; c < grid[r].length; c++) _sharedDigits(grid[r][c], other?[r][c])],
        ]);
      case RationalVal() || BitwiseVal():
        return value;
    }
  }

  /// The leading digits of [value] that moving it to [nudged] leaves alone,
  /// down to the digit the move shows up in. Zero when the move is larger
  /// than the value itself: what remains of `∫(0, π, sin(x)²) − π/2` is the
  /// rounding of the integral, not a number.
  static Decimal _sharedDigits(Decimal value, Decimal? nudged) {
    if (nudged == null) return Dec.round(value, CalculusEngine.resultPrecision);
    final spread = Dec.abs(Dec.sub(nudged, value));
    if (Dec.isZero(spread) || Dec.isZero(value)) return value;
    final digits = Dec.adjExp(value) - Dec.adjExp(spread) + 1;
    return digits < 1 ? Dec.zero : Dec.round(value, digits);
  }

  /// Second pass: what the first one recorded for this visit of [node].
  (Decimal, Decimal)? _recorded(AstNode node) {
    if (!_nudging || _sampling > 0) return null;
    final known = _numerical[node];
    final at = _cursor[node] ?? 0;
    if (known == null || at >= known.length) return null;
    _cursor[node] = at + 1;
    return known[at];
  }

  /// Second pass: the recorded result of [node], moved by its error bound.
  CalcValue? _replayed(AstNode node) {
    final known = _recorded(node);
    return known == null ? null : _dv(Dec.add(known.$1, known.$2));
  }

  /// `Rand`: a random number from 0 up to, but not including, 1, with ten
  /// decimals. Every `Rand` of an expression is a number of its own; the
  /// second pass gets the numbers of the first one again.
  CalcValue _randomNumber(AstNode node) {
    final known = _recorded(node);
    if (known != null) return DecimalVal(known.$1);
    final digits = '${_random.nextInt(100000)}'.padLeft(5, '0') + '${_random.nextInt(100000)}'.padLeft(5, '0');
    final value = Dec.parse('0.$digits');
    if (_sampling == 0 && !_nudging) (_numerical[node] ??= <(Decimal, Decimal)>[]).add((value, Dec.zero));
    return DecimalVal(value);
  }

  /// Runs a numerical [method] and records its result and error bound.
  CalcValue _numericalResult(AstNode node, Decimal Function(UncertaintySink report) method) {
    var bound = Dec.zero;
    final Decimal value;
    _sampling++;
    try {
      value = method((b) => bound = Dec.max(bound, b));
    } finally {
      _sampling--;
    }
    if (_sampling == 0 && !_nudging) {
      (_numerical[node] ??= <(Decimal, Decimal)>[]).add((value, bound));
      if (!Dec.isZero(bound)) _approximated = true;
    }
    return _dv(value);
  }

  /// Unpacks a factorial: the display form of a giant one, the error bound
  /// of an approximated one.
  CalcValue _factorialValue(FactorialResult result) {
    final value = result.value;
    if (result.display != null) _displayOverrides[value] = result.display;
    final bound = result.uncertainty;
    if (bound == null || _sampling > 0 || value is! DecimalVal) return value;
    _approximated = true;
    return _nudging ? _dv(Dec.add(value.value, bound)) : value;
  }

  // ------------------------------------------------------------------ walker

  CalcValue _eval(AstNode node, _Scope? scope) {
    token.tick();
    switch (node) {
      case NumberNode(:final literal):
        return _literal(literal);
      case ConstantNode(:final name):
        return name == 'Rand' ? _randomNumber(node) : _constant(name);
      case VariableNode(:final name):
        final v = scope?.lookup(name) ?? variables[name];
        if (v == null) throw UndefinedVariableError('Variable $name has no value');
        return v;
      case UnaryNode(:final op, :final operand):
        final v = _eval(operand, scope);
        return switch (op) {
          UnaryOp.plus => v,
          UnaryOp.negate => negate(v),
          UnaryOp.bitNot => BaseN.not(_bits(v)),
        };
      case BinaryNode(:final op, :final left, :final right):
        final l = _eval(left, scope);
        // Additive percentage: 200 + 15% = 200 + 200 × 15 / 100.
        if ((op == BinaryOp.add || op == BinaryOp.subtract) &&
            right is PostfixNode &&
            right.op == PostfixOp.percent &&
            l.isRealScalar) {
          final share = multiply(l, _percent(_eval(right.operand, scope)));
          return op == BinaryOp.add ? add(l, share) : subtract(l, share);
        }
        return binary(op, l, _eval(right, scope));
      case PostfixNode(:final op, :final operand):
        final v = _eval(operand, scope);
        switch (op) {
          case PostfixOp.percent:
            return _percent(v);
          case PostfixOp.degree:
            return _fromDegrees(v);
          case PostfixOp.factorial:
            return _factorialValue(GammaCombinatorics.factorial(v, token: token));
        }
      case FunctionNode(:final name, :final args):
        return _call(name, <CalcValue>[for (final a in args) _eval(a, scope)]);
      case DerivativeNode(:final body, :final point, :final variable):
        final replayed = _replayed(node);
        if (replayed != null) return replayed;
        final x0 = _real(_eval(point, scope), 'The point of a derivative');
        return _numericalResult(
          node,
          (report) => CalculusEngine.derivative(
            (x) => _realBody(body, variable, x, scope),
            x0,
            token: token,
            onUncertainty: report,
          ),
        );
      case SeriesNode(:final lower, :final upper, :final term, :final variable, :final isProduct):
        final sign = isProduct ? 'Π' : 'Σ';
        final first = integerOf(_eval(lower, scope)), last = integerOf(_eval(upper, scope));
        if (first == null || last == null) {
          throw DomainError('$sign counts in whole numbers: $variable must start and end at one');
        }
        if (last - first >= maxSeriesTerms) throw DomainError('$sign has too many terms');
        // From a first value above the last one nothing is added or
        // multiplied: the empty sum is 0, the empty product 1.
        CalcValue total = isProduct ? Values.one : Values.zero;
        for (var k = first; k <= last; k += _b1) {
          token.tick();
          final value = _eval(term, _Scope(variable, Values.ofBigInt(k), scope));
          total = isProduct ? multiply(total, value) : add(total, value);
        }
        return total;
      case IntegralNode(:final lower, :final upper, :final integrand, :final variable):
        final replayed = _replayed(node);
        if (replayed != null) return replayed;
        final a = _real(_eval(lower, scope), 'The lower bound');
        final b = _real(_eval(upper, scope), 'The upper bound');
        return _numericalResult(
          node,
          (report) => CalculusEngine.integrate(
            (x) => _realBody(integrand, variable, x, scope),
            a,
            b,
            token: token,
            onUncertainty: report,
          ),
        );
    }
  }

  Decimal _realBody(AstNode body, String variable, Decimal x, _Scope? scope) {
    final v = _eval(body, _Scope(variable, DecimalVal(x), scope));
    return _real(v, 'The function');
  }

  // ----------------------------------------------------------------- literals

  CalcValue _literal(String text) {
    final baseN = context.baseN;
    if (baseN != null) return BaseN.parse(text, baseN);
    if (!_decimalLiteral.hasMatch(text)) throw SyntaxError('Malformed number "$text"');
    final e = text.indexOf('E');
    if (e >= 0) {
      final exponent = int.tryParse(text.substring(e + 1));
      if (exponent == null || exponent.abs() > kMaxExponent) {
        if (exponent != null && exponent < 0) return Values.zero;
        throw const OverflowError();
      }
    }
    return Values.ofDecimalExact(Dec.parse(text));
  }

  CalcValue _constant(String name) {
    switch (name) {
      case 'π':
        return DecimalVal(MathConstants.pi());
      case 'e':
        return DecimalVal(MathConstants.e);
      case 'φ':
        return DecimalVal(MathConstants.phi);
      case 'i':
        return ComplexMath.i;
    }
    final physical = MathConstants.physical(name);
    if (physical != null) return Values.ofDecimalExact(Dec.parse(physical.value));
    throw SyntaxError('Unknown constant "$name"');
  }

  // ------------------------------------------------------------- conversions

  DecimalVal _dv(Decimal d) {
    if (!Dec.isZero(d)) {
      final x = Dec.adjExp(d);
      if (x > kMaxExponent) throw const OverflowError();
      if (x < -kMaxExponent) return DecimalVal(Dec.zero);
    }
    return DecimalVal(d);
  }

  ComplexVal _cv(ComplexVal z) {
    _dv(z.real);
    _dv(z.imag);
    return z;
  }

  Decimal _real(CalcValue v, String what) => switch (v) {
        RationalVal(:final value) => Dec.fromRational(value),
        DecimalVal(:final value) => value,
        BitwiseVal(:final numericValue) => Dec.fromBigInt(numericValue),
        ComplexVal(:final real, :final imag) =>
          Dec.isZero(imag) ? real : throw DomainError('$what must be a real number'),
        MatrixVal() => throw DimensionError('$what must be a scalar'),
      };

  ComplexVal _complex(CalcValue v) => switch (v) {
        ComplexVal() => v,
        MatrixVal() => throw const DimensionError('A scalar is required here'),
        _ => ComplexVal(_real(v, 'The operand'), Dec.zero),
      };

  BitwiseVal _bits(CalcValue v) {
    final cfg = context.baseN ?? const BaseNConfig();
    switch (v) {
      case BitwiseVal():
        return v;
      case RationalVal(:final value) when value.denominator == _b1:
        return BitwiseVal.wrap(value.numerator, wordSize: cfg.wordSize, isSigned: cfg.isSigned);
      default:
        throw const DomainError('Bitwise operators need whole numbers');
    }
  }

  static bool isZero(CalcValue v) => switch (v) {
        RationalVal(:final value) => value.numerator == BigInt.zero,
        DecimalVal(:final value) => Dec.isZero(value),
        ComplexVal() => ComplexMath.isZero(v),
        BitwiseVal(:final bits) => bits == BigInt.zero,
        MatrixVal() => false,
      };

  /// The integer held by [v], or `null`.
  static BigInt? integerOf(CalcValue v) => switch (v) {
        RationalVal(:final value) => value.denominator == BigInt.one ? value.numerator : null,
        DecimalVal(:final value) => Dec.isInteger(value) && Dec.adjExp(value) < 4000 ? Dec.toBigInt(value) : null,
        BitwiseVal(:final numericValue) => numericValue,
        ComplexVal() || MatrixVal() => null,
      };

  CalcValue _percent(CalcValue v) => switch (v) {
        RationalVal(:final value) => rationalOrDecimal(value / _hundred),
        _ => divide(v, RationalVal(_hundred)),
      };

  /// `x°`: degrees expressed in the current angle unit.
  CalcValue _fromDegrees(CalcValue v) {
    switch (context.angleUnit) {
      case AngleUnit.deg:
        return v;
      case AngleUnit.grad:
        return divide(multiply(v, Values.ofInt(10)), Values.ofInt(9));
      case AngleUnit.rad:
        return _dv(Transcendental.toRadians(_real(v, 'An angle'), AngleUnit.deg));
    }
  }

  // --------------------------------------------------------------- arithmetic

  /// Sum / difference of two inexact numbers: a result that is more than 42
  /// orders of magnitude below the operands is cancellation noise (zero-snap).
  DecimalVal _snappedSum(Decimal a, Decimal b, Decimal sum) {
    if (!Dec.isZero(sum) && !Dec.isZero(a) && !Dec.isZero(b)) {
      final xa = Dec.adjExp(a), xb = Dec.adjExp(b);
      if (Dec.adjExp(sum) < (xa > xb ? xa : xb) + Transcendental.zeroSnapExponent) return DecimalVal(Dec.zero);
    }
    return _dv(sum);
  }

  CalcValue negate(CalcValue v) => switch (v) {
        RationalVal(:final value) => RationalVal(-value),
        DecimalVal(:final value) => DecimalVal(Dec.neg(value)),
        ComplexVal() => ComplexMath.neg(v),
        BitwiseVal() => BaseN.negate(v),
        MatrixVal() => MatrixOps.scale(v, Dec.fromInt(-1)),
      };

  CalcValue add(CalcValue a, CalcValue b) {
    if (a is MatrixVal || b is MatrixVal) {
      if (a is MatrixVal && b is MatrixVal) return MatrixOps.add(a, b);
      throw const DimensionError('A matrix and a scalar cannot be added');
    }
    if (a is BitwiseVal || b is BitwiseVal) return BaseN.add(_bits(a), _bits(b));
    if (a is ComplexVal || b is ComplexVal) return _cv(ComplexMath.add(_complex(a), _complex(b)));
    if (a is RationalVal && b is RationalVal) return a.plus(b);
    final da = _real(a, ''), db = _real(b, '');
    return _snappedSum(da, db, Dec.add(da, db));
  }

  CalcValue subtract(CalcValue a, CalcValue b) {
    if (a is MatrixVal || b is MatrixVal) {
      if (a is MatrixVal && b is MatrixVal) return MatrixOps.sub(a, b);
      throw const DimensionError('A matrix and a scalar cannot be subtracted');
    }
    if (a is BitwiseVal || b is BitwiseVal) return BaseN.sub(_bits(a), _bits(b));
    if (a is ComplexVal || b is ComplexVal) return _cv(ComplexMath.sub(_complex(a), _complex(b)));
    if (a is RationalVal && b is RationalVal) return a.minus(b);
    final da = _real(a, ''), db = _real(b, '');
    return _snappedSum(da, db, Dec.sub(da, db));
  }

  CalcValue multiply(CalcValue a, CalcValue b) {
    if (a is MatrixVal) {
      return b is MatrixVal ? MatrixOps.mul(a, b) : MatrixOps.scale(a, _real(b, 'A matrix factor'));
    }
    if (b is MatrixVal) return MatrixOps.scale(b, _real(a, 'A matrix factor'));
    if (a is BitwiseVal || b is BitwiseVal) return BaseN.mul(_bits(a), _bits(b));
    if (a is ComplexVal || b is ComplexVal) return _cv(ComplexMath.mul(_complex(a), _complex(b)));
    if (a is RationalVal && b is RationalVal) return a.times(b);
    return _dv(Dec.mul(_real(a, ''), _real(b, '')));
  }

  CalcValue divide(CalcValue a, CalcValue b) {
    if (b is MatrixVal) return multiply(a, MatrixOps.inverse(b));
    if (isZero(b)) throw const DivisionByZero();
    if (a is MatrixVal) return MatrixOps.scale(a, Dec.div(Dec.one, _real(b, 'A matrix divisor'), WORK_PREC + 4));
    if (a is BitwiseVal || b is BitwiseVal) return BaseN.div(_bits(a), _bits(b));
    if (a is ComplexVal || b is ComplexVal) return _cv(ComplexMath.div(_complex(a), _complex(b)));
    if (a is RationalVal && b is RationalVal) return a.dividedBy(b);
    return _dv(Dec.div(_real(a, ''), _real(b, '')));
  }

  /// `a mod b` with the sign of the divisor.
  CalcValue modulo(CalcValue a, CalcValue b) {
    if (a is BitwiseVal || b is BitwiseVal) return BaseN.mod(_bits(a), _bits(b));
    if (isZero(b)) throw const DivisionByZero('Modulo by zero');
    if (a is RationalVal && b is RationalVal) {
      final q = (a.value / b.value).floor();
      return rationalOrDecimal(a.value - b.value * Rational(q));
    }
    final da = _real(a, 'mod'), db = _real(b, 'mod');
    final q = Dec.floor(Dec.div(da, db, WORK_PREC + 10));
    return _dv(Dec.sub(da, Dec.mul(db, q, 1000)));
  }

  /// `r∠θ`: the complex number with modulus [modulus] and argument [angle],
  /// the angle in the current angle unit.
  CalcValue polar(CalcValue modulus, CalcValue angle) {
    final r = _real(modulus, 'The modulus in front of ∠');
    final theta = _real(angle, 'The angle behind ∠');
    final cos = Transcendental.cos(theta, context.angleUnit, token: token).value;
    final sin = Transcendental.sin(theta, context.angleUnit, token: token).value;
    return _cv(ComplexVal(Dec.mul(r, cos), Dec.mul(r, sin)));
  }

  /// Any binary operator.
  CalcValue binary(BinaryOp op, CalcValue l, CalcValue r) => switch (op) {
        BinaryOp.add => add(l, r),
        BinaryOp.subtract => subtract(l, r),
        BinaryOp.multiply => multiply(l, r),
        BinaryOp.divide => divide(l, r),
        BinaryOp.power => power(l, r),
        BinaryOp.modulo => modulo(l, r),
        BinaryOp.polar => polar(l, r),
        BinaryOp.bitAnd => BaseN.and(_bits(l), _bits(r)),
        BinaryOp.bitOr => BaseN.or(_bits(l), _bits(r)),
        BinaryOp.bitXor => BaseN.xor(_bits(l), _bits(r)),
        BinaryOp.shiftLeft => BaseN.shiftLeft(_bits(l), _bits(r)),
        BinaryOp.shiftRight => BaseN.shiftRight(_bits(l), _bits(r)),
      };

  // -------------------------------------------------------------------- power

  bool _isEulerE(CalcValue v) => v is DecimalVal && identical(v.value, MathConstants.e);

  CalcValue power(CalcValue base, CalcValue exponent) {
    if (exponent is MatrixVal) throw const DimensionError('A matrix cannot be an exponent');
    if (base is MatrixVal) {
      final n = integerOf(exponent);
      if (n == null || n.bitLength > 16) throw const DomainError('A matrix power needs a whole exponent');
      return MatrixOps.power(base, n.toInt());
    }
    if (base is BitwiseVal || exponent is BitwiseVal) return BaseN.pow(_bits(base), _bits(exponent), token);
    if (_isEulerE(base)) return _exp(exponent);
    if (base is ComplexVal || exponent is ComplexVal) {
      return _cv(ComplexMath.pow(_complex(base), _complex(exponent), token: token));
    }
    final n = integerOf(exponent);
    if (n != null && exponent is RationalVal) return _integerPower(base, n);
    if (exponent is RationalVal) return _rationalPower(base, exponent.value);
    // inexact exponent
    final x = _real(base, ''), y = _real(exponent, '');
    final sign = Dec.sign(x);
    if (sign > 0) return _dv(Transcendental.pow(x, y, token: token));
    if (sign == 0) {
      if (Dec.sign(y) > 0) return Values.zero;
      throw const DomainError('0 raised to a non-positive power');
    }
    if (n != null) return _integerPower(base, n);
    if (context.isComplex) return _cv(ComplexMath.pow(_complex(base), _complex(exponent), token: token));
    throw const DomainError('Negative base with a fractional exponent');
  }

  CalcValue _integerPower(CalcValue base, BigInt n) {
    if (isZero(base)) {
      if (n.sign > 0) return base is RationalVal ? Values.zero : DecimalVal(Dec.zero);
      if (n.sign == 0) throw const DomainError('0^0 is undefined');
      throw const DivisionByZero();
    }
    if (n == _b0) return Values.one;
    if (base is RationalVal) {
      final r = base.value;
      if (r.denominator == _b1 && (r.numerator == _b1 || r.numerator == -_b1)) {
        return RationalVal(r.numerator == _b1 || n.isEven ? Rational.one : -Rational.one);
      }
      final bits = r.numerator.bitLength > r.denominator.bitLength ? r.numerator.bitLength : r.denominator.bitLength;
      if (n.bitLength <= 12 && bits * n.abs().toInt() <= kRationalBitCeiling + 64) {
        token.tick();
        return rationalOrDecimal(r.pow(n.toInt()));
      }
    }
    final x = _real(base, '');
    if (n.bitLength <= 62) return _dv(Dec.powInt(x, n.toInt(), token: token));
    // Astronomic exponent: go through logarithms, restoring the sign by parity.
    final magnitude = Transcendental.pow(Dec.abs(x), Dec.fromBigInt(n), token: token);
    return _dv(Dec.isNegative(x) && n.isOdd ? Dec.neg(magnitude) : magnitude);
  }

  /// `base^(p/q)` for an exact, non-integer exponent.
  CalcValue _rationalPower(CalcValue base, Rational exponent) {
    final p = exponent.numerator, q = exponent.denominator;
    if (isZero(base)) {
      if (p.sign > 0) return Values.zero;
      throw const DomainError('0 raised to a non-positive power');
    }
    final negative = switch (base) {
      RationalVal(:final value) => value.numerator.isNegative,
      _ => Dec.isNegative(_real(base, '')),
    };
    if (negative && q.isEven) {
      if (context.isComplex) {
        return _cv(ComplexMath.pow(_complex(base), _complex(RationalVal(exponent)), token: token));
      }
      throw const DomainError('Even root of a negative number');
    }
    // Exact when numerator and denominator are perfect q-th powers.
    if (base is RationalVal && q.bitLength <= 7 && p.bitLength <= 10) {
      final k = q.toInt();
      final r = base.value;
      final num = r.numerator.abs(), den = r.denominator;
      final rootNum = Dec.iroot(num, k), rootDen = Dec.iroot(den, k);
      if (rootNum.pow(k) == num && rootDen.pow(k) == den) {
        final root = Rational(negative ? -rootNum : rootNum, rootDen);
        return _integerPower(RationalVal(root), p);
      }
    }
    final x = Dec.abs(_real(base, ''));
    final magnitude = Transcendental.pow(x, Dec.fromRational(exponent, WORK_PREC + 10), token: token);
    return _dv(negative && p.isOdd ? Dec.neg(magnitude) : magnitude);
  }

  CalcValue _exp(CalcValue v) {
    if (v is MatrixVal) throw const DimensionError('exp of a matrix');
    if (v is ComplexVal) return _cv(ComplexMath.snap(ComplexMath.exp(v, token: token)));
    if (isZero(v)) return Values.one;
    return _dv(Transcendental.exp(_real(v, ''), token: token));
  }

  // ---------------------------------------------------------------- functions

  CalcValue sqrt(CalcValue v) {
    switch (v) {
      case RationalVal(:final value):
        final negative = value.numerator.isNegative;
        if (negative && !context.isComplex) {
          throw const DomainError('Square root of a negative number (enable CPLX)');
        }
        final num = value.numerator.abs(), den = value.denominator;
        final rn = Dec.isqrt(num), rd = Dec.isqrt(den);
        final exact = rn * rn == num && rd * rd == den;
        if (!negative) {
          return exact ? RationalVal(Rational(rn, rd)) : _dv(Dec.sqrt(Dec.fromRational(value, WORK_PREC + 10)));
        }
        final magnitude =
            exact ? Dec.fromRational(Rational(rn, rd)) : Dec.sqrt(Dec.fromRational(-value, WORK_PREC + 10));
        return ComplexVal(Dec.zero, magnitude);
      case DecimalVal(:final value):
        if (!Dec.isNegative(value)) return _dv(Dec.sqrt(value));
        if (!context.isComplex) throw const DomainError('Square root of a negative number (enable CPLX)');
        return ComplexVal(Dec.zero, Dec.sqrt(Dec.neg(value)));
      case ComplexVal():
        return ComplexMath.sqrt(v);
      case BitwiseVal(:final numericValue):
        if (numericValue.isNegative) throw const DomainError('Square root of a negative number');
        return BitwiseVal.wrap(Dec.isqrt(numericValue), wordSize: v.wordSize, isSigned: v.isSigned);
      case MatrixVal():
        throw const DimensionError('Square root of a matrix');
    }
  }

  CalcValue _trig(String name, CalcValue v) {
    if (v is ComplexVal) {
      final z = switch (name) {
        'sin' => ComplexMath.sin(v, token: token),
        'cos' => ComplexMath.cos(v, token: token),
        _ => ComplexMath.tan(v, token: token),
      };
      return _cv(z);
    }
    final x = _real(v, name);
    final unit = context.angleUnit;
    final r = switch (name) {
      'sin' => Transcendental.sin(x, unit, token: token),
      'cos' => Transcendental.cos(x, unit, token: token),
      _ => Transcendental.tan(x, unit, token: token),
    };
    if (r.exact) return Values.ofDecimalExact(r.value);
    return _dv(r.value);
  }

  CalcValue _inverseTrig(String name, CalcValue v) {
    if (v is! ComplexVal) {
      final x = _real(v, name);
      final inDomain = name == 'atan' || Dec.compare(Dec.abs(x), Dec.one) <= 0;
      if (inDomain) {
        if (Dec.isZero(x) && name != 'acos') return Values.zero;
        if (name == 'acos' && Dec.equal(x, Dec.one)) return Values.zero;
        final unit = context.angleUnit;
        return _dv(switch (name) {
          'asin' => Transcendental.asin(x, unit, token: token),
          'acos' => Transcendental.acos(x, unit, token: token),
          _ => Transcendental.atan(x, unit, token: token),
        });
      }
      if (!context.isComplex) throw DomainError('$name is only defined on [-1, 1]');
    }
    final z = _complex(v);
    return _cv(switch (name) {
      'asin' => ComplexMath.asin(z, token: token),
      'acos' => ComplexMath.acos(z, token: token),
      _ => ComplexMath.atan(z, token: token),
    });
  }

  CalcValue _hyperbolic(String name, CalcValue v) {
    if (v is ComplexVal) {
      return _cv(switch (name) {
        'sinh' => ComplexMath.sinh(v, token: token),
        'cosh' => ComplexMath.cosh(v, token: token),
        'tanh' => ComplexMath.tanh(v, token: token),
        _ => throw UnsupportedOperationError('$name of a complex number'),
      });
    }
    final x = _real(v, name);
    if (Dec.isZero(x) && name != 'cosh' && name != 'acosh') return Values.zero;
    return _dv(switch (name) {
      'sinh' => Transcendental.sinh(x, token: token),
      'cosh' => Transcendental.cosh(x, token: token),
      'tanh' => Transcendental.tanh(x, token: token),
      'asinh' => Transcendental.asinh(x, token: token),
      'acosh' => Transcendental.acosh(x, token: token),
      _ => Transcendental.atanh(x, token: token),
    });
  }

  CalcValue _ln(CalcValue v) {
    if (v is MatrixVal) throw const DimensionError('Logarithm of a matrix');
    if (v is! ComplexVal) {
      final x = _real(v, 'ln');
      final sign = Dec.sign(x);
      if (sign > 0) {
        if (v is RationalVal && v.value == Rational.one) return Values.zero;
        return _dv(Transcendental.ln(x, token: token));
      }
      if (sign == 0) throw const DomainError('Logarithm of zero is undefined');
      if (!context.isComplex) throw const DomainError('Logarithm of a negative number (enable CPLX)');
    }
    return _cv(ComplexMath.ln(_complex(v), token: token));
  }

  CalcValue _logBase(CalcValue base, CalcValue v) => divide(_ln(v), _ln(base));

  CalcValue _log10(CalcValue v) {
    if (v is ComplexVal || (v.isRealScalar && Dec.sign(_real(v, 'log')) < 0)) {
      return divide(_ln(v), DecimalVal(MathConstants.ln10()));
    }
    final x = _real(v, 'log');
    if (Dec.isZero(x)) throw const DomainError('Logarithm of zero is undefined');
    final r = Transcendental.log10(x, token: token);
    return Dec.parts(x).m == _b1 ? Values.ofDecimalExact(r) : _dv(r);
  }

  CalcValue _abs(CalcValue v) => switch (v) {
        RationalVal(:final value) => RationalVal(value.abs()),
        DecimalVal(:final value) => DecimalVal(Dec.abs(value)),
        ComplexVal() => _dv(ComplexMath.modulus(v)),
        BitwiseVal(:final numericValue) =>
          BitwiseVal.wrap(numericValue.abs(), wordSize: v.wordSize, isSigned: v.isSigned),
        MatrixVal() => _dv(MatrixOps.determinant(v)),
      };

  CalcValue _rounding(String name, CalcValue v, [CalcValue? places]) {
    if (v is RationalVal && places == null) {
      final r = v.value;
      final whole = switch (name) {
        'floor' => r.floor(),
        'ceil' => r.ceil(),
        'trunc' => r.truncate(),
        _ => r.round(),
      };
      return name == 'frac' ? rationalOrDecimal(r - Rational(r.truncate())) : Values.ofBigInt(whole);
    }
    final x = _real(v, name);
    if (name == 'round' && places != null) {
      final n = integerOf(places);
      if (n == null || n.bitLength > 16) throw const DomainError('round needs a whole number of places');
      return Values.ofDecimalExact(Dec.roundToPlaces(x, n.toInt()));
    }
    return _dv(switch (name) {
      'floor' => Dec.floor(x),
      'ceil' => Dec.ceil(x),
      'trunc' => Dec.truncate(x),
      'frac' => Dec.sub(x, Dec.truncate(x), 1000),
      _ => Dec.roundToPlaces(x),
    });
  }

  int _compare(CalcValue a, CalcValue b) {
    if (a is RationalVal && b is RationalVal) return a.value.compareTo(b.value);
    return Dec.compare(_real(a, 'A comparison'), _real(b, 'A comparison'));
  }

  BigInt _wholeArg(CalcValue v, String name) {
    final n = integerOf(v);
    if (n == null) throw DomainError('$name needs whole numbers');
    return n;
  }

  void _arity(String name, List<CalcValue> args, int min, [int? max]) {
    final hi = max ?? min;
    if (args.length < min || args.length > hi) {
      final expected = min == hi ? '$min' : '$min-$hi';
      throw SyntaxError('$name expects $expected argument${hi == 1 ? '' : 's'}, got ${args.length}');
    }
  }

  CalcValue _call(String name, List<CalcValue> args) {
    CalcValue one() {
      _arity(name, args, 1);
      return args[0];
    }

    switch (name) {
      case 'sin' || 'cos' || 'tan':
        return _trig(name, one());
      case 'asin' || 'acos' || 'atan':
        return _inverseTrig(name, one());
      case 'sinh' || 'cosh' || 'tanh' || 'asinh' || 'acosh' || 'atanh':
        return _hyperbolic(name, one());
      case 'ln':
        return _ln(one());
      case 'log':
        if (args.length == 2) return _logBase(args[0], args[1]);
        return _log10(one());
      case 'logb':
        _arity(name, args, 2);
        return _logBase(args[0], args[1]);
      case 'log2':
        final v = one();
        if (v.isRealScalar && Dec.sign(_real(v, name)) > 0) {
          return _dv(Transcendental.log2(_real(v, name), token: token));
        }
        return divide(_ln(v), DecimalVal(MathConstants.ln2()));
      case 'exp':
        return _exp(one());
      case 'sqrt':
        return sqrt(one());
      case 'cbrt':
        return power(one(), RationalVal(Rational.fromInt(1, 3)));
      case 'root':
        _arity(name, args, 2);
        if (isZero(args[0])) throw const DomainError('The degree of a root cannot be zero');
        return power(args[1], divide(Values.one, args[0]));
      case 'pow':
        _arity(name, args, 2);
        return power(args[0], args[1]);
      case 'abs':
        return _abs(one());
      case 'sgn':
        final v = one();
        return Values.ofInt(v is RationalVal ? v.value.numerator.sign : Dec.sign(_real(v, name)));
      case 'floor' || 'ceil' || 'trunc' || 'frac':
        return _rounding(name, one());
      case 'round':
        _arity(name, args, 1, 2);
        return _rounding(name, args[0], args.length == 2 ? args[1] : null);
      case 'mod':
        _arity(name, args, 2);
        return modulo(args[0], args[1]);
      case 'gcd' || 'lcm':
        if (args.isEmpty) throw SyntaxError('$name expects at least one argument');
        var acc = _wholeArg(args[0], name).abs();
        for (final a in args.skip(1)) {
          final b = _wholeArg(a, name).abs();
          final g = acc.gcd(b);
          acc = name == 'gcd' ? g : (g == _b0 ? _b0 : acc ~/ g * b);
        }
        return Values.ofBigInt(acc);
      case 'min' || 'max':
        if (args.isEmpty) throw SyntaxError('$name expects at least one argument');
        var best = args[0];
        for (final a in args.skip(1)) {
          final c = _compare(a, best);
          if (name == 'min' ? c < 0 : c > 0) best = a;
        }
        return best;
      case 'fact':
        return _factorialValue(GammaCombinatorics.factorial(one(), token: token));
      case 'gamma':
        return _factorialValue(GammaCombinatorics.gamma(one(), token: token));
      case 'ncr':
        _arity(name, args, 2);
        return GammaCombinatorics.nCr(args[0], args[1], token: token);
      case 'npr':
        _arity(name, args, 2);
        return GammaCombinatorics.nPr(args[0], args[1], token: token);
      case 'atan2':
        _arity(name, args, 2);
        final r = Transcendental.atan2Rad(_real(args[0], name), _real(args[1], name), token: token);
        return _dv(Transcendental.fromRadians(r, context.angleUnit));
      case 're':
        final v = one();
        return v is ComplexVal ? _dv(v.real) : v;
      case 'im':
        final v = one();
        return v is ComplexVal ? _dv(v.imag) : Values.zero;
      case 'conj':
        final v = one();
        return v is ComplexVal ? ComplexMath.conj(v) : v;
      case 'arg':
        final r = ComplexMath.argument(_complex(one()), token: token);
        return Dec.isZero(r) ? Values.zero : _dv(Transcendental.fromRadians(r, context.angleUnit));
      case 'det':
        final v = one();
        if (v is! MatrixVal) throw const DimensionError('det needs a matrix');
        return _dv(MatrixOps.determinant(v));
      case 'trn':
        final v = one();
        if (v is! MatrixVal) throw const DimensionError('trn needs a matrix');
        return MatrixOps.transpose(v);
      case 'inv':
        final v = one();
        return v is MatrixVal ? MatrixOps.inverse(v) : divide(Values.one, v);
      case 'identity':
        final n = integerOf(one());
        if (n == null || n < _b1 || n > BigInt.from(MatrixOps.maxDimension)) {
          throw const DimensionError('identity needs a size from 1 to 4');
        }
        return MatrixOps.identity(n.toInt());
    }
    throw SyntaxError('Unknown function "$name"');
  }
}
