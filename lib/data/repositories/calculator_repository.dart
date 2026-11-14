import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/math_context.dart';
import '../local_db/app_database.dart';

/// One line of the history tape.
final class HistoryEntry {
  const HistoryEntry({
    required this.id,
    required this.expressionJson,
    required this.expressionText,
    required this.resultPrimary,
    required this.valueEncoded,
    required this.createdAt,
    this.resultSecondary,
    this.angleUnit = 'deg',
  });

  final int id;
  final String expressionJson;
  final String expressionText;
  final String resultPrimary;
  final String? resultSecondary;
  final String valueEncoded;
  final String angleUnit;
  final DateTime createdAt;
}

/// User preferences that survive a restart.
final class CalculatorSettings {
  const CalculatorSettings({
    this.angleUnit = AngleUnit.deg,
    this.juxtaposition = JuxtapositionMode.standardTi,
    this.complexEnabled = false,
    this.hapticsEnabled = true,
    this.engineeringNotation = false,
  });

  final AngleUnit angleUnit;
  final JuxtapositionMode juxtaposition;
  final bool complexEnabled;
  final bool hapticsEnabled;

  /// Results are written with exponents that are multiples of three (ENG).
  final bool engineeringNotation;

  CalculatorSettings copyWith({
    AngleUnit? angleUnit,
    JuxtapositionMode? juxtaposition,
    bool? complexEnabled,
    bool? hapticsEnabled,
    bool? engineeringNotation,
  }) =>
      CalculatorSettings(
        angleUnit: angleUnit ?? this.angleUnit,
        juxtaposition: juxtaposition ?? this.juxtaposition,
        complexEnabled: complexEnabled ?? this.complexEnabled,
        hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
        engineeringNotation: engineeringNotation ?? this.engineeringNotation,
      );

  Map<String, Object?> toJson() => <String, Object?>{
        'angleUnit': angleUnit.name,
        'juxtaposition': juxtaposition.name,
        'complex': complexEnabled,
        'haptics': hapticsEnabled,
        'engineering': engineeringNotation,
      };

  static CalculatorSettings fromJson(Map<String, Object?> json) => CalculatorSettings(
        angleUnit: AngleUnit.values.firstWhere((u) => u.name == json['angleUnit'], orElse: () => AngleUnit.deg),
        juxtaposition: JuxtapositionMode.values
            .firstWhere((m) => m.name == json['juxtaposition'], orElse: () => JuxtapositionMode.standardTi),
        complexEnabled: json['complex'] == true,
        hapticsEnabled: json['haptics'] != false,
        engineeringNotation: json['engineering'] == true,
      );
}

/// Persistence of history, variables (`A`..`Z`, `M`, `Ans`) and settings.
abstract interface class CalculatorRepository {
  /// Newest first; [query] filters on expression and result text.
  Future<List<HistoryEntry>> history({String query = '', int limit = 300});

  Future<HistoryEntry> addHistory({
    required String expressionJson,
    required String expressionText,
    required String resultPrimary,
    required String valueEncoded,
    String? resultSecondary,
    String angleUnit = 'deg',
  });

  Future<void> deleteHistory(int id);

  Future<void> clearHistory();

  /// All stored variables, encoded with `CalcValueCodec`.
  Future<Map<String, String>> variables();

  Future<void> saveVariable(String name, String valueEncoded);

  Future<void> deleteVariable(String name);

  CalculatorSettings loadSettings();

  void saveSettings(CalculatorSettings settings);

  Future<void> close();
}

/// SQLite (Drift) + SharedPreferences implementation.
class DriftCalculatorRepository implements CalculatorRepository {
  DriftCalculatorRepository(this._db, this._preferences);

  static const String _settingsKey = 'settings.v1';

  final AppDatabase _db;
  final SharedPreferences _preferences;

  static HistoryEntry _entry(CalculationHistoryData row) => HistoryEntry(
        id: row.id,
        expressionJson: row.expressionJson,
        expressionText: row.expressionText,
        resultPrimary: row.resultPrimary,
        resultSecondary: row.resultSecondary,
        valueEncoded: row.valueEncoded,
        angleUnit: row.angleUnit,
        createdAt: row.createdAt,
      );

  @override
  Future<List<HistoryEntry>> history({String query = '', int limit = 300}) async {
    final select = _db.select(_db.calculationHistory);
    final needle = query.trim();
    if (needle.isNotEmpty) {
      final pattern = '%${needle.replaceAll('%', r'\%').replaceAll('_', r'\_')}%';
      select.where(
        (t) => t.expressionText.like(pattern, escapeChar: r'\') | t.resultPrimary.like(pattern, escapeChar: r'\'),
      );
    }
    select
      ..orderBy(<OrderingTerm Function($CalculationHistoryTable)>[(t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    final rows = await select.get();
    return rows.map(_entry).toList();
  }

  @override
  Future<HistoryEntry> addHistory({
    required String expressionJson,
    required String expressionText,
    required String resultPrimary,
    required String valueEncoded,
    String? resultSecondary,
    String angleUnit = 'deg',
  }) async {
    final now = DateTime.now();
    final id = await _db.into(_db.calculationHistory).insert(
          CalculationHistoryCompanion.insert(
            expressionJson: expressionJson,
            expressionText: expressionText,
            resultPrimary: resultPrimary,
            resultSecondary: Value<String?>(resultSecondary),
            valueEncoded: valueEncoded,
            angleUnit: Value<String>(angleUnit),
            createdAt: now,
          ),
        );
    return HistoryEntry(
      id: id,
      expressionJson: expressionJson,
      expressionText: expressionText,
      resultPrimary: resultPrimary,
      resultSecondary: resultSecondary,
      valueEncoded: valueEncoded,
      angleUnit: angleUnit,
      createdAt: now,
    );
  }

  @override
  Future<void> deleteHistory(int id) async {
    await (_db.delete(_db.calculationHistory)..where((t) => t.id.equals(id))).go();
  }

  @override
  Future<void> clearHistory() async {
    await _db.delete(_db.calculationHistory).go();
  }

  @override
  Future<Map<String, String>> variables() async {
    final rows = await _db.select(_db.variableSlots).get();
    return <String, String>{for (final row in rows) row.name: row.valueEncoded};
  }

  @override
  Future<void> saveVariable(String name, String valueEncoded) async {
    await _db.into(_db.variableSlots).insertOnConflictUpdate(
          VariableSlotsCompanion.insert(name: name, valueEncoded: valueEncoded, updatedAt: DateTime.now()),
        );
  }

  @override
  Future<void> deleteVariable(String name) async {
    await (_db.delete(_db.variableSlots)..where((t) => t.name.equals(name))).go();
  }

  @override
  CalculatorSettings loadSettings() {
    final raw = _preferences.getString(_settingsKey);
    if (raw == null) return const CalculatorSettings();
    try {
      return CalculatorSettings.fromJson((jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>());
    } on Object {
      return const CalculatorSettings();
    }
  }

  @override
  void saveSettings(CalculatorSettings settings) {
    unawaited(_preferences.setString(_settingsKey, jsonEncode(settings.toJson())));
  }

  @override
  Future<void> close() => _db.close();
}

/// Volatile implementation (widget tests, platforms without SQLite).
class InMemoryCalculatorRepository implements CalculatorRepository {
  InMemoryCalculatorRepository({CalculatorSettings settings = const CalculatorSettings()}) : _settings = settings;

  final List<HistoryEntry> _history = <HistoryEntry>[];
  final Map<String, String> _variables = <String, String>{};
  CalculatorSettings _settings;
  int _nextId = 1;

  @override
  Future<List<HistoryEntry>> history({String query = '', int limit = 300}) async {
    final needle = query.trim().toLowerCase();
    final matches = _history.reversed.where(
      (e) =>
          needle.isEmpty ||
          e.expressionText.toLowerCase().contains(needle) ||
          e.resultPrimary.toLowerCase().contains(needle),
    );
    return matches.take(limit).toList();
  }

  @override
  Future<HistoryEntry> addHistory({
    required String expressionJson,
    required String expressionText,
    required String resultPrimary,
    required String valueEncoded,
    String? resultSecondary,
    String angleUnit = 'deg',
  }) async {
    final entry = HistoryEntry(
      id: _nextId++,
      expressionJson: expressionJson,
      expressionText: expressionText,
      resultPrimary: resultPrimary,
      resultSecondary: resultSecondary,
      valueEncoded: valueEncoded,
      angleUnit: angleUnit,
      createdAt: DateTime.now(),
    );
    _history.add(entry);
    return entry;
  }

  @override
  Future<void> deleteHistory(int id) async => _history.removeWhere((e) => e.id == id);

  @override
  Future<void> clearHistory() async => _history.clear();

  @override
  Future<Map<String, String>> variables() async => Map<String, String>.of(_variables);

  @override
  Future<void> saveVariable(String name, String valueEncoded) async => _variables[name] = valueEncoded;

  @override
  Future<void> deleteVariable(String name) async => _variables.remove(name);

  @override
  CalculatorSettings loadSettings() => _settings;

  @override
  void saveSettings(CalculatorSettings settings) => _settings = settings;

  @override
  Future<void> close() async {}
}
