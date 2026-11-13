import 'package:decimal/decimal.dart';
import 'package:rational/rational.dart';

import '../evaluator/decimal_math.dart';
import 'calc_error.dart';

/// Every value the evaluator can produce.
sealed class CalcValue {
  const CalcValue();
}

/// An inexact real number carried with 50 significant digits.
final class DecimalVal extends CalcValue {
  final Decimal value; // 50-digit working precision
  const DecimalVal(this.value);

  @override
  String toString() => 'DecimalVal($value)';
}

/// An exact rational number.
final class RationalVal extends CalcValue {
  final Rational value; // Auto-demotes to DecimalVal if bitLength > 2048
  const RationalVal(this.value);

  @override
  String toString() => 'RationalVal($value)';
}

/// A complex number in rectangular form.
final class ComplexVal extends CalcValue {
  final Decimal real;
  final Decimal imag;
  const ComplexVal(this.real, this.imag);

  @override
  String toString() => 'ComplexVal($real, $imag)';
}

/// A fixed-width integer of the Base-N programmer mode.
///
/// [bits] always holds the raw word in `[0, 2^wordSize)`; [isSigned] only
/// selects how the word is read (two's complement) when it is displayed.
final class BitwiseVal extends CalcValue {
  final BigInt bits;
  final int wordSize; // 8, 16, 32, 64
  final bool isSigned;
  const BitwiseVal(this.bits, {this.wordSize = 64, this.isSigned = true});

  /// Wraps an arbitrary integer into the word.
  factory BitwiseVal.wrap(BigInt value, {int wordSize = 64, bool isSigned = true}) =>
      BitwiseVal(value & ((BigInt.one << wordSize) - BigInt.one), wordSize: wordSize, isSigned: isSigned);

  BigInt get mask => (BigInt.one << wordSize) - BigInt.one;

  /// Numeric reading of the word (two's complement when signed).
  BigInt get numericValue {
    if (!isSigned) return bits;
    final signBit = BigInt.one << (wordSize - 1);
    return bits & signBit == BigInt.zero ? bits : bits - (BigInt.one << wordSize);
  }

  @override
  String toString() => 'BitwiseVal($numericValue, $wordSize-bit ${isSigned ? 'signed' : 'unsigned'})';
}

/// A dense matrix of at most 4 x 4 entries.
final class MatrixVal extends CalcValue {
  final List<List<Decimal>> grid; // 1..4 rows x 1..4 cols
  const MatrixVal(this.grid);

  int get rows => grid.length;
  int get cols => grid.isEmpty ? 0 : grid.first.length;
  bool get isSquare => rows == cols;

  @override
  String toString() => 'MatrixVal($grid)';
}

/// Size limit of an exact fraction (numerator and denominator).
const int kRationalBitCeiling = 2048;

/// Rational complexity ceiling (blueprint §4.2).
///
/// Keeps [r] exact while both parts fit into [kRationalBitCeiling] bits and
/// otherwise demotes it to a 50-digit [DecimalVal], so that `gcd` reductions
/// of ever-growing denominators can never stall the evaluator.
CalcValue rationalOrDecimal(Rational r) =>
    r.numerator.bitLength > kRationalBitCeiling || r.denominator.bitLength > kRationalBitCeiling
        ? DecimalVal(Dec.fromRational(r))
        : RationalVal(r);

/// Exact arithmetic on fractions, guarded by the complexity ceiling.
extension RationalValArithmetic on RationalVal {
  CalcValue plus(RationalVal other) => rationalOrDecimal(value + other.value);

  CalcValue minus(RationalVal other) => rationalOrDecimal(value - other.value);

  CalcValue times(RationalVal other) => rationalOrDecimal(value * other.value);

  CalcValue dividedBy(RationalVal other) {
    if (other.value.numerator == BigInt.zero) throw const DivisionByZero();
    return rationalOrDecimal(value / other.value);
  }
}

/// Convenience constructors and views shared by the engines.
extension CalcValueViews on CalcValue {
  /// Whether the value is an exact fraction.
  bool get isExact => this is RationalVal;

  /// Whether the value lies on the real axis (and is a plain scalar).
  bool get isRealScalar => this is RationalVal || this is DecimalVal;

  /// The value as a 50-digit decimal; only valid for real scalars.
  Decimal get asDecimal => switch (this) {
        DecimalVal(:final value) => value,
        RationalVal(:final value) => Dec.fromRational(value),
        BitwiseVal(:final numericValue) => Dec.fromBigInt(numericValue),
        ComplexVal() => throw const DomainError('A real number is required here'),
        MatrixVal() => throw const DimensionError('A scalar is required here'),
      };
}

/// Shorthand factories.
abstract final class Values {
  static final RationalVal zero = RationalVal(Rational.zero);
  static final RationalVal one = RationalVal(Rational.one);

  static RationalVal ofInt(int v) => RationalVal(Rational.fromInt(v));

  static RationalVal ofBigInt(BigInt v) => RationalVal(Rational(v));

  /// Exact value of a decimal literal (falls back to [DecimalVal] when huge).
  static CalcValue ofDecimalExact(Decimal d) {
    final r = Dec.toRational(d);
    return r == null ? DecimalVal(Dec.round(d, WORK_PREC)) : rationalOrDecimal(r);
  }
}
