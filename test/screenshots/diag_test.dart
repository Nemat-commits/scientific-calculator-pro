// TEMPORARY diagnostic: how does the test renderer stroke the integral sign?
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final GlobalKey boundary = GlobalKey();

Paint stroke(double width, {StrokeCap cap = StrokeCap.round, StrokeJoin join = StrokeJoin.round}) => Paint()
  ..color = const Color(0xFF38BDF8)
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = cap
  ..strokeJoin = join;

class Diag extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const f = 36.5;
    const top = 1.175 * f, bottom = 0.575 * f;
    const y = 70.0;
    final w = math.max(1.2, f * 0.065);
    double cxOf(int i) => 30.0 + i * 45;

    Path original(double cx) {
      final t = y - top, b = y + bottom;
      return Path()
        ..moveTo(cx + f * 0.19, t + f * 0.09)
        ..cubicTo(cx + f * 0.17, t - f * 0.02, cx + f * 0.04, t - f * 0.02, cx + f * 0.03, t + f * 0.18)
        ..lineTo(cx - f * 0.03, b - f * 0.18)
        ..cubicTo(cx - f * 0.04, b + f * 0.02, cx - f * 0.17, b + f * 0.02, cx - f * 0.19, b - f * 0.09);
    }

    // 0: exactly as the app draws it
    canvas.drawPath(original(cxOf(0)), stroke(w));
    // 1: butt caps + miter joins
    canvas.drawPath(original(cxOf(1)), stroke(w, cap: StrokeCap.butt, join: StrokeJoin.miter));
    // 2: bevel joins, round caps
    canvas.drawPath(original(cxOf(2)), stroke(w, join: StrokeJoin.bevel));
    // 3: three separate paths
    {
      final cx = cxOf(3), t = y - top, b = y + bottom;
      canvas
        ..drawPath(
          Path()
            ..moveTo(cx + f * 0.19, t + f * 0.09)
            ..cubicTo(cx + f * 0.17, t - f * 0.02, cx + f * 0.04, t - f * 0.02, cx + f * 0.03, t + f * 0.18),
          stroke(w),
        )
        ..drawLine(Offset(cx + f * 0.03, t + f * 0.18), Offset(cx - f * 0.03, b - f * 0.18), stroke(w))
        ..drawPath(
          Path()
            ..moveTo(cx - f * 0.03, b - f * 0.18)
            ..cubicTo(cx - f * 0.04, b + f * 0.02, cx - f * 0.17, b + f * 0.02, cx - f * 0.19, b - f * 0.09),
          stroke(w),
        );
    }
    // 4: flattened to a polyline by path metrics
    {
      final flat = Path();
      var first = true;
      for (final metric in original(cxOf(4)).computeMetrics()) {
        for (var d = 0.0; d <= metric.length; d += 1.5) {
          final p = metric.getTangentForOffset(d)!.position;
          if (first) {
            flat.moveTo(p.dx, p.dy);
            first = false;
          } else {
            flat.lineTo(p.dx, p.dy);
          }
        }
      }
      canvas.drawPath(flat, stroke(w));
    }
    // 5: quadratic hooks instead of cubic ones
    {
      final cx = cxOf(5), t = y - top, b = y + bottom;
      canvas.drawPath(
        Path()
          ..moveTo(cx + f * 0.19, t + f * 0.09)
          ..quadraticBezierTo(cx + f * 0.10, t - f * 0.10, cx + f * 0.03, t + f * 0.18)
          ..lineTo(cx - f * 0.03, b - f * 0.18)
          ..quadraticBezierTo(cx - f * 0.10, b + f * 0.10, cx - f * 0.19, b - f * 0.09),
        stroke(w),
      );
    }
    // 6: original, filled instead of stroked (shows what the path contains)
    canvas.drawPath(original(cxOf(6)), Paint()..color = const Color(0xFFFB7185));
    // 7: the original with a thin stroke
    canvas.drawPath(original(cxOf(7)), stroke(1));
    // 8: only cubic + line
    {
      final cx = cxOf(8), t = y - top, b = y + bottom;
      canvas.drawPath(
        Path()
          ..moveTo(cx + f * 0.19, t + f * 0.09)
          ..cubicTo(cx + f * 0.17, t - f * 0.02, cx + f * 0.04, t - f * 0.02, cx + f * 0.03, t + f * 0.18)
          ..lineTo(cx - f * 0.03, b - f * 0.18),
        stroke(w),
      );
    }
    // 9: line + cubic only
    {
      final cx = cxOf(9), t = y - top, b = y + bottom;
      canvas.drawPath(
        Path()
          ..moveTo(cx + f * 0.03, t + f * 0.18)
          ..lineTo(cx - f * 0.03, b - f * 0.18)
          ..cubicTo(cx - f * 0.04, b + f * 0.02, cx - f * 0.17, b + f * 0.02, cx - f * 0.19, b - f * 0.09),
        stroke(w),
      );
    }
  }

  @override
  bool shouldRepaint(Diag old) => false;
}

void main() {
  testWidgets('integral sign variants', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.physicalSize = const Size(1000, 240);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: ColoredBox(
          color: const Color(0xFF11151F),
          child: CustomPaint(size: const Size(500, 120), painter: Diag()),
        ),
      ),
    );
    await tester.runAsync(() async {
      final render = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('build/screenshots/diag_integral.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }, skip: Platform.environment['CALC_SCREENSHOTS'] != '1');
}
