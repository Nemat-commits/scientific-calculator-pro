import 'evaluation_protocol.dart';

/// No isolates on this platform: evaluate in place.
Future<ExpressionEvaluator> createEvaluator() async => InlineEvaluator();

/// One line for the start-up log: which cancellation tiers are available.
String describeEvaluator(ExpressionEvaluator evaluator) => 'in place (no worker isolate)';
