// The 24 mandatory verification cases of the architecture blueprint (§9).
//
// Pure Dart: run with
//   dart test test/domain/engine_verification_test.dart --plain-name "MathEngine"   (TC-01 … TC-20)
//   dart test test/domain/engine_verification_test.dart                             (TC-01 … TC-24)
import 'package:modern_scientific_calculator/domain/compiler/tree_to_token_lowerer.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/clipboard_sanitizer.dart';
import 'package:modern_scientific_calculator/domain/editor/input_phase.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/evaluator/cancellation_token.dart';
import 'package:modern_scientific_calculator/domain/evaluator/number_formatter.dart';
import 'package:modern_scientific_calculator/domain/math_engine.dart';
import 'package:modern_scientific_calculator/domain/models/calc_error.dart';
import 'package:modern_scientific_calculator/domain/models/calc_value.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/domain/models/math_context.dart';
import 'package:rational/rational.dart';
import 'package:test/test.dart';

const MathContext deg = MathContext();
const MathContext rad = MathContext(angleUnit: AngleUnit.rad);
const MathContext radComplex = MathContext(angleUnit: AngleUnit.rad, complexMode: ComplexMode.complex);
const MathContext casio = MathContext(juxtaposition: JuxtapositionMode.strictCasio);

/// Primary display string of [expression].
String calc(String expression, [MathContext context = deg]) =>
    MathEngine.evaluateText(expression, context: context).primary;

EvaluationResult eval(String expression, [MathContext context = deg]) =>
    MathEngine.evaluateText(expression, context: context);

AtomKey digit(String d) => AtomKey(d, AtomKind.digit);
AtomKey op(String o) => AtomKey(o, AtomKind.binaryOp);

/// Types [keys] into [session].
EditingSession type(EditingSession session, List<CalcKey> keys) => keys.fold(session, InputPhaseMachine.press);

void main() {
  group('MathEngine', () {
    test('TC-01 decimal precision: 0.1 + 0.2 = 0.3', () {
      expect(calc('0.1 + 0.2'), '0.3');
    });

    test('TC-02 cancellation guard: (1 + 10^-25) - 1 = 1e-25', () {
      expect(calc('(1 + 10^-25) - 1'), '1e-25');
    });

    test('TC-03 precedence: -3^2 = -9 and (-3)^2 = 9', () {
      expect(calc('-3^2'), '-9');
      expect(calc('(-3)^2'), '9');
    });

    test('TC-04 right-associativity: 2^3^2 = 512', () {
      expect(calc('2^3^2'), '512');
    });

    test('TC-05 implicit multiplication: 1 ÷ 2π with 34 digits', () {
      expect(calc('1 ÷ 2π'), '0.1591549430918953357688837633725144');
    });

    test('TC-06 cardinal trig zero: sin(180°) = 0 and cos(90°) = 0', () {
      expect(calc('sin(180°)'), '0');
      expect(calc('cos(90°)'), '0');
      // The same angles entered as plain numbers in DEG mode.
      expect(calc('sin(180)'), '0');
      expect(calc('cos(90)'), '0');
    });

    test('TC-07 trig asymptote: tan(90°) is a DomainError', () {
      expect(() => calc('tan(90°)'), throwsA(isA<DomainError>()));
      expect(
        () => calc('tan(90°)'),
        throwsA(isA<DomainError>().having((e) => e.message, 'message', 'Undefined asymptote')),
      );
    });

    test('TC-08 high-precision transcendentals: ln(e^5) = 5 and (2^√2)^√2 = 4', () {
      expect(calc('ln(e^5)'), '5');
      expect(calc('(2^√2)^√2'), '4');
    });

    test('TC-09 additive percentage: 200 + 15% = 230 and 200 × 15% = 30', () {
      expect(calc('200 + 15%'), '230');
      expect(calc('200 × 15%'), '30');
    });

    test('TC-10 rational exactness: 1/3 + 1/6 = 1/2 (0.5)', () {
      final result = eval('1/3 + 1/6');
      expect(result.value, isA<RationalVal>());
      expect((result.value as RationalVal).value, Rational.fromInt(1, 2));
      expect(result.secondary, '1/2');
      expect(result.primary, '0.5');
    });

    test('TC-11 rational ceiling: denominator > 2^2048 plus 1/3 falls back to DecimalVal', () {
      final huge = RationalVal(Rational(BigInt.one, (BigInt.one << 2049) + BigInt.one));
      final third = RationalVal(Rational.fromInt(1, 3));
      final sum = huge.plus(third);
      expect(sum, isA<DecimalVal>());
      expect(NumberFormatter.formatValue(sum), '0.3333333333333333333333333333333333');
      // Every exact operation is guarded, and small fractions stay exact.
      expect(huge.times(third), isA<DecimalVal>());
      expect(huge.minus(third), isA<DecimalVal>());
      expect(huge.dividedBy(RationalVal(Rational.fromInt(1, 5))), isA<DecimalVal>());
      expect(third.plus(third), isA<RationalVal>());
      // Reached through the evaluator as well: the common denominator of the
      // two fractions needs about 2900 bits.
      expect(eval('1/(2^1500+1) + 1/3^900').value, isA<DecimalVal>());
    });

    test('TC-12 complex arithmetic: √(-4) × (1 + 2i) = -4 + 2i', () {
      expect(calc('√(-4) × (1 + 2i)', radComplex), '-4 + 2i');
    });

    test("TC-13 Euler's identity: e^(i × π) + 1 = 0 + 0i", () {
      expect(calc('e^(i × π) + 1', radComplex), '0 + 0i');
    });

    test('TC-14 gamma / non-integer factorial: 0.5! and 1.5! (Spouge)', () {
      expect(calc('0.5!'), '0.886226925452758');
      expect(calc('1.5!'), '1.32934038817914');
    });

    test('TC-15 giant factorial: 5000! by the log-Stirling series', () {
      expect(calc('5000!'), '4.2285779266 × 10^16325');
    });

    test('TC-16 numerical derivative: d/dx(x^3 - 4x, x=2) = 8', () {
      expect(calc('d/dx(x^3 - 4x, x=2)'), '8');
    });

    test('TC-17 cusp derivative guard: d/dx(|x|, x=0) is a DomainError', () {
      expect(() => calc('d/dx(|x|, x=0)'), throwsA(isA<DomainError>()));
    });

    test('TC-18 definite integral: ∫(0, π, sin(x)) = 2 in RAD', () {
      expect(calc('∫(0, π, sin(x))', rad), '2');
    });

    test('TC-19 singular endpoint integral: ∫(0, 1, 1/√x) = 2', () {
      expect(calc('∫(0, 1, 1/√x)'), '2');
    });

    test('TC-20 large-angle reduction: sin(10^20 rad) = -0.64525128526578', () {
      final value = eval('sin(10^20)', rad).value;
      // The blueprint quotes 14 significant digits …
      expect(NumberFormatter.formatValue(value, prec: 14), '-0.64525128526578');
      // … and the full 34-digit read-out keeps the complete radian phase.
      expect(NumberFormatter.formatValue(value), '-0.645251285265780844205811711312523');
    });
  });

  group('Editor pipeline', () {
    test('TC-21 implicit multiplication setting: 6 ÷ 2(1+2) is 9 (standard) vs 1 (Casio)', () {
      expect(calc('6 ÷ 2(1+2)'), '9');
      expect(calc('6 ÷ 2(1+2)', casio), '1');
    });

    test('TC-22 2D tree navigation: Fraction → 1 → ▼ → 2 → ▶ → +3 gives ((1)/(2))+3 = 3.5', () {
      final session = type(EditingSession.empty(), <CalcKey>[
        const TemplateKey(TemplateKind.fraction),
        digit('1'),
        const MoveKey(CursorDirection.down),
        digit('2'),
        const MoveKey(CursorDirection.right),
        op('+'),
        digit('3'),
      ]);
      final root = session.editor.root;
      expect(root.children.first, isA<FractionNode>());
      expect(session.editor.cursor.depth, 1, reason: 'the caret left the fraction');
      expect(TreeToTokenLowerer.toText(root), '((1)/(2))+3');
      expect(MathEngine.evaluateSequence(root).primary, '3.5');
    });

    test('TC-23 post-commit Ans: 50 = + 10 gives 60, 50 = 7 gives 7', () {
      EditingSession commit(EditingSession s, Map<String, CalcValue> variables) {
        variables['Ans'] = MathEngine.evaluateSequence(s.editor.root, variables: variables).value;
        return InputPhaseMachine.committed(s);
      }

      // 50 = + 10 =
      final variables = <String, CalcValue>{'Ans': Values.zero};
      var session = commit(type(EditingSession.empty(), <CalcKey>[digit('5'), digit('0')]), variables);
      expect(session.phase, InputPhase.committedResult);
      session = type(session, <CalcKey>[op('+')]);
      expect(session.phase, InputPhase.editing);
      expect(TreeToTokenLowerer.toText(session.editor.root), 'Ans+');
      session = type(session, <CalcKey>[digit('1'), digit('0')]);
      expect(MathEngine.evaluateSequence(session.editor.root, variables: variables).primary, '60');

      // 50 = 7 =
      final fresh = <String, CalcValue>{'Ans': Values.zero};
      session = commit(type(EditingSession.empty(), <CalcKey>[digit('5'), digit('0')]), fresh);
      session = type(session, <CalcKey>[digit('7')]);
      expect(session.phase, InputPhase.editing);
      expect(TreeToTokenLowerer.toText(session.editor.root), '7');
      expect(MathEngine.evaluateSequence(session.editor.root, variables: fresh).primary, '7');

      // ◀ keeps the committed expression for in-place editing.
      session = commit(type(EditingSession.empty(), <CalcKey>[digit('5'), digit('0')]), fresh);
      session = type(session, <CalcKey>[const MoveKey(CursorDirection.left)]);
      expect(session.phase, InputPhase.editing);
      expect(TreeToTokenLowerer.toText(session.editor.root), '50');
    });

    test('TC-24 clipboard and cancellation: paste "1,250.50 × 2³ − √16" = 10000, timeout cancels', () {
      final pasted = ClipboardSanitizer.sanitize('1,250.50 × 2³ − √16');
      expect(pasted.whereType<AtomNode>().any((a) => a.text == ','), isFalse, reason: 'commas are stripped');
      expect(pasted.whereType<PowerNode>(), hasLength(1));
      expect(pasted.whereType<RootNode>(), hasLength(1));
      final editor = MathPrintController.insert(EditorState.empty(), pasted);
      expect(TreeToTokenLowerer.toText(editor.root), '1250.50×2^(3)−√(16)');
      expect(MathEngine.evaluateSequence(editor.root).primary, '10000');

      // A budget that is already used up trips at the first cooperative check.
      expect(
        () => MathEngine.evaluateText('2500!', token: CancellationToken(timeout: Duration.zero)),
        throwsA(isA<CancelledEvaluationError>()),
      );
      // A newer keystroke (generation) makes the running evaluation obsolete.
      var latestGeneration = 1;
      final token = CancellationToken(generationId: 1, latestGeneration: () => latestGeneration);
      expect(MathEngine.evaluateText('2500!', token: token).value, isA<DecimalVal>());
      latestGeneration = 2;
      expect(
        () => MathEngine.evaluateText('∫(0, 1, x^2)', token: token),
        throwsA(isA<CancelledEvaluationError>()),
      );
    });
  });

  group('Performance budget', () {
    test('the 24 verification cases evaluate in under 50 ms', () {
      void evaluateAll() {
        calc('0.1 + 0.2');
        calc('(1 + 10^-25) - 1');
        calc('-3^2');
        calc('(-3)^2');
        calc('2^3^2');
        calc('1 ÷ 2π');
        calc('sin(180°)');
        calc('cos(90°)');
        try {
          calc('tan(90°)');
        } on DomainError {
          // expected
        }
        calc('ln(e^5)');
        calc('(2^√2)^√2');
        calc('200 + 15%');
        calc('200 × 15%');
        calc('1/3 + 1/6');
        RationalVal(Rational(BigInt.one, (BigInt.one << 2049) + BigInt.one)).plus(RationalVal(Rational.fromInt(1, 3)));
        calc('√(-4) × (1 + 2i)', radComplex);
        calc('e^(i × π) + 1', radComplex);
        calc('0.5!');
        calc('1.5!');
        calc('5000!');
        calc('d/dx(x^3 - 4x, x=2)');
        try {
          calc('d/dx(|x|, x=0)');
        } on DomainError {
          // expected
        }
        calc('∫(0, π, sin(x))', rad);
        calc('∫(0, 1, 1/√x)');
        calc('sin(10^20)', rad);
        calc('6 ÷ 2(1+2)');
        calc('6 ÷ 2(1+2)', casio);
        calc('((1)/(2))+3');
        calc('50+10');
        calc('1,250.50 × 2³ − √16');
      }

      // Let the JIT settle, then keep the best of several timed passes so a
      // busy CI machine cannot produce a false alarm.
      for (var i = 0; i < 20; i++) {
        evaluateAll();
      }
      var best = const Duration(days: 1);
      for (var i = 0; i < 10; i++) {
        final clock = Stopwatch()..start();
        evaluateAll();
        clock.stop();
        if (clock.elapsed < best) best = clock.elapsed;
      }
      // ignore: avoid_print
      print('24-case pass: ${best.inMicroseconds / 1000} ms');
      expect(best.inMilliseconds, lessThan(50));
    });
  });

  test('working and display precision constants match the blueprint', () {
    expect(WORK_PREC, 50);
    expect(DISP_PREC, 34);
    expect(MAX_TREE_DEPTH, 4);
    expect(kRationalBitCeiling, 2048);
  });
}
