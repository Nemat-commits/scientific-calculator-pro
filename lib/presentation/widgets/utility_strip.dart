import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/editor/calc_key.dart';
import '../../domain/editor/math_print_controller.dart';
import '../state/calculator_notifier.dart';
import 'calc_key_button.dart';

/// The compact row above a keypad: caret keys and the independent memory.
///
/// `MC` and `MR` light up while the memory holds a value.
class UtilityStrip extends ConsumerWidget {
  const UtilityStrip({super.key, this.leading, this.gap = 5});

  /// Extra key in front of the row.
  final Widget? leading;
  final double gap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    final hasMemory = ref.watch(calculatorProvider.select((s) => s.hasMemory));

    Widget move(String label, CursorDirection direction, String name) => CalcKeyButton(
          label: label,
          tone: KeyTone.function,
          fontSize: 13,
          radius: 12,
          repeats: true,
          semanticLabel: 'Cursor $name',
          onPressed: () => notifier.press(MoveKey(direction)),
        );
    Widget memory(String label, VoidCallback action, {bool lit = false}) => CalcKeyButton(
          label: label,
          tone: KeyTone.function,
          fontSize: 13,
          radius: 12,
          emphasised: lit,
          onPressed: action,
        );

    final leading = this.leading;
    return KeyGrid(
      gap: gap,
      rows: <List<Widget>>[
        <Widget>[
          if (leading != null) leading,
          move('◀', CursorDirection.left, 'left'),
          move('▶', CursorDirection.right, 'right'),
          move('▲', CursorDirection.up, 'up'),
          move('▼', CursorDirection.down, 'down'),
          memory('MC', notifier.memoryClear, lit: hasMemory),
          memory('MR', notifier.memoryRecall, lit: hasMemory),
          memory('M+', notifier.memoryAdd),
          memory('M−', notifier.memorySubtract),
        ],
      ],
    );
  }
}
