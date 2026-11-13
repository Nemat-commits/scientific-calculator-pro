import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../evaluator/decimal_math.dart';
import 'calc_value.dart';

/// Loss-free text form of a [CalcValue].
///
/// Used wherever values leave the evaluator as plain strings: the variable
/// map of the UI state (`'Ans': '0'`), the SQLite tables and the messages
/// exchanged with the worker isolate.
///
/// | value     | encoding                                  |
/// |-----------|-------------------------------------------|
/// | rational  | `7`, `-3/8`                               |
/// | decimal   | `~31415926535e-10` (coefficient, exponent)|
/// | complex   | `c:<re>;<im>`                             |
/// | bitwise   | `b:<hex bits>:<word>:<s or u>`            |
/// | matrix    | `m:<rows>:<cols>:<v>;<v>;…`               |
abstract final class CalcValueCodec {
  static String _dec(Decimal d) {
    final p = Dec.parts(d);
    return '~${p.m}e${p.e}';
  }

  static Decimal _parseDec(String s) {
    final body = s.startsWith('~') ? s.substring(1) : s;
    final e = body.indexOf('e');
    if (e < 0) return Dec.parse(body);
    return Dec.compose(BigInt.parse(body.substring(0, e)), int.parse(body.substring(e + 1)));
  }

  static String encode(CalcValue v) => switch (v) {
        RationalVal(:final value) =>
          value.denominator == BigInt.one ? '${value.numerator}' : '${value.numerator}/${value.denominator}',
        DecimalVal(:final value) => _dec(value),
        ComplexVal(:final real, :final imag) => 'c:${_dec(real)};${_dec(imag)}',
        BitwiseVal(:final bits, :final wordSize, :final isSigned) =>
          'b:${bits.toRadixString(16)}:$wordSize:${isSigned ? 's' : 'u'}',
        MatrixVal(:final grid) =>
          'm:${v.rows}:${v.cols}:${<String>[for (final row in grid) ...row.map(_dec)].join(';')}',
      };

  /// Inverse of [encode]. Unreadable input decodes to zero.
  static CalcValue decode(String text) {
    try {
      final s = text.trim();
      if (s.startsWith('~')) return DecimalVal(_parseDec(s));
      if (s.startsWith('c:')) {
        final parts = s.substring(2).split(';');
        return ComplexVal(_parseDec(parts[0]), _parseDec(parts[1]));
      }
      if (s.startsWith('b:')) {
        final parts = s.substring(2).split(':');
        return BitwiseVal(
          BigInt.parse(parts[0], radix: 16),
          wordSize: int.parse(parts[1]),
          isSigned: parts[2] == 's',
        );
      }
      if (s.startsWith('m:')) {
        final head = s.substring(2).split(':');
        final rows = int.parse(head[0]), cols = int.parse(head[1]);
        final cells = head.sublist(2).join(':').split(';').map(_parseDec).toList();
        return MatrixVal(<List<Decimal>>[
          for (var r = 0; r < rows; r++) cells.sublist(r * cols, (r + 1) * cols),
        ]);
      }
      final slash = s.indexOf('/');
      if (slash > 0) {
        return RationalVal(Rational(BigInt.parse(s.substring(0, slash)), BigInt.parse(s.substring(slash + 1))));
      }
      final whole = BigInt.tryParse(s);
      if (whole != null) return RationalVal(Rational(whole));
      return Values.ofDecimalExact(Dec.parse(s));
    } on Object {
      return Values.zero;
    }
  }

  /// Decodes a whole variable map.
  static Map<String, CalcValue> decodeAll(Map<String, String> encoded) =>
      <String, CalcValue>{for (final e in encoded.entries) e.key: decode(e.value)};
}
