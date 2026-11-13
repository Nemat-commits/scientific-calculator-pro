/// Executable syntax tree produced by the Pratt parser.
library;

/// Prefix operators.
enum UnaryOp { negate, plus, bitNot }

/// Infix operators.
enum BinaryOp {
  add,
  subtract,
  multiply,
  divide,
  power,
  modulo,
  bitAnd,
  bitOr,
  bitXor,
  shiftLeft,
  shiftRight,
}

/// Postfix operators.
enum PostfixOp { factorial, percent, degree }

/// Base class of all executable nodes.
sealed class AstNode {
  const AstNode();
}

/// A numeric literal exactly as it was typed (`12.5`, `1.5E-3`, `FF`).
final class NumberNode extends AstNode {
  const NumberNode(this.literal);
  final String literal;

  @override
  String toString() => literal;
}

/// A named constant (`π`, `e`, `i`, CODATA symbols).
final class ConstantNode extends AstNode {
  const ConstantNode(this.name);
  final String name;

  @override
  String toString() => name;
}

/// A variable (`Ans`, `M`, `A`..`Z`, `x`).
final class VariableNode extends AstNode {
  const VariableNode(this.name);
  final String name;

  @override
  String toString() => name;
}

final class UnaryNode extends AstNode {
  const UnaryNode(this.op, this.operand);
  final UnaryOp op;
  final AstNode operand;

  @override
  String toString() => '(${op.name} $operand)';
}

final class BinaryNode extends AstNode {
  const BinaryNode(this.op, this.left, this.right, {this.implicit = false});
  final BinaryOp op;
  final AstNode left;
  final AstNode right;

  /// True for a multiplication that was implied by juxtaposition.
  final bool implicit;

  @override
  String toString() => '(${op.name} $left $right)';
}

final class PostfixNode extends AstNode {
  const PostfixNode(this.op, this.operand);
  final PostfixOp op;
  final AstNode operand;

  @override
  String toString() => '(${op.name} $operand)';
}

/// A call of a named function.
final class FunctionNode extends AstNode {
  const FunctionNode(this.name, this.args);
  final String name;
  final List<AstNode> args;

  @override
  String toString() => '($name ${args.join(' ')})';
}

/// `d/dx(body)` evaluated at `x = point`.
final class DerivativeNode extends AstNode {
  const DerivativeNode(this.body, this.point, {this.variable = 'x'});
  final AstNode body;
  final AstNode point;
  final String variable;

  @override
  String toString() => '(d/d$variable $body at $point)';
}

/// Definite integral of `integrand` over `[lower, upper]`.
final class IntegralNode extends AstNode {
  const IntegralNode(this.lower, this.upper, this.integrand, {this.variable = 'x'});
  final AstNode lower;
  final AstNode upper;
  final AstNode integrand;
  final String variable;

  @override
  String toString() => '(∫ $lower $upper $integrand d$variable)';
}
