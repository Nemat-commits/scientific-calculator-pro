import 'package:drift/drift.dart';

part 'app_database.g.dart';

/// The history tape: one row per committed calculation.
class CalculationHistory extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// JSON of the editor tree, so an entry can be recalled for editing.
  TextColumn get expressionJson => text()();

  /// Linear text of the expression (searchable).
  TextColumn get expressionText => text()();

  /// Canonical result string.
  TextColumn get resultPrimary => text()();

  /// Exact fraction / engineering form, when there is one.
  TextColumn get resultSecondary => text().nullable()();

  /// Loss-free encoding of the value (`CalcValueCodec`).
  TextColumn get valueEncoded => text()();

  /// Angle unit the calculation ran in (`deg`, `rad`, `grad`).
  TextColumn get angleUnit => text().withDefault(const Constant('deg'))();

  DateTimeColumn get createdAt => dateTime()();
}

/// Named variables: `Ans`, `M`, `A`..`Z`.
class VariableSlots extends Table {
  TextColumn get name => text()();

  /// Loss-free encoding of the value (`CalcValueCodec`).
  TextColumn get valueEncoded => text()();

  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{name};
}

/// The SQLite database of the app.
@DriftDatabase(tables: <Type>[CalculationHistory, VariableSlots])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
