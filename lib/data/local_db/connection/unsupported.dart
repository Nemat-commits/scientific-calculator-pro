import 'package:drift/drift.dart';

/// No SQLite on this platform.
QueryExecutor? openConnection() => null;
