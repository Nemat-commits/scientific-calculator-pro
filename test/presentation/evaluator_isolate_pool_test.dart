// Dual-layer cancellation of the background evaluator. Pure Dart: these run
// under `dart test` as well as under `flutter test`.
import 'package:modern_scientific_calculator/domain/editor/clipboard_sanitizer.dart';
import 'package:modern_scientific_calculator/domain/models/calc_error.dart';
import 'package:modern_scientific_calculator/domain/models/math_context.dart';
import 'package:modern_scientific_calculator/presentation/isolate/evaluator_isolate_pool.dart';
import 'package:test/test.dart';

EvaluationRequest request(String text, {bool commit = false, Duration? busy, Map<String, String>? variables}) =>
    EvaluationRequest(
      root: ClipboardSanitizer.toSequence(text),
      context: const MathContext(),
      variables: variables ?? const <String, String>{'Ans': '0', 'M': '0'},
      isCommit: commit,
      debugBusyLoop: busy,
    );

void main() {
  late EvaluatorIsolatePool pool;

  setUp(() async => pool = await EvaluatorIsolatePool.start());
  tearDown(() => pool.dispose());

  test('evaluates on the worker isolate and returns the encoded value', () async {
    final outcome = await pool.evaluate(request('Ans+1/8', variables: const <String, String>{'Ans': '41'}));
    expect(outcome.isSuccess, isTrue);
    expect(outcome.primary, '41.125');
    expect(outcome.secondary, '329/8');
    expect(outcome.valueEncoded, '329/8');
    expect(outcome.expression, 'Ans+1÷8');
  });

  test('errors cross the isolate boundary as structured values', () async {
    final outcome = await pool.evaluate(request('1÷0', commit: true));
    expect(outcome.isSuccess, isFalse);
    expect(outcome.error, isA<DivisionByZero>());
  });

  test('tier 1: a newer keystroke supersedes a running evaluation', () async {
    final clock = Stopwatch()..start();
    final heavy = pool.evaluate(request('∫(0,1,∫(0,1,∫(0,1,sin(x)^x)))', commit: true));
    final light = pool.evaluate(request('2+2'));
    final results = await Future.wait(<Future<EvaluationOutcome>>[heavy, light]);
    expect(results[0].isCancelled, isTrue);
    expect(results[1].primary, '4');
    expect(clock.elapsedMilliseconds, lessThan(1000), reason: 'the heavy job did not run to completion');
    expect(pool.respawnCount, 0, reason: 'no isolate had to be killed');
  });

  test('tier 1: a live preview gives up after its 250 ms budget', () async {
    final clock = Stopwatch()..start();
    final outcome = await pool.evaluate(request('∫(0,1,∫(0,1,∫(0,1,sin(x)^x)))'));
    expect(outcome.error, isA<CancelledEvaluationError>());
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(240));
    expect(clock.elapsedMilliseconds, lessThan(1200));
    expect(pool.respawnCount, 0);
  });

  test('tier 2: the watchdog kills a stuck worker and a warm spare takes over', () async {
    final clock = Stopwatch()..start();
    // An uninterruptible 6 s spin stands in for one runaway native operation.
    final stuck = await pool.evaluate(request('1+1', busy: const Duration(seconds: 6)));
    expect(stuck.error, isA<CancelledEvaluationError>());
    expect(clock.elapsedMilliseconds, greaterThanOrEqualTo(1450));
    expect(clock.elapsedMilliseconds, lessThan(3000));
    expect(pool.respawnCount, 1);

    clock.reset();
    final next = await pool.evaluate(request('6×7'));
    expect(next.primary, '42');
    expect(clock.elapsedMilliseconds, lessThan(1000), reason: 'the replacement worker was already warm');
  });
}
