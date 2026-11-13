// Opens the platform's SQLite connection. Platforms without `dart:io`
// (the web) get `null` and fall back to the in-memory repository.
export 'unsupported.dart' if (dart.library.io) 'native.dart';
