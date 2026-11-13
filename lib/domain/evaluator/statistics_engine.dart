import 'package:decimal/decimal.dart';

import '../models/calc_error.dart';
import 'decimal_math.dart';

/// Summary of one data column.
final class OneVarStats {
  const OneVarStats({
    required this.n,
    required this.sum,
    required this.sumOfSquares,
    required this.mean,
    required this.populationVariance,
    required this.populationStdDev,
    required this.sampleVariance,
    required this.sampleStdDev,
    required this.min,
    required this.max,
    required this.median,
    required this.q1,
    required this.q3,
  });

  final int n;
  final Decimal sum;
  final Decimal sumOfSquares;
  final Decimal mean;
  final Decimal populationVariance;
  final Decimal populationStdDev;

  /// `null` for a single observation.
  final Decimal? sampleVariance;
  final Decimal? sampleStdDev;
  final Decimal min;
  final Decimal max;
  final Decimal median;
  final Decimal q1;
  final Decimal q3;

  Decimal get range => Dec.sub(max, min, 1000);
}

/// Summary of paired data plus the least-squares line `y = a + b x`.
final class TwoVarStats {
  const TwoVarStats({
    required this.x,
    required this.y,
    required this.sumOfProducts,
    required this.covariance,
    required this.slope,
    required this.intercept,
    required this.correlation,
  });

  final OneVarStats x;
  final OneVarStats y;
  final Decimal sumOfProducts;

  /// Population covariance.
  final Decimal covariance;

  /// `b`; `null` when all x values coincide.
  final Decimal? slope;

  /// `a`
  final Decimal? intercept;

  /// Pearson's r; `null` when either column is constant.
  final Decimal? correlation;

  Decimal? get rSquared => correlation == null ? null : Dec.mul(correlation!, correlation!);

  /// `ŷ = a + b x`
  Decimal? predictY(Decimal xValue) => slope == null ? null : Dec.add(intercept!, Dec.mul(slope!, xValue));

  /// `x̂ = (y − a) / b`
  Decimal? predictX(Decimal yValue) =>
      slope == null || Dec.isZero(slope!) ? null : Dec.div(Dec.sub(yValue, intercept!), slope!);
}

/// 1-variable and 2-variable statistics on exact decimal data.
abstract final class StatisticsEngine {
  static const int _exact = 100000;

  static Decimal _median(List<Decimal> sorted) {
    final n = sorted.length;
    if (n.isOdd) return sorted[n ~/ 2];
    return Dec.mul(Dec.add(sorted[n ~/ 2 - 1], sorted[n ~/ 2], _exact), Dec.half, _exact);
  }

  /// Statistics of [data]; each value may carry a positive integer weight in
  /// [frequencies].
  static OneVarStats oneVariable(List<Decimal> data, {List<int>? frequencies}) {
    if (data.isEmpty) throw const DomainError('Enter at least one value');
    if (frequencies != null && frequencies.length != data.length) {
      throw const DimensionError('Every value needs a frequency');
    }
    final values = <Decimal>[];
    for (var i = 0; i < data.length; i++) {
      final f = frequencies == null ? 1 : frequencies[i];
      if (f < 0) throw const DomainError('Frequencies cannot be negative');
      for (var k = 0; k < f; k++) {
        values.add(data[i]);
      }
    }
    if (values.isEmpty) throw const DomainError('Enter at least one value');
    final n = values.length;
    final count = Dec.fromInt(n);
    var sum = Dec.zero, sumSq = Dec.zero;
    for (final v in values) {
      sum = Dec.add(sum, v, _exact);
      sumSq = Dec.add(sumSq, Dec.mul(v, v, _exact), _exact);
    }
    // n Σx² − (Σx)² is formed exactly, so no digits are lost to cancellation.
    final spread = Dec.sub(Dec.mul(count, sumSq, _exact), Dec.mul(sum, sum, _exact), _exact);
    final popVar = Dec.div(spread, Dec.mul(count, count, _exact));
    final sampleVar = n > 1 ? Dec.div(spread, Dec.mul(count, Dec.fromInt(n - 1), _exact)) : null;
    final sorted = <Decimal>[...values]..sort(Dec.compare);
    final half = n ~/ 2;
    return OneVarStats(
      n: n,
      sum: sum,
      sumOfSquares: sumSq,
      mean: Dec.div(sum, count),
      populationVariance: popVar,
      populationStdDev: Dec.sqrt(popVar),
      sampleVariance: sampleVar,
      sampleStdDev: sampleVar == null ? null : Dec.sqrt(sampleVar),
      min: sorted.first,
      max: sorted.last,
      median: _median(sorted),
      q1: n == 1 ? sorted.first : _median(sorted.sublist(0, half)),
      q3: n == 1 ? sorted.first : _median(sorted.sublist(n - half)),
    );
  }

  /// Statistics and linear regression of the pairs `(xs[i], ys[i])`.
  static TwoVarStats twoVariable(List<Decimal> xs, List<Decimal> ys) {
    if (xs.length != ys.length) throw const DimensionError('x and y need the same number of values');
    if (xs.isEmpty) throw const DomainError('Enter at least one pair');
    final sx = oneVariable(xs), sy = oneVariable(ys);
    final count = Dec.fromInt(xs.length);
    var sumXY = Dec.zero;
    for (var i = 0; i < xs.length; i++) {
      sumXY = Dec.add(sumXY, Dec.mul(xs[i], ys[i], _exact), _exact);
    }
    Decimal spread(Decimal sumSq, Decimal sum) =>
        Dec.sub(Dec.mul(count, sumSq, _exact), Dec.mul(sum, sum, _exact), _exact);
    final sxx = spread(sx.sumOfSquares, sx.sum), syy = spread(sy.sumOfSquares, sy.sum);
    final sxy = Dec.sub(Dec.mul(count, sumXY, _exact), Dec.mul(sx.sum, sy.sum, _exact), _exact);
    final slope = Dec.isZero(sxx) ? null : Dec.div(sxy, sxx);
    final intercept = slope == null ? null : Dec.div(Dec.sub(sy.sum, Dec.mul(slope, sx.sum, 80), 80), count);
    final correlation =
        Dec.isZero(sxx) || Dec.isZero(syy) ? null : Dec.div(sxy, Dec.sqrt(Dec.mul(sxx, syy, _exact), 60));
    return TwoVarStats(
      x: sx,
      y: sy,
      sumOfProducts: sumXY,
      covariance: Dec.div(sxy, Dec.mul(count, count, _exact)),
      slope: slope,
      intercept: intercept,
      correlation: correlation,
    );
  }
}
