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
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/tabs/advanced_lab_tab_view.dart';

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
    op('−'), digit('5'), op('+'),
    const TemplateKey(TemplateKind.squareRoot),
    digit('5'), const TemplateKey(TemplateKind.square), op('−'), digit('4'), op('×'), digit('2'), op('×'),
    const AtomKey('(', AtomKind.paren), op('−'), digit('3'), const AtomKey(')', AtomKind.paren),
    down,
    digit('2'), op('×'), digit('2'),
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

    await capture(tester, '01_portrait_empty');

    typeQuadraticFormula(n);
    await capture(tester, '02_portrait_standard_editing');

    await n.evaluate();
    await capture(tester, '03_portrait_standard_result');

    n.press(const ClearKey());
    n.setActiveTab(1);
    for (final key in <CalcKey>[
      const TemplateKey(TemplateKind.integral),
      digit('0'), right,
      const AtomKey('π', AtomKind.constant), right,
      const TemplateKey(TemplateKind.function, name: 'sin'),
      const AtomKey('x', AtomKind.variable), right,
      const TemplateKey(TemplateKind.square),
      right, op('+'),
      const TemplateKey(TemplateKind.nthRoot), digit('3'), right, digit('2'), digit('7'), right,
      op('×'), const AtomKey('e', AtomKind.constant), const TemplateKey(TemplateKind.power), op('−'),
      const TemplateKey(TemplateKind.fraction), digit('1'), down, digit('2'),
    ]) {
      n.press(key);
    }
    await capture(tester, '04_portrait_scientific');

    n.toggleInverse();
    await capture(tester, '05_portrait_scientific_inv');
    n.toggleInverse();

    n.setActiveTab(2);
    await capture(tester, '06_portrait_lab_solver');
    for (final mode in AdvancedLabTabView.modes.skip(1)) {
      await tester.tap(find.descendant(of: find.byType(AdvancedLabTabView), matching: find.text(mode)).first);
      await capture(tester, '07_portrait_lab_${mode.toLowerCase().replaceAll('-', '')}');
    }

    n.setActiveTab(3);
    await capture(tester, '08_portrait_convert');

    n.press(const ClearKey());
    for (final expression in <String>['1/3+1/6', '5000!', 'sin(30)+cos(60)', '2^64']) {
      n.pasteText(expression);
      await n.evaluate();
      await settle(tester);
      n.press(const ClearKey());
    }
    n.setActiveTab(4);
    await capture(tester, '09_portrait_history');

    n.setActiveTab(0);
    n.pasteText('1/0');
    await n.evaluate();
    await capture(tester, '10_portrait_error');
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
    typeQuadraticFormula(container.read(calculatorProvider.notifier));
    await capture(tester, '14_small_phone');
  }, skip: !enabled);
}
