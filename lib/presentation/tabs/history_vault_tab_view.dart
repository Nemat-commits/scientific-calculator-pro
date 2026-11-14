import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../data/repositories/calculator_repository.dart';
import '../../domain/evaluator/number_formatter.dart';
import '../../domain/models/calc_value_codec.dart';
import '../state/calculator_notifier.dart';
import '../widgets/app_icons.dart';
import '../widgets/app_text_field.dart';
import '../widgets/app_toast.dart';
import '../widgets/expression_text.dart';
import '../widgets/lab_widgets.dart';
import '../widgets/result_text.dart';
import '../widgets/shell_layout.dart';

/// Tab 5: the searchable history tape and the variable slot editor.
class HistoryVaultTabView extends ConsumerStatefulWidget {
  const HistoryVaultTabView({super.key});

  /// Variable slots offered by the editor.
  static const List<String> slots = <String>['Ans', 'M', 'A', 'B', 'C', 'D', 'E', 'F', 'x', 'y'];

  @override
  ConsumerState<HistoryVaultTabView> createState() => _HistoryVaultTabViewState();
}

class _HistoryVaultTabViewState extends ConsumerState<HistoryVaultTabView> {
  int _page = 0;
  bool _confirmClear = false;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ChoiceChips(
                  labels: const <String>['Tape', 'Variables'],
                  selected: _page,
                  height: 32,
                  onSelected: (i) => setState(() {
                    _page = i;
                    _confirmClear = false;
                  }),
                ),
              ),
              if (_page == 0)
                SmallButton(
                  _confirmClear ? 'Really clear?' : 'Clear all',
                  danger: true,
                  onTap: ref.watch(historyProvider.select((h) => h.entries.isEmpty))
                      ? null
                      : () {
                          if (_confirmClear) ref.read(historyProvider.notifier).clear();
                          setState(() => _confirmClear = !_confirmClear);
                        },
                ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _page,
              children: const <Widget>[_TapePage(), _VariablesPage()],
            ),
          ),
        ],
      );
}

String _timeLabel(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  final now = DateTime.now();
  final sameDay = now.year == t.year && now.month == t.month && now.day == t.day;
  final clock = '${two(t.hour)}:${two(t.minute)}';
  return sameDay ? clock : '${t.year}-${two(t.month)}-${two(t.day)} $clock';
}

class _TapePage extends ConsumerWidget {
  const _TapePage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(historyProvider);
    final keyboard = MediaQuery.viewInsetsOf(context).bottom;
    return Column(
      children: <Widget>[
        AppTextField(
          hint: 'Search expressions and results',
          leading: AppIconGlyph.search,
          onChanged: (q) => ref.read(historyProvider.notifier).setQuery(q),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: Panel(
            padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
            child: history.entries.isEmpty
                ? Center(
                    child: Text(
                      history.query.isEmpty ? 'Calculations you commit with = appear here.' : 'No match.',
                      textAlign: TextAlign.center,
                      style: AppTypography.ui(size: 13, color: AppColors.textFaint),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.only(bottom: keyboard > 0 ? keyboard : 4),
                    itemCount: history.entries.length,
                    itemBuilder: (context, i) => HistoryTile(entry: history.entries[i]),
                  ),
          ),
        ),
      ],
    );
  }
}

/// One history entry: a tap recalls the expression for editing, `Ans` inserts
/// the result at the caret, a long press opens the entry in full
/// ([HistoryDetailSheet]) and `×` deletes it. Recalling and inserting bring
/// the keypad back.
class HistoryTile extends ConsumerWidget {
  const HistoryTile({super.key, required this.entry, this.onUsed, this.dense = false});

  final HistoryEntry entry;

  /// Called after the entry was recalled or inserted.
  final VoidCallback? onUsed;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(calculatorProvider.notifier);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        notifier.recallExpression(entry.expressionJson);
        onUsed?.call();
        ShellLayout.showKeypad(context);
      },
      onLongPress: () => HistoryDetailSheet.show(context, entry),
      child: Container(
        padding: EdgeInsets.symmetric(vertical: dense ? 6 : 8),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.panelBorder))),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: ExpressionText(
                          entry.expressionText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.mono(size: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                      Text(
                        '${entry.angleUnit.toUpperCase()} · ${_timeLabel(entry.createdAt)}',
                        style: AppTypography.ui(size: 10, color: AppColors.textFaint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  SizedBox(
                    height: dense ? 22 : 26,
                    child: ResultText(
                      ResultText.lead(entry.resultPrimary, entry.resultSecondary),
                      fontSize: dense ? 16 : 19,
                      prefix: '=',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(
              'Ans',
              onTap: () {
                notifier.insertValue(entry.resultPrimary);
                onUsed?.call();
                ShellLayout.showKeypad(context);
              },
            ),
            if (!dense)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => ref.read(historyProvider.notifier).delete(entry.id),
                child: const Padding(
                  padding: EdgeInsets.only(left: 8, top: 6, bottom: 6),
                  child: AppIcon(AppIconGlyph.close, size: 15, color: AppColors.textMuted),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A history entry in full: the whole expression, every digit of the result
/// and buttons that copy either one. Opened by a long press on a tile.
class HistoryDetailSheet extends ConsumerWidget {
  const HistoryDetailSheet({super.key, required this.entry});

  final HistoryEntry entry;

  /// Slides the sheet up from the bottom edge.
  static Future<void> show(BuildContext context, HistoryEntry entry) => Navigator.of(context).push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          barrierDismissible: true,
          barrierColor: AppColors.scrim,
          barrierLabel: 'Close',
          transitionDuration: const Duration(milliseconds: 180),
          reverseTransitionDuration: const Duration(milliseconds: 140),
          pageBuilder: (context, _, __) => HistoryDetailSheet(entry: entry),
          transitionsBuilder: (context, animation, _, child) => FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: Tween<Offset>(begin: const Offset(0, 0.12), end: Offset.zero)
                  .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
              child: child,
            ),
          ),
        ),
      );

  Future<void> _copy(BuildContext context, WidgetRef ref, String text, String confirmation) async {
    final navigator = Navigator.of(context);
    final toast = ref.read(toastProvider.notifier);
    await Clipboard.setData(ClipboardData(text: text));
    navigator.pop();
    toast.show(confirmation);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secondary = entry.resultSecondary;
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: 560, maxHeight: MediaQuery.sizeOf(context).height * 0.72),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.cardSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.cardBorder),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(child: SectionLabel('Calculation')),
                        Text(
                          '${entry.angleUnit.toUpperCase()} · ${_timeLabel(entry.createdAt)}',
                          style: AppTypography.ui(size: 11, color: AppColors.textFaint),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            ExpressionText(
                              entry.expressionText,
                              style: AppTypography.mono(size: 14, color: AppColors.textSecondary, height: 1.35),
                            ),
                            const SizedBox(height: 10),
                            ResultText(entry.resultPrimary, fontSize: 18, prefix: '=', wrap: true),
                            if (secondary != null && secondary.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 4),
                              ResultText(
                                secondary,
                                fontSize: 13,
                                color: AppColors.textMuted,
                                weight: AppWeight.regular,
                                prefix: '=',
                                wrap: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: <Widget>[
                        SmallButton(
                          'Copy expression',
                          onTap: () => _copy(context, ref, entry.expressionText, 'Expression copied'),
                        ),
                        SmallButton(
                          'Copy result',
                          primary: true,
                          onTap: () => _copy(context, ref, entry.resultPrimary, 'Result copied'),
                        ),
                        SmallButton('Close', onTap: () => Navigator.of(context).pop()),
                      ],
                    ),
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

class _VariablesPage extends ConsumerWidget {
  const _VariablesPage();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final variables = ref.watch(calculatorProvider.select((s) => s.variables));
    final notifier = ref.read(calculatorProvider.notifier);
    return Panel(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      child: ListView(
        children: <Widget>[
          for (final name in HistoryVaultTabView.slots)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 7),
              decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppColors.panelBorder))),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 40,
                    child: Text(name,
                        style: AppTypography.mono(size: 15, weight: AppWeight.medium, color: AppColors.mathVariable)),
                  ),
                  Expanded(
                    child: SizedBox(
                      height: 22,
                      child: ResultText(
                        NumberFormatter.formatValue(CalcValueCodec.decode(variables[name] ?? '0'), prec: 16),
                        fontSize: 15,
                        weight: AppWeight.regular,
                        alignment: Alignment.centerLeft,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SmallButton('Insert', onTap: () => notifier.insertVariable(name)),
                  if (name != 'Ans') ...<Widget>[
                    const SizedBox(width: 6),
                    SmallButton('Ans →', onTap: () => notifier.storeAnswerIn(name)),
                    const SizedBox(width: 6),
                    SmallButton('0', danger: true, onTap: () => notifier.clearVariable(name)),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}
