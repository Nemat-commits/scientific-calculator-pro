/// Units offered by the converter tab.
///
/// A unit maps onto the base unit of its category through
/// `base = (value + offset) × factor`. Factors are exact wherever the unit is
/// defined exactly (they are parsed as fractions, never as binary floats); the
/// two temperature scales with a shifted zero use [offset].
library;

/// One convertible unit.
final class UnitDef {
  const UnitDef(this.id, this.symbol, this.name, this.factor, {this.offset = '0'});

  final String id;
  final String symbol;
  final String name;

  /// Size of the unit in base units: a decimal, a fraction `a/b`, or an
  /// expression involving `π`.
  final String factor;

  /// Shift applied before scaling (affine temperature scales).
  final String offset;
}

/// A group of units that measure the same quantity.
final class UnitCategory {
  const UnitCategory(this.id, this.name, this.baseSymbol, this.units);

  final String id;
  final String name;

  /// Symbol of the unit whose factor is 1.
  final String baseSymbol;
  final List<UnitDef> units;

  UnitDef unit(String unitId) => units.firstWhere((u) => u.id == unitId);

  /// The unit a conversion starts from: the base unit, except for
  /// temperatures, where the everyday scale comes first.
  UnitDef get defaultUnit =>
      id == 'temperature' ? units.first : units.firstWhere((u) => u.symbol == baseSymbol, orElse: () => units.first);
}

/// The 12 unit categories.
abstract final class UnitDefinitions {
  static const List<UnitCategory> categories = <UnitCategory>[
    UnitCategory('length', 'Length', 'm', <UnitDef>[
      UnitDef('nm', 'nm', 'Nanometre', '1e-9'),
      UnitDef('um', 'µm', 'Micrometre', '1e-6'),
      UnitDef('mm', 'mm', 'Millimetre', '0.001'),
      UnitDef('cm', 'cm', 'Centimetre', '0.01'),
      UnitDef('m', 'm', 'Metre', '1'),
      UnitDef('km', 'km', 'Kilometre', '1000'),
      UnitDef('in', 'in', 'Inch', '0.0254'),
      UnitDef('ft', 'ft', 'Foot', '0.3048'),
      UnitDef('yd', 'yd', 'Yard', '0.9144'),
      UnitDef('mi', 'mi', 'Mile', '1609.344'),
      UnitDef('nmi', 'nmi', 'Nautical mile', '1852'),
      UnitDef('au', 'au', 'Astronomical unit', '149597870700'),
      UnitDef('ly', 'ly', 'Light-year', '9460730472580800'),
    ]),
    UnitCategory('mass', 'Mass', 'kg', <UnitDef>[
      UnitDef('ug', 'µg', 'Microgram', '1e-9'),
      UnitDef('mg', 'mg', 'Milligram', '1e-6'),
      UnitDef('g', 'g', 'Gram', '0.001'),
      UnitDef('kg', 'kg', 'Kilogram', '1'),
      UnitDef('t', 't', 'Tonne', '1000'),
      UnitDef('ct', 'ct', 'Carat', '0.0002'),
      UnitDef('oz', 'oz', 'Ounce', '0.028349523125'),
      UnitDef('lb', 'lb', 'Pound', '0.45359237'),
      UnitDef('st', 'st', 'Stone', '6.35029318'),
      UnitDef('ton_us', 'sh tn', 'Short ton (US)', '907.18474'),
      UnitDef('ton_uk', 'long tn', 'Long ton (UK)', '1016.0469088'),
    ]),
    UnitCategory('temperature', 'Temperature', 'K', <UnitDef>[
      UnitDef('c', '°C', 'Celsius', '1', offset: '273.15'),
      UnitDef('f', '°F', 'Fahrenheit', '5/9', offset: '459.67'),
      UnitDef('k', 'K', 'Kelvin', '1'),
      UnitDef('r', '°R', 'Rankine', '5/9'),
    ]),
    UnitCategory('area', 'Area', 'm²', <UnitDef>[
      UnitDef('mm2', 'mm²', 'Square millimetre', '1e-6'),
      UnitDef('cm2', 'cm²', 'Square centimetre', '1e-4'),
      UnitDef('m2', 'm²', 'Square metre', '1'),
      UnitDef('ha', 'ha', 'Hectare', '10000'),
      UnitDef('km2', 'km²', 'Square kilometre', '1e6'),
      UnitDef('in2', 'in²', 'Square inch', '0.00064516'),
      UnitDef('ft2', 'ft²', 'Square foot', '0.09290304'),
      UnitDef('yd2', 'yd²', 'Square yard', '0.83612736'),
      UnitDef('acre', 'ac', 'Acre', '4046.8564224'),
      UnitDef('mi2', 'mi²', 'Square mile', '2589988.110336'),
    ]),
    UnitCategory('volume', 'Volume', 'm³', <UnitDef>[
      UnitDef('ml', 'mL', 'Millilitre', '1e-6'),
      UnitDef('l', 'L', 'Litre', '0.001'),
      UnitDef('m3', 'm³', 'Cubic metre', '1'),
      UnitDef('tsp', 'tsp', 'Teaspoon (US)', '157725491/32000000000000'),
      UnitDef('tbsp', 'tbsp', 'Tablespoon (US)', '473176473/32000000000000'),
      UnitDef('floz', 'fl oz', 'Fluid ounce (US)', '473176473/16000000000000'),
      UnitDef('cup', 'cup', 'Cup (US)', '473176473/2000000000000'),
      UnitDef('pt', 'pt', 'Pint (US)', '473176473/1000000000000'),
      UnitDef('qt', 'qt', 'Quart (US)', '473176473/500000000000'),
      UnitDef('gal', 'gal', 'Gallon (US)', '0.003785411784'),
      UnitDef('gal_uk', 'gal UK', 'Gallon (imperial)', '0.00454609'),
      UnitDef('in3', 'in³', 'Cubic inch', '0.000016387064'),
      UnitDef('ft3', 'ft³', 'Cubic foot', '0.028316846592'),
    ]),
    UnitCategory('speed', 'Speed', 'm/s', <UnitDef>[
      UnitDef('mps', 'm/s', 'Metre per second', '1'),
      UnitDef('kmh', 'km/h', 'Kilometre per hour', '5/18'),
      UnitDef('mph', 'mph', 'Mile per hour', '0.44704'),
      UnitDef('kn', 'kn', 'Knot', '463/900'),
      UnitDef('fps', 'ft/s', 'Foot per second', '0.3048'),
      UnitDef('c', 'c', 'Speed of light', '299792458'),
    ]),
    UnitCategory('time', 'Time', 's', <UnitDef>[
      UnitDef('ns', 'ns', 'Nanosecond', '1e-9'),
      UnitDef('us', 'µs', 'Microsecond', '1e-6'),
      UnitDef('ms', 'ms', 'Millisecond', '0.001'),
      UnitDef('s', 's', 'Second', '1'),
      UnitDef('min', 'min', 'Minute', '60'),
      UnitDef('h', 'h', 'Hour', '3600'),
      UnitDef('d', 'd', 'Day', '86400'),
      UnitDef('wk', 'wk', 'Week', '604800'),
      UnitDef('mo', 'mo', 'Month (1/12 Julian year)', '2629800'),
      UnitDef('yr', 'yr', 'Julian year', '31557600'),
    ]),
    UnitCategory('data', 'Data', 'B', <UnitDef>[
      UnitDef('bit', 'bit', 'Bit', '0.125'),
      UnitDef('b', 'B', 'Byte', '1'),
      UnitDef('kb', 'kB', 'Kilobyte', '1000'),
      UnitDef('mb', 'MB', 'Megabyte', '1e6'),
      UnitDef('gb', 'GB', 'Gigabyte', '1e9'),
      UnitDef('tb', 'TB', 'Terabyte', '1e12'),
      UnitDef('kib', 'KiB', 'Kibibyte', '1024'),
      UnitDef('mib', 'MiB', 'Mebibyte', '1048576'),
      UnitDef('gib', 'GiB', 'Gibibyte', '1073741824'),
      UnitDef('tib', 'TiB', 'Tebibyte', '1099511627776'),
    ]),
    UnitCategory('pressure', 'Pressure', 'Pa', <UnitDef>[
      UnitDef('pa', 'Pa', 'Pascal', '1'),
      UnitDef('kpa', 'kPa', 'Kilopascal', '1000'),
      UnitDef('mpa', 'MPa', 'Megapascal', '1e6'),
      UnitDef('mbar', 'mbar', 'Millibar', '100'),
      UnitDef('bar', 'bar', 'Bar', '100000'),
      UnitDef('atm', 'atm', 'Standard atmosphere', '101325'),
      UnitDef('torr', 'Torr', 'Torr', '20265/152'),
      UnitDef('mmhg', 'mmHg', 'Millimetre of mercury', '133.322387415'),
      UnitDef('inhg', 'inHg', 'Inch of mercury', '3386.389'),
      UnitDef('psi', 'psi', 'Pound per square inch', '8896443230521/1290320000'),
    ]),
    UnitCategory('energy', 'Energy', 'J', <UnitDef>[
      UnitDef('ev', 'eV', 'Electronvolt', '1.602176634e-19'),
      UnitDef('erg', 'erg', 'Erg', '1e-7'),
      UnitDef('j', 'J', 'Joule', '1'),
      UnitDef('kj', 'kJ', 'Kilojoule', '1000'),
      UnitDef('cal', 'cal', 'Calorie (thermochemical)', '4.184'),
      UnitDef('kcal', 'kcal', 'Kilocalorie', '4184'),
      UnitDef('wh', 'Wh', 'Watt-hour', '3600'),
      UnitDef('kwh', 'kWh', 'Kilowatt-hour', '3600000'),
      UnitDef('btu', 'BTU', 'British thermal unit (IT)', '1055.05585262'),
      UnitDef('ftlbf', 'ft·lbf', 'Foot-pound force', '3389544870828501/2500000000000000'),
    ]),
    UnitCategory('power', 'Power', 'W', <UnitDef>[
      UnitDef('mw', 'mW', 'Milliwatt', '0.001'),
      UnitDef('w', 'W', 'Watt', '1'),
      UnitDef('kw', 'kW', 'Kilowatt', '1000'),
      UnitDef('megaw', 'MW', 'Megawatt', '1e6'),
      UnitDef('hp', 'hp', 'Horsepower (mechanical)', '37284993579113511/50000000000000'),
      UnitDef('ps', 'PS', 'Horsepower (metric)', '735.49875'),
      UnitDef('btuh', 'BTU/h', 'BTU per hour', '52752792631/180000000000'),
      UnitDef('ftlbfs', 'ft·lbf/s', 'Foot-pound force per second', '3389544870828501/2500000000000000'),
    ]),
    UnitCategory('angle', 'Angle', '°', <UnitDef>[
      UnitDef('deg', '°', 'Degree', '1'),
      UnitDef('rad', 'rad', 'Radian', '180/π'),
      UnitDef('grad', 'gon', 'Gradian', '0.9'),
      UnitDef('turn', 'tr', 'Turn', '360'),
      UnitDef('arcmin', '′', 'Arcminute', '1/60'),
      UnitDef('arcsec', '″', 'Arcsecond', '1/3600'),
      UnitDef('mrad', 'mrad', 'Milliradian', '0.18/π'),
    ]),
  ];

  static UnitCategory category(String id) => categories.firstWhere((c) => c.id == id);
}
