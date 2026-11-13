import 'package:flutter/widgets.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';

/// Pill-shaped tab switcher.
///
/// Tabs change by tapping a segment or by swiping horizontally across the
/// bar. Together with the display card this is the only place where a
/// horizontal drag is recognised; the keypads below never switch tabs.
class SegmentedTabBar extends StatelessWidget {
  const SegmentedTabBar({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onSelected,
    this.height = 44,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final double height;

  /// Velocity (logical px/s) that turns a drag into a tab change.
  static const double swipeVelocity = 180;

  /// Maps the end of a horizontal drag onto a neighbouring tab.
  static int? swipeTarget(DragEndDetails details, int current, int count) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < swipeVelocity) return null;
    final next = v < 0 ? current + 1 : current - 1;
    return next < 0 || next >= count ? null : next;
  }

  @override
  Widget build(BuildContext context) {
    final count = labels.length;
    final selected = selectedIndex < 0 ? 0 : (selectedIndex >= count ? count - 1 : selectedIndex);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (details) {
        final target = swipeTarget(details, selected, count);
        if (target != null) onSelected(target);
      },
      child: Container(
        height: height,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.tabTrack,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(color: AppColors.panelBorder),
        ),
        child: Stack(
          children: <Widget>[
            AnimatedAlign(
              alignment: Alignment(count == 1 ? 0 : -1 + 2 * selected / (count - 1), 0),
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              child: FractionallySizedBox(
                widthFactor: 1 / count,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppColors.tabThumb,
                    borderRadius: BorderRadius.circular(height / 2),
                    border: Border.all(color: AppColors.accentSoft),
                  ),
                ),
              ),
            ),
            Row(
              children: <Widget>[
                for (var i = 0; i < count; i++)
                  Expanded(
                    child: Semantics(
                      button: true,
                      selected: i == selected,
                      label: labels[i],
                      onTap: () => onSelected(i),
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onSelected(i),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: AppTypography.ui(
                                  size: 13,
                                  weight: i == selected ? AppWeight.strong : AppWeight.medium,
                                  color: i == selected ? AppColors.textPrimary : AppColors.textSecondary,
                                ),
                                child: Text(labels[i], maxLines: 1, softWrap: false),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
