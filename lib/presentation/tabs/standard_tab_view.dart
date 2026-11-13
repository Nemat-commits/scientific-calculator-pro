import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../state/calculator_ui_state.dart';
import '../widgets/calc_key_button.dart';

/// Tab 1: the 4 × 5 core keypad with the cursor & memory strip above it.
class StandardTabView extends ConsumerWidget {
  const StandardTabView({super.key});

  /// `(` or `)` - whichever makes sense at the caret.
  static AtomKey smartParenthesis(CalculatorUiState state) {
    const open = AtomKey('(', AtomKind.paren), close = AtomKey(')', AtomKind.paren);
    if (state.inputPhase != InputPhase.editing) return open;
    final editor = state.editor;
    final sequence = MathPrintController.currentSequence(editor);
    final offset = editor.cursor.offset;
    var unclosed = 0;
    for (var i = 0; i < offset; i++) {
      final node = sequence.children[i];
      if (node is AtomNode && node.kind == AtomKind.paren) unclosed += node.text == '(' ? 1 : -1;
    }
    if (unclosed <= 0 || offset == 0) return open;
    final previous = sequence.children[offset - 1];
    final endsOperand = previous is! AtomNode ||
        previous.kind == AtomKind.digit ||
        previous.kind == AtomKind.constant ||
        previous.kind == AtomKind.variable ||
        previous.kind == AtomKind.unaryPostfix ||
        (previous.kind == AtomKind.paren && previous.text == ')');
    return endsOperand ? close : open;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);

    Widget digit(String d) => CalcKeyButton(
          label: d,
          fontSize: 24,
          onPressed: () => notifier.press(AtomKey(d, AtomKind.digit)),
        );
    Widget operator(String symbol) => CalcKeyButton(
          label: symbol,
          tone: KeyTone.operator,
          fontSize: 26,
          haptic: HapticPattern.medium,
          onPressed: () => notifier.press(AtomKey(symbol, AtomKind.binaryOp)),
        );
    Widget move(String label, CursorDirection direction, String name) => CalcKeyButton(
          label: label,
          tone: KeyTone.function,
          fontSize: 13,
          radius: 12,
          repeats: true,
          semanticLabel: 'Cursor $name',
          onPressed: () => notifier.press(MoveKey(direction)),
        );
    Widget memory(String label, VoidCallback action) => CalcKeyButton(
          label: label,
          tone: KeyTone.function,
          fontSize: 13,
          radius: 12,
          onPressed: action,
        );

    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxHeight < 300;
        final gap = tight ? 5.0 : 8.0;
        final strip = (constraints.maxHeight * 0.115).clamp(26.0, 42.0);
        return Column(
          children: <Widget>[
            SizedBox(
              height: strip,
              child: KeyGrid(
                gap: gap,
                rows: <List<Widget>>[
                  <Widget>[
                    move('◀', CursorDirection.left, 'left'),
                    move('▶', CursorDirection.right, 'right'),
                    move('▲', CursorDirection.up, 'up'),
                    move('▼', CursorDirection.down, 'down'),
                    memory('MC', notifier.memoryClear),
                    memory('MR', notifier.memoryRecall),
                    memory('M+', notifier.memoryAdd),
                    memory('M−', notifier.memorySubtract),
                  ],
                ],
              ),
            ),
            SizedBox(height: gap),
            Expanded(
              child: KeyGrid(
                gap: gap,
                rows: <List<Widget>>[
                  <Widget>[
                    CalcKeyButton(
                      label: 'AC',
                      tone: KeyTone.danger,
                      fontSize: 20,
                      haptic: HapticPattern.heavy,
                      semanticLabel: 'All clear',
                      onPressed: () => notifier.press(const ClearKey()),
                    ),
                    CalcKeyButton(
                      label: '( )',
                      tone: KeyTone.function,
                      fontSize: 20,
                      semanticLabel: 'Parenthesis',
                      onPressed: () => notifier.press(smartParenthesis(ref.read(calculatorProvider))),
                      onLongPress: () => notifier.press(const AtomKey('(', AtomKind.paren)),
                    ),
                    CalcKeyButton(
                      label: '%',
                      tone: KeyTone.function,
                      fontSize: 20,
                      semanticLabel: 'Percent',
                      onPressed: () => notifier.press(const AtomKey('%', AtomKind.unaryPostfix)),
                    ),
                    operator('÷'),
                  ],
                  <Widget>[digit('7'), digit('8'), digit('9'), operator('×')],
                  <Widget>[digit('4'), digit('5'), digit('6'), operator('−')],
                  <Widget>[digit('1'), digit('2'), digit('3'), operator('+')],
                  <Widget>[
                    digit('0'),
                    digit('.'),
                    CalcKeyButton(
                      label: '⌫',
                      tone: KeyTone.danger,
                      fontSize: 22,
                      repeats: true,
                      semanticLabel: 'Backspace',
                      onPressed: () => notifier.press(const BackspaceKey()),
                    ),
                    CalcKeyButton(
                      label: '=',
                      tone: KeyTone.equals,
                      fontSize: 28,
                      haptic: HapticPattern.medium,
                      semanticLabel: 'Equals',
                      onPressed: () => notifier.press(const EvaluateKey()),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
