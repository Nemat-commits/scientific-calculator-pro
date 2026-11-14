import '../models/editor_node.dart';
import 'math_print_controller.dart';

/// 2D templates a key can insert.
enum TemplateKind {
  /// Stacked fraction `□/□`.
  fraction,

  /// Mixed fraction `□ □/□` with the caret in the whole part.
  mixedFraction,

  /// Empty superscript `x^□`.
  power,

  /// `x²`
  square,

  /// `x³`
  cube,

  /// `x⁻¹`
  reciprocal,

  /// `√□`
  squareRoot,

  /// `∛□`
  cubeRoot,

  /// `ⁿ√□` with the caret in the degree.
  nthRoot,

  /// `10^□`
  powerOfTen,

  /// `e^□`
  powerOfE,

  /// `name(□, …)`
  function,

  /// `∫` with bounds and integrand.
  integral,

  /// `Σ` from a first to a last whole number.
  summation,

  /// `Π` from a first to a last whole number.
  product,

  /// `d/dx(□)` at `x = □`.
  derivative,
}

/// A key press, independent of any widget toolkit.
sealed class CalcKey {
  const CalcKey();
}

/// Inserts one atom (digit, operator, constant, variable, parenthesis …).
final class AtomKey extends CalcKey {
  const AtomKey(this.text, this.kind);
  final String text;
  final AtomKind kind;
}

/// Inserts a 2D template.
final class TemplateKey extends CalcKey {
  const TemplateKey(this.kind, {this.name, this.arity = 1});
  final TemplateKind kind;

  /// Function name for [TemplateKind.function].
  final String? name;

  /// Number of arguments for [TemplateKind.function].
  final int arity;
}

/// Moves the caret.
final class MoveKey extends CalcKey {
  const MoveKey(this.direction);
  final CursorDirection direction;
}

/// `⌫`
final class BackspaceKey extends CalcKey {
  const BackspaceKey();
}

/// `AC`
final class ClearKey extends CalcKey {
  const ClearKey();
}

/// `=`
final class EvaluateKey extends CalcKey {
  const EvaluateKey();
}
