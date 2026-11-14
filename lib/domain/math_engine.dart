import 'dart:math' as math;

import 'compiler/implicit_mul_normalizer.dart';
import 'compiler/pratt_ast_parser.dart';
import 'compiler/tree_to_token_lowerer.dart';
import 'editor/clipboard_sanitizer.dart';
import 'evaluator/ast_evaluator.dart';
import 'evaluator/calculus_engine.dart';
import 'evaluator/cancellation_token.dart';
import 'evaluator/gamma_combinatorics.dart';
import 'evaluator/number_formatter.dart';
import 'models/ast_node.dart';
import 'models/calc_error.dart';
import 'models/calc_value.dart';
import 'models/editor_node.dart';
import 'models/math_context.dart';

/// Outcome of evaluating one expression.
final class EvaluationResult {
  const EvaluationResult({
    required this.value,
    required this.primary,
    required this.expression,
    this.secondary,
  });

  /// The computed value (kept for `Ans`).
  final CalcValue value;

  /// Canonical 34-digit display string.
  final String primary;

  /// Another way to write the result, when there is one: the exact fraction,
  /// the engineering form - or, in engineering notation, the plain number.
  final String? secondary;

  /// Linear text of the evaluated expression, e.g. `((1)/(2))+3`.
  final String expression;
}

/// Facade over the whole pipeline:
/// editor tree → tokens → implicit-multiplication pass → AST → value → text.
abstract final class MathEngine {
  /// Compiles an editor tree into an executable syntax tree.
  static AstNode compile(EditorSequence root, {JuxtapositionMode juxtaposition = JuxtapositionMode.standardTi}) {
    final tokens = TreeToTokenLowerer.lower(root);
    if (tokens.isEmpty) throw const SyntaxError('Empty expression', position: 0);
    return PrattAstParser.parse(ImplicitMulNormalizer.normalize(tokens, juxtaposition));
  }

  /// Evaluates the expression held by [root].
  static EvaluationResult evaluateSequence(
    EditorSequence root, {
    MathContext context = const MathContext(),
    Map<String, CalcValue>? variables,
    CancellationToken? token,
    math.Random? random,
  }) {
    final tokens = TreeToTokenLowerer.lower(root, programmer: context.baseN != null);
    if (tokens.isEmpty) throw const SyntaxError('Empty expression', position: 0);
    final ast = PrattAstParser.parse(ImplicitMulNormalizer.normalize(tokens, context.juxtaposition));
    final evaluator = AstEvaluator(context: context, variables: variables, token: token, random: random);
    final value = evaluator.evaluate(ast);
    final special = evaluator.displayOverrideFor(value);
    return EvaluationResult(
      value: value,
      primary: special ?? format(value, context),
      secondary: special == null ? NumberFormatter.formatSecondary(value, notation: context.notation) : null,
      expression: TreeToTokenLowerer.toDisplayText(root),
    );
  }

  /// Evaluates a formula given as plain text (`"1 ÷ 2π"`, `"∫(0, π, sin(x))"`).
  static EvaluationResult evaluateText(
    String text, {
    MathContext context = const MathContext(),
    Map<String, CalcValue>? variables,
    CancellationToken? token,
    math.Random? random,
  }) =>
      evaluateSequence(
        ClipboardSanitizer.toSequence(text, radix: context.baseN?.radix ?? 10, programmer: context.baseN != null),
        context: context,
        variables: variables,
        token: token,
        random: random,
      );

  /// Display string of [value] under [context].
  static String format(CalcValue value, MathContext context, {int prec = DISP_PREC}) =>
      NumberFormatter.formatValue(value, prec: prec, notation: context.notation, radix: context.baseN?.radix);

  /// Builds the pre-computed tables (Spouge coefficients, Gauss-Legendre
  /// nodes). Worker isolates call this once right after they start.
  static void warmUp() {
    GammaCombinatorics.warmUp();
    CalculusEngine.warmUp();
  }
}
