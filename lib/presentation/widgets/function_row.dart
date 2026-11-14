import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/editor/calc_key.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import 'calc_key_button.dart';
import 'key_legend.dart';

/// One key of a [FunctionRow].
final class FunctionRowKey {
  const FunctionRowKey(this.name, this.key, this.legend);

  /// Accessible name.
  final String name;
  final CalcKey key;
  final Widget Function(Color color) legend;
}

/// A single row of compact function keys. It opens below the cursor & memory
/// strip when `f(x)` is pressed, and brings functions within reach that the
/// keypad underneath has no key for.
class FunctionRow extends ConsumerWidget {
  const FunctionRow({super.key, required this.keys});

  final List<FunctionRowKey> keys;

  static const double _size = 15;

  static FunctionRowKey _function(String name, {String? label, String? sub, int arity = 1, String? says}) =>
      FunctionRowKey(
        says ?? name,
        TemplateKey(TemplateKind.function, name: name, arity: arity),
        (c) => KeyLegend(label ?? name, sub: sub, color: c, size: _size),
      );

  /// What an everyday formula needs most; shown above the standard keypad.
  static final List<FunctionRowKey> everyday = <FunctionRowKey>[
    _function('sin'),
    _function('cos'),
    _function('tan'),
    _function('ln'),
    FunctionRowKey(
        'square root', const TemplateKey(TemplateKind.squareRoot), (c) => KeyLegend('√x', color: c, size: _size)),
    FunctionRowKey(
        'square', const TemplateKey(TemplateKind.square), (c) => KeyLegend('x', sup: '2', color: c, size: _size)),
    FunctionRowKey(
        'power', const TemplateKey(TemplateKind.power), (c) => KeyLegend('x', sup: 'y', color: c, size: _size)),
    FunctionRowKey('pi', const AtomKey('π', AtomKind.constant), (c) => KeyLegend('π', color: c, size: _size)),
  ];

  /// Functions the scientific grid has no key for.
  static final List<FunctionRowKey> further = <FunctionRowKey>[
    _function('log2', label: 'log', sub: '2', says: 'log base 2'),
    _function('logb', label: 'log', sub: 'a', arity: 2, says: 'log to base a'),
    _function('gamma', label: 'Γ', says: 'gamma'),
    _function('gcd', arity: 2),
    _function('lcm', arity: 2),
    FunctionRowKey(
        'degrees', const AtomKey('°', AtomKind.unaryPostfix), (c) => KeyLegend('°', color: c, size: _size + 2)),
    FunctionRowKey('percent', const AtomKey('%', AtomKind.unaryPostfix), (c) => KeyLegend('%', color: c, size: _size)),
    _function('arg', says: 'argument of a complex number'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    return KeyGrid(
      gap: 5,
      rows: <List<Widget>>[
        <Widget>[
          for (final item in keys)
            CalcKeyButton(
              tone: KeyTone.function,
              radius: 12,
              semanticLabel: item.name,
              onPressed: () => notifier.press(item.key),
              child: item.legend(CalcKeyButton.foregroundOf(KeyTone.function)),
            ),
        ],
      ],
    );
  }
}

/// The `f(x)` key at the start of the strip, and the row it opens.
///
/// [builder] gets the strip key and the row (which is `null` while closed and
/// animates its own height) and arranges them with the keypad.
class FunctionRowToggle extends StatefulWidget {
  const FunctionRowToggle({
    super.key,
    required this.keys,
    required this.rowHeight,
    required this.gap,
    required this.showLabel,
    required this.hideLabel,
    required this.builder,
  });

  final List<FunctionRowKey> keys;
  final double rowHeight;

  /// Space between the strip and the row.
  final double gap;

  /// Accessible names of the `f(x)` key.
  final String showLabel;
  final String hideLabel;
  final Widget Function(BuildContext context, Widget toggle, Widget row, bool open) builder;

  @override
  State<FunctionRowToggle> createState() => _FunctionRowToggleState();
}

class _FunctionRowToggleState extends State<FunctionRowToggle> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final toggle = CalcKeyButton(
      label: 'f(x)',
      tone: _open ? KeyTone.active : KeyTone.function,
      fontSize: 13,
      radius: 12,
      semanticLabel: _open ? widget.hideLabel : widget.showLabel,
      onPressed: () => setState(() => _open = !_open),
    );
    final row = AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: !_open
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: EdgeInsets.only(top: widget.gap),
              child: SizedBox(height: widget.rowHeight, child: FunctionRow(keys: widget.keys)),
            ),
    );
    return widget.builder(context, toggle, row, _open);
  }
}
