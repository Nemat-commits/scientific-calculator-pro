import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../state/calculator_ui_state.dart';
import '../widgets/calc_key_button.dart';
import '../widgets/key_legend.dart';
import '../widgets/utility_strip.dart';

/// Tab 1: the 4 × 5 core keypad with the cursor & memory strip above it.
///
/// `f(x)` at the start of the strip opens a row with the most used scientific
/// keys, so that an everyday formula such as `2 × sin(45) + √16` can be typed
/// without changing tabs.
class StandardTabView extends ConsumerStatefulWidget {
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
  ConsumerState<StandardTabView> createState() => _StandardTabViewState();
}

class _StandardTabViewState extends ConsumerState<StandardTabView> {
  /// Whether the row of quick scientific keys is open.
  bool _quickOpen = false;

  @override
  Widget build(BuildContext context) {
    final notifier = ref.read(calculatorProvider.notifier);
    final openParentheses = ref.watch(calculatorProvider.select((s) => s.unclosedParenthesesCount));

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
    Widget quick(String name, CalcKey key, Widget Function(Color color) legend) => CalcKeyButton(
          tone: KeyTone.function,
          radius: 12,
          semanticLabel: name,
          onPressed: () => notifier.press(key),
          child: legend(CalcKeyButton.foregroundOf(KeyTone.function)),
        );
    Widget function(String name) => quick(
          name,
          TemplateKey(TemplateKind.function, name: name),
          (c) => KeyLegend(name, color: c, size: 15),
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
              child: UtilityStrip(
                leading: CalcKeyButton(
                  label: 'f(x)',
                  tone: _quickOpen ? KeyTone.active : KeyTone.function,
                  fontSize: 13,
                  radius: 12,
                  semanticLabel: _quickOpen ? 'Hide the scientific keys' : 'Show the scientific keys',
                  onPressed: () => setState(() => _quickOpen = !_quickOpen),
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: !_quickOpen
                  ? const SizedBox(width: double.infinity)
                  : Padding(
                      padding: EdgeInsets.only(top: gap),
                      child: SizedBox(
                        height: strip * 1.12,
                        child: KeyGrid(
                          gap: 5,
                          rows: <List<Widget>>[
                            <Widget>[
                              function('sin'),
                              function('cos'),
                              function('tan'),
                              function('ln'),
                              quick('square root', const TemplateKey(TemplateKind.squareRoot),
                                  (c) => KeyLegend('√x', color: c, size: 15)),
                              quick('square', const TemplateKey(TemplateKind.square),
                                  (c) => KeyLegend('x', sup: '2', color: c, size: 15)),
                              quick('power', const TemplateKey(TemplateKind.power),
                                  (c) => KeyLegend('x', sup: 'y', color: c, size: 15)),
                              quick('pi', const AtomKey('π', AtomKind.constant),
                                  (c) => KeyLegend('π', color: c, size: 15)),
                            ],
                          ],
                        ),
                      ),
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
                    _Badged(
                      count: openParentheses,
                      child: CalcKeyButton(
                        label: '( )',
                        tone: KeyTone.function,
                        fontSize: 20,
                        semanticLabel: 'Parenthesis',
                        onPressed: () => notifier.press(StandardTabView.smartParenthesis(ref.read(calculatorProvider))),
                        onLongPress: () => notifier.press(const AtomKey('(', AtomKind.paren)),
                      ),
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

/// Puts a small counter on the top right corner of a key while [count] is
/// positive (parentheses that are still open).
class _Badged extends StatelessWidget {
  const _Badged({required this.count, required this.child});

  final int count;
  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: <Widget>[
          child,
          if (count > 0)
            Positioned(
              top: 4,
              right: 4,
              child: IgnorePointer(
                child: Semantics(
                  label: '$count open',
                  excludeSemantics: true,
                  child: Container(
                    constraints: const BoxConstraints(minWidth: 16),
                    height: 16,
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.keyBadge, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      '$count',
                      maxLines: 1,
                      style: AppTypography.ui(
                          size: 10, weight: AppWeight.strong, color: AppColors.keyEqualsText, height: 1.1),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
}
