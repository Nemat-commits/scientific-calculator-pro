import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../widgets/app_toast.dart';
import '../widgets/calc_key_button.dart';
import '../widgets/calc_prompt.dart';
import '../widgets/function_row.dart';
import '../widgets/key_legend.dart';
import '../widgets/persistent_display_card.dart';
import '../widgets/shell_layout.dart';
import '../widgets/utility_strip.dart';

/// What a scientific key does in one shift layer.
class _Face {
  const _Face(this.legend, this.key, {this.name, this.action});

  /// Builds the legend in the colour of the key; [scale] is 1 for the main
  /// legend and smaller for the hint in the corner.
  final Widget Function(Color color, double scale) legend;

  /// The key the face presses, unless it has an [action] of its own.
  final CalcKey? key;

  /// What the face does when it is not a key of the editor (`ENG`, `CALC`).
  final void Function(BuildContext context, WidgetRef ref)? action;

  /// Accessible name.
  final String? name;
}

/// Font size of a main legend.
const double _legendSize = 17;

_Face _text(String label, CalcKey key, {String? name, double size = _legendSize}) =>
    _Face((c, k) => KeyLegend(label, color: c, size: size * k), key, name: name ?? label);

_Face _function(String name, {String? label, String? sup, int arity = 1}) => _Face(
      (c, k) => KeyLegend(label ?? name, sup: sup, color: c, size: _legendSize * k),
      TemplateKey(TemplateKind.function, name: name, arity: arity),
      name: name,
    );

/// Tab 2: the cursor & memory strip and the 5 × 6 scientific grid.
///
/// `INV` is the shift key and has a colour of its own. The corner of a key
/// names, in that colour, the function `INV` turns it into; while `INV` is
/// on, the keys it has changed take the colour and their corners name what
/// they return to. `INV` and `HYP` release again after the next function key.
///
/// `f(x)` at the start of the strip opens a row with the functions the grid
/// has no key for.
class ScientificTabView extends ConsumerWidget {
  const ScientificTabView({super.key});

  static const Duration _morph = Duration(milliseconds: 140);

  /// Size of the hint in the corner of a key.
  static const double cornerLegendSize = 9;

  /// The trigonometric key for a shift state.
  static _Face _trig(String base, bool inverse, bool hyperbolic) {
    final name = '${inverse ? 'a' : ''}$base${hyperbolic ? 'h' : ''}';
    return _function(name, label: '$base${hyperbolic ? 'h' : ''}', sup: inverse ? '−1' : null);
  }

  /// `ENG`: switches the notation of the results and says what it is now.
  static void toggleEngineering(WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier)..toggleEngineering();
    notifier.releaseShift();
    ref
        .read(toastProvider.notifier)
        .show(ref.read(calculatorProvider).isEngineering ? ModeHints.engineering : ModeHints.normal);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    final inverse = ref.watch(calculatorProvider.select((s) => s.isInverseActive));
    final hyperbolic = ref.watch(calculatorProvider.select((s) => s.isHyperbolicActive));
    final shifted = inverse || hyperbolic;
    // Next to the standard keypad the strip would only repeat its top row.
    final showStrip = !ShellLayout.isDualPane(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxHeight < 300 ? 5.0 : 8.0;
        final strip = showStrip ? (constraints.maxHeight * 0.085).clamp(24.0, 38.0) : 0.0;

        Widget grid(double height) {
          final keyHeight = (height - gap * 5) / 6;
          final corners = keyHeight >= 40;
          // On low keys the legends give the corner hints some room.
          final scale = keyHeight < 52 ? 0.88 : 1.0;

          /// A key with the face [normal]; [inv] is what `INV` makes of it.
          Widget key(_Face normal, {_Face? inv, KeyTone tone = KeyTone.function}) {
            final morphed = inverse && inv != null;
            final face = morphed ? inv : normal;
            final other = inv == null ? null : (inverse ? normal : inv);
            final color = morphed ? AppColors.keyShiftText : CalcKeyButton.foregroundOf(tone);
            return CalcKeyButton(
              tone: tone,
              semanticLabel: face.name,
              onPressed: () {
                final action = face.action;
                if (action != null) {
                  action(context, ref);
                } else {
                  notifier.press(face.key!, consumeShift: shifted);
                }
              },
              corner: corners && other != null
                  ? AnimatedSwitcher(
                      duration: _morph,
                      child: KeyedSubtree(
                        key: ValueKey<String?>(other.name),
                        child: other.legend(
                          inverse ? AppColors.textMuted : AppColors.keyShiftHint,
                          cornerLegendSize / _legendSize,
                        ),
                      ),
                    )
                  : null,
              child: AnimatedSwitcher(
                duration: _morph,
                child: KeyedSubtree(key: ValueKey<String?>(face.name), child: face.legend(color, scale)),
              ),
            );
          }

          Widget trig(String base) => key(_trig(base, false, hyperbolic), inv: _trig(base, true, hyperbolic));

          return KeyGrid(
            gap: gap,
            rows: <List<Widget>>[
              <Widget>[
                CalcKeyButton(
                  label: 'INV',
                  tone: inverse ? KeyTone.shiftActive : KeyTone.shift,
                  fontSize: 16 * scale,
                  semanticLabel: 'INV, second functions',
                  onPressed: notifier.toggleInverse,
                ),
                CalcKeyButton(
                  label: 'HYP',
                  tone: hyperbolic ? KeyTone.active : KeyTone.function,
                  fontSize: 16 * scale,
                  onPressed: notifier.toggleHyperbolic,
                ),
                key(
                  _Face(
                    (c, k) => KeyLegend('Σ', color: c, size: (_legendSize + 2) * k),
                    const TemplateKey(TemplateKind.summation),
                    name: 'sum',
                  ),
                  inv: _Face(
                    (c, k) => KeyLegend('Π', color: c, size: (_legendSize + 2) * k),
                    const TemplateKey(TemplateKind.product),
                    name: 'product',
                  ),
                ),
                key(
                  _text('x', const AtomKey('x', AtomKind.variable)),
                  inv: _text('y', const AtomKey('y', AtomKind.variable)),
                ),
                CalcKeyButton(
                  label: 'AC',
                  tone: KeyTone.danger,
                  fontSize: 17 * scale,
                  haptic: HapticPattern.heavy,
                  semanticLabel: 'All clear',
                  onPressed: () => notifier.press(const ClearKey()),
                ),
              ],
              <Widget>[
                trig('sin'),
                trig('cos'),
                trig('tan'),
                key(
                  _function('ln'),
                  inv: _Face(
                    (c, k) => KeyLegend('e', sup: 'x', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.powerOfE),
                    name: 'e to the x',
                  ),
                ),
                key(
                  _function('log'),
                  inv: _Face(
                    (c, k) => KeyLegend('10', sup: 'x', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.powerOfTen),
                    name: 'ten to the x',
                  ),
                ),
              ],
              <Widget>[
                key(
                  _Face(
                    (c, k) => KeyLegend('x', sup: '2', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.square),
                    name: 'square',
                  ),
                  inv: _Face(
                    (c, k) => KeyLegend('x', sup: '3', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.cube),
                    name: 'cube',
                  ),
                ),
                key(
                  _Face(
                    (c, k) => KeyLegend('x', sup: 'y', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.power),
                    name: 'power',
                  ),
                  inv: _Face(
                    (c, k) => KeyLegend('√x', lead: 'y', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.nthRoot),
                    name: 'nth root',
                  ),
                ),
                key(
                  _Face(
                    (c, k) => KeyLegend('√x', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.squareRoot),
                    name: 'square root',
                  ),
                  inv: _Face(
                    (c, k) => KeyLegend('√x', lead: '3', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.cubeRoot),
                    name: 'cube root',
                  ),
                ),
                key(
                  _Face(
                    (c, k) => FractionLegend(color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.fraction),
                    name: 'fraction',
                  ),
                  inv: _Face(
                    (c, k) => MixedFractionLegend(color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.mixedFraction),
                    name: 'mixed fraction',
                  ),
                ),
                key(
                  _function('abs', label: '|x|'),
                  inv: _text('1/x', const TemplateKey(TemplateKind.reciprocal), name: 'reciprocal', size: 16),
                ),
              ],
              <Widget>[
                key(
                  _text('π', const AtomKey('π', AtomKind.constant), name: 'pi'),
                  inv: _text('φ', const AtomKey('φ', AtomKind.constant), name: 'phi'),
                ),
                key(
                  _text('e', const AtomKey('e', AtomKind.constant)),
                  inv: _text('Rand', const AtomKey('Rand', AtomKind.constant), name: 'random number', size: 15),
                ),
                key(
                  _text('i', const AtomKey('i', AtomKind.constant), name: 'imaginary unit'),
                  inv: _Face(
                    (c, k) => AngleLegend(color: c, size: _legendSize * k),
                    const AtomKey('∠', AtomKind.binaryOp),
                    name: 'polar form',
                  ),
                ),
                key(
                  _Face(
                    (c, k) => KeyLegend('×10', sup: 'x', color: c, size: 15 * k),
                    const AtomKey('E', AtomKind.digit),
                    name: 'exponent',
                  ),
                  inv: _Face(
                    (c, k) => KeyLegend('ENG', color: c, size: 15 * k),
                    null,
                    name: 'engineering notation',
                    action: (context, ref) => toggleEngineering(ref),
                  ),
                ),
                key(
                  _text('x!', const AtomKey('!', AtomKind.unaryPostfix), name: 'factorial'),
                  inv: _text('mod', const AtomKey('mod', AtomKind.binaryOp), size: 15),
                ),
              ],
              <Widget>[
                key(
                  _Face(
                    (c, k) => KeyLegend('∫', sub: 'dx', color: c, size: _legendSize * k),
                    const TemplateKey(TemplateKind.integral),
                    name: 'integral',
                  ),
                ),
                key(
                  _Face(
                    (c, k) => KeyLegend('d/dx', color: c, size: 15 * k),
                    const TemplateKey(TemplateKind.derivative),
                    name: 'derivative',
                  ),
                ),
                key(_function('ncr', label: 'nCr', arity: 2), inv: _function('npr', label: 'nPr', arity: 2)),
                key(_text('(', const AtomKey('(', AtomKind.paren), name: 'open parenthesis')),
                key(_text(')', const AtomKey(')', AtomKind.paren), name: 'close parenthesis')),
              ],
              <Widget>[
                key(
                  _Face(
                    (c, k) => KeyLegend('CALC', color: c, size: 14 * k),
                    null,
                    name: 'CALC, evaluate with values for the variables',
                    action: (context, ref) {
                      ref.read(calculatorProvider.notifier).releaseShift();
                      CalcPrompt.show(context, ref);
                    },
                  ),
                ),
                key(
                  _text('Ans', const AtomKey('Ans', AtomKind.variable)),
                  inv: _text('M', const AtomKey('M', AtomKind.variable), name: 'Memory'),
                ),
                CalcKeyButton(
                  label: ',',
                  tone: KeyTone.function,
                  fontSize: 20,
                  semanticLabel: 'Next argument',
                  onPressed: notifier.pressSeparator,
                ),
                CalcKeyButton(
                  label: '⌫',
                  tone: KeyTone.danger,
                  fontSize: 20,
                  repeats: true,
                  semanticLabel: 'Backspace',
                  onPressed: () => notifier.press(const BackspaceKey()),
                ),
                CalcKeyButton(
                  label: '=',
                  tone: KeyTone.equals,
                  fontSize: 24,
                  haptic: HapticPattern.medium,
                  semanticLabel: 'Equals',
                  onPressed: () => notifier.press(const EvaluateKey()),
                ),
              ],
            ],
          );
        }

        if (!showStrip) return grid(constraints.maxHeight);
        final rowHeight = strip * 1.12;
        return FunctionRowToggle(
          keys: FunctionRow.further,
          rowHeight: rowHeight,
          gap: gap,
          showLabel: 'Show more functions',
          hideLabel: 'Hide the extra functions',
          builder: (context, toggle, row, open) => Column(
            children: <Widget>[
              SizedBox(height: strip, child: UtilityStrip(leading: toggle)),
              row,
              SizedBox(height: gap),
              Expanded(
                child: grid(constraints.maxHeight - strip - gap - (open ? rowHeight + gap : 0)),
              ),
            ],
          ),
        );
      },
    );
  }
}
