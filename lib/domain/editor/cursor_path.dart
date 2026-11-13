import '../models/editor_node.dart';

/// One level of the cursor: a sequence and a child index inside it.
typedef CursorEntry = (String sequenceId, int offset);

/// Immutable stack of `(sequenceId, childIndex)` pairs.
///
/// The bottom entry always addresses the root sequence. While the cursor is
/// inside a composite node that sits at index `j` of its parent sequence, the
/// parent entry holds `j + 1` (the position just right of the composite) and
/// the entry above addresses the slot that contains the caret.
final class CursorPath {
  const CursorPath(this.entries);

  /// Cursor inside the root sequence.
  factory CursorPath.root([int offset = 0]) =>
      CursorPath(List<CursorEntry>.unmodifiable(<CursorEntry>[(EditorSequence.rootId, offset)]));

  factory CursorPath.fromRecords(List<(String sequenceId, int offset)> records) =>
      CursorPath(List<CursorEntry>.unmodifiable(records));

  final List<CursorEntry> entries;

  int get depth => entries.length;

  CursorEntry get top => entries.last;

  /// Sequence that contains the caret.
  String get sequenceId => entries.last.$1;

  /// Caret position inside [sequenceId].
  int get offset => entries.last.$2;

  CursorPath push(String sequenceId, int offset) =>
      CursorPath(List<CursorEntry>.unmodifiable(<CursorEntry>[...entries, (sequenceId, offset)]));

  CursorPath pop() => CursorPath(List<CursorEntry>.unmodifiable(entries.sublist(0, entries.length - 1)));

  CursorPath replaceTop(String sequenceId, int offset) =>
      CursorPath(List<CursorEntry>.unmodifiable(<CursorEntry>[
        ...entries.sublist(0, entries.length - 1),
        (sequenceId, offset),
      ]));

  CursorPath withOffset(int offset) => replaceTop(sequenceId, offset);

  /// Keeps the first [count] entries.
  CursorPath truncate(int count) => CursorPath(List<CursorEntry>.unmodifiable(entries.sublist(0, count)));

  List<(String sequenceId, int offset)> toRecords() => List<(String, int)>.unmodifiable(entries);

  List<Object?> toJson() => <Object?>[
        for (final e in entries) <Object?>[e.$1, e.$2],
      ];

  static CursorPath fromJson(List<Object?> json) => CursorPath(List<CursorEntry>.unmodifiable(<CursorEntry>[
        for (final item in json) ((item as List<Object?>)[0] as String, item[1] as int),
      ]));

  @override
  bool operator ==(Object other) {
    if (other is! CursorPath || other.entries.length != entries.length) return false;
    for (var i = 0; i < entries.length; i++) {
      if (entries[i] != other.entries[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(entries);

  @override
  String toString() => entries.map((e) => '${e.$1}@${e.$2}').join(' > ');
}
