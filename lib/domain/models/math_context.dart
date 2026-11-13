/// Evaluation settings that travel with every expression.
library;

/// Unit of angles consumed / produced by the trigonometric functions.
enum AngleUnit {
  deg('DEG'),
  rad('RAD'),
  grad('GRAD');

  const AngleUnit(this.label);

  /// Badge text shown in the display card.
  final String label;
}

/// How results are written out.
enum NotationMode {
  /// Plain digits when they fit, scientific notation otherwise.
  auto,

  /// Always `d.ddde±x`.
  scientific,

  /// Scientific notation with an exponent that is a multiple of three.
  engineering,
}

/// Binding strength of implied multiplication (`2π`, `2(1+2)`).
enum JuxtapositionMode {
  /// Coefficient juxtaposition (`2π`, `3x`) binds tightly; `2(…)` and
  /// `2sin(…)` behave like an explicit `×` (TI style): `6÷2(1+2) = 9`.
  standardTi('TI'),

  /// Every implied multiplication binds tighter than `×` and `÷`
  /// (Casio style): `6÷2(1+2) = 1`.
  strictCasio('CASIO');

  const JuxtapositionMode(this.label);
  final String label;
}

/// Whether results may leave the real axis.
enum ComplexMode {
  real('REAL'),
  complex('CPLX');

  const ComplexMode(this.label);
  final String label;
}

/// Integer arithmetic settings of the Base-N programmer mode.
final class BaseNConfig {
  const BaseNConfig({this.radix = 10, this.wordSize = 64, this.isSigned = true});

  /// 2, 8, 10 or 16.
  final int radix;

  /// 8, 16, 32 or 64 bits.
  final int wordSize;
  final bool isSigned;

  BaseNConfig copyWith({int? radix, int? wordSize, bool? isSigned}) => BaseNConfig(
        radix: radix ?? this.radix,
        wordSize: wordSize ?? this.wordSize,
        isSigned: isSigned ?? this.isSigned,
      );

  Map<String, Object?> toJson() => {'radix': radix, 'wordSize': wordSize, 'isSigned': isSigned};

  static BaseNConfig fromJson(Map<String, Object?> json) => BaseNConfig(
        radix: json['radix'] as int? ?? 10,
        wordSize: json['wordSize'] as int? ?? 64,
        isSigned: json['isSigned'] as bool? ?? true,
      );
}

/// Immutable bundle of every setting that changes the meaning of an expression.
final class MathContext {
  const MathContext({
    this.angleUnit = AngleUnit.deg,
    this.notation = NotationMode.auto,
    this.juxtaposition = JuxtapositionMode.standardTi,
    this.complexMode = ComplexMode.real,
    this.baseN,
  });

  final AngleUnit angleUnit;
  final NotationMode notation;
  final JuxtapositionMode juxtaposition;
  final ComplexMode complexMode;

  /// Non-null while the Base-N programmer mode evaluates integers.
  final BaseNConfig? baseN;

  bool get isComplex => complexMode == ComplexMode.complex;

  MathContext copyWith({
    AngleUnit? angleUnit,
    NotationMode? notation,
    JuxtapositionMode? juxtaposition,
    ComplexMode? complexMode,
    BaseNConfig? baseN,
    bool clearBaseN = false,
  }) =>
      MathContext(
        angleUnit: angleUnit ?? this.angleUnit,
        notation: notation ?? this.notation,
        juxtaposition: juxtaposition ?? this.juxtaposition,
        complexMode: complexMode ?? this.complexMode,
        baseN: clearBaseN ? null : (baseN ?? this.baseN),
      );

  Map<String, Object?> toJson() => {
        'angleUnit': angleUnit.name,
        'notation': notation.name,
        'juxtaposition': juxtaposition.name,
        'complexMode': complexMode.name,
        if (baseN != null) 'baseN': baseN!.toJson(),
      };

  static MathContext fromJson(Map<String, Object?> json) {
    T pick<T extends Enum>(List<T> values, Object? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);
    final baseN = json['baseN'];
    return MathContext(
      angleUnit: pick(AngleUnit.values, json['angleUnit'], AngleUnit.deg),
      notation: pick(NotationMode.values, json['notation'], NotationMode.auto),
      juxtaposition: pick(JuxtapositionMode.values, json['juxtaposition'], JuxtapositionMode.standardTi),
      complexMode: pick(ComplexMode.values, json['complexMode'], ComplexMode.real),
      baseN: baseN is Map ? BaseNConfig.fromJson(baseN.cast<String, Object?>()) : null,
    );
  }
}
