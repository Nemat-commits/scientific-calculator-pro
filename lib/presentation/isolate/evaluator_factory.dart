// Picks the evaluator for the platform: a worker-isolate pool wherever
// isolates and native memory exist, an in-place evaluator on the web.
export 'evaluator_factory_web.dart' if (dart.library.io) 'evaluator_factory_io.dart';
