import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/compiler/tree_to_token_lowerer.dart';
import '../../domain/editor/cursor_path.dart';
import '../state/calculator_notifier.dart';
import '../state/calculator_ui_state.dart';
import 'app_icons.dart';
import 'math_print_canvas.dart';
import 'result_text.dart';
import 'segmented_tab_bar.dart';

/// The display that stays on screen in every tab: status badges, the 2D
/// expression, the live preview / result row and the pull-down handle of the
/// quick history.
///
/// A horizontal swipe across the card switches tabs (the keypads never do).
class PersistentDisplayCard extends ConsumerStatefulWidget {
  const PersistentDisplayCard({
    super.key,
    required this.tabCount,
    this.onToggleHistory,
    this.historyOpen = false,
  });

  /// Number of tabs a swipe can cycle through.
  final int tabCount;

  /// Tap / pull on the handle at the bottom edge.
  final VoidCallback? onToggleHistory;
  final bool historyOpen;

  @override
  ConsumerState<PersistentDisplayCard> createState() => _PersistentDisplayCardState();
}

class _PersistentDisplayCardState extends ConsumerState<PersistentDisplayCard> {
  /// Result row shows the alternative read-out (fraction ⇄ decimal).
  bool _swapped = false;
  String? _notice;
  Timer? _noticeTimer;

  @override
  void dispose() {
    _noticeTimer?.cancel();
    super.dispose();
  }

  void _flash(String message) {
    _noticeTimer?.cancel();
    setState(() => _notice = message);
    _noticeTimer = Timer(const Duration(milliseconds: 1300), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  Future<void> _copy(CalculatorUiState state) async {
    final text = state.inputPhase == InputPhase.committedResult && state.livePreviewPrimary.isNotEmpty
        ? state.livePreviewPrimary
        : TreeToTokenLowerer.toDisplayText(state.rootSequence);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _flash('Copied');
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.trim().isEmpty) return;
    ref.read(calculatorProvider.notifier).pasteText(text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(calculatorProvider);
    final notifier = ref.read(calculatorProvider.notifier);
    ref.listen<String>(calculatorProvider.select((s) => s.livePreviewPrimary), (_, __) => _swapped = false);

    final committed = state.inputPhase == InputPhase.committedResult;
    final failed = state.inputPhase == InputPhase.errorLocked;
    final secondary = state.livePreviewSecondary;
    final swap = _swapped && secondary != null;
    final primaryText = swap ? secondary : state.livePreviewPrimary;
    final secondaryText = swap ? state.livePreviewPrimary : secondary;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final target = SegmentedTabBar.swipeTarget(details, state.activeTabIndex, widget.tabCount);
        if (target != null) notifier.setActiveTab(target);
      },
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.cardSurface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppColors.cardBorder),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 200;
            final resultSize = compact ? 26.0 : 36.0;
            final expressionSize = compact ? 24.0 : 32.0;
            return Padding(
              padding: EdgeInsets.fromLTRB(16, compact ? 8 : 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _StatusRow(state: state, notice: _notice, onCopy: () => _copy(state), onPaste: _paste),
                  SizedBox(height: compact ? 2 : 6),
                  Expanded(
                    // The 2D rendering is a painting; screen readers get the
                    // expression as linear text.
                    child: Semantics(
                      container: true,
                      label: 'Expression: ${state.rootSequence.isEmpty ? 'empty' : TreeToTokenLowerer.toDisplayText(state.rootSequence)}',
                      child: MathPrintCanvas(
                        root: state.rootSequence,
                        cursor: CursorPath.fromRecords(state.cursorPath),
                        fontSize: expressionSize,
                        showCaret: state.inputPhase == InputPhase.editing,
                        onTapPosition: notifier.setCursor,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: resultSize * 1.3,
                    child: failed
                        ? Semantics(
                            container: true,
                            liveRegion: true,
                            label: 'Error: ${state.errorMessage ?? 'Error'}',
                            excludeSemantics: true,
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  state.errorMessage ?? 'Error',
                                  maxLines: 1,
                                  style: AppTypography.ui(size: compact ? 15 : 18, weight: AppWeight.medium, color: AppColors.error),
                                ),
                              ),
                            ),
                          )
                        : GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: secondary == null ? null : () => setState(() => _swapped = !_swapped),
                            child: primaryText.isEmpty
                                ? const SizedBox.expand()
                                : Semantics(
                                    container: true,
                                    liveRegion: committed,
                                    label: '${committed ? 'Result' : 'Preview'}: $primaryText',
                                    excludeSemantics: true,
                                    child: ResultText(
                                      primaryText,
                                      fontSize: committed ? resultSize : resultSize * 0.72,
                                      color: committed ? AppColors.textPrimary : AppColors.textMuted,
                                      weight: committed ? AppWeight.medium : AppWeight.regular,
                                      prefix: '=',
                                    ),
                                  ),
                          ),
                  ),
                  if (!compact)
                    SizedBox(
                      height: 18,
                      child: secondaryText == null || secondaryText.isEmpty || failed
                          ? null
                          : ResultText(
                              secondaryText,
                              fontSize: 13,
                              color: AppColors.textMuted,
                              weight: AppWeight.regular,
                              prefix: committed ? '=' : null,
                            ),
                    ),
                  _HistoryHandle(open: widget.historyOpen, onToggle: widget.onToggleHistory, compact: compact),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _StatusRow extends ConsumerWidget {
  const _StatusRow({required this.state, required this.notice, required this.onCopy, required this.onPaste});

  final CalculatorUiState state;
  final String? notice;
  final VoidCallback onCopy;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    return SizedBox(
      height: 26,
      child: Row(
        children: <Widget>[
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  StatusBadge(state.angleUnit.label, highlighted: true, onTap: notifier.cycleAngleUnit, semanticLabel: 'Angle unit'),
                  StatusBadge(state.isComplexEnabled ? 'CPLX' : 'REAL', highlighted: state.isComplexEnabled, onTap: notifier.toggleComplex),
                  StatusBadge(state.juxtapositionMode.label, onTap: notifier.toggleJuxtaposition, semanticLabel: 'Implied multiplication'),
                  if (state.isInverseActive) const StatusBadge('INV', highlighted: true),
                  if (state.isHyperbolicActive) const StatusBadge('HYP', highlighted: true),
                  if (state.hasMemory) const StatusBadge('M', highlighted: true),
                  if (state.inputPhase == InputPhase.errorLocked) const StatusBadge('ERROR', danger: true),
                  if (state.isEvaluatingHeavy) const _BusyDot(),
                  if (notice != null) StatusBadge(notice!, highlighted: true),
                ],
              ),
            ),
          ),
          _IconAction(AppIconGlyph.undo, 'Undo', state.canUndo ? notifier.undo : null),
          _IconAction(AppIconGlyph.redo, 'Redo', state.canRedo ? notifier.redo : null),
          _IconAction(AppIconGlyph.copy, 'Copy', onCopy),
          _IconAction(AppIconGlyph.paste, 'Paste', onPaste),
        ],
      ),
    );
  }
}

/// A small pill in the status row; tappable when [onTap] is set.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.highlighted = false, this.danger = false, this.onTap, this.semanticLabel});

  final String label;
  final bool highlighted;
  final bool danger;
  final VoidCallback? onTap;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final color = danger ? AppColors.error : (highlighted ? AppColors.accent : AppColors.textMuted);
    final pill = Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: danger ? AppColors.errorSoft : (highlighted ? AppColors.accentFaint : AppColors.transparent),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: danger ? AppColors.errorSoft : (highlighted ? AppColors.accentSoft : AppColors.cardBorder)),
      ),
      child: Text(label, maxLines: 1, style: AppTypography.ui(size: 10.5, weight: AppWeight.strong, color: color, letterSpacing: 0.4)),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      label: semanticLabel == null ? label : '$semanticLabel: $label',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: onTap, child: pill),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction(this.glyph, this.label, this.onTap);

  final AppIconGlyph glyph;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: AppIcon(glyph, size: 17, color: onTap == null ? AppColors.textFaint : AppColors.textSecondary),
          ),
        ),
      );
}

/// Pulses while a calculation runs for longer than 50 ms.
class _BusyDot extends StatefulWidget {
  const _BusyDot();

  @override
  State<_BusyDot> createState() => _BusyDotState();
}

class _BusyDotState extends State<_BusyDot> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: FadeTransition(
          opacity: Tween<double>(begin: 0.25, end: 1).animate(_pulse),
          child: Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(color: AppColors.warning, shape: BoxShape.circle),
          ),
        ),
      );
}

class _HistoryHandle extends StatelessWidget {
  const _HistoryHandle({required this.open, required this.onToggle, required this.compact});

  final bool open;
  final VoidCallback? onToggle;
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: open ? 'Close quick history' : 'Open quick history',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          onVerticalDragEnd: onToggle == null
              ? null
              : (details) {
                  final v = details.primaryVelocity ?? 0;
                  if ((v > 120 && !open) || (v < -120 && open)) onToggle!();
                },
          child: SizedBox(
            height: compact ? 14 : 20,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: open ? 56 : 40,
                height: 4,
                decoration: BoxDecoration(
                  color: open ? AppColors.accent : AppColors.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      );
}
