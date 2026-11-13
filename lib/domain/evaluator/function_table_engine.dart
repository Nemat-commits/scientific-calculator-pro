import 'package:decimal/decimal.dart';

import '../compiler/implicit_mul_normalizer.dart';
import '../compiler/pratt_ast_parser.dart';
import '../compiler/tree_to_token_lowerer.dart';
import '../models/calc_error.dart';
import '../models/calc_value.dart';
import '../models/editor_node.dart';
import '../models/math_context.dart';
import 'ast_evaluator.dart';
import 'cancellation_token.dart';
import 'decimal_math.dart';
import 'number_formatter.dart';

/// One line of an `f(x)` table.
final class FunctionTableRow {
  const FunctionTableRow({required this.x, this.value, this.error});

  /// Formatted abscissa.
  final String x;

  /// Formatted `f(x)`, or `null` when the evaluation failed.
  final String? value;

  /// Reason of the failure (e.g. "Division by zero").
  final String? error;
}

/// Tabulates a function of one variable.
abstract final class FunctionTableEngine {
  /// Hard limit of generated rows.
  static const int maxRows = 200;

  /// Evaluates [function] for `x = start, start + step, …, end`.
  static List<FunctionTableRow> generate({
    required EditorSequence function,
    required Decimal start,
    required Decimal end,
    required Decimal step,
    MathContext context = const MathContext(),
    Map<String, CalcValue>? variables,
    String variable = 'x',
    int precision = 12,
    CancellationToken? token,
  }) {
    if (Dec.isZero(step)) throw const DomainError('The step must not be zero');
    final ascending = Dec.sign(step) > 0;
    if (ascending ? Dec.compare(start, end) > 0 : Dec.compare(start, end) < 0) {
      throw const DomainError('The step points away from the end value');
    }
    final tokens = TreeToTokenLowerer.lower(function);
    if (tokens.isEmpty) throw const SyntaxError('Enter a function of x', position: 0);
    final ast = PrattAstParser.parse(ImplicitMulNormalizer.normalize(tokens, context.juxtaposition));
    final evaluator = AstEvaluator(context: context, variables: variables, token: token);
    final rows = <FunctionTableRow>[];
    var x = start;
    while (rows.length < maxRows && (ascending ? Dec.compare(x, end) <= 0 : Dec.compare(x, end) >= 0)) {
      final label = NumberFormatter.formatDec(x, prec: precision);
      try {
        final v = evaluator.evaluateWith(ast, variable, Values.ofDecimalExact(x));
        rows.add(FunctionTableRow(x: label, value: NumberFormatter.formatValue(v, prec: precision)));
      } on CancelledEvaluationError {
        rethrow;
      } on CalcError catch (e) {
        rows.add(FunctionTableRow(x: label, error: e.headline));
      }
      x = Dec.add(x, step, 1000);
    }
    return rows;
  }
}
