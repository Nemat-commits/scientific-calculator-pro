import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../../core/constants/math_constants.dart';
import '../models/calc_error.dart';
import '../models/calc_value.dart';
import '../models/math_context.dart';
import 'decimal_math.dart';
import 'transcendental_engine.dart';

export 'base_n_engine.dart';
export 'function_table_engine.dart';
export 'statistics_engine.dart';

/// Roots of a polynomial, in display order (real roots ascending first).
final class PolynomialSolution {
  const PolynomialSolution(this.roots, {this.discriminant});

  /// Each root is a [RationalVal] (exact), a [DecimalVal] or a [ComplexVal].
  final List<CalcValue> roots;

  /// `b² − 4ac` for quadratics (when it could be formed).
  final CalcValue? discriminant;
}

/// Closed-form solver for polynomials of degree 1 to 3.
abstract final class PolynomialSolver {
  static const int _p = WORK_PREC + 10;
  static final Decimal _three = Dec.fromInt(3);
  static final Decimal _four = Dec.fromInt(4);
  static final Decimal _twentySeven = Dec.fromInt(27);
  static final Decimal _third = Dec.div(Dec.one, _three, _p);

  static Decimal _d(CalcValue v) => switch (v) {
        RationalVal(:final value) => Dec.fromRational(value, _p),
        DecimalVal(:final value) => value,
        _ => throw const DomainError('Coefficients must be real numbers'),
      };

  static Decimal _add(Decimal a, Decimal b) => Dec.add(a, b, _p);
  static Decimal _sub(Decimal a, Decimal b) => Dec.sub(a, b, _p);
  static Decimal _mul(Decimal a, Decimal b) => Dec.mul(a, b, _p);
  static Decimal _div(Decimal a, Decimal b) => Dec.div(a, b, _p);

  /// Treats a value that is tiny next to [scale] as an exact zero.
  static Decimal _snap(Decimal v, Decimal scale) {
    if (Dec.isZero(v) || Dec.isZero(scale)) return v;
    return Dec.adjExp(v) < Dec.adjExp(scale) - 40 ? Dec.zero : v;
  }

  static CalcValue _real(Decimal x) => DecimalVal(Dec.round(x, WORK_PREC));

  /// Solves `c[0] x^n + c[1] x^(n-1) + … + c[n] = 0` for `n` in 1..3.
  static PolynomialSolution solve(List<CalcValue> coefficients) {
    var c = coefficients;
    while (c.length > 1 && _isZero(c.first)) {
      c = c.sublist(1);
    }
    switch (c.length) {
      case 2:
        return PolynomialSolution(<CalcValue>[_linear(c[0], c[1])]);
      case 3:
        return solveQuadratic(c[0], c[1], c[2]);
      case 4:
        return solveCubic(c[0], c[1], c[2], c[3]);
      default:
        throw const DomainError('The leading coefficients are zero: nothing to solve');
    }
  }

  static bool _isZero(CalcValue v) => switch (v) {
        RationalVal(:final value) => value.numerator == BigInt.zero,
        DecimalVal(:final value) => Dec.isZero(value),
        _ => false,
      };

  static CalcValue _linear(CalcValue a, CalcValue b) {
    if (a is RationalVal && b is RationalVal) return rationalOrDecimal(-b.value / a.value);
    return _real(Dec.neg(_div(_d(b), _d(a))));
  }

  /// `a x² + b x + c = 0`
  static PolynomialSolution solveQuadratic(CalcValue a, CalcValue b, CalcValue c) {
    if (_isZero(a)) return solve(<CalcValue>[b, c]);
    if (a is RationalVal && b is RationalVal && c is RationalVal) {
      final ra = a.value, rb = b.value, rc = c.value;
      final disc = rb * rb - Rational.fromInt(4) * ra * rc;
      final twoA = Rational.fromInt(2) * ra;
      if (disc.numerator.sign >= 0) {
        final sn = Dec.isqrt(disc.numerator), sd = Dec.isqrt(disc.denominator);
        if (sn * sn == disc.numerator && sd * sd == disc.denominator) {
          final s = Rational(sn, sd);
          final x1 = (-rb - s) / twoA, x2 = (-rb + s) / twoA;
          final lo = x1 < x2 ? x1 : x2, hi = x1 < x2 ? x2 : x1;
          return PolynomialSolution(
            <CalcValue>[rationalOrDecimal(lo), rationalOrDecimal(hi)],
            discriminant: rationalOrDecimal(disc),
          );
        }
      }
      return _quadraticDecimal(_d(a), _d(b), _d(c), rationalOrDecimal(disc));
    }
    return _quadraticDecimal(_d(a), _d(b), _d(c), null);
  }

  static PolynomialSolution _quadraticDecimal(Decimal a, Decimal b, Decimal c, CalcValue? exactDisc) {
    final b2 = _mul(b, b), fourAc = _mul(_four, _mul(a, c));
    final disc = _snap(_sub(b2, fourAc), Dec.max(Dec.abs(b2), Dec.abs(fourAc)));
    final discriminant = exactDisc ?? _real(disc);
    final twoA = _mul(Dec.two, a);
    if (Dec.sign(disc) >= 0) {
      final s = Dec.sqrt(disc, _p);
      // q = -(b + sign(b) sqrt(disc)) / 2 avoids cancellation.
      final q = Dec.neg(_mul(Dec.half, Dec.isNegative(b) ? _sub(b, s) : _add(b, s)));
      final x1 = _div(q, a);
      final x2 = Dec.isZero(q) ? x1 : _div(c, q);
      final lo = Dec.min(x1, x2), hi = Dec.max(x1, x2);
      return PolynomialSolution(<CalcValue>[_real(lo), _real(hi)], discriminant: discriminant);
    }
    final re = Dec.round(Dec.neg(_div(b, twoA)), WORK_PREC);
    final im = Dec.round(Dec.abs(_div(Dec.sqrt(Dec.neg(disc), _p), twoA)), WORK_PREC);
    return PolynomialSolution(
      <CalcValue>[ComplexVal(re, im), ComplexVal(re, Dec.neg(im))],
      discriminant: discriminant,
    );
  }

  static Decimal _cbrt(Decimal x) {
    if (Dec.isZero(x)) return Dec.zero;
    final r = Transcendental.pow(Dec.abs(x), _third, prec: _p);
    return Dec.isNegative(x) ? Dec.neg(r) : r;
  }

  /// `a x³ + b x² + c x + d = 0` (Cardano / trigonometric form + Newton polish).
  static PolynomialSolution solveCubic(CalcValue a, CalcValue b, CalcValue c, CalcValue d) {
    if (_isZero(a)) return solve(<CalcValue>[b, c, d]);
    final da = _d(a), db = _d(b), dc = _d(c), dd = _d(d);
    final a1 = _div(db, da), a2 = _div(dc, da), a3 = _div(dd, da);
    // x = t - a1/3  ->  t^3 + p t + q = 0
    final shift = Dec.neg(_div(a1, _three));
    final a1sq = _mul(a1, a1);
    final p = _snap(_sub(a2, _div(a1sq, _three)), Dec.max(Dec.abs(a2), a1sq));
    final q1 = _div(_mul(Dec.two, _mul(a1sq, a1)), _twentySeven), q2 = _div(_mul(a1, a2), _three);
    final q = _snap(
      _add(_sub(q1, q2), a3),
      Dec.max(Dec.max(Dec.abs(q1), Dec.abs(q2)), Dec.abs(a3)),
    );
    final quarterQ2 = _div(_mul(q, q), _four), cubeP = _div(_mul(p, _mul(p, p)), _twentySeven);
    final disc = _snap(_add(quarterQ2, cubeP), Dec.max(quarterQ2, Dec.abs(cubeP)));

    Decimal polish(Decimal x) {
      for (var i = 0; i < 2; i++) {
        final f = _add(_mul(_add(_mul(_add(_mul(da, x), db), x), dc), x), dd);
        final df = _add(_mul(_add(_mul(_mul(_three, da), x), _mul(Dec.two, db)), x), dc);
        if (Dec.isZero(f) || Dec.isZero(df)) break;
        final step = _div(f, df);
        if (!Dec.isZero(x) && Dec.adjExp(step) > Dec.adjExp(x) - 8) break; // multiple root: Newton is unreliable
        x = _sub(x, step);
      }
      return x;
    }

    final exact = a is RationalVal && b is RationalVal && c is RationalVal && d is RationalVal
        ? <Rational>[a.value, b.value, c.value, d.value]
        : null;
    CalcValue realRoot(Decimal t) {
      final x = polish(_add(t, shift));
      if (exact != null) {
        final r = _reconstruct(x);
        if (r != null && _evalExact(exact, r).numerator == BigInt.zero) return rationalOrDecimal(r);
      }
      final scale = Dec.max(Dec.abs(shift), Dec.abs(t));
      return _real(_snap(x, scale));
    }

    final sign = Dec.sign(disc);
    if (sign > 0) {
      final s = Dec.sqrt(disc, _p);
      final halfQ = Dec.neg(_mul(q, Dec.half));
      final u = _cbrt(Dec.isNegative(halfQ) ? _sub(halfQ, s) : _add(halfQ, s));
      final v = Dec.isZero(u) ? Dec.zero : Dec.neg(_div(p, _mul(_three, u)));
      final t1 = _add(u, v);
      final re = Dec.round(_add(Dec.neg(_mul(t1, Dec.half)), shift), WORK_PREC);
      final im = Dec.round(Dec.abs(_mul(_mul(Dec.sqrt(_three, _p), Dec.half), _sub(u, v))), WORK_PREC);
      return PolynomialSolution(<CalcValue>[realRoot(t1), ComplexVal(re, im), ComplexVal(re, Dec.neg(im))]);
    }
    if (sign == 0) {
      if (Dec.isZero(p)) {
        final r = realRoot(Dec.zero);
        return PolynomialSolution(<CalcValue>[r, r, r]);
      }
      final single = realRoot(_div(_mul(_three, q), p));
      final double_ = realRoot(Dec.neg(_div(_mul(_three, q), _mul(Dec.two, p))));
      return PolynomialSolution(_sorted(<CalcValue>[single, double_, double_]));
    }
    // Three distinct real roots.
    final m = Dec.sqrt(Dec.neg(_div(p, _three)), _p); // sqrt(-p/3)
    var cosArg = _div(_mul(_three, q), _mul(_mul(Dec.two, p), m));
    if (Dec.compare(Dec.abs(cosArg), Dec.one) > 0) cosArg = Dec.isNegative(cosArg) ? Dec.fromInt(-1) : Dec.one;
    final theta = _div(Transcendental.acosRad(cosArg, prec: _p), _three);
    final twoPiOver3 = _div(_mul(Dec.two, MathConstants.pi(_p)), _three);
    final roots = <CalcValue>[
      for (var k = 0; k < 3; k++)
        realRoot(
          _mul(
            _mul(Dec.two, m),
            Transcendental.cos(_sub(theta, _mul(Dec.fromInt(k), twoPiOver3)), AngleUnit.rad, prec: _p).value,
          ),
        ),
    ];
    return PolynomialSolution(_sorted(roots));
  }

  static Decimal _asDecimal(CalcValue v) => switch (v) {
        RationalVal(:final value) => Dec.fromRational(value),
        DecimalVal(:final value) => value,
        _ => Dec.zero,
      };

  static List<CalcValue> _sorted(List<CalcValue> roots) =>
      roots..sort((x, y) => Dec.compare(_asDecimal(x), _asDecimal(y)));

  static Rational _evalExact(List<Rational> c, Rational x) {
    var acc = Rational.zero;
    for (final k in c) {
      acc = acc * x + k;
    }
    return acc;
  }

  /// Simple fraction closest to [x] (continued fractions), or `null`.
  static Rational? _reconstruct(Decimal x) {
    final value = Dec.toRational(Dec.round(x, WORK_PREC));
    if (value == null) return null;
    final limit = BigInt.from(10).pow(12);
    var h0 = BigInt.zero, h1 = BigInt.one, k0 = BigInt.one, k1 = BigInt.zero;
    var rest = value;
    for (var i = 0; i < 64; i++) {
      final whole = rest.floor();
      final h2 = whole * h1 + h0, k2 = whole * k1 + k0;
      if (k2 > limit) break;
      h0 = h1;
      h1 = h2;
      k0 = k1;
      k1 = k2;
      final frac = rest - Rational(whole);
      final candidate = Rational(h1, k1);
      final error = Dec.fromRational(candidate - value, 20);
      if (Dec.isZero(error) || Dec.adjExp(error) < Dec.adjExp(Dec.max(Dec.abs(x), Dec.one)) - 40) return candidate;
      if (frac.numerator == BigInt.zero) return candidate;
      rest = frac.inverse;
    }
    return null;
  }
}

/// Dense matrix arithmetic for shapes up to 4 x 4.
abstract final class MatrixOps {
  static const int maxDimension = 4;
  static const int _p = WORK_PREC + 8;

  /// Validates the shape of [grid] and wraps it.
  static MatrixVal of(List<List<Decimal>> grid) {
    if (grid.isEmpty || grid.length > maxDimension) {
      throw const DimensionError('A matrix has 1 to 4 rows');
    }
    final cols = grid.first.length;
    if (cols == 0 || cols > maxDimension || grid.any((row) => row.length != cols)) {
      throw const DimensionError('A matrix has 1 to 4 columns of equal length');
    }
    return MatrixVal(List<List<Decimal>>.unmodifiable(<List<Decimal>>[
      for (final row in grid) List<Decimal>.unmodifiable(row),
    ]));
  }

  static MatrixVal _build(int rows, int cols, Decimal Function(int r, int c) entry) => MatrixVal(
        List<List<Decimal>>.unmodifiable(<List<Decimal>>[
          for (var r = 0; r < rows; r++)
            List<Decimal>.unmodifiable(<Decimal>[for (var c = 0; c < cols; c++) entry(r, c)]),
        ]),
      );

  static Decimal _maxAbs(MatrixVal a) {
    var best = Dec.zero;
    for (final row in a.grid) {
      for (final v in row) {
        best = Dec.max(best, Dec.abs(v));
      }
    }
    return best;
  }

  /// Rounds to working precision and clears cancellation noise.
  static MatrixVal _clean(MatrixVal a, [Decimal? scale]) {
    final reference = scale ?? _maxAbs(a);
    return _build(a.rows, a.cols, (r, c) {
      final v = a.grid[r][c];
      if (!Dec.isZero(v) && !Dec.isZero(reference) && Dec.adjExp(v) < Dec.adjExp(reference) - 40) return Dec.zero;
      return Dec.round(v, WORK_PREC);
    });
  }

  static void _sameShape(MatrixVal a, MatrixVal b) {
    if (a.rows != b.rows || a.cols != b.cols) {
      throw DimensionError('Shapes ${a.rows}×${a.cols} and ${b.rows}×${b.cols} do not match');
    }
  }

  static void _square(MatrixVal a, String what) {
    if (!a.isSquare) throw DimensionError('$what needs a square matrix');
  }

  static MatrixVal identity(int n) => _build(n, n, (r, c) => r == c ? Dec.one : Dec.zero);

  static MatrixVal add(MatrixVal a, MatrixVal b) {
    _sameShape(a, b);
    return _clean(_build(a.rows, a.cols, (r, c) => Dec.add(a.grid[r][c], b.grid[r][c], _p)), Dec.max(_maxAbs(a), _maxAbs(b)));
  }

  static MatrixVal sub(MatrixVal a, MatrixVal b) {
    _sameShape(a, b);
    return _clean(_build(a.rows, a.cols, (r, c) => Dec.sub(a.grid[r][c], b.grid[r][c], _p)), Dec.max(_maxAbs(a), _maxAbs(b)));
  }

  static MatrixVal scale(MatrixVal a, Decimal k) => _build(a.rows, a.cols, (r, c) => Dec.mul(a.grid[r][c], k));

  static MatrixVal mul(MatrixVal a, MatrixVal b) {
    if (a.cols != b.rows) {
      throw DimensionError('Cannot multiply ${a.rows}×${a.cols} by ${b.rows}×${b.cols}');
    }
    final product = _build(a.rows, b.cols, (r, c) {
      var sum = Dec.zero;
      for (var k = 0; k < a.cols; k++) {
        sum = Dec.add(sum, Dec.mul(a.grid[r][k], b.grid[k][c], _p), _p);
      }
      return sum;
    });
    return _clean(product, Dec.mul(_maxAbs(a), _maxAbs(b)));
  }

  static MatrixVal transpose(MatrixVal a) => _build(a.cols, a.rows, (r, c) => a.grid[c][r]);

  static Decimal trace(MatrixVal a) {
    _square(a, 'The trace');
    var sum = Dec.zero;
    for (var i = 0; i < a.rows; i++) {
      sum = Dec.add(sum, a.grid[i][i]);
    }
    return sum;
  }

  static Decimal _det(List<List<Decimal>> g, List<int> rows, List<int> cols) {
    final n = rows.length;
    if (n == 1) return g[rows[0]][cols[0]];
    if (n == 2) {
      return Dec.sub(
        Dec.mul(g[rows[0]][cols[0]], g[rows[1]][cols[1]], _p),
        Dec.mul(g[rows[0]][cols[1]], g[rows[1]][cols[0]], _p),
        _p,
      );
    }
    final rest = rows.sublist(1);
    var sum = Dec.zero;
    for (var j = 0; j < n; j++) {
      final entry = g[rows[0]][cols[j]];
      if (Dec.isZero(entry)) continue;
      final minor = _det(g, rest, <int>[...cols.sublist(0, j), ...cols.sublist(j + 1)]);
      final term = Dec.mul(entry, minor, _p);
      sum = j.isEven ? Dec.add(sum, term, _p) : Dec.sub(sum, term, _p);
    }
    return sum;
  }

  /// Hadamard-style magnitude bound used to recognise a vanishing determinant.
  static Decimal _detScale(MatrixVal a) {
    var scale = Dec.one;
    for (final row in a.grid) {
      var best = Dec.zero;
      for (final v in row) {
        best = Dec.max(best, Dec.abs(v));
      }
      scale = Dec.mul(scale, best, 20);
    }
    return scale;
  }

  /// Determinant by cofactor expansion (division free, hence exact for
  /// exactly representable entries).
  static Decimal determinant(MatrixVal a) {
    _square(a, 'The determinant');
    final index = <int>[for (var i = 0; i < a.rows; i++) i];
    final det = _det(a.grid, index, index);
    final scale = _detScale(a);
    if (!Dec.isZero(det) && !Dec.isZero(scale) && Dec.adjExp(det) < Dec.adjExp(scale) - 40) return Dec.zero;
    return Dec.round(det, WORK_PREC);
  }

  /// Inverse through the adjugate.
  static MatrixVal inverse(MatrixVal a) {
    _square(a, 'The inverse');
    final n = a.rows;
    final det = determinant(a);
    if (Dec.isZero(det)) throw const DomainError('The matrix is singular');
    if (n == 1) return _build(1, 1, (r, c) => Dec.div(Dec.one, det));
    final all = <int>[for (var i = 0; i < n; i++) i];
    List<int> without(int k) => <int>[...all.sublist(0, k), ...all.sublist(k + 1)];
    final result = _build(n, n, (r, c) {
      // adjugate(r, c) = cofactor(c, r)
      final minor = _det(a.grid, without(c), without(r));
      final cofactor = (r + c).isEven ? minor : Dec.neg(minor);
      return Dec.div(cofactor, det, _p);
    });
    return _clean(result);
  }

  /// `a^n` for an integer `n` (negative powers invert first).
  static MatrixVal power(MatrixVal a, int n) {
    _square(a, 'A matrix power');
    if (n < 0) return power(inverse(a), -n);
    if (n > 4096) throw const OverflowError();
    var result = identity(a.rows);
    var base = a;
    var e = n;
    while (e > 0) {
      if (e & 1 == 1) result = mul(result, base);
      e >>= 1;
      if (e > 0) base = mul(base, base);
    }
    return result;
  }

  /// Rank by Gaussian elimination with partial pivoting.
  static int rank(MatrixVal a) {
    final g = <List<Decimal>>[for (final row in a.grid) <Decimal>[...row]];
    final scale = _maxAbs(a);
    if (Dec.isZero(scale)) return 0;
    bool negligible(Decimal v) => Dec.isZero(v) || Dec.adjExp(v) < Dec.adjExp(scale) - 40;
    var rank = 0;
    for (var col = 0; col < a.cols && rank < a.rows; col++) {
      var pivot = rank;
      for (var r = rank + 1; r < a.rows; r++) {
        if (Dec.compare(Dec.abs(g[r][col]), Dec.abs(g[pivot][col])) > 0) pivot = r;
      }
      if (negligible(g[pivot][col])) continue;
      final swap = g[rank];
      g[rank] = g[pivot];
      g[pivot] = swap;
      for (var r = rank + 1; r < a.rows; r++) {
        final factor = Dec.div(g[r][col], g[rank][col], _p);
        for (var c = col; c < a.cols; c++) {
          final v = Dec.sub(g[r][c], Dec.mul(factor, g[rank][c], _p), _p);
          g[r][c] = negligible(v) ? Dec.zero : v;
        }
      }
      rank++;
    }
    return rank;
  }

  /// Solution of `a x = b` for a square, regular `a`.
  static List<Decimal> solve(MatrixVal a, List<Decimal> b) {
    _square(a, 'A linear system');
    if (b.length != a.rows) throw const DimensionError('The right-hand side has the wrong length');
    final x = mul(inverse(a), _build(b.length, 1, (r, c) => b[r]));
    return <Decimal>[for (final row in x.grid) row[0]];
  }
}

/// Operations on 2D / 3D vectors.
abstract final class VectorOps {
  static const int _p = WORK_PREC + 8;

  static void _sameLength(List<Decimal> a, List<Decimal> b) {
    if (a.length != b.length || a.isEmpty) throw const DimensionError('The vectors must have the same length');
  }

  static Decimal dot(List<Decimal> a, List<Decimal> b) {
    _sameLength(a, b);
    var sum = Dec.zero;
    for (var i = 0; i < a.length; i++) {
      sum = Dec.add(sum, Dec.mul(a[i], b[i], _p), _p);
    }
    return Dec.round(sum, WORK_PREC);
  }

  /// Cross product of two 3D vectors.
  static List<Decimal> cross(List<Decimal> a, List<Decimal> b) {
    if (a.length != 3 || b.length != 3) throw const DimensionError('The cross product needs 3D vectors');
    Decimal minor(int i, int j) =>
        Dec.round(Dec.sub(Dec.mul(a[i], b[j], _p), Dec.mul(a[j], b[i], _p), _p), WORK_PREC);
    return <Decimal>[minor(1, 2), minor(2, 0), minor(0, 1)];
  }

  static Decimal norm(List<Decimal> a) => Dec.sqrt(dot(a, a));

  /// Angle between two vectors, in radians.
  static Decimal angle(List<Decimal> a, List<Decimal> b) {
    final na = norm(a), nb = norm(b);
    if (Dec.isZero(na) || Dec.isZero(nb)) throw const DomainError('The zero vector has no direction');
    var c = Dec.div(dot(a, b), Dec.mul(na, nb, _p), _p);
    if (Dec.compare(Dec.abs(c), Dec.one) > 0) c = Dec.isNegative(c) ? Dec.fromInt(-1) : Dec.one;
    return Transcendental.acosRad(c);
  }

  static List<Decimal> unit(List<Decimal> a) {
    final n = norm(a);
    if (Dec.isZero(n)) throw const DomainError('The zero vector has no direction');
    return <Decimal>[for (final v in a) Dec.div(v, n)];
  }
}
