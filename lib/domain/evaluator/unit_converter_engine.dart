import '../../core/constants/unit_definitions.dart';
import '../math_engine.dart';
import '../models/calc_value.dart';
import 'ast_evaluator.dart';
import 'number_formatter.dart';

/// Bi-directional unit conversion through the SI base unit of each category.
///
/// `base = (value + offset_from) × factor_from`
/// `result = base ÷ factor_to − offset_to`
///
/// All factors are exact fractions, so chains such as inch → mile → inch
/// return exactly the number that was entered.
abstract final class UnitConverterEngine {
  static final Map<String, CalcValue> _cache = <String, CalcValue>{};
  static final AstEvaluator _arithmetic = AstEvaluator();

  static CalcValue _parse(String expression) =>
      _cache[expression] ??= MathEngine.evaluateText(expression).value;

  /// Size of [unit] in base units.
  static CalcValue factorOf(UnitDef unit) => _parse(unit.factor);

  /// Converts [value] from one unit into another unit of the same category.
  static CalcValue convert(CalcValue value, UnitDef from, UnitDef to) {
    if (identical(from, to)) return value;
    final base = _arithmetic.multiply(_arithmetic.add(value, _parse(from.offset)), factorOf(from));
    return _arithmetic.subtract(_arithmetic.divide(base, factorOf(to)), _parse(to.offset));
  }

  /// Converts and formats with [precision] significant digits.
  static String convertFormatted(CalcValue value, UnitDef from, UnitDef to, {int precision = 12}) =>
      NumberFormatter.formatValue(convert(value, from, to), prec: precision);
}
