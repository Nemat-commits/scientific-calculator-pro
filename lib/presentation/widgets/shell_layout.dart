import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/calculator_notifier.dart';

/// Tells the tabs how the shell arranges them.
class ShellLayout extends InheritedWidget {
  const ShellLayout({super.key, required this.dualPane, required super.child});

  /// Whether the display and the standard keypad sit next to the active tab
  /// (the landscape workbench) instead of taking turns with it.
  final bool dualPane;

  /// Whether the widget at [context] is part of the dual-pane workbench.
  static bool isDualPane(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ShellLayout>()?.dualPane ?? false;

  /// Brings the full display and the main keypad back after a tab changed
  /// the expression. In the dual-pane layout both are on screen already, so
  /// nothing moves.
  static void showKeypad(BuildContext context) {
    if (isDualPane(context)) return;
    ProviderScope.containerOf(context, listen: false).read(calculatorProvider.notifier).setActiveTab(0);
  }

  /// Inserts the number [value] (a formatter string) into the expression and
  /// brings the keypad back.
  static void sendToCalculator(BuildContext context, String value) {
    ProviderScope.containerOf(context, listen: false).read(calculatorProvider.notifier).insertValue(value);
    showKeypad(context);
  }

  @override
  bool updateShouldNotify(ShellLayout oldWidget) => oldWidget.dualPane != dualPane;
}
