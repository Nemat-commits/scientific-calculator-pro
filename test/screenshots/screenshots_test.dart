// Renders the real UI into PNG files (build/screenshots/) for visual review.
//
// This is not an assertion suite; it only runs when asked for:
//   CALC_SCREENSHOTS=1 flutter test test/screenshots
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/domain/models/editor_node.dart';
import 'package:modern_scientific_calculator/domain/models/math_context.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/tabs/advanced_lab_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/history_vault_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/standard_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/tabs/unit_converter_tab_view.dart';
import 'package:modern_scientific_calculator/presentation/widgets/lab_widgets.dart';

import '../support/test_app.dart';

final bool enabled = Platform.environment['CALC_SCREENSHOTS'] == '1';
final GlobalKey boundary = GlobalKey();

Future<void> capture(WidgetTester tester, String name) async {
  await settle(tester);
  await tester.runAsync(() async {
    final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: tester.view.devicePixelRatio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File('build/screenshots/$name.png')..createSync(recursive: true);
    file.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

AtomKey digit(String d) => AtomKey(d, AtomKind.digit);
AtomKey op(String o) => AtomKey(o, AtomKind.binaryOp);
const MoveKey right = MoveKey(CursorDirection.right);
const MoveKey down = MoveKey(CursorDirection.down);

/// (−b + √(b² − 4ac)) / 2a with numbers, typed key by key.
void typeQuadraticFormula(CalculatorNotifier n) {
  for (final key in <CalcKey>[
    const TemplateKey(TemplateKind.fraction),
    op('−'),
    digit('5'),
    op('+'),
    const TemplateKey(TemplateKind.squareRoot),
    digit('5'),
    const TemplateKey(TemplateKind.square),
    op('−'),
    digit('4'),
    op('×'),
    digit('2'),
    op('×'),
    const AtomKey('(', AtomKind.paren),
    op('−'),
    digit('3'),
    const AtomKey(')', AtomKind.paren),
    down,
    digit('2'),
    op('×'),
    digit('2'),
  ]) {
    n.press(key);
  }
}

void main() {
  setUpAll(loadAppFonts);

  Future<ProviderContainer> start(WidgetTester tester, Size size) =>
      pumpCalculator(tester, size: size, pixelRatio: 2, boundaryKey: boundary);

  testWidgets('portrait screens', (tester) async {
    final container = await start(tester, const Size(412, 915));
    final n = container.read(calculatorProvider.notifier);
    Future<void> tapKeys(Type tab, List<String> names) async {
      for (final name in names) {
        await tester.tap(keyIn(tab, name).hitTestable().first);
        await tester.pump(const Duration(milliseconds: 40));
      }
    }

    Future<void> tapText(String text) async {
      var target = find.text(text).hitTestable();
      if (target.evaluate().isEmpty) {
        // Below the fold of a scrolling panel.
        await tester.ensureVisible(find.text(text).first);
        await settle(tester);
        target = find.text(text).hitTestable();
      }
      await tester.tap(target.first);
      await settle(tester);
    }

    await capture(tester, '01_portrait_empty');

    // The quick scientific keys, a parenthesis that is still open (ghost
    // parenthesis in the display, counter on the key) and a value in memory.
    await tapKeys(
        StandardTabView, <String>['Show the scientific keys', '2', '×', 'Parenthesis', '3', '+', 'sin', '4', '5']);
    await tester.tap(keyIn(StandardTabView, 'M+').hitTestable().first);
    await capture(tester, '02_portrait_quick_keys');
    await tester.tap(keyIn(StandardTabView, 'MC').hitTestable().first);
    await tapKeys(StandardTabView, <String>['Hide the scientific keys', 'All clear']);
    await settle(tester);

    typeQuadraticFormula(n);
    await capture(tester, '02_portrait_standard_editing');

    await commit(tester, container);
    await capture(tester, '03_portrait_standard_result');

    // ∫₀^π sin²x dx + ∛27 · e^(−1/2), in radians.
    n.press(const ClearKey());
    n.setActiveTab(1);
    while (stateOf(container).angleUnit != AngleUnit.rad) {
      n.cycleAngleUnit();
    }
    for (final key in <CalcKey>[
      const TemplateKey(TemplateKind.integral),
      digit('0'),
      right,
      const AtomKey('π', AtomKind.constant),
      right,
      const TemplateKey(TemplateKind.function, name: 'sin'),
      const AtomKey('x', AtomKind.variable),
      right,
      const TemplateKey(TemplateKind.square),
      right,
      op('+'),
      const TemplateKey(TemplateKind.nthRoot),
      digit('3'),
      right,
      digit('2'),
      digit('7'),
      right,
      op('×'),
      const AtomKey('e', AtomKind.constant),
      const TemplateKey(TemplateKind.power),
      op('−'),
      const TemplateKey(TemplateKind.fraction),
      digit('1'),
      down,
      digit('2'),
    ]) {
      n.press(key);
    }
    await capture(tester, '04_portrait_scientific');

    n.toggleInverse();
    await capture(tester, '05_portrait_scientific_inv');
    n.toggleInverse();
    await commit(tester, container);
    await capture(tester, '05_portrait_scientific_result');
    while (stateOf(container).angleUnit != AngleUnit.deg) {
      n.cycleAngleUnit();
    }

    // A line that is too long for the display shrinks first, then scrolls.
    n.press(const ClearKey());
    n.pasteText('1+2+3+4+5+6+7+8+9+10+11+12+13+14+15+16+17+18+19+20+21+22+23+24+25');
    await capture(tester, '05_portrait_long_expression');
    n.press(const ClearKey());
    n.pasteText('x^2-3x+2');

    // Lab: 2x² + 5x − 3 = 0
    n.setActiveTab(2);
    await settle(tester);
    await tapKeys(AdvancedLabTabView, <String>['2', '⏎', '5', '⏎', '−', '3']);
    await tapText('Solve');
    await capture(tester, '06_portrait_lab_solver');

    await tapText('Matrix');
    await tapKeys(AdvancedLabTabView, <String>['2', '⏎', '1', '⏎', '1', '⏎', '3', '⏎']);
    await tapText('A⁻¹');
    await capture(tester, '07_portrait_lab_matrix');

    await tapText('Table');
    await tapText('Run');
    await capture(tester, '07_portrait_lab_table');

    await tapText('Stats');
    for (final value in <String>['2', '4', '4', '5', '7', '9']) {
      await tapKeys(AdvancedLabTabView, <String>[value, 'Add']);
    }
    await capture(tester, '07_portrait_lab_stats');

    await tapText('Base-N');
    await tapKeys(AdvancedLabTabView, <String>['F', 'F', 'AND', '3', 'C']);
    await capture(tester, '07_portrait_lab_basen');

    n.setActiveTab(3);
    await settle(tester);
    await tapKeys(UnitConverterTabView, <String>['2', '.', '5']);
    await capture(tester, '08_portrait_convert');
    // "Constants" is the last chip of a horizontally scrolling row.
    await tester.drag(
      find.descendant(of: find.byType(UnitConverterTabView), matching: find.byType(ChoiceChips)),
      const Offset(-1200, 0),
    );
    await settle(tester);
    await tapText('Constants');
    await capture(tester, '08_portrait_constants');

    n.press(const ClearKey());
    for (final expression in <String>['1/3+1/6', '5000!', 'sin(30)+cos(60)', '2^64']) {
      n.pasteText(expression);
      await commit(tester, container);
      n.press(const ClearKey());
    }
    n.setActiveTab(4);
    await capture(tester, '09_portrait_history');

    await tester.longPress(find.byType(HistoryTile).at(2));
    await capture(tester, '09_portrait_history_detail');
    await tapText('Close');

    // The folded display opened in place.
    await tester.tap(find.bySemanticsLabel('Expand display'));
    await capture(tester, '09_portrait_history_display_open');

    n.setActiveTab(0);
    await settle(tester);
    await tester.tap(find.bySemanticsLabel('Open quick history'));
    await capture(tester, '09_portrait_quick_history');
    await tapText('Close');

    n.pasteText('1/0');
    await commit(tester, container);
    await capture(tester, '10_portrait_error');

    // The hint that explains a mode when its badge is tapped.
    n.press(const ClearKey());
    await tester.tap(find.bySemanticsLabel('Implied multiplication: TI'));
    await capture(tester, '10_portrait_mode_hint');
    await tester.pump(const Duration(seconds: 2));
  }, skip: !enabled);

  testWidgets('landscape workbench', (tester) async {
    final container = await start(tester, const Size(1280, 800));
    final n = container.read(calculatorProvider.notifier);
    typeQuadraticFormula(n);
    await capture(tester, '11_tablet_scientific');
    n.setActiveTab(2);
    await capture(tester, '12_tablet_lab');
  }, skip: !enabled);

  testWidgets('phone landscape', (tester) async {
    final container = await start(tester, const Size(800, 360));
    typeQuadraticFormula(container.read(calculatorProvider.notifier));
    await capture(tester, '13_phone_landscape');
  }, skip: !enabled);

  testWidgets('small phone', (tester) async {
    final container = await start(tester, const Size(360, 640));
    final n = container.read(calculatorProvider.notifier);
    typeQuadraticFormula(n);
    await capture(tester, '14_small_phone');

    n.setActiveTab(1);
    await capture(tester, '14_small_phone_scientific');

    // Base-N: all four bases fit once the display is folded.
    n.setActiveTab(2);
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(AdvancedLabTabView), matching: find.text('Base-N')).first);
    await settle(tester);
    for (final name in <String>['F', 'F', 'AND', '3', 'C']) {
      await tester.tap(keyIn(AdvancedLabTabView, name).hitTestable().first);
      await tester.pump(const Duration(milliseconds: 40));
    }
    await capture(tester, '15_small_phone_basen');

    // Converter: an empty field reads 0 and converts as 0.
    n.setActiveTab(3);
    await settle(tester);
    await tester.tap(find.descendant(of: find.byType(UnitConverterTabView), matching: find.text('Temperature')).first);
    await settle(tester);
    await tester.tap(keyIn(UnitConverterTabView, 'Clear').hitTestable().first);
    await capture(tester, '16_small_phone_convert_zero');
  }, skip: !enabled);
}
