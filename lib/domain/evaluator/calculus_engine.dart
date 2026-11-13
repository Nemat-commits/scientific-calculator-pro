import 'package:decimal/decimal.dart';

import '../models/calc_error.dart';
import 'cancellation_token.dart';
import 'decimal_math.dart';

/// A real function of one real variable.
typedef RealFunction = Decimal Function(Decimal x);

/// Numerical differentiation and integration.
abstract final class CalculusEngine {
  /// Significant digits of every returned result (`prec: 14`).
  static const int resultPrecision = 14;

  /// Panels after which the untransformed rule is considered stalled.
  static const int _plainStallPanels = 128;

  /// Panels after which a transform level is considered stalled.
  static const int _stallPanels = 32;

  /// Upper bound of the composite rule.
  static const int _maxPanels = 1024;

  /// Highest number of nested endpoint substitutions.
  static const int _maxLevel = 6;

  static final Decimal _three = Dec.fromInt(3);
  static final Decimal _four = Dec.fromInt(4);
  static final Decimal _six = Dec.fromInt(6);
  static final Decimal _stepFactor = Dec.parse('1e-6');
  static final Decimal _cuspGap = Dec.parse('1e-3');
  static final Decimal _cuspRatio = Dec.parse('0.9');
  static final Decimal _singularLimit = Dec.parse('1e12');
  static final Decimal _tolerance = Dec.parse('1e-16');
  static final Decimal _looseTolerance = Dec.parse('1e-7');
  static final Decimal _acceptTolerance = Dec.parse('1e-5');
  static final Decimal _crossTolerance = Dec.parse('1e-15');

  static final Decimal _sqrt10over7 = Dec.sqrt(Dec.div(Dec.ten, Dec.fromInt(7), 60), 60);
  static final Decimal _sqrt70 = Dec.sqrt(Dec.fromInt(70), 60);

  static Decimal _node(bool outer) {
    final twice = Dec.mul(Dec.two, _sqrt10over7, 60);
    final five = Dec.fromInt(5);
    final inner = outer ? Dec.add(five, twice, 60) : Dec.sub(five, twice, 60);
    return Dec.div(Dec.sqrt(inner, 60), _three, WORK_PREC);
  }

  static Decimal _weight(bool outer) {
    final t = Dec.mul(Dec.fromInt(13), _sqrt70, 60);
    final base = Dec.fromInt(322);
    return Dec.div(outer ? Dec.sub(base, t, 60) : Dec.add(base, t, 60), Dec.fromInt(900), WORK_PREC);
  }

  /// 5-point Gauss-Legendre abscissae on `[-1, 1]`, computed algebraically:
  /// `0`, `±(1/3)·sqrt(5 − 2·sqrt(10/7))`, `±(1/3)·sqrt(5 + 2·sqrt(10/7))`.
  static final List<Decimal> gaussNodes = List<Decimal>.unmodifiable(<Decimal>[
    Dec.neg(_node(true)),
    Dec.neg(_node(false)),
    Dec.zero,
    _node(false),
    _node(true),
  ]);

  /// Matching weights: `128/225` and `(322 ± 13·sqrt(70))/900`.
  static final List<Decimal> gaussWeights = List<Decimal>.unmodifiable(<Decimal>[
    _weight(true),
    _weight(false),
    Dec.div(Dec.fromInt(128), Dec.fromInt(225), WORK_PREC),
    _weight(false),
    _weight(true),
  ]);

  /// Forces the lazily initialised tables (called when a worker isolate boots).
  static void warmUp() {
    gaussNodes.length;
    gaussWeights.length;
  }

  /// Richardson-extrapolated central difference with a cusp guard.
  static Decimal derivative(RealFunction f, Decimal x0, {CancellationToken? token}) {
    final ax = Dec.abs(x0);
    final h = Dec.mul(Dec.compare(ax, Dec.one) > 0 ? ax : Dec.one, _stepFactor);
    final h2 = Dec.mul(h, Dec.half);
    token?.throwIfCancelled();
    final f0 = f(x0);
    final fp1 = f(Dec.add(x0, h)), fm1 = f(Dec.sub(x0, h));
    final fp2 = f(Dec.add(x0, h2)), fm2 = f(Dec.sub(x0, h2));
    token?.throwIfCancelled();

    // One-sided secants: a kink keeps them apart no matter how small h gets.
    Decimal gap(Decimal fp, Decimal fm, Decimal step) {
      final right = Dec.div(Dec.sub(fp, f0), step);
      final left = Dec.div(Dec.sub(f0, fm), step);
      return Dec.abs(Dec.sub(right, left));
    }

    final gap1 = gap(fp1, fm1, h), gap2 = gap(fp2, fm2, h2);
    if (Dec.compare(gap1, _cuspGap) > 0 && Dec.compare(gap2, Dec.mul(_cuspRatio, gap1)) >= 0) {
      throw const DomainError('Non-differentiable cusp or discontinuity');
    }

    final d1 = Dec.div(Dec.sub(fp1, fm1), Dec.mul(h, Dec.two));
    final d2 = Dec.div(Dec.sub(fp2, fm2), h);
    final result = Dec.div(Dec.sub(Dec.mul(_four, d2), d1), _three);

    // Anything below the round-off floor of the difference quotient is zero.
    var magnitude = Dec.abs(f0);
    for (final v in <Decimal>[fp1, fm1]) {
      magnitude = Dec.max(magnitude, Dec.abs(v));
    }
    if (!Dec.isZero(result)) {
      final floorExp = (Dec.isZero(magnitude) ? 0 : Dec.adjExp(magnitude)) - Dec.adjExp(h) - 22;
      if (Dec.adjExp(result) < floorExp) return Dec.zero;
    }
    return Dec.round(result, resultPrecision);
  }

  static bool _isSingular(RealFunction f, Decimal x) {
    try {
      return Dec.compare(Dec.abs(f(x)), _singularLimit) > 0;
    } on DivisionByZero {
      return true;
    } on DomainError {
      return true;
    } on OverflowError {
      return true;
    }
  }

  /// Composite 5-point Gauss-Legendre rule; returns the integral and the
  /// integral of the absolute value (the natural error scale).
  static (Decimal, Decimal) _composite(RealFunction g, Decimal lo, Decimal hi, int panels, CancellationToken? token) {
    final width = Dec.div(Dec.sub(hi, lo), Dec.fromInt(panels));
    final halfWidth = Dec.mul(width, Dec.half);
    var sum = Dec.zero, sumAbs = Dec.zero;
    for (var i = 0; i < panels; i++) {
      token?.throwIfCancelled();
      final mid = Dec.add(lo, Dec.mul(width, Dec.add(Dec.fromInt(i), Dec.half)));
      for (var j = 0; j < 5; j++) {
        final v = Dec.mul(gaussWeights[j], g(Dec.add(mid, Dec.mul(halfWidth, gaussNodes[j]))));
        sum = Dec.add(sum, v);
        sumAbs = Dec.add(sumAbs, Dec.abs(v));
      }
    }
    return (Dec.mul(sum, halfWidth), Dec.mul(sumAbs, halfWidth));
  }

  /// Definite integral of [f] over `[a, b]`.
  ///
  /// Open rule (the endpoints are never sampled). When an endpoint is
  /// singular - evaluation throws or exceeds `10^12` - or the plain rule
  /// stalls, the substitution `x(t) = a + (b−a)(3t² − 2t³)`,
  /// `dx = 6(b−a)·t(1−t)·dt` is applied (repeatedly if necessary), which
  /// flattens integrable endpoint singularities such as `∫₀¹ dx/√x`.
  ///
  /// A slowly converging integral is returned with fewer than
  /// [resultPrecision] digits; [onPrecision] is then told how many.
  static Decimal integrate(
    RealFunction f,
    Decimal a,
    Decimal b, {
    CancellationToken? token,
    void Function(int digits)? onPrecision,
  }) {
    final order = Dec.compare(a, b);
    if (order == 0) return Dec.zero;
    if (order > 0) return Dec.neg(integrate(f, b, a, token: token, onPrecision: onPrecision));
    final width = Dec.sub(b, a);
    final singular = _isSingular(f, a) || _isSingular(f, b);

    RealFunction transformed(int level) {
      if (level == 0) return f;
      return (Decimal t) {
        var u = t;
        var jacobian = width;
        for (var i = 0; i < level; i++) {
          jacobian = Dec.mul(jacobian, Dec.mul(_six, Dec.mul(u, Dec.sub(Dec.one, u))));
          u = Dec.mul(Dec.mul(u, u), Dec.sub(_three, Dec.mul(Dec.two, u)));
        }
        return Dec.mul(f(Dec.add(a, Dec.mul(width, u))), jacobian);
      };
    }

    Decimal finish(Decimal value, Decimal scale, [int digits = resultPrecision]) {
      if (Dec.isZero(value)) return Dec.zero;
      if (!Dec.isZero(scale) && Dec.adjExp(value) < Dec.adjExp(scale) - 20) return Dec.zero;
      return Dec.round(value, digits);
    }

    // Nested (dyadic) meshes share their panel edges, so a kink that hides in
    // the node-free gap next to an edge yields the *same* wrong value on every
    // refinement. Re-evaluating on a mesh with an odd panel count - whose
    // interior edges never coincide with dyadic ones - exposes that.
    Decimal crossCheck(_Ladder ladder) {
      final finest = ladder.panels ~/ 2;
      final g = transformed(ladder.level);
      final lo = ladder.level == 0 ? a : Dec.zero, hi = ladder.level == 0 ? b : Dec.one;
      final (value, _) = _composite(g, lo, hi, (finest * 3 ~/ 2) | 1, token);
      final gap = Dec.abs(Dec.sub(value, ladder.value!));
      ladder.crossGap = gap;
      return gap;
    }

    // One refinement ladder (2, 4, 8, ... panels) of a given transform level.
    // Returns the converged value, or records how far the ladder got.
    Decimal? climb(_Ladder ladder, int untilPanels) {
      final g = transformed(ladder.level);
      final lo = ladder.level == 0 ? a : Dec.zero, hi = ladder.level == 0 ? b : Dec.one;
      while (ladder.panels <= untilPanels) {
        final (value, scale) = _composite(g, lo, hi, ladder.panels, token);
        ladder.panels *= 2;
        final prev = ladder.value;
        ladder
          ..value = value
          ..scale = scale;
        if (prev == null) continue;
        final diff = Dec.abs(Dec.sub(value, prev));
        final prevDiff = ladder.diff;
        ladder
          ..prevDiff = prevDiff
          ..diff = diff;
        if (prevDiff == null) continue;
        // Error of the finer rule, extrapolated from the observed decay. The
        // coarser pair must already agree to ~7 digits, which rules out a
        // lucky coincidence of two poor estimates.
        //
        // Two estimates can agree to the last working digit (a constant, an
        // odd function over a symmetric interval, sin² over a full period):
        // then there is no decay to extrapolate and the difference itself -
        // zero - is the prediction.
        var predicted = diff;
        if (!Dec.isZero(diff)) {
          final ratio = Dec.div(prevDiff, diff, 20);
          if (Dec.compare(ratio, Dec.two) > 0) predicted = Dec.div(diff, Dec.sub(ratio, Dec.one), 20);
        }
        if (Dec.compare(predicted, Dec.mul(_tolerance, scale)) <= 0 &&
            Dec.compare(prevDiff, Dec.mul(_looseTolerance, scale)) <= 0 &&
            Dec.compare(crossCheck(ladder), Dec.mul(_crossTolerance, scale)) <= 0) {
          return finish(value, scale);
        }
      }
      return null;
    }

    _Ladder? best;
    for (var level = singular ? 1 : 0; level <= _maxLevel; level++) {
      final ladder = _Ladder(level);
      final done = climb(ladder, level == 0 ? _plainStallPanels : _stallPanels);
      if (done != null) return done;
      if (best == null || Dec.compare(ladder.worstDiff, best.worstDiff) < 0) best = ladder;
    }

    // Nothing converged quickly: push the most promising ladder further.
    final done = climb(best!, _maxPanels);
    if (done != null) return done;
    final scale = best.scale!;
    final error = Dec.max(best.worstDiff, crossCheck(best));
    if (Dec.compare(error, Dec.mul(_acceptTolerance, scale)) <= 0) {
      // Report only the digits the last estimates agree on.
      final agreed = Dec.adjExp(scale) - Dec.adjExp(error) - 1;
      final digits = agreed < 3 ? 3 : (agreed > resultPrecision ? resultPrecision : agreed);
      onPrecision?.call(digits);
      return finish(best.value!, scale, digits);
    }
    throw const DomainError('Integral does not converge');
  }
}

/// Progress of one refinement ladder of [CalculusEngine.integrate].
final class _Ladder {
  _Ladder(this.level);

  final int level;
  int panels = 2;
  Decimal? value;
  Decimal? scale;
  Decimal? diff;
  Decimal? prevDiff;
  Decimal? crossGap;

  /// Conservative error estimate: the larger of the last two differences.
  Decimal get worstDiff {
    final d = diff, p = prevDiff;
    if (d == null) return Dec.parse('1e999');
    return p == null ? d : Dec.max(d, p);
  }
}
