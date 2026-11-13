import '../models/calc_error.dart';

/// Tier-1 cooperative cancellation.
///
/// Hot loops (series terms, factorial products, quadrature panels, AST node
/// visits) call [tick] once per iteration. Every [checkInterval] ticks the
/// token looks at three things:
///
///  * an explicit [cancel] request,
///  * the shared generation counter - a newer keystroke bumps it, which makes
///    the evaluation that carries an older [generationId] obsolete,
///  * the wall-clock budget (250 ms for live previews, 1 500 ms for `=`).
///
/// When any of them trips, [CancelledEvaluationError] unwinds the evaluator.
final class CancellationToken {
  CancellationToken({
    this.generationId = 0,
    int Function()? latestGeneration,
    Duration? timeout,
  })  : _latestGeneration = latestGeneration,
        _budgetMicros = timeout?.inMicroseconds;

  /// A token that never cancels.
  static final CancellationToken none = CancellationToken();

  /// Loop iterations between two real checks.
  static const int checkInterval = 64;

  /// Budget of a live-preview evaluation.
  static const Duration previewBudget = Duration(milliseconds: 250);

  /// Budget of an explicit `=` commit.
  static const Duration commitBudget = Duration(milliseconds: 1500);

  /// Generation this evaluation was started for.
  final int generationId;

  final int Function()? _latestGeneration;
  final int? _budgetMicros;
  final Stopwatch _clock = Stopwatch()..start();
  int _ticks = 0;
  bool _cancelRequested = false;

  /// Requests cancellation at the next check.
  void cancel() => _cancelRequested = true;

  /// Time spent since the token was created.
  Duration get elapsed => _clock.elapsed;

  /// Whether the next check would throw.
  bool get isCancelled {
    if (_cancelRequested) return true;
    final latest = _latestGeneration;
    if (latest != null && latest() != generationId) return true;
    final budget = _budgetMicros;
    return budget != null && _clock.elapsedMicroseconds >= budget;
  }

  /// Cheap per-iteration hook; performs the real check every 64th call.
  void tick() {
    if ((++_ticks & (checkInterval - 1)) == 0) throwIfCancelled();
  }

  /// Performs the real check immediately.
  void throwIfCancelled() {
    if (_cancelRequested) {
      throw const CancelledEvaluationError('Evaluation cancelled');
    }
    final latest = _latestGeneration;
    if (latest != null && latest() != generationId) {
      throw const CancelledEvaluationError('Superseded by newer input');
    }
    final budget = _budgetMicros;
    if (budget != null && _clock.elapsedMicroseconds >= budget) {
      throw const CancelledEvaluationError('Evaluation timed out');
    }
  }
}
