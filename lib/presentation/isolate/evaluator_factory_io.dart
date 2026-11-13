import 'evaluation_protocol.dart';
import 'evaluator_isolate_pool.dart';

/// Starts the background isolate pool.
Future<ExpressionEvaluator> createEvaluator() => EvaluatorIsolatePool.start();
