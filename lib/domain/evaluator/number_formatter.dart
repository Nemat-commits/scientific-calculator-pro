import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../models/calc_value.dart';
import '../models/math_context.dart';
import 'decimal_math.dart';

export 'decimal_math.dart' show DISP_PREC, WORK_PREC;

/// Turns values into their canonical display strings.
///
/// The strings are locale-neutral (no digit grouping); the UI layer applies
/// thousands separators with [NumberFormatter.groupThousands].
abstract final class NumberFormatter {
  /// Smallest decimal exponent still written without scientific notation.
  static const int minPlainExponent = -7;

  /// Largest number of digits a "simple" fraction may use (numerator plus
  /// denominator) to be offered as the secondary read-out.
  static const int maxFractionDigits = 24;

  /// Digits per part in the short form of a complex number.
  static const int complexShortDigits = 10;

  /// Formats [x] with at most [prec] significant digits (half-even).
  ///
  /// Whole numbers are always printed as plain integers while they fit
  /// (`30`, `10000` - never `3E+1`), tiny and huge magnitudes switch to
  /// `d.ddde±x`.
  static String formatDec(
    Decimal x, {
    int prec = DISP_PREC,
    NotationMode notation = NotationMode.auto,
  }) {
    if (Dec.isZero(x)) return '0';
    final p = Dec.parts(Dec.round(x, prec));
    final digits = Dec.digits(p.m);
    final n = digits.length;
    final adj = n - 1 + p.e;
    final sign = p.m.isNegative ? '-' : '';
    switch (notation) {
      case NotationMode.scientific:
        return sign + _scientific(digits, adj);
      case NotationMode.engineering:
        return sign + _engineering(digits, adj);
      case NotationMode.auto:
        final plainLimit = prec > 16 ? prec : 16;
        if (p.e >= 0) {
          return adj < plainLimit ? '$sign$digits${'0' * p.e}' : sign + _scientific(digits, adj);
        }
        if (adj >= minPlainExponent && adj < plainLimit) return sign + _plainFraction(digits, p.e);
        return sign + _scientific(digits, adj);
    }
  }

  static String _plainFraction(String digits, int e) {
    final n = digits.length;
    final point = n + e; // digits before the decimal point
    if (point > 0) return '${digits.substring(0, point)}.${digits.substring(point)}';
    return '0.${'0' * -point}$digits';
  }

  static String _scientific(String digits, int adj) {
    final mantissa = digits.length == 1 ? digits : '${digits[0]}.${digits.substring(1)}';
    return '${mantissa}e$adj';
  }

  static String _engineering(String digits, int adj) {
    final exp3 = adj - (adj % 3); // Dart's % is non-negative for a positive modulus
    final intDigits = adj - exp3 + 1;
    final padded = digits.length < intDigits ? digits + '0' * (intDigits - digits.length) : digits;
    final head = padded.substring(0, intDigits);
    final tail = padded.substring(intDigits);
    final mantissa = tail.isEmpty ? head : '$head.$tail';
    return exp3 == 0 ? mantissa : '${mantissa}e$exp3';
  }

  /// `n/d` (or just `n` for whole numbers).
  static String formatFraction(Rational r) =>
      r.denominator == BigInt.one ? r.numerator.toString() : '${r.numerator}/${r.denominator}';

  /// Canonical primary string of any value.
  static String formatValue(
    CalcValue v, {
    int prec = DISP_PREC,
    NotationMode notation = NotationMode.auto,
    int? radix,
  }) {
    switch (v) {
      case RationalVal(:final value):
        if (value.denominator == BigInt.one && notation == NotationMode.auto) {
          final digits = Dec.digitCount(value.numerator);
          if (digits <= (prec > 16 ? prec : 16)) return value.numerator.toString();
        }
        return formatDec(Dec.fromRational(value, prec), prec: prec, notation: notation);
      case DecimalVal(:final value):
        return formatDec(value, prec: prec, notation: notation);
      case ComplexVal(:final real, :final imag):
        final re = formatDec(real, prec: prec, notation: notation);
        final im = formatDec(Dec.abs(imag), prec: prec, notation: notation);
        return '$re ${Dec.isNegative(imag) ? '-' : '+'} ${im}i';
      case BitwiseVal():
        return formatBitwise(v, radix: radix ?? 10);
      case MatrixVal(:final grid):
        final shown = prec > 12 ? 12 : prec;
        return '[${grid.map((row) => '[${row.map((c) => formatDec(c, prec: shown, notation: notation)).join(', ')}]').join(', ')}]';
    }
  }

  /// Alternative read-out: the exact fraction of a rational result, the
  /// engineering form of a result shown in scientific notation, or a complex
  /// number rounded to [complexShortDigits] digits per part. When the
  /// primary read-out is in another [notation] than the automatic one, the
  /// alternative of a number that is no fraction is its automatic form.
  static String? formatSecondary(CalcValue v, {int prec = DISP_PREC, NotationMode notation = NotationMode.auto}) {
    String? plainForm() {
      final plain = formatValue(v, prec: prec);
      return plain == formatValue(v, prec: prec, notation: notation) ? null : plain;
    }

    switch (v) {
      case RationalVal(:final value):
        if (value.denominator == BigInt.one) return notation == NotationMode.auto ? null : plainForm();
        final used = Dec.digitCount(value.numerator) + Dec.digitCount(value.denominator);
        return used <= maxFractionDigits ? formatFraction(value) : null;
      case DecimalVal(:final value):
        if (notation != NotationMode.auto) return plainForm();
        final primary = formatDec(value, prec: prec);
        if (!primary.contains('e')) return null;
        final eng = formatDec(value, prec: prec, notation: NotationMode.engineering);
        return eng == primary ? null : eng;
      case ComplexVal():
        // Two long decimals side by side are hard to read: the short form.
        final short = formatValue(v, prec: complexShortDigits, notation: notation);
        return short == formatValue(v, prec: prec, notation: notation) ? null : short;
      case BitwiseVal() || MatrixVal():
        return null;
    }
  }

  /// Word of a Base-N value in [radix] (2, 8, 10 or 16).
  static String formatBitwise(BitwiseVal v, {int radix = 10, bool pad = false}) {
    if (radix == 10) return v.numericValue.toString();
    var s = v.bits.toRadixString(radix).toUpperCase();
    if (pad) {
      final width = switch (radix) { 2 => v.wordSize, 8 => (v.wordSize + 2) ~/ 3, _ => v.wordSize ~/ 4 };
      s = s.padLeft(width, '0');
    }
    return s;
  }

  static final RegExp _number = RegExp(r'\d+(?:\.\d+)?');

  /// Inserts thousands separators into the integer part of every plain
  /// number of [text] (exponents and fractional digits are left untouched).
  static String groupThousands(String text, {String separator = ','}) {
    return text.replaceAllMapped(_number, (match) {
      final start = match.start;
      if (start > 0) {
        final prev = text[start - 1];
        final prev2 = start > 1 ? text[start - 2] : '';
        final afterExponent =
            prev == 'e' || prev == '^' || ((prev == '-' || prev == '+') && (prev2 == 'e' || prev2 == '^'));
        if (afterExponent || prev == '.') return match[0]!;
      }
      final token = match[0]!;
      final dot = token.indexOf('.');
      final intPart = dot < 0 ? token : token.substring(0, dot);
      if (intPart.length <= 3) return token;
      final buffer = StringBuffer();
      final lead = intPart.length % 3;
      if (lead > 0) buffer.write(intPart.substring(0, lead));
      for (var i = lead; i < intPart.length; i += 3) {
        if (buffer.isNotEmpty) buffer.write(separator);
        buffer.write(intPart.substring(i, i + 3));
      }
      return dot < 0 ? buffer.toString() : '$buffer${token.substring(dot)}';
    });
  }

  /// Groups the digits of a Base-N word in blocks of [size].
  static String groupWord(String word, {int size = 4, String separator = ' '}) {
    final buffer = StringBuffer();
    final lead = word.length % size;
    if (lead > 0) buffer.write(word.substring(0, lead));
    for (var i = lead; i < word.length; i += size) {
      if (buffer.isNotEmpty) buffer.write(separator);
      buffer.write(word.substring(i, i + size));
    }
    return buffer.toString();
  }
}
