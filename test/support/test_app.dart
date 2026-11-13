import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:modern_scientific_calculator/core/theme/app_typography.dart';
import 'package:modern_scientific_calculator/main.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_notifier.dart';
import 'package:modern_scientific_calculator/presentation/state/calculator_ui_state.dart';

/// Registers the bundled font files under their plain family names so widget
/// tests lay text out with the real metrics (and never touch google_fonts).
Future<void> loadAppFonts() async {
  AppTypography.useGoogleFonts = false;
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final file in files) {
      final bytes = File('assets/google_fonts/$file').readAsBytesSync();
      loader.addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    }
    await loader.load();
  }

  await family(AppTypography.monoFamily, const <String>[
    'JetBrainsMono-Regular.ttf',
    'JetBrainsMono-Medium.ttf',
    'JetBrainsMono-Bold.ttf',
  ]);
  await family(AppTypography.uiFamily, const <String>[
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
  ]);
}

/// Pumps the whole app at [size] (logical pixels) and returns its container.
Future<ProviderContainer> pumpCalculator(
  WidgetTester tester, {
  Size size = const Size(412, 915),
  double pixelRatio = 1,
  Key? boundaryKey,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = size * pixelRatio;
  addTearDown(tester.view.reset);
  final container = ProviderContainer();
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundaryKey, child: const CalculatorApp()),
    ),
  );
  await settle(tester);
  return container;
}

/// Lets the in-place evaluator, timers and short animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// The current calculator state.
CalculatorUiState stateOf(ProviderContainer container) => container.read(calculatorProvider);
