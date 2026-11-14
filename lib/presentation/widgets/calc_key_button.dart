import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../state/calculator_notifier.dart';

/// Colour role of a key.
enum KeyTone {
  /// `0`-`9`, `.`
  digit,

  /// Scientific / template keys.
  function,

  /// `+ − × ÷`
  operator,

  /// `AC`, `⌫`
  danger,

  /// `=`
  equals,

  /// A toggle that is currently on (HYP).
  active,

  /// The shift key `INV`.
  shift,

  /// The shift key while it is on.
  shiftActive,
}

/// A calculator key: scales to 0.94× within 60 ms while pressed and fires a
/// haptic pulse on touch-down.
///
/// Only tap recognisers are attached - keys never take part in horizontal
/// drags, so a swipe that starts on the keypad cannot switch tabs.
class CalcKeyButton extends ConsumerStatefulWidget {
  const CalcKeyButton({
    super.key,
    required this.onPressed,
    this.label,
    this.child,
    this.tone = KeyTone.digit,
    this.fontSize = 22,
    this.haptic = HapticPattern.light,
    this.repeats = false,
    this.onLongPress,
    this.semanticLabel,
    this.radius = 16,
    this.corner,
    this.emphasised = false,
  }) : assert(label != null || child != null, 'A key needs a label or a child');

  final VoidCallback? onPressed;

  /// Text legend (drawn in JetBrains Mono).
  final String? label;

  /// Custom legend; overrides [label].
  final Widget? child;
  final KeyTone tone;
  final double fontSize;
  final HapticPattern haptic;

  /// Auto-repeat while held (cursor keys, backspace).
  final bool repeats;
  final VoidCallback? onLongPress;
  final String? semanticLabel;
  final double radius;

  /// Small secondary legend in the top right corner (what `INV` turns the
  /// key into).
  final Widget? corner;

  /// Draws attention to the key: accent outline and a brighter legend.
  final bool emphasised;

  /// Legend colour of a tone.
  static Color foregroundOf(KeyTone tone) => switch (tone) {
        KeyTone.digit => AppColors.keyDigitText,
        KeyTone.function => AppColors.keyFuncText,
        KeyTone.operator => AppColors.keyOperatorText,
        KeyTone.danger => AppColors.keyDangerText,
        KeyTone.equals => AppColors.keyEqualsText,
        KeyTone.active => AppColors.keyActiveText,
        KeyTone.shift => AppColors.keyShiftText,
        KeyTone.shiftActive => AppColors.keyShiftActiveText,
      };

  @override
  ConsumerState<CalcKeyButton> createState() => _CalcKeyButtonState();
}

class _CalcKeyButtonState extends ConsumerState<CalcKeyButton> {
  static const Duration _pressDuration = Duration(milliseconds: 60);
  static const Duration _repeatDelay = Duration(milliseconds: 380);
  static const Duration _repeatInterval = Duration(milliseconds: 70);

  bool _down = false;
  Timer? _repeat;
  bool _repeated = false;

  @override
  void dispose() {
    _repeat?.cancel();
    super.dispose();
  }

  void _press(TapDownDetails details) {
    if (widget.onPressed == null) return;
    setState(() => _down = true);
    ref.read(hapticServiceProvider).play(widget.haptic);
    _repeated = false;
    if (widget.repeats) {
      _repeat?.cancel();
      _repeat = Timer(_repeatDelay, () {
        _repeat = Timer.periodic(_repeatInterval, (_) {
          _repeated = true;
          widget.onPressed?.call();
        });
      });
    }
  }

  void _release() {
    _repeat?.cancel();
    _repeat = null;
    if (_down && mounted) setState(() => _down = false);
  }

  Color get _background => switch (widget.tone) {
        KeyTone.digit => AppColors.keyDigit,
        KeyTone.function => AppColors.keyFunc,
        KeyTone.operator => AppColors.keyOperator,
        KeyTone.danger => AppColors.keyDanger,
        KeyTone.equals => AppColors.keyEqualsStart,
        KeyTone.active => AppColors.keyActive,
        KeyTone.shift => AppColors.keyShift,
        KeyTone.shiftActive => AppColors.keyShiftActive,
      };

  Color get _edge {
    if (widget.emphasised) return AppColors.accent;
    return switch (widget.tone) {
      KeyTone.shift => AppColors.keyShiftEdge,
      KeyTone.shiftActive => AppColors.keyShiftActive,
      _ => AppColors.keyEdge,
    };
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = widget.emphasised ? AppColors.keyEmphasisText : CalcKeyButton.foregroundOf(widget.tone);
    final corner = widget.corner;
    final legend = widget.child ??
        Text(
          AppTypography.signs(widget.label!),
          maxLines: 1,
          softWrap: false,
          textAlign: TextAlign.center,
          style: AppTypography.mono(
            size: widget.fontSize,
            weight: widget.tone == KeyTone.equals || widget.tone == KeyTone.shift || widget.tone == KeyTone.shiftActive
                ? AppWeight.strong
                : AppWeight.medium,
            color: foreground,
            height: 1.1,
          ),
        );
    final radius = BorderRadius.circular(widget.radius);
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _press,
        onTapUp: (_) {
          final fire = !_repeated;
          _release();
          if (fire) widget.onPressed?.call();
        },
        onTapCancel: _release,
        onLongPress: widget.onLongPress == null || widget.repeats
            ? null
            : () {
                _release();
                widget.onLongPress!();
              },
        // The semantics node above already names the key.
        child: ExcludeSemantics(
          child: AnimatedScale(
            scale: _down ? 0.94 : 1,
            duration: _pressDuration,
            curve: Curves.easeOut,
            child: AnimatedOpacity(
              opacity: enabled ? 1 : 0.28,
              duration: _pressDuration,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: _background,
                  gradient: widget.tone == KeyTone.equals
                      ? const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[AppColors.keyEqualsStart, AppColors.keyEqualsEnd],
                        )
                      : null,
                  borderRadius: radius,
                  border: Border.all(color: _edge),
                ),
                child: corner == null
                    ? _ScaledLegend(child: legend)
                    : Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          // The main legend sits a little lower to stay clear
                          // of the corner.
                          Padding(padding: const EdgeInsets.only(top: 4), child: _ScaledLegend(child: legend)),
                          Positioned(top: 5, right: 7, child: corner),
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

/// Centres a legend on its key. Legends are drawn for a phone-sized key; on
/// the larger keys of a tablet they grow with the key (up to 1.5×) instead of
/// floating in empty space, and on a cramped key they shrink to fit.
class _ScaledLegend extends StatelessWidget {
  const _ScaledLegend({required this.child});

  final Widget child;

  /// Key size the legends are designed for.
  static const Size _reference = Size(72, 58);
  static const double _maxScale = 1.5;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final fitted = Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(fit: BoxFit.scaleDown, child: child),
            ),
          );
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return fitted;
          final scale = math
              .min(constraints.maxWidth / _reference.width, constraints.maxHeight / _reference.height)
              .clamp(1.0, _maxScale);
          if (scale <= 1.02) return fitted;
          // Lay the legend out in a proportionally smaller box and magnify
          // that box, so the fit-to-key guard above keeps working.
          return Center(
            child: SizedBox(
              width: constraints.maxWidth / scale,
              height: constraints.maxHeight / scale,
              child: Transform.scale(scale: scale, child: fitted),
            ),
          );
        },
      );
}

/// Lays keys out in equally sized cells. Purely tap driven - no drag
/// recognisers are ever attached to the grid.
class KeyGrid extends StatelessWidget {
  const KeyGrid({super.key, required this.rows, this.gap = 8});

  /// The keys, row by row. Rows may differ in length.
  final List<List<Widget>> rows;
  final double gap;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          for (var r = 0; r < rows.length; r++) ...<Widget>[
            if (r > 0) SizedBox(height: gap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var c = 0; c < rows[r].length; c++) ...<Widget>[
                    if (c > 0) SizedBox(width: gap),
                    Expanded(child: rows[r][c]),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
}
