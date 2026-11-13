import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/editor/cursor_path.dart';
import '../../domain/models/editor_node.dart';

/// Where the caret can go inside one slot, in canvas coordinates.
class SlotGeometry {
  const SlotGeometry({
    required this.id,
    required this.depth,
    required this.caretX,
    required this.baseline,
    required this.ascent,
    required this.descent,
    required this.fontSize,
  });

  final String id;

  /// Nesting level (the root sequence is 0).
  final int depth;

  /// Caret abscissae for offsets `0..n`.
  final List<double> caretX;
  final double baseline;
  final double ascent;
  final double descent;
  final double fontSize;

  Rect get rect => Rect.fromLTRB(caretX.first, baseline - ascent, caretX.last, baseline + descent);
}

/// A laid-out expression, ready to be painted and hit-tested.
class MathLayout {
  MathLayout._(this._root, this.slots, this.size);

  final _Box _root;

  /// Geometry of every slot, parents before children.
  final List<SlotGeometry> slots;

  /// Tight size of the expression.
  final Size size;

  SlotGeometry? slot(String id) {
    for (final s in slots) {
      if (s.id == id) return s;
    }
    return null;
  }

  void paint(Canvas canvas) => _root.paint(canvas);

  /// The caret position closest to [point].
  (String sequenceId, int offset)? hitTest(Offset point) {
    if (slots.isEmpty) return null;
    SlotGeometry best = slots.first;
    for (final s in slots) {
      final pad = s.fontSize * 0.25;
      if (s.rect.inflate(pad).contains(point) && s.depth >= best.depth) best = s;
    }
    var index = 0;
    var distance = double.infinity;
    for (var i = 0; i < best.caretX.length; i++) {
      final d = (best.caretX[i] - point.dx).abs();
      if (d < distance) {
        distance = d;
        index = i;
      }
    }
    return (best.id, index);
  }
}

/// Recursive layout of the editor tree into boxes with a common baseline.
class MathLayoutEngine {
  MathLayoutEngine({required this.fontSize, this.activeSlotId, this.textScaler = TextScaler.noScaling})
      : _minFont = fontSize * 0.5;

  /// Font size of the root line.
  final double fontSize;

  /// Slot that holds the caret (its empty placeholder is highlighted).
  final String? activeSlotId;
  final TextScaler textScaler;
  final double _minFont;
  final List<SlotGeometry> _slots = <SlotGeometry>[];

  static final Map<String, TextPainter> _painters = <String, TextPainter>{};

  /// Drops the cached glyph runs (call after fonts finished loading).
  static void clearCache() => _painters.clear();

  MathLayout layout(EditorSequence root) {
    final box = _sequence(root, fontSize, 0);
    final pad = fontSize * 0.08;
    box.place(pad, box.asc + pad, this);
    return MathLayout._(box, List<SlotGeometry>.unmodifiable(_slots), Size(box.w + 2 * pad, box.asc + box.desc + 2 * pad));
  }

  double _scaled(double f, double k) => math.max(f * k, _minFont);

  TextPainter _text(String text, double size, Color color, {AppWeight weight = AppWeight.regular}) {
    final key = '$text|$size|${color.hashCode}|${weight.index}|${AppTypography.useGoogleFonts}';
    final cached = _painters[key];
    if (cached != null) return cached;
    if (_painters.length > 1500) _painters.clear();
    final painter = TextPainter(
      text: TextSpan(text: AppTypography.signs(text), style: AppTypography.mono(size: size, color: color, weight: weight)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 1,
    )..layout();
    return _painters[key] = painter;
  }

  _TextBox _glyphs(String text, double f, Color color, {double padLeft = 0, double padRight = 0, AppWeight weight = AppWeight.regular}) =>
      _TextBox(_text(text, f, color, weight: weight), f, padLeft: padLeft, padRight: padRight);

  static const Map<String, String> _functionLabels = <String, String>{
    'ncr': 'nCr',
    'npr': 'nPr',
    'gamma': 'Γ',
    'logb': 'log',
  };

  /// Inverse functions are written as `sin⁻¹` with a real superscript.
  static const Set<String> _inverseFunctions = <String>{'asin', 'acos', 'atan', 'asinh', 'acosh', 'atanh'};

  _SeqBox _sequence(EditorSequence seq, double f, int depth) {
    final box = _SeqBox(seq.id, f, depth, active: seq.id == activeSlotId);
    var x = 0.0;
    _Box? previous;
    final children = seq.children;
    for (var i = 0; i < children.length; i++) {
      final node = children[i];
      final child = switch (node) {
        AtomNode() => _atom(node, i == 0 ? null : children[i - 1], f),
        FractionNode(:final numerator, :final denominator) => _FractionBox(
            _sequence(numerator, _scaled(f, 0.85), depth + 1),
            _sequence(denominator, _scaled(f, 0.85), depth + 1),
            f,
          ),
        PowerNode(:final exponent) =>
          _PowerBox(_sequence(exponent, _scaled(f, 0.68), depth + 1), f, previous?.asc ?? f * 0.76),
        RootNode(:final degree, :final radicand) => _RootBox(
            degree.isEmpty && degree.id != activeSlotId ? null : _sequence(degree, _scaled(f, 0.55), depth + 1),
            _sequence(radicand, f, depth + 1),
            f,
          ),
        FunctionCallEditorNode(:final functionName, :final argSlots) => _call(functionName, argSlots, f, depth),
        CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand, :final dummyVariable) =>
          _IntegralBox(
            _sequence(lowerBound, _scaled(f, 0.62), depth + 1),
            _sequence(upperBound, _scaled(f, 0.62), depth + 1),
            _sequence(integrand, f, depth + 1),
            _glyphs('d$dummyVariable', f, AppColors.mathFunction, padLeft: f * 0.12),
            f,
          ),
        DerivativeEditorNode(:final body, :final evalPoint, :final dummyVariable) => _DerivativeBox(
            _glyphs('d', _scaled(f, 0.7), AppColors.mathFunction),
            _glyphs('d$dummyVariable', _scaled(f, 0.7), AppColors.mathFunction),
            _sequence(body, f, depth + 1),
            _glyphs('$dummyVariable=', _scaled(f, 0.62), AppColors.mathFunction),
            _sequence(evalPoint, _scaled(f, 0.62), depth + 1),
            f,
          ),
      };
      box.add(child, x);
      x += child.w;
      previous = child;
    }
    box.finish(x);
    return box;
  }

  _Box _atom(AtomNode node, EditorNode? before, double f) {
    final text = node.text;
    switch (node.kind) {
      case AtomKind.digit:
        if (text == 'E') {
          return _glyphs('E', f * 0.8, AppColors.mathOperator, padLeft: f * 0.04, padRight: f * 0.04, weight: AppWeight.medium);
        }
        return _glyphs(text, f, AppColors.mathDigit);
      case AtomKind.binaryOp:
        // A sign in prefix position hugs its operand.
        final prefix = before == null ||
            (before is AtomNode &&
                (before.kind == AtomKind.binaryOp ||
                    before.kind == AtomKind.separator ||
                    before.kind == AtomKind.unaryPrefix ||
                    (before.kind == AtomKind.paren && before.text == '(') ||
                    (before.kind == AtomKind.digit && before.text == 'E')));
        final word = text.length > 1 && text != '<<' && text != '>>';
        final pad = prefix ? f * 0.03 : f * (word ? 0.30 : 0.17);
        return _glyphs(text, word ? f * 0.82 : f, AppColors.mathOperator, padLeft: pad, padRight: pad);
      case AtomKind.unaryPostfix:
        return _glyphs(text, f, AppColors.mathOperator);
      case AtomKind.unaryPrefix:
        return _glyphs(text, text.length > 1 ? f * 0.82 : f, AppColors.mathOperator, padRight: text.length > 1 ? f * 0.25 : 0);
      case AtomKind.constant:
        return _symbol(text, f, AppColors.mathConstant);
      case AtomKind.variable:
        return _symbol(text, f, AppColors.mathVariable);
      case AtomKind.paren:
        return _glyphs(text, f, AppColors.mathParen);
      case AtomKind.separator:
        return _glyphs(text, f, AppColors.mathParen, padRight: f * 0.12);
    }
  }

  /// A symbol whose `_` introduces a subscript (`m_e` → mₑ).
  _Box _symbol(String text, double f, Color color) {
    final split = text.indexOf('_');
    if (split <= 0 || split == text.length - 1) return _glyphs(text, f, color);
    final base = _glyphs(text.substring(0, split), f, color);
    final sub = _glyphs(text.substring(split + 1), f * 0.6, color);
    return _GroupBox()
      ..put(base, 0, 0)
      ..put(sub, base.w + f * 0.01, f * 0.20)
      ..close(extraRight: f * 0.03);
  }

  _Box _call(String name, List<EditorSequence> slots, double f, int depth) {
    if (name == 'abs' && slots.length == 1) {
      return _BarsBox(_sequence(slots.first, f, depth + 1), f);
    }
    final group = _GroupBox();
    var x = 0.0;
    var args = slots;
    final inverse = _inverseFunctions.contains(name);
    final label = _glyphs(inverse ? name.substring(1) : (_functionLabels[name] ?? name), f, AppColors.mathFunction);
    group.put(label, x, 0);
    x += label.w;
    if (inverse) {
      final minusOne = _glyphs('−1', f * 0.6, AppColors.mathFunction);
      group.put(minusOne, x + f * 0.01, -f * 0.42);
      x += minusOne.w + f * 0.02;
    }
    if (name == 'logb' && slots.length == 2) {
      // log with its base as a subscript
      final base = _sequence(slots.first, _scaled(f, 0.6), depth + 1);
      group.put(base, x + f * 0.02, f * 0.24);
      x += base.w + f * 0.04;
      args = slots.sublist(1);
    }
    final inner = _GroupBox();
    var ix = 0.0;
    for (var i = 0; i < args.length; i++) {
      if (i > 0) {
        final comma = _glyphs(',', f, AppColors.mathParen, padRight: f * 0.14);
        inner.put(comma, ix, 0);
        ix += comma.w;
      }
      final arg = _sequence(args[i], f, depth + 1);
      inner.put(arg, ix, 0);
      ix += arg.w;
    }
    inner.close();
    final parens = _ParenBox(inner, f);
    group.put(parens, x + f * 0.02, 0);
    return group..close();
  }

  void _record(SlotGeometry geometry) => _slots.add(geometry);
}

// ----------------------------------------------------------------------------
// Boxes. `x` is the left edge and `y` the baseline, both absolute once placed.
// ----------------------------------------------------------------------------

abstract class _Box {
  double w = 0;
  double asc = 0;
  double desc = 0;
  double x = 0;
  double y = 0;

  void place(double px, double py, MathLayoutEngine engine) {
    x = px;
    y = py;
  }

  void paint(Canvas canvas);
}

double _rule(double f) => math.max(1, f * 0.055);
double _axis(double f) => f * 0.27;

Paint _stroke(Color color, double width) => Paint()
  ..color = color
  ..style = PaintingStyle.stroke
  ..strokeWidth = width
  ..strokeCap = StrokeCap.round
  ..strokeJoin = StrokeJoin.round;

class _TextBox extends _Box {
  _TextBox(this.painter, double f, {this.padLeft = 0, double padRight = 0}) {
    w = painter.width + padLeft + padRight;
    asc = f * 0.76;
    desc = f * 0.22;
    _baseline = painter.computeDistanceToActualBaseline(TextBaseline.alphabetic);
  }

  final TextPainter painter;
  final double padLeft;
  late final double _baseline;

  @override
  void paint(Canvas canvas) => painter.paint(canvas, Offset(x + padLeft, y - _baseline));
}

/// Children at fixed offsets relative to the group's origin.
class _GroupBox extends _Box {
  final List<(_Box box, double dx, double dy)> kids = <(_Box, double, double)>[];

  void put(_Box box, double dx, double dy) => kids.add((box, dx, dy));

  /// Derives the group's metrics from its children.
  void close({double extraRight = 0}) {
    for (final (box, dx, dy) in kids) {
      w = math.max(w, dx + box.w);
      asc = math.max(asc, box.asc - dy);
      desc = math.max(desc, box.desc + dy);
    }
    w += extraRight;
  }

  @override
  void place(double px, double py, MathLayoutEngine engine) {
    super.place(px, py, engine);
    for (final (box, dx, dy) in kids) {
      box.place(px + dx, py + dy, engine);
    }
  }

  @override
  void paint(Canvas canvas) {
    for (final (box, _, _) in kids) {
      box.paint(canvas);
    }
  }
}

/// One slot: its children share a baseline; an empty slot shows a placeholder.
class _SeqBox extends _Box {
  _SeqBox(this.id, this.f, this.depth, {required this.active});

  final String id;
  final double f;
  final int depth;
  final bool active;
  final List<(_Box box, double dx)> items = <(_Box, double)>[];
  final List<double> _carets = <double>[0];

  void add(_Box box, double dx) {
    items.add((box, dx));
    _carets.add(dx + box.w);
    asc = math.max(asc, box.asc);
    desc = math.max(desc, box.desc);
  }

  void finish(double width) {
    if (items.isEmpty) {
      w = f * 0.58;
      asc = f * 0.76;
      desc = f * 0.10;
      _carets[0] = w / 2;
    } else {
      w = width;
      asc = math.max(asc, f * 0.76);
      desc = math.max(desc, f * 0.22);
    }
  }

  @override
  void place(double px, double py, MathLayoutEngine engine) {
    super.place(px, py, engine);
    engine._record(
      SlotGeometry(
        id: id,
        depth: depth,
        caretX: <double>[for (final c in _carets) px + c],
        baseline: py,
        ascent: math.max(asc, f * 0.80),
        descent: math.max(desc, f * 0.22),
        fontSize: f,
      ),
    );
    for (final (box, dx) in items) {
      box.place(px + dx, py, engine);
    }
  }

  @override
  void paint(Canvas canvas) {
    if (items.isEmpty) {
      // The empty expression line shows just the caret.
      if (depth == 0) return;
      final rect = Rect.fromLTRB(x + f * 0.06, y - f * 0.70, x + w - f * 0.06, y + f * 0.04);
      final radius = Radius.circular(f * 0.10);
      if (active) {
        canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), Paint()..color = AppColors.accentFaint);
      }
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, radius),
        _stroke(active ? AppColors.accent : AppColors.mathPlaceholder, math.max(1, f * 0.035)),
      );
      return;
    }
    for (final (box, _) in items) {
      box.paint(canvas);
    }
  }
}

class _FractionBox extends _GroupBox {
  _FractionBox(_SeqBox numerator, _SeqBox denominator, this.f) {
    final pad = f * 0.14, side = f * 0.05, gap = f * 0.13;
    final t = _rule(f), ax = _axis(f);
    final inner = math.max(numerator.w, denominator.w);
    put(numerator, side + pad + (inner - numerator.w) / 2, -(ax + t / 2 + gap + numerator.desc));
    put(denominator, side + pad + (inner - denominator.w) / 2, -ax + t / 2 + gap + denominator.asc);
    close();
    w = inner + 2 * pad + 2 * side;
  }

  final double f;

  @override
  void paint(Canvas canvas) {
    final side = f * 0.05, barY = y - _axis(f);
    canvas.drawLine(Offset(x + side, barY), Offset(x + w - side, barY), _stroke(AppColors.mathDigit, _rule(f)));
    super.paint(canvas);
  }
}

class _PowerBox extends _GroupBox {
  _PowerBox(_SeqBox exponent, double f, double baseAscent) {
    final raise = math.max(f * 0.42, baseAscent - exponent.f * 0.55);
    put(exponent, f * 0.03, -raise);
    close(extraRight: f * 0.03);
    desc = 0;
  }
}

class _RootBox extends _GroupBox {
  _RootBox(_SeqBox? degree, this.radicand, this.f) {
    const hook = 0.24;
    final extraLeft = degree == null ? 0.0 : math.max(0.0, degree.w - f * hook);
    signX = extraLeft;
    bodyAscent = radicand.asc + f * 0.17;
    put(radicand, extraLeft + f * 0.50, 0);
    if (degree != null) {
      put(degree, extraLeft + f * hook - degree.w, -math.max(f * 0.46, bodyAscent * 0.52));
    }
    close(extraRight: f * 0.12);
    asc = math.max(asc, bodyAscent + _rule(f));
    desc = math.max(desc, f * 0.10);
  }

  final _SeqBox radicand;
  final double f;
  late final double signX;
  late final double bodyAscent;

  @override
  void paint(Canvas canvas) {
    final x0 = x + signX;
    final top = y - bodyAscent - _rule(f) / 2;
    final path = Path()
      ..moveTo(x0 + f * 0.03, y - f * 0.27)
      ..lineTo(x0 + f * 0.13, y - f * 0.33)
      ..lineTo(x0 + f * 0.27, y + desc - f * 0.03)
      ..lineTo(x0 + f * 0.46, top)
      ..lineTo(x0 + f * 0.50 + radicand.w + f * 0.08, top);
    canvas.drawPath(path, _stroke(AppColors.mathDigit, _rule(f) * 1.1));
    super.paint(canvas);
  }
}

/// Parentheses drawn to the height of their content.
class _ParenBox extends _GroupBox {
  _ParenBox(_Box content, this.f) {
    put(content, f * 0.30, 0);
    close(extraRight: f * 0.30);
    asc = math.max(asc, f * 0.76);
    desc = math.max(desc, f * 0.22);
  }

  final double f;

  @override
  void paint(Canvas canvas) {
    final top = y - asc - f * 0.02, bottom = y + desc + f * 0.02;
    final paint = _stroke(AppColors.mathParen, _rule(f) * 1.05);
    final bulge = f * 0.17;
    Path arc(double edge, double direction) => Path()
      ..moveTo(edge, top)
      ..quadraticBezierTo(edge - direction * bulge * 2, (top + bottom) / 2, edge, bottom);
    canvas
      ..drawPath(arc(x + f * 0.24, 1), paint)
      ..drawPath(arc(x + w - f * 0.24, -1), paint);
    super.paint(canvas);
  }
}

/// `|x|`
class _BarsBox extends _GroupBox {
  _BarsBox(_Box content, this.f) {
    put(content, f * 0.20, 0);
    close(extraRight: f * 0.20);
    asc = math.max(asc, f * 0.76);
    desc = math.max(desc, f * 0.22);
  }

  final double f;

  @override
  void paint(Canvas canvas) {
    final paint = _stroke(AppColors.mathFunction, _rule(f));
    final top = y - asc - f * 0.02, bottom = y + desc + f * 0.02;
    canvas
      ..drawLine(Offset(x + f * 0.09, top), Offset(x + f * 0.09, bottom), paint)
      ..drawLine(Offset(x + w - f * 0.09, top), Offset(x + w - f * 0.09, bottom), paint);
    super.paint(canvas);
  }
}

class _IntegralBox extends _GroupBox {
  _IntegralBox(_SeqBox lower, _SeqBox upper, _SeqBox integrand, _TextBox differential, this.f) {
    final signHeight = math.max(f * 1.75, integrand.asc + integrand.desc + f * 0.30);
    top = _axis(f) + signHeight / 2;
    bottom = signHeight / 2 - _axis(f);
    put(upper, f * 0.46, -(top - upper.asc * 0.85));
    put(lower, f * 0.30, bottom - f * 0.02 - lower.desc * 0.2);
    final boundsRight = math.max(f * 0.46 + upper.w, f * 0.30 + lower.w);
    final bodyX = math.max(f * 0.58, boundsRight + f * 0.10);
    put(integrand, bodyX, 0);
    put(differential, bodyX + integrand.w, 0);
    close(extraRight: f * 0.06);
    asc = math.max(asc, top + f * 0.03);
    desc = math.max(desc, bottom + f * 0.03);
  }

  final double f;
  late final double top;
  late final double bottom;

  @override
  void paint(Canvas canvas) {
    final cx = x + f * 0.22, t = y - top, b = y + bottom;
    final path = Path()
      ..moveTo(cx + f * 0.19, t + f * 0.09)
      ..cubicTo(cx + f * 0.17, t - f * 0.02, cx + f * 0.04, t - f * 0.02, cx + f * 0.03, t + f * 0.18)
      ..lineTo(cx - f * 0.03, b - f * 0.18)
      ..cubicTo(cx - f * 0.04, b + f * 0.02, cx - f * 0.17, b + f * 0.02, cx - f * 0.19, b - f * 0.09);
    canvas.drawPath(path, _stroke(AppColors.mathOperator, math.max(1.2, f * 0.065)));
    super.paint(canvas);
  }
}

class _DerivativeBox extends _GroupBox {
  _DerivativeBox(_TextBox top, _TextBox bottom, _SeqBox body, _TextBox pointLabel, _SeqBox point, this.f) {
    // d / dx as a small stacked fraction
    final t = _rule(f), ax = _axis(f), gap = f * 0.10;
    operatorWidth = math.max(top.w, bottom.w) + f * 0.12;
    put(top, (operatorWidth - top.w) / 2, -(ax + t / 2 + gap + top.desc * 0.4));
    put(bottom, (operatorWidth - bottom.w) / 2, -ax + t / 2 + gap + bottom.asc * 0.92);
    final parens = _ParenBox(body, f);
    put(parens, operatorWidth + f * 0.06, 0);
    barX = operatorWidth + f * 0.06 + parens.w + f * 0.08;
    barTop = parens.asc + f * 0.04;
    barBottom = math.max(parens.desc + f * 0.30, f * 0.52);
    final drop = barBottom - point.desc * 0.5;
    put(pointLabel, barX + f * 0.10, drop);
    put(point, barX + f * 0.10 + pointLabel.w, drop);
    close(extraRight: f * 0.06);
  }

  final double f;
  late final double operatorWidth;
  late final double barX;
  late final double barTop;
  late final double barBottom;

  @override
  void paint(Canvas canvas) {
    final barY = y - _axis(f);
    canvas
      ..drawLine(Offset(x + f * 0.03, barY), Offset(x + operatorWidth - f * 0.03, barY), _stroke(AppColors.mathFunction, _rule(f)))
      ..drawLine(Offset(x + barX, y - barTop), Offset(x + barX, y + barBottom), _stroke(AppColors.mathFunction, _rule(f)));
    super.paint(canvas);
  }
}

// ----------------------------------------------------------------------------
// Widget
// ----------------------------------------------------------------------------

/// Renders an editor tree in 2D (stacked fractions, radical bars, raised
/// exponents, integral bounds) with a blinking caret, and reports taps as
/// caret positions.
class MathPrintCanvas extends StatefulWidget {
  const MathPrintCanvas({
    super.key,
    required this.root,
    this.cursor,
    this.fontSize = 32,
    this.showCaret = true,
    this.onTapPosition,
    this.alignment = Alignment.centerLeft,
  });

  final EditorSequence root;

  /// Caret position; `null` renders a read-only expression.
  final CursorPath? cursor;
  final double fontSize;
  final bool showCaret;

  /// Called with the caret position nearest to a tap.
  final void Function(String sequenceId, int offset)? onTapPosition;
  final Alignment alignment;

  @override
  State<MathPrintCanvas> createState() => _MathPrintCanvasState();
}

class _MathPrintCanvasState extends State<MathPrintCanvas> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1060));
  final ScrollController _scroll = ScrollController();

  MathLayout? _layout;
  Object? _layoutKey;

  @override
  void initState() {
    super.initState();
    _blink.repeat();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  @override
  void didUpdateWidget(MathPrintCanvas old) {
    super.didUpdateWidget(old);
    if (old.cursor != widget.cursor || !identical(old.root, widget.root)) {
      _blink
        ..value = 0
        ..repeat();
    }
  }

  @override
  void dispose() {
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _blink.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _fontsChanged() {
    MathLayoutEngine.clearCache();
    if (mounted) setState(() => _layoutKey = null);
  }

  MathLayout _layoutFor(double fontSize, TextScaler scaler) {
    final active = widget.cursor?.sequenceId;
    final key = (widget.root, fontSize, active, scaler);
    final cached = _layout;
    if (cached != null && _layoutKey == key) return cached;
    _layoutKey = key;
    return _layout = MathLayoutEngine(fontSize: fontSize, activeSlotId: active, textScaler: scaler).layout(widget.root);
  }

  /// Keeps the caret inside the viewport after the content changed.
  void _revealCaret(MathLayout layout, double viewport) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      final position = _scroll.position;
      final cursor = widget.cursor;
      double target;
      if (cursor == null) {
        target = position.pixels;
      } else {
        final slot = layout.slot(cursor.sequenceId);
        if (slot == null) return;
        final index = cursor.offset < slot.caretX.length ? cursor.offset : slot.caretX.length - 1;
        final caret = slot.caretX[index];
        final margin = math.min(48.0, viewport * 0.2);
        target = position.pixels;
        if (caret < target + margin) target = caret - margin;
        if (caret > target + viewport - margin) target = caret - viewport + margin;
      }
      target = target.clamp(position.minScrollExtent, position.maxScrollExtent);
      if ((target - position.pixels).abs() > 0.5) _scroll.jumpTo(target);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.isFinite ? constraints.maxHeight : double.infinity;
        var layout = _layoutFor(widget.fontSize, scaler);
        if (layout.size.height > maxHeight && maxHeight > 0) {
          // Too tall for the display: shrink the whole expression.
          final factor = math.max(0.5, maxHeight / layout.size.height);
          layout = _layoutFor((widget.fontSize * factor * 100).floorToDouble() / 100, scaler);
        }
        final viewport = constraints.maxWidth.isFinite ? constraints.maxWidth : layout.size.width;
        final height = maxHeight.isFinite ? maxHeight : layout.size.height;
        final width = math.max(layout.size.width, viewport);
        // Free space is distributed according to the alignment.
        final dx = (width - layout.size.width) * (widget.alignment.x + 1) / 2;
        final dy = math.max(0.0, (height - layout.size.height) * (widget.alignment.y + 1) / 2);
        final origin = Offset(dx, dy);
        _revealCaret(layout, viewport);
        return SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          physics: const ClampingScrollPhysics(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: widget.onTapPosition == null
                ? null
                : (details) {
                    final hit = layout.hitTest(details.localPosition - origin);
                    if (hit != null) widget.onTapPosition!(hit.$1, hit.$2);
                  },
            child: RepaintBoundary(
              child: CustomPaint(
                size: Size(width, height),
                painter: _ExpressionPainter(layout, origin),
                foregroundPainter: widget.showCaret && widget.cursor != null
                    ? _CaretPainter(layout, origin, widget.cursor!, _blink)
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ExpressionPainter extends CustomPainter {
  const _ExpressionPainter(this.layout, this.origin);

  final MathLayout layout;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..translate(origin.dx, origin.dy);
    layout.paint(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ExpressionPainter old) => !identical(old.layout, layout) || old.origin != origin;
}

class _CaretPainter extends CustomPainter {
  _CaretPainter(this.layout, this.origin, this.cursor, this.blink) : super(repaint: blink);

  final MathLayout layout;
  final Offset origin;
  final CursorPath cursor;
  final Animation<double> blink;

  @override
  void paint(Canvas canvas, Size size) {
    if (blink.value >= 0.5) return;
    final slot = layout.slot(cursor.sequenceId);
    if (slot == null) return;
    final index = cursor.offset < slot.caretX.length ? cursor.offset : slot.caretX.length - 1;
    final x = origin.dx + slot.caretX[index];
    final top = origin.dy + slot.baseline - slot.fontSize * 0.84;
    final bottom = origin.dy + slot.baseline + slot.fontSize * 0.20;
    canvas.drawLine(
      Offset(x, top),
      Offset(x, bottom),
      Paint()
        ..color = AppColors.caret
        ..strokeWidth = math.max(1.6, slot.fontSize * 0.06)
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_CaretPainter old) =>
      !identical(old.layout, layout) || old.origin != origin || old.cursor != cursor;
}
