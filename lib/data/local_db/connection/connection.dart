// Opens the platform's SQLite connection. Platforms without `dart:ffi`
// (the web) get `null` and fall back to the in-memory repository.
export 'unsupported.dart' if (dart.library.ffi) 'native.dart';
