import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/models/editor_node.dart';
import '../state/calculator_notifier.dart';
import '../tabs/advanced_lab_tab_view.dart';
import '../tabs/history_vault_tab_view.dart';
import '../tabs/scientific_tab_view.dart';
import '../tabs/standard_tab_view.dart';
import '../tabs/unit_converter_tab_view.dart';
import '../widgets/lab_widgets.dart';
import '../widgets/persistent_display_card.dart';
import '../widgets/segmented_tab_bar.dart';

/// The single screen of the app.
///
/// * **Portrait** (width < 600 dp): display card (35 %), segmented tab bar
///   (7 %), active tab (58 %, kept alive in an `IndexedStack`).
/// * **Landscape** (width ≥ 600 dp): dual-pane workbench - the specialised
///   tabs on the left (52 %), the display card stacked above the standard
///   keypad on the right (48 %).
class CalculatorShellScreen extends ConsumerStatefulWidget {
  const CalculatorShellScreen({super.key});

  /// Width at which the dual-pane layout takes over.
  static const double landscapeBreakpoint = 600;

  static const List<String> tabLabels = <String>['Standard', 'Scientific', 'Lab', 'Convert', 'History'];

  @override
  ConsumerState<CalculatorShellScreen> createState() => _CalculatorShellScreenState();
}

class _CalculatorShellScreenState extends ConsumerState<CalculatorShellScreen> {
  // Global keys keep the state of every tab when the layout flips between
  // portrait and landscape.
  final GlobalKey _standardKey = GlobalKey(debugLabel: 'standard');
  final GlobalKey _scientificKey = GlobalKey(debugLabel: 'scientific');
  final GlobalKey _labKey = GlobalKey(debugLabel: 'lab');
  final GlobalKey _convertKey = GlobalKey(debugLabel: 'convert');
  final GlobalKey _historyKey = GlobalKey(debugLabel: 'history');
  final FocusNode _keyboardFocus = FocusNode(debugLabel: 'calculator keyboard');

  bool _historyOpen = false;

  @override
  void dispose() {
    _keyboardFocus.dispose();
    super.dispose();
  }

  void _selectTab(int index) {
    ref.read(hapticServiceProvider).play(HapticPattern.medium);
    ref.read(calculatorProvider.notifier).setActiveTab(index);
    if (_historyOpen) setState(() => _historyOpen = false);
  }

  void _toggleHistory() => setState(() => _historyOpen = !_historyOpen);

  /// Hardware keyboard support (desktop, web, emulators).
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final notifier = ref.read(calculatorProvider.notifier);
    final key = event.logicalKey;
    // The produced character decides first: on most layouts `+` is Shift+`=`
    // and `*` is Shift+`8`, so the logical key alone would be misleading.
    final character = event.character;
    CalcKey? mapped = character == null || character.length != 1
        ? null
        : switch (character) {
            '=' => const EvaluateKey(),
            '+' => const AtomKey('+', AtomKind.binaryOp),
            '-' => const AtomKey('−', AtomKind.binaryOp),
            '*' => const AtomKey('×', AtomKind.binaryOp),
            '/' => const AtomKey('÷', AtomKind.binaryOp),
            '^' => const TemplateKey(TemplateKind.power),
            '(' => const AtomKey('(', AtomKind.paren),
            ')' => const AtomKey(')', AtomKind.paren),
            '!' => const AtomKey('!', AtomKind.unaryPostfix),
            '%' => const AtomKey('%', AtomKind.unaryPostfix),
            '.' || ',' => const AtomKey('.', AtomKind.digit),
            'x' => const AtomKey('x', AtomKind.variable),
            'e' => const AtomKey('e', AtomKind.constant),
            'p' => const AtomKey('π', AtomKind.constant),
            _ => RegExp(r'^\d$').hasMatch(character) ? AtomKey(character, AtomKind.digit) : null,
          };
    if (mapped == null) {
      if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.numpadEnter) {
        mapped = const EvaluateKey();
      } else if (key == LogicalKeyboardKey.backspace) {
        mapped = const BackspaceKey();
      } else if (key == LogicalKeyboardKey.escape || key == LogicalKeyboardKey.delete) {
        mapped = const ClearKey();
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        mapped = const MoveKey(CursorDirection.left);
      } else if (key == LogicalKeyboardKey.arrowRight) {
        mapped = const MoveKey(CursorDirection.right);
      } else if (key == LogicalKeyboardKey.arrowUp) {
        mapped = const MoveKey(CursorDirection.up);
      } else if (key == LogicalKeyboardKey.arrowDown) {
        mapped = const MoveKey(CursorDirection.down);
      }
    }
    if (mapped == null) return KeyEventResult.ignored;
    notifier.press(mapped);
    return KeyEventResult.handled;
  }

  Widget _card(int tabCount) => PersistentDisplayCard(
        tabCount: tabCount,
        historyOpen: _historyOpen,
        onToggleHistory: _toggleHistory,
      );

  Widget _portrait(int active) => Column(
        children: <Widget>[
          Expanded(flex: 35, child: _card(5)),
          Expanded(
            flex: 7,
            child: Center(
              child: SegmentedTabBar(
                labels: CalculatorShellScreen.tabLabels,
                selectedIndex: active,
                onSelected: _selectTab,
                height: 40,
              ),
            ),
          ),
          Expanded(
            flex: 58,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: IndexedStack(
                    index: active,
                    children: <Widget>[
                      StandardTabView(key: _standardKey),
                      ScientificTabView(key: _scientificKey),
                      AdvancedLabTabView(key: _labKey),
                      UnitConverterTabView(key: _convertKey),
                      HistoryVaultTabView(key: _historyKey),
                    ],
                  ),
                ),
                if (_historyOpen) Positioned.fill(child: _QuickHistory(onClose: _toggleHistory)),
              ],
            ),
          ),
        ],
      );

  Widget _landscape(int active) {
    // The standard keypad is pinned on the right, so the left pane starts at
    // the scientific tab.
    final left = active < 1 ? 1 : active;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Expanded(
          flex: 52,
          child: Column(
            children: <Widget>[
              SegmentedTabBar(
                labels: CalculatorShellScreen.tabLabels.sublist(1),
                selectedIndex: left - 1,
                onSelected: (i) => _selectTab(i + 1),
                height: 38,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: IndexedStack(
                        index: left - 1,
                        children: <Widget>[
                          ScientificTabView(key: _scientificKey),
                          AdvancedLabTabView(key: _labKey),
                          UnitConverterTabView(key: _convertKey),
                          HistoryVaultTabView(key: _historyKey),
                        ],
                      ),
                    ),
                    if (_historyOpen) Positioned.fill(child: _QuickHistory(onClose: _toggleHistory)),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 48,
          child: Column(
            children: <Widget>[
              Expanded(flex: 40, child: _card(5)),
              const SizedBox(height: 8),
              Expanded(flex: 60, child: StandardTabView(key: _standardKey)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(calculatorProvider.select((s) => s.activeTabIndex));
    return ColoredBox(
      color: AppColors.bgObsidian,
      child: SafeArea(
        child: Focus(
          focusNode: _keyboardFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth + 24 < CalculatorShellScreen.landscapeBreakpoint
                  ? _portrait(active)
                  : _landscape(active),
            ),
          ),
        ),
      ),
    );
  }
}

/// The pull-down tape: the most recent calculations on top of the keypad.
class _QuickHistory extends ConsumerWidget {
  const _QuickHistory({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(historyProvider.select((h) => h.entries));
    final recent = entries.length > 30 ? entries.sublist(0, 30) : entries;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      child: ColoredBox(
        color: AppColors.scrim,
        child: Align(
          alignment: Alignment.topCenter,
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {}, // taps inside the panel must not close it
              child: Panel(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        const Expanded(child: SectionLabel('Recent calculations')),
                        SmallButton('Close', onTap: onClose),
                      ],
                    ),
                    Expanded(
                      child: recent.isEmpty
                          ? Center(
                              child: Text(
                                'Nothing here yet - press = to commit a result.',
                                textAlign: TextAlign.center,
                                style: AppTypography.ui(size: 13, color: AppColors.textFaint),
                              ),
                            )
                          : ListView.builder(
                              itemCount: recent.length,
                              itemBuilder: (context, i) => HistoryTile(entry: recent[i], dense: true, onUsed: onClose),
                            ),
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
