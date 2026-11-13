import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// SQLite file in the app's documents directory, opened on a background
/// isolate so queries never block a frame.
QueryExecutor? openConnection() => LazyDatabase(() async {
      final directory = await getApplicationDocumentsDirectory();
      return NativeDatabase.createInBackground(File(p.join(directory.path, 'calculator.sqlite')));
    });
