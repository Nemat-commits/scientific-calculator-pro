import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/haptics/haptic_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_typography.dart';
import 'data/local_db/app_database.dart';
import 'data/local_db/connection/connection.dart';
import 'data/local_db/draft_state_store.dart';
import 'data/repositories/calculator_repository.dart';
import 'presentation/isolate/evaluation_protocol.dart';
import 'presentation/isolate/evaluator_factory.dart';
import 'presentation/screens/calculator_shell_screen.dart';
import 'presentation/state/calculator_notifier.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppTypography.configure();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: AppColors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.bgObsidian,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  unawaited(_enableHighRefreshRate());

  final preferences = await SharedPreferences.getInstance();
  final executor = openConnection();
  final CalculatorRepository repository = executor == null
      ? InMemoryCalculatorRepository()
      : DriftCalculatorRepository(AppDatabase(executor), preferences);

  // Everything below degrades gracefully: a failure must never keep the
  // calculator from starting.
  var variables = const <String, String>{};
  try {
    variables = await repository.variables().timeout(const Duration(seconds: 3));
  } on Object {
    // start with empty variables
  }
  ExpressionEvaluator evaluator;
  try {
    evaluator = await createEvaluator().timeout(const Duration(seconds: 5));
  } on Object {
    evaluator = InlineEvaluator();
  }
  try {
    await AppTypography.preload().timeout(const Duration(seconds: 3));
  } on Object {
    // the platform fallback font is used until the bundle is ready
  }

  runApp(
    ProviderScope(
      overrides: <Override>[
        repositoryProvider.overrideWithValue(repository),
        draftStoreProvider.overrideWithValue(DraftStateStore(preferences)),
        evaluatorProvider.overrideWithValue(evaluator),
        hapticServiceProvider.overrideWithValue(HapticService()),
        storedVariablesProvider.overrideWithValue(variables),
      ],
      child: const CalculatorApp(),
    ),
  );
}

/// Asks Android for the panel's highest refresh rate (90 / 120 / 144 Hz).
Future<void> _enableHighRefreshRate() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
  try {
    await FlutterDisplayMode.setHighRefreshRate();
  } on Object {
    // Fixed-rate panel or an OEM that blocks mode switching: stay at 60 Hz.
  }
}

/// Root widget.
class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) => WidgetsApp(
        title: 'Scientific Calculator',
        color: AppColors.bgObsidian,
        debugShowCheckedModeBanner: false,
        textStyle: AppTypography.ui(size: 14),
        pageRouteBuilder: <T>(RouteSettings settings, WidgetBuilder builder) => PageRouteBuilder<T>(
          settings: settings,
          pageBuilder: (context, _, __) => builder(context),
        ),
        builder: (context, child) {
          // Keep extreme system font scales from breaking the fixed key grid.
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(textScaler: media.textScaler.clamp(minScaleFactor: 0.85, maxScaleFactor: 1.15)),
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const CalculatorShellScreen(),
      );
}
