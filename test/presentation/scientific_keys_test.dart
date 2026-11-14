// The scientific grid of the review: its layout, the INV key, the functions
// that were added (Σ, Π, a b/c, Rand, ∠, ENG) and CALC.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/core/theme/app_colors.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_ui_state.dart';
import 'package:modern_scientific_calculator/presentation/tabs/scientific_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/standard_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/widgets/app_toast.dart';
import 'package:modern_scientific_calculator/presentation/widgets/calc_key_button.dart';
import 'package:modern_scientific_calculator/presentation/widgets/calc_prompt.dart';
import 'package:modern_scientific_calculator/presentation/widgets/key_legend.dart';
import 'package:modern_scientific_calculator/presentation/widgets/lab_widgets.dart';
import 'package:modern_scientific_calculator/presentation/widgets/persistent_display_card.dart';

import '../support/test_app.dart';

Finder scientificKey(String name) => keyIn(ScientificTabView, name);

const String calcKey = 'CALC, evaluate with values for the variables';
const String invKey = 'INV, second functions';

Future<void> tapAll(WidgetTester tester, List<Finder> keys) async {
  for (final key in keys) {
    await tester.tap(key);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await settle(tester);
}

/// The scientific tab on a phone, with its container.
Future<(ProviderContainer, CalculatorNotifier)> openScientific(WidgetTester tester, {Size? size}) async {
  final container = size == null ? await pumpCalculator(tester) : await pumpCalculator(tester, size: size);
  final notifier = container.read(calculatorProvider.notifier)..setActiveTab(1);
  await settle(tester);
  return (container, notifier);
}

/// The names of the 30 keys of the grid, row by row.
List<List<String>> gridOf(WidgetTester tester) {
  final keys = tester
      .widgetList<CalcKeyButton>(
          find.descendant(of: find.byType(ScientificTabView), matching: find.byType(CalcKeyButton)))
      .toList();
  final placed = <(Offset, String)>[
    for (final key in keys)
      (
        tester.getTopLeft(find.byWidget(key)),
        key.label ?? key.semanticLabel ?? '?',
      ),
  ]..sort((a, b) => a.$1.dy != b.$1.dy ? a.$1.dy.compareTo(b.$1.dy) : a.$1.dx.compareTo(b.$1.dx));
  final grid = placed.sublist(placed.length - 30);
  return <List<String>>[
    for (var row = 0; row < 6; row++) <String>[for (var column = 0; column < 5; column++) grid[row * 5 + column].$2],
  ];
}

/// Presses CALC and waits until the prompt has slid in.
Future<void> openPrompt(WidgetTester tester) async {
  await tester.tap(scientificKey(calcKey));
  await settle(tester);
}

/// A key of the prompt's keypad.
Finder promptKey(String label) => find.descendant(
      of: find.byType(CalcPrompt),
      matching: find.byWidgetPredicate((w) => w is CalcKeyButton && w.label == label),
    );

/// The fields of the prompt, in order.
List<LabField> promptFields(WidgetTester tester) =>
    tester.widgetList<LabField>(find.descendant(of: find.byType(CalcPrompt), matching: find.byType(LabField))).toList();

Finder badge(String label) => find.descendant(
      of: find.byType(PersistentDisplayCard),
      matching: find.byWidgetPredicate((w) => w is StatusBadge && w.label == label),
    );

AtomKey digit(String d) => AtomKey(d, AtomKind.digit);
AtomKey op(String o) => AtomKey(o, AtomKind.binaryOp);
const AtomKey x = AtomKey('x', AtomKind.variable);
const AtomKey y = AtomKey('y', AtomKind.variable);

void main() {
  setUpAll(loadAppFonts);

  group('the grid', () {
    testWidgets('has the keys of the review, each in its place', (tester) async {
      await openScientific(tester);
      expect(gridOf(tester), <List<String>>[
        <String>['INV', 'HYP', 'sum', 'x', 'AC'],
        <String>['sin', 'cos', 'tan', 'ln', 'log'],
        <String>['square', 'power', 'square root', 'fraction', 'abs'],
        <String>['pi', 'e', 'imaginary unit', 'exponent', 'factorial'],
        <String>['integral', 'derivative', 'ncr', 'open parenthesis', 'close parenthesis'],
        <String>[calcKey, 'Ans', ',', '⌫', '='],
      ]);

      await tapAll(tester, <Finder>[scientificKey('INV')]);
      expect(gridOf(tester), <List<String>>[
        <String>['INV', 'HYP', 'product', 'y', 'AC'],
        <String>['asin', 'acos', 'atan', 'e to the x', 'ten to the x'],
        <String>['cube', 'nth root', 'cube root', 'mixed fraction', 'reciprocal'],
        <String>['phi', 'random number', 'polar form', 'engineering notation', 'mod'],
        <String>['integral', 'derivative', 'npr', 'open parenthesis', 'close parenthesis'],
        <String>[calcKey, 'Memory', ',', '⌫', '='],
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('fits a small phone and a tablet without overflowing', (tester) async {
      await openScientific(tester, size: const Size(360, 640));
      expect(gridOf(tester).first, <String>['INV', 'HYP', 'sum', 'x', 'AC']);
      expect(tester.takeException(), isNull);
      for (final name in <String>['sum', calcKey, 'Equals', 'factorial']) {
        expect(scientificKey(name).hitTestable(), findsOneWidget, reason: name);
      }
    });

    testWidgets('f(x) opens a row with the functions that have no key in the grid', (tester) async {
      final (container, notifier) = await openScientific(tester);
      expect(scientificKey('log base 2'), findsNothing);
      final gridTop = tester.getTopLeft(scientificKey('INV')).dy;

      await tapAll(tester, <Finder>[scientificKey('Show more functions')]);
      for (final name in <String>['log base 2', 'log to base a', 'gamma', 'gcd', 'lcm', 'degrees', 'percent']) {
        expect(scientificKey(name).hitTestable(), findsOneWidget, reason: name);
      }
      expect(tester.getTopLeft(scientificKey('INV')).dy, greaterThan(gridTop), reason: 'the grid makes room');
      expect(gridOf(tester).last, <String>[calcKey, 'Ans', ',', '⌫', '=']);

      await tapAll(tester, <Finder>[scientificKey('log base 2')]);
      notifier.pasteText('1024');
      await commit(tester, container);
      expect(stateOf(container).livePreviewPrimary, '10');

      await tapAll(tester, <Finder>[scientificKey('All clear'), scientificKey('gamma')]);
      notifier.pasteText('5');
      await commit(tester, container);
      expect(stateOf(container).livePreviewPrimary, '24');

      await tapAll(tester, <Finder>[scientificKey('Hide the extra functions')]);
      expect(scientificKey('gcd'), findsNothing);
      expect(tester.getTopLeft(scientificKey('INV')).dy, gridTop);
      expect(tester.takeException(), isNull);
    });

    testWidgets('next to the scientific grid the standard keypad offers that row', (tester) async {
      await pumpCalculator(tester, size: const Size(1280, 800));
      await tapAll(tester, <Finder>[keyIn(StandardTabView, 'Show more functions')]);
      expect(keyIn(StandardTabView, 'gcd').hitTestable(), findsOneWidget);
      expect(keyIn(StandardTabView, 'sin'), findsNothing, reason: 'sin is on screen in the grid');
      expect(tester.takeException(), isNull);
    });
  });

  group('INV', () {
    testWidgets('is a shift key with a colour of its own', (tester) async {
      await openScientific(tester);
      CalcKeyButton key(String name) => tester.widget<CalcKeyButton>(scientificKey(name));
      // The two legends of a key: the large one, and the hint in its corner.
      List<KeyLegend> legends(String name) => tester
          .widgetList<KeyLegend>(find.descendant(of: scientificKey(name), matching: find.byType(KeyLegend)))
          .toList()
        ..sort((a, b) => b.size.compareTo(a.size));
      Color legend(String name) => legends(name).first.color;
      Color hint(String name) {
        final both = legends(name);
        expect(both, hasLength(2), reason: name);
        expect(both.last.size, lessThan(both.first.size * 0.6), reason: name);
        return both.last.color;
      }

      // No other key of the grid has the tone of INV.
      expect(key('INV').tone, KeyTone.shift);
      expect(key('INV').semanticLabel, invKey);
      final tones = tester
          .widgetList<CalcKeyButton>(
              find.descendant(of: find.byType(ScientificTabView), matching: find.byType(CalcKeyButton)))
          .where((k) => k.tone == KeyTone.shift || k.tone == KeyTone.shiftActive);
      expect(tones, hasLength(1));
      expect(CalcKeyButton.foregroundOf(KeyTone.shift), AppColors.keyShiftText);
      expect(AppColors.keyShiftText, isNot(CalcKeyButton.foregroundOf(KeyTone.function)));
      expect(AppColors.keyShiftText, isNot(AppColors.accent), reason: 'HYP lights up in the accent colour');

      // The second functions are named in the colour of the key that reaches them.
      expect(hint('sin'), AppColors.keyShiftHint);
      expect(hint('sum'), AppColors.keyShiftHint);
      expect(legend('sin'), CalcKeyButton.foregroundOf(KeyTone.function));

      await tapAll(tester, <Finder>[scientificKey('INV')]);
      expect(key('INV').tone, KeyTone.shiftActive);
      // What INV has changed takes its colour; what it has not, keeps its own.
      expect(legend('asin'), AppColors.keyShiftText);
      expect(legend('product'), AppColors.keyShiftText);
      expect(legend('integral'), CalcKeyButton.foregroundOf(KeyTone.function));
      expect(hint('asin'), AppColors.textMuted);
      expect(badge('INV'), findsOneWidget);

      // It is a one-shot shift.
      await tapAll(tester, <Finder>[scientificKey('phi')]);
      expect(key('INV').tone, KeyTone.shift);
      expect(scientificKey('pi'), findsOneWidget);
    });
  });

  group('the added functions', () {
    testWidgets('Σ and Π are templates with a first and a last value and a term', (tester) async {
      final (container, notifier) = await openScientific(tester);
      await tapAll(tester, <Finder>[scientificKey('sum')]);
      notifier
        ..press(digit('1'))
        ..press(const MoveKey(CursorDirection.right))
        ..press(digit('1'))
        ..press(digit('0'))
        ..press(const MoveKey(CursorDirection.right));
      await tapAll(tester, <Finder>[scientificKey('x'), scientificKey('square')]);
      expect(notifier.expressionText(), 'Σ(1,10,x^(2))');
      await tapAll(tester, <Finder>[scientificKey('Equals')]);
      expect(stateOf(container).livePreviewPrimary, '385');

      await tapAll(tester, <Finder>[scientificKey('All clear'), scientificKey('INV'), scientificKey('product')]);
      expect(stateOf(container).isInverseActive, isFalse);
      notifier
        ..press(digit('1'))
        ..press(const MoveKey(CursorDirection.right))
        ..press(digit('5'))
        ..press(const MoveKey(CursorDirection.right));
      await tapAll(tester, <Finder>[scientificKey('x'), scientificKey('Equals')]);
      expect(notifier.expressionText(), 'Π(1,5,x)');
      expect(stateOf(container).livePreviewPrimary, '120');
      expect(tester.takeException(), isNull);
    });

    testWidgets('the "," key walks through the three slots of a Σ', (tester) async {
      final (container, notifier) = await openScientific(tester);
      await tapAll(tester, <Finder>[scientificKey('sum')]);
      notifier.press(digit('1'));
      await tapAll(tester, <Finder>[scientificKey('Next argument')]);
      notifier.press(digit('4'));
      await tapAll(tester, <Finder>[scientificKey('Next argument'), scientificKey('x'), scientificKey('Equals')]);
      expect(notifier.expressionText(), 'Σ(1,4,x)');
      expect(stateOf(container).livePreviewPrimary, '10');
    });

    testWidgets('a b/c types a mixed fraction', (tester) async {
      final (container, notifier) = await openScientific(tester);
      await tapAll(tester, <Finder>[scientificKey('INV'), scientificKey('mixed fraction')]);
      notifier
        ..press(digit('2'))
        ..press(const MoveKey(CursorDirection.right))
        ..press(digit('1'))
        ..press(const MoveKey(CursorDirection.right))
        ..press(digit('3'));
      await tapAll(tester, <Finder>[scientificKey('Equals')]);
      expect(stateOf(container).rootSequence.children.single,
          isA<FractionNode>().having((f) => f.isMixed, 'mixed', isTrue));
      expect(stateOf(container).livePreviewSecondary, '7/3');
      expect(tester.takeException(), isNull);
    });

    testWidgets('∠ types the polar form and switches to complex mode', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.press(digit('2'));
      await tapAll(tester, <Finder>[scientificKey('INV'), scientificKey('polar form')]);
      notifier
        ..press(digit('9'))
        ..press(digit('0'));
      expect(stateOf(container).isComplexEnabled, isTrue);
      await tapAll(tester, <Finder>[scientificKey('Equals')]);
      expect(notifier.expressionText(), '2∠90');
      expect(stateOf(container).livePreviewPrimary, '0 + 2i');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a long complex result leads with its short form', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('2∠30');
      await commit(tester, container);
      expect(stateOf(container).livePreviewPrimary, '1.732050807568877293527446341505872 + 1i');
      expect(find.bySemanticsLabel('Result: 1.732050808 + 1i'), findsOneWidget);
      // A tap brings the full digits to the front.
      await tester.tap(find.bySemanticsLabel('Result: 1.732050808 + 1i'));
      await settle(tester);
      expect(find.bySemanticsLabel('Result: 1.732050807568877293527446341505872 + 1i'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Rand gives a new number with every =', (tester) async {
      final (container, _) = await openScientific(tester);
      await tapAll(tester, <Finder>[scientificKey('INV'), scientificKey('random number')]);
      expect(stateOf(container).livePreviewPrimary, '', reason: 'no preview: it would not be the number of =');
      final seen = <String>{};
      for (var i = 0; i < 4; i++) {
        await tapAll(tester, <Finder>[scientificKey('Equals')]);
        final shown = stateOf(container).livePreviewPrimary;
        expect(double.parse(shown), inInclusiveRange(0, 0.9999999999));
        seen.add(shown);
      }
      expect(seen.length, greaterThan(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('ENG switches the notation, says so, and shows a badge that switches back', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('12345×67');
      await commit(tester, container);
      expect(badge('ENG'), findsNothing);

      await tapAll(tester, <Finder>[scientificKey('INV'), scientificKey('engineering notation')]);
      expect(stateOf(container).isEngineering, isTrue);
      expect(stateOf(container).isInverseActive, isFalse);
      expect(stateOf(container).livePreviewPrimary, '827.115e3');
      expect(container.read(toastProvider)?.text, ModeHints.engineering);
      expect(badge('ENG'), findsOneWidget);
      expect(notifier.expressionText(), '12345×67', reason: 'ENG is no key of the expression');

      await tester.tap(badge('ENG'));
      await settle(tester);
      expect(stateOf(container).isEngineering, isFalse);
      expect(stateOf(container).livePreviewPrimary, '827115');
      expect(badge('ENG'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the second functions of the review compute', (tester) async {
      final (container, notifier) = await openScientific(tester);
      Future<String> result(List<Object> steps) async {
        await tapAll(tester, <Finder>[scientificKey('All clear')]);
        for (final step in steps) {
          if (step is String) {
            await tapAll(tester, <Finder>[scientificKey(step)]);
          } else {
            notifier.press(step as CalcKey);
          }
        }
        await tapAll(tester, <Finder>[scientificKey('Equals')]);
        return stateOf(container).livePreviewPrimary;
      }

      const right = MoveKey(CursorDirection.right);
      expect(await result(<Object>[digit('4'), 'INV', 'reciprocal']), '0.25'); // 1/x
      expect(await result(<Object>[digit('2'), 'INV', 'cube']), '8'); // x³
      expect(await result(<Object>['INV', 'cube root', digit('2'), digit('7')]), '3'); // ∛x
      expect(await result(<Object>['INV', 'nth root', digit('4'), right, digit('8'), digit('1')]), '3'); // ʸ√x
      expect(await result(<Object>[digit('1'), digit('7'), 'INV', 'mod', digit('5')]), '2');
      expect(await result(<Object>['INV', 'npr', digit('5'), right, digit('2')]), '20');
      expect(await result(<Object>['INV', 'phi']), startsWith('1.6180339887498948482'));
      expect(await result(<Object>['INV', 'y', op('+'), digit('1')]), '',
          reason: 'y has no value: an error, no result');
      expect(stateOf(container).errorMessage, contains('CALC'));
      expect(tester.takeException(), isNull);
    });
  });

  group('CALC', () {
    Future<void> typeFormula(CalculatorNotifier notifier) async {
      // x² + 3y
      for (final key in <CalcKey>[x, const TemplateKey(TemplateKind.square), op('+'), digit('3'), y]) {
        notifier.press(key);
      }
    }

    testWidgets('lists the variables, evaluates with the typed values and keeps the formula', (tester) async {
      final (container, notifier) = await openScientific(tester);
      await typeFormula(notifier);
      await settle(tester);
      final formula = notifier.expressionText();
      final history = container.read(historyProvider).entries.length;

      await openPrompt(tester);
      expect(find.byType(CalcPrompt), findsOneWidget);
      expect(promptFields(tester).map((f) => f.label), <String>['x =', 'y =']);
      expect(promptFields(tester).map((f) => f.value), <String>['', ''], reason: 'nothing is stored yet');
      expect(promptFields(tester).first.active, isTrue);

      // 5 ⏎ 2 ⏎: the enter key moves on, and evaluates after the last field.
      await tapAll(tester, <Finder>[promptKey('5'), promptKey('⏎')]);
      expect(promptFields(tester)[1].active, isTrue);
      await tapAll(tester, <Finder>[promptKey('2'), promptKey('⏎')]);
      await settle(tester);
      expect(find.byType(CalcPrompt), findsNothing);

      expect(stateOf(container).livePreviewPrimary, '31');
      expect(find.bySemanticsLabel('Result: 31'), findsOneWidget);
      expect(badge('x = 5, y = 2'), findsOneWidget);
      expect(notifier.expressionText(), formula);
      expect(stateOf(container).inputPhase, InputPhase.editing);
      expect(stateOf(container).variables['x'], isNull);
      expect(stateOf(container).variables['y'], isNull);
      expect(stateOf(container).variables['Ans'], '0');
      expect(container.read(historyProvider).entries, hasLength(history));

      // CALC again, with other values and the Evaluate button.
      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('1'), promptKey('0')]);
      await tester.tap(find.text('y ='));
      await settle(tester);
      expect(promptFields(tester)[1].active, isTrue, reason: 'a tap selects a field');
      await tapAll(tester, <Finder>[promptKey('−'), promptKey('4')]);
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '88'); // 100 − 12
      expect(badge('x = 10, y = −4'), findsOneWidget);
      expect(notifier.expressionText(), formula);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starts each field with the stored value, which the first key replaces', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('7/2');
      await commit(tester, container);
      notifier
        ..storeAnswerIn('x')
        ..press(const ClearKey());
      await typeFormula(notifier);
      await settle(tester);

      await openPrompt(tester);
      expect(promptFields(tester).map((f) => f.value), <String>['7/2', '']);
      // Evaluating at once uses the stored x, and 0 for the empty y.
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '12.25');
      expect(badge('x = 7/2, y = 0'), findsOneWidget);

      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('3')]);
      expect(promptFields(tester).first.value, '3', reason: 'the key replaced 7/2');
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '9');
      expect(stateOf(container).variables['x'], '7/2', reason: 'the stored value is untouched');
      expect(tester.takeException(), isNull);
    });

    testWidgets('asks for x when the expression has no variable, and can be closed', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('2+3');
      await settle(tester);
      await openPrompt(tester);
      expect(promptFields(tester).map((f) => f.label), <String>['x =']);
      await tester.tap(find.text('Close'));
      await settle(tester);
      expect(find.byType(CalcPrompt), findsNothing);
      expect(stateOf(container).substitution, isNull);
      expect(notifier.expressionText(), '2+3');

      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('9')]);
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '5');
      expect(badge('x = 9'), findsOneWidget);
    });

    testWidgets('says what it needs when there is no formula', (tester) async {
      final (container, _) = await openScientific(tester);
      await tapAll(tester, <Finder>[scientificKey(calcKey)]);
      expect(find.byType(CalcPrompt), findsNothing);
      expect(container.read(toastProvider)?.text, contains('CALC'));
    });

    testWidgets('a value that fails is reported and the formula stays open', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('1/x');
      await settle(tester);
      final formula = notifier.expressionText();
      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('0')]);
      expect(promptFields(tester).single.value, '0');
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).errorMessage, isNotNull);
      expect(find.bySemanticsLabel(RegExp('^Error: ')), findsOneWidget);
      expect(badge('x = 0'), findsOneWidget);
      expect(stateOf(container).inputPhase, InputPhase.editing);

      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('8')]);
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '0.125');
      expect(find.bySemanticsLabel(RegExp('^Error: ')), findsNothing);
      expect(notifier.expressionText(), formula);
      expect(tester.takeException(), isNull);
    });

    testWidgets('takes fractions and exponents as values, and marks what is no number', (tester) async {
      final (container, notifier) = await openScientific(tester);
      notifier.pasteText('2x');
      await settle(tester);
      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('3'), promptKey('a/b'), promptKey('4')]);
      expect(promptFields(tester).single.value, '3/4');
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '1.5');

      await openPrompt(tester);
      await tapAll(tester, <Finder>[promptKey('5'), promptKey('a/b')]);
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(find.byType(CalcPrompt), findsOneWidget, reason: '"5/" is no number: the prompt stays');
      expect(promptFields(tester).single.error, isTrue);
      expect(find.text('This is not a number.'), findsOneWidget);
      await tapAll(tester, <Finder>[promptKey('2')]);
      expect(promptFields(tester).single.error, isFalse);
      await tester.tap(find.text('Evaluate'));
      await settle(tester);
      expect(stateOf(container).livePreviewPrimary, '5');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a hardware keyboard types into the prompt and not into the formula', (tester) async {
      final (container, notifier) = await openScientific(tester);
      await typeFormula(notifier);
      await settle(tester);
      final formula = notifier.expressionText();
      await openPrompt(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.digit6, character: '6');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.minus, character: '-');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit1, character: '1');
      await tester.sendKeyEvent(LogicalKeyboardKey.digit9, character: '9');
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await settle(tester);
      expect(promptFields(tester).map((f) => f.value), <String>['6', '−1']);
      expect(notifier.expressionText(), formula);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await settle(tester);
      expect(find.byType(CalcPrompt), findsNothing);
      expect(stateOf(container).livePreviewPrimary, '33'); // 36 − 3

      await openPrompt(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await settle(tester);
      expect(find.byType(CalcPrompt), findsNothing);
      expect(stateOf(container).livePreviewPrimary, '33', reason: 'closing changes nothing');
      expect(tester.takeException(), isNull);
    });

    testWidgets('releases INV and fits a small phone', (tester) async {
      final (container, notifier) = await openScientific(tester, size: const Size(360, 640));
      await typeFormula(notifier);
      await tapAll(tester, <Finder>[scientificKey('INV'), scientificKey(calcKey)]);
      expect(stateOf(container).isInverseActive, isFalse);
      expect(find.byType(CalcPrompt), findsOneWidget);
      expect(find.text('Evaluate').hitTestable(), findsOneWidget);
      expect(promptKey('7').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
