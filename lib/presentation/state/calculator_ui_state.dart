import '../../domain/editor/cursor_path.dart';
import '../../domain/editor/input_phase.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/models/editor_node.dart';
import '../../domain/models/math_context.dart';

// The enums the blueprint lists next to the UI state live in the pure-Dart
// domain (the evaluator and the editor need them too) and are re-exported
// from here.
export '../../domain/editor/input_phase.dart' show InputPhase;
export '../../domain/models/math_context.dart' show AngleUnit, JuxtapositionMode, NotationMode;

const Object _keep = Object();

/// Immutable state of the calculator screen.
class CalculatorUiState {
  final EditorSequence rootSequence;
  final List<(String sequenceId, int offset)> cursorPath;
  final InputPhase inputPhase;
  final String livePreviewPrimary;
  final String? livePreviewSecondary; // Fraction 'a/b' or Engineering notation
  final String? errorMessage;
  final int activeTabIndex; // 0..4
  final AngleUnit angleUnit;
  final bool isInverseActive; // 2nd / INV toggle
  final bool isHyperbolicActive; // HYP toggle
  final bool isComplexEnabled; // REAL vs CPLX mode
  final JuxtapositionMode juxtapositionMode;

  /// How results are written: [NotationMode.engineering] while ENG is on.
  final NotationMode notation;

  /// Set while the result row shows what `CALC` computed: the values that
  /// stood in for the variables, e.g. `x = 5, y = 2`. The variables
  /// themselves keep what they had stored.
  final String? substitution;
  final bool isEvaluatingHeavy; // True when background isolate > 50ms
  final Map<String, String> variables; // 'Ans', 'M', 'A'..'Z'
  final List<EditorSequence> undoStack;
  final List<EditorSequence> redoStack;

  const CalculatorUiState({
    required this.rootSequence,
    required this.cursorPath,
    this.inputPhase = InputPhase.editing,
    this.livePreviewPrimary = '',
    this.livePreviewSecondary,
    this.errorMessage,
    this.activeTabIndex = 0,
    this.angleUnit = AngleUnit.deg,
    this.isInverseActive = false,
    this.isHyperbolicActive = false,
    this.isComplexEnabled = false,
    this.juxtapositionMode = JuxtapositionMode.standardTi,
    this.notation = NotationMode.auto,
    this.substitution,
    this.isEvaluatingHeavy = false,
    this.variables = const {'Ans': '0', 'M': '0'},
    this.undoStack = const [],
    this.redoStack = const [],
  });

  /// An empty input line.
  factory CalculatorUiState.initial() => CalculatorUiState(
        rootSequence: EditorSequence.root(),
        cursorPath: const <(String, int)>[(EditorSequence.rootId, 0)],
      );

  /// Tree + caret as the editor sees them.
  EditorState get editor => EditorState(rootSequence, CursorPath.fromRecords(cursorPath));

  /// Evaluation settings derived from the mode toggles.
  MathContext get mathContext => MathContext(
        angleUnit: angleUnit,
        juxtaposition: juxtapositionMode,
        complexMode: isComplexEnabled ? ComplexMode.complex : ComplexMode.real,
        notation: notation,
      );

  bool get isEngineering => notation == NotationMode.engineering;

  bool get canUndo => undoStack.isNotEmpty;
  bool get canRedo => redoStack.isNotEmpty;

  /// Whether the independent memory holds something.
  bool get hasMemory => (variables['M'] ?? '0') != '0';

  /// Parentheses that are still open around the caret (the badge on the
  /// `( )` key).
  int get unclosedParenthesesCount =>
      inputPhase == InputPhase.editing ? MathPrintController.openParentheses(editor) : 0;

  CalculatorUiState copyWith({
    EditorSequence? rootSequence,
    List<(String sequenceId, int offset)>? cursorPath,
    InputPhase? inputPhase,
    String? livePreviewPrimary,
    Object? livePreviewSecondary = _keep,
    Object? errorMessage = _keep,
    int? activeTabIndex,
    AngleUnit? angleUnit,
    bool? isInverseActive,
    bool? isHyperbolicActive,
    bool? isComplexEnabled,
    JuxtapositionMode? juxtapositionMode,
    NotationMode? notation,
    Object? substitution = _keep,
    bool? isEvaluatingHeavy,
    Map<String, String>? variables,
    List<EditorSequence>? undoStack,
    List<EditorSequence>? redoStack,
  }) =>
      CalculatorUiState(
        rootSequence: rootSequence ?? this.rootSequence,
        cursorPath: cursorPath ?? this.cursorPath,
        inputPhase: inputPhase ?? this.inputPhase,
        livePreviewPrimary: livePreviewPrimary ?? this.livePreviewPrimary,
        livePreviewSecondary:
            identical(livePreviewSecondary, _keep) ? this.livePreviewSecondary : livePreviewSecondary as String?,
        errorMessage: identical(errorMessage, _keep) ? this.errorMessage : errorMessage as String?,
        activeTabIndex: activeTabIndex ?? this.activeTabIndex,
        angleUnit: angleUnit ?? this.angleUnit,
        isInverseActive: isInverseActive ?? this.isInverseActive,
        isHyperbolicActive: isHyperbolicActive ?? this.isHyperbolicActive,
        isComplexEnabled: isComplexEnabled ?? this.isComplexEnabled,
        juxtapositionMode: juxtapositionMode ?? this.juxtapositionMode,
        notation: notation ?? this.notation,
        substitution: identical(substitution, _keep) ? this.substitution : substitution as String?,
        isEvaluatingHeavy: isEvaluatingHeavy ?? this.isEvaluatingHeavy,
        variables: variables ?? this.variables,
        undoStack: undoStack ?? this.undoStack,
        redoStack: redoStack ?? this.redoStack,
      );
}
