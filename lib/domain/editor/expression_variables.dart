import '../models/editor_node.dart';

/// The variables an expression depends on.
abstract final class ExpressionVariables {
  /// The single-letter variables of [root] in the order they first appear
  /// (`x`, `y`, `A`…`Z`; the memories `Ans` and `MatA` are no letters).
  ///
  /// A variable that only stands for the running value of a template - the
  /// `x` of `∫ … dx`, of `d/dx`, of a `Σ` or a `Π` - is not one the
  /// expression depends on, and is left out.
  static List<String> free(EditorSequence root) {
    final found = <String>[];

    void walk(EditorSequence sequence, Set<String> bound) {
      for (final node in sequence.children) {
        switch (node) {
          case AtomNode(:final text, :final kind):
            if (kind == AtomKind.variable && text.length == 1 && !bound.contains(text) && !found.contains(text)) {
              found.add(text);
            }
          case CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand, :final dummyVariable):
            walk(lowerBound, bound);
            walk(upperBound, bound);
            walk(integrand, <String>{...bound, dummyVariable});
          case DerivativeEditorNode(:final body, :final evalPoint, :final dummyVariable):
            walk(body, <String>{...bound, dummyVariable});
            walk(evalPoint, bound);
          case FractionNode() || PowerNode() || RootNode() || FunctionCallEditorNode():
            for (final slot in node.slots) {
              walk(slot, bound);
            }
        }
      }
    }

    walk(root, const <String>{});
    return found;
  }

  /// Whether [root] contains the atom [text] anywhere (for example `Rand`).
  static bool mentions(EditorSequence root, String text) {
    for (final node in root.children) {
      if (node is AtomNode) {
        if (node.text == text) return true;
      } else if (node.slots.any((slot) => mentions(slot, text))) {
        return true;
      }
    }
    return false;
  }
}
