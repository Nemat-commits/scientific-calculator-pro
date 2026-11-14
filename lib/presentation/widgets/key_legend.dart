import 'package:flutter/widgets.dart';

import '../../core/theme/app_typography.dart';

/// Legend of a function key with real superscripts / subscripts
/// (`x²`, `sin⁻¹`, `ʸ√x`, `10ˣ`, `logₐ`) - independent of the glyph coverage
/// of the font.
class KeyLegend extends StatelessWidget {
  const KeyLegend(this.text, {super.key, this.sup, this.sub, this.lead, required this.color, this.size = 17});

  /// Main text.
  final String text;

  /// Raised suffix.
  final String? sup;

  /// Lowered suffix.
  final String? sub;

  /// Raised prefix (the index of a root).
  final String? lead;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final base = AppTypography.mono(size: size, weight: AppWeight.medium, color: color, height: 1.1);
    final small = AppTypography.mono(size: size * 0.62, weight: AppWeight.medium, color: color, height: 1);
    InlineSpan shifted(String s, double dy) => WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Transform.translate(offset: Offset(0, dy), child: Text(AppTypography.signs(s), style: small)),
        );
    return Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          if (lead != null) shifted(lead!, -size * 0.42),
          TextSpan(text: AppTypography.signs(text)),
          if (sup != null) shifted(sup!, -size * 0.42),
          if (sub != null) shifted(sub!, size * 0.18),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
  }
}

/// Legend of the fraction key: two boxes separated by a bar.
class FractionLegend extends StatelessWidget {
  const FractionLegend({super.key, required this.color, this.size = 17});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 0.95,
        height: size * 1.45,
        child: CustomPaint(painter: _FractionPainter(color)),
      );
}

class _FractionPainter extends CustomPainter {
  const _FractionPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.057).clamp(0.9, 1.4)
      ..strokeJoin = StrokeJoin.round;
    final box = size.height * 0.34;
    final left = (size.width - box) / 2;
    final radius = Radius.circular(box * 0.22);
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, 0.7, box, box), radius), stroke)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(left, size.height - box - 0.7, box, box), radius), stroke)
      ..drawLine(Offset(0, size.height / 2), Offset(size.width, size.height / 2), stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_FractionPainter old) => old.color != color;
}

/// Legend of the mixed-fraction key: a box for the whole part in front of
/// the two boxes of the fraction.
class MixedFractionLegend extends StatelessWidget {
  const MixedFractionLegend({super.key, required this.color, this.size = 17});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 1.55,
        height: size * 1.45,
        child: CustomPaint(painter: _MixedFractionPainter(color)),
      );
}

class _MixedFractionPainter extends CustomPainter {
  const _MixedFractionPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.057).clamp(0.9, 1.4)
      ..strokeJoin = StrokeJoin.round;
    final box = size.height * 0.34;
    final whole = size.height * 0.44;
    final radius = Radius.circular(box * 0.22);
    final fractionLeft = whole + size.height * 0.16;
    final fractionWidth = size.width - fractionLeft;
    final boxLeft = fractionLeft + (fractionWidth - box) / 2;
    canvas
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.7, (size.height - whole) / 2, whole, whole), radius), stroke)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(boxLeft, 0.7, box, box), radius), stroke)
      ..drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(boxLeft, size.height - box - 0.7, box, box), radius), stroke)
      ..drawLine(Offset(fractionLeft, size.height / 2), Offset(size.width, size.height / 2),
          stroke..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_MixedFractionPainter old) => old.color != color;
}

/// Legend of the polar-form key: the angle sign, which no bundled font has.
class AngleLegend extends StatelessWidget {
  const AngleLegend({super.key, required this.color, this.size = 17});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size * 0.9,
        height: size * 0.82,
        child: CustomPaint(painter: _AnglePainter(color)),
      );
}

class _AnglePainter extends CustomPainter {
  const _AnglePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.height * 0.11).clamp(0.9, 1.7)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final inset = stroke.strokeWidth / 2;
    final path = Path()
      ..moveTo(size.width * 0.86, inset)
      ..lineTo(inset, size.height - inset)
      ..lineTo(size.width - inset, size.height - inset);
    canvas.drawPath(path, stroke);
  }

  @override
  bool shouldRepaint(_AnglePainter old) => old.color != color;
}
