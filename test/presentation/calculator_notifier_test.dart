import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/data/local_db/draft_state_store.dart';
import 'package:modern_scientific_calculator/data/repositories/calculator_repository.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/math_engine.dart';
import 'package:modern_scientific_calculator/domain/models/calc_value_codec.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_ui_state.dart';

AtomKey digit(String d) => AtomKey(d, AtomKind.digit);
AtomKey op(String o) => AtomKey(o, AtomKind.binaryOp);

/// Lets pending evaluations (plain futures of the in-place evaluator) finish.
Future<void> idle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late ProviderContainer container;
  late CalculatorNotifier calculator;
  CalculatorUiState state() => container.read(calculatorProvider);

  ProviderContainer create({List<Override> overrides = const <Override>[]}) {
    final c = ProviderContainer(overrides: overrides);
    addTearDown(c.dispose);
    return c;
  }

  void type(List<CalcKey> keys) => keys.forEach(calculator.press);

  setUp(() {
    container = create();
    calculator = container.read(calculatorProvider.notifier);
  });

  group('live preview', () {
    test('follows the expression while typing', () async {
      type(<CalcKey>[digit('1'), op('+'), digit('2')]);
      await idle();
      expect(state().inputPhase, InputPhase.editing);
      expect(state().livePreviewPrimary, '3');
    });

    test('is hidden for a bare number and for incomplete input', () async {
      type(<CalcKey>[digit('4'), digit('2')]);
      await idle();
      expect(state().livePreviewPrimary, '');
      type(<CalcKey>[op('×')]);
      await idle();
      expect(state().livePreviewPrimary, '');
      expect(state().errorMessage, isNull, reason: 'typing never raises an error');
    });

    test('offers the exact fraction as the secondary read-out', () async {
      type(<CalcKey>[digit('1'), op('÷'), digit('8')]);
      await idle();
      expect(state().livePreviewPrimary, '0.125');
      expect(state().livePreviewSecondary, '1/8');
    });
  });

  group('post-commit state machine', () {
    Future<void> commitFifty() async {
      type(<CalcKey>[digit('5'), digit('0')]);
      await calculator.evaluate();
      expect(state().inputPhase, InputPhase.committedResult);
      expect(state().livePreviewPrimary, '50');
      expect(state().variables['Ans'], '50');
    }

    test('an operator continues from Ans', () async {
      await commitFifty();
      type(<CalcKey>[op('+')]);
      expect(state().inputPhase, InputPhase.editing);
      expect(calculator.expressionText(), 'Ans+');
      type(<CalcKey>[digit('1'), digit('0')]);
      await calculator.evaluate();
      expect(state().livePreviewPrimary, '60');
    });

    test('x² continues from Ans as well', () async {
      await commitFifty();
      type(<CalcKey>[const TemplateKey(TemplateKind.square)]);
      expect(calculator.expressionText(), 'Ans^(2)');
      await calculator.evaluate();
      expect(state().livePreviewPrimary, '2500');
    });

    test('a digit starts a new expression', () async {
      await commitFifty();
      type(<CalcKey>[digit('7')]);
      expect(state().inputPhase, InputPhase.editing);
      expect(calculator.expressionText(), '7');
      await calculator.evaluate();
      expect(state().livePreviewPrimary, '7');
    });

    test('a prefix template starts a new expression', () async {
      await commitFifty();
      type(<CalcKey>[const TemplateKey(TemplateKind.squareRoot), digit('9')]);
      expect(calculator.expressionText(), '√(9)');
    });

    test('a cursor key re-opens the previous expression', () async {
      await commitFifty();
      type(<CalcKey>[const MoveKey(CursorDirection.left), digit('1')]);
      expect(state().inputPhase, InputPhase.editing);
      expect(calculator.expressionText(), '501');
    });

    test('commits are written to the history tape', () async {
      await commitFifty();
      await idle();
      final history = container.read(historyProvider);
      expect(history.entries, hasLength(1));
      expect(history.entries.single.expressionText, '50');
      expect(history.entries.single.resultPrimary, '50');
    });
  });

  group('errors', () {
    test('a failed commit locks the line until the next key', () async {
      type(<CalcKey>[digit('1'), op('÷'), digit('0')]);
      await calculator.evaluate();
      expect(state().inputPhase, InputPhase.errorLocked);
      expect(state().errorMessage, 'Division by zero');
      expect(state().variables['Ans'], '0', reason: 'Ans keeps its old value');

      type(<CalcKey>[const BackspaceKey()]);
      expect(state().inputPhase, InputPhase.editing);
      expect(state().errorMessage, isNull);
      expect(calculator.expressionText(), '1÷0');
    });

    test('AC clears everything', () async {
      type(<CalcKey>[digit('1'), op('÷'), digit('0')]);
      await calculator.evaluate();
      type(<CalcKey>[const ClearKey()]);
      expect(state().inputPhase, InputPhase.editing);
      expect(state().rootSequence.isEmpty, isTrue);
    });
  });

  test('undo and redo walk through the edit history', () async {
    type(<CalcKey>[digit('1'), digit('2'), op('+')]);
    expect(calculator.expressionText(), '12+');
    calculator.undo();
    expect(calculator.expressionText(), '12');
    calculator.undo();
    expect(calculator.expressionText(), '1');
    expect(state().canRedo, isTrue);
    calculator.redo();
    expect(calculator.expressionText(), '12');
    type(<CalcKey>[digit('9')]);
    expect(state().canRedo, isFalse, reason: 'a new edit discards the redo branch');
    expect(calculator.expressionText(), '129');
  });

  test('memory keys', () async {
    type(<CalcKey>[digit('5')]);
    await calculator.evaluate();
    await calculator.memoryAdd();
    await calculator.memoryAdd();
    expect(state().variables['M'], '10');
    expect(state().hasMemory, isTrue);
    await calculator.memorySubtract();
    expect(state().variables['M'], '5');
    calculator.memoryRecall();
    expect(calculator.expressionText(), 'M');
    await calculator.evaluate();
    expect(state().livePreviewPrimary, '5');
    calculator.memoryClear();
    expect(state().hasMemory, isFalse);
  });

  test('variables can be stored and used', () async {
    type(<CalcKey>[digit('6'), op('×'), digit('7')]);
    await calculator.evaluate();
    calculator.storeAnswerIn('A');
    expect(state().variables['A'], '42');
    type(<CalcKey>[const ClearKey()]);
    calculator.insertVariable('A');
    type(<CalcKey>[op('+'), digit('1')]);
    await calculator.evaluate();
    expect(state().livePreviewPrimary, '43');
  });

  test('mode toggles are persisted with the settings', () async {
    final repository = InMemoryCalculatorRepository();
    container = create(overrides: <Override>[repositoryProvider.overrideWithValue(repository)]);
    calculator = container.read(calculatorProvider.notifier);
    expect(state().angleUnit, AngleUnit.deg);
    calculator.cycleAngleUnit();
    expect(state().angleUnit, AngleUnit.rad);
    calculator.toggleJuxtaposition();
    expect(repository.loadSettings().angleUnit, AngleUnit.rad);
    expect(repository.loadSettings().juxtaposition, JuxtapositionMode.strictCasio);

    // A fresh notifier starts from the stored settings.
    final next = create(overrides: <Override>[repositoryProvider.overrideWithValue(repository)]);
    expect(next.read(calculatorProvider).angleUnit, AngleUnit.rad);
  });

  test('typing i switches to complex mode', () async {
    type(<CalcKey>[digit('2'), const AtomKey('i', AtomKind.constant)]);
    expect(state().isComplexEnabled, isTrue);
    // The power binds tighter than the implied product: 2·(i²) = −2.
    type(<CalcKey>[const TemplateKey(TemplateKind.square)]);
    await calculator.evaluate();
    expect(state().livePreviewPrimary, '-2 + 0i');
  });

  test('INV and HYP release after the key they modify', () {
    calculator.toggleInverse();
    calculator.toggleHyperbolic();
    expect(state().isInverseActive && state().isHyperbolicActive, isTrue);
    calculator.press(const TemplateKey(TemplateKind.function, name: 'asinh'), consumeShift: true);
    expect(state().isInverseActive || state().isHyperbolicActive, isFalse);
    expect(calculator.expressionText(), 'asinh()');
  });

  test('the uncommitted expression survives a restart', () async {
    final drafts = DraftStateStore.memory();
    container = create(overrides: <Override>[draftStoreProvider.overrideWithValue(drafts)]);
    calculator = container.read(calculatorProvider.notifier);
    type(<CalcKey>[
      const TemplateKey(TemplateKind.fraction),
      digit('3'),
      const MoveKey(CursorDirection.down),
      digit('4')
    ]);
    final cursor = state().cursorPath;

    final restarted = create(overrides: <Override>[draftStoreProvider.overrideWithValue(drafts)]);
    final restored = restarted.read(calculatorProvider);
    expect(restarted.read(calculatorProvider.notifier).expressionText(), '((3)/(4))');
    expect(restored.cursorPath, cursor);
    await idle();
    expect(restarted.read(calculatorProvider).livePreviewPrimary, '0.75');

    // A committed line is no draft any more.
    await restarted.read(calculatorProvider.notifier).evaluate();
    expect(drafts.read(), isNull);
  });

  test('pasted text is sanitised into editor nodes', () async {
    calculator.pasteText('1,250.50 × 2³ − √16');
    expect(state().rootSequence.children.whereType<PowerNode>(), hasLength(1));
    expect(state().rootSequence.children.whereType<RootNode>(), hasLength(1));
    await calculator.evaluate();
    expect(state().livePreviewPrimary, '10000');
  });

  test('a history entry can be recalled for editing', () async {
    type(<CalcKey>[const TemplateKey(TemplateKind.squareRoot), digit('2')]);
    await calculator.evaluate();
    await idle();
    final entry = container.read(historyProvider).entries.single;
    type(<CalcKey>[const ClearKey()]);
    calculator.recallExpression(entry.expressionJson);
    expect(calculator.expressionText(), '√(2)');
    expect(state().inputPhase, InputPhase.editing);
    expect(state().rootSequence.children.single, isA<RootNode>());
  });

  group('CALC', () {
    const x = AtomKey('x', AtomKind.variable);
    const y = AtomKey('y', AtomKind.variable);
    String number(String text) => CalcValueCodec.encode(MathEngine.evaluateText(text).value);

    test('asks for the variables of the expression', () {
      type(<CalcKey>[x, const TemplateKey(TemplateKind.square), op('+'), digit('3'), y, op('−'), x]);
      expect(calculator.freeVariables(), <String>['x', 'y']);
      type(<CalcKey>[const ClearKey(), digit('2'), op('+'), digit('3')]);
      expect(calculator.freeVariables(), isEmpty);
    });

    test('evaluates with the given values and leaves everything else as it was', () async {
      type(<CalcKey>[digit('7')]);
      await calculator.evaluate();
      calculator.storeAnswerIn('x');
      await idle();
      final historyBefore = container.read(historyProvider).entries.length;
      type(<CalcKey>[const ClearKey(), x, const TemplateKey(TemplateKind.square), op('+'), digit('3'), y]);
      await idle();
      expect(state().livePreviewPrimary, '', reason: 'y has no value yet, so there is nothing to preview');
      final expression = calculator.expressionText();
      final caret = state().cursorPath;

      await calculator.evaluateWith(<String, String>{'x': number('5'), 'y': number('2')}, note: 'x = 5, y = 2');
      expect(state().livePreviewPrimary, '31');
      expect(state().substitution, 'x = 5, y = 2');
      // The formula is still being edited, with the caret where it was.
      expect(state().inputPhase, InputPhase.editing);
      expect(calculator.expressionText(), expression);
      expect(state().cursorPath, caret);
      // Nothing was stored, and nothing went onto the tape.
      expect(state().variables['x'], '7');
      expect(state().variables['y'], isNull);
      expect(state().variables['Ans'], '7');
      await idle();
      expect(container.read(historyProvider).entries, hasLength(historyBefore));

      // Again, with other values.
      await calculator.evaluateWith(<String, String>{'x': number('1/2'), 'y': number('−1')}, note: 'x = 1/2, y = −1');
      expect(state().livePreviewPrimary, '-2.75');
      expect(state().livePreviewSecondary, '-11/4');
      expect(state().substitution, 'x = 1/2, y = −1');
      expect(calculator.expressionText(), expression);
    });

    test('the result goes when the expression changes, and = works as ever', () async {
      type(<CalcKey>[digit('2')]);
      await calculator.evaluate();
      calculator.storeAnswerIn('x');
      type(<CalcKey>[const ClearKey(), x, op('+'), digit('1')]);
      await calculator.evaluateWith(<String, String>{'x': number('9')}, note: 'x = 9');
      expect(state().livePreviewPrimary, '10');
      // Moving the caret keeps it.
      type(<CalcKey>[const MoveKey(CursorDirection.left)]);
      await idle();
      expect(state().substitution, 'x = 9');
      expect(state().livePreviewPrimary, '10');
      // Typing brings the preview with the stored value back.
      type(<CalcKey>[digit('0')]);
      await idle();
      expect(state().substitution, isNull);
      expect(calculator.expressionText(), 'x+01');
      expect(state().livePreviewPrimary, '3');

      await calculator.evaluateWith(<String, String>{'x': number('9')}, note: 'x = 9');
      await calculator.evaluate();
      expect(state().inputPhase, InputPhase.committedResult);
      expect(state().substitution, isNull);
      expect(state().livePreviewPrimary, '3', reason: '= uses the stored x');
    });

    test('values that fail leave the line open for the next ones', () async {
      type(<CalcKey>[digit('1'), op('÷'), x]);
      await idle();
      final expression = calculator.expressionText();
      await calculator.evaluateWith(<String, String>{'x': number('0')}, note: 'x = 0');
      expect(state().errorMessage, isNotNull);
      expect(state().substitution, 'x = 0');
      expect(state().inputPhase, InputPhase.editing, reason: 'unlike after =, the line is not locked');
      expect(calculator.expressionText(), expression);

      await calculator.evaluateWith(<String, String>{'x': number('4')}, note: 'x = 4');
      expect(state().errorMessage, isNull);
      expect(state().livePreviewPrimary, '0.25');

      // A key after a failure continues the formula and drops the message.
      await calculator.evaluateWith(<String, String>{'x': number('0')}, note: 'x = 0');
      type(<CalcKey>[op('+'), digit('2')]);
      expect(state().errorMessage, isNull);
      expect(state().substitution, isNull);
      expect(calculator.expressionText(), '$expression+2');
    });

    test('= on a variable without a value points to CALC, which then works on that line', () async {
      type(<CalcKey>[x, op('×'), digit('3')]);
      await calculator.evaluate();
      expect(state().inputPhase, InputPhase.errorLocked);
      expect(state().errorMessage, 'Variable x has no value${CalculatorNotifier.calcHint}');
      expect(calculator.freeVariables(), <String>['x']);

      await calculator.evaluateWith(<String, String>{'x': number('4')}, note: 'x = 4');
      expect(state().inputPhase, InputPhase.editing);
      expect(state().errorMessage, isNull);
      expect(state().livePreviewPrimary, '12');
      expect(calculator.expressionText(), 'x×3');
    });

    test('works on a committed line and keeps the formula', () async {
      type(<CalcKey>[digit('5')]);
      await calculator.evaluate();
      calculator.storeAnswerIn('x');
      type(<CalcKey>[const ClearKey(), x, op('×'), digit('3')]);
      await calculator.evaluate();
      expect(state().inputPhase, InputPhase.committedResult);
      expect(state().livePreviewPrimary, '15');
      await calculator.evaluateWith(<String, String>{'x': number('4')}, note: 'x = 4');
      expect(state().inputPhase, InputPhase.editing);
      expect(state().livePreviewPrimary, '12');
      expect(calculator.expressionText(), 'x×3');
      expect(state().variables['Ans'], '15', reason: 'Ans is still the result of =');
    });

    test('a change of mode works the result out again with the same values', () async {
      type(<CalcKey>[const TemplateKey(TemplateKind.function, name: 'sin'), x]);
      await calculator.evaluateWith(
        <String, String>{'x': number('30')},
        note: 'x = 30',
        entries: <String, String>{'x': '30'},
      );
      expect(state().livePreviewPrimary, '0.5');
      calculator.toggleInverse();

      calculator.cycleAngleUnit(); // DEG → RAD
      await idle();
      expect(state().substitution, 'x = 30');
      expect(state().livePreviewPrimary, '-0.9880316240928617899877489072944582'); // sin(30 rad)
      expect(state().isInverseActive, isTrue, reason: 'no key was pressed');
      expect(calculator.calcEntries, <String, String>{'x': '30'});
    });

    test('remembers what was typed for as long as its result is on display', () async {
      type(<CalcKey>[x, op('+'), digit('1')]);
      expect(calculator.calcEntries, isEmpty);
      await calculator.evaluateWith(
        <String, String>{'x': number('1/2')},
        note: 'x = 1/2',
        entries: <String, String>{'x': '1/2'},
      );
      expect(calculator.calcEntries, <String, String>{'x': '1/2'});
      type(<CalcKey>[const MoveKey(CursorDirection.left)]);
      expect(calculator.calcEntries, <String, String>{'x': '1/2'}, reason: 'the result is still there');
      type(<CalcKey>[digit('2')]);
      await idle();
      expect(calculator.calcEntries, isEmpty, reason: 'the expression is another one now');
    });

    test('after values that failed, moving the caret brings the preview back', () async {
      type(<CalcKey>[digit('2')]);
      await calculator.evaluate();
      calculator.storeAnswerIn('x');
      type(<CalcKey>[const ClearKey(), digit('1'), op('÷'), x]);
      await idle();
      expect(state().livePreviewPrimary, '0.5');

      await calculator.evaluateWith(<String, String>{'x': number('0')}, note: 'x = 0');
      expect(state().errorMessage, isNotNull);
      // ENG has no number to rewrite here and leaves the message alone.
      calculator.toggleEngineering();
      expect(state().errorMessage, isNotNull);
      expect(state().substitution, 'x = 0');
      calculator.toggleEngineering();

      type(<CalcKey>[const MoveKey(CursorDirection.left)]);
      await idle();
      expect(state().errorMessage, isNull);
      expect(state().substitution, isNull);
      expect(state().livePreviewPrimary, '0.5');
      expect(calculator.expressionText(), '1÷x');
    });

    test('M+ adds what CALC has on display', () async {
      type(<CalcKey>[x, op('×'), digit('3')]);
      await calculator.evaluateWith(<String, String>{'x': number('4')}, note: 'x = 4');
      await calculator.memoryAdd();
      expect(state().variables['M'], '12');
    });
  });

  group('ENG', () {
    test('rewrites the result on display and back', () async {
      type(<CalcKey>[digit('1'), digit('2'), digit('3'), digit('4'), digit('5'), op('×'), digit('6'), digit('7')]);
      await calculator.evaluate();
      expect(state().livePreviewPrimary, '827115');
      calculator.toggleEngineering();
      expect(state().isEngineering, isTrue);
      expect(state().livePreviewPrimary, '827.115e3');
      expect(state().livePreviewSecondary, '827115');
      calculator.toggleEngineering();
      expect(state().isEngineering, isFalse);
      expect(state().livePreviewPrimary, '827115');
      expect(state().livePreviewSecondary, isNull);
    });

    test('applies to the preview, to the next result and to what CALC shows', () async {
      calculator.toggleEngineering();
      type(<CalcKey>[digit('5'), digit('0'), op('×'), digit('3'), digit('0'), digit('0')]);
      await idle();
      expect(state().livePreviewPrimary, '15e3');
      await calculator.evaluate();
      expect(state().livePreviewPrimary, '15e3');
      expect(state().variables['Ans'], '15000', reason: 'the value is not touched by the notation');

      type(<CalcKey>[const ClearKey(), const AtomKey('x', AtomKind.variable), op('×'), digit('2')]);
      await calculator.evaluateWith(
        <String, String>{'x': CalcValueCodec.encode(MathEngine.evaluateText('2500').value)},
        note: 'x = 2500',
      );
      expect(state().livePreviewPrimary, '5e3');
      calculator.toggleEngineering();
      expect(state().livePreviewPrimary, '5000');
      expect(state().substitution, 'x = 2500');
    });

    test('is remembered with the settings', () {
      final repository = InMemoryCalculatorRepository();
      container = create(overrides: <Override>[repositoryProvider.overrideWithValue(repository)]);
      calculator = container.read(calculatorProvider.notifier);
      expect(state().isEngineering, isFalse);
      calculator.toggleEngineering();
      expect(repository.loadSettings().engineeringNotation, isTrue);

      final restarted = create(overrides: <Override>[repositoryProvider.overrideWithValue(repository)]);
      expect(restarted.read(calculatorProvider).isEngineering, isTrue);
    });
  });

  test('Rand has no live preview: the number comes with =', () async {
    type(<CalcKey>[const AtomKey('Rand', AtomKind.constant), op('×'), digit('6')]);
    await idle();
    expect(state().livePreviewPrimary, '');
    await calculator.evaluate();
    final value = double.parse(state().livePreviewPrimary);
    expect(value, inInclusiveRange(0, 6));
    expect(state().inputPhase, InputPhase.committedResult);
  });

  test('typing the angle of a polar form switches to complex mode', () async {
    expect(state().isComplexEnabled, isFalse);
    type(<CalcKey>[digit('2'), op('∠'), digit('9'), digit('0')]);
    expect(state().isComplexEnabled, isTrue);
    await calculator.evaluate();
    expect(state().livePreviewPrimary, '0 + 2i');
  });

  test('releaseShift lets INV and HYP go', () {
    calculator
      ..toggleInverse()
      ..toggleHyperbolic();
    expect(state().isInverseActive && state().isHyperbolicActive, isTrue);
    calculator.releaseShift();
    expect(state().isInverseActive || state().isHyperbolicActive, isFalse);
  });
}
