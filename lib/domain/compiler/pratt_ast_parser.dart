import '../models/ast_node.dart';
import '../models/calc_error.dart';
import 'tree_to_token_lowerer.dart';

/// Precedence-climbing (Pratt) parser.
///
/// Binding powers, weakest first:
///
/// | level | operators                                   |
/// |-------|---------------------------------------------|
/// | 2-8   | `or`, `xor`, `and`, `<<` `>>` (Base-N)      |
/// | 10    | `+` `−`                                     |
/// | 20    | `×` `÷` `mod`, ordinary implied `×`         |
/// | 30    | tight implied multiplication (`2π`)         |
/// | 35    | prefix `−` / `+` / `not`                    |
/// | 45    | inline radical `√`                          |
/// | 50    | `^` (right associative)                     |
/// | 60    | postfix `!` `%` `°`                         |
///
/// Parentheses that are still open at the end of the input are closed
/// automatically ("ghost parentheses"), so `sin(30` or `2×(3+4` evaluate
/// while they are being typed.
final class PrattAstParser {
  PrattAstParser._(this._tokens);

  final List<Token> _tokens;
  int _pos = 0;

  static const int _prefixPower = 35;
  static const int _radicalPower = 45;
  static const int _postfixPower = 60;

  /// Parses a normalised token stream into an executable tree.
  static AstNode parse(List<Token> tokens) {
    if (tokens.isEmpty) throw const SyntaxError('Empty expression', position: 0);
    final parser = PrattAstParser._(tokens);
    final node = parser._expression(0);
    final rest = parser._peek;
    if (rest != null) {
      throw SyntaxError(
        rest.kind == TokenKind.rightParen ? 'Unmatched ")"' : 'Unexpected "${rest.text}"',
        position: parser._pos,
      );
    }
    return node;
  }

  Token? get _peek => _pos < _tokens.length ? _tokens[_pos] : null;

  Token _advance() => _tokens[_pos++];

  bool _accept(TokenKind kind) {
    if (_peek?.kind == kind) {
      _pos++;
      return true;
    }
    return false;
  }

  /// Consumes a closing parenthesis, or accepts the end of the input in its
  /// place (ghost parenthesis).
  void _closeGroup() {
    if (_peek == null || _accept(TokenKind.rightParen)) return;
    throw SyntaxError('Expected ")" but found "${_peek!.text}"', position: _pos);
  }

  void _expect(TokenKind kind, String what) {
    if (!_accept(kind)) {
      final found = _peek;
      throw SyntaxError(
        found == null ? 'Incomplete expression: missing $what' : 'Expected $what but found "${found.text}"',
        position: _pos,
      );
    }
  }

  static (BinaryOp, int, int)? _binary(Token t) {
    if (t.implicit) {
      return t.tight ? (BinaryOp.multiply, 30, 31) : (BinaryOp.multiply, 20, 21);
    }
    return switch (t.text) {
      '+' => (BinaryOp.add, 10, 11),
      '−' || '-' => (BinaryOp.subtract, 10, 11),
      '×' || '*' || '·' => (BinaryOp.multiply, 20, 21),
      '÷' || '/' => (BinaryOp.divide, 20, 21),
      'mod' => (BinaryOp.modulo, 20, 21),
      '^' => (BinaryOp.power, 50, 49),
      'or' => (BinaryOp.bitOr, 2, 3),
      'xor' => (BinaryOp.bitXor, 4, 5),
      'and' => (BinaryOp.bitAnd, 6, 7),
      '<<' => (BinaryOp.shiftLeft, 8, 9),
      '>>' => (BinaryOp.shiftRight, 8, 9),
      _ => null,
    };
  }

  AstNode _expression(int minPower) {
    var left = _prefix();
    while (true) {
      final t = _peek;
      if (t == null) break;
      if (t.kind == TokenKind.postfix) {
        if (_postfixPower < minPower) break;
        _advance();
        final op = switch (t.text) {
          '!' => PostfixOp.factorial,
          '%' => PostfixOp.percent,
          '°' => PostfixOp.degree,
          _ => throw SyntaxError('Unknown postfix operator "${t.text}"', position: _pos - 1),
        };
        left = PostfixNode(op, left);
        continue;
      }
      if (t.kind != TokenKind.operator) break;
      final info = _binary(t);
      if (info == null) throw SyntaxError('Unknown operator "${t.text}"', position: _pos);
      final (op, leftPower, rightPower) = info;
      if (leftPower < minPower) break;
      _advance();
      final right = _expression(rightPower);
      left = BinaryNode(op, left, right, implicit: t.implicit);
    }
    return left;
  }

  AstNode _prefix() {
    final t = _peek;
    if (t == null) throw SyntaxError('Incomplete expression', position: _pos);
    _advance();
    switch (t.kind) {
      case TokenKind.number:
        return NumberNode(t.text);
      case TokenKind.constant:
        return ConstantNode(t.text);
      case TokenKind.variable:
        return VariableNode(t.text);
      case TokenKind.operator:
        if (t.implicit) break;
        if (t.text == '−' || t.text == '-') return UnaryNode(UnaryOp.negate, _expression(_prefixPower));
        if (t.text == '+') return UnaryNode(UnaryOp.plus, _expression(_prefixPower));
      case TokenKind.prefix:
        if (t.text == 'not') return UnaryNode(UnaryOp.bitNot, _expression(_prefixPower));
        return FunctionNode(t.text == '∛' ? 'cbrt' : 'sqrt', <AstNode>[_expression(_radicalPower)]);
      case TokenKind.leftParen:
        if (_peek?.kind == TokenKind.rightParen) throw SyntaxError('Empty parentheses', position: _pos);
        final inner = _expression(0);
        _closeGroup();
        return inner;
      case TokenKind.function:
        return FunctionNode(t.text == '√' ? 'sqrt' : t.text, _arguments(t.text));
      case TokenKind.derivative:
        _expect(TokenKind.leftParen, '"("');
        final body = _slot('the function to differentiate');
        _expect(TokenKind.comma, '","');
        if (_pos + 1 < _tokens.length && _tokens[_pos + 1].kind == TokenKind.equals) _pos += 2;
        final point = _slot('the point of evaluation');
        _closeGroup();
        return DerivativeNode(body, point, variable: t.variable ?? 'x');
      case TokenKind.integral:
        _expect(TokenKind.leftParen, '"("');
        final lower = _slot('the lower bound');
        _expect(TokenKind.comma, '","');
        final upper = _slot('the upper bound');
        _expect(TokenKind.comma, '","');
        final integrand = _slot('the integrand');
        _closeGroup();
        return IntegralNode(lower, upper, integrand, variable: t.variable ?? 'x');
      case TokenKind.postfix || TokenKind.rightParen || TokenKind.comma || TokenKind.equals:
        break;
    }
    throw SyntaxError('Unexpected "${t.text}"', position: _pos - 1);
  }

  /// One template slot; an empty slot is reported as such.
  AstNode _slot(String what) {
    final t = _peek;
    if (t == null || t.kind == TokenKind.comma || t.kind == TokenKind.rightParen) {
      throw SyntaxError('Missing $what', position: _pos);
    }
    return _expression(0);
  }

  List<AstNode> _arguments(String name) {
    _expect(TokenKind.leftParen, '"(" after $name');
    final args = <AstNode>[];
    if (_accept(TokenKind.rightParen)) return args;
    while (true) {
      args.add(_slot('an argument of $name'));
      if (_accept(TokenKind.comma)) continue;
      _closeGroup();
      return args;
    }
  }
}
