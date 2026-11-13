import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/domain/editor/calc_key.dart';
import 'package:modern_scientific_calculator/domain/editor/math_print_controller.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/widgets/math_print_canvas.dart';

import '../support/test_app.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('a long line shrinks to fit first, then scrolls and keeps the caret in view', (tester) async {
    final container = await pumpCalculator(tester);
    final notifier = container.read(calculatorProvider.notifier);
    ScrollPosition position() => tester
        .widget<SingleChildScrollView>(
          find.descendant(of: find.byType(MathPrintCanvas), matching: find.byType(SingleChildScrollView)),
        )
        .controller!
        .position;

    // Wider than the display at full size, narrow enough once it is shrunk.
    notifier.pasteText('12+34+56+78+90+12+34');
    await settle(tester);
    expect(position().maxScrollExtent, lessThan(1), reason: 'the whole line is visible');

    // Too wide even at the smallest size: the line scrolls and follows the caret.
    notifier.pasteText('+56+78+90+12+34+56+78+90+12+34+56+78+90+12+34+56+78+90+12+34+56+78+90');
    await settle(tester);
    expect(position().maxScrollExtent, greaterThan(40));
    expect(position().pixels, position().maxScrollExtent, reason: 'the caret sits at the end of the line');

    // Moving the caret to the start scrolls back.
    for (var i = 0; i < 120; i++) {
      notifier.press(const MoveKey(CursorDirection.left));
    }
    await settle(tester);
    expect(position().pixels, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expression and result are exposed to screen readers as text', (tester) async {
    final container = await pumpCalculator(tester);
    final notifier = container.read(calculatorProvider.notifier);
    expect(find.bySemanticsLabel('Expression: empty'), findsOneWidget);

    notifier.pasteText('5^2+3');
    await settle(tester);
    expect(find.bySemanticsLabel('Expression: 5^2+3'), findsOneWidget);
    expect(find.bySemanticsLabel('Preview: 28'), findsOneWidget);

    await commit(tester, container);
    expect(find.bySemanticsLabel('Result: 28'), findsOneWidget);

    notifier.pasteText('1/0');
    await commit(tester, container);
    expect(find.bySemanticsLabel(RegExp('^Error: ')), findsOneWidget);
  });
}
