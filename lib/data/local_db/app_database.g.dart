// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CalculationHistoryTable extends CalculationHistory
    with TableInfo<$CalculationHistoryTable, CalculationHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CalculationHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _expressionJsonMeta =
      const VerificationMeta('expressionJson');
  @override
  late final GeneratedColumn<String> expressionJson = GeneratedColumn<String>(
      'expression_json', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _expressionTextMeta =
      const VerificationMeta('expressionText');
  @override
  late final GeneratedColumn<String> expressionText = GeneratedColumn<String>(
      'expression_text', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _resultPrimaryMeta =
      const VerificationMeta('resultPrimary');
  @override
  late final GeneratedColumn<String> resultPrimary = GeneratedColumn<String>(
      'result_primary', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _resultSecondaryMeta =
      const VerificationMeta('resultSecondary');
  @override
  late final GeneratedColumn<String> resultSecondary = GeneratedColumn<String>(
      'result_secondary', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _valueEncodedMeta =
      const VerificationMeta('valueEncoded');
  @override
  late final GeneratedColumn<String> valueEncoded = GeneratedColumn<String>(
      'value_encoded', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _angleUnitMeta =
      const VerificationMeta('angleUnit');
  @override
  late final GeneratedColumn<String> angleUnit = GeneratedColumn<String>(
      'angle_unit', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('deg'));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
      'created_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        expressionJson,
        expressionText,
        resultPrimary,
        resultSecondary,
        valueEncoded,
        angleUnit,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'calculation_history';
  @override
  VerificationContext validateIntegrity(
      Insertable<CalculationHistoryData> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('expression_json')) {
      context.handle(
          _expressionJsonMeta,
          expressionJson.isAcceptableOrUnknown(
              data['expression_json']!, _expressionJsonMeta));
    } else if (isInserting) {
      context.missing(_expressionJsonMeta);
    }
    if (data.containsKey('expression_text')) {
      context.handle(
          _expressionTextMeta,
          expressionText.isAcceptableOrUnknown(
              data['expression_text']!, _expressionTextMeta));
    } else if (isInserting) {
      context.missing(_expressionTextMeta);
    }
    if (data.containsKey('result_primary')) {
      context.handle(
          _resultPrimaryMeta,
          resultPrimary.isAcceptableOrUnknown(
              data['result_primary']!, _resultPrimaryMeta));
    } else if (isInserting) {
      context.missing(_resultPrimaryMeta);
    }
    if (data.containsKey('result_secondary')) {
      context.handle(
          _resultSecondaryMeta,
          resultSecondary.isAcceptableOrUnknown(
              data['result_secondary']!, _resultSecondaryMeta));
    }
    if (data.containsKey('value_encoded')) {
      context.handle(
          _valueEncodedMeta,
          valueEncoded.isAcceptableOrUnknown(
              data['value_encoded']!, _valueEncodedMeta));
    } else if (isInserting) {
      context.missing(_valueEncodedMeta);
    }
    if (data.containsKey('angle_unit')) {
      context.handle(_angleUnitMeta,
          angleUnit.isAcceptableOrUnknown(data['angle_unit']!, _angleUnitMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CalculationHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CalculationHistoryData(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      expressionJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}expression_json'])!,
      expressionText: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}expression_text'])!,
      resultPrimary: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}result_primary'])!,
      resultSecondary: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}result_secondary']),
      valueEncoded: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value_encoded'])!,
      angleUnit: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}angle_unit'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $CalculationHistoryTable createAlias(String alias) {
    return $CalculationHistoryTable(attachedDatabase, alias);
  }
}

class CalculationHistoryData extends DataClass
    implements Insertable<CalculationHistoryData> {
  final int id;

  /// JSON of the editor tree, so an entry can be recalled for editing.
  final String expressionJson;

  /// Linear text of the expression (searchable).
  final String expressionText;

  /// Canonical result string.
  final String resultPrimary;

  /// Exact fraction / engineering form, when there is one.
  final String? resultSecondary;

  /// Loss-free encoding of the value (`CalcValueCodec`).
  final String valueEncoded;

  /// Angle unit the calculation ran in (`deg`, `rad`, `grad`).
  final String angleUnit;
  final DateTime createdAt;
  const CalculationHistoryData(
      {required this.id,
      required this.expressionJson,
      required this.expressionText,
      required this.resultPrimary,
      this.resultSecondary,
      required this.valueEncoded,
      required this.angleUnit,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['expression_json'] = Variable<String>(expressionJson);
    map['expression_text'] = Variable<String>(expressionText);
    map['result_primary'] = Variable<String>(resultPrimary);
    if (!nullToAbsent || resultSecondary != null) {
      map['result_secondary'] = Variable<String>(resultSecondary);
    }
    map['value_encoded'] = Variable<String>(valueEncoded);
    map['angle_unit'] = Variable<String>(angleUnit);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  CalculationHistoryCompanion toCompanion(bool nullToAbsent) {
    return CalculationHistoryCompanion(
      id: Value(id),
      expressionJson: Value(expressionJson),
      expressionText: Value(expressionText),
      resultPrimary: Value(resultPrimary),
      resultSecondary: resultSecondary == null && nullToAbsent
          ? const Value.absent()
          : Value(resultSecondary),
      valueEncoded: Value(valueEncoded),
      angleUnit: Value(angleUnit),
      createdAt: Value(createdAt),
    );
  }

  factory CalculationHistoryData.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CalculationHistoryData(
      id: serializer.fromJson<int>(json['id']),
      expressionJson: serializer.fromJson<String>(json['expressionJson']),
      expressionText: serializer.fromJson<String>(json['expressionText']),
      resultPrimary: serializer.fromJson<String>(json['resultPrimary']),
      resultSecondary: serializer.fromJson<String?>(json['resultSecondary']),
      valueEncoded: serializer.fromJson<String>(json['valueEncoded']),
      angleUnit: serializer.fromJson<String>(json['angleUnit']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'expressionJson': serializer.toJson<String>(expressionJson),
      'expressionText': serializer.toJson<String>(expressionText),
      'resultPrimary': serializer.toJson<String>(resultPrimary),
      'resultSecondary': serializer.toJson<String?>(resultSecondary),
      'valueEncoded': serializer.toJson<String>(valueEncoded),
      'angleUnit': serializer.toJson<String>(angleUnit),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  CalculationHistoryData copyWith(
          {int? id,
          String? expressionJson,
          String? expressionText,
          String? resultPrimary,
          Value<String?> resultSecondary = const Value.absent(),
          String? valueEncoded,
          String? angleUnit,
          DateTime? createdAt}) =>
      CalculationHistoryData(
        id: id ?? this.id,
        expressionJson: expressionJson ?? this.expressionJson,
        expressionText: expressionText ?? this.expressionText,
        resultPrimary: resultPrimary ?? this.resultPrimary,
        resultSecondary: resultSecondary.present
            ? resultSecondary.value
            : this.resultSecondary,
        valueEncoded: valueEncoded ?? this.valueEncoded,
        angleUnit: angleUnit ?? this.angleUnit,
        createdAt: createdAt ?? this.createdAt,
      );
  CalculationHistoryData copyWithCompanion(CalculationHistoryCompanion data) {
    return CalculationHistoryData(
      id: data.id.present ? data.id.value : this.id,
      expressionJson: data.expressionJson.present
          ? data.expressionJson.value
          : this.expressionJson,
      expressionText: data.expressionText.present
          ? data.expressionText.value
          : this.expressionText,
      resultPrimary: data.resultPrimary.present
          ? data.resultPrimary.value
          : this.resultPrimary,
      resultSecondary: data.resultSecondary.present
          ? data.resultSecondary.value
          : this.resultSecondary,
      valueEncoded: data.valueEncoded.present
          ? data.valueEncoded.value
          : this.valueEncoded,
      angleUnit: data.angleUnit.present ? data.angleUnit.value : this.angleUnit,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CalculationHistoryData(')
          ..write('id: $id, ')
          ..write('expressionJson: $expressionJson, ')
          ..write('expressionText: $expressionText, ')
          ..write('resultPrimary: $resultPrimary, ')
          ..write('resultSecondary: $resultSecondary, ')
          ..write('valueEncoded: $valueEncoded, ')
          ..write('angleUnit: $angleUnit, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, expressionJson, expressionText,
      resultPrimary, resultSecondary, valueEncoded, angleUnit, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CalculationHistoryData &&
          other.id == this.id &&
          other.expressionJson == this.expressionJson &&
          other.expressionText == this.expressionText &&
          other.resultPrimary == this.resultPrimary &&
          other.resultSecondary == this.resultSecondary &&
          other.valueEncoded == this.valueEncoded &&
          other.angleUnit == this.angleUnit &&
          other.createdAt == this.createdAt);
}

class CalculationHistoryCompanion
    extends UpdateCompanion<CalculationHistoryData> {
  final Value<int> id;
  final Value<String> expressionJson;
  final Value<String> expressionText;
  final Value<String> resultPrimary;
  final Value<String?> resultSecondary;
  final Value<String> valueEncoded;
  final Value<String> angleUnit;
  final Value<DateTime> createdAt;
  const CalculationHistoryCompanion({
    this.id = const Value.absent(),
    this.expressionJson = const Value.absent(),
    this.expressionText = const Value.absent(),
    this.resultPrimary = const Value.absent(),
    this.resultSecondary = const Value.absent(),
    this.valueEncoded = const Value.absent(),
    this.angleUnit = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  CalculationHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String expressionJson,
    required String expressionText,
    required String resultPrimary,
    this.resultSecondary = const Value.absent(),
    required String valueEncoded,
    this.angleUnit = const Value.absent(),
    required DateTime createdAt,
  })  : expressionJson = Value(expressionJson),
        expressionText = Value(expressionText),
        resultPrimary = Value(resultPrimary),
        valueEncoded = Value(valueEncoded),
        createdAt = Value(createdAt);
  static Insertable<CalculationHistoryData> custom({
    Expression<int>? id,
    Expression<String>? expressionJson,
    Expression<String>? expressionText,
    Expression<String>? resultPrimary,
    Expression<String>? resultSecondary,
    Expression<String>? valueEncoded,
    Expression<String>? angleUnit,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (expressionJson != null) 'expression_json': expressionJson,
      if (expressionText != null) 'expression_text': expressionText,
      if (resultPrimary != null) 'result_primary': resultPrimary,
      if (resultSecondary != null) 'result_secondary': resultSecondary,
      if (valueEncoded != null) 'value_encoded': valueEncoded,
      if (angleUnit != null) 'angle_unit': angleUnit,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  CalculationHistoryCompanion copyWith(
      {Value<int>? id,
      Value<String>? expressionJson,
      Value<String>? expressionText,
      Value<String>? resultPrimary,
      Value<String?>? resultSecondary,
      Value<String>? valueEncoded,
      Value<String>? angleUnit,
      Value<DateTime>? createdAt}) {
    return CalculationHistoryCompanion(
      id: id ?? this.id,
      expressionJson: expressionJson ?? this.expressionJson,
      expressionText: expressionText ?? this.expressionText,
      resultPrimary: resultPrimary ?? this.resultPrimary,
      resultSecondary: resultSecondary ?? this.resultSecondary,
      valueEncoded: valueEncoded ?? this.valueEncoded,
      angleUnit: angleUnit ?? this.angleUnit,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (expressionJson.present) {
      map['expression_json'] = Variable<String>(expressionJson.value);
    }
    if (expressionText.present) {
      map['expression_text'] = Variable<String>(expressionText.value);
    }
    if (resultPrimary.present) {
      map['result_primary'] = Variable<String>(resultPrimary.value);
    }
    if (resultSecondary.present) {
      map['result_secondary'] = Variable<String>(resultSecondary.value);
    }
    if (valueEncoded.present) {
      map['value_encoded'] = Variable<String>(valueEncoded.value);
    }
    if (angleUnit.present) {
      map['angle_unit'] = Variable<String>(angleUnit.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CalculationHistoryCompanion(')
          ..write('id: $id, ')
          ..write('expressionJson: $expressionJson, ')
          ..write('expressionText: $expressionText, ')
          ..write('resultPrimary: $resultPrimary, ')
          ..write('resultSecondary: $resultSecondary, ')
          ..write('valueEncoded: $valueEncoded, ')
          ..write('angleUnit: $angleUnit, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $VariableSlotsTable extends VariableSlots
    with TableInfo<$VariableSlotsTable, VariableSlot> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $VariableSlotsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _valueEncodedMeta =
      const VerificationMeta('valueEncoded');
  @override
  late final GeneratedColumn<String> valueEncoded = GeneratedColumn<String>(
      'value_encoded', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [name, valueEncoded, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'variable_slots';
  @override
  VerificationContext validateIntegrity(Insertable<VariableSlot> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('value_encoded')) {
      context.handle(
          _valueEncodedMeta,
          valueEncoded.isAcceptableOrUnknown(
              data['value_encoded']!, _valueEncodedMeta));
    } else if (isInserting) {
      context.missing(_valueEncodedMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {name};
  @override
  VariableSlot map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return VariableSlot(
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      valueEncoded: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}value_encoded'])!,
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}updated_at'])!,
    );
  }

  @override
  $VariableSlotsTable createAlias(String alias) {
    return $VariableSlotsTable(attachedDatabase, alias);
  }
}

class VariableSlot extends DataClass implements Insertable<VariableSlot> {
  final String name;

  /// Loss-free encoding of the value (`CalcValueCodec`).
  final String valueEncoded;
  final DateTime updatedAt;
  const VariableSlot(
      {required this.name,
      required this.valueEncoded,
      required this.updatedAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['name'] = Variable<String>(name);
    map['value_encoded'] = Variable<String>(valueEncoded);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  VariableSlotsCompanion toCompanion(bool nullToAbsent) {
    return VariableSlotsCompanion(
      name: Value(name),
      valueEncoded: Value(valueEncoded),
      updatedAt: Value(updatedAt),
    );
  }

  factory VariableSlot.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return VariableSlot(
      name: serializer.fromJson<String>(json['name']),
      valueEncoded: serializer.fromJson<String>(json['valueEncoded']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'name': serializer.toJson<String>(name),
      'valueEncoded': serializer.toJson<String>(valueEncoded),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  VariableSlot copyWith(
          {String? name, String? valueEncoded, DateTime? updatedAt}) =>
      VariableSlot(
        name: name ?? this.name,
        valueEncoded: valueEncoded ?? this.valueEncoded,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  VariableSlot copyWithCompanion(VariableSlotsCompanion data) {
    return VariableSlot(
      name: data.name.present ? data.name.value : this.name,
      valueEncoded: data.valueEncoded.present
          ? data.valueEncoded.value
          : this.valueEncoded,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('VariableSlot(')
          ..write('name: $name, ')
          ..write('valueEncoded: $valueEncoded, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(name, valueEncoded, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is VariableSlot &&
          other.name == this.name &&
          other.valueEncoded == this.valueEncoded &&
          other.updatedAt == this.updatedAt);
}

class VariableSlotsCompanion extends UpdateCompanion<VariableSlot> {
  final Value<String> name;
  final Value<String> valueEncoded;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const VariableSlotsCompanion({
    this.name = const Value.absent(),
    this.valueEncoded = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  VariableSlotsCompanion.insert({
    required String name,
    required String valueEncoded,
    required DateTime updatedAt,
    this.rowid = const Value.absent(),
  })  : name = Value(name),
        valueEncoded = Value(valueEncoded),
        updatedAt = Value(updatedAt);
  static Insertable<VariableSlot> custom({
    Expression<String>? name,
    Expression<String>? valueEncoded,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (name != null) 'name': name,
      if (valueEncoded != null) 'value_encoded': valueEncoded,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  VariableSlotsCompanion copyWith(
      {Value<String>? name,
      Value<String>? valueEncoded,
      Value<DateTime>? updatedAt,
      Value<int>? rowid}) {
    return VariableSlotsCompanion(
      name: name ?? this.name,
      valueEncoded: valueEncoded ?? this.valueEncoded,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (valueEncoded.present) {
      map['value_encoded'] = Variable<String>(valueEncoded.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('VariableSlotsCompanion(')
          ..write('name: $name, ')
          ..write('valueEncoded: $valueEncoded, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CalculationHistoryTable calculationHistory =
      $CalculationHistoryTable(this);
  late final $VariableSlotsTable variableSlots = $VariableSlotsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [calculationHistory, variableSlots];
}

typedef $$CalculationHistoryTableCreateCompanionBuilder
    = CalculationHistoryCompanion Function({
  Value<int> id,
  required String expressionJson,
  required String expressionText,
  required String resultPrimary,
  Value<String?> resultSecondary,
  required String valueEncoded,
  Value<String> angleUnit,
  required DateTime createdAt,
});
typedef $$CalculationHistoryTableUpdateCompanionBuilder
    = CalculationHistoryCompanion Function({
  Value<int> id,
  Value<String> expressionJson,
  Value<String> expressionText,
  Value<String> resultPrimary,
  Value<String?> resultSecondary,
  Value<String> valueEncoded,
  Value<String> angleUnit,
  Value<DateTime> createdAt,
});

class $$CalculationHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $CalculationHistoryTable> {
  $$CalculationHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expressionJson => $composableBuilder(
      column: $table.expressionJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expressionText => $composableBuilder(
      column: $table.expressionText,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultPrimary => $composableBuilder(
      column: $table.resultPrimary, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get resultSecondary => $composableBuilder(
      column: $table.resultSecondary,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get angleUnit => $composableBuilder(
      column: $table.angleUnit, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$CalculationHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $CalculationHistoryTable> {
  $$CalculationHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expressionJson => $composableBuilder(
      column: $table.expressionJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expressionText => $composableBuilder(
      column: $table.expressionText,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultPrimary => $composableBuilder(
      column: $table.resultPrimary,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get resultSecondary => $composableBuilder(
      column: $table.resultSecondary,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get angleUnit => $composableBuilder(
      column: $table.angleUnit, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$CalculationHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $CalculationHistoryTable> {
  $$CalculationHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get expressionJson => $composableBuilder(
      column: $table.expressionJson, builder: (column) => column);

  GeneratedColumn<String> get expressionText => $composableBuilder(
      column: $table.expressionText, builder: (column) => column);

  GeneratedColumn<String> get resultPrimary => $composableBuilder(
      column: $table.resultPrimary, builder: (column) => column);

  GeneratedColumn<String> get resultSecondary => $composableBuilder(
      column: $table.resultSecondary, builder: (column) => column);

  GeneratedColumn<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded, builder: (column) => column);

  GeneratedColumn<String> get angleUnit =>
      $composableBuilder(column: $table.angleUnit, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$CalculationHistoryTableTableManager extends RootTableManager<
    _$AppDatabase,
    $CalculationHistoryTable,
    CalculationHistoryData,
    $$CalculationHistoryTableFilterComposer,
    $$CalculationHistoryTableOrderingComposer,
    $$CalculationHistoryTableAnnotationComposer,
    $$CalculationHistoryTableCreateCompanionBuilder,
    $$CalculationHistoryTableUpdateCompanionBuilder,
    (
      CalculationHistoryData,
      BaseReferences<_$AppDatabase, $CalculationHistoryTable,
          CalculationHistoryData>
    ),
    CalculationHistoryData,
    PrefetchHooks Function()> {
  $$CalculationHistoryTableTableManager(
      _$AppDatabase db, $CalculationHistoryTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CalculationHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CalculationHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CalculationHistoryTableAnnotationComposer(
                  $db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> expressionJson = const Value.absent(),
            Value<String> expressionText = const Value.absent(),
            Value<String> resultPrimary = const Value.absent(),
            Value<String?> resultSecondary = const Value.absent(),
            Value<String> valueEncoded = const Value.absent(),
            Value<String> angleUnit = const Value.absent(),
            Value<DateTime> createdAt = const Value.absent(),
          }) =>
              CalculationHistoryCompanion(
            id: id,
            expressionJson: expressionJson,
            expressionText: expressionText,
            resultPrimary: resultPrimary,
            resultSecondary: resultSecondary,
            valueEncoded: valueEncoded,
            angleUnit: angleUnit,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String expressionJson,
            required String expressionText,
            required String resultPrimary,
            Value<String?> resultSecondary = const Value.absent(),
            required String valueEncoded,
            Value<String> angleUnit = const Value.absent(),
            required DateTime createdAt,
          }) =>
              CalculationHistoryCompanion.insert(
            id: id,
            expressionJson: expressionJson,
            expressionText: expressionText,
            resultPrimary: resultPrimary,
            resultSecondary: resultSecondary,
            valueEncoded: valueEncoded,
            angleUnit: angleUnit,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$CalculationHistoryTable,
                        CalculationHistoryData>(table),
                    BaseReferences<_$AppDatabase, $CalculationHistoryTable,
                        CalculationHistoryData>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$CalculationHistoryTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $CalculationHistoryTable,
    CalculationHistoryData,
    $$CalculationHistoryTableFilterComposer,
    $$CalculationHistoryTableOrderingComposer,
    $$CalculationHistoryTableAnnotationComposer,
    $$CalculationHistoryTableCreateCompanionBuilder,
    $$CalculationHistoryTableUpdateCompanionBuilder,
    (
      CalculationHistoryData,
      BaseReferences<_$AppDatabase, $CalculationHistoryTable,
          CalculationHistoryData>
    ),
    CalculationHistoryData,
    PrefetchHooks Function()>;
typedef $$VariableSlotsTableCreateCompanionBuilder = VariableSlotsCompanion
    Function({
  required String name,
  required String valueEncoded,
  required DateTime updatedAt,
  Value<int> rowid,
});
typedef $$VariableSlotsTableUpdateCompanionBuilder = VariableSlotsCompanion
    Function({
  Value<String> name,
  Value<String> valueEncoded,
  Value<DateTime> updatedAt,
  Value<int> rowid,
});

class $$VariableSlotsTableFilterComposer
    extends Composer<_$AppDatabase, $VariableSlotsTable> {
  $$VariableSlotsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));
}

class $$VariableSlotsTableOrderingComposer
    extends Composer<_$AppDatabase, $VariableSlotsTable> {
  $$VariableSlotsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));
}

class $$VariableSlotsTableAnnotationComposer
    extends Composer<_$AppDatabase, $VariableSlotsTable> {
  $$VariableSlotsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get valueEncoded => $composableBuilder(
      column: $table.valueEncoded, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$VariableSlotsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $VariableSlotsTable,
    VariableSlot,
    $$VariableSlotsTableFilterComposer,
    $$VariableSlotsTableOrderingComposer,
    $$VariableSlotsTableAnnotationComposer,
    $$VariableSlotsTableCreateCompanionBuilder,
    $$VariableSlotsTableUpdateCompanionBuilder,
    (
      VariableSlot,
      BaseReferences<_$AppDatabase, $VariableSlotsTable, VariableSlot>
    ),
    VariableSlot,
    PrefetchHooks Function()> {
  $$VariableSlotsTableTableManager(_$AppDatabase db, $VariableSlotsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$VariableSlotsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$VariableSlotsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$VariableSlotsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> name = const Value.absent(),
            Value<String> valueEncoded = const Value.absent(),
            Value<DateTime> updatedAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              VariableSlotsCompanion(
            name: name,
            valueEncoded: valueEncoded,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String name,
            required String valueEncoded,
            required DateTime updatedAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              VariableSlotsCompanion.insert(
            name: name,
            valueEncoded: valueEncoded,
            updatedAt: updatedAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (
                    e.readTable<$VariableSlotsTable, VariableSlot>(table),
                    BaseReferences<_$AppDatabase, $VariableSlotsTable,
                        VariableSlot>(db, table, e)
                  ))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$VariableSlotsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $VariableSlotsTable,
    VariableSlot,
    $$VariableSlotsTableFilterComposer,
    $$VariableSlotsTableOrderingComposer,
    $$VariableSlotsTableAnnotationComposer,
    $$VariableSlotsTableCreateCompanionBuilder,
    $$VariableSlotsTableUpdateCompanionBuilder,
    (
      VariableSlot,
      BaseReferences<_$AppDatabase, $VariableSlotsTable, VariableSlot>
    ),
    VariableSlot,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CalculationHistoryTableTableManager get calculationHistory =>
      $$CalculationHistoryTableTableManager(_db, _db.calculationHistory);
  $$VariableSlotsTableTableManager get variableSlots =>
      $$VariableSlotsTableTableManager(_db, _db.variableSlots);
}
