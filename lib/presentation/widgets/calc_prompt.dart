import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/compiler/tree_to_token_lowerer.dart';
import '../../domain/evaluator/number_formatter.dart';
import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import '../../domain/models/calc_value.dart';
import '../../domain/models/calc_value_codec.dart';
import '../state/calculator_notifier.dart';
import 'app_toast.dart';
import 'lab_widgets.dart';

/// `CALC`: asks for a value for every variable of the expression and
/// evaluates the expression with them.
///
/// The values are for this evaluation only. Each field starts with what its
/// variable has stored; nothing typed here is stored, and the expression
/// stays in the editor, so `CALC` can be pressed again for other values.
class CalcPrompt extends ConsumerStatefulWidget {
  const CalcPrompt({super.key, required this.variables, required this.expression});

  /// The variables to ask for, in the order they appear in the expression.
  final List<String> variables;

  /// The expression in its linear form.
  final String expression;

  /// What the prompt asks for when the expression has no variable.
  static const String fallbackVariable = 'x';

  /// Opens the prompt for the expression in the editor. With nothing in the
  /// editor there is nothing to evaluate, and a message says so.
  static Future<void> show(BuildContext context, WidgetRef ref) async {
    final state = ref.read(calculatorProvider);
    if (state.rootSequence.isEmpty) {
      ref.read(toastProvider.notifier).show('CALC evaluates a formula · type one first');
      return;
    }
    final found = ref.read(calculatorProvider.notifier).freeVariables();
    await Navigator.of(context).push<void>(
      PageRouteBuilder<void>(
        opaque: false,
        barrierDismissible: true,
        barrierColor: AppColors.scrim,
        barrierLabel: 'Close',
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (context, _, __) => CalcPrompt(
          variables: found.isEmpty ? const <String>[fallbackVariable] : found,
          expression: TreeToTokenLowerer.toDisplayText(state.rootSequence),
        ),
        transitionsBuilder: (context, animation, _, child) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          ),
        ),
      ),
    );
  }

  /// How a stored value is written into its field: the fraction of an exact
  /// one, otherwise the number.
  static String fieldText(CalcValue value) =>
      NumberFormatter.formatSecondary(value) ?? NumberFormatter.formatValue(value, prec: 12).replaceAll('e', 'E');

  @override
  ConsumerState<CalcPrompt> createState() => _CalcPromptState();
}

class _CalcPromptState extends ConsumerState<CalcPrompt> {
  late final List<String> _values;

  /// Fields that still show the stored value: the first key replaces it.
  late final List<bool> _untouched;
  final Set<int> _invalid = <int>{};
  int _active = 0;

  @override
  void initState() {
    super.initState();
    final stored = ref.read(calculatorProvider).variables;
    _values = <String>[
      for (final name in widget.variables)
        if (stored[name] case final String encoded) _stored(encoded) else '',
    ];
    _untouched = <bool>[for (final value in _values) value.isNotEmpty];
  }

  static String _stored(String encoded) {
    try {
      return CalcPrompt.fieldText(CalcValueCodec.decode(encoded));
    } on Object {
      return '';
    }
  }

  void _edit(String Function(String value) change) => setState(() {
        final current = _untouched[_active] ? '' : _values[_active];
        _values[_active] = change(current);
        _untouched[_active] = false;
        _invalid.remove(_active);
      });

  void _next() {
    if (_active + 1 < _values.length) {
      setState(() => _active++);
    } else {
      _evaluate();
    }
  }

  void _evaluate() {
    final encoded = <String, String>{};
    final shown = <String>[];
    final invalid = <int>{};
    for (var i = 0; i < _values.length; i++) {
      final text = _values[i].trim();
      try {
        final value = text.isEmpty ? Values.zero : MathEngine.evaluateText(text).value;
        encoded[widget.variables[i]] = CalcValueCodec.encode(value);
        shown.add('${widget.variables[i]} = ${text.isEmpty ? '0' : text}');
      } on CalcError {
        invalid.add(i);
      }
    }
    if (invalid.isNotEmpty) {
      setState(() {
        _invalid
          ..clear()
          ..addAll(invalid);
        _active = invalid.first;
      });
      return;
    }
    ref.read(calculatorProvider.notifier).evaluateWith(encoded, note: shown.join(', '));
    Navigator.of(context).pop();
  }

  /// A hardware keyboard types into the active field.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      Navigator.of(context).pop();
    } else if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
      _next();
    } else if (key == LogicalKeyboardKey.tab) {
      setState(() => _active = (_active + 1) % _values.length);
    } else if (key == LogicalKeyboardKey.backspace) {
      _edit(FieldInput.backspace);
    } else {
      final typed = switch (event.character) {
        final String c when c.length == 1 && '0123456789./'.contains(c) => c,
        '-' || '−' => '−',
        'e' || 'E' => 'E',
        _ => null,
      };
      if (typed == null) return KeyEventResult.ignored;
      _edit((value) => FieldInput.append(value, typed));
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final keypadHeight = (screen.height * 0.30).clamp(150.0, 230.0);
    return Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: _sheet(screen, keypadHeight),
    );
  }

  Widget _sheet(Size screen, double keypadHeight) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const SectionLabel('CALC'),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            AppTypography.signs(widget.expression),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: AppTypography.mono(size: 13, color: AppColors.textSecondary),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _invalid.isEmpty
                          ? 'Values for this evaluation only. Nothing is stored.'
                          : 'This is not a number.',
                      style:
                          AppTypography.ui(size: 11.5, color: _invalid.isEmpty ? AppColors.textFaint : AppColors.error),
                    ),
                    const SizedBox(height: 10),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: screen.height * 0.2),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: <Widget>[
                            for (var i = 0; i < _values.length; i++)
                              LabField(
                                label: '${widget.variables[i]} =',
                                value: _values[i],
                                active: i == _active,
                                error: _invalid.contains(i),
                                minWidth: 96,
                                onTap: () => setState(() => _active = i),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      height: keypadHeight,
                      child: MiniKeypad(
                        onInput: (char) => _edit((value) => FieldInput.append(value, char)),
                        onBackspace: () => _edit(FieldInput.backspace),
                        onClear: () => _edit((_) => ''),
                        onEnter: _next,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: <Widget>[
                        SmallButton('Close', onTap: () => Navigator.of(context).pop()),
                        const SizedBox(width: 8),
                        SmallButton('Evaluate', primary: true, onTap: _evaluate),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
