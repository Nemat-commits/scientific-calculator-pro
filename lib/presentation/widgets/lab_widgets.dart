import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'calc_key_button.dart';

/// A raised surface inside a tab.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding = const EdgeInsets.all(12)});

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.panel,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Padding(padding: padding, child: child),
      );
}

/// A row of mutually exclusive chips (scrolls horizontally when crowded).
class ChoiceChips extends StatelessWidget {
  const ChoiceChips({super.key, required this.labels, required this.selected, required this.onSelected, this.height = 30});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: labels.length,
          separatorBuilder: (_, __) => const SizedBox(width: 6),
          itemBuilder: (context, i) {
            final active = i == selected;
            return Semantics(
              button: true,
              selected: active,
              label: labels[i],
              onTap: () => onSelected(i),
              excludeSemantics: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelected(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: active ? AppColors.tabThumb : AppColors.panel,
                    borderRadius: BorderRadius.circular(height / 2),
                    border: Border.all(color: active ? AppColors.accentSoft : AppColors.panelBorder),
                  ),
                  child: Text(
                    labels[i],
                    maxLines: 1,
                    style: AppTypography.ui(
                      size: 12.5,
                      weight: active ? AppWeight.strong : AppWeight.medium,
                      color: active ? AppColors.textPrimary : AppColors.textSecondary,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
}

/// A compact text button.
class SmallButton extends StatelessWidget {
  const SmallButton(this.label, {super.key, required this.onTap, this.primary = false, this.danger = false});

  final String label;
  final VoidCallback? onTap;
  final bool primary;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : (primary ? AppColors.textPrimary : AppColors.accent);
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.4 : 1,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              gradient: primary
                  ? const LinearGradient(colors: <Color>[AppColors.keyEqualsStart, AppColors.keyEqualsEnd])
                  : null,
              color: primary ? null : (danger ? AppColors.keyDanger : AppColors.keyOperator),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(label, maxLines: 1, style: AppTypography.ui(size: 12.5, weight: AppWeight.strong, color: color)),
          ),
        ),
      ),
    );
  }
}

/// A value slot that is edited with the [MiniKeypad].
class LabField extends StatelessWidget {
  const LabField({
    super.key,
    required this.value,
    required this.active,
    required this.onTap,
    this.label,
    this.hint = '0',
    this.minWidth = 54,
    this.error = false,
  });

  final String value;
  final bool active;
  final VoidCallback onTap;

  /// Caption shown in front of the value.
  final String? label;
  final String hint;
  final double minWidth;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final border = error ? AppColors.error : (active ? AppColors.accent : AppColors.panelBorder);
    return Semantics(
      textField: true,
      label: label,
      value: value,
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          constraints: BoxConstraints(minWidth: minWidth, minHeight: 34),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: active ? AppColors.accentFaint : AppColors.bgObsidian,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: active ? 1.4 : 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (label != null) ...<Widget>[
                Text(label!, style: AppTypography.ui(size: 12, weight: AppWeight.medium, color: AppColors.textMuted)),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value.isEmpty ? hint : value,
                    maxLines: 1,
                    style: AppTypography.mono(
                      size: 15,
                      weight: AppWeight.medium,
                      color: value.isEmpty ? AppColors.textFaint : AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
              if (active) Container(width: 1.5, height: 16, margin: const EdgeInsets.only(left: 2), color: AppColors.caret),
            ],
          ),
        ),
      ),
    );
  }
}

/// Numeric keypad for the fields of the lab and the converter.
///
/// It feeds characters to whichever field is active; the main expression is
/// never touched.
class MiniKeypad extends StatelessWidget {
  const MiniKeypad({
    super.key,
    required this.onInput,
    required this.onBackspace,
    required this.onEnter,
    this.enterLabel = '⏎',
    this.onClear,
    this.allowFraction = true,
  });

  /// Called with the character of a key.
  final ValueChanged<String> onInput;
  final VoidCallback onBackspace;

  /// Confirm / next field.
  final VoidCallback onEnter;
  final String enterLabel;

  /// Shown instead of the fraction slash when set.
  final VoidCallback? onClear;
  final bool allowFraction;

  @override
  Widget build(BuildContext context) {
    Widget char(String label, [String? value, KeyTone tone = KeyTone.digit]) => CalcKeyButton(
          label: label,
          tone: tone,
          fontSize: 19,
          radius: 12,
          onPressed: () => onInput(value ?? label),
        );
    return KeyGrid(
      gap: 6,
      rows: <List<Widget>>[
        <Widget>[
          char('7'),
          char('8'),
          char('9'),
          CalcKeyButton(
            label: '⌫',
            tone: KeyTone.danger,
            fontSize: 18,
            radius: 12,
            repeats: true,
            semanticLabel: 'Backspace',
            onPressed: onBackspace,
            onLongPress: onClear,
          ),
        ],
        <Widget>[char('4'), char('5'), char('6'), char('−', '−', KeyTone.operator)],
        <Widget>[
          char('1'),
          char('2'),
          char('3'),
          if (onClear != null && !allowFraction)
            CalcKeyButton(label: 'C', tone: KeyTone.danger, fontSize: 18, radius: 12, onPressed: onClear)
          else
            char('a/b', '/', KeyTone.operator),
        ],
        <Widget>[
          char('0'),
          char('.'),
          char('E', 'E', KeyTone.function),
          CalcKeyButton(
            label: enterLabel,
            tone: KeyTone.equals,
            fontSize: 18,
            radius: 12,
            semanticLabel: switch (enterLabel) { '⏎' => 'Next field', 'C' => 'Clear', _ => enterLabel },
            onPressed: onEnter,
          ),
        ],
      ],
    );
  }
}

/// `label  value` line of a result list.
class ValueRow extends StatelessWidget {
  const ValueRow(this.label, this.value, {super.key, this.onTap, this.emphasised = false});

  final String label;
  final String value;
  final VoidCallback? onTap;
  final bool emphasised;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: <Widget>[
              Text(label, style: AppTypography.ui(size: 12.5, weight: AppWeight.medium, color: AppColors.textMuted)),
              const SizedBox(width: 12),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(
                    value,
                    maxLines: 1,
                    style: AppTypography.mono(
                      size: emphasised ? 16 : 14,
                      weight: emphasised ? AppWeight.medium : AppWeight.regular,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// Caption of a section.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text.toUpperCase(),
          style: AppTypography.ui(size: 10.5, weight: AppWeight.strong, color: AppColors.textMuted, letterSpacing: 0.8),
        ),
      );
}

/// Edits a string the way the mini keypad types into a field.
abstract final class FieldInput {
  /// Appends [char] to [value] (a minus sign toggles in front of an empty
  /// or already negative entry).
  static String append(String value, String char) {
    if (char == '−' && (value.isEmpty || value == '−')) return value.isEmpty ? '−' : '';
    if (value.length >= 40) return value;
    return '$value$char';
  }

  /// Removes the last character.
  static String backspace(String value) => value.isEmpty ? value : value.substring(0, value.length - 1);
}
