import 'package:decimal/decimal.dart';

import '../../domain/evaluator/decimal_math.dart';

/// A CODATA / SI physical constant offered by the converter tab.
final class PhysicalConstant {
  const PhysicalConstant({
    required this.symbol,
    required this.name,
    required this.value,
    required this.unit,
    this.exact = false,
  });

  /// Token inserted into the editor (also the lookup key of the evaluator).
  /// An underscore introduces a subscript: `m_e` is drawn as mₑ.
  final String symbol;
  final String name;

  /// Decimal literal in SI units.
  final String value;
  final String unit;

  /// Whether the SI defines the value exactly.
  final bool exact;
}

/// High-precision mathematical constants (100 decimal digits each).
abstract final class MathConstants {
  // ignore: constant_identifier_names
  static const String PI_100 =
      '3.1415926535897932384626433832795028841971693993751058209749445923078164062862089986280348253421170680';

  // ignore: constant_identifier_names
  static const String E_100 =
      '2.7182818284590452353602874713526624977572470936999595749669676277240766303535475945713821785251664274';

  // ignore: constant_identifier_names
  static const String LN2_100 =
      '0.6931471805599453094172321214581765680755001343602552541206800094933936219696947156058633269964186875';

  // ignore: constant_identifier_names
  static const String LN10_100 =
      '2.3025850929940456840179914546843642076011014886287729760333279009675726096773524802359972050895982983';

  // ignore: constant_identifier_names
  static const String PHI_100 =
      '1.6180339887498948482045868343656381177203091798057628621354486227052604628189024497072072041893911375';

  /// Digits of the stored constants that are safe to rely on.
  static const int reliableDigits = 98;

  static final Decimal pi100 = Dec.parse(PI_100);
  static final Decimal e100 = Dec.parse(E_100);
  static final Decimal ln2x100 = Dec.parse(LN2_100);
  static final Decimal ln10x100 = Dec.parse(LN10_100);
  static final Decimal phi100 = Dec.parse(PHI_100);

  static final Map<int, Decimal> _piCache = <int, Decimal>{};
  static final Map<int, Decimal> _ln2Cache = <int, Decimal>{};
  static final Map<int, Decimal> _ln10Cache = <int, Decimal>{};

  static int _clamp(int prec) => prec > reliableDigits ? reliableDigits : prec;

  /// pi rounded to [prec] significant digits (at most [reliableDigits]).
  static Decimal pi([int prec = WORK_PREC]) => _piCache[prec] ??= Dec.round(pi100, _clamp(prec));

  /// ln 2 rounded to [prec] significant digits.
  static Decimal ln2([int prec = WORK_PREC]) => _ln2Cache[prec] ??= Dec.round(ln2x100, _clamp(prec));

  /// ln 10 rounded to [prec] significant digits.
  static Decimal ln10([int prec = WORK_PREC]) => _ln10Cache[prec] ??= Dec.round(ln10x100, _clamp(prec));

  /// Euler's number at working precision.
  static final Decimal e = Dec.round(e100, WORK_PREC);

  /// Golden ratio at working precision.
  static final Decimal phi = Dec.round(phi100, WORK_PREC);

  /// Physical constants (CODATA 2022 recommended values, SI units).
  static const List<PhysicalConstant> codata = <PhysicalConstant>[
    PhysicalConstant(symbol: 'c_0', name: 'Speed of light in vacuum', value: '299792458', unit: 'm/s', exact: true),
    PhysicalConstant(symbol: 'h', name: 'Planck constant', value: '6.62607015e-34', unit: 'J·s', exact: true),
    PhysicalConstant(
        symbol: 'ħ',
        name: 'Reduced Planck constant',
        value: '1.054571817646156391262428003302280744722826330020e-34',
        unit: 'J·s',
        exact: true),
    PhysicalConstant(symbol: 'q_e', name: 'Elementary charge', value: '1.602176634e-19', unit: 'C', exact: true),
    PhysicalConstant(symbol: 'k_B', name: 'Boltzmann constant', value: '1.380649e-23', unit: 'J/K', exact: true),
    PhysicalConstant(symbol: 'N_A', name: 'Avogadro constant', value: '6.02214076e23', unit: '1/mol', exact: true),
    PhysicalConstant(
        symbol: 'R', name: 'Molar gas constant', value: '8.31446261815324', unit: 'J/(mol·K)', exact: true),
    PhysicalConstant(symbol: 'F', name: 'Faraday constant', value: '96485.3321233100184', unit: 'C/mol', exact: true),
    PhysicalConstant(symbol: 'G', name: 'Newtonian constant of gravitation', value: '6.67430e-11', unit: 'm³/(kg·s²)'),
    PhysicalConstant(
        symbol: 'g_0', name: 'Standard acceleration of gravity', value: '9.80665', unit: 'm/s²', exact: true),
    PhysicalConstant(symbol: 'm_e', name: 'Electron mass', value: '9.1093837139e-31', unit: 'kg'),
    PhysicalConstant(symbol: 'm_p', name: 'Proton mass', value: '1.67262192595e-27', unit: 'kg'),
    PhysicalConstant(symbol: 'm_n', name: 'Neutron mass', value: '1.67492750056e-27', unit: 'kg'),
    PhysicalConstant(symbol: 'm_u', name: 'Atomic mass constant', value: '1.66053906892e-27', unit: 'kg'),
    PhysicalConstant(symbol: 'ε_0', name: 'Vacuum electric permittivity', value: '8.8541878188e-12', unit: 'F/m'),
    PhysicalConstant(symbol: 'μ_0', name: 'Vacuum magnetic permeability', value: '1.25663706127e-6', unit: 'N/A²'),
    PhysicalConstant(symbol: 'α', name: 'Fine-structure constant', value: '7.2973525643e-3', unit: ''),
    PhysicalConstant(symbol: 'R_∞', name: 'Rydberg constant', value: '10973731.568157', unit: '1/m'),
    PhysicalConstant(symbol: 'a_0', name: 'Bohr radius', value: '5.29177210544e-11', unit: 'm'),
    PhysicalConstant(symbol: 'μ_B', name: 'Bohr magneton', value: '9.2740100657e-24', unit: 'J/T'),
    PhysicalConstant(
        symbol: 'σ',
        name: 'Stefan-Boltzmann constant',
        value: '5.670374419184429453970996731889230875840122970291e-8',
        unit: 'W/(m²·K⁴)',
        exact: true),
    PhysicalConstant(
        symbol: 'V_m',
        name: 'Molar volume of an ideal gas (273.15 K, 101.325 kPa)',
        value: '0.02241396954501413773501110289',
        unit: 'm³/mol',
        exact: true),
    PhysicalConstant(symbol: 'atm', name: 'Standard atmosphere', value: '101325', unit: 'Pa', exact: true),
    PhysicalConstant(symbol: 'eV', name: 'Electron volt', value: '1.602176634e-19', unit: 'J', exact: true),
  ];

  static final Map<String, PhysicalConstant> _codataBySymbol = <String, PhysicalConstant>{
    for (final c in codata) c.symbol: c,
  };

  /// Looks a physical constant up by its editor symbol.
  static PhysicalConstant? physical(String symbol) => _codataBySymbol[symbol];
}
