import '../models/editor_node.dart';
import 'calc_key.dart';
import 'cursor_path.dart';
import 'math_print_controller.dart';

/// Where the input line is in its life cycle.
enum InputPhase {
  /// The expression is being typed.
  editing,

  /// `=` produced a result that is on display.
  committedResult,

  /// `=` failed; the error is on display.
  errorLocked,
}

/// Editor content plus its [InputPhase].
final class EditingSession {
  const EditingSession(this.editor, {this.phase = InputPhase.editing});

  factory EditingSession.empty() => EditingSession(EditorState.empty());

  final EditorState editor;
  final InputPhase phase;

  EditingSession withPhase(InputPhase next) => EditingSession(editor, phase: next);
}

/// Post-commit (`Ans`) state machine.
///
/// While a committed result is on display the next key decides what happens
/// to the old expression:
///
/// * a **binary or postfix operator** (`+ − × ÷ ^ ! %`, `x²` …) continues
///   from the result: the line becomes `Ans <operator>`;
/// * a **digit, constant, or prefix function / template** starts a new
///   expression;
/// * **◀ / ▶** bring the previous expression back for in-place editing.
abstract final class InputPhaseMachine {
  /// The atom that stands for the last result.
  static const AtomNode ans = AtomNode('Ans', AtomKind.variable);

  /// Whether [key] continues a calculation from the previous result.
  static bool continuesFromResult(CalcKey key) => switch (key) {
        AtomKey(:final kind) => kind == AtomKind.binaryOp || kind == AtomKind.unaryPostfix,
        TemplateKey(:final kind) => kind == TemplateKind.power ||
            kind == TemplateKind.square ||
            kind == TemplateKind.cube ||
            kind == TemplateKind.reciprocal,
        _ => false,
      };

  /// Applies an editing key to the tree (no phase logic).
  static EditorState applyToEditor(EditorState e, CalcKey key) {
    switch (key) {
      case AtomKey(:final text, :final kind):
        return MathPrintController.insertAtom(e, text, kind);
      case TemplateKey(:final kind, :final name, :final arity):
        const two = <EditorNode>[AtomNode('2', AtomKind.digit)];
        const three = <EditorNode>[AtomNode('3', AtomKind.digit)];
        const minusOne = <EditorNode>[AtomNode('−', AtomKind.binaryOp), AtomNode('1', AtomKind.digit)];
        switch (kind) {
          case TemplateKind.fraction:
            return MathPrintController.insertFraction(e);
          case TemplateKind.power:
            return MathPrintController.insertPower(e);
          case TemplateKind.square:
            return MathPrintController.insertPower(e, exponent: two);
          case TemplateKind.cube:
            return MathPrintController.insertPower(e, exponent: three);
          case TemplateKind.reciprocal:
            return MathPrintController.insertPower(e, exponent: minusOne);
          case TemplateKind.squareRoot:
            return MathPrintController.insertRoot(e);
          case TemplateKind.cubeRoot:
            return MathPrintController.insertRoot(e, degree: three);
          case TemplateKind.nthRoot:
            return MathPrintController.insertRoot(e, withDegree: true);
          case TemplateKind.powerOfTen:
            final base = MathPrintController.insert(e, const <EditorNode>[
              AtomNode('1', AtomKind.digit),
              AtomNode('0', AtomKind.digit),
            ]);
            return MathPrintController.insertPower(base);
          case TemplateKind.powerOfE:
            return MathPrintController.insertPower(MathPrintController.insertAtom(e, 'e', AtomKind.constant));
          case TemplateKind.function:
            return MathPrintController.insertFunction(e, name ?? '', arity: arity);
          case TemplateKind.integral:
            return MathPrintController.insertIntegral(e);
          case TemplateKind.derivative:
            return MathPrintController.insertDerivative(e);
        }
      case MoveKey(:final direction):
        return MathPrintController.move(e, direction);
      case BackspaceKey():
        return MathPrintController.smartBackspace(e);
      case ClearKey():
        return EditorState.empty();
      case EvaluateKey():
        return e;
    }
  }

  /// Handles [key] in the current phase and returns the next session.
  ///
  /// [EvaluateKey] is left to the caller (evaluation is asynchronous); use
  /// [committed] / [failed] to record its outcome.
  static EditingSession press(EditingSession s, CalcKey key) {
    if (key is EvaluateKey) return s;
    if (key is ClearKey) return EditingSession.empty();
    switch (s.phase) {
      case InputPhase.editing:
        return EditingSession(applyToEditor(s.editor, key));
      case InputPhase.committedResult:
        if (key is MoveKey) {
          // Re-open the previous expression: ◀ lands at its end, ▶ at its start.
          final cursor =
              key.direction == CursorDirection.right ? CursorPath.root() : CursorPath.root(s.editor.root.length);
          return EditingSession(EditorState(s.editor.root, cursor));
        }
        if (key is BackspaceKey) return EditingSession(MathPrintController.moveToEnd(s.editor));
        final start = continuesFromResult(key)
            ? EditorState.atEnd(EditorSequence.root(const <EditorNode>[ans]))
            : EditorState.empty();
        return EditingSession(applyToEditor(start, key));
      case InputPhase.errorLocked:
        if (key is MoveKey || key is BackspaceKey) {
          return EditingSession(MathPrintController.normalize(s.editor));
        }
        final start = continuesFromResult(key)
            ? EditorState.atEnd(EditorSequence.root(const <EditorNode>[ans]))
            : EditorState.empty();
        return EditingSession(applyToEditor(start, key));
    }
  }

  /// `=` succeeded.
  static EditingSession committed(EditingSession s) => s.withPhase(InputPhase.committedResult);

  /// `=` failed.
  static EditingSession failed(EditingSession s) => s.withPhase(InputPhase.errorLocked);
}
