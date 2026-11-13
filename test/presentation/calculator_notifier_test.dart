import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/data/local_db/draft_state_store.dart';
import 'package:modern_scientific_calculator/data/repositories/calculator_repository.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
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
}
