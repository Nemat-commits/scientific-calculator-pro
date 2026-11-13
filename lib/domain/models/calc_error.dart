/// Structured error model shared by the compiler, the evaluator and the UI.
library;

/// Coarse classification used by the UI to pick an icon / headline.
enum CalcErrorType {
  syntax,
  domain,
  divisionByZero,
  overflow,
  cancelled,
  undefinedVariable,
  dimension,
  unsupported,
}

/// Base class of every error the calculator can raise on purpose.
///
/// All subclasses are plain immutable values so they can cross an isolate
/// boundary through [toJson] / [CalcError.fromJson].
sealed class CalcError implements Exception {
  const CalcError(this.type, this.message, {this.position});

  final CalcErrorType type;

  /// Human readable, already suitable for display.
  final String message;

  /// Index of the offending token (when known).
  final int? position;

  /// Short headline shown in the error-locked display.
  String get headline => switch (type) {
        CalcErrorType.syntax => 'Syntax error',
        CalcErrorType.domain => 'Math error',
        CalcErrorType.divisionByZero => 'Division by zero',
        CalcErrorType.overflow => 'Overflow',
        CalcErrorType.cancelled => 'Cancelled',
        CalcErrorType.undefinedVariable => 'Undefined variable',
        CalcErrorType.dimension => 'Dimension error',
        CalcErrorType.unsupported => 'Not supported',
      };

  Map<String, Object?> toJson() => {
        'type': type.name,
        'message': message,
        if (position != null) 'position': position,
      };

  static CalcError fromJson(Map<String, Object?> json) {
    final message = json['message'] as String? ?? '';
    final position = json['position'] as int?;
    final type = CalcErrorType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => CalcErrorType.domain,
    );
    return switch (type) {
      CalcErrorType.syntax => SyntaxError(message, position: position),
      CalcErrorType.domain => DomainError(message),
      CalcErrorType.divisionByZero => DivisionByZero(message),
      CalcErrorType.overflow => OverflowError(message),
      CalcErrorType.cancelled => CancelledEvaluationError(message),
      CalcErrorType.undefinedVariable => UndefinedVariableError(message),
      CalcErrorType.dimension => DimensionError(message),
      CalcErrorType.unsupported => UnsupportedOperationError(message),
    };
  }

  @override
  String toString() => '$runtimeType: $message';
}

/// The expression cannot be parsed.
final class SyntaxError extends CalcError {
  const SyntaxError(String message, {super.position}) : super(CalcErrorType.syntax, message);
}

/// The operation is mathematically undefined for the given operand(s).
final class DomainError extends CalcError {
  const DomainError(String message) : super(CalcErrorType.domain, message);
}

/// A divisor evaluated to exactly zero.
final class DivisionByZero extends CalcError {
  const DivisionByZero([String message = 'Division by zero']) : super(CalcErrorType.divisionByZero, message);
}

/// The magnitude of a result left the representable exponent range.
final class OverflowError extends CalcError {
  const OverflowError([String message = 'Result is too large']) : super(CalcErrorType.overflow, message);
}

/// Raised cooperatively when an evaluation was superseded or ran out of time.
final class CancelledEvaluationError extends CalcError {
  const CancelledEvaluationError([String message = 'Evaluation cancelled']) : super(CalcErrorType.cancelled, message);
}

/// A variable was referenced that has no stored value.
final class UndefinedVariableError extends CalcError {
  const UndefinedVariableError(String message) : super(CalcErrorType.undefinedVariable, message);
}

/// Matrix / vector shapes do not fit the requested operation.
final class DimensionError extends CalcError {
  const DimensionError(String message) : super(CalcErrorType.dimension, message);
}

/// The operation exists but is not available for this kind of value.
final class UnsupportedOperationError extends CalcError {
  const UnsupportedOperationError(String message) : super(CalcErrorType.unsupported, message);
}
