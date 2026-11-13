import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../../core/constants/math_constants.dart';
import '../models/calc_error.dart';
import '../models/calc_value.dart';
import 'cancellation_token.dart';
import 'decimal_math.dart';
import 'number_formatter.dart';
import 'transcendental_engine.dart';

/// Outcome of a factorial evaluation.
final class FactorialResult {
  const FactorialResult(this.value, {this.display, this.uncertainty});

  final CalcValue value;

  /// Set for log-Stirling results: `"4.2285779266 × 10^16325"`.
  final String? display;

  /// Set for Spouge results: how far [value] may be off - one unit of the
  /// last digit it is kept to.
  final Decimal? uncertainty;
}

/// Gamma function, factorials and counting functions.
abstract final class GammaCombinatorics {
  /// Spouge parameter `a`.
  static const int spougeA = 22;

  /// Largest integer whose factorial is multiplied out exactly.
  static const int exactFactorialLimit = 2500;

  /// Significant digits kept from a Spouge evaluation.
  static const int gammaDigits = 15;

  /// The 21 Spouge coefficients `c_1 .. c_21`
  /// (`c_k = (-1)^(k-1)/(k-1)! * (a-k)^(k-1/2) * e^(a-k)`), computed once per
  /// isolate.
  // ignore: non_constant_identifier_names
  static final List<Decimal> SPOUGE_COEFFS = _spougeCoefficients();

  static final Decimal _sqrtTwoPi = Dec.sqrt(Dec.mul(MathConstants.pi(70), Dec.two, 70), 66);

  static List<Decimal> _spougeCoefficients() {
    final out = <Decimal>[];
    var factorial = BigInt.one; // (k-1)!
    for (var k = 1; k < spougeA; k++) {
      if (k > 2) factorial *= BigInt.from(k - 1);
      final base = Dec.fromInt(spougeA - k);
      // (a-k)^(k-1/2) = (a-k)^k / sqrt(a-k)
      final power = Dec.div(Dec.powInt(base, k, prec: 70), Dec.sqrt(base, 70), 70);
      var c = Dec.div(Dec.mul(power, Transcendental.exp(base, prec: 66), 70), Dec.fromBigInt(factorial), 66);
      if (k.isEven) c = Dec.neg(c);
      out.add(c);
    }
    return List<Decimal>.unmodifiable(out);
  }

  /// Forces the lazily initialised tables (called when a worker isolate boots).
  static void warmUp() {
    SPOUGE_COEFFS.length;
    _sqrtTwoPi.hashCode;
  }

  /// `Gamma(z)` for real `z` by Spouge's approximation (about 18 good digits).
  static Decimal spougeGamma(Decimal z, {CancellationToken? token}) {
    if (Dec.isInteger(z) && Dec.sign(z) <= 0) {
      throw const DomainError('Gamma is undefined at zero and negative integers');
    }
    if (Dec.compare(z, Dec.half) < 0) {
      // Reflection: Gamma(z) = pi / (sin(pi z) Gamma(1 - z)).
      final pi = MathConstants.pi(60);
      final sinPiZ = Transcendental.sinCosRad(Dec.mul(pi, z, 60), prec: 40, token: token).sin;
      final mirror = spougeGamma(Dec.sub(Dec.one, z, 1000), token: token);
      return Dec.div(pi, Dec.mul(sinPiZ, mirror, 40), 30);
    }
    final w = Dec.sub(z, Dec.one, 1000); // Gamma(z) = Gamma(w + 1)
    final wa = Dec.add(w, Dec.fromInt(spougeA), 1000);
    var sum = _sqrtTwoPi; // c_0
    for (var k = 1; k < spougeA; k++) {
      token?.tick();
      sum = Dec.add(sum, Dec.div(SPOUGE_COEFFS[k - 1], Dec.add(w, Dec.fromInt(k), 1000), 60), 60);
    }
    // (w+a)^(w+1/2) e^-(w+a) = exp((w + 1/2) ln(w + a) - (w + a))
    final lnWa = Transcendental.ln(wa, prec: 60, token: token);
    final t = Dec.sub(Dec.mul(Dec.add(w, Dec.half, 1000), lnWa, 66), wa, 66);
    return Dec.mul(Transcendental.exp(t, prec: 40, token: token), sum, 40);
  }

  /// Spouge's approximation, kept to [gammaDigits] digits.
  static FactorialResult _spouge(Decimal z, CancellationToken? token) {
    final value = Dec.round(spougeGamma(z, token: token), gammaDigits);
    return FactorialResult(
      DecimalVal(value),
      uncertainty: Dec.isZero(value) ? null : Dec.compose(BigInt.one, Dec.adjExp(value) - gammaDigits + 1),
    );
  }

  /// `Gamma(x)` as a calculator value.
  static FactorialResult gamma(CalcValue x, {CancellationToken? token}) {
    final n = _integerOf(x);
    if (n != null) {
      if (n.sign <= 0) throw const DomainError('Gamma is undefined at zero and negative integers');
      return factorial(Values.ofBigInt(n - BigInt.one), token: token);
    }
    return _spouge(x.asDecimal, token);
  }

  /// `x!` routed as demanded by the blueprint:
  ///
  ///  * integer `0 <= n <= 2500`: exact `BigInt` product,
  ///  * integer `n > 2500`: logarithmic Stirling series,
  ///  * non-integer `x`: `spougeGamma(x + 1)` rounded to 15 digits.
  static FactorialResult factorial(CalcValue x, {CancellationToken? token}) {
    if (x is ComplexVal) throw const UnsupportedOperationError('Factorial of a complex number');
    if (x is MatrixVal) throw const DimensionError('Factorial of a matrix');
    final n = _integerOf(x);
    if (n != null) return _integerFactorial(n, token);
    return _spouge(Dec.add(x.asDecimal, Dec.one, 1000), token);
  }

  static FactorialResult _integerFactorial(BigInt n, CancellationToken? token) {
    if (n.isNegative) throw const DomainError('Factorial of a negative integer');
    if (n > BigInt.from(exactFactorialLimit)) return _stirling(n, token);
    final limit = n.toInt();
    var acc = BigInt.one;
    for (var i = 2; i <= limit; i++) {
      token?.tick();
      acc *= BigInt.from(i);
    }
    return FactorialResult(rationalOrDecimal(Rational(acc)));
  }

  // B_2k / (2k (2k - 1)) for k = 1..8.
  static const List<int> _stirlingNum = <int>[1, -1, 1, -1, 1, -691, 1, -3617];
  static const List<int> _stirlingDen = <int>[12, 360, 1260, 1680, 1188, 360360, 156, 122400];

  /// `ln(n!) = n ln n - n + ln(2 pi n)/2 + 1/(12n) - 1/(360n^3) + ...`
  ///
  /// The blueprint lists the first two correction terms; six more are added
  /// so the stored value is good to all 50 working digits and follow-up
  /// arithmetic (`5000!/4999!`) stays clean.
  static FactorialResult _stirling(BigInt n, CancellationToken? token) {
    if (n.bitLength > 40) throw const OverflowError();
    const p = 72;
    final nd = Dec.fromBigInt(n);
    final lnN = Transcendental.ln(nd, prec: p, token: token);
    var s = Dec.sub(Dec.mul(nd, lnN, p), nd, p);
    final twoPiN = Dec.mul(Dec.mul(MathConstants.pi(p), Dec.two, p), nd, p);
    s = Dec.add(s, Dec.mul(Transcendental.ln(twoPiN, prec: p, token: token), Dec.half, p), p);
    final n2 = Dec.mul(nd, nd, p);
    var power = nd; // n^(2k-1)
    for (var k = 0; k < _stirlingNum.length; k++) {
      token?.tick();
      s = Dec.add(s, Dec.div(Dec.fromInt(_stirlingNum[k]), Dec.mul(Dec.fromInt(_stirlingDen[k]), power, p), p), p);
      power = Dec.mul(power, n2, p);
    }
    // log10(n!) = E + f  =>  n! = 10^f x 10^E
    final log10 = Dec.div(s, MathConstants.ln10(p + 4), p);
    final whole = Dec.floor(log10);
    final exponent = Dec.toSmallInt(whole);
    if (exponent == null || exponent > kMaxExponent) throw const OverflowError();
    final frac = Dec.sub(log10, whole, p);
    final mantissa = Transcendental.exp(Dec.mul(frac, MathConstants.ln10(p), p), prec: WORK_PREC + 4, token: token);
    final value = Dec.round(Dec.mul(mantissa, Dec.compose(BigInt.one, exponent), WORK_PREC + 4), WORK_PREC);
    return FactorialResult(DecimalVal(value), display: giantDisplay(value));
  }

  /// `"${10^f} × 10^$E"` with an 11-digit mantissa.
  static String giantDisplay(Decimal value) {
    final shown = Dec.round(value, 11);
    final p = Dec.parts(shown);
    final adj = Dec.adjExp(shown);
    return '${NumberFormatter.formatDec(Dec.compose(p.m, p.e - adj), prec: 11)} × 10^$adj';
  }

  /// Binomial coefficient `n choose r` for non-negative integers.
  static CalcValue nCr(CalcValue n, CalcValue r, {CancellationToken? token}) {
    final (nn, rr) = _countingArgs(n, r, 'nCr');
    if (rr > nn) return Values.zero;
    final k = rr < nn - rr ? rr : nn - rr;
    if (k.bitLength > 30) throw const OverflowError();
    final steps = k.toInt();
    var acc = BigInt.one;
    final base = nn - k;
    for (var i = 1; i <= steps; i++) {
      token?.tick();
      acc = acc * (base + BigInt.from(i)) ~/ BigInt.from(i);
    }
    return rationalOrDecimal(Rational(acc));
  }

  /// Number of `r`-permutations of `n` items.
  static CalcValue nPr(CalcValue n, CalcValue r, {CancellationToken? token}) {
    final (nn, rr) = _countingArgs(n, r, 'nPr');
    if (rr > nn) return Values.zero;
    if (rr.bitLength > 30) throw const OverflowError();
    final steps = rr.toInt();
    var acc = BigInt.one;
    for (var i = 0; i < steps; i++) {
      token?.tick();
      acc *= nn - BigInt.from(i);
    }
    return rationalOrDecimal(Rational(acc));
  }

  static (BigInt, BigInt) _countingArgs(CalcValue n, CalcValue r, String name) {
    final nn = _integerOf(n), rr = _integerOf(r);
    if (nn == null || rr == null || nn.isNegative || rr.isNegative) {
      throw DomainError('$name needs non-negative integers');
    }
    return (nn, rr);
  }

  /// The integer held by [v], or `null` when it is not a whole real number.
  static BigInt? _integerOf(CalcValue v) {
    switch (v) {
      case RationalVal(:final value):
        return value.denominator == BigInt.one ? value.numerator : null;
      case DecimalVal(:final value):
        if (!Dec.isInteger(value)) return null;
        if (Dec.adjExp(value) > 18) throw const OverflowError();
        return Dec.toBigInt(value);
      case BitwiseVal(:final numericValue):
        return numericValue;
      case ComplexVal() || MatrixVal():
        return null;
    }
  }
}
