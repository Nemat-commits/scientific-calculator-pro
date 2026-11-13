import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../models/calc_error.dart';
import 'cancellation_token.dart';

/// Significant digits carried by every inexact intermediate result.
// ignore: constant_identifier_names
const int WORK_PREC = 50;

/// Significant digits of a formatted result (half-even rounded).
// ignore: constant_identifier_names
const int DISP_PREC = 34;

/// Extra digits used inside kernels so that [WORK_PREC] digits are trustworthy.
const int kGuardDigits = 12;

/// Largest decimal exponent magnitude the calculator represents.
const int kMaxExponent = 999999;

/// Rounding rule used when significant digits are dropped.
enum DecRounding { halfEven, halfUp, down }

/// A decimal number seen as `m x 10^e` with `m` free of trailing zeros.
final class DecParts {
  const DecParts(this.m, this.e);

  /// Signed coefficient.
  final BigInt m;

  /// Power-of-ten exponent.
  final int e;
}

/// Decimal floating point on top of `package:decimal`.
///
/// `Decimal` itself is exact and unbounded, so every operation here states the
/// number of significant digits it rounds to. No `double` and no `dart:math`
/// are involved: all work happens on `BigInt` coefficients, which keeps the
/// cost independent of the magnitude of the exponent.
abstract final class Dec {
  static final BigInt _i0 = BigInt.zero;
  static final BigInt _i1 = BigInt.one;
  static final BigInt _i10 = BigInt.from(10);

  static final Expando<DecParts> _partsOf = Expando<DecParts>('DecParts');
  static final List<BigInt> _pow10 = <BigInt>[BigInt.one];

  static final Decimal zero = compose(_i0, 0);
  static final Decimal one = compose(_i1, 0);
  static final Decimal two = compose(BigInt.two, 0);
  static final Decimal ten = compose(_i1, 1);
  static final Decimal half = compose(BigInt.from(5), -1);

  /// `10^n` for `n >= 0` (memoised for the common range).
  static BigInt pow10(int n) {
    if (n < 0) throw ArgumentError.value(n, 'n', 'must be non-negative');
    if (n < 4096) {
      while (_pow10.length <= n) {
        _pow10.add(_pow10.last * _i10);
      }
      return _pow10[n];
    }
    return _i10.pow(n);
  }

  /// Builds the decimal `m x 10^e`.
  static Decimal compose(BigInt m, int e) {
    if (m == _i0) {
      e = 0;
    } else if (m.isEven && m.remainder(_i10) == _i0) {
      for (var k = 64; k >= 1; k >>= 1) {
        final p = pow10(k);
        while (m.remainder(p) == _i0) {
          m = m ~/ p;
          e += k;
        }
      }
    }
    final d = Decimal.fromBigInt(m).shift(e);
    _partsOf[d] = DecParts(m, e);
    return d;
  }

  /// Coefficient / exponent view of [d].
  static DecParts parts(Decimal d) {
    final cached = _partsOf[d];
    if (cached != null) return cached;
    // Slow path for decimals that were not created by [compose].
    final s = d.scale;
    var m = d.shift(s).toBigInt();
    var e = -s;
    if (m == _i0) {
      e = 0;
    } else {
      for (var k = 64; k >= 1; k >>= 1) {
        final p = pow10(k);
        while (m.remainder(p) == _i0) {
          m = m ~/ p;
          e += k;
        }
      }
    }
    final p = DecParts(m, e);
    _partsOf[d] = p;
    return p;
  }

  /// Number of decimal digits of `|m|` (`0` has one digit).
  static int digitCount(BigInt m) {
    if (m == _i0) return 1;
    final a = m.isNegative ? -m : m;
    final bits = a.bitLength;
    if (bits < 4) return a.toInt() >= 10 ? 2 : 1;
    // floor(log10(a)) is est-1, est or est+1 where est = floor((bits-1)*log10(2)).
    final est = ((bits - 1) * 30103) ~/ 100000;
    if (a < pow10(est)) return est;
    if (a >= pow10(est + 1)) return est + 2;
    return est + 1;
  }

  static bool isZero(Decimal d) => parts(d).m == _i0;

  static int sign(Decimal d) => parts(d).m.sign;

  static bool isNegative(Decimal d) => parts(d).m.isNegative;

  /// `floor(log10(|d|))`; `0` for zero.
  static int adjExp(Decimal d) {
    final p = parts(d);
    return digitCount(p.m) - 1 + p.e;
  }

  static Decimal neg(Decimal d) {
    final p = parts(d);
    return compose(-p.m, p.e);
  }

  static Decimal abs(Decimal d) {
    final p = parts(d);
    return p.m.isNegative ? compose(-p.m, p.e) : d;
  }

  /// Three-way comparison that never expands large exponents.
  static int compare(Decimal a, Decimal b) {
    final pa = parts(a), pb = parts(b);
    final sa = pa.m.sign, sb = pb.m.sign;
    if (sa != sb) return sa < sb ? -1 : 1;
    if (sa == 0) return 0;
    final xa = digitCount(pa.m) + pa.e, xb = digitCount(pb.m) + pb.e;
    if (xa != xb) return (xa < xb ? -1 : 1) * sa;
    final c = pa.e >= pb.e
        ? (pa.m * pow10(pa.e - pb.e)).compareTo(pb.m)
        : pa.m.compareTo(pb.m * pow10(pb.e - pa.e));
    return c;
  }

  static bool equal(Decimal a, Decimal b) => compare(a, b) == 0;

  static Decimal max(Decimal a, Decimal b) => compare(a, b) >= 0 ? a : b;

  static Decimal min(Decimal a, Decimal b) => compare(a, b) <= 0 ? a : b;

  /// Rounds to [sig] significant digits.
  static Decimal round(Decimal d, int sig, [DecRounding mode = DecRounding.halfEven]) {
    final p = parts(d);
    final n = digitCount(p.m);
    if (n <= sig) return d;
    return _roundParts(p.m, p.e, n, sig, mode);
  }

  static Decimal _roundParts(BigInt m, int e, int n, int sig, DecRounding mode) {
    if (sig < 1) sig = 1;
    if (n <= sig) return compose(m, e);
    final drop = n - sig;
    final div = pow10(drop);
    var q = m ~/ div;
    if (mode != DecRounding.down) {
      final r = m.remainder(div).abs();
      if (r != _i0) {
        final c = (r << 1).compareTo(div);
        if (c > 0 || (c == 0 && (mode == DecRounding.halfUp || q.isOdd))) {
          q += m.isNegative ? -_i1 : _i1;
        }
      }
    }
    return compose(q, e + drop);
  }

  static Decimal _finish(BigInt m, int e, int prec) {
    final n = digitCount(m);
    return n > prec ? _roundParts(m, e, n, prec, DecRounding.halfEven) : compose(m, e);
  }

  static Decimal add(Decimal a, Decimal b, [int prec = WORK_PREC]) {
    final pa = parts(a), pb = parts(b);
    if (pa.m == _i0) return round(b, prec);
    if (pb.m == _i0) return round(a, prec);
    final topA = digitCount(pa.m) + pa.e, topB = digitCount(pb.m) + pb.e;
    final lowE = pa.e < pb.e ? pa.e : pb.e;
    final top = topA > topB ? topA : topB;
    if (top - lowE > prec + 8) {
      // The exact sum does not fit anyway: an operand lying entirely below
      // the rounding position of the other one cannot change the result.
      if (topA - topB > prec + 4) return round(a, prec);
      if (topB - topA > prec + 4) return round(b, prec);
    }
    final m = pa.e >= pb.e ? pa.m * pow10(pa.e - pb.e) + pb.m : pa.m + pb.m * pow10(pb.e - pa.e);
    return _finish(m, lowE, prec);
  }

  static Decimal sub(Decimal a, Decimal b, [int prec = WORK_PREC]) => add(a, neg(b), prec);

  static Decimal mul(Decimal a, Decimal b, [int prec = WORK_PREC]) {
    final pa = parts(a), pb = parts(b);
    return _finish(pa.m * pb.m, pa.e + pb.e, prec);
  }

  /// `a / b` correctly rounded to [prec] digits. Throws [DivisionByZero].
  static Decimal div(Decimal a, Decimal b, [int prec = WORK_PREC]) {
    final pa = parts(a), pb = parts(b);
    if (pb.m == _i0) throw const DivisionByZero();
    if (pa.m == _i0) return zero;
    var shift = prec + 3 + digitCount(pb.m) - digitCount(pa.m);
    if (shift < 0) shift = 0;
    final num = pa.m * pow10(shift);
    var q = num ~/ pb.m;
    var e = pa.e - pb.e - shift;
    if (num.remainder(pb.m) != _i0) {
      // Sticky digit: keeps an inexact quotient off the exact tie position.
      final negative = pa.m.isNegative != pb.m.isNegative;
      q = q * _i10 + (negative ? -_i1 : _i1);
      e -= 1;
    }
    return _finish(q, e, prec);
  }

  /// Integer square root (floor).
  static BigInt isqrt(BigInt n) {
    if (n.isNegative) throw ArgumentError.value(n, 'n', 'must be non-negative');
    if (n < BigInt.two) return n;
    var x = _i1 << ((n.bitLength + 1) >> 1);
    while (true) {
      final y = (x + n ~/ x) >> 1;
      if (y >= x) return x;
      x = y;
    }
  }

  /// Integer [k]-th root (floor) of a non-negative [n].
  static BigInt iroot(BigInt n, int k) {
    if (k == 1 || n < BigInt.two) return n;
    if (k == 2) return isqrt(n);
    final bk = BigInt.from(k), bk1 = BigInt.from(k - 1);
    var x = _i1 << ((n.bitLength + k - 1) ~/ k);
    while (true) {
      final y = (bk1 * x + n ~/ x.pow(k - 1)) ~/ bk;
      if (y >= x) return x;
      x = y;
    }
  }

  /// Square root rounded to [prec] digits (exact when the root is exact).
  static Decimal sqrt(Decimal x, [int prec = WORK_PREC]) {
    final p = parts(x);
    if (p.m.isNegative) throw const DomainError('Square root of a negative number');
    if (p.m == _i0) return zero;
    var shift = 2 * (prec + 2) - digitCount(p.m);
    if (shift < 0) shift = 0;
    if ((p.e - shift).isOdd) shift += 1;
    final scaled = p.m * pow10(shift);
    var r = isqrt(scaled);
    var e = (p.e - shift) ~/ 2;
    if (r * r != scaled) {
      r = r * _i10 + _i1;
      e -= 1;
    }
    return _finish(r, e, prec);
  }

  /// `base^n` for an integer [n] by binary exponentiation.
  static Decimal powInt(Decimal base, int n, {int prec = WORK_PREC, CancellationToken? token}) {
    if (n == 0) return one;
    if (isZero(base)) {
      if (n < 0) throw const DivisionByZero();
      return zero;
    }
    final wp = prec + kGuardDigits;
    var e = n.abs();
    var result = one;
    var b = base;
    while (true) {
      token?.tick();
      if (e & 1 == 1) result = mul(result, b, wp);
      e >>= 1;
      if (e == 0) break;
      b = mul(b, b, wp);
      final x = adjExp(b);
      if (x > 2 * kMaxExponent || x < -2 * kMaxExponent) {
        // The magnitude can only move further away from the range.
        final grows = (x > 0) == (n > 0);
        if (grows) throw const OverflowError();
        return zero;
      }
    }
    return n < 0 ? div(one, result, prec) : round(result, prec);
  }

  static Decimal fromInt(int v) => compose(BigInt.from(v), 0);

  static Decimal fromBigInt(BigInt v) => compose(v, 0);

  static final RegExp _literal = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$');

  /// Parses `[+-]digits[.digits][e[+-]digits]`.
  static Decimal parse(String source) {
    final match = _literal.firstMatch(source.trim());
    if (match == null) throw FormatException('Not a decimal literal', source);
    final intPart = match.group(2) ?? '';
    final fracPart = match.group(3) ?? '';
    if (intPart.isEmpty && fracPart.isEmpty) throw FormatException('Not a decimal literal', source);
    var m = BigInt.parse('$intPart$fracPart');
    if (match.group(1) == '-') m = -m;
    final exp = match.group(4);
    return compose(m, (exp == null ? 0 : int.parse(exp)) - fracPart.length);
  }

  static Decimal? tryParse(String source) {
    try {
      return parse(source);
    } on FormatException {
      return null;
    }
  }

  /// Nearest decimal with [prec] significant digits.
  static Decimal fromRational(Rational r, [int prec = WORK_PREC]) =>
      div(compose(r.numerator, 0), compose(r.denominator, 0), prec);

  /// Exact rational value, or `null` when the exponent is unreasonably large.
  static Rational? toRational(Decimal d) {
    final p = parts(d);
    if (p.e >= 0) {
      if (p.e > 700) return null;
      return Rational(p.m * pow10(p.e));
    }
    if (p.e < -700) return null;
    return Rational(p.m, pow10(-p.e));
  }

  /// Whether [d] is a whole number.
  static bool isInteger(Decimal d) => parts(d).e >= 0;

  /// Truncates towards zero.
  static BigInt toBigInt(Decimal d) {
    final p = parts(d);
    if (p.e >= 0) {
      if (p.e > 100000) throw const OverflowError('Integer is too large');
      return p.m * pow10(p.e);
    }
    if (-p.e >= digitCount(p.m)) return _i0;
    return p.m ~/ pow10(-p.e);
  }

  /// Converts to `int` when [d] is an integer of at most 18 digits.
  static int? toSmallInt(Decimal d) {
    final p = parts(d);
    if (p.e < 0 || digitCount(p.m) + p.e > 18) return null;
    return (p.m * pow10(p.e)).toInt();
  }

  static Decimal truncate(Decimal d) => isInteger(d) ? d : compose(toBigInt(d), 0);

  static Decimal floor(Decimal d) {
    if (isInteger(d)) return d;
    final t = toBigInt(d);
    return compose(isNegative(d) ? t - _i1 : t, 0);
  }

  static Decimal ceil(Decimal d) {
    if (isInteger(d)) return d;
    final t = toBigInt(d);
    return compose(isNegative(d) ? t : t + _i1, 0);
  }

  /// Rounds half away from zero to [places] decimal places.
  static Decimal roundToPlaces(Decimal d, [int places = 0]) {
    final p = parts(d);
    if (p.e >= -places) return d;
    final drop = -places - p.e;
    final n = digitCount(p.m);
    if (drop > n) return zero;
    final div = pow10(drop);
    var q = p.m ~/ div;
    final r = p.m.remainder(div).abs();
    if ((r << 1) >= div) q += p.m.isNegative ? -_i1 : _i1;
    return compose(q, -places);
  }

  /// `trunc(d x 10^scale)` - entry point of the fixed-point kernels.
  static BigInt toFixed(Decimal d, int scale) {
    final p = parts(d);
    final sh = p.e + scale;
    if (sh >= 0) return p.m * pow10(sh);
    if (-sh > digitCount(p.m)) return _i0;
    return p.m ~/ pow10(-sh);
  }

  /// Inverse of [toFixed].
  static Decimal fromFixed(BigInt v, int scale) => compose(v, -scale);

  /// Euclidean remainder `a mod n` (result in `[0, |n|)`), exact.
  static Decimal mod(Decimal a, Decimal n) {
    final pa = parts(a), pn = parts(n);
    if (pn.m == _i0) throw const DivisionByZero('Modulo by zero');
    if (pa.m == _i0) return zero;
    final nAbs = pn.m.abs();
    if (pa.e >= pn.e) {
      // a = ma*10^(ea-en) units of 10^en; reduce the power of ten modulo |mn|.
      final scale = _i10.modPow(BigInt.from(pa.e - pn.e), nAbs);
      final r = (pa.m % nAbs) * scale % nAbs;
      return compose(r, pn.e);
    }
    final shift = pn.e - pa.e;
    if (shift > 100000) return pa.m.isNegative ? add(a, abs(n)) : a;
    final modulus = nAbs * pow10(shift);
    return compose(pa.m % modulus, pa.e);
  }

  /// Plain digits of `|m|`.
  static String digits(BigInt m) => (m.isNegative ? -m : m).toString();
}
