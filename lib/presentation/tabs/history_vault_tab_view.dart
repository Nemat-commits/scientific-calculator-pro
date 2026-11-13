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
import '../widgets/lab_widgets.dart';
import '../widgets/result_text.dart';

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

/// One history entry: tap to recall the expression, `Ans` to insert the
/// result, `×` to delete.
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
      },
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
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          entry.expressionText,
                          maxLines: 1,
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
                    child: ResultText(entry.resultPrimary, fontSize: dense ? 16 : 19, prefix: '='),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            SmallButton(
              'Ans',
              onTap: () {
                // "m × 10^n" becomes the literal mEn; compound results (complex
                // numbers) are wrapped so they stay one operand.
                final literal = entry.resultPrimary.replaceAll(' × 10^', 'E');
                notifier.pasteText(literal.contains(' ') ? '($literal)' : literal);
                onUsed?.call();
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
                    child: Text(name, style: AppTypography.mono(size: 15, weight: AppWeight.medium, color: AppColors.mathVariable)),
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
