// The layout and interaction changes of version 3.1: the folding display,
// the mode hints, the reworked keypads and the "send to calculator" paths.
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/core/constants/unit_definitions.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/presentation/screens/calculator_shell_screen.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_ui_state.dart';
import 'package:modern_scientific_calculator/presentation/tabs/advanced_lab_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/history_vault_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/scientific_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/standard_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/unit_converter_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/widgets/app_toast.dart';
import 'package:modern_scientific_calculator/presentation/widgets/calc_key_button.dart';
import 'package:modern_scientific_calculator/presentation/widgets/key_legend.dart';
import 'package:modern_scientific_calculator/presentation/widgets/math_print_canvas.dart';
import 'package:modern_scientific_calculator/presentation/widgets/persistent_display_card.dart';
import 'package:modern_scientific_calculator/presentation/widgets/result_text.dart';

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

double cardHeight(WidgetTester tester) => tester.getSize(find.byType(PersistentDisplayCard)).height;

/// Long enough for a hint to fade in (or for the one before it to fade out).
Future<void> shortly(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 250));
}

void main() {
  setUpAll(loadAppFonts);

  group('display card', () {
    test('is a third of the screen when open, between 210 and 310 dp', () {
      expect(CalculatorShellScreen.displayHeight(800, 760), 264);
      expect(CalculatorShellScreen.displayHeight(600, 560), 210, reason: 'lower limit');
      expect(CalculatorShellScreen.displayHeight(1100, 1060), 310, reason: 'upper limit');
      expect(CalculatorShellScreen.displayHeight(380, 340), 153, reason: 'a short window keeps room for the keys');
    });

    testWidgets('folds into a bar on the tabs that bring their own read-out', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      final full = cardHeight(tester);
      expect(full, CalculatorShellScreen.displayHeight(915, 915 - 18));
      notifier.pasteText('6×7');
      await commit(tester, container);

      for (final tab in <int>[2, 3, 4]) {
        notifier.setActiveTab(tab);
        await settle(tester);
        expect(cardHeight(tester), PersistentDisplayCard.barHeight, reason: 'tab $tab');
        // The bar keeps the mode badges and shows the last answer.
        expect(find.bySemanticsLabel('Angle unit: DEG'), findsOneWidget);
        expect(find.bySemanticsLabel('Ans: 42'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // The keypads keep the full display.
      for (final tab in <int>[1, 0]) {
        notifier.setActiveTab(tab);
        await settle(tester);
        expect(cardHeight(tester), full, reason: 'tab $tab');
        expect(find.bySemanticsLabel('Expand display'), findsNothing);
      }
    });

    testWidgets('the bar opens in place and folds again; a tab change resets it', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      final full = cardHeight(tester);
      notifier.setActiveTab(4);
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Expand display'));
      await settle(tester);
      expect(cardHeight(tester), full);
      expect(stateOf(container).activeTabIndex, 4, reason: 'the tab stays');

      await tester.tap(find.bySemanticsLabel('Collapse display'));
      await settle(tester);
      expect(cardHeight(tester), PersistentDisplayCard.barHeight);

      await tester.tap(find.bySemanticsLabel('Expand display'));
      await settle(tester);
      notifier.setActiveTab(3);
      await settle(tester);
      expect(cardHeight(tester), PersistentDisplayCard.barHeight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never folds in the dual-pane layout', (tester) async {
      final container = await pumpCalculator(tester, size: const Size(1280, 800));
      final full = cardHeight(tester);
      for (final tab in <int>[2, 3, 4]) {
        container.read(calculatorProvider.notifier).setActiveTab(tab);
        await settle(tester);
        expect(cardHeight(tester), full);
        expect(find.bySemanticsLabel('Expand display'), findsNothing);
      }
    });

    testWidgets('a mode badge explains its mode for a moment, and the explanation is true', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      Future<String> result(String expression) async {
        notifier
          ..press(const ClearKey())
          ..pasteText(expression);
        await commit(tester, container);
        final state = stateOf(container);
        return state.inputPhase == InputPhase.errorLocked ? 'error' : state.livePreviewPrimary;
      }

      expect(await result('6÷2(1+2)'), '9');
      expect(await result('√(−1)'), 'error');

      await tester.tap(find.bySemanticsLabel('Implied multiplication: TI'));
      await shortly(tester);
      expect(stateOf(container).juxtapositionMode, JuxtapositionMode.strictCasio);
      expect(find.text('CASIO mode · 6 ÷ 2(1+2) = 1'), findsOneWidget);
      expect(await result('6÷2(1+2)'), '1');

      // The hint goes away by itself.
      await tester.pump(ToastHost.duration);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('CASIO mode'), findsNothing);

      await tester.tap(find.bySemanticsLabel('Implied multiplication: CASIO'));
      await shortly(tester);
      expect(find.text('TI / standard mode · 6 ÷ 2(1+2) = 9'), findsOneWidget);

      // A second hint replaces the first one at once.
      await tester.tap(find.bySemanticsLabel('REAL'));
      await shortly(tester);
      expect(find.textContaining('TI / standard mode'), findsNothing);
      expect(find.textContaining('Complex mode'), findsOneWidget);
      expect(await result('√(−1)'), '0 + 1i');

      await tester.tap(find.bySemanticsLabel('CPLX'));
      await shortly(tester);
      expect(find.textContaining('Real mode'), findsOneWidget);
      await tester.pump(ToastHost.duration);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.textContaining('Real mode'), findsNothing);
    });
  });

  group('expression line', () {
    testWidgets('an empty line shows a muted 0 in front of the caret', (tester) async {
      await pumpCalculator(tester);
      expect(tester.widget<MathPrintCanvas>(find.byType(MathPrintCanvas)).placeholder, '0');

      final plain = MathLayoutEngine(fontSize: 32).layout(EditorSequence.root());
      final hinted = MathLayoutEngine(fontSize: 32, placeholder: '0').layout(EditorSequence.root());
      final zero = MathLayoutEngine(fontSize: 32).layout(EditorSequence.root(const <EditorNode>[
        AtomNode('0', AtomKind.digit),
      ]));
      // As wide as a typed 0, and the caret stands behind it - where it
      // stays when the first digit replaces the placeholder.
      expect(hinted.size.width, greaterThan(plain.size.width));
      expect(
          hinted.slot(EditorSequence.rootId)!.caretX.single, closeTo(zero.slot(EditorSequence.rootId)!.caretX.last, 3));
      // A line with content has no placeholder.
      final withHint = MathLayoutEngine(fontSize: 32, placeholder: '0').layout(EditorSequence.root(const <EditorNode>[
        AtomNode('0', AtomKind.digit),
      ]));
      expect(withHint.size, zero.size);
    });

    testWidgets('parentheses that are still open are drawn as ghosts behind the caret', (tester) async {
      await pumpCalculator(tester);
      EditorSequence line(String text) => EditorSequence.root(<EditorNode>[
            for (final c in text.split(''))
              AtomNode(
                  c, switch (c) { '(' || ')' => AtomKind.paren, '+' || '×' => AtomKind.binaryOp, _ => AtomKind.digit }),
          ]);
      MathLayout layout(String text) => MathLayoutEngine(fontSize: 32).layout(line(text));

      final open = layout('2×((3+4'), closed = layout('2×((3+4))');
      // Two ghosts take the room of two parentheses …
      expect(open.size.width, closeTo(closed.size.width, 0.5));
      // … but the caret cannot go behind them: 7 positions for 7 symbols + 1.
      final carets = open.slot(EditorSequence.rootId)!.caretX;
      expect(carets, hasLength(8));
      expect(carets.last, lessThan(closed.slot(EditorSequence.rootId)!.caretX.last - 10));
      // Nothing is added to a balanced line.
      expect(layout('2×(3+4)').size.width, lessThan(open.size.width));
    });
  });

  group('standard tab', () {
    testWidgets('the quick scientific keys type a formula without a tab change', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      expect(standardKey('sin'), findsNothing);

      await tapAll(tester, <Finder>[standardKey('Show the scientific keys')]);
      for (final name in <String>['sin', 'cos', 'tan', 'ln', 'square root', 'square', 'power', 'pi']) {
        expect(standardKey(name).hitTestable(), findsOneWidget, reason: name);
      }
      // 2 × sin(45) + √16
      await tapAll(tester, <Finder>[
        standardKey('2'),
        standardKey('×'),
        standardKey('sin'),
        standardKey('4'),
        standardKey('5'),
        standardKey('Cursor right'),
        standardKey('+'),
        standardKey('square root'),
        standardKey('1'),
        standardKey('6'),
      ]);
      expect(notifier.expressionText(), '2×sin(45)+√(16)');
      expect(stateOf(container).livePreviewPrimary, startsWith('5.41421356237'));
      expect(stateOf(container).activeTabIndex, 0);
      expect(tester.takeException(), isNull);

      await tapAll(tester, <Finder>[standardKey('Hide the scientific keys')]);
      expect(standardKey('sin'), findsNothing);
    });

    testWidgets('the parenthesis key counts the groups that are still open', (tester) async {
      final container = await pumpCalculator(tester);
      final anyBadge = find.bySemanticsLabel(RegExp(r'^\d+ open$'));
      expect(anyBadge, findsNothing);

      await tapAll(tester, <Finder>[standardKey('Parenthesis'), standardKey('Parenthesis'), standardKey('7')]);
      expect(container.read(calculatorProvider.notifier).expressionText(), '((7');
      expect(stateOf(container).unclosedParenthesesCount, 2);
      expect(find.bySemanticsLabel('2 open'), findsOneWidget);

      await tapAll(tester, <Finder>[standardKey('Parenthesis')]);
      expect(find.bySemanticsLabel('1 open'), findsOneWidget);
      await tapAll(tester, <Finder>[standardKey('Parenthesis')]);
      expect(container.read(calculatorProvider.notifier).expressionText(), '((7))');
      expect(anyBadge, findsNothing);

      // A committed result has nothing open.
      await tapAll(tester, <Finder>[standardKey('All clear'), standardKey('Parenthesis'), standardKey('7')]);
      expect(find.bySemanticsLabel('1 open'), findsOneWidget);
      await tapAll(tester, <Finder>[standardKey('=')]);
      expect(stateOf(container).livePreviewPrimary, '7');
      expect(anyBadge, findsNothing);
    });

    testWidgets('MC and MR light up while the memory holds a value', (tester) async {
      final container = await pumpCalculator(tester);
      CalcKeyButton key(String name) => tester.widget<CalcKeyButton>(standardKey(name));
      expect(key('MC').emphasised, isFalse);
      expect(key('MR').emphasised, isFalse);

      await tapAll(tester, <Finder>[standardKey('7'), standardKey('M+')]);
      expect(stateOf(container).hasMemory, isTrue);
      expect(key('MC').emphasised, isTrue);
      expect(key('MR').emphasised, isTrue);
      expect(key('M+').emphasised, isFalse);

      await tapAll(tester, <Finder>[standardKey('MC')]);
      expect(key('MC').emphasised, isFalse);
      expect(key('MR').emphasised, isFalse);
    });
  });

  group('scientific tab', () {
    testWidgets('has its own =, AC, backspace and memory strip', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.setActiveTab(1);
      await settle(tester);

      // gcd(84, 36): gcd is in the row that f(x) opens, and the "," key moves
      // on to the second argument.
      await tapAll(tester, <Finder>[scientificKey('Show more functions')]);
      await tapAll(tester, <Finder>[scientificKey('gcd')]);
      notifier.pasteText('84');
      await tapAll(tester, <Finder>[scientificKey('Next argument')]);
      notifier.pasteText('36');
      expect(notifier.expressionText(), 'gcd(84,36)');

      await tapAll(tester, <Finder>[scientificKey('Equals')]);
      expect(stateOf(container).inputPhase, InputPhase.committedResult);
      expect(stateOf(container).livePreviewPrimary, '12');
      expect(stateOf(container).activeTabIndex, 1);

      await tapAll(tester, <Finder>[scientificKey('M+'), scientificKey('All clear')]);
      expect(stateOf(container).hasMemory, isTrue);
      expect(stateOf(container).rootSequence.isEmpty, isTrue);

      await tapAll(tester, <Finder>[scientificKey('MR'), scientificKey('Backspace')]);
      expect(stateOf(container).rootSequence.isEmpty, isTrue);
      await tapAll(tester, <Finder>[scientificKey('MR'), scientificKey('Equals')]);
      expect(stateOf(container).livePreviewPrimary, '12');

      // lcm stands next to it.
      await tapAll(tester, <Finder>[scientificKey('All clear'), scientificKey('lcm')]);
      notifier.pasteText('4');
      await tapAll(tester, <Finder>[scientificKey('Next argument')]);
      notifier.pasteText('6');
      await tapAll(tester, <Finder>[scientificKey('Equals')]);
      expect(stateOf(container).livePreviewPrimary, '12');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a key names in its corner what INV turns it into', (tester) async {
      final container = await pumpCalculator(tester);
      container.read(calculatorProvider.notifier).setActiveTab(1);
      await settle(tester);
      // The hint in the corner of a key.
      KeyLegend corner(String key) => tester.widget<KeyLegend>(
            find.descendant(
              of: scientificKey(key),
              matching: find.byWidgetPredicate((w) => w is KeyLegend && w.size <= ScientificTabView.cornerLegendSize),
            ),
          );

      expect((corner('sin').text, corner('sin').sup), ('sin', '−1'));
      expect((corner('ln').text, corner('ln').sup), ('e', 'x'));
      expect(corner('factorial').text, 'mod');
      expect(corner('Ans').text, 'M');

      // While INV is on, the key shows the inverse and the corner the way back.
      await tapAll(tester, <Finder>[scientificKey('INV')]);
      expect((corner('asin').text, corner('asin').sup), ('sin', null));
      expect(corner('e to the x').text, 'ln');

      // Keys without a second function have no hint.
      expect(
        find.descendant(of: scientificKey('integral'), matching: find.byType(KeyLegend)),
        findsOneWidget,
      );
    });

    testWidgets('next to the standard keypad it leaves the strip to that keypad', (tester) async {
      await pumpCalculator(tester, size: const Size(1280, 800));
      expect(scientificKey('sin').hitTestable(), findsOneWidget);
      expect(scientificKey('Equals').hitTestable(), findsOneWidget);
      expect(scientificKey('MR'), findsNothing);
      expect(standardKey('MR').hitTestable(), findsOneWidget);
    });
  });

  group('converter', () {
    Finder inConverter(Finder finder) => find.descendant(of: find.byType(UnitConverterTabView), matching: finder);

    testWidgets('an empty field reads 0 and converts as 0', (tester) async {
      final container = await pumpCalculator(tester);
      container.read(calculatorProvider.notifier).setActiveTab(3);
      await settle(tester);
      await tester.tap(inConverter(find.text('Temperature')));
      await settle(tester);
      expect(inConverter(find.text('33.8')), findsOneWidget, reason: '1 °C in °F');

      await tester.tap(keyIn(UnitConverterTabView, 'Clear').hitTestable());
      await settle(tester);
      expect(inConverter(find.text('32')), findsOneWidget, reason: '0 °C in °F');
      expect(inConverter(find.text('273.15')), findsOneWidget, reason: '0 °C in K');
      expect(inConverter(find.text('—')), findsNothing);

      // A typed 0 is the same thing.
      await tester.tap(keyIn(UnitConverterTabView, '0').hitTestable());
      await settle(tester);
      expect(inConverter(find.text('32')), findsOneWidget);
    });

    testWidgets('the arrow of a row sends its value to the calculator', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.pasteText('2×');
      notifier.setActiveTab(3);
      await settle(tester);
      await tester.tap(inConverter(find.text('Temperature')));
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Use the value in Fahrenheit in the calculator'));
      await settle(tester);
      expect(stateOf(container).activeTabIndex, 0, reason: 'back at the keypad');
      expect(notifier.expressionText(), '2×33.8');
      expect(stateOf(container).livePreviewPrimary, '67.6');
    });

    group('data units', () {
      Future<void> openData(WidgetTester tester, {Size? size}) async {
        final container = size == null ? await pumpCalculator(tester) : await pumpCalculator(tester, size: size);
        container.read(calculatorProvider.notifier).setActiveTab(3);
        await settle(tester);
        final data = inConverter(find.text('Data'));
        await tester.ensureVisible(data);
        await settle(tester);
        await tester.tap(data);
        await settle(tester);
      }

      /// The values of the rows that are not being typed, top to bottom.
      List<String> shown(WidgetTester tester) =>
          tester.widgetList<ResultText>(inConverter(find.byType(ResultText))).map((r) => r.value).toList();

      Future<void> oneOf(WidgetTester tester, String symbol) async {
        await tester.tap(inConverter(find.text(symbol)));
        await settle(tester);
        await tester.tap(keyIn(UnitConverterTabView, 'Clear').hitTestable());
        await tester.tap(keyIn(UnitConverterTabView, '1').hitTestable());
        await settle(tester);
      }

      testWidgets('every line says how its unit is built, and a note tells the two families apart', (tester) async {
        await openData(tester);
        for (final step in <String>['1000 B', '1024 B', '1000 kB', '1024 KiB', '1000 MB', '1024 MiB']) {
          expect(inConverter(find.text(step)), findsOneWidget, reason: step);
        }
        expect(inConverter(find.text(UnitDefinitions.dataNote)), findsOneWidget);
        expect(UnitDefinitions.dataNote, allOf(contains('steps of 1000'), contains('steps of 1024')));
        // The names are written out in full where there is room for all of them.
        expect(inConverter(find.text('Megabyte')), findsOneWidget);
        expect(inConverter(find.text('Mebibyte')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });

      testWidgets('1 MB is 1000 kB, and 1 MiB is 1024 KiB', (tester) async {
        await openData(tester);
        await oneOf(tester, 'MB');
        // bit, B, kB, KiB, then MiB and GB behind the line being typed.
        expect(shown(tester).take(6), <String>['8000000', '1000000', '1000', '976.5625', '0.953674316406', '0.001']);

        await oneOf(tester, 'MiB');
        expect(shown(tester).take(5), <String>['8388608', '1048576', '1048.576', '1024', '1.048576']);
        expect(tester.takeException(), isNull);
      });

      testWidgets('step and name stand side by side, and one above the other on a narrow screen', (tester) async {
        Rect of(String text) => tester.getRect(inConverter(find.text(text)));

        await openData(tester);
        expect(of('1000 B').right, lessThan(of('Kilobyte').left));
        expect(of('1000 B').center.dy, moreOrLessEquals(of('Kilobyte').center.dy, epsilon: 2));

        await openData(tester, size: const Size(360, 640));
        for (final (step, name) in <(String, String)>[('1000 B', 'Kilobyte'), ('1024 B', 'Kibibyte')]) {
          expect(of(step).bottom, lessThanOrEqualTo(of(name).top + 0.5), reason: '$step above $name');
          expect(of(step).left, moreOrLessEquals(of(name).left, epsilon: 0.5));
          for (final text in <String>[step, name]) {
            expect(tester.renderObject<RenderParagraph>(inConverter(find.text(text))).didExceedMaxLines, isFalse);
          }
        }
        expect(tester.takeException(), isNull);
      });
    });

    testWidgets('a long unit name takes a second line, so that what tells two units apart is not cut', (tester) async {
      for (final size in <Size>[const Size(412, 915), const Size(360, 640)]) {
        final container = await pumpCalculator(tester, size: size);
        container.read(calculatorProvider.notifier).setActiveTab(3);
        await settle(tester);
        for (final category in UnitDefinitions.categories) {
          final chip = inConverter(find.text(category.name));
          await tester.ensureVisible(chip);
          await settle(tester);
          await tester.tap(chip);
          await settle(tester);
          // The list builds its lines as they scroll into view.
          final seen = <String>{};
          for (var page = 0; page < 4; page++) {
            for (final unit in category.units) {
              final name = inConverter(find.text(unit.name));
              if (name.evaluate().isEmpty) continue;
              seen.add(unit.name);
              // (The torr is its own symbol: two texts.)
              expect(
                tester.renderObjectList<RenderParagraph>(name).any((text) => text.didExceedMaxLines),
                isFalse,
                reason: '${unit.name} at a width of ${size.width}',
              );
            }
            await tester.drag(inConverter(find.byType(Scrollable)).last, const Offset(0, -160));
            await settle(tester);
          }
          expect(
            seen,
            containsAll(category.units.map((u) => u.name)),
            reason: '${category.name} at a width of ${size.width}',
          );
        }
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('the selected category chip scrolls into view', (tester) async {
      final container = await pumpCalculator(tester, size: const Size(360, 640));
      container.read(calculatorProvider.notifier).setActiveTab(3);
      await settle(tester);
      // "Volume" is cut off at the right edge of a narrow screen.
      final volume = inConverter(find.text('Volume'));
      final before = tester.getRect(volume);
      expect(before.right, greaterThan(348));
      await tester.tapAt(before.centerLeft + const Offset(4, 0));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 300));

      final after = tester.getRect(volume);
      expect(after.right, lessThan(348), reason: 'the whole chip is on screen');
      expect((after.center.dx - 180).abs(), lessThan(40), reason: 'near the middle of the row');
    });
  });

  group('lab', () {
    testWidgets('Base-N on a small phone: every base is on screen, binary in whole bytes', (tester) async {
      final container = await pumpCalculator(tester, size: const Size(360, 640));
      final notifier = container.read(calculatorProvider.notifier);
      notifier.setActiveTab(2);
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(AdvancedLabTabView), matching: find.text('Base-N')).first);
      await settle(tester);
      Finder labKey(String label) => keyIn(AdvancedLabTabView, label).hitTestable();

      await tapAll(tester, <Finder>[labKey('F'), labKey('F'), labKey('AND'), labKey('3'), labKey('C')]);
      for (final row in <String>['HEX 3C', 'DEC 60', 'OCT 74', 'BIN 0011 1100']) {
        expect(find.bySemanticsLabel(row).hitTestable(), findsOneWidget, reason: row);
      }

      // A tap on a row selects that base; keys outside the base are disabled.
      expect(tester.widget<CalcKeyButton>(labKey('2')).onPressed, isNotNull);
      await tester.tap(find.bySemanticsLabel('BIN 0011 1100'));
      await settle(tester);
      expect(tester.widget<CalcKeyButton>(labKey('2')).onPressed, isNull);
      expect(tester.widget<CalcKeyButton>(labKey('F')).onPressed, isNull);
      expect(tester.widget<CalcKeyButton>(labKey('1')).onPressed, isNotNull);

      // The decimal value goes to the calculator.
      await tester.tap(find.bySemanticsLabel('Use the decimal value in the calculator'));
      await settle(tester);
      expect(stateOf(container).activeTabIndex, 0);
      expect(notifier.expressionText(), '60');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a solver root can be sent to the calculator', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.pasteText('10+');
      notifier.setActiveTab(2);
      await settle(tester);
      Finder labKey(String label) => keyIn(AdvancedLabTabView, label).hitTestable();
      // 2x² + 5x − 3 = 0 has the roots −3 and 1/2.
      await tapAll(tester, <Finder>[labKey('2'), labKey('⏎'), labKey('5'), labKey('⏎'), labKey('−'), labKey('3')]);
      await tester.tap(find.text('Solve').hitTestable().first);
      await settle(tester);

      await tester.tap(find.bySemanticsLabel('Use x1 in the calculator'));
      await settle(tester);
      expect(stateOf(container).activeTabIndex, 0);
      // A negative number stays one operand.
      expect(notifier.expressionText(), '10+(−3)');
      expect(stateOf(container).livePreviewPrimary, '7');
    });
  });

  group('history', () {
    testWidgets('a tap recalls the expression for editing and returns to the keypad', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.pasteText('(1+2)×3');
      await commit(tester, container);
      notifier
        ..press(const ClearKey())
        ..setActiveTab(4);
      await settle(tester);

      await tester.tap(find.byType(HistoryTile).first);
      await settle(tester);
      expect(stateOf(container).activeTabIndex, 0);
      expect(stateOf(container).inputPhase, InputPhase.editing);
      expect(notifier.expressionText(), '(1+2)×3');

      // The recalled line is a tree again: a digit inside it can be changed.
      await tapAll(tester, <Finder>[standardKey('Backspace'), standardKey('5')]);
      expect(notifier.expressionText(), '(1+2)×5');
      expect(stateOf(container).livePreviewPrimary, '15');
    });

    testWidgets('Ans inserts the result at the caret and returns to the keypad', (tester) async {
      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.pasteText('(1+2)×3');
      await commit(tester, container);
      notifier
        ..press(const ClearKey())
        ..pasteText('2×')
        ..setActiveTab(4);
      await settle(tester);

      await tester.tap(find.descendant(of: find.byType(HistoryTile).first, matching: find.text('Ans')));
      await settle(tester);
      expect(stateOf(container).activeTabIndex, 0);
      expect(notifier.expressionText(), '2×9');
    });

    testWidgets('a long press opens the entry in full; its buttons copy', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map<Object?, Object?>)['text']! as String);
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));

      final container = await pumpCalculator(tester);
      final notifier = container.read(calculatorProvider.notifier);
      notifier.pasteText('1/7');
      await commit(tester, container);
      notifier.setActiveTab(4);
      await settle(tester);

      await tester.longPress(find.byType(HistoryTile).first);
      await settle(tester);
      expect(find.text('Copy expression'), findsOneWidget);
      // Every digit of the result at full size.
      expect(find.textContaining('0.1428571428571428571428571428571429'), findsWidgets);

      await tester.tap(find.text('Copy result'));
      await settle(tester);
      expect(copied, <String>['0.1428571428571428571428571428571429']);
      expect(find.text('Copy expression'), findsNothing, reason: 'the sheet closes');
      expect(find.text('Result copied'), findsOneWidget);

      await tester.longPress(find.byType(HistoryTile).first);
      await settle(tester);
      await tester.tap(find.text('Copy expression'));
      await settle(tester);
      expect(copied.last, '1÷7');

      await tester.longPress(find.byType(HistoryTile).first);
      await settle(tester);
      await tester.tap(find.text('Close'));
      await settle(tester);
      expect(find.text('Copy expression'), findsNothing);
      expect(stateOf(container).activeTabIndex, 4);

      await tester.pump(ToastHost.duration);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Expression copied'), findsNothing);
    });
  });
}
