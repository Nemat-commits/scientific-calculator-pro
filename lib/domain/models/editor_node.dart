/// 2D MathPrint editor tree.
///
/// An expression is an [EditorSequence] of [EditorNode]s. Leaf nodes are
/// [AtomNode]s; composite nodes (fractions, powers, roots, function calls,
/// integrals, sums, products, derivatives) own further sequences ("slots").
library;

/// Role of an [AtomNode].
///
/// The first five kinds are the ones named by the blueprint; the remaining
/// three cover parentheses, argument separators and the inline radical that
/// replaces a [RootNode] beyond the maximum nesting depth.
enum AtomKind {
  digit,
  binaryOp,
  unaryPostfix,
  constant,
  variable,
  unaryPrefix,
  paren,
  separator,
}

/// What a [CalculusIntegralNode] does with its body between the two bounds.
enum BoundedOperator {
  /// `∫`: the definite integral over `[lower, upper]`.
  integral('∫'),

  /// `Σ`: the sum of the body for every whole number from lower to upper.
  sum('Σ'),

  /// `Π`: the product of the body for every whole number from lower to upper.
  product('Π');

  const BoundedOperator(this.symbol);

  /// The sign of the operator, also its lexeme in the linear form.
  final String symbol;
}

/// An ordered run of nodes with a stable identity.
class EditorSequence {
  final String id;
  final List<EditorNode> children;
  EditorSequence({required this.id, List<EditorNode>? children}) : children = children ?? [];

  /// Identity of the top-level sequence.
  static const String rootId = 'root';

  static int _counter = 0;

  /// A unique id for a new slot.
  static String nextId() => 's${++_counter}';

  /// A new sequence with a fresh id.
  factory EditorSequence.fresh([List<EditorNode>? children]) =>
      EditorSequence(id: nextId(), children: List<EditorNode>.unmodifiable(children ?? const <EditorNode>[]));

  /// The top-level sequence of an expression.
  factory EditorSequence.root([List<EditorNode>? children]) =>
      EditorSequence(id: rootId, children: List<EditorNode>.unmodifiable(children ?? const <EditorNode>[]));

  bool get isEmpty => children.isEmpty;
  bool get isNotEmpty => children.isNotEmpty;
  int get length => children.length;

  /// Number of `(` typed into this sequence that have no matching `)` yet.
  /// They are closed implicitly where the sequence ends, which the display
  /// shows as ghost parentheses.
  int get unclosedParentheses {
    var open = 0;
    for (final node in children) {
      if (node is AtomNode && node.kind == AtomKind.paren) {
        if (node.text == '(') {
          open++;
        } else if (open > 0) {
          open--;
        }
      }
    }
    return open;
  }

  /// Same identity, different content.
  EditorSequence withChildren(List<EditorNode> newChildren) =>
      EditorSequence(id: id, children: List<EditorNode>.unmodifiable(newChildren));

  /// Deep copy in which every slot (not the receiver itself) gets a new id.
  EditorSequence withFreshSlotIds() => withChildren(<EditorNode>[
        for (final node in children)
          node is AtomNode ? node : node.withSlots(<EditorSequence>[for (final s in node.slots) s._fresh()]),
      ]);

  EditorSequence _fresh() => EditorSequence(id: nextId(), children: withFreshSlotIds().children);

  Map<String, Object?> toJson() => <String, Object?>{
        'id': id,
        'c': <Object?>[for (final node in children) node.toJson()],
      };

  static EditorSequence fromJson(Map<String, Object?> json) {
    final id = json['id'] as String? ?? nextId();
    _reserve(id);
    final raw = json['c'] as List<Object?>? ?? const <Object?>[];
    return EditorSequence(
      id: id,
      children: List<EditorNode>.unmodifiable(<EditorNode>[
        for (final item in raw) EditorNode.fromJson((item as Map<Object?, Object?>).cast<String, Object?>()),
      ]),
    );
  }

  /// Keeps [nextId] ahead of ids that were restored from storage.
  static void _reserve(String id) {
    if (id.length > 1 && id.startsWith('s')) {
      final n = int.tryParse(id.substring(1));
      if (n != null && n > _counter) _counter = n;
    }
  }

  @override
  String toString() => '[${children.join(' ')}]';
}

/// Base class of all editor nodes.
sealed class EditorNode {
  const EditorNode();

  static EditorNode fromJson(Map<String, Object?> json) {
    EditorSequence seq(String key) =>
        EditorSequence.fromJson((json[key] as Map<Object?, Object?>).cast<String, Object?>());
    switch (json['t']) {
      case 'a':
        final kind = AtomKind.values.firstWhere((k) => k.name == json['k'], orElse: () => AtomKind.digit);
        return AtomNode(json['x'] as String? ?? '', kind);
      case 'frac':
        return FractionNode(whole: json['w'] == null ? null : seq('w'), numerator: seq('n'), denominator: seq('d'));
      case 'pow':
        return PowerNode(exponent: seq('e'));
      case 'root':
        return RootNode(degree: seq('g'), radicand: seq('r'));
      case 'fn':
        final raw = json['args'] as List<Object?>? ?? const <Object?>[];
        return FunctionCallEditorNode(
          functionName: json['name'] as String? ?? '',
          argSlots: List<EditorSequence>.unmodifiable(<EditorSequence>[
            for (final a in raw) EditorSequence.fromJson((a as Map<Object?, Object?>).cast<String, Object?>()),
          ]),
        );
      case 'int':
        return CalculusIntegralNode(
          lowerBound: seq('lo'),
          upperBound: seq('hi'),
          integrand: seq('f'),
          dummyVariable: json['v'] as String? ?? 'x',
          operator:
              BoundedOperator.values.firstWhere((o) => o.name == json['op'], orElse: () => BoundedOperator.integral),
        );
      case 'diff':
        return DerivativeEditorNode(body: seq('f'), evalPoint: seq('at'), dummyVariable: json['v'] as String? ?? 'x');
      default:
        throw FormatException('Unknown editor node type: ${json['t']}');
    }
  }
}

final class AtomNode extends EditorNode {
  final String text; // e.g. '7', '+', 'π', 'X', 'Ans'
  final AtomKind kind; // digit, binaryOp, unaryPostfix, constant, variable
  const AtomNode(this.text, this.kind);

  @override
  bool operator ==(Object other) => other is AtomNode && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => text;
}

final class FractionNode extends EditorNode {
  /// The whole part of a mixed fraction (`2` in `2 1/3`); `null` for a plain
  /// fraction. The value of a mixed fraction is `whole + numerator/denominator`.
  final EditorSequence? whole;
  final EditorSequence numerator;
  final EditorSequence denominator;
  const FractionNode({this.whole, required this.numerator, required this.denominator});

  bool get isMixed => whole != null;

  @override
  String toString() => whole == null ? 'frac($numerator,$denominator)' : 'mixed($whole,$numerator,$denominator)';
}

final class PowerNode extends EditorNode {
  final EditorSequence exponent;
  const PowerNode({required this.exponent});

  @override
  String toString() => '^$exponent';
}

final class RootNode extends EditorNode {
  final EditorSequence degree; // Empty for square root, '3' for cube root
  final EditorSequence radicand;
  const RootNode({required this.degree, required this.radicand});

  @override
  String toString() => 'root($degree,$radicand)';
}

final class FunctionCallEditorNode extends EditorNode {
  final String functionName; // 'sin', 'ln', 'abs', 'ncr', etc.
  final List<EditorSequence> argSlots;
  const FunctionCallEditorNode({required this.functionName, required this.argSlots});

  @override
  String toString() => '$functionName(${argSlots.join(',')})';
}

/// A body between a lower and an upper bound over the variable
/// [dummyVariable]: the definite integral, and the sum `Σ` and product `Π`
/// over whole numbers (see [operator]).
final class CalculusIntegralNode extends EditorNode {
  final EditorSequence lowerBound;
  final EditorSequence upperBound;
  final EditorSequence integrand;
  final String dummyVariable;
  final BoundedOperator operator;
  const CalculusIntegralNode({
    required this.lowerBound,
    required this.upperBound,
    required this.integrand,
    this.dummyVariable = 'x',
    this.operator = BoundedOperator.integral,
  });

  @override
  String toString() =>
      '${operator == BoundedOperator.integral ? 'int' : operator.name}($lowerBound,$upperBound,$integrand)';
}

final class DerivativeEditorNode extends EditorNode {
  final EditorSequence body;
  final EditorSequence evalPoint;
  final String dummyVariable;
  const DerivativeEditorNode({
    required this.body,
    required this.evalPoint,
    this.dummyVariable = 'x',
  });

  @override
  String toString() => 'diff($body,$evalPoint)';
}

/// Structural helpers shared by the editor, the lowerer and the renderer.
extension EditorNodeStructure on EditorNode {
  /// Whether the node owns child sequences.
  bool get isComposite => this is! AtomNode;

  /// Whether the node shrinks its content when rendered and therefore counts
  /// towards the maximum 2D nesting depth.
  bool get isStructural => this is FractionNode || this is RootNode || this is PowerNode;

  /// Child sequences in reading (cursor traversal) order.
  List<EditorSequence> get slots => switch (this) {
        AtomNode() => const <EditorSequence>[],
        FractionNode(:final whole, :final numerator, :final denominator) => <EditorSequence>[
            if (whole != null) whole,
            numerator,
            denominator
          ],
        PowerNode(:final exponent) => <EditorSequence>[exponent],
        RootNode(:final degree, :final radicand) => <EditorSequence>[degree, radicand],
        FunctionCallEditorNode(:final argSlots) => argSlots,
        CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand) => <EditorSequence>[
            lowerBound,
            upperBound,
            integrand
          ],
        DerivativeEditorNode(:final body, :final evalPoint) => <EditorSequence>[body, evalPoint],
      };

  /// First slot entered when the cursor moves into the node from the left.
  EditorSequence get firstChildSequence => slots.first;

  /// Last slot, entered when the cursor moves into the node from the right.
  EditorSequence get lastChildSequence => slots.last;

  /// A copy of the node that owns [newSlots] (same order as [slots]).
  EditorNode withSlots(List<EditorSequence> newSlots) => switch (this) {
        AtomNode() => this,
        FractionNode(:final whole) => whole == null
            ? FractionNode(numerator: newSlots[0], denominator: newSlots[1])
            : FractionNode(whole: newSlots[0], numerator: newSlots[1], denominator: newSlots[2]),
        PowerNode() => PowerNode(exponent: newSlots[0]),
        RootNode() => RootNode(degree: newSlots[0], radicand: newSlots[1]),
        FunctionCallEditorNode(:final functionName) =>
          FunctionCallEditorNode(functionName: functionName, argSlots: List<EditorSequence>.unmodifiable(newSlots)),
        CalculusIntegralNode(:final dummyVariable, :final operator) => CalculusIntegralNode(
            lowerBound: newSlots[0],
            upperBound: newSlots[1],
            integrand: newSlots[2],
            dummyVariable: dummyVariable,
            operator: operator,
          ),
        DerivativeEditorNode(:final dummyVariable) =>
          DerivativeEditorNode(body: newSlots[0], evalPoint: newSlots[1], dummyVariable: dummyVariable),
      };

  Map<String, Object?> toJson() => switch (this) {
        AtomNode(:final text, :final kind) => <String, Object?>{'t': 'a', 'x': text, 'k': kind.name},
        FractionNode(:final whole, :final numerator, :final denominator) => <String, Object?>{
            't': 'frac',
            if (whole != null) 'w': whole.toJson(),
            'n': numerator.toJson(),
            'd': denominator.toJson()
          },
        PowerNode(:final exponent) => <String, Object?>{'t': 'pow', 'e': exponent.toJson()},
        RootNode(:final degree, :final radicand) => <String, Object?>{
            't': 'root',
            'g': degree.toJson(),
            'r': radicand.toJson()
          },
        FunctionCallEditorNode(:final functionName, :final argSlots) => <String, Object?>{
            't': 'fn',
            'name': functionName,
            'args': <Object?>[for (final a in argSlots) a.toJson()],
          },
        CalculusIntegralNode(
          :final lowerBound,
          :final upperBound,
          :final integrand,
          :final dummyVariable,
          :final operator
        ) =>
          <String, Object?>{
            't': 'int',
            'lo': lowerBound.toJson(),
            'hi': upperBound.toJson(),
            'f': integrand.toJson(),
            'v': dummyVariable,
            if (operator != BoundedOperator.integral) 'op': operator.name,
          },
        DerivativeEditorNode(:final body, :final evalPoint, :final dummyVariable) => <String, Object?>{
            't': 'diff',
            'f': body.toJson(),
            'at': evalPoint.toJson(),
            'v': dummyVariable
          },
      };
}
