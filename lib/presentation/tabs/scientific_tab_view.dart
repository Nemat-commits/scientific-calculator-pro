import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../widgets/calc_key_button.dart';
import '../widgets/key_legend.dart';
import '../widgets/shell_layout.dart';
import '../widgets/utility_strip.dart';

/// What a scientific key does in one shift layer.
class _Face {
  const _Face(this.legend, this.key, {this.name});

  /// Builds the legend in the colour of the key; [scale] is 1 for the main
  /// legend and smaller for the hint in the corner.
  final Widget Function(Color color, double scale) legend;
  final CalcKey key;

  /// Accessible name.
  final String? name;
}

/// Font size of a main legend.
const double _legendSize = 17;

_Face _text(String label, CalcKey key, {String? name}) =>
    _Face((c, k) => KeyLegend(label, color: c, size: _legendSize * k), key, name: name ?? label);

_Face _function(String name, {String? label, String? sup, int arity = 1}) => _Face(
      (c, k) => KeyLegend(label ?? name, sup: sup, color: c, size: _legendSize * k),
      TemplateKey(TemplateKind.function, name: name, arity: arity),
      name: name,
    );

/// Tab 2: the cursor & memory strip and the 5 × 6 scientific grid.
///
/// `INV` and `HYP` morph the keys with a cross-fade; both release again after
/// the next function key. The corner of a key names the function `INV` turns
/// it into (or, while `INV` is on, the one it returns to).
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    final inverse = ref.watch(calculatorProvider.select((s) => s.isInverseActive));
    final hyperbolic = ref.watch(calculatorProvider.select((s) => s.isHyperbolicActive));
    final angle = ref.watch(calculatorProvider.select((s) => s.angleUnit));
    final shifted = inverse || hyperbolic;
    // Next to the standard keypad the strip would only repeat its top row.
    final showStrip = !ShellLayout.isDualPane(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final gap = constraints.maxHeight < 300 ? 5.0 : 8.0;
        final strip = showStrip ? (constraints.maxHeight * 0.085).clamp(24.0, 38.0) : 0.0;
        final keyHeight = (constraints.maxHeight - strip - gap * (showStrip ? 6 : 5)) / 6;
        final corners = keyHeight >= 40;
        // On low keys the legends give the corner hints some room.
        final scale = keyHeight < 52 ? 0.88 : 1.0;

        /// A key with the face [normal]; [inv] is what `INV` makes of it.
        Widget key(_Face normal, {_Face? inv, KeyTone tone = KeyTone.function}) {
          final morphed = inverse && inv != null;
          final face = morphed ? inv : normal;
          final other = inv == null ? null : (inverse ? normal : inv);
          final color = morphed ? AppColors.accent : CalcKeyButton.foregroundOf(tone);
          return CalcKeyButton(
            tone: tone,
            semanticLabel: face.name,
            onPressed: () => notifier.press(face.key, consumeShift: shifted),
            corner: corners && other != null
                ? AnimatedSwitcher(
                    duration: _morph,
                    child: KeyedSubtree(
                      key: ValueKey<String?>(other.name),
                      child: other.legend(AppColors.textMuted, cornerLegendSize / _legendSize),
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

        Widget toggle(String label, bool active, VoidCallback onPressed) => CalcKeyButton(
              label: label,
              tone: active ? KeyTone.active : KeyTone.function,
              fontSize: 16 * scale,
              onPressed: onPressed,
            );

        final grid = KeyGrid(
          gap: gap,
          rows: <List<Widget>>[
            <Widget>[
              toggle('INV', inverse, notifier.toggleInverse),
              toggle('HYP', hyperbolic, notifier.toggleHyperbolic),
              CalcKeyButton(
                label: angle.label,
                tone: KeyTone.function,
                fontSize: 15 * scale,
                semanticLabel: 'Angle unit ${angle.label}',
                onPressed: notifier.cycleAngleUnit,
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
                  (c, k) => KeyLegend('x', sup: '−1', color: c, size: _legendSize * k),
                  const TemplateKey(TemplateKind.reciprocal),
                  name: 'reciprocal',
                ),
              ),
              key(
                _function('abs', label: '|x|'),
                inv: _text('mod', const AtomKey('mod', AtomKind.binaryOp)),
              ),
            ],
            <Widget>[
              key(
                _text('π', const AtomKey('π', AtomKind.constant), name: 'pi'),
                inv: _text('φ', const AtomKey('φ', AtomKind.constant), name: 'phi'),
              ),
              key(
                _text('e', const AtomKey('e', AtomKind.constant)),
                inv: _text('°', const AtomKey('°', AtomKind.unaryPostfix), name: 'degrees'),
              ),
              key(
                _text('i', const AtomKey('i', AtomKind.constant), name: 'imaginary unit'),
                inv: _Face(
                  (c, k) => KeyLegend('log', sub: '2', color: c, size: _legendSize * k),
                  const TemplateKey(TemplateKind.function, name: 'log2'),
                  name: 'log base 2',
                ),
              ),
              key(
                _Face(
                  (c, k) => KeyLegend('×10', sup: 'x', color: c, size: 15 * k),
                  const AtomKey('E', AtomKind.digit),
                  name: 'exponent',
                ),
                inv: _Face(
                  (c, k) => KeyLegend('log', sub: 'a', color: c, size: _legendSize * k),
                  const TemplateKey(TemplateKind.function, name: 'logb', arity: 2),
                  name: 'log to base a',
                ),
              ),
              key(
                _text('x!', const AtomKey('!', AtomKind.unaryPostfix), name: 'factorial'),
                inv: _function('gamma', label: 'Γ'),
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
              key(_function('gcd', arity: 2), inv: _function('lcm', arity: 2)),
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
        if (!showStrip) return grid;
        return Column(
          children: <Widget>[
            SizedBox(height: strip, child: const UtilityStrip()),
            SizedBox(height: gap),
            Expanded(child: grid),
          ],
        );
      },
    );
  }
}
