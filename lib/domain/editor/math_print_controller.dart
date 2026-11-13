import '../models/editor_node.dart';
import 'cursor_path.dart';

/// Deepest allowed nesting of fractions, roots and powers. Templates
/// requested below that depth are inserted as inline parenthesised tokens.
// ignore: constant_identifier_names
const int MAX_TREE_DEPTH = 4;

/// Directions understood by [MathPrintController.move].
enum CursorDirection { left, right, up, down }

/// An expression tree together with its caret.
final class EditorState {
  const EditorState(this.root, this.cursor);

  factory EditorState.empty() => EditorState(EditorSequence.root(), CursorPath.root());

  /// A tree with the caret parked at its end.
  factory EditorState.atEnd(EditorSequence root) => EditorState(root, CursorPath.root(root.length));

  final EditorSequence root;
  final CursorPath cursor;

  bool get isEmpty => root.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{'root': root.toJson(), 'cursor': cursor.toJson()};

  static EditorState fromJson(Map<String, Object?> json) {
    final root = EditorSequence.fromJson((json['root'] as Map<Object?, Object?>).cast<String, Object?>());
    final rawCursor = json['cursor'];
    final cursor = rawCursor is List<Object?> ? CursorPath.fromJson(rawCursor) : CursorPath.root(root.length);
    return MathPrintController.normalize(EditorState(root, cursor));
  }
}

/// Pure editing operations on an [EditorState].
///
/// Every operation returns a new state; trees are never mutated in place, so
/// earlier states stay valid for undo / redo.
abstract final class MathPrintController {
  // ------------------------------------------------------------------ queries

  /// Sequences along the cursor path, root first.
  static List<EditorSequence> _chain(EditorState s) {
    final chain = <EditorSequence>[s.root];
    final entries = s.cursor.entries;
    for (var i = 1; i < entries.length; i++) {
      final node = chain.last.children[entries[i - 1].$2 - 1];
      chain.add(node.slots.firstWhere((slot) => slot.id == entries[i].$1));
    }
    return chain;
  }

  /// Composite node that owns the slot at [level] (`level >= 1`).
  static EditorNode _ownerAt(List<EditorSequence> chain, CursorPath path, int level) =>
      chain[level - 1].children[path.entries[level - 1].$2 - 1];

  /// Whether [path] addresses an existing position of [root].
  static bool isValid(EditorSequence root, CursorPath path) {
    final entries = path.entries;
    if (entries.isEmpty || entries.first.$1 != root.id) return false;
    var seq = root;
    for (var i = 0; i < entries.length; i++) {
      final offset = entries[i].$2;
      if (offset < 0 || offset > seq.length) return false;
      if (i + 1 == entries.length) return true;
      if (offset == 0) return false;
      final node = seq.children[offset - 1];
      EditorSequence? next;
      for (final slot in node.slots) {
        if (slot.id == entries[i + 1].$1) next = slot;
      }
      if (next == null) return false;
      seq = next;
    }
    return true;
  }

  /// Repairs a stale caret by parking it at the end of the expression.
  static EditorState normalize(EditorState s) =>
      isValid(s.root, s.cursor) ? s : EditorState(s.root, CursorPath.root(s.root.length));

  /// Sequence that currently holds the caret.
  static EditorSequence currentSequence(EditorState s) => _chain(s).last;

  /// Parentheses that are still open around the caret: in the slot it is in
  /// and in every slot that encloses it.
  static int openParentheses(EditorState s) => _chain(s).fold(0, (count, seq) => count + seq.unclosedParentheses);

  /// The caret at the end of the argument that follows the one it is in, or
  /// `null` when the caret is not inside a function call with a further
  /// argument (the `,` key).
  static EditorState? nextArgument(EditorState s) {
    final chain = _chain(s);
    for (var level = chain.length - 1; level >= 1; level--) {
      final owner = _ownerAt(chain, s.cursor, level);
      if (owner is! FunctionCallEditorNode) continue;
      final slots = owner.argSlots;
      final index = slots.indexWhere((slot) => slot.id == chain[level].id);
      if (index >= 0 && index + 1 < slots.length) {
        final next = slots[index + 1];
        return EditorState(s.root, s.cursor.truncate(level).push(next.id, next.length));
      }
    }
    return null;
  }

  /// Number of fractions / roots / powers enclosing the caret.
  static int structuralDepth(EditorState s) {
    final chain = _chain(s);
    var depth = 0;
    for (var level = 1; level < chain.length; level++) {
      if (_ownerAt(chain, s.cursor, level).isStructural) depth++;
    }
    return depth;
  }

  /// Cursor path that places the caret at [offset] of the sequence [id]
  /// (used for tap-to-position). `null` when the sequence does not exist.
  static CursorPath? pathTo(EditorSequence root, String id, int offset) {
    List<CursorEntry>? walk(EditorSequence seq) {
      if (seq.id == id) {
        final clamped = offset < 0 ? 0 : (offset > seq.length ? seq.length : offset);
        return <CursorEntry>[(seq.id, clamped)];
      }
      for (var i = 0; i < seq.length; i++) {
        for (final slot in seq.children[i].slots) {
          final sub = walk(slot);
          if (sub != null) return <CursorEntry>[(seq.id, i + 1), ...sub];
        }
      }
      return null;
    }

    final entries = walk(root);
    return entries == null ? null : CursorPath(List<CursorEntry>.unmodifiable(entries));
  }

  /// Rebuilds the tree after the sequence at the top of [path] was replaced
  /// by [newTop]; untouched branches are shared with the old tree.
  static EditorSequence _rebuild(List<EditorSequence> chain, CursorPath path, EditorSequence newTop) {
    var current = newTop;
    for (var level = chain.length - 2; level >= 0; level--) {
      final parent = chain[level];
      final index = path.entries[level].$2 - 1;
      final node = parent.children[index];
      final replaced = node.withSlots(<EditorSequence>[
        for (final slot in node.slots) slot.id == current.id ? current : slot,
      ]);
      current = parent.withChildren(<EditorNode>[...parent.children]..[index] = replaced);
    }
    return current;
  }

  /// Slots the caret may visit. The (hidden) degree of a plain square root is
  /// skipped unless the caret already sits in it.
  static List<EditorSequence> _navigableSlots(EditorNode node, String? currentId) {
    if (node is RootNode && node.degree.isEmpty && node.degree.id != currentId) {
      return <EditorSequence>[node.radicand];
    }
    return node.slots;
  }

  // ------------------------------------------------------------------ editing

  /// Inserts [nodes] at the caret and moves the caret behind them.
  static EditorState insert(EditorState s, List<EditorNode> nodes) {
    if (nodes.isEmpty) return s;
    final chain = _chain(s);
    final seq = chain.last;
    final offset = s.cursor.offset;
    final updated = seq.withChildren(<EditorNode>[
      ...seq.children.sublist(0, offset),
      ...nodes,
      ...seq.children.sublist(offset),
    ]);
    final cursor = s.cursor.withOffset(offset + nodes.length);
    return EditorState(_rebuild(chain, cursor, updated), cursor);
  }

  static EditorState insertAtom(EditorState s, String text, AtomKind kind) =>
      insert(s, <EditorNode>[AtomNode(text, kind)]);

  static EditorState _insertComposite(EditorState s, EditorNode node, EditorSequence? enter) {
    final inserted = insert(s, <EditorNode>[node]);
    return enter == null ? inserted : EditorState(inserted.root, inserted.cursor.push(enter.id, 0));
  }

  /// Inserts atoms and leaves the caret [caretAfter] atoms into the run.
  static EditorState _insertInline(EditorState s, List<AtomNode> atoms, int caretAfter) {
    final inserted = insert(s, atoms);
    return EditorState(inserted.root, inserted.cursor.withOffset(s.cursor.offset + caretAfter));
  }

  static const AtomNode _open = AtomNode('(', AtomKind.paren);
  static const AtomNode _close = AtomNode(')', AtomKind.paren);

  static bool _atDepthLimit(EditorState s) => structuralDepth(s) >= MAX_TREE_DEPTH;

  /// Stacked fraction with the caret in the numerator.
  static EditorState insertFraction(EditorState s) {
    if (_atDepthLimit(s)) {
      return _insertInline(s, const <AtomNode>[_open, _close, AtomNode('÷', AtomKind.binaryOp), _open, _close], 1);
    }
    final numerator = EditorSequence.fresh();
    return _insertComposite(s, FractionNode(numerator: numerator, denominator: EditorSequence.fresh()), numerator);
  }

  /// Superscript. With a preset [exponent] (x², x⁻¹) the caret stays behind
  /// the power, otherwise it enters the empty exponent.
  static EditorState insertPower(EditorState s, {List<EditorNode> exponent = const <EditorNode>[]}) {
    if (_atDepthLimit(s)) {
      const caret = AtomNode('^', AtomKind.binaryOp);
      if (exponent.isEmpty) return _insertInline(s, const <AtomNode>[caret, _open, _close], 2);
      final atoms = exponent.whereType<AtomNode>().toList();
      final wrapped = atoms.length == 1 ? <AtomNode>[caret, ...atoms] : <AtomNode>[caret, _open, ...atoms, _close];
      return _insertInline(s, wrapped, wrapped.length);
    }
    final slot = EditorSequence.fresh(exponent);
    return _insertComposite(s, PowerNode(exponent: slot), exponent.isEmpty ? slot : null);
  }

  /// Radical. A square root starts in the radicand; with [withDegree] the
  /// caret starts in the (empty) degree, and a preset [degree] gives e.g. a
  /// cube root.
  static EditorState insertRoot(
    EditorState s, {
    bool withDegree = false,
    List<EditorNode> degree = const <EditorNode>[],
  }) {
    if (_atDepthLimit(s)) {
      if (!withDegree && degree.isEmpty) {
        return _insertInline(s, const <AtomNode>[AtomNode('√', AtomKind.unaryPrefix), _open, _close], 2);
      }
      final degreeSlot = EditorSequence.fresh(degree);
      final radicand = EditorSequence.fresh();
      final node = FunctionCallEditorNode(
        functionName: 'root',
        argSlots: List<EditorSequence>.unmodifiable(<EditorSequence>[degreeSlot, radicand]),
      );
      return _insertComposite(s, node, degree.isEmpty ? degreeSlot : radicand);
    }
    final degreeSlot = EditorSequence.fresh(degree);
    final radicand = EditorSequence.fresh();
    return _insertComposite(
      s,
      RootNode(degree: degreeSlot, radicand: radicand),
      withDegree && degree.isEmpty ? degreeSlot : radicand,
    );
  }

  /// `name(□, …)` with the caret in the first argument.
  static EditorState insertFunction(EditorState s, String name, {int arity = 1}) {
    final slots = List<EditorSequence>.unmodifiable(<EditorSequence>[
      for (var i = 0; i < arity; i++) EditorSequence.fresh(),
    ]);
    return _insertComposite(s, FunctionCallEditorNode(functionName: name, argSlots: slots), slots.first);
  }

  /// Definite integral with the caret in the lower bound.
  static EditorState insertIntegral(EditorState s, {String variable = 'x'}) {
    final lower = EditorSequence.fresh();
    final node = CalculusIntegralNode(
      lowerBound: lower,
      upperBound: EditorSequence.fresh(),
      integrand: EditorSequence.fresh(),
      dummyVariable: variable,
    );
    return _insertComposite(s, node, lower);
  }

  /// Derivative at a point with the caret in the body.
  static EditorState insertDerivative(EditorState s, {String variable = 'x'}) {
    final body = EditorSequence.fresh();
    final node = DerivativeEditorNode(body: body, evalPoint: EditorSequence.fresh(), dummyVariable: variable);
    return _insertComposite(s, node, body);
  }

  // --------------------------------------------------------------- navigation

  static EditorState move(EditorState s, CursorDirection direction) => switch (direction) {
        CursorDirection.left => moveLeft(s),
        CursorDirection.right => moveRight(s),
        CursorDirection.up => moveUp(s),
        CursorDirection.down => moveDown(s),
      };

  static EditorState moveToStart(EditorState s) => EditorState(s.root, CursorPath.root());

  static EditorState moveToEnd(EditorState s) => EditorState(s.root, CursorPath.root(s.root.length));

  static EditorState moveRight(EditorState s) {
    final chain = _chain(s);
    final seq = chain.last;
    final offset = s.cursor.offset;
    if (offset < seq.length) {
      final node = seq.children[offset];
      if (node.isComposite) {
        // Step over the node in the parent and descend into its first slot.
        final first = _navigableSlots(node, null).first;
        return EditorState(s.root, s.cursor.withOffset(offset + 1).push(first.id, 0));
      }
      return EditorState(s.root, s.cursor.withOffset(offset + 1));
    }
    if (s.cursor.depth > 1) {
      final owner = _ownerAt(chain, s.cursor, chain.length - 1);
      final slots = _navigableSlots(owner, seq.id);
      final index = slots.indexWhere((slot) => slot.id == seq.id);
      if (index + 1 < slots.length) {
        return EditorState(s.root, s.cursor.replaceTop(slots[index + 1].id, 0));
      }
      return EditorState(s.root, s.cursor.pop());
    }
    return s;
  }

  static EditorState moveLeft(EditorState s) {
    final chain = _chain(s);
    final seq = chain.last;
    final offset = s.cursor.offset;
    if (offset > 0) {
      final node = seq.children[offset - 1];
      if (node.isComposite) {
        final last = _navigableSlots(node, null).last;
        return EditorState(s.root, s.cursor.push(last.id, last.length));
      }
      return EditorState(s.root, s.cursor.withOffset(offset - 1));
    }
    if (s.cursor.depth > 1) {
      final owner = _ownerAt(chain, s.cursor, chain.length - 1);
      final slots = _navigableSlots(owner, seq.id);
      final index = slots.indexWhere((slot) => slot.id == seq.id);
      if (index > 0) {
        final previous = slots[index - 1];
        return EditorState(s.root, s.cursor.replaceTop(previous.id, previous.length));
      }
      final popped = s.cursor.pop();
      return EditorState(s.root, popped.withOffset(popped.offset - 1));
    }
    return s;
  }

  static EditorState moveUp(EditorState s) => _moveVertical(s, up: true);

  static EditorState moveDown(EditorState s) => _moveVertical(s, up: false);

  /// Jumps between the vertical slots of the nearest enclosing fraction,
  /// root or integral.
  static EditorState _moveVertical(EditorState s, {required bool up}) {
    final chain = _chain(s);
    for (var level = chain.length - 1; level >= 1; level--) {
      final owner = _ownerAt(chain, s.cursor, level);
      final here = chain[level].id;
      EditorSequence? target;
      switch (owner) {
        case FractionNode(:final numerator, :final denominator):
          if (up && here == denominator.id) target = numerator;
          if (!up && here == numerator.id) target = denominator;
        case RootNode(:final degree, :final radicand):
          if (up && here == radicand.id) target = degree;
          if (!up && here == degree.id) target = radicand;
        case CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand):
          if (up && (here == lowerBound.id || here == integrand.id)) target = upperBound;
          if (!up && (here == upperBound.id || here == integrand.id)) target = lowerBound;
        case AtomNode() || PowerNode() || FunctionCallEditorNode() || DerivativeEditorNode():
          break;
      }
      if (target != null) {
        return EditorState(s.root, s.cursor.truncate(level).push(target.id, target.length));
      }
    }
    return s;
  }

  // ----------------------------------------------------------------- deleting

  /// Backspace that respects 2D structure:
  ///
  ///  * inside a completely empty template the template itself is removed,
  ///  * right behind a template the caret steps into its last slot instead of
  ///    deleting the whole node,
  ///  * otherwise the atom left of the caret is removed.
  static EditorState smartBackspace(EditorState s) {
    final chain = _chain(s);
    final seq = chain.last;
    final offset = s.cursor.offset;
    if (s.cursor.depth > 1) {
      final owner = _ownerAt(chain, s.cursor, chain.length - 1);
      if (owner.slots.every((slot) => slot.isEmpty)) {
        final parent = chain[chain.length - 2];
        final index = s.cursor.entries[s.cursor.depth - 2].$2 - 1;
        final updated = parent.withChildren(<EditorNode>[...parent.children]..removeAt(index));
        final cursor = s.cursor.pop().withOffset(index);
        return EditorState(_rebuild(chain.sublist(0, chain.length - 1), cursor, updated), cursor);
      }
    }
    if (offset > 0) {
      final previous = seq.children[offset - 1];
      if (previous.isComposite) {
        final last = _navigableSlots(previous, null).last;
        return EditorState(s.root, s.cursor.push(last.id, last.length));
      }
      final updated = seq.withChildren(<EditorNode>[...seq.children]..removeAt(offset - 1));
      final cursor = s.cursor.withOffset(offset - 1);
      return EditorState(_rebuild(chain, cursor, updated), cursor);
    }
    return moveLeft(s);
  }
}
