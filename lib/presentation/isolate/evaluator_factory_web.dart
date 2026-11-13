import 'evaluation_protocol.dart';

/// No isolates on this platform: evaluate in place.
Future<ExpressionEvaluator> createEvaluator() async => InlineEvaluator();
