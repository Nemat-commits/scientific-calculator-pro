import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/presentation/screens/calculator_shell_screen.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_ui_state.dart';
import 'package:modern_scientific_calculator/presentation/tabs/advanced_lab_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/scientific_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/standard_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/unit_converter_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/widgets/persistent_display_card.dart';
import 'package:modern_scientific_calculator/presentation/widgets/segmented_tab_bar.dart';

import '../support/test_app.dart';

Finder standardKey(String name) => keyIn(StandardTabView, name);

Finder scientificKey(String name) => keyIn(ScientificTabView, name);

Future<void> tapAll(WidgetTester tester, List<Finder> keys) async {
  for (final key in keys) {
    await tester.tap(key);
    await tester.pump(const Duration(milliseconds: 80));
  }
  await settle(tester);
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('portrait: typing on the standard keypad evaluates and commits', (tester) async {
    final container = await pumpCalculator(tester);
    await tapAll(tester, <Finder>[standardKey('7'), standardKey('×'), standardKey('6')]);
    expect(stateOf(container).livePreviewPrimary, '42');
    expect(stateOf(container).inputPhase, InputPhase.editing);

    await tapAll(tester, <Finder>[standardKey('=')]);
    expect(stateOf(container).inputPhase, InputPhase.committedResult);
    expect(stateOf(container).livePreviewPrimary, '42');

    await tapAll(tester, <Finder>[standardKey('+'), standardKey('8'), standardKey('=')]);
    expect(stateOf(container).livePreviewPrimary, '50');
    expect(container.read(historyProvider).entries, hasLength(2));
  });

  testWidgets('the smart parenthesis key opens and closes groups', (tester) async {
    final container = await pumpCalculator(tester);
    await tapAll(tester, <Finder>[
      standardKey('2'),
      standardKey('×'),
      standardKey('( )'),
      standardKey('3'),
      standardKey('+'),
      standardKey('4'),
      standardKey('( )'),
    ]);
    expect(container.read(calculatorProvider.notifier).expressionText(), '2×(3+4)');
    expect(stateOf(container).livePreviewPrimary, '14');
  });

  testWidgets('scientific tab: templates, INV morphing and 2D navigation', (tester) async {
    final container = await pumpCalculator(tester);
    final notifier = container.read(calculatorProvider.notifier);
    notifier.setActiveTab(1);
    await settle(tester);

    await tapAll(tester, <Finder>[scientificKey('sin')]);
    expect(notifier.expressionText(), 'sin()');

    // INV turns sin into sin⁻¹ and releases after one key.
    await tapAll(tester, <Finder>[scientificKey('▶'), scientificKey('INV')]);
    expect(stateOf(container).isInverseActive, isTrue);
    expect(scientificKey('asin'), findsOneWidget);
    expect(scientificKey('sin'), findsNothing);
    await tapAll(tester, <Finder>[scientificKey('asin')]);
    expect(stateOf(container).isInverseActive, isFalse);
    expect(notifier.expressionText(), 'sin()asin()');

    // A fraction typed across both tabs.
    notifier.setActiveTab(0);
    await settle(tester);
    await tapAll(tester, <Finder>[standardKey('AC')]);
    notifier.setActiveTab(1);
    await settle(tester);
    await tapAll(tester, <Finder>[scientificKey('fraction')]);
    notifier.setActiveTab(0);
    await settle(tester);
    await tapAll(tester, <Finder>[standardKey('1'), standardKey('▼'), standardKey('2'), standardKey('▶'), standardKey('+'), standardKey('3')]);
    expect(notifier.expressionText(), '((1)/(2))+3');
    expect(stateOf(container).livePreviewPrimary, '3.5');
  });

  testWidgets('gesture isolation: only the display card and the tab bar switch tabs', (tester) async {
    final container = await pumpCalculator(tester);
    expect(stateOf(container).activeTabIndex, 0);

    // A hard horizontal fling across the keypad does nothing - whether it
    // starts on a key or in the gap between keys.
    await tester.fling(standardKey('6'), const Offset(-300, 0), 2000);
    await settle(tester);
    expect(stateOf(container).activeTabIndex, 0);
    await tester.fling(find.byType(StandardTabView), const Offset(-300, 0), 2000, warnIfMissed: false);
    await settle(tester);
    expect(stateOf(container).activeTabIndex, 0);
    expect(stateOf(container).rootSequence.isEmpty, isTrue, reason: 'a fling is not a key press');

    // The same fling on the display card moves to the next tab …
    await tester.fling(find.byType(PersistentDisplayCard), const Offset(-200, 0), 2000);
    await settle(tester);
    expect(stateOf(container).activeTabIndex, 1);

    // … and on the tab bar back again.
    await tester.fling(find.byType(SegmentedTabBar).first, const Offset(200, 0), 2000);
    await settle(tester);
    expect(stateOf(container).activeTabIndex, 0);

    // Tapping a segment selects it directly.
    await tester.tap(find.text('History'));
    await settle(tester);
    expect(stateOf(container).activeTabIndex, 4);
  });

  testWidgets('the pull-down handle opens the quick history', (tester) async {
    final container = await pumpCalculator(tester);
    await tapAll(tester, <Finder>[standardKey('9'), standardKey('−'), standardKey('4'), standardKey('=')]);
    expect(find.text('RECENT CALCULATIONS'), findsNothing);
    await tester.tap(find.bySemanticsLabel('Open quick history'));
    await settle(tester);
    expect(find.text('RECENT CALCULATIONS'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await settle(tester);
    expect(find.text('RECENT CALCULATIONS'), findsNothing);
    expect(stateOf(container).livePreviewPrimary, '5');
  });

  group('responsive layout', () {
    const sizes = <String, Size>{
      'small phone 360x640': Size(360, 640),
      'phone 412x915': Size(412, 915),
      'phone landscape 800x360': Size(800, 360),
      'tablet 1280x800': Size(1280, 800),
    };

    for (final entry in sizes.entries) {
      testWidgets('${entry.key}: every tab and lab mode lays out without overflow', (tester) async {
        final container = await pumpCalculator(tester, size: entry.value);
        final notifier = container.read(calculatorProvider.notifier);
        final landscape = entry.value.width >= CalculatorShellScreen.landscapeBreakpoint;

        // Portrait shows one tab at a time; landscape pins the standard keypad
        // next to the specialised workspace.
        expect(standardKey('7').hitTestable(), findsOneWidget);
        expect(scientificKey('sin').hitTestable(), landscape ? findsOneWidget : findsNothing);

        notifier.pasteText('∫(0,1,√(x^2+1/(1+x)))+sin(30)×2^10');
        for (var tab = 0; tab < 5; tab++) {
          notifier.setActiveTab(tab);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'tab $tab');
        }
        notifier.setActiveTab(2);
        await settle(tester);
        for (final mode in AdvancedLabTabView.modes) {
          await tester.tap(find.descendant(of: find.byType(AdvancedLabTabView), matching: find.text(mode)).first);
          await settle(tester);
          expect(tester.takeException(), isNull, reason: 'lab mode $mode');
        }
        notifier.setActiveTab(3);
        await settle(tester);
        expect(find.byType(UnitConverterTabView), findsOneWidget);
        await commit(tester, container);
        expect(stateOf(container).inputPhase, InputPhase.committedResult);
        expect(stateOf(container).livePreviewPrimary, '513.0095131798541');
        expect(tester.takeException(), isNull);
      });
    }
  });

  testWidgets('lab: the quadratic solver finds exact roots', (tester) async {
    final container = await pumpCalculator(tester);
    container.read(calculatorProvider.notifier).setActiveTab(2);
    await settle(tester);
    Finder labKey(String label) => keyIn(AdvancedLabTabView, label).hitTestable();
    // 2x² + 5x − 3 = 0
    await tapAll(tester, <Finder>[labKey('2'), labKey('⏎'), labKey('5'), labKey('⏎'), labKey('−'), labKey('3')]);
    await tester.tap(find.text('Solve').hitTestable().first);
    await settle(tester);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('1/2  =  0.5'), findsOneWidget);
  });
}
