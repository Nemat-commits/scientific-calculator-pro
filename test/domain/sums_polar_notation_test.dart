// Σ, Π, mixed fractions, the polar form, Rand, engineering notation and the
// variables an expression depends on (what CALC asks for).
import 'dart:math' as math;

import 'package:modern_scientific_calculator/domain/compiler/tree_to_token_lowerer.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/clipboard_sanitizer.dart';
import 'package:modern_scientific_calculator/domain/editor/expression_variables.dart';
import 'package:modern_scientific_calculator/domain/editor/input_phase.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/evaluator/number_formatter.dart';
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
const AtomKey x = AtomKey('x', AtomKind.variable);
const MoveKey right = MoveKey(CursorDirection.right);
const TemplateKey mixed = TemplateKey(TemplateKind.mixedFraction);

EditorSequence typed(List<CalcKey> keys) => keys.fold(EditorState.empty(), InputPhaseMachine.applyToEditor).root;

/// A source of random numbers that hands out [draws] in turn.
class Scripted implements math.Random {
  Scripted(this.draws);

  final List<int> draws;
  int taken = 0;

  @override
  int nextInt(int max) => draws[taken++ % draws.length] % max;

  @override
  double nextDouble() => throw UnsupportedError('nextDouble');

  @override
  bool nextBool() => throw UnsupportedError('nextBool');
}

Matcher failsWith<T extends CalcError>(String message) =>
    throwsA(isA<T>().having((e) => e.message, 'message', contains(message)));

void main() {
  group('Σ and Π', () {
    test('add up and multiply the term for every whole number of the range', () {
      expect(calc('Σ(1,10,x)'), '55');
      expect(calc('Σ(1,10,x^2)'), '385');
      expect(calc('Σ(1,100,x)'), '5050');
      expect(calc('Π(1,5,x)'), '120');
      expect(calc('Π(1,10,(x+1)/x)'), '11'); // telescopes to 11/1
      expect(calc('Σ(0,4,2^x)'), '31');
      expect(calc('Σ(−2,2,x^2)'), '10');
    });

    test('stay exact where the terms are fractions', () {
      final harmonic = MathEngine.evaluateText('Σ(1,10,1/x)');
      expect(harmonic.primary, '2.928968253968253968253968253968254');
      expect(harmonic.secondary, '7381/2520');
      // 20 terms of the series of e agree with e to 19 digits.
      expect(calc('Σ(0,20,1/x!)'), startsWith('2.718281828459045235'));
    });

    test('an empty range gives the neutral element', () {
      expect(calc('Σ(5,1,x)'), '0');
      expect(calc('Π(5,1,x)'), '1');
      expect(calc('Σ(3,3,x)'), '3');
    });

    test('nest, and take part in an expression like any other operand', () {
      expect(calc('Σ(1,3,Σ(1,x,x))'), '10'); // 1 + 3 + 6
      expect(calc('Σ(1,3,∫(0,x,x^2))'), '12'); // (1 + 8 + 27) / 3
      expect(calc('2Σ(1,3,x)+1'), '13');
      expect(calc('Σ(1,4,x)^2'), '100');
      expect(calc('Π(1,3,Σ(1,x,x))'), '18'); // 1 · 3 · 6
    });

    test('the running x is that of the sum, not the stored one', () {
      final variables = <String, CalcValue>{'x': MathEngine.evaluateText('100').value};
      expect(MathEngine.evaluateText('Σ(1,3,x)', variables: variables).primary, '6');
      expect(MathEngine.evaluateText('Σ(1,3,x)+x', variables: variables).primary, '106');
      expect(MathEngine.evaluateText('Σ(1,x/50,x)', variables: variables).primary, '3'); // the bounds see the stored x
    });

    test('count in whole numbers and refuse a range that is too long', () {
      expect(() => calc('Σ(1,2.5,x)'), failsWith<DomainError>('whole numbers'));
      expect(() => calc('Π(0.5,3,x)'), failsWith<DomainError>('whole numbers'));
      expect(() => calc('Σ(1,100000000,x)'), failsWith<DomainError>('too many terms'));
    });

    test('are typed as templates and written as Σ( … ) in the linear form', () {
      final sum = typed(<CalcKey>[
        const TemplateKey(TemplateKind.summation),
        digit('1'),
        right,
        digit('1'),
        digit('0'),
        right,
        x,
        const TemplateKey(TemplateKind.square),
      ]);
      expect(TreeToTokenLowerer.toText(sum), 'Σ(1,10,x^(2))');
      expect(TreeToTokenLowerer.toDisplayText(sum), 'Σ(1,10,x^2)');
      expect(MathEngine.evaluateSequence(sum).primary, '385');

      final product =
          typed(<CalcKey>[const TemplateKey(TemplateKind.product), digit('1'), right, digit('5'), right, x]);
      expect(TreeToTokenLowerer.toText(product), 'Π(1,5,x)');
      expect(MathEngine.evaluateSequence(product).primary, '120');

      // A stored expression comes back as the same template.
      final restored = EditorSequence.fromJson(sum.toJson());
      expect(restored.toString(), sum.toString());
      expect(MathEngine.evaluateSequence(restored).primary, '385');
      expect(EditorSequence.fromJson(product.toJson()).toString(), product.toString());
    });

    test('pasted text may spell them out', () {
      expect(calc('sum(1,100,x)'), '5050');
      expect(calc('prod(1,6,x)'), '720');
      expect(TreeToTokenLowerer.toText(ClipboardSanitizer.toSequence('sum(1,4,x)')), 'Σ(1,4,x)');
    });
  });

  group('mixed fractions', () {
    EditorSequence twoAndAThird({List<CalcKey> before = const <CalcKey>[], List<CalcKey> sign = const <CalcKey>[]}) =>
        typed(<CalcKey>[...before, mixed, ...sign, digit('2'), right, digit('1'), right, digit('3')]);

    test('are the whole part plus the fraction', () {
      final root = twoAndAThird();
      expect(TreeToTokenLowerer.toText(root), '((2)+(1)/(3))');
      expect(TreeToTokenLowerer.toDisplayText(root), '2+1/3');
      final result = MathEngine.evaluateSequence(root);
      expect(result.primary, '2.333333333333333333333333333333333');
      expect(result.secondary, '7/3');
    });

    test('act as one operand', () {
      final sum = typed(<CalcKey>[
        mixed, digit('2'), right, digit('1'), right, digit('3'), right, //
        op('+'), mixed, digit('1'), right, digit('1'), right, digit('6'), right,
        op('×'), digit('2'),
      ]);
      // 2 1/3 + 1 1/6 × 2 = 7/3 + 7/3
      expect(MathEngine.evaluateSequence(sum).secondary, '14/3');
    });

    test('a sign is the sign of the whole mixed number', () {
      // −2 1/3 is −(2 + 1/3) = −7/3, wherever the sign was typed.
      final inFront = twoAndAThird(before: <CalcKey>[op('−')]);
      final inside = twoAndAThird(sign: <CalcKey>[op('−')]);
      expect(MathEngine.evaluateSequence(inFront).secondary, '-7/3');
      expect(MathEngine.evaluateSequence(inside).secondary, '-7/3');
      expect(TreeToTokenLowerer.toDisplayText(inside), '−(2+1/3)');
      final times =
          typed(<CalcKey>[digit('3'), op('×'), mixed, op('−'), digit('2'), right, digit('1'), right, digit('3')]);
      expect(MathEngine.evaluateSequence(times).primary, '-7');
    });

    test('an empty whole part is an error and not a zero', () {
      final root = typed(<CalcKey>[mixed, right, digit('1'), right, digit('3')]);
      expect(() => MathEngine.evaluateSequence(root), throwsA(isA<SyntaxError>()));
    });

    test('survive being stored', () {
      final root = twoAndAThird();
      final restored = EditorSequence.fromJson(root.toJson());
      expect(restored.toString(), root.toString());
      expect((restored.children.single as FractionNode).isMixed, isTrue);
      // A plain fraction stays a plain fraction.
      final plain = typed(<CalcKey>[const TemplateKey(TemplateKind.fraction), digit('1'), right, digit('2')]);
      expect((EditorSequence.fromJson(plain.toJson()).children.single as FractionNode).isMixed, isFalse);
    });
  });

  group('polar form', () {
    const rad = MathContext(angleUnit: AngleUnit.rad);
    const grad = MathContext(angleUnit: AngleUnit.grad);

    test('r∠θ is r·(cos θ + i·sin θ) in the angle unit', () {
      expect(calc('1∠90'), '0 + 1i');
      expect(calc('2∠0'), '2 + 0i');
      expect(calc('5∠−90'), '0 - 5i');
      expect(calc('2∠30'), '1.732050807568877293527446341505872 + 1i');
      expect(calc('2∠60'), '1 + 1.732050807568877293527446341505872i');
      expect(calc('1∠(π/2)', rad), '0 + 1i');
      expect(calc('1∠100', grad), '0 + 1i');
    });

    test('binds tighter than the arithmetic around it', () {
      expect(calc('(1∠90)^2'), '-1 + 0i');
      expect(calc('1∠90×2'), '0 + 2i');
      expect(calc('1∠90+1∠0'), '1 + 1i');
      expect(calc('−2∠180'), '2 + 0i'); // −(2∠180)
      expect(calc('10∠90÷(5∠45)'), startsWith('1.41421356237309504880168872420969'));
    });

    test('abs and arg take it apart again', () {
      expect(calc('abs(3∠40)'), '3');
      expect(calc('arg(3∠40)'), '40');
      expect(calc('arg(2∠1.25)', rad), '1.25');
    });

    test('a long complex result has a short form of ten digits', () {
      final result = MathEngine.evaluateText('2∠30');
      expect(result.secondary, '1.732050808 + 1i');
      expect(MathEngine.evaluateText('1∠90').secondary, isNull, reason: 'nothing to shorten');
    });
  });

  group('Rand', () {
    test('is a number from 0 up to 1 with ten decimals', () {
      expect(MathEngine.evaluateText('Rand', random: Scripted(<int>[12, 34567])).primary, '0.0001234567');
      expect(MathEngine.evaluateText('Rand', random: Scripted(<int>[0, 0])).primary, '0');
      expect(MathEngine.evaluateText('Rand', random: Scripted(<int>[99999, 99999])).primary, '0.9999999999');
      for (var i = 0; i < 200; i++) {
        final value = double.parse(calc('Rand'));
        expect(value, inInclusiveRange(0, 0.9999999999));
      }
    });

    test('every Rand of an expression is a number of its own', () {
      // 0.5 − 0.25, not 0.5 − 0.5.
      expect(
        MathEngine.evaluateText('Rand−Rand', random: Scripted(<int>[50000, 0, 25000, 0])).primary,
        '0.25',
      );
      expect(MathEngine.evaluateText('Σ(1,4,Rand)', random: Scripted(<int>[25000, 0])).primary, '1');
    });

    test('takes part in arithmetic', () {
      // A die: 1 + floor(6 · 0.5)
      expect(MathEngine.evaluateText('floor(Rand×6)+1', random: Scripted(<int>[50000, 0])).primary, '4');
      expect(MathEngine.evaluateText('2Rand', random: Scripted(<int>[25000, 0])).primary, '0.5');
      expect(MathEngine.evaluateText('rand()', random: Scripted(<int>[25000, 0])).primary, '0.25');
    });
  });

  group('engineering notation', () {
    const eng = MathContext(notation: NotationMode.engineering);

    test('writes the exponent in steps of three', () {
      expect(calc('12345', eng), '12.345e3');
      expect(calc('1000', eng), '1e3');
      expect(calc('123456789×1000', eng), '123.456789e9');
      expect(calc('1E20', eng), '100e18');
      expect(calc('0.5', eng), '500e-3');
      expect(calc('0.00012', eng), '120e-6');
      expect(calc('−4700', eng), '-4.7e3');
    });

    test('leaves numbers from 1 up to 1000 as they are', () {
      expect(calc('42', eng), '42');
      expect(calc('999', eng), '999');
      expect(calc('1.5', eng), '1.5');
      expect(calc('0', eng), '0');
    });

    test('keeps the plain number or the fraction as the second read-out', () {
      expect(MathEngine.evaluateText('12345', context: eng).secondary, '12345');
      expect(MathEngine.evaluateText('0.5', context: eng).secondary, '1/2');
      expect(MathEngine.evaluateText('42', context: eng).secondary, isNull);
    });

    test('is a way of writing: the value is the same', () {
      final plain = MathEngine.evaluateText('12345×67');
      final engineering = MathEngine.evaluateText('12345×67', context: eng);
      expect(engineering.primary, '827.115e3');
      expect(CalcValueCodec.encode(engineering.value), CalcValueCodec.encode(plain.value));
      expect(NumberFormatter.formatValue(plain.value, notation: NotationMode.engineering), '827.115e3');
    });
  });

  group('the variables an expression depends on', () {
    List<String> free(String expression) => ExpressionVariables.free(ClipboardSanitizer.toSequence(expression));

    test('are listed in the order they appear, each once', () {
      expect(free('x^2+y'), <String>['x', 'y']);
      expect(free('sin(x)/y+x'), <String>['x', 'y']);
      expect(free('A×B+C'), <String>['A', 'B', 'C']);
      expect(free('2+3'), isEmpty);
    });

    test('Ans is not a variable to ask for; the memory M is one of the letters', () {
      expect(free('A×B+Ans'), <String>['A', 'B']);
      expect(free('Ans^2'), isEmpty);
      expect(free('A×B+Ans+M'), <String>['A', 'B', 'M']);
    });

    test('the running variable of a template is not one of them', () {
      expect(free('∫(0,a,x^2)'), <String>['a']);
      expect(free('Σ(1,n,x)'), <String>['n']);
      expect(free('Σ(1,n,x)+x'), <String>['n', 'x'], reason: 'the x outside the sum is free');
      expect(free('Π(1,5,x×k)'), <String>['k']);
      expect(free('d/dx(x^2, x=t)'), <String>['t']);
    });

    test('are found inside templates', () {
      final root = typed(<CalcKey>[
        const TemplateKey(TemplateKind.fraction),
        x,
        right,
        const AtomKey('y', AtomKind.variable),
        right,
        op('+'),
        const TemplateKey(TemplateKind.squareRoot),
        const AtomKey('A', AtomKind.variable),
      ]);
      expect(ExpressionVariables.free(root), <String>['x', 'y', 'A']);
    });

    test('mentions finds an atom at any depth', () {
      final root = typed(<CalcKey>[
        const TemplateKey(TemplateKind.squareRoot),
        const AtomKey('Rand', AtomKind.constant),
      ]);
      expect(ExpressionVariables.mentions(root, 'Rand'), isTrue);
      expect(ExpressionVariables.mentions(typed(<CalcKey>[digit('1')]), 'Rand'), isFalse);
    });
  });
}
