import 'dart:async';
import 'dart:isolate';

import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import 'evaluation_protocol.dart';
import 'shared_generation.dart';

export 'evaluation_protocol.dart';

/// Background evaluator with a two-tier safety net.
///
/// * **Tier 1 - cooperative token.** Every request carries a generation id.
///   The latest id also lives in [SharedGeneration], a word of native memory
///   the worker can read while it is busy; all series, factorial and
///   quadrature loops compare it (and their 250 ms / 1 500 ms time budget)
///   every 64 iterations and unwind with a `CancelledEvaluationError`.
/// * **Tier 2 - preemptive kill.** If a request is still unanswered when the
///   watchdog fires (a single native operation that never reaches a check),
///   the worker is killed with `Isolate.immediate` and a warm spare takes
///   over at once, so the UI never freezes.
final class EvaluatorIsolatePool implements ExpressionEvaluator {
  EvaluatorIsolatePool._(this.watchdog, this.commitGrace);

  /// Age at which an unanswered request gets its worker killed.
  final Duration watchdog;

  /// Extra time granted to `=` so its cooperative 1 500 ms budget can report
  /// first.
  final Duration commitGrace;

  final SharedGeneration? _shared = SharedGeneration.tryAllocate();
  final Map<int, _Pending> _pending = <int, _Pending>{};
  late Future<_Worker> _active;
  Future<_Worker>? _spare;
  int _generation = 0;
  int _nextId = 0;
  int _respawns = 0;
  bool _disposed = false;

  /// Number of workers that had to be killed so far.
  int get respawnCount => _respawns;

  /// Whether newer input can interrupt a busy worker cooperatively.
  bool get hasSharedGeneration => _shared != null;

  /// Spawns a warm worker plus a warm spare.
  static Future<EvaluatorIsolatePool> start({
    Duration watchdog = const Duration(milliseconds: 1500),
    Duration commitGrace = const Duration(milliseconds: 300),
  }) async {
    final pool = EvaluatorIsolatePool._(watchdog, commitGrace);
    pool._active = pool._spawn();
    await pool._active;
    pool._spare = pool._spawn();
    return pool;
  }

  Future<_Worker> _spawn() async {
    final inbox = ReceivePort();
    final ready = Completer<SendPort>();
    inbox.listen((Object? message) {
      if (message is SendPort) {
        ready.complete(message);
      } else if (message is Map) {
        _onReply(message.cast<String, Object?>());
      }
    });
    final isolate = await Isolate.spawn<List<Object?>>(
      _workerMain,
      <Object?>[inbox.sendPort, _shared?.address],
      debugName: 'calc-evaluator',
    );
    return _Worker(isolate, await ready.future, inbox);
  }

  @override
  Future<EvaluationOutcome> evaluate(EvaluationRequest request) async {
    if (_disposed) {
      return const EvaluationOutcome.failure(CancelledEvaluationError('Evaluator was shut down'));
    }
    final id = ++_nextId;
    final generation = ++_generation;
    _shared?.value = generation;
    // Everything still in flight is obsolete now.
    for (final stale in _pending.values) {
      stale.completer.complete(const EvaluationOutcome.failure(CancelledEvaluationError('Superseded by newer input')));
    }
    for (final stale in _pending.values) {
      stale.timer.cancel();
    }
    _pending.clear();

    final completer = Completer<EvaluationOutcome>();
    final limit = request.isCommit ? watchdog + commitGrace : watchdog;
    final entry = _Pending(completer, Timer(limit, () => _onWatchdog(id)));
    _pending[id] = entry;
    final worker = await _active;
    if (_pending[id] == entry) worker.port.send(request.toMessage(id, generation));
    return completer.future;
  }

  void _onReply(Map<String, Object?> message) {
    final entry = _pending.remove(message['id']);
    if (entry == null) return; // superseded or already timed out
    entry.timer.cancel();
    entry.completer.complete(EvaluationOutcome.fromMessage(message));
  }

  void _onWatchdog(int id) {
    final entry = _pending.remove(id);
    if (entry == null || _disposed) return;
    _restartWorker();
    entry.completer.complete(const EvaluationOutcome.failure(CancelledEvaluationError('Evaluation timed out')));
  }

  /// Tier 2: kill the stuck worker and promote the warm spare.
  void _restartWorker() {
    _respawns++;
    final stuck = _active;
    unawaited(stuck.then((w) => w.kill()));
    _active = _spare ?? _spawn();
    _spare = _spawn();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in _pending.values) {
      entry.timer.cancel();
      entry.completer.complete(const EvaluationOutcome.failure(CancelledEvaluationError('Evaluator was shut down')));
    }
    _pending.clear();
    unawaited(_active.then((w) => w.kill()));
    final spare = _spare;
    if (spare != null) unawaited(spare.then((w) => w.kill()));
  }

  /// Entry point of the worker isolate.
  static void _workerMain(List<Object?> args) {
    final mainPort = args[0]! as SendPort;
    final address = args[1] as int?;
    final shared = address == null ? null : SharedGeneration.fromAddress(address);
    MathEngine.warmUp();
    final inbox = ReceivePort();
    mainPort.send(inbox.sendPort);
    inbox.listen((Object? message) {
      final request = (message! as Map<Object?, Object?>).cast<String, Object?>();
      mainPort.send(
        EvaluationWorker.handle(request, latestGeneration: shared == null ? null : () => shared.value),
      );
    });
  }
}

final class _Worker {
  _Worker(this.isolate, this.port, this.inbox);

  final Isolate isolate;
  final SendPort port;
  final ReceivePort inbox;

  void kill() {
    isolate.kill(priority: Isolate.immediate);
    inbox.close();
  }
}

final class _Pending {
  _Pending(this.completer, this.timer);

  final Completer<EvaluationOutcome> completer;
  final Timer timer;
}
