import '../../domain/evaluator/cancellation_token.dart';
import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import '../../domain/models/calc_value_codec.dart';
import '../../domain/models/editor_node.dart';
import '../../domain/models/math_context.dart';

/// One expression to evaluate.
final class EvaluationRequest {
  const EvaluationRequest({
    required this.root,
    required this.context,
    required this.variables,
    this.isCommit = false,
    this.debugBusyLoop,
  });

  /// The editor tree.
  final EditorSequence root;
  final MathContext context;

  /// Encoded variables (`Ans`, `M`, `A`..).
  final Map<String, String> variables;

  /// `true` for an explicit `=` (1.5 s budget), `false` for a live preview
  /// (250 ms budget).
  final bool isCommit;

  /// Test hook: makes the worker spin for this long without ever reaching a
  /// cooperative check, like a single runaway native operation would.
  final Duration? debugBusyLoop;

  Map<String, Object?> toMessage(int id, int generation) => <String, Object?>{
        'id': id,
        'generation': generation,
        'commit': isCommit,
        'root': root.toJson(),
        'context': context.toJson(),
        'variables': variables,
        if (debugBusyLoop != null) 'busy': debugBusyLoop!.inMilliseconds,
      };
}

/// Result of an [EvaluationRequest].
final class EvaluationOutcome {
  const EvaluationOutcome.success({
    required String this.primary,
    required String this.valueEncoded,
    required String this.expression,
    this.secondary,
  }) : error = null;

  const EvaluationOutcome.failure(CalcError this.error)
      : primary = null,
        secondary = null,
        valueEncoded = null,
        expression = null;

  final String? primary;
  final String? secondary;

  /// [CalcValueCodec] form of the value (for `Ans`).
  final String? valueEncoded;

  /// Linear text of the expression.
  final String? expression;
  final CalcError? error;

  bool get isSuccess => error == null;

  /// The request was superseded or ran out of time.
  bool get isCancelled => error is CancelledEvaluationError;

  static EvaluationOutcome fromMessage(Map<String, Object?> message) {
    if (message['ok'] == true) {
      return EvaluationOutcome.success(
        primary: message['primary']! as String,
        secondary: message['secondary'] as String?,
        valueEncoded: message['value']! as String,
        expression: message['expression']! as String,
      );
    }
    return EvaluationOutcome.failure(
      CalcError.fromJson((message['error']! as Map<Object?, Object?>).cast<String, Object?>()),
    );
  }
}

/// Something that can evaluate expressions off the UI's critical path.
abstract interface class ExpressionEvaluator {
  /// Evaluates [request]. A newer call supersedes the ones still in flight;
  /// those complete with a [CancelledEvaluationError] outcome.
  Future<EvaluationOutcome> evaluate(EvaluationRequest request);

  /// Releases the resources of the evaluator.
  void dispose();
}

/// The code that runs for every request - inside the worker isolate, or in
/// place for [InlineEvaluator].
abstract final class EvaluationWorker {
  /// Evaluates one request message and returns the reply message.
  static Map<String, Object?> handle(Map<String, Object?> message, {int Function()? latestGeneration}) {
    final id = message['id'];
    try {
      final busy = message['busy'] as int?;
      if (busy != null) {
        final clock = Stopwatch()..start();
        while (clock.elapsedMilliseconds < busy) {
          // deliberately uninterruptible
        }
      }
      final commit = message['commit'] == true;
      final token = CancellationToken(
        generationId: message['generation'] as int? ?? 0,
        latestGeneration: latestGeneration,
        timeout: commit ? CancellationToken.commitBudget : CancellationToken.previewBudget,
      );
      final result = MathEngine.evaluateSequence(
        EditorSequence.fromJson((message['root']! as Map<Object?, Object?>).cast<String, Object?>()),
        context: MathContext.fromJson((message['context']! as Map<Object?, Object?>).cast<String, Object?>()),
        variables: CalcValueCodec.decodeAll((message['variables']! as Map<Object?, Object?>).cast<String, String>()),
        token: token,
      );
      return <String, Object?>{
        'id': id,
        'ok': true,
        'primary': result.primary,
        'secondary': result.secondary,
        'value': CalcValueCodec.encode(result.value),
        'expression': result.expression,
      };
    } on CalcError catch (e) {
      return <String, Object?>{'id': id, 'ok': false, 'error': e.toJson()};
    } on StackOverflowError {
      return <String, Object?>{
        'id': id,
        'ok': false,
        'error': const SyntaxError('The expression is nested too deeply').toJson(),
      };
    } on Object catch (e) {
      return <String, Object?>{
        'id': id,
        'ok': false,
        'error': DomainError('Cannot evaluate ($e)').toJson(),
      };
    }
  }
}

/// Evaluates on the calling isolate (web, tests, and as a last resort when no
/// worker isolate can be spawned). Only the cooperative time budget applies.
final class InlineEvaluator implements ExpressionEvaluator {
  int _generation = 0;
  int _nextId = 0;

  @override
  Future<EvaluationOutcome> evaluate(EvaluationRequest request) {
    final generation = ++_generation;
    final message = request.toMessage(++_nextId, generation);
    return Future<EvaluationOutcome>(() {
      if (generation != _generation) {
        return const EvaluationOutcome.failure(CancelledEvaluationError('Superseded by newer input'));
      }
      return EvaluationOutcome.fromMessage(EvaluationWorker.handle(message, latestGeneration: () => _generation));
    });
  }

  @override
  void dispose() {}
}
