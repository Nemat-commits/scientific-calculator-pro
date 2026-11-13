import 'package:decimal/decimal.dart';

import '../../core/constants/math_constants.dart';
import '../models/calc_error.dart';
import '../models/calc_value.dart';
import 'cancellation_token.dart';
import 'decimal_math.dart';
import 'transcendental_engine.dart';

/// Complex arithmetic and elementary functions (angles in radians).
abstract final class ComplexMath {
  static final ComplexVal i = ComplexVal(Dec.zero, Dec.one);

  static ComplexVal of(Decimal re, [Decimal? im]) => ComplexVal(re, im ?? Dec.zero);

  static bool isZero(ComplexVal z) => Dec.isZero(z.real) && Dec.isZero(z.imag);

  /// Clears a component that is pure cancellation noise next to the other one.
  static ComplexVal snap(ComplexVal z) {
    if (Dec.isZero(z.real) || Dec.isZero(z.imag)) return z;
    final re = Dec.adjExp(z.real), im = Dec.adjExp(z.imag);
    if (re < im + Transcendental.zeroSnapExponent) return ComplexVal(Dec.zero, z.imag);
    if (im < re + Transcendental.zeroSnapExponent) return ComplexVal(z.real, Dec.zero);
    return z;
  }

  static ComplexVal add(ComplexVal a, ComplexVal b) => ComplexVal(Dec.add(a.real, b.real), Dec.add(a.imag, b.imag));

  static ComplexVal sub(ComplexVal a, ComplexVal b) => ComplexVal(Dec.sub(a.real, b.real), Dec.sub(a.imag, b.imag));

  static ComplexVal neg(ComplexVal a) => ComplexVal(Dec.neg(a.real), Dec.neg(a.imag));

  static ComplexVal conj(ComplexVal a) => ComplexVal(a.real, Dec.neg(a.imag));

  static ComplexVal mul(ComplexVal a, ComplexVal b) {
    const p = WORK_PREC + 6;
    return ComplexVal(
      Dec.sub(Dec.mul(a.real, b.real, p), Dec.mul(a.imag, b.imag, p)),
      Dec.add(Dec.mul(a.real, b.imag, p), Dec.mul(a.imag, b.real, p)),
    );
  }

  static ComplexVal scale(ComplexVal a, Decimal k) => ComplexVal(Dec.mul(a.real, k), Dec.mul(a.imag, k));

  static ComplexVal div(ComplexVal a, ComplexVal b) {
    if (isZero(b)) throw const DivisionByZero();
    const p = WORK_PREC + 6;
    final den = Dec.add(Dec.mul(b.real, b.real, p), Dec.mul(b.imag, b.imag, p), p);
    final re = Dec.add(Dec.mul(a.real, b.real, p), Dec.mul(a.imag, b.imag, p), p);
    final im = Dec.sub(Dec.mul(a.imag, b.real, p), Dec.mul(a.real, b.imag, p), p);
    return ComplexVal(Dec.div(re, den), Dec.div(im, den));
  }

  /// `|z|`
  static Decimal modulus(ComplexVal z, [int prec = WORK_PREC]) {
    if (Dec.isZero(z.imag)) return Dec.abs(z.real);
    if (Dec.isZero(z.real)) return Dec.abs(z.imag);
    final p = prec + 6;
    return Dec.sqrt(Dec.add(Dec.mul(z.real, z.real, p), Dec.mul(z.imag, z.imag, p), p), prec);
  }

  /// Principal argument in `(-pi, pi]`.
  static Decimal argument(ComplexVal z, {CancellationToken? token}) {
    if (isZero(z)) throw const DomainError('The argument of 0 is undefined');
    return Transcendental.atan2Rad(z.imag, z.real, token: token);
  }

  /// Principal square root.
  static ComplexVal sqrt(ComplexVal z) {
    if (isZero(z)) return z;
    const p = WORK_PREC + 6;
    if (Dec.isZero(z.imag)) {
      return Dec.isNegative(z.real)
          ? ComplexVal(Dec.zero, Dec.sqrt(Dec.neg(z.real)))
          : ComplexVal(Dec.sqrt(z.real), Dec.zero);
    }
    final m = modulus(z, p);
    if (!Dec.isNegative(z.real)) {
      final re = Dec.sqrt(Dec.mul(Dec.add(m, z.real, p), Dec.half, p), p);
      return ComplexVal(Dec.round(re, WORK_PREC), Dec.div(z.imag, Dec.mul(re, Dec.two, p)));
    }
    var im = Dec.sqrt(Dec.mul(Dec.sub(m, z.real, p), Dec.half, p), p);
    final re = Dec.div(Dec.abs(z.imag), Dec.mul(im, Dec.two, p));
    if (Dec.isNegative(z.imag)) im = Dec.neg(im);
    return ComplexVal(re, Dec.round(im, WORK_PREC));
  }

  static ComplexVal exp(ComplexVal z, {CancellationToken? token}) {
    final magnitude = Transcendental.exp(z.real, prec: WORK_PREC + 4, token: token);
    if (Dec.isZero(z.imag)) return ComplexVal(Dec.round(magnitude, WORK_PREC), Dec.zero);
    final sc = Transcendental.sinCosRad(z.imag, prec: WORK_PREC + 4, token: token);
    return ComplexVal(Dec.mul(magnitude, sc.cos), Dec.mul(magnitude, sc.sin));
  }

  /// Principal natural logarithm.
  static ComplexVal ln(ComplexVal z, {CancellationToken? token}) {
    if (isZero(z)) throw const DomainError('Logarithm of zero is undefined');
    return ComplexVal(Transcendental.ln(modulus(z, WORK_PREC + 6), token: token), argument(z, token: token));
  }

  static ComplexVal powInt(ComplexVal z, int n, {CancellationToken? token}) {
    if (n == 0) return ComplexVal(Dec.one, Dec.zero);
    if (isZero(z)) {
      if (n < 0) throw const DivisionByZero();
      return z;
    }
    var e = n.abs();
    var result = ComplexVal(Dec.one, Dec.zero);
    var base = z;
    while (true) {
      token?.tick();
      if (e & 1 == 1) result = mul(result, base);
      e >>= 1;
      if (e == 0) break;
      base = mul(base, base);
    }
    return n < 0 ? div(ComplexVal(Dec.one, Dec.zero), result) : result;
  }

  /// `z^w` (principal branch).
  static ComplexVal pow(ComplexVal z, ComplexVal w, {CancellationToken? token}) {
    if (isZero(z)) {
      if (Dec.sign(w.real) > 0) return ComplexVal(Dec.zero, Dec.zero);
      throw const DomainError('0 raised to a non-positive power');
    }
    if (Dec.isZero(w.imag)) {
      final n = Dec.toSmallInt(w.real);
      if (n != null && n.abs() <= 4096) return powInt(z, n, token: token);
    }
    return snap(exp(mul(w, ln(z, token: token)), token: token));
  }

  static ComplexVal sin(ComplexVal z, {CancellationToken? token}) {
    final sc = Transcendental.sinCosRad(z.real, prec: WORK_PREC + 4, token: token);
    final ch = Transcendental.cosh(z.imag, prec: WORK_PREC + 4, token: token);
    final sh = Transcendental.sinh(z.imag, prec: WORK_PREC + 4, token: token);
    return snap(ComplexVal(Dec.mul(sc.sin, ch), Dec.mul(sc.cos, sh)));
  }

  static ComplexVal cos(ComplexVal z, {CancellationToken? token}) {
    final sc = Transcendental.sinCosRad(z.real, prec: WORK_PREC + 4, token: token);
    final ch = Transcendental.cosh(z.imag, prec: WORK_PREC + 4, token: token);
    final sh = Transcendental.sinh(z.imag, prec: WORK_PREC + 4, token: token);
    return snap(ComplexVal(Dec.mul(sc.cos, ch), Dec.neg(Dec.mul(sc.sin, sh))));
  }

  static ComplexVal tan(ComplexVal z, {CancellationToken? token}) {
    final c = cos(z, token: token);
    if (isZero(c)) throw const DomainError('Undefined asymptote');
    return div(sin(z, token: token), c);
  }

  static ComplexVal sinh(ComplexVal z, {CancellationToken? token}) {
    final sc = Transcendental.sinCosRad(z.imag, prec: WORK_PREC + 4, token: token);
    final ch = Transcendental.cosh(z.real, prec: WORK_PREC + 4, token: token);
    final sh = Transcendental.sinh(z.real, prec: WORK_PREC + 4, token: token);
    return snap(ComplexVal(Dec.mul(sh, sc.cos), Dec.mul(ch, sc.sin)));
  }

  static ComplexVal cosh(ComplexVal z, {CancellationToken? token}) {
    final sc = Transcendental.sinCosRad(z.imag, prec: WORK_PREC + 4, token: token);
    final ch = Transcendental.cosh(z.real, prec: WORK_PREC + 4, token: token);
    final sh = Transcendental.sinh(z.real, prec: WORK_PREC + 4, token: token);
    return snap(ComplexVal(Dec.mul(ch, sc.cos), Dec.mul(sh, sc.sin)));
  }

  static ComplexVal tanh(ComplexVal z, {CancellationToken? token}) {
    final c = cosh(z, token: token);
    if (isZero(c)) throw const DomainError('Undefined asymptote');
    return div(sinh(z, token: token), c);
  }

  static final ComplexVal _one = ComplexVal(Dec.one, Dec.zero);

  /// `asin z = -i ln(iz + sqrt(1 - z^2))`
  static ComplexVal asin(ComplexVal z, {CancellationToken? token}) {
    final root = sqrt(sub(_one, mul(z, z)));
    final inner = ln(add(mul(i, z), root), token: token);
    return snap(ComplexVal(inner.imag, Dec.neg(inner.real)));
  }

  /// `acos z = pi/2 - asin z`
  static ComplexVal acos(ComplexVal z, {CancellationToken? token}) {
    final a = asin(z, token: token);
    final halfPi = Dec.mul(MathConstants.pi(WORK_PREC + 4), Dec.half, WORK_PREC + 4);
    return snap(ComplexVal(Dec.sub(halfPi, a.real), Dec.neg(a.imag)));
  }

  /// `atan z = (i/2) (ln(1 - iz) - ln(1 + iz))`
  static ComplexVal atan(ComplexVal z, {CancellationToken? token}) {
    final iz = mul(i, z);
    final plus = add(_one, iz), minus = sub(_one, iz);
    if (isZero(plus) || isZero(minus)) throw const DomainError('atan is undefined at ±i');
    final d = sub(ln(minus, token: token), ln(plus, token: token));
    // (i/2) (x + iy) = (-y + ix) / 2
    return snap(ComplexVal(Dec.mul(Dec.neg(d.imag), Dec.half), Dec.mul(d.real, Dec.half)));
  }
}
