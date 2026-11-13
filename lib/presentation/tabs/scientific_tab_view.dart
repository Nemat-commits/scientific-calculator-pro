import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/editor/calc_key.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../widgets/calc_key_button.dart';
import '../widgets/key_legend.dart';

/// What a scientific key does in one shift layer.
class _Face {
  const _Face(this.legend, this.key, {this.name});

  /// Builds the legend in the colour of the key.
  final Widget Function(Color color) legend;
  final CalcKey key;

  /// Accessible name.
  final String? name;
}

_Face _text(String label, CalcKey key, {String? name}) =>
    _Face((c) => KeyLegend(label, color: c), key, name: name ?? label);

_Face _function(String name, {String? label, String? sup, int arity = 1}) => _Face(
      (c) => KeyLegend(label ?? name, sup: sup, color: c),
      TemplateKey(TemplateKind.function, name: name, arity: arity),
      name: name,
    );

/// Tab 2: the 5 × 6 scientific grid. `INV` and `HYP` morph the keys with a
/// cross-fade; both release again after the next function key.
class ScientificTabView extends ConsumerWidget {
  const ScientificTabView({super.key});

  static const Duration _morph = Duration(milliseconds: 140);

  /// The trigonometric key for the current shift state.
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

    Widget key(_Face normal, {_Face? inv, KeyTone tone = KeyTone.function}) {
      final face = inverse && inv != null ? inv : normal;
      final color = CalcKeyButton.foregroundOf(tone);
      return CalcKeyButton(
        tone: tone,
        semanticLabel: face.name,
        onPressed: () => notifier.press(face.key, consumeShift: shifted),
        child: AnimatedSwitcher(
          duration: _morph,
          child: KeyedSubtree(key: ValueKey<String?>(face.name), child: face.legend(color)),
        ),
      );
    }

    Widget toggle(String label, bool active, VoidCallback onPressed) => CalcKeyButton(
          label: label,
          tone: active ? KeyTone.active : KeyTone.function,
          fontSize: 16,
          onPressed: onPressed,
        );

    Widget move(String label, CursorDirection direction, String name) => CalcKeyButton(
          label: label,
          tone: KeyTone.function,
          fontSize: 14,
          repeats: true,
          semanticLabel: 'Cursor $name',
          onPressed: () => notifier.press(MoveKey(direction)),
        );

    const variableX = AtomKey('x', AtomKind.variable);
    return LayoutBuilder(
      builder: (context, constraints) => KeyGrid(
        gap: constraints.maxHeight < 300 ? 5 : 8,
        rows: <List<Widget>>[
          <Widget>[
            toggle('INV', inverse, notifier.toggleInverse),
            toggle('HYP', hyperbolic, notifier.toggleHyperbolic),
            CalcKeyButton(
              label: angle.label,
              tone: KeyTone.function,
              fontSize: 15,
              semanticLabel: 'Angle unit ${angle.label}',
              onPressed: notifier.cycleAngleUnit,
            ),
            key(_text('x', variableX), inv: _text('y', const AtomKey('y', AtomKind.variable))),
            key(
              _text('Ans', const AtomKey('Ans', AtomKind.variable)),
              inv: _text('M', const AtomKey('M', AtomKind.variable), name: 'Memory'),
            ),
          ],
          <Widget>[
            key(_trig('sin', inverse, hyperbolic)),
            key(_trig('cos', inverse, hyperbolic)),
            key(_trig('tan', inverse, hyperbolic)),
            key(
              _function('ln'),
              inv: _Face((c) => KeyLegend('e', sup: 'x', color: c), const TemplateKey(TemplateKind.powerOfE), name: 'e to the x'),
            ),
            key(
              _function('log'),
              inv: _Face((c) => KeyLegend('10', sup: 'x', color: c), const TemplateKey(TemplateKind.powerOfTen), name: 'ten to the x'),
            ),
          ],
          <Widget>[
            key(
              _Face((c) => KeyLegend('x', sup: '2', color: c), const TemplateKey(TemplateKind.square), name: 'square'),
              inv: _Face((c) => KeyLegend('x', sup: '3', color: c), const TemplateKey(TemplateKind.cube), name: 'cube'),
            ),
            key(
              _Face((c) => KeyLegend('x', sup: 'y', color: c), const TemplateKey(TemplateKind.power), name: 'power'),
              inv: _Face((c) => KeyLegend('√x', lead: 'y', color: c), const TemplateKey(TemplateKind.nthRoot), name: 'nth root'),
            ),
            key(
              _Face((c) => KeyLegend('√x', color: c), const TemplateKey(TemplateKind.squareRoot), name: 'square root'),
              inv: _Face((c) => KeyLegend('√x', lead: '3', color: c), const TemplateKey(TemplateKind.cubeRoot), name: 'cube root'),
            ),
            key(
              _Face((c) => FractionLegend(color: c), const TemplateKey(TemplateKind.fraction), name: 'fraction'),
              inv: _Face((c) => KeyLegend('x', sup: '−1', color: c), const TemplateKey(TemplateKind.reciprocal), name: 'reciprocal'),
            ),
            key(
              _function('abs', label: '|x|'),
              inv: _text('mod', const AtomKey('mod', AtomKind.binaryOp)),
            ),
          ],
          <Widget>[
            key(_text('π', const AtomKey('π', AtomKind.constant), name: 'pi'), inv: _text('φ', const AtomKey('φ', AtomKind.constant), name: 'phi')),
            key(_text('e', const AtomKey('e', AtomKind.constant)), inv: _text('°', const AtomKey('°', AtomKind.unaryPostfix), name: 'degrees')),
            key(
              _text('i', const AtomKey('i', AtomKind.constant), name: 'imaginary unit'),
              inv: _Face(
                (c) => KeyLegend('log', sub: '2', color: c),
                const TemplateKey(TemplateKind.function, name: 'log2'),
                name: 'log base 2',
              ),
            ),
            key(
              _Face((c) => KeyLegend('×10', sup: 'x', color: c, size: 15), const AtomKey('E', AtomKind.digit), name: 'exponent'),
              inv: _function('logb', label: 'log', arity: 2),
            ),
            key(_text('x!', const AtomKey('!', AtomKind.unaryPostfix), name: 'factorial'), inv: _function('gamma', label: 'Γ')),
          ],
          <Widget>[
            key(_Face((c) => KeyLegend('∫', sub: 'dx', color: c), const TemplateKey(TemplateKind.integral), name: 'integral')),
            key(_Face((c) => KeyLegend('d/dx', color: c, size: 15), const TemplateKey(TemplateKind.derivative), name: 'derivative')),
            key(_function('ncr', label: 'nCr', arity: 2), inv: _function('npr', label: 'nPr', arity: 2)),
            key(_text('(', const AtomKey('(', AtomKind.paren), name: 'open parenthesis')),
            key(_text(')', const AtomKey(')', AtomKind.paren), name: 'close parenthesis')),
          ],
          <Widget>[
            move('◀', CursorDirection.left, 'left'),
            move('▶', CursorDirection.right, 'right'),
            move('▲', CursorDirection.up, 'up'),
            move('▼', CursorDirection.down, 'down'),
            CalcKeyButton(
              label: '⌫',
              tone: KeyTone.danger,
              fontSize: 20,
              repeats: true,
              semanticLabel: 'Backspace',
              onPressed: () => notifier.press(const BackspaceKey()),
            ),
          ],
        ],
      ),
    );
  }
}
