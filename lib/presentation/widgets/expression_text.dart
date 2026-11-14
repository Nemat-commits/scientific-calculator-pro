import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import 'key_legend.dart';

/// An expression in its linear form (`Σ(1,10,x^2)+2∠30`), as the history
/// tape and the CALC prompt show it.
///
/// The angle sign of the polar form is drawn: no bundled font has it.
class ExpressionText extends StatelessWidget {
  const ExpressionText(this.text, {super.key, required this.style, this.maxLines, this.overflow, this.textAlign});

  final String text;
  final TextStyle style;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign? textAlign;

  static const String _angle = '∠';

  @override
  Widget build(BuildContext context) {
    final shown = AppTypography.signs(text);
    if (!shown.contains(_angle)) {
      return Text(shown, maxLines: maxLines, overflow: overflow, textAlign: textAlign, style: style);
    }
    final parts = shown.split(_angle);
    final size = style.fontSize ?? 14;
    return Text.rich(
      TextSpan(
        children: <InlineSpan>[
          for (var i = 0; i < parts.length; i++) ...<InlineSpan>[
            if (i > 0)
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: size * 0.06),
                  child: AngleLegend(color: style.color ?? AppColors.textSecondary, size: size),
                ),
              ),
            TextSpan(text: parts[i]),
          ],
        ],
      ),
      semanticsLabel: text,
      maxLines: maxLines,
      overflow: overflow,
      textAlign: textAlign,
      style: style,
    );
  }
}
