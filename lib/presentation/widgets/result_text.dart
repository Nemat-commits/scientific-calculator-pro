import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/evaluator/number_formatter.dart';

/// Shows a canonical result string the way people write numbers:
/// thousands separators in the integer part and `×10ⁿ` with a real
/// superscript instead of `e±n`.
class ResultText extends StatelessWidget {
  const ResultText(
    this.value, {
    super.key,
    this.fontSize = 34,
    this.color = AppColors.textPrimary,
    this.weight = AppWeight.medium,
    this.prefix,
    this.alignment = Alignment.centerRight,
    this.wrap = false,
  });

  /// Canonical string from the number formatter (`1e-25`, `-4 + 2i`, …).
  final String value;
  final double fontSize;
  final Color color;
  final AppWeight weight;

  /// Optional lead-in such as `=`.
  final String? prefix;
  final Alignment alignment;

  /// Breaks a long value over several lines at full size instead of
  /// shrinking it onto one.
  final bool wrap;

  static final RegExp _exponent = RegExp(r'e(-?\d+)|\s*×\s*10\^(-?\d+)');

  /// Whether the read-out [secondary] should stand in front of [primary]: a
  /// complex number leads with its short form, because both of its parts at
  /// full length do not fit a line at a readable size.
  static bool leadsWithSecondary(String primary, String? secondary) =>
      secondary != null && secondary.isNotEmpty && primary.endsWith('i');

  /// The read-out of a result to show where there is room for one.
  static String lead(String primary, String? secondary) =>
      leadsWithSecondary(primary, secondary) ? secondary! : primary;

  /// Splits [text] into plain runs and exponents.
  static List<(String text, bool superscript)> segments(String text) {
    final grouped = NumberFormatter.groupThousands(text);
    final out = <(String, bool)>[];
    var last = 0;
    for (final match in _exponent.allMatches(grouped)) {
      if (match.start > last) out.add((grouped.substring(last, match.start), false));
      out
        ..add(('×10', false))
        ..add((match.group(1) ?? match.group(2)!, true));
      last = match.end;
    }
    if (last < grouped.length) out.add((grouped.substring(last), false));
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.mono(size: fontSize, weight: weight, color: color, height: 1.15);
    final small = AppTypography.mono(size: fontSize * 0.6, weight: weight, color: color, height: 1);
    final spans = <InlineSpan>[
      if (prefix != null) TextSpan(text: '$prefix ', style: base.copyWith(color: AppColors.textMuted)),
      for (final (text, superscript) in segments(value))
        if (superscript)
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Transform.translate(
              offset: Offset(0, -fontSize * 0.42),
              child: Text(AppTypography.signs(text), style: small),
            ),
          )
        else
          TextSpan(text: AppTypography.signs(text)),
    ];
    if (wrap) return Text.rich(TextSpan(style: base, children: spans));
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: alignment,
      child: Text.rich(TextSpan(style: base, children: spans), maxLines: 1, softWrap: false),
    );
  }
}
