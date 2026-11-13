// Behavioural tests of the pure-Dart domain beyond the 24 blueprint cases.
import 'package:decimal/decimal.dart';
import 'package:modern_scientific_calculator/core/constants/unit_definitions.dart';
import 'package:modern_scientific_calculator/domain/compiler/tree_to_token_lowerer.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/clipboard_sanitizer.dart';
import 'package:modern_scientific_calculator/domain/editor/cursor_path.dart';
import 'package:modern_scientific_calculator/domain/editor/input_phase.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/evaluator/algebra_solver_engine.dart';
import 'package:modern_scientific_calculator/domain/evaluator/decimal_math.dart';
import 'package:modern_scientific_calculator/domain/evaluator/number_formatter.dart';
import 'package:modern_scientific_calculator/domain/evaluator/unit_converter_engine.dart';
import 'package:modern_scientific_calculator/domain/math_engine.dart';
import 'package:modern_scientific_calculator/domain/models/calc_error.dart';
import 'package:modern_scientific_calculator/domain/models/calc_value.dart';
import 'package:modern_scientific_calculator/domain/models/calc_value_codec.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/domain/models/math_context.dart';
import 'package:test/test.dart';

String calc(String expression, [MathContext context = const MathContext()]) =>
    MathEngine.evaluateText(expression, context: context).primary;

AtomKey digit(String d) => AtomKey(d, AtomKind.digit);
AtomKey op(String o) => AtomKey(o, AtomKind.binaryOp);
const MoveKey left = MoveKey(CursorDirection.left);
const MoveKey right = MoveKey(CursorDirection.right);
const MoveKey up = MoveKey(CursorDirection.up);
const MoveKey down = MoveKey(CursorDirection.down);

EditorState keys(List<CalcKey> sequence, [EditorState? start]) =>
    sequence.fold(start ?? EditorState.empty(), InputPhaseMachine.applyToEditor);

String text(EditorState s) => TreeToTokenLowerer.toText(s.root);

void main() {
  group('Number formatting', () {
    test('whole numbers keep their zeros', () {
      expect(calc('30.00'), '30');
      expect(calc('10000.00'), '10000');
      expect(calc('2^64'), '18446744073709551616');
      expect(calc('20!'), '2432902008176640000');
    });

    test('small and large magnitudes switch to scientific notation', () {
      expect(calc('1/10^25'), '1e-25');
      expect(calc('1.5×10^-9'), '1.5e-9');
      expect(calc('0.0000001'), '0.0000001');
      expect(calc('35!'), '1.03331479663861449296666513375232e40');
    });

    test('half-even rounding at 34 significant digits', () {
      expect(calc('2/3'), '0.6666666666666666666666666666666667');
      expect(calc('1/3'), '0.3333333333333333333333333333333333');
    });

    test('secondary read-outs: fraction and engineering notation', () {
      expect(MathEngine.evaluateText('7/2').secondary, '7/2');
      expect(MathEngine.evaluateText('4/2').secondary, isNull);
      expect(MathEngine.evaluateText('π×10^-8').secondary, startsWith('31.4159'));
    });

    test('thousands grouping is a pure presentation helper', () {
      expect(NumberFormatter.groupThousands('1234567.891234'), '1,234,567.891234');
      expect(NumberFormatter.groupThousands('-1234 + 5678901i'), '-1,234 + 5,678,901i');
      expect(NumberFormatter.groupThousands('4.2285779266 × 10^16325'), '4.2285779266 × 10^16325');
      expect(NumberFormatter.groupThousands('1.5e-12345'), '1.5e-12345');
    });
  });

  group('Arithmetic semantics', () {
    test('exact rationals and zero snap', () {
      expect(calc('0.1+0.2-0.3'), '0');
      expect(calc('log(1000)-3'), '0');
      expect(calc('sin(30)+cos(60)'), '1');
      expect(calc('√(1/4)+8^(1/3)'), '2.5');
      expect(calc('(-8)^(1/3)'), '-2');
      expect(calc('5000!/4999!'), '5000');
    });

    test('percent, modulo and counting functions', () {
      expect(calc('100 - 10%'), '90');
      expect(calc('50%'), '0.5');
      expect(calc('7 mod 3 + mod(-7,3)'), '3');
      expect(calc('nCr(52,5)'), '2598960');
      expect(calc('nPr(10,3)'), '720');
      expect(calc('gcd(84,36)+lcm(4,6)'), '24');
    });

    test('ghost parentheses and implied multiplication', () {
      expect(calc('3(4'), '12');
      expect(calc('2(3+4'), '14');
      expect(calc('2π', const MathContext(angleUnit: AngleUnit.rad)), startsWith('6.28318530717958647692'));
    });

    test('errors are structured', () {
      expect(() => calc('1/0'), throwsA(isA<DivisionByZero>()));
      expect(() => calc('1.2.3'), throwsA(isA<SyntaxError>()));
      expect(() => calc('√(-9)'), throwsA(isA<DomainError>()));
      expect(() => calc('9^9^9'), throwsA(isA<OverflowError>()));
      expect(() => calc('2+'), throwsA(isA<SyntaxError>()));
      expect(() => calc('Q+1'), throwsA(isA<UndefinedVariableError>()));
      expect(() => calc('tan(π/2)', const MathContext(angleUnit: AngleUnit.rad)), throwsA(isA<DomainError>()));
    });

    test('complex mode', () {
      const cplx = MathContext(angleUnit: AngleUnit.rad, complexMode: ComplexMode.complex);
      expect(calc('(1+2i)^2', cplx), '-3 + 4i');
      expect(calc('√(-9)', cplx), '0 + 3i');
      expect(calc('ln(-1)', cplx), '0 + 3.141592653589793238462643383279503i');
      expect(calc('abs(3+4i)', cplx), '5');
    });

    test('angle units', () {
      expect(calc('sin(100)', const MathContext(angleUnit: AngleUnit.grad)), '1');
      expect(calc('asin(1)'), '90');
      expect(calc('atan(1)', const MathContext(angleUnit: AngleUnit.grad)), '50');
      expect(calc('cos(π)', const MathContext(angleUnit: AngleUnit.rad)), '-1');
    });

    test('Base-N words wrap around', () {
      const hex8 = MathContext(baseN: BaseNConfig(radix: 16, wordSize: 8, isSigned: false));
      expect(calc('FF + 1', hex8), '0');
      expect(calc('F0 and 3C', hex8), '30');
      expect(calc('not 0F', hex8), 'F0');
      expect(calc('1 << 7', hex8), '80');
      const dec16 = MathContext(baseN: BaseNConfig(wordSize: 16));
      expect(calc('32767 + 1', dec16), '-32768');
      expect(calc('-7 ÷ 2', dec16), '-3');
    });
  });

  group('MathPrint controller', () {
    test('typing and moving through a fraction', () {
      var s = keys(<CalcKey>[const TemplateKey(TemplateKind.fraction), digit('1'), down, digit('2')]);
      expect(text(s), '((1)/(2))');
      expect(s.cursor.depth, 2);
      s = keys(<CalcKey>[up, digit('5')], s);
      expect(text(s), '((15)/(2))');
      s = keys(<CalcKey>[right, digit('9')], s);
      expect(text(s), '((15)/(92))', reason: '▶ at the end of the numerator enters the denominator');
      s = keys(<CalcKey>[right, right, right, op('+'), digit('1')], s);
      expect(text(s), '((15)/(92))+1');
    });

    test('moveLeft re-enters a template from the right', () {
      var s = keys(<CalcKey>[digit('2'), const TemplateKey(TemplateKind.power), digit('3'), right, op('+')]);
      expect(text(s), '2^(3)+');
      s = keys(<CalcKey>[left, left, digit('4')], s);
      expect(text(s), '2^(34)+');
    });

    test('smart backspace removes an empty template and edits a filled one', () {
      var s = keys(<CalcKey>[digit('7'), const TemplateKey(TemplateKind.fraction)]);
      expect(s.root.children, hasLength(2));
      s = keys(<CalcKey>[const BackspaceKey()], s);
      expect(text(s), '7');
      expect(s.cursor, CursorPath.root(1));

      s = keys(<CalcKey>[const TemplateKey(TemplateKind.fraction), digit('1'), down, digit('2'), digit('3'), right]);
      s = keys(<CalcKey>[const BackspaceKey()], s);
      expect(text(s), '((1)/(23))', reason: 'the first backspace only steps into the fraction');
      s = keys(<CalcKey>[const BackspaceKey()], s);
      expect(text(s), '((1)/(2))');
    });

    test('structural nesting is capped at depth 4', () {
      var s = EditorState.empty();
      for (var i = 0; i < MAX_TREE_DEPTH; i++) {
        s = keys(<CalcKey>[const TemplateKey(TemplateKind.squareRoot)], s);
      }
      expect(MathPrintController.structuralDepth(s), MAX_TREE_DEPTH);
      s = keys(<CalcKey>[const TemplateKey(TemplateKind.fraction)], s);
      expect(MathPrintController.structuralDepth(s), MAX_TREE_DEPTH, reason: 'no fifth level is created');
      final innermost = MathPrintController.currentSequence(s);
      expect(innermost.children.every((n) => n is AtomNode), isTrue);
      expect(innermost.children.map((n) => (n as AtomNode).text).join(), '()÷()');
    });

    test('tap-to-position paths and JSON round trip', () {
      final s = keys(<CalcKey>[const TemplateKey(TemplateKind.fraction), digit('1'), down, digit('2'), right, op('+')]);
      final fraction = s.root.children.first as FractionNode;
      final path = MathPrintController.pathTo(s.root, fraction.denominator.id, 1)!;
      expect(MathPrintController.isValid(s.root, path), isTrue);
      final edited = MathPrintController.insertAtom(EditorState(s.root, path), '5', AtomKind.digit);
      expect(text(edited), '((1)/(25))+');

      final restored = EditorState.fromJson(edited.toJson());
      expect(text(restored), text(edited));
      expect(restored.cursor, edited.cursor);
    });

    test('templates: roots, integral and derivative', () {
      var s = keys(<CalcKey>[const TemplateKey(TemplateKind.nthRoot), digit('3'), right, digit('8')]);
      expect(text(s), 'root(3,8)');
      expect(MathEngine.evaluateSequence(s.root).primary, '2');

      s = keys(<CalcKey>[
        const TemplateKey(TemplateKind.integral),
        digit('0'),
        right,
        digit('1'),
        right,
        const AtomKey('x', AtomKind.variable),
        const TemplateKey(TemplateKind.square),
      ]);
      expect(text(s), '∫(0,1,x^(2))');
      expect(MathEngine.evaluateSequence(s.root).secondary, isNull);
      expect(MathEngine.evaluateSequence(s.root).primary, '0.33333333333333');

      s = keys(<CalcKey>[
        const TemplateKey(TemplateKind.derivative),
        const TemplateKey(TemplateKind.function, name: 'ln'),
        const AtomKey('x', AtomKind.variable),
        right,
        right,
        digit('4'),
      ]);
      expect(text(s), 'd/dx(ln(x),x=4)');
      expect(MathEngine.evaluateSequence(s.root).primary, '0.25');
    });
  });

  group('Clipboard sanitizer', () {
    String linear(String raw) => TreeToTokenLowerer.toText(ClipboardSanitizer.toSequence(raw));

    test('number formats', () {
      expect(linear('1,234,567.89'), '1234567.89');
      expect(linear('1.250.000,5'), '1250000.5');
      expect(linear('3,5'), '3.5');
      expect(linear('max(1,250)'), 'max(1,250)');
      expect(linear('6.02E23'), '6.02E23');
      expect(linear('1e-25'), '1E-25');
    });

    test('operators, superscripts and templates', () {
      expect(linear('2*3/4-1'), '2×3÷4−1');
      expect(linear('x⁻¹ + 10²'), 'x^(−1)+10^(2)');
      expect(linear('2**10'), '2^(10)');
      expect(linear('|x-1|'), 'abs(x−1)');
      expect(linear('sqrt(2)+cbrt(27)'), '√(2)+root(3,27)');
      expect(linear('2+2=4'), '2+2');
      expect(linear('price: 3 €'), '3');
      expect(linear('2xsin(x)'), '2xsin(x)');
      expect(linear('sinx'), 'sin(x)');
    });
  });

  group('Algebra lab engines', () {
    String show(CalcValue v) => NumberFormatter.formatValue(v, prec: 12);

    test('quadratic: exact, irrational and complex roots', () {
      final exact = PolynomialSolver.solve(<CalcValue>[Values.ofInt(2), Values.ofInt(5), Values.ofInt(-3)]);
      expect(exact.roots.map(show).toList(), <String>['-3', '0.5']);
      expect(exact.roots.every((r) => r is RationalVal), isTrue);

      final irrational = PolynomialSolver.solve(<CalcValue>[Values.ofInt(1), Values.ofInt(0), Values.ofInt(-2)]);
      expect(irrational.roots.map(show).toList(), <String>['-1.41421356237', '1.41421356237']);

      final complex = PolynomialSolver.solve(<CalcValue>[Values.ofInt(1), Values.ofInt(2), Values.ofInt(5)]);
      expect(complex.roots.map(show).toList(), <String>['-1 + 2i', '-1 - 2i']);
    });

    test('cubic: three rational roots, one real root, repeated roots', () {
      final three = PolynomialSolver.solve(
        <CalcValue>[Values.ofInt(1), Values.ofInt(-6), Values.ofInt(11), Values.ofInt(-6)],
      );
      expect(three.roots.map(show).toList(), <String>['1', '2', '3']);
      expect(three.roots.every((r) => r is RationalVal), isTrue);

      final one = PolynomialSolver.solve(<CalcValue>[Values.ofInt(1), Values.ofInt(0), Values.ofInt(0), Values.ofInt(-8)]);
      expect(show(one.roots[0]), '2');
      expect(show(one.roots[1]), '-1 + 1.73205080757i');

      final repeated = PolynomialSolver.solve(
        <CalcValue>[Values.ofInt(1), Values.ofInt(-3), Values.ofInt(3), Values.ofInt(-1)],
      );
      expect(repeated.roots.map(show).toList(), <String>['1', '1', '1']);
    });

    test('matrix arithmetic', () {
      MatrixVal m(List<List<int>> rows) => MatrixOps.of(<List<Decimal>>[
            for (final r in rows) <Decimal>[for (final v in r) Dec.fromInt(v)],
          ]);
      final x = m(<List<int>>[
        <int>[2, 1],
        <int>[5, 3],
      ]);
      expect(show(DecimalVal(MatrixOps.determinant(x))), '1');
      expect(show(MatrixOps.inverse(x)), '[[3, -1], [-5, 2]]');
      expect(show(MatrixOps.mul(x, MatrixOps.inverse(x))), '[[1, 0], [0, 1]]');
      expect(show(MatrixOps.transpose(x)), '[[2, 5], [1, 3]]');
      expect(MatrixOps.rank(m(<List<int>>[
        <int>[1, 2],
        <int>[2, 4],
      ])), 1);
      expect(() => MatrixOps.inverse(m(<List<int>>[
            <int>[1, 2],
            <int>[2, 4],
          ])), throwsA(isA<DomainError>()));
      final evaluated = MathEngine.evaluateText('MatA×MatA+MatA', variables: <String, CalcValue>{'MatA': x});
      expect(evaluated.primary, '[[11, 6], [30, 17]]');
    });

    test('statistics and regression', () {
      final data = <int>[2, 4, 4, 4, 5, 5, 7, 9].map(Dec.fromInt).toList();
      final s = StatisticsEngine.oneVariable(data);
      expect(NumberFormatter.formatDec(s.mean), '5');
      expect(NumberFormatter.formatDec(s.populationStdDev), '2');
      expect(NumberFormatter.formatDec(s.median), '4.5');
      final xs = <int>[1, 2, 3, 4].map(Dec.fromInt).toList();
      final ys = <int>[3, 5, 7, 9].map(Dec.fromInt).toList();
      final t = StatisticsEngine.twoVariable(xs, ys);
      expect(NumberFormatter.formatDec(t.slope!), '2');
      expect(NumberFormatter.formatDec(t.intercept!), '1');
      expect(NumberFormatter.formatDec(t.correlation!), '1');
    });

    test('f(x) table', () {
      final rows = FunctionTableEngine.generate(
        function: ClipboardSanitizer.toSequence('1/x'),
        start: Dec.fromInt(-1),
        end: Dec.one,
        step: Dec.one,
      );
      expect(rows.map((r) => r.value ?? r.error).toList(), <String?>['-1', 'Division by zero', '1']);
    });

    test('unit conversion is exact', () {
      final length = UnitDefinitions.category('length');
      final temperature = UnitDefinitions.category('temperature');
      expect(UnitConverterEngine.convertFormatted(Values.ofInt(1), length.unit('mi'), length.unit('km')), '1.609344');
      expect(UnitConverterEngine.convertFormatted(Values.ofInt(12), length.unit('in'), length.unit('ft')), '1');
      expect(
        UnitConverterEngine.convertFormatted(Values.ofInt(100), temperature.unit('c'), temperature.unit('f')),
        '212',
      );
      expect(
        UnitConverterEngine.convertFormatted(Values.ofInt(-40), temperature.unit('f'), temperature.unit('c')),
        '-40',
      );
      expect(UnitDefinitions.categories, hasLength(12));
    });

    test('value codec round-trips every kind of value', () {
      for (final expression in <String>['7/2', '2^0.5', '-3']) {
        final v = MathEngine.evaluateText(expression).value;
        final back = CalcValueCodec.decode(CalcValueCodec.encode(v));
        expect(NumberFormatter.formatValue(back), NumberFormatter.formatValue(v));
        expect(back.runtimeType, v.runtimeType);
      }
      const cplx = MathContext(complexMode: ComplexMode.complex);
      final z = MathEngine.evaluateText('3-4i', context: cplx).value;
      expect(NumberFormatter.formatValue(CalcValueCodec.decode(CalcValueCodec.encode(z))), '3 - 4i');
      expect(CalcValueCodec.decode('0'), isA<RationalVal>());
    });
  });
}
