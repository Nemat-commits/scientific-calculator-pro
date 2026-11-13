import 'package:flutter/widgets.dart';

/// Vector glyphs drawn by hand so the UI does not depend on an icon font.
enum AppIconGlyph { undo, redo, copy, paste, close, search, history, chevronDown, chevronUp, trash, plus, check }

/// A small stroked icon.
class AppIcon extends StatelessWidget {
  const AppIcon(this.glyph, {super.key, this.size = 18, required this.color, this.strokeWidth = 1.6});

  final AppIconGlyph glyph;
  final double size;
  final Color color;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: _IconPainter(glyph, color, strokeWidth)),
      );
}

class _IconPainter extends CustomPainter {
  const _IconPainter(this.glyph, this.color, this.strokeWidth);

  final AppIconGlyph glyph;
  final Color color;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    Offset p(double x, double y) => Offset(x * s, y * s);
    final path = Path();
    void move(double x, double y) => path.moveTo(x * s, y * s);
    void line(double x, double y) => path.lineTo(x * s, y * s);

    switch (glyph) {
      case AppIconGlyph.undo:
      case AppIconGlyph.redo:
        if (glyph == AppIconGlyph.redo) {
          canvas
            ..translate(s, 0)
            ..scale(-1, 1);
        }
        move(0.36, 0.20);
        line(0.14, 0.42);
        line(0.36, 0.64);
        move(0.14, 0.42);
        line(0.60, 0.42);
        path.arcToPoint(p(0.60, 0.82), radius: Radius.circular(0.20 * s));
        line(0.40, 0.82);
      case AppIconGlyph.copy:
        canvas
          ..drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(0.34 * s, 0.30 * s, 0.84 * s, 0.86 * s), Radius.circular(0.10 * s)),
              paint)
          ..drawPath(
            Path()
              ..moveTo(0.66 * s, 0.30 * s)
              ..lineTo(0.66 * s, 0.22 * s)
              ..arcToPoint(p(0.58, 0.14), radius: Radius.circular(0.08 * s), clockwise: false)
              ..lineTo(0.24 * s, 0.14 * s)
              ..arcToPoint(p(0.16, 0.22), radius: Radius.circular(0.08 * s), clockwise: false)
              ..lineTo(0.16 * s, 0.62 * s)
              ..arcToPoint(p(0.24, 0.70), radius: Radius.circular(0.08 * s), clockwise: false)
              ..lineTo(0.34 * s, 0.70 * s),
            paint,
          );
      case AppIconGlyph.paste:
        canvas
          ..drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(0.20 * s, 0.22 * s, 0.80 * s, 0.88 * s), Radius.circular(0.10 * s)),
              paint)
          ..drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTRB(0.36 * s, 0.12 * s, 0.64 * s, 0.30 * s), Radius.circular(0.06 * s)),
              paint);
        move(0.36, 0.52);
        line(0.64, 0.52);
        move(0.36, 0.68);
        line(0.56, 0.68);
      case AppIconGlyph.close:
        move(0.24, 0.24);
        line(0.76, 0.76);
        move(0.76, 0.24);
        line(0.24, 0.76);
      case AppIconGlyph.search:
        canvas.drawCircle(p(0.44, 0.44), 0.24 * s, paint);
        move(0.62, 0.62);
        line(0.84, 0.84);
      case AppIconGlyph.history:
        canvas.drawCircle(p(0.5, 0.5), 0.34 * s, paint);
        move(0.5, 0.30);
        line(0.5, 0.52);
        line(0.64, 0.60);
      case AppIconGlyph.chevronDown:
        move(0.24, 0.38);
        line(0.5, 0.64);
        line(0.76, 0.38);
      case AppIconGlyph.chevronUp:
        move(0.24, 0.62);
        line(0.5, 0.36);
        line(0.76, 0.62);
      case AppIconGlyph.trash:
        move(0.20, 0.28);
        line(0.80, 0.28);
        move(0.40, 0.28);
        line(0.42, 0.16);
        line(0.58, 0.16);
        line(0.60, 0.28);
        move(0.28, 0.28);
        line(0.32, 0.84);
        line(0.68, 0.84);
        line(0.72, 0.28);
      case AppIconGlyph.plus:
        move(0.5, 0.2);
        line(0.5, 0.8);
        move(0.2, 0.5);
        line(0.8, 0.5);
      case AppIconGlyph.check:
        move(0.2, 0.52);
        line(0.42, 0.74);
        line(0.8, 0.28);
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_IconPainter old) => old.glyph != glyph || old.color != color || old.strokeWidth != strokeWidth;
}
