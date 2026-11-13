import 'package:decimal/decimal.dart';

import '../../core/constants/math_constants.dart';
import '../models/calc_error.dart';
import '../models/math_context.dart';
import 'cancellation_token.dart';
import 'decimal_math.dart';

/// Result of a trigonometric evaluation.
final class TrigValue {
  const TrigValue(this.value, {this.exact = false});

  final Decimal value;

  /// True when [value] is an exact cardinal value (0, ±1/2, ±1).
  final bool exact;
}

/// 50-digit elementary functions.
///
/// Series are summed in `BigInt` fixed point with [kGuardDigits] spare digits
/// and stop as soon as a term drops below the fixed-point resolution
/// (far below the `10^-50` bound of the blueprint).
abstract final class Transcendental {
  static final BigInt _i0 = BigInt.zero;
  static final BigInt _i1 = BigInt.one;
  static final BigInt _i2 = BigInt.two;
  static final BigInt _i4 = BigInt.from(4);

  /// Components smaller than `10^-42` produced by a reduction are noise.
  static const int zeroSnapExponent = -42;

  static final Decimal _c07 = Dec.parse('0.7');
  static final Decimal _c14 = Dec.parse('1.4');
  static final Decimal _c01 = Dec.parse('0.1');
  static final Decimal _c03 = Dec.parse('0.3');
  static final Decimal _c05 = Dec.parse('0.5');
  static final Decimal _c078 = Dec.parse('0.78');
  static final Decimal _d9over10 = Dec.parse('0.9');
  static final Decimal _d90 = Dec.fromInt(90);
  static final Decimal _d180 = Dec.fromInt(180);
  static final Decimal _d200 = Dec.fromInt(200);
  static final Decimal _d360 = Dec.fromInt(360);
  static final Decimal _d400 = Dec.fromInt(400);

  /// Snaps reduction noise to an exact zero.
  static Decimal snap(Decimal v) => !Dec.isZero(v) && Dec.adjExp(v) < zeroSnapExponent ? Dec.zero : v;

  // ---------------------------------------------------------------- exp / ln

  /// `e^x`: `x = k ln2 + r`, Taylor series in `r`, then `x 2^k`.
  static Decimal exp(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.one;
    final ax = Dec.adjExp(x);
    if (ax >= 7) {
      // |x| >= 1e7 is far beyond kMaxExponent * ln 10.
      if (Dec.isNegative(x)) return Dec.zero;
      throw const OverflowError();
    }
    final wp = prec + kGuardDigits;
    if (ax < -(wp + 2)) return Dec.add(Dec.one, x, prec);
    final s = wp + 8;
    final scale = Dec.pow10(s);
    final xf = Dec.toFixed(x, s);
    final ln2f = Dec.toFixed(MathConstants.ln2x100, s);
    // k = round(x / ln 2) with floor semantics for negative arguments.
    final twice = xf * _i2 + ln2f, den = ln2f * _i2;
    final k = ((twice - twice % den) ~/ den).toInt();
    final rf = xf - BigInt.from(k) * ln2f;
    var sum = scale;
    var term = scale;
    for (var n = 1;; n++) {
      token?.tick();
      term = (term * rf) ~/ (scale * BigInt.from(n));
      if (term == _i0) break;
      sum += term;
    }
    var result = Dec.fromFixed(sum, s);
    if (k != 0) {
      final tenExp = (k * 30103) ~/ 100000;
      if (tenExp > kMaxExponent + 2) throw const OverflowError();
      if (tenExp < -(kMaxExponent + 2)) return Dec.zero;
      result = Dec.mul(result, Dec.powInt(Dec.two, k, prec: wp, token: token), wp);
    }
    final out = Dec.round(result, prec);
    final ox = Dec.adjExp(out);
    if (ox > kMaxExponent) throw const OverflowError();
    if (ox < -kMaxExponent) return Dec.zero;
    return out;
  }

  /// `atanh(y) = y (1 + y^2/3 + y^4/5 + ...)` for `|y| <= 0.2`.
  static Decimal _atanhSeries(Decimal y, int wp, CancellationToken? token) {
    final s = wp + 6;
    final scale = Dec.pow10(s);
    final y2 = Dec.toFixed(Dec.mul(y, y, s), s);
    var sum = scale;
    var power = scale;
    for (var k = 1;; k++) {
      token?.tick();
      power = (power * y2) ~/ scale;
      if (power == _i0) break;
      sum += power ~/ BigInt.from(2 * k + 1);
    }
    return Dec.mul(y, Dec.fromFixed(sum, s), wp);
  }

  /// Natural logarithm: `x = m 10^p`, `m` halved `k2` times into `[0.7, 1.4]`,
  /// `ln m = 2 atanh((m-1)/(m+1))`, result `= ln m + k2 ln2 + p ln10`.
  ///
  /// (The blueprint quotes `[0.7, 1.35]`; that window is narrower than a
  /// factor of two and would never capture e.g. `m = 1.38`, hence `1.4`.)
  static Decimal ln(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final sgn = Dec.sign(x);
    if (sgn == 0) throw const DomainError('Logarithm of zero is undefined');
    if (sgn < 0) throw const DomainError('Logarithm of a negative number');
    final wp = prec + kGuardDigits;
    if (Dec.compare(x, _c07) >= 0 && Dec.compare(x, _c14) <= 0) {
      // Close to 1: no additive constants, therefore no cancellation.
      final num = Dec.sub(x, Dec.one, 1000);
      if (Dec.isZero(num)) return Dec.zero;
      final y = Dec.div(num, Dec.add(x, Dec.one, 1000), wp);
      return Dec.round(Dec.mul(Dec.two, _atanhSeries(y, wp, token), wp), prec);
    }
    final p = Dec.parts(x);
    final n = Dec.digitCount(p.m);
    var m = Dec.compose(p.m, 1 - n); // [1, 10)
    final p10 = n - 1 + p.e;
    var k2 = 0;
    while (Dec.compare(m, _c14) > 0) {
      m = Dec.mul(m, Dec.half, 1000);
      k2++;
    }
    final y = Dec.div(Dec.sub(m, Dec.one, 1000), Dec.add(m, Dec.one, 1000), wp);
    final cw = wp + 8;
    var r = Dec.mul(Dec.two, _atanhSeries(y, wp, token), wp);
    if (k2 != 0) r = Dec.add(r, Dec.mul(Dec.fromInt(k2), MathConstants.ln2(cw), cw), cw);
    if (p10 != 0) r = Dec.add(r, Dec.mul(Dec.fromInt(p10), MathConstants.ln10(cw), cw), cw);
    return Dec.round(r, prec);
  }

  /// `ln(1 + x)` without cancellation for small `x`.
  static Decimal ln1p(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.zero;
    if (Dec.compare(Dec.abs(x), _c03) <= 0) {
      final wp = prec + kGuardDigits;
      final y = Dec.div(x, Dec.add(Dec.two, x, 1000), wp);
      return Dec.round(Dec.mul(Dec.two, _atanhSeries(y, wp, token), wp), prec);
    }
    return ln(Dec.add(Dec.one, x, 1000), prec: prec, token: token);
  }

  static Decimal log10(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final p = Dec.parts(x);
    if (p.m == _i1) return Dec.fromInt(p.e); // exact power of ten
    final wp = prec + 6;
    return Dec.div(ln(x, prec: wp, token: token), MathConstants.ln10(wp + 4), prec);
  }

  static Decimal log2(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final p = Dec.parts(x);
    if (p.e >= 0 && p.e < 400 && !p.m.isNegative && p.m != _i0) {
      final v = p.m * Dec.pow10(p.e);
      if (v & (v - _i1) == _i0) return Dec.fromInt(v.bitLength - 1); // exact power of two
    }
    final wp = prec + 6;
    return Dec.div(ln(x, prec: wp, token: token), MathConstants.ln2(wp + 4), prec);
  }

  /// `x^y` for a positive real base.
  static Decimal pow(Decimal x, Decimal y, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.sign(x) <= 0) throw const DomainError('Power of a non-positive base');
    if (Dec.isZero(y) || Dec.equal(x, Dec.one)) return Dec.one;
    final rough = ln(x, prec: 12, token: token);
    if (Dec.isZero(rough)) return Dec.one;
    final intDigits = Dec.adjExp(y) + Dec.adjExp(rough) + 2;
    if (intDigits > 8) {
      final positive = Dec.sign(y) == Dec.sign(rough);
      if (positive) throw const OverflowError();
      return Dec.zero;
    }
    final lp = prec + kGuardDigits + 4 + (intDigits > 0 ? intDigits : 0);
    final t = Dec.mul(y, ln(x, prec: lp, token: token), lp);
    return exp(t, prec: prec, token: token);
  }

  // ------------------------------------------------------------ trig kernels

  static Decimal _sinKernel(Decimal r, int wp, CancellationToken? token) {
    if (Dec.isZero(r)) return Dec.zero;
    final s = wp + 6;
    final scale = Dec.pow10(s);
    final r2 = Dec.toFixed(Dec.mul(r, r, s), s);
    var sum = scale;
    var term = scale;
    for (var k = 1;; k++) {
      token?.tick();
      term = -(term * r2) ~/ (scale * BigInt.from(2 * k * (2 * k + 1)));
      if (term == _i0) break;
      sum += term;
    }
    return Dec.mul(r, Dec.fromFixed(sum, s), wp);
  }

  static Decimal _cosKernel(Decimal r, int wp, CancellationToken? token) {
    if (Dec.isZero(r)) return Dec.one;
    final s = wp + 6;
    final scale = Dec.pow10(s);
    final r2 = Dec.toFixed(Dec.mul(r, r, s), s);
    var sum = scale;
    var term = scale;
    for (var k = 1;; k++) {
      token?.tick();
      term = -(term * r2) ~/ (scale * BigInt.from((2 * k - 1) * 2 * k));
      if (term == _i0) break;
      sum += term;
    }
    return Dec.round(Dec.fromFixed(sum, s), wp);
  }

  /// Large-angle reduction against the stored 100-digit pi.
  ///
  /// The fixed-point resolution grows with the magnitude of [x]
  /// (`wp + exponent + 3` decimals, capped at the 98 reliable digits) so that
  /// e.g. `sin(10^20)` keeps its full phase accuracy. Beyond the cap the
  /// number of trustworthy digits shrinks and is reported in `digits`.
  static ({Decimal r, int quadrant, int digits}) _reduceRadians(Decimal x, int wp) {
    if (Dec.compare(Dec.abs(x), _c078) <= 0) return (r: x, quadrant: 0, digits: wp);
    final ax = Dec.adjExp(x);
    final a = ax < 0 ? 0 : ax;
    var f = wp + a + 3;
    var digits = wp;
    if (f > MathConstants.reliableDigits) {
      f = MathConstants.reliableDigits;
      digits = f - a - 3;
    }
    if (digits < 1) throw const DomainError('Angle is too large to be reduced accurately');
    final xf = Dec.toFixed(x, f);
    final halfPi = Dec.toFixed(MathConstants.pi100, f) ~/ _i2;
    var q = (xf * _i2 + halfPi) ~/ (halfPi * _i2);
    var rf = xf - q * halfPi;
    final quarter = halfPi >> 1;
    if (rf > quarter) {
      rf -= halfPi;
      q += _i1;
    } else if (rf < -quarter) {
      rf += halfPi;
      q -= _i1;
    }
    return (r: Dec.fromFixed(rf, f), quadrant: (q % _i4).toInt(), digits: digits);
  }

  /// `(sin x, cos x)` for an angle in radians.
  static ({Decimal sin, Decimal cos}) sinCosRad(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final wp = prec + kGuardDigits;
    final red = _reduceRadians(x, wp);
    final s = _sinKernel(red.r, wp, token);
    final c = _cosKernel(red.r, wp, token);
    final reduced = !identical(red.r, x);
    final outPrec = red.digits < prec ? red.digits : prec;
    Decimal fin(Decimal v) {
      final r = Dec.round(v, outPrec);
      return reduced ? snap(r) : r;
    }

    return switch (red.quadrant) {
      0 => (sin: fin(s), cos: fin(c)),
      1 => (sin: fin(c), cos: fin(Dec.neg(s))),
      2 => (sin: fin(Dec.neg(s)), cos: fin(Dec.neg(c))),
      _ => (sin: fin(Dec.neg(c)), cos: fin(s)),
    };
  }

  /// Degrees (or gradians) reduced to `[0, 360)` degrees, exactly.
  static Decimal _normalisedDegrees(Decimal x, AngleUnit unit) {
    if (unit == AngleUnit.grad) return Dec.mul(Dec.mod(x, _d400), _d9over10, 1000);
    return Dec.mod(x, _d360);
  }

  /// `(sin, cos)` of an exact degree angle in `[0, 360)`, plus the cardinal
  /// index (`theta / 15`) when the angle is a multiple of 15 degrees.
  static ({Decimal sin, Decimal cos, int? cardinal}) _sinCosDegrees(Decimal theta, int prec, CancellationToken? token) {
    final wp = prec + kGuardDigits;
    final whole = Dec.toSmallInt(theta);
    final cardinal = whole != null && whole % 15 == 0 ? whole ~/ 15 : null;
    // nearest multiple of 90 degrees
    final q = Dec.toBigInt(Dec.roundToPlaces(Dec.div(theta, _d90, 20))).toInt();
    final d = Dec.sub(theta, Dec.fromInt(90 * q), 1000); // [-45, 45], exact
    final r = Dec.div(Dec.mul(d, MathConstants.pi(wp + 4), wp + 4), _d180, wp + 2);
    final s = _sinKernel(r, wp, token);
    final c = _cosKernel(r, wp, token);
    Decimal fin(Decimal v) => Dec.round(v, prec);
    return switch (q % 4) {
      0 => (sin: fin(s), cos: fin(c), cardinal: cardinal),
      1 => (sin: fin(c), cos: fin(Dec.neg(s)), cardinal: cardinal),
      2 => (sin: fin(Dec.neg(s)), cos: fin(Dec.neg(c)), cardinal: cardinal),
      _ => (sin: fin(Dec.neg(c)), cos: fin(s), cardinal: cardinal),
    };
  }

  static final Decimal _minusHalf = Dec.parse('-0.5');
  static final Decimal _minusOne = Dec.fromInt(-1);

  /// Exact sine of `15 k` degrees, when it is rational.
  static Decimal? _cardinalSin(int k) => switch (k % 24) {
        0 || 12 => Dec.zero,
        2 || 10 => Dec.half,
        6 => Dec.one,
        14 || 22 => _minusHalf,
        18 => _minusOne,
        _ => null,
      };

  /// Sine of an angle given in [unit].
  static TrigValue sin(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) {
    if (unit == AngleUnit.rad) return TrigValue(sinCosRad(x, prec: prec, token: token).sin);
    final sc = _sinCosDegrees(_normalisedDegrees(x, unit), prec, token);
    final exact = sc.cardinal == null ? null : _cardinalSin(sc.cardinal!);
    return exact != null ? TrigValue(exact, exact: true) : TrigValue(sc.sin);
  }

  /// Cosine of an angle given in [unit].
  static TrigValue cos(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) {
    if (unit == AngleUnit.rad) return TrigValue(sinCosRad(x, prec: prec, token: token).cos);
    final sc = _sinCosDegrees(_normalisedDegrees(x, unit), prec, token);
    final exact = sc.cardinal == null ? null : _cardinalSin(sc.cardinal! + 6);
    return exact != null ? TrigValue(exact, exact: true) : TrigValue(sc.cos);
  }

  /// Tangent of an angle given in [unit]; throws on the asymptotes.
  static TrigValue tan(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) {
    const asymptote = DomainError('Undefined asymptote');
    if (unit == AngleUnit.rad) {
      final sc = sinCosRad(x, prec: prec + 4, token: token);
      if (Dec.isZero(sc.cos)) throw asymptote;
      return TrigValue(Dec.div(sc.sin, sc.cos, prec));
    }
    final sc = _sinCosDegrees(_normalisedDegrees(x, unit), prec + 4, token);
    final k = sc.cardinal;
    if (k != null) {
      switch (k % 24) {
        case 0 || 12:
          return TrigValue(Dec.zero, exact: true);
        case 6 || 18:
          throw asymptote;
        case 3 || 15:
          return TrigValue(Dec.one, exact: true);
        case 9 || 21:
          return TrigValue(_minusOne, exact: true);
      }
    }
    return TrigValue(Dec.div(sc.sin, sc.cos, prec));
  }

  // --------------------------------------------------------- inverse trig

  static Decimal _atanSeries(Decimal v, int wp, CancellationToken? token) {
    if (Dec.isZero(v)) return Dec.zero;
    final s = wp + 6;
    final scale = Dec.pow10(s);
    final v2 = Dec.toFixed(Dec.mul(v, v, s), s);
    var sum = scale;
    var power = scale;
    for (var k = 1;; k++) {
      token?.tick();
      power = -(power * v2) ~/ scale;
      if (power == _i0) break;
      sum += power ~/ BigInt.from(2 * k + 1);
    }
    return Dec.mul(v, Dec.fromFixed(sum, s), wp);
  }

  /// `atan(x)` in radians.
  static Decimal atanRad(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.zero;
    final wp = prec + kGuardDigits;
    final negative = Dec.isNegative(x);
    var v = Dec.abs(x);
    final invert = Dec.compare(v, Dec.one) > 0;
    if (invert) v = Dec.div(Dec.one, v, wp);
    var doublings = 0;
    while (Dec.compare(v, _c01) > 0) {
      // atan v = 2 atan(v / (1 + sqrt(1 + v^2)))
      final root = Dec.sqrt(Dec.add(Dec.one, Dec.mul(v, v, wp), wp), wp);
      v = Dec.div(v, Dec.add(Dec.one, root, wp), wp);
      doublings++;
    }
    var r = _atanSeries(v, wp, token);
    if (doublings > 0) r = Dec.mul(r, Dec.fromInt(1 << doublings), wp);
    if (invert) r = Dec.sub(Dec.mul(MathConstants.pi(wp + 2), Dec.half, wp + 2), r, wp);
    return Dec.round(negative ? Dec.neg(r) : r, prec);
  }

  /// `asin(x)` in radians.
  static Decimal asinRad(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final c = Dec.compare(Dec.abs(x), Dec.one);
    if (c > 0) throw const DomainError('asin is only defined on [-1, 1]');
    if (c == 0) {
      final h = Dec.round(Dec.mul(MathConstants.pi(prec + 4), Dec.half, prec + 4), prec);
      return Dec.isNegative(x) ? Dec.neg(h) : h;
    }
    final wp = prec + kGuardDigits;
    final den = Dec.sqrt(Dec.mul(Dec.sub(Dec.one, x, 1000), Dec.add(Dec.one, x, 1000), wp), wp);
    return atanRad(Dec.div(x, den, wp), prec: prec, token: token);
  }

  /// `acos(x)` in radians.
  static Decimal acosRad(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final c = Dec.compare(Dec.abs(x), Dec.one);
    if (c > 0) throw const DomainError('acos is only defined on [-1, 1]');
    if (c == 0) return Dec.isNegative(x) ? MathConstants.pi(prec) : Dec.zero;
    final wp = prec + kGuardDigits;
    final ratio = Dec.div(Dec.sub(Dec.one, x, 1000), Dec.add(Dec.one, x, 1000), wp);
    final half = atanRad(Dec.sqrt(ratio, wp), prec: prec + 4, token: token);
    return Dec.round(Dec.mul(half, Dec.two, prec + 4), prec);
  }

  /// Converts a radian result into [unit].
  static Decimal fromRadians(Decimal r, AngleUnit unit, {int prec = WORK_PREC}) => switch (unit) {
        AngleUnit.rad => Dec.round(r, prec),
        AngleUnit.deg => Dec.div(Dec.mul(r, _d180, prec + 6), MathConstants.pi(prec + 6), prec),
        AngleUnit.grad => Dec.div(Dec.mul(r, _d200, prec + 6), MathConstants.pi(prec + 6), prec),
      };

  /// Converts an angle given in [unit] into radians.
  static Decimal toRadians(Decimal x, AngleUnit unit, {int prec = WORK_PREC}) => switch (unit) {
        AngleUnit.rad => Dec.round(x, prec),
        AngleUnit.deg => Dec.div(Dec.mul(x, MathConstants.pi(prec + 6), prec + 6), _d180, prec),
        AngleUnit.grad => Dec.div(Dec.mul(x, MathConstants.pi(prec + 6), prec + 6), _d200, prec),
      };

  static Decimal asin(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) =>
      fromRadians(asinRad(x, prec: prec + 4, token: token), unit, prec: prec);

  static Decimal acos(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) =>
      fromRadians(acosRad(x, prec: prec + 4, token: token), unit, prec: prec);

  static Decimal atan(Decimal x, AngleUnit unit, {int prec = WORK_PREC, CancellationToken? token}) =>
      fromRadians(atanRad(x, prec: prec + 4, token: token), unit, prec: prec);

  /// Four-quadrant arctangent in radians, `(-pi, pi]`.
  static Decimal atan2Rad(Decimal y, Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final sx = Dec.sign(x), sy = Dec.sign(y);
    final wp = prec + 6;
    if (sx == 0) {
      if (sy == 0) throw const DomainError('atan2(0, 0) is undefined');
      final h = Dec.mul(MathConstants.pi(wp), Dec.half, wp);
      return Dec.round(sy > 0 ? h : Dec.neg(h), prec);
    }
    if (sy == 0) return sx > 0 ? Dec.zero : MathConstants.pi(prec);
    final base = atanRad(Dec.div(y, x, wp + kGuardDigits), prec: wp, token: token);
    if (sx > 0) return Dec.round(base, prec);
    final pi = MathConstants.pi(wp);
    return Dec.round(sy > 0 ? Dec.add(base, pi, wp) : Dec.sub(base, pi, wp), prec);
  }

  // ------------------------------------------------------------ hyperbolic

  static Decimal _sinhSeries(Decimal r, int wp, CancellationToken? token) {
    final s = wp + 6;
    final scale = Dec.pow10(s);
    final r2 = Dec.toFixed(Dec.mul(r, r, s), s);
    var sum = scale;
    var term = scale;
    for (var k = 1;; k++) {
      token?.tick();
      term = (term * r2) ~/ (scale * BigInt.from(2 * k * (2 * k + 1)));
      if (term == _i0) break;
      sum += term;
    }
    return Dec.mul(r, Dec.fromFixed(sum, s), wp);
  }

  static Decimal sinh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.zero;
    final wp = prec + kGuardDigits;
    if (Dec.compare(Dec.abs(x), _c05) < 0) return Dec.round(_sinhSeries(x, wp, token), prec);
    final ex = exp(x, prec: wp, token: token);
    if (Dec.isZero(ex)) throw const OverflowError();
    return Dec.round(Dec.mul(Dec.sub(ex, Dec.div(Dec.one, ex, wp), wp), Dec.half, wp), prec);
  }

  static Decimal cosh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.one;
    final wp = prec + kGuardDigits;
    final ex = exp(Dec.abs(x), prec: wp, token: token);
    return Dec.round(Dec.mul(Dec.add(ex, Dec.div(Dec.one, ex, wp), wp), Dec.half, wp), prec);
  }

  static Decimal tanh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.zero;
    final wp = prec + kGuardDigits;
    final ax = Dec.abs(x);
    if (Dec.compare(ax, _c05) < 0) {
      return Dec.div(_sinhSeries(x, wp, token), cosh(x, prec: wp, token: token), prec);
    }
    if (Dec.adjExp(ax) >= 3) return Dec.isNegative(x) ? _minusOne : Dec.one;
    final e2 = exp(Dec.mul(ax, Dec.two, wp), prec: wp, token: token);
    final t = Dec.div(Dec.sub(e2, Dec.one, wp), Dec.add(e2, Dec.one, wp), prec);
    return Dec.isNegative(x) ? Dec.neg(t) : t;
  }

  static Decimal asinh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.isZero(x)) return Dec.zero;
    final wp = prec + kGuardDigits;
    final ax = Dec.abs(x);
    final x2 = Dec.mul(ax, ax, wp);
    // asinh x = ln1p(x + x^2 / (1 + sqrt(1 + x^2)))
    final root = Dec.sqrt(Dec.add(Dec.one, x2, wp), wp);
    final arg = Dec.add(ax, Dec.div(x2, Dec.add(Dec.one, root, wp), wp), wp);
    final r = ln1p(arg, prec: prec, token: token);
    return Dec.isNegative(x) ? Dec.neg(r) : r;
  }

  static Decimal acosh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    if (Dec.compare(x, Dec.one) < 0) throw const DomainError('acosh is only defined for x ≥ 1');
    final wp = prec + kGuardDigits;
    final eps = Dec.sub(x, Dec.one, 1000);
    if (Dec.isZero(eps)) return Dec.zero;
    // acosh(1 + e) = ln1p(e + sqrt(e (2 + e)))
    final root = Dec.sqrt(Dec.mul(eps, Dec.add(eps, Dec.two, 1000), wp), wp);
    return ln1p(Dec.add(eps, root, wp), prec: prec, token: token);
  }

  static Decimal atanh(Decimal x, {int prec = WORK_PREC, CancellationToken? token}) {
    final c = Dec.compare(Dec.abs(x), Dec.one);
    if (c >= 0) throw const DomainError('atanh is only defined on (-1, 1)');
    if (Dec.isZero(x)) return Dec.zero;
    final wp = prec + kGuardDigits;
    // atanh x = ln1p(2x / (1 - x)) / 2
    final arg = Dec.div(Dec.mul(x, Dec.two, 1000), Dec.sub(Dec.one, x, 1000), wp);
    return Dec.round(Dec.mul(ln1p(arg, prec: wp, token: token), Dec.half, wp), prec);
  }
}
