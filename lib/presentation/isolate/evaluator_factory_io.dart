import 'evaluator_isolate_pool.dart';

/// Starts the background isolate pool.
Future<ExpressionEvaluator> createEvaluator() => EvaluatorIsolatePool.start();

/// One line for the start-up log: which cancellation tiers are available.
String describeEvaluator(ExpressionEvaluator evaluator) {
  if (evaluator is! EvaluatorIsolatePool) return 'in place (no worker isolate)';
  return evaluator.hasSharedGeneration
      ? 'worker isolates, cooperative cancellation by shared generation counter, watchdog'
      : 'worker isolates, cooperative cancellation by time budget, watchdog';
}
