import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/editor/math_print_controller.dart';

/// Snapshot of the expression that is being typed.
///
/// `SharedPreferences` keeps an in-memory copy of its values, so [read] is
/// synchronous: the tree is back on screen in the very first frame after a
/// cold start, before any database has been opened.
class DraftStateStore {
  /// Backed by the platform preferences.
  DraftStateStore(SharedPreferences preferences) : _preferences = preferences;

  /// Volatile store (tests, previews).
  DraftStateStore.memory() : _preferences = null;

  static const String _key = 'draft.v1';

  final SharedPreferences? _preferences;
  String? _memory;

  /// The stored draft, or `null` when there is none (or it is unreadable).
  EditorState? read() {
    final raw = _preferences == null ? _memory : _preferences.getString(_key);
    if (raw == null || raw.isEmpty) return null;
    try {
      return EditorState.fromJson((jsonDecode(raw) as Map<Object?, Object?>).cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  /// Stores [state]; an empty expression clears the draft.
  void write(EditorState state) {
    if (state.isEmpty) return clear();
    final raw = jsonEncode(state.toJson());
    if (_preferences == null) {
      _memory = raw;
    } else {
      unawaited(_preferences.setString(_key, raw));
    }
  }

  void clear() {
    if (_preferences == null) {
      _memory = null;
    } else {
      unawaited(_preferences.remove(_key));
    }
  }
}
