import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/math_constants.dart';
import '../../core/constants/unit_definitions.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/evaluator/unit_converter_engine.dart';
import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import '../../domain/models/calc_value.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../widgets/lab_widgets.dart';
import '../widgets/result_text.dart';

/// Tab 4: converter for 12 unit categories plus the CODATA constants.
///
/// Every unit of the selected category is listed with its converted value;
/// tapping a row makes it the unit that is being typed.
class UnitConverterTabView extends ConsumerStatefulWidget {
  const UnitConverterTabView({super.key});

  @override
  ConsumerState<UnitConverterTabView> createState() => _UnitConverterTabViewState();
}

class _UnitConverterTabViewState extends ConsumerState<UnitConverterTabView> {
  /// Index into the categories; one past the end selects the constants.
  int _category = 0;
  final Map<String, String> _sourceUnit = <String, String>{};
  String _input = '1';
  String? _inserted;

  static final List<String> _labels = <String>[
    for (final c in UnitDefinitions.categories) c.name,
    'Constants',
  ];

  bool get _showConstants => _category == UnitDefinitions.categories.length;

  UnitCategory get _current => UnitDefinitions.categories[_category];

  UnitDef get _source {
    final category = _current;
    final id = _sourceUnit[category.id];
    return id == null ? category.defaultUnit : category.unit(id);
  }

  CalcValue? _typed() {
    if (_input.isEmpty || _input == '−') return null;
    try {
      return MathEngine.evaluateText(_input).value;
    } on CalcError {
      return null;
    }
  }

  /// [value] in the unit [to] as a canonical number string, or `null` when
  /// there is nothing to show.
  String? _converted(CalcValue? value, UnitDef to) {
    if (value == null) return null;
    try {
      return UnitConverterEngine.convertFormatted(value, _source, to);
    } on CalcError {
      return null;
    }
  }

  void _insertConstant(PhysicalConstant constant) {
    ref.read(calculatorProvider.notifier).insertNodes(<EditorNode>[AtomNode(constant.symbol, AtomKind.constant)]);
    setState(() => _inserted = constant.symbol);
  }

  Widget _unitRow(UnitDef unit, CalcValue? value) {
    final active = identical(unit, _source);
    final shown = active ? null : _converted(value, unit);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() {
        // Carry the shown value over to the newly selected unit.
        final carried = _converted(value, unit);
        _sourceUnit[_current.id] = unit.id;
        if (carried != null) _input = carried.replaceFirst('e', 'E').replaceAll('-', '−');
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: active ? AppColors.accentFaint : AppColors.bgObsidian,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: active ? AppColors.accent : AppColors.panelBorder, width: active ? 1.4 : 1),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(
              width: 58,
              child: Text(
                unit.symbol,
                maxLines: 1,
                style: AppTypography.ui(
                    size: 13.5, weight: AppWeight.strong, color: active ? AppColors.accent : AppColors.textPrimary),
              ),
            ),
            Expanded(
              flex: 4,
              child: Text(
                unit.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.ui(size: 11.5, color: AppColors.textMuted),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 5,
              child: active || shown == null
                  ? FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerRight,
                      child: Text(
                        // The unit being typed shows the keystrokes as they are.
                        active ? AppTypography.signs(_input.isEmpty ? '0' : _input) : '—',
                        maxLines: 1,
                        style: AppTypography.mono(size: 15, weight: active ? AppWeight.medium : AppWeight.regular),
                      ),
                    )
                  : ResultText(shown, fontSize: 15, weight: AppWeight.regular),
            ),
          ],
        ),
      ),
    );
  }

  /// `m_e` is drawn the way the display draws it: mₑ.
  static Widget _constantSymbol(String symbol) {
    final style = AppTypography.mono(size: 13.5, weight: AppWeight.medium, color: AppColors.mathConstant);
    final split = symbol.indexOf('_');
    if (split <= 0 || split == symbol.length - 1) return Text(symbol, maxLines: 1, style: style);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        Text(symbol.substring(0, split), maxLines: 1, style: style),
        Transform.translate(
          offset: const Offset(0.5, 2.5),
          child: Text(symbol.substring(split + 1), maxLines: 1, style: style.copyWith(fontSize: 9.5)),
        ),
      ],
    );
  }

  Widget _constantRow(PhysicalConstant constant) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _insertConstant(constant),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: _inserted == constant.symbol ? AppColors.accentFaint : AppColors.bgObsidian,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _inserted == constant.symbol ? AppColors.accentSoft : AppColors.panelBorder),
        ),
        child: Row(
          children: <Widget>[
            SizedBox(width: 52, child: _constantSymbol(constant.symbol)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(constant.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.ui(size: 12, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(
                    '${_shorten(constant.value)} ${constant.unit}${constant.exact ? '  (exact)' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.mono(size: 11.5, color: AppColors.textMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Keeps long exact values readable in the list.
  static String _shorten(String value) {
    final e = value.indexOf('e');
    final mantissa = e < 0 ? value : value.substring(0, e);
    if (mantissa.length <= 16) return value;
    return '${mantissa.substring(0, 15)}…${e < 0 ? '' : value.substring(e)}';
  }

  @override
  Widget build(BuildContext context) {
    final value = _showConstants ? null : _typed();
    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = (constraints.maxHeight * 0.40).clamp(120.0, 190.0);
        return Column(
          children: <Widget>[
            ChoiceChips(
              labels: _labels,
              selected: _category,
              height: 32,
              onSelected: (i) => setState(() => _category = i),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Panel(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
                child: _showConstants
                    ? ListView(
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              'CODATA 2022 · tap a constant to insert it into the expression',
                              style: AppTypography.ui(size: 11.5, color: AppColors.textMuted),
                            ),
                          ),
                          for (final c in MathConstants.codata) _constantRow(c),
                        ],
                      )
                    : ListView(
                        key: ValueKey<String>(_current.id),
                        children: <Widget>[for (final unit in _current.units) _unitRow(unit, value)],
                      ),
              ),
            ),
            if (!_showConstants) ...<Widget>[
              const SizedBox(height: 8),
              SizedBox(
                height: pad,
                child: MiniKeypad(
                  onInput: (c) => setState(() => _input = FieldInput.append(_input, c)),
                  onBackspace: () => setState(() => _input = FieldInput.backspace(_input)),
                  onClear: () => setState(() => _input = ''),
                  onEnter: () => setState(() => _input = ''),
                  enterLabel: 'C',
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
