import '../models/math_context.dart';
import 'tree_to_token_lowerer.dart';

/// Makes implied multiplication explicit.
///
/// Wherever one operand ends and the next one starts without an operator in
/// between, a multiplication token is injected. Its binding strength depends
/// on the [JuxtapositionMode]:
///
/// * **standardTi** - a coefficient glued to a symbol (`2π`, `3x`, `xy`,
///   `2πr`) forms one term and binds tightly, so `1÷2π = 1/(2π)`. A factor in
///   front of a parenthesis or a function (`2(1+2)`, `2sin x`) is an ordinary
///   multiplication: `6÷2(1+2) = (6÷2)×3 = 9`.
/// * **strictCasio** - every implied multiplication binds tighter than `×`
///   and `÷`: `6÷2(1+2) = 6÷(2×3) = 1`.
abstract final class ImplicitMulNormalizer {
  static const Token _normal = Token(TokenKind.operator, '×', implicit: true);
  static const Token _tight = Token(TokenKind.operator, '×', implicit: true, tight: true);

  static bool _endsOperand(Token t) =>
      t.kind == TokenKind.number ||
      t.kind == TokenKind.constant ||
      t.kind == TokenKind.variable ||
      t.kind == TokenKind.rightParen ||
      t.kind == TokenKind.postfix;

  static bool _startsOperand(Token t) =>
      t.kind == TokenKind.number ||
      t.kind == TokenKind.constant ||
      t.kind == TokenKind.variable ||
      t.kind == TokenKind.leftParen ||
      t.kind == TokenKind.function ||
      t.kind == TokenKind.prefix ||
      t.kind == TokenKind.derivative ||
      t.kind == TokenKind.integral;

  static bool _isSymbol(Token t) => t.kind == TokenKind.constant || t.kind == TokenKind.variable;

  /// Returns [tokens] with multiplication tokens inserted at every
  /// juxtaposition.
  static List<Token> normalize(List<Token> tokens, JuxtapositionMode mode) {
    final out = <Token>[];
    for (var i = 0; i < tokens.length; i++) {
      final current = tokens[i];
      if (i > 0) {
        final previous = tokens[i - 1];
        // `d/dx(f, x = a)`: the bound variable in front of `=` is no operand.
        final bindsVariable = i + 1 < tokens.length && tokens[i + 1].kind == TokenKind.equals;
        final callParen = current.kind == TokenKind.leftParen &&
            (previous.kind == TokenKind.function ||
                previous.kind == TokenKind.derivative ||
                previous.kind == TokenKind.integral);
        if (!bindsVariable && !callParen && _endsOperand(previous) && _startsOperand(current)) {
          final coefficient = (previous.kind == TokenKind.number || _isSymbol(previous)) && _isSymbol(current);
          out.add(mode == JuxtapositionMode.strictCasio || coefficient ? _tight : _normal);
        }
      }
      out.add(current);
    }
    return out;
  }
}
