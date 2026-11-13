import '../models/calc_error.dart';
import '../models/calc_value.dart';
import '../models/math_context.dart';
import 'cancellation_token.dart';

/// Fixed-width integer arithmetic of the Base-N programmer mode.
///
/// Every result wraps around the word size (two's complement), exactly like
/// the registers of a CPU.
abstract final class BaseN {
  static BitwiseVal _wrap(BigInt value, BitwiseVal like) =>
      BitwiseVal.wrap(value, wordSize: like.wordSize, isSigned: like.isSigned);

  /// Parses a literal written in the radix of [config].
  static BitwiseVal parse(String literal, BaseNConfig config) {
    final value = BigInt.tryParse(literal, radix: config.radix);
    if (value == null) {
      throw SyntaxError('"$literal" is not a valid base-${config.radix} number');
    }
    return BitwiseVal.wrap(value, wordSize: config.wordSize, isSigned: config.isSigned);
  }

  /// Re-reads [v] under another word size / signedness.
  static BitwiseVal convert(BitwiseVal v, BaseNConfig config) =>
      BitwiseVal.wrap(v.numericValue, wordSize: config.wordSize, isSigned: config.isSigned);

  static BitwiseVal add(BitwiseVal a, BitwiseVal b) => _wrap(a.numericValue + b.numericValue, a);

  static BitwiseVal sub(BitwiseVal a, BitwiseVal b) => _wrap(a.numericValue - b.numericValue, a);

  static BitwiseVal mul(BitwiseVal a, BitwiseVal b) => _wrap(a.numericValue * b.numericValue, a);

  /// Integer division truncating towards zero.
  static BitwiseVal div(BitwiseVal a, BitwiseVal b) {
    if (b.bits == BigInt.zero) throw const DivisionByZero();
    return _wrap(a.numericValue ~/ b.numericValue, a);
  }

  /// Remainder with the sign of the dividend.
  static BitwiseVal mod(BitwiseVal a, BitwiseVal b) {
    if (b.bits == BigInt.zero) throw const DivisionByZero('Modulo by zero');
    return _wrap(a.numericValue.remainder(b.numericValue), a);
  }

  static BitwiseVal negate(BitwiseVal a) => _wrap(-a.numericValue, a);

  static BitwiseVal not(BitwiseVal a) => _wrap(a.bits ^ a.mask, a);

  static BitwiseVal and(BitwiseVal a, BitwiseVal b) => _wrap(a.bits & b.bits, a);

  static BitwiseVal or(BitwiseVal a, BitwiseVal b) => _wrap(a.bits | b.bits, a);

  static BitwiseVal xor(BitwiseVal a, BitwiseVal b) => _wrap(a.bits ^ b.bits, a);

  static int _shiftCount(BitwiseVal a, BitwiseVal n) {
    final count = n.numericValue;
    if (count.isNegative) throw const DomainError('Negative shift count');
    return count > BigInt.from(a.wordSize) ? a.wordSize : count.toInt();
  }

  static BitwiseVal shiftLeft(BitwiseVal a, BitwiseVal n) => _wrap(a.bits << _shiftCount(a, n), a);

  /// Arithmetic shift for signed words, logical shift for unsigned ones.
  static BitwiseVal shiftRight(BitwiseVal a, BitwiseVal n) {
    final count = _shiftCount(a, n);
    return _wrap(a.isSigned ? a.numericValue >> count : a.bits >> count, a);
  }

  static BitwiseVal pow(BitwiseVal a, BitwiseVal e, [CancellationToken? token]) {
    final exponent = e.numericValue;
    if (exponent.isNegative) throw const DomainError('Negative exponent in Base-N mode');
    token?.tick();
    return _wrap(a.bits.modPow(exponent, BigInt.one << a.wordSize), a);
  }
}
