// Checks the numbers of the Convert and Lab tabs against values that were
// not produced by the app: the definitions of the units, the published
// physical constants, and results computed with other software. The expected
// values are in reference_data.dart; tool/reference/generate_reference_data.py
// writes that file and says where each group of values comes from.
import 'package:decimal/decimal.dart';
import 'package:modern_scientific_calculator/core/constants/math_constants.dart';
import 'package:modern_scientific_calculator/core/constants/unit_definitions.dart';
import 'package:modern_scientific_calculator/domain/editor/clipboard_sanitizer.dart';
import 'package:modern_scientific_calculator/domain/evaluator/algebra_solver_engine.dart';
import 'package:modern_scientific_calculator/domain/evaluator/decimal_math.dart';
import 'package:modern_scientific_calculator/domain/evaluator/number_formatter.dart';
import 'package:modern_scientific_calculator/domain/evaluator/unit_converter_engine.dart';
import 'package:modern_scientific_calculator/domain/math_engine.dart';
import 'package:modern_scientific_calculator/domain/models/calc_error.dart';
import 'package:modern_scientific_calculator/domain/models/calc_value.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/domain/models/math_context.dart';
import 'package:rational/rational.dart';
import 'package:test/test.dart';

import 'reference_data.dart';

/// `p/q` as an exact fraction.
Rational fraction(String text) {
  final parts = text.split('/');
  return Rational(BigInt.parse(parts[0]), parts.length > 1 ? BigInt.parse(parts[1]) : BigInt.one);
}

/// A decimal literal (`-1.5`, `6.02214076e23`) as an exact fraction.
Rational literal(String text) => (MathEngine.evaluateText(text.replaceAll('e', 'E')).value as RationalVal).value;

Decimal decimalOf(String text) => text.contains('/') ? Dec.fromRational(fraction(text), 70) : Dec.parse(text);

Decimal realOf(CalcValue v) => switch (v) {
      ComplexVal(:final real) => real,
      _ => v.asDecimal,
    };

Decimal imaginaryOf(CalcValue v) => v is ComplexVal ? v.imag : Dec.zero;

/// Whether [actual] and [expected] agree in their first [digits] significant
/// digits (to `10^-digits` when the expected value is 0).
bool agree(Decimal actual, Decimal expected, int digits) {
  final difference = Dec.abs(Dec.sub(actual, expected, 120));
  if (Dec.isZero(difference)) return true;
  final scale = Dec.isZero(expected) ? 0 : Dec.adjExp(expected);
  return Dec.adjExp(difference) < scale - digits;
}

Matcher agreesWith(String expected, {int digits = 40}) => predicate<Decimal>(
      (actual) => agree(actual, decimalOf(expected), digits),
      'agrees with $expected in $digits digits',
    );

MatrixVal matrix(List<List<String>> rows) => MatrixOps.of(<List<Decimal>>[
      for (final row in rows) <Decimal>[for (final v in row) decimalOf(v)],
    ]);

void expectMatrix(MatrixVal actual, List<List<String>> expected, String what) {
  expect(actual.rows, expected.length, reason: what);
  expect(actual.cols, expected.first.length, reason: what);
  for (var r = 0; r < expected.length; r++) {
    for (var c = 0; c < expected[r].length; c++) {
      expect(actual.grid[r][c], agreesWith(expected[r][c]), reason: '$what, row ${r + 1}, column ${c + 1}');
    }
  }
}

void main() {
  group('Convert: units', () {
    test('every unit has the size its definition gives it', () {
      var checked = 0;
      for (final category in UnitDefinitions.categories) {
        for (final unit in category.units) {
          final where = '${category.id}/${unit.id}';
          final factor = UnitConverterEngine.factorOf(unit);
          if (category.id == 'angle') {
            final reference = referenceAngleFactors[unit.id];
            expect(reference, isNotNull, reason: '$where has no reference value');
            expect(factor.asDecimal, agreesWith(reference!), reason: where);
          } else {
            final reference = referenceUnitFactors[category.id]?[unit.id];
            expect(reference, isNotNull, reason: '$where has no reference value');
            expect(factor, isA<RationalVal>(), reason: '$where is not stored exactly');
            expect((factor as RationalVal).value, fraction(reference!), reason: where);
          }
          final offset = MathEngine.evaluateText(unit.offset).value as RationalVal;
          final expectedOffset =
              category.id == 'temperature' ? fraction(referenceTemperatureOffsets[unit.id]!) : Rational.zero;
          expect(offset.value, expectedOffset, reason: 'offset of $where');
          checked++;
        }
      }
      // Nothing in the reference tables is left over either.
      final referenced =
          referenceUnitFactors.values.fold<int>(0, (n, units) => n + units.length) + referenceAngleFactors.length;
      expect(checked, referenced);
    });

    test('conversions that standards state as round numbers come out exactly', () {
      for (final (category, value, from, to, expected) in referenceConversions) {
        final units = UnitDefinitions.category(category);
        final result = UnitConverterEngine.convert(RationalVal(literal(value)), units.unit(from), units.unit(to));
        expect(result, isA<RationalVal>(), reason: '$value $from in $to');
        expect((result as RationalVal).value, literal(expected), reason: '$value $from in $to');
      }
    });

    test('conversions that do not come out round agree with an independent calculation', () {
      for (final (category, value, from, to, expected) in referenceRoundedConversions) {
        final units = UnitDefinitions.category(category);
        final result = UnitConverterEngine.convert(RationalVal(literal(value)), units.unit(from), units.unit(to));
        final shown = result is RationalVal ? Dec.fromRational(result.value, 70) : result.asDecimal;
        expect(shown, agreesWith(expected), reason: '$value $from in $to');
      }
    });

    test('every conversion is undone by the opposite one', () {
      final probe = RationalVal(literal('12.5'));
      for (final category in UnitDefinitions.categories) {
        for (final from in category.units) {
          for (final to in category.units) {
            final there = UnitConverterEngine.convert(probe, from, to);
            final back = UnitConverterEngine.convert(there, to, from);
            expect(back.asDecimal, agreesWith('12.5'), reason: '${category.id}: ${from.id} → ${to.id} → ${from.id}');
          }
        }
      }
    });

    test('the two families of data units are told apart by name', () {
      final data = UnitDefinitions.category('data');
      String shown(String value, String from, String to) =>
          UnitConverterEngine.convertFormatted(RationalVal(literal(value)), data.unit(from), data.unit(to));
      // SI prefixes are powers of 1000, the IEC prefixes powers of 1024.
      expect(shown('1', 'mb', 'kb'), '1000');
      expect(shown('1', 'mib', 'kib'), '1024');
      expect(shown('1', 'mb', 'kib'), '976.5625');
      for (final unit in data.units) {
        if (unit.id == 'bit' || unit.id == 'b') continue;
        expect(unit.name, contains(unit.id.endsWith('ib') ? '1024' : '1000'), reason: unit.id);
      }
    });
  });

  group('Convert: physical constants', () {
    test('every constant has its published value', () {
      for (final constant in MathConstants.codata) {
        final reference = referenceConstants[constant.symbol];
        expect(reference, isNotNull, reason: '${constant.symbol} has no reference value');
        final given = literal(constant.value);
        final derived = const <String>{'ħ', 'R', 'F', 'σ', 'V_m'}.contains(constant.symbol);
        if (!derived) {
          // A defined or measured value: every digit is the published one.
          expect(given, literal(reference!), reason: constant.symbol);
        } else {
          // A value that follows from exact ones: right to the last digit it is given with.
          final significant =
              constant.value.split('e').first.replaceAll(RegExp(r'[.\-]'), '').replaceFirst(RegExp('^0+'), '');
          expect(Dec.fromRational(given, 70), agreesWith(reference!, digits: significant.length - 1),
              reason: constant.symbol);
        }
      }
      expect(MathConstants.codata.length, referenceConstants.length);
    });

    test('the value the calculator computes with is the one that is shown', () {
      for (final constant in MathConstants.codata) {
        final key = EditorSequence.root(<EditorNode>[AtomNode(constant.symbol, AtomKind.constant)]);
        final used = MathEngine.evaluateSequence(key).value;
        expect(used, isA<RationalVal>(), reason: constant.symbol);
        expect((used as RationalVal).value, literal(constant.value), reason: constant.symbol);
      }
    });
  });

  group('Lab: equations', () {
    test('roots of linear, quadratic and cubic equations', () {
      for (final (coefficients, roots) in referencePolynomials) {
        final solution = PolynomialSolver.solve(<CalcValue>[for (final c in coefficients) RationalVal(fraction(c))]);
        final what = 'coefficients $coefficients';
        expect(solution.roots.length, roots.length, reason: what);
        final open = <CalcValue>[...solution.roots];
        for (final (re, im) in roots) {
          final index = open.indexWhere(
            (root) => agree(realOf(root), decimalOf(re), 30) && agree(imaginaryOf(root), decimalOf(im), 30),
          );
          expect(index, isNot(-1),
              reason: '$what: no root $re ${im.startsWith('-') ? '' : '+'}${im}i among ${solution.roots}');
          if (index >= 0) open.removeAt(index);
        }
      }
    });
  });

  group('Lab: matrices', () {
    test('determinant, trace, rank, inverse, transpose, sum, difference and product', () {
      for (final (a, b, det, trace, rank, inverse, transpose, sum, difference, product) in referenceMatrices) {
        final ma = matrix(a), mb = matrix(b);
        final what = 'A = $a';
        expect(MatrixOps.determinant(ma), agreesWith(det), reason: 'determinant, $what');
        expect(MatrixOps.trace(ma), agreesWith(trace), reason: 'trace, $what');
        expect(MatrixOps.rank(ma), rank, reason: 'rank, $what');
        if (inverse == null) {
          expect(() => MatrixOps.inverse(ma), throwsA(isA<CalcError>()), reason: 'inverse of a singular matrix, $what');
        } else {
          expectMatrix(MatrixOps.inverse(ma), inverse, 'inverse, $what');
        }
        expectMatrix(MatrixOps.transpose(ma), transpose, 'transpose, $what');
        expectMatrix(MatrixOps.add(ma, mb), sum, 'sum, $what');
        expectMatrix(MatrixOps.sub(ma, mb), difference, 'difference, $what');
        expectMatrix(MatrixOps.mul(ma, mb), product, 'product, $what');
      }
    });

    test('rectangular matrices', () {
      for (final (a, b, product, transpose, rank) in referenceRectangular) {
        final ma = matrix(a), mb = matrix(b);
        expectMatrix(MatrixOps.mul(ma, mb), product, 'product, A = $a');
        expectMatrix(MatrixOps.transpose(ma), transpose, 'transpose, A = $a');
        expect(MatrixOps.rank(ma), rank, reason: 'rank, A = $a');
      }
    });
  });

  group('Lab: statistics', () {
    test('one variable', () {
      for (final (data, expected) in referenceStatistics) {
        final s = StatisticsEngine.oneVariable(<Decimal>[for (final v in data) Dec.parse(v)]);
        final what = 'data $data';
        expect(s.n, int.parse(expected[0]), reason: what);
        final actual = <Decimal?>[
          s.sum,
          s.sumOfSquares,
          s.mean,
          s.populationVariance,
          s.populationStdDev,
          s.sampleVariance,
          s.sampleStdDev,
          s.min,
          s.max,
          s.median,
          s.q1,
          s.q3,
        ];
        const names = <String>['Σx', 'Σx²', 'mean', 'σ²', 'σ', 's²', 's', 'min', 'max', 'median', 'Q1', 'Q3'];
        for (var i = 0; i < actual.length; i++) {
          final reference = expected[i + 1];
          if (reference == 'null') {
            expect(actual[i], isNull, reason: '${names[i]}, $what');
          } else {
            expect(actual[i], isNotNull, reason: '${names[i]}, $what');
            expect(actual[i], agreesWith(reference), reason: '${names[i]}, $what');
          }
        }
      }
    });

    test('linear regression', () {
      for (final (xs, ys, expected) in referenceRegressions) {
        final t = StatisticsEngine.twoVariable(
          <Decimal>[for (final v in xs) Dec.parse(v)],
          <Decimal>[for (final v in ys) Dec.parse(v)],
        );
        final what = 'x $xs, y $ys';
        expect(t.sumOfProducts, agreesWith(expected[0]), reason: 'Σxy, $what');
        expect(t.covariance, agreesWith(expected[1]), reason: 'covariance, $what');
        expect(t.slope, agreesWith(expected[2]), reason: 'slope, $what');
        expect(t.intercept, agreesWith(expected[3]), reason: 'intercept, $what');
        expect(t.correlation, agreesWith(expected[4]), reason: 'r, $what');
      }
    });
  });

  group('Lab: Base-N', () {
    test('arithmetic and bit operations wrap like a register of the word size', () {
      for (final (bits, isSigned, expression, word, number) in referenceBaseN) {
        final context = MathContext(baseN: BaseNConfig(radix: 16, wordSize: bits, isSigned: isSigned));
        final result = MathEngine.evaluateText(expression, context: context);
        final what = '$expression ($bits bits, ${isSigned ? 'signed' : 'unsigned'})';
        expect(result.primary, word, reason: what);
        expect((result.value as BitwiseVal).numericValue.toString(), number, reason: what);
      }
    });

    test('a word reads the same in all four bases', () {
      for (final (bits, hex, unsigned, signed, octal, binary) in referenceBases) {
        final word = BaseN.parse(hex, BaseNConfig(radix: 16, wordSize: bits, isSigned: false));
        final what = '$hex ($bits bits)';
        expect(NumberFormatter.formatBitwise(word, radix: 10), unsigned, reason: what);
        expect(NumberFormatter.formatBitwise(word, radix: 8), octal, reason: what);
        expect(NumberFormatter.formatBitwise(word, radix: 2), binary, reason: what);
        expect(NumberFormatter.formatBitwise(word, radix: 16), hex, reason: what);
        final asSigned = BaseN.convert(word, BaseNConfig(wordSize: bits, isSigned: true));
        expect(asSigned.numericValue.toString(), signed, reason: what);
        // And back again from each base.
        for (final (radix, text) in <(int, String)>[(10, unsigned), (8, octal), (2, binary)]) {
          final parsed = BaseN.parse(text, BaseNConfig(radix: radix, wordSize: bits, isSigned: false));
          expect(parsed.bits, word.bits, reason: '$what from base $radix');
        }
      }
    });
  });

  group('Lab: table', () {
    test('values of f(x)', () {
      for (final (function, unit, start, end, step, values) in referenceTables) {
        final rows = FunctionTableEngine.generate(
          function: ClipboardSanitizer.toSequence(function),
          start: Dec.parse(start),
          end: Dec.parse(end),
          step: Dec.parse(step),
          context: MathContext(angleUnit: AngleUnit.values.byName(unit)),
        );
        expect(rows.length, values.length, reason: function);
        for (var i = 0; i < values.length; i++) {
          final shown = rows[i].value;
          expect(shown, isNotNull, reason: '$function at x = ${rows[i].x}: ${rows[i].error}');
          final value = MathEngine.evaluateText(shown!.replaceAll('e', 'E')).value.asDecimal;
          expect(value, agreesWith(values[i], digits: 11), reason: '$function at x = ${rows[i].x}');
        }
      }
    });
  });
}
