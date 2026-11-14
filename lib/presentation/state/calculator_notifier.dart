import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics/haptic_service.dart';
import '../../data/local_db/draft_state_store.dart';
import '../../data/repositories/calculator_repository.dart';
import '../../domain/compiler/tree_to_token_lowerer.dart';
import '../../domain/editor/calc_key.dart';
import '../../domain/editor/clipboard_sanitizer.dart';
import '../../domain/editor/cursor_path.dart';
import '../../domain/editor/expression_variables.dart';
import '../../domain/editor/input_phase.dart';
import '../../domain/editor/math_print_controller.dart';
import '../../domain/evaluator/ast_evaluator.dart';
import '../../domain/evaluator/number_formatter.dart';
import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import '../../domain/models/calc_value.dart';
import '../../domain/models/calc_value_codec.dart';
import '../../domain/models/editor_node.dart';
import '../isolate/evaluation_protocol.dart';
import 'calculator_ui_state.dart';

/// History, variables and settings. Overridden with the SQLite-backed
/// repository in `main()`; the default keeps everything in memory.
final Provider<CalculatorRepository> repositoryProvider =
    Provider<CalculatorRepository>((ref) => InMemoryCalculatorRepository());

/// Draft of the expression that is being typed.
final Provider<DraftStateStore> draftStoreProvider = Provider<DraftStateStore>((ref) => DraftStateStore.memory());

/// Expression evaluator. Overridden with the isolate pool in `main()`.
final Provider<ExpressionEvaluator> evaluatorProvider = Provider<ExpressionEvaluator>((ref) {
  final evaluator = InlineEvaluator();
  ref.onDispose(evaluator.dispose);
  return evaluator;
});

/// Haptic feedback. Silent unless overridden.
final Provider<HapticService> hapticServiceProvider = Provider<HapticService>((ref) => SilentHapticService());

/// Variables that were read from storage before the first frame.
final Provider<Map<String, String>> storedVariablesProvider =
    Provider<Map<String, String>>((ref) => const <String, String>{});

/// The calculator itself.
final NotifierProvider<CalculatorNotifier, CalculatorUiState> calculatorProvider =
    NotifierProvider<CalculatorNotifier, CalculatorUiState>(CalculatorNotifier.new);

/// The history tape.
final NotifierProvider<HistoryNotifier, HistoryState> historyProvider =
    NotifierProvider<HistoryNotifier, HistoryState>(HistoryNotifier.new);

/// Manages key intents, the post-commit state machine, undo / redo, live
/// previews and commits.
class CalculatorNotifier extends Notifier<CalculatorUiState> {
  static const int _undoLimit = 100;
  static const Duration _heavyThreshold = Duration(milliseconds: 50);

  late CalculatorRepository _repository;
  late DraftStateStore _drafts;
  late ExpressionEvaluator _evaluator;
  late HapticService _haptics;
  final AstEvaluator _arithmetic = AstEvaluator();
  Timer? _heavyTimer;

  /// Expression, result and angle unit of the latest commit; pressing `=`
  /// again without any change must not add the same line to the tape twice.
  (String, String, String)? _lastCommit;
  int _ticket = 0;

  /// The value `CALC` put on display (see [CalculatorUiState.substitution]).
  String? _substituted;

  /// The values of the latest `CALC`, encoded and as they were typed.
  Map<String, String> _calcValues = const <String, String>{};
  Map<String, String> _calcEntries = const <String, String>{};

  /// What was typed into `CALC` for the result (or the error) on display, by
  /// variable; empty once it is gone. The prompt starts from these, so that
  /// changing one of several values takes one key.
  Map<String, String> get calcEntries => state.substitution == null ? const <String, String>{} : _calcEntries;

  @override
  CalculatorUiState build() {
    _repository = ref.read(repositoryProvider);
    _drafts = ref.read(draftStoreProvider);
    _evaluator = ref.read(evaluatorProvider);
    _haptics = ref.read(hapticServiceProvider);
    ref.onDispose(() => _heavyTimer?.cancel());

    final settings = _repository.loadSettings();
    _haptics.enabled = settings.hapticsEnabled && _haptics is! SilentHapticService;
    final draft = _drafts.read();
    final initial = CalculatorUiState(
      rootSequence: draft?.root ?? EditorSequence.root(),
      cursorPath: (draft?.cursor ?? CursorPath.root()).toRecords(),
      angleUnit: settings.angleUnit,
      juxtapositionMode: settings.juxtaposition,
      isComplexEnabled: settings.complexEnabled,
      notation: settings.engineeringNotation ? NotationMode.engineering : NotationMode.auto,
      variables: <String, String>{'Ans': '0', 'M': '0', ...ref.read(storedVariablesProvider)},
    );
    if (draft != null && !draft.isEmpty) scheduleMicrotask(_requestPreview);
    return initial;
  }

  // ------------------------------------------------------------------- input

  /// Handles one key press. With [consumeShift] the INV / HYP toggles are
  /// released afterwards (they act like a one-shot shift key).
  void press(CalcKey key, {bool consumeShift = false}) {
    if (key is EvaluateKey) {
      unawaited(evaluate());
      return;
    }
    final before = state;
    final session = InputPhaseMachine.press(EditingSession(before.editor, phase: before.inputPhase), key);
    _apply(before, session, consumedShift: consumeShift);
    final complex = key is AtomKey && ((key.kind == AtomKind.constant && key.text == 'i') || key.text == '∠');
    if (complex && !state.isComplexEnabled) {
      toggleComplex(); // typing i or the angle of a polar form implies complex mode
    }
  }

  void _apply(CalculatorUiState before, EditingSession session, {bool consumedShift = false}) {
    final treeChanged = !identical(session.editor.root, before.rootSequence);
    var undo = before.undoStack;
    var redo = before.redoStack;
    if (treeChanged) {
      undo = <EditorSequence>[...undo, before.rootSequence];
      if (undo.length > _undoLimit) undo = undo.sublist(undo.length - _undoLimit);
      redo = const <EditorSequence>[];
    }
    // A result or a message (of `=`, or of a CALC that failed) leaves the display.
    final leftResult = before.inputPhase != InputPhase.editing || before.errorMessage != null;
    state = before.copyWith(
      rootSequence: session.editor.root,
      cursorPath: session.editor.cursor.toRecords(),
      inputPhase: session.phase,
      errorMessage: null,
      // The message of a failed CALC goes, and the values it names with it.
      substitution: before.errorMessage != null ? null : before.substitution,
      livePreviewPrimary: leftResult ? '' : null,
      livePreviewSecondary: leftResult ? null : before.livePreviewSecondary,
      undoStack: undo,
      redoStack: redo,
      isInverseActive: consumedShift ? false : null,
      isHyperbolicActive: consumedShift ? false : null,
    );
    _drafts.write(session.editor);
    if (treeChanged || leftResult) unawaited(_requestPreview());
  }

  /// Places the caret (tap on the MathPrint canvas).
  void setCursor(String sequenceId, int offset) {
    final path = MathPrintController.pathTo(state.rootSequence, sequenceId, offset);
    if (path == null) return;
    final leftResult = state.inputPhase != InputPhase.editing || state.errorMessage != null;
    state = state.copyWith(
      cursorPath: path.toRecords(),
      inputPhase: InputPhase.editing,
      errorMessage: null,
      substitution: state.errorMessage != null ? null : state.substitution,
      livePreviewPrimary: leftResult ? '' : null,
      livePreviewSecondary: leftResult ? null : state.livePreviewSecondary,
    );
    if (leftResult) unawaited(_requestPreview());
  }

  /// Inserts editor nodes (paste, history, constants) like an operand key.
  void insertNodes(List<EditorNode> nodes) {
    if (nodes.isEmpty) return;
    final before = state;
    final base = before.inputPhase == InputPhase.editing ? before.editor : EditorState.empty();
    _apply(before, EditingSession(MathPrintController.insert(base, nodes)));
  }

  /// Sanitises [text] and inserts it at the caret.
  void pasteText(String text) => insertNodes(ClipboardSanitizer.sanitize(text));

  /// Inserts a number that another part of the app produced (history tape,
  /// converter, lab) at the caret. [value] is a formatter string such as
  /// `1.5e-7`, `4.2 × 10^16325` or `-4 + 2i`; anything that is not a plain
  /// unsigned number goes in parentheses so that it stays one operand.
  void insertValue(String value) {
    final literal = value.trim().replaceAll(' × 10^', 'E');
    if (literal.isEmpty) return;
    final compound = literal.contains(' ') || literal.startsWith('-') || literal.startsWith('−');
    pasteText(compound ? '($literal)' : literal);
    if (literal.contains('i') && !state.isComplexEnabled) toggleComplex(); // as when i is typed
  }

  /// `,`: inside a function with several arguments the caret moves on to the
  /// next argument; anywhere else an argument separator is typed.
  void pressSeparator() {
    final before = state;
    if (before.inputPhase == InputPhase.editing) {
      final next = MathPrintController.nextArgument(before.editor);
      if (next != null) {
        _apply(before, EditingSession(next, phase: before.inputPhase));
        return;
      }
    }
    press(const AtomKey(',', AtomKind.separator));
  }

  /// Replaces the input line with a stored expression (history recall).
  void recallExpression(String expressionJson) {
    try {
      final decoded = (jsonDecode(expressionJson) as Map<Object?, Object?>).cast<String, Object?>();
      final root = EditorSequence.fromJson(decoded);
      final restored = EditorSequence.root(root.withFreshSlotIds().children);
      _apply(state, EditingSession(EditorState.atEnd(restored)));
    } on Object {
      // A corrupt entry is simply not recalled.
    }
  }

  /// Linear text of the current expression.
  String expressionText() => TreeToTokenLowerer.toText(state.rootSequence);

  // -------------------------------------------------------------- evaluation

  Future<void> _requestPreview() async {
    var snapshot = state;
    if (snapshot.inputPhase != InputPhase.editing) return;
    final ticket = ++_ticket;
    if (snapshot.substitution != null) {
      // What CALC showed - a result or a message - belonged to the expression as it was.
      snapshot = snapshot.copyWith(
        substitution: null,
        errorMessage: null,
        livePreviewPrimary: '',
        livePreviewSecondary: null,
      );
      state = snapshot;
    }
    // A preview of Rand would be a number that `=` does not give again.
    if (snapshot.rootSequence.isEmpty || ExpressionVariables.mentions(snapshot.rootSequence, 'Rand')) {
      state = snapshot.copyWith(livePreviewPrimary: '', livePreviewSecondary: null);
      return;
    }
    final outcome = await _evaluator.evaluate(
      EvaluationRequest(root: snapshot.rootSequence, context: snapshot.mathContext, variables: snapshot.variables),
    );
    if (ticket != _ticket || state.inputPhase != InputPhase.editing) return;
    if (outcome.isSuccess) {
      // A bare number needs no preview of itself.
      final trivial = outcome.primary == outcome.expression;
      state = state.copyWith(
        livePreviewPrimary: trivial ? '' : outcome.primary,
        livePreviewSecondary: trivial ? null : outcome.secondary,
      );
    } else if (!outcome.isCancelled) {
      state = state.copyWith(livePreviewPrimary: '', livePreviewSecondary: null);
    }
  }

  /// `=`: evaluates the expression and commits the result.
  Future<void> evaluate() async {
    final snapshot = state;
    if (snapshot.rootSequence.isEmpty) return;
    final ticket = ++_ticket;
    _heavyTimer?.cancel();
    _heavyTimer = Timer(_heavyThreshold, () {
      if (ticket == _ticket) state = state.copyWith(isEvaluatingHeavy: true);
    });
    final outcome = await _evaluator.evaluate(
      EvaluationRequest(
        root: snapshot.rootSequence,
        context: snapshot.mathContext,
        variables: snapshot.variables,
        isCommit: true,
      ),
    );
    _heavyTimer?.cancel();
    if (ticket != _ticket) {
      state = state.copyWith(isEvaluatingHeavy: false);
      return; // the user kept typing
    }
    if (outcome.isSuccess) {
      final value = outcome.valueEncoded!;
      state = state.copyWith(
        inputPhase: InputPhase.committedResult,
        cursorPath: CursorPath.root(snapshot.rootSequence.length).toRecords(),
        livePreviewPrimary: outcome.primary,
        livePreviewSecondary: outcome.secondary,
        errorMessage: null,
        substitution: null,
        variables: <String, String>{...state.variables, 'Ans': value},
        isEvaluatingHeavy: false,
        isInverseActive: false,
        isHyperbolicActive: false,
      );
      _haptics.medium();
      _drafts.clear();
      unawaited(_repository.saveVariable('Ans', value));
      final commit = (outcome.expression!, outcome.primary!, snapshot.angleUnit.name);
      final repeated = snapshot.inputPhase == InputPhase.committedResult && commit == _lastCommit;
      _lastCommit = commit;
      if (repeated) return;
      await _repository.addHistory(
        expressionJson: jsonEncode(snapshot.rootSequence.toJson()),
        expressionText: outcome.expression!,
        resultPrimary: outcome.primary!,
        resultSecondary: outcome.secondary,
        valueEncoded: value,
        angleUnit: snapshot.angleUnit.name,
      );
      unawaited(ref.read(historyProvider.notifier).refresh());
    } else {
      final error = outcome.error!;
      state = state.copyWith(
        inputPhase: InputPhase.errorLocked,
        // A variable without a value is what CALC is for.
        errorMessage: error.type == CalcErrorType.undefinedVariable ? '${error.message}$calcHint' : error.message,
        livePreviewPrimary: '',
        livePreviewSecondary: null,
        substitution: null,
        isEvaluatingHeavy: false,
      );
      _haptics.error();
    }
  }

  /// Added to the message of a variable that has no value.
  static const String calcHint = ' · CALC asks for one';

  /// The single-letter variables the expression depends on, in the order
  /// they appear (what `CALC` asks for).
  List<String> freeVariables() => ExpressionVariables.free(state.rootSequence);

  /// `CALC`: evaluates the expression with [values] standing in for its
  /// variables - encoded values by variable name - and shows the result in
  /// the result row, labelled with [note] (`x = 5`).
  ///
  /// Nothing else changes: the variables keep what they had stored, `Ans`
  /// and the history stay as they were, and the expression remains in the
  /// editor for the next set of values. [entries] is what was typed for each
  /// variable (see [calcEntries]).
  Future<void> evaluateWith(
    Map<String, String> values, {
    required String note,
    Map<String, String> entries = const <String, String>{},
  }) =>
      _evaluateWith(values, note: note, entries: entries);

  /// [refresh]: the same values again after a change of mode, without the
  /// feedback of a key.
  Future<void> _evaluateWith(
    Map<String, String> values, {
    required String note,
    required Map<String, String> entries,
    bool refresh = false,
  }) async {
    final snapshot = state;
    if (snapshot.rootSequence.isEmpty) return;
    _calcValues = Map<String, String>.unmodifiable(values);
    _calcEntries = Map<String, String>.unmodifiable(entries);
    final ticket = ++_ticket;
    _heavyTimer?.cancel();
    _heavyTimer = Timer(_heavyThreshold, () {
      if (ticket == _ticket) state = state.copyWith(isEvaluatingHeavy: true);
    });
    final outcome = await _evaluator.evaluate(
      EvaluationRequest(
        root: snapshot.rootSequence,
        context: snapshot.mathContext,
        variables: <String, String>{...snapshot.variables, ...values},
        isCommit: true,
      ),
    );
    _heavyTimer?.cancel();
    if (ticket != _ticket) {
      state = state.copyWith(isEvaluatingHeavy: false);
      return; // the expression changed in the meantime
    }
    // The caret stays where it was unless a result or an error was on display.
    final caret = snapshot.inputPhase == InputPhase.editing
        ? snapshot.cursorPath
        : CursorPath.root(snapshot.rootSequence.length).toRecords();
    if (outcome.isSuccess) {
      _substituted = outcome.valueEncoded;
      state = state.copyWith(
        inputPhase: InputPhase.editing,
        cursorPath: caret,
        livePreviewPrimary: outcome.primary,
        livePreviewSecondary: outcome.secondary,
        errorMessage: null,
        substitution: note,
        isEvaluatingHeavy: false,
        isInverseActive: refresh ? null : false,
        isHyperbolicActive: refresh ? null : false,
      );
      if (!refresh) _haptics.medium();
    } else {
      // The line is not locked: these values failed, the next ones may not.
      _substituted = null;
      state = state.copyWith(
        inputPhase: InputPhase.editing,
        cursorPath: caret,
        errorMessage: outcome.error!.message,
        livePreviewPrimary: '',
        livePreviewSecondary: null,
        substitution: note,
        isEvaluatingHeavy: false,
        isInverseActive: refresh ? null : false,
        isHyperbolicActive: refresh ? null : false,
      );
      if (!refresh) _haptics.error();
    }
  }

  /// After a change of mode or of a stored variable, what is on display is
  /// worked out again: with the values of `CALC` while its result is showing,
  /// otherwise as the preview.
  void _refresh() {
    final s = state;
    final note = s.substitution;
    if (s.inputPhase == InputPhase.editing && note != null) {
      unawaited(_evaluateWith(_calcValues, note: note, entries: _calcEntries, refresh: true));
    } else {
      unawaited(_requestPreview());
    }
  }

  // -------------------------------------------------------------- undo / redo

  void undo() {
    final s = state;
    if (!s.canUndo) return;
    final previous = s.undoStack.last;
    state = s.copyWith(
      rootSequence: previous,
      cursorPath: CursorPath.root(previous.length).toRecords(),
      inputPhase: InputPhase.editing,
      errorMessage: null,
      undoStack: s.undoStack.sublist(0, s.undoStack.length - 1),
      redoStack: <EditorSequence>[...s.redoStack, s.rootSequence],
    );
    _drafts.write(state.editor);
    unawaited(_requestPreview());
  }

  void redo() {
    final s = state;
    if (!s.canRedo) return;
    final next = s.redoStack.last;
    state = s.copyWith(
      rootSequence: next,
      cursorPath: CursorPath.root(next.length).toRecords(),
      inputPhase: InputPhase.editing,
      errorMessage: null,
      undoStack: <EditorSequence>[...s.undoStack, s.rootSequence],
      redoStack: s.redoStack.sublist(0, s.redoStack.length - 1),
    );
    _drafts.write(state.editor);
    unawaited(_requestPreview());
  }

  // -------------------------------------------------------------------- modes

  void toggleInverse() => state = state.copyWith(isInverseActive: !state.isInverseActive);

  void toggleHyperbolic() => state = state.copyWith(isHyperbolicActive: !state.isHyperbolicActive);

  /// Releases `INV` and `HYP` (after a key that is no key of the editor).
  void releaseShift() {
    if (state.isInverseActive || state.isHyperbolicActive) {
      state = state.copyWith(isInverseActive: false, isHyperbolicActive: false);
    }
  }

  void setActiveTab(int index) {
    if (index < 0 || index > 4 || index == state.activeTabIndex) return;
    state = state.copyWith(activeTabIndex: index);
  }

  void _saveSettings() {
    _repository.saveSettings(
      _repository.loadSettings().copyWith(
            angleUnit: state.angleUnit,
            juxtaposition: state.juxtapositionMode,
            complexEnabled: state.isComplexEnabled,
            engineeringNotation: state.isEngineering,
          ),
    );
  }

  /// `ENG`: engineering notation (exponents in steps of three) on and off.
  /// The result on display is rewritten at once.
  void toggleEngineering() {
    state = state.copyWith(notation: state.isEngineering ? NotationMode.auto : NotationMode.engineering);
    _saveSettings();
    final s = state;
    final calc = s.substitution != null && s.inputPhase == InputPhase.editing;
    if (calc && s.errorMessage != null) return; // the message of a CALC that failed: no number to rewrite
    final shown = s.inputPhase == InputPhase.committedResult ? s.variables['Ans'] : (calc ? _substituted : null);
    if (shown == null) {
      unawaited(_requestPreview());
      return;
    }
    // The short form of a giant factorial (m × 10^E) is all there is of it.
    if (s.livePreviewPrimary.contains(' × 10^')) return;
    try {
      final value = CalcValueCodec.decode(shown);
      state = s.copyWith(
        livePreviewPrimary: MathEngine.format(value, s.mathContext),
        livePreviewSecondary: NumberFormatter.formatSecondary(value, notation: s.notation),
      );
    } on Object {
      // Keep the result as it is written.
    }
  }

  /// DEG → RAD → GRAD → DEG.
  void cycleAngleUnit() {
    const order = AngleUnit.values;
    state = state.copyWith(angleUnit: order[(state.angleUnit.index + 1) % order.length]);
    _saveSettings();
    _refresh();
  }

  void toggleComplex() {
    state = state.copyWith(isComplexEnabled: !state.isComplexEnabled);
    _saveSettings();
    _refresh();
  }

  void toggleJuxtaposition() {
    state = state.copyWith(
      juxtapositionMode: state.juxtapositionMode == JuxtapositionMode.standardTi
          ? JuxtapositionMode.strictCasio
          : JuxtapositionMode.standardTi,
    );
    _saveSettings();
    _refresh();
  }

  // ---------------------------------------------------------------- variables

  void _setVariable(String name, String encoded) {
    state = state.copyWith(variables: <String, String>{...state.variables, name: encoded});
    unawaited(_repository.saveVariable(name, encoded));
    _refresh();
  }

  /// Stores the last result (`Ans`) in [name].
  void storeAnswerIn(String name) => _setVariable(name, state.variables['Ans'] ?? '0');

  /// Resets [name] to zero.
  void clearVariable(String name) => _setVariable(name, '0');

  /// Inserts the variable [name] into the expression.
  void insertVariable(String name) => press(AtomKey(name, AtomKind.variable));

  /// The value `M+` / `M−` operate on: the committed result, or the value of
  /// the expression that is being typed.
  Future<CalcValue?> _currentValue() async {
    final s = state;
    if (s.inputPhase == InputPhase.committedResult) return CalcValueCodec.decode(s.variables['Ans'] ?? '0');
    if (s.inputPhase == InputPhase.editing && s.substitution != null && _substituted != null) {
      return CalcValueCodec.decode(_substituted!); // what CALC has on display
    }
    if (s.rootSequence.isEmpty) return null;
    final outcome = await _evaluator.evaluate(
      EvaluationRequest(root: s.rootSequence, context: s.mathContext, variables: s.variables, isCommit: true),
    );
    return outcome.isSuccess ? CalcValueCodec.decode(outcome.valueEncoded!) : null;
  }

  Future<void> _memory(CalcValue Function(CalcValue memory, CalcValue value) combine) async {
    final value = await _currentValue();
    if (value == null) {
      _haptics.error();
      return;
    }
    try {
      final memory = CalcValueCodec.decode(state.variables['M'] ?? '0');
      _setVariable('M', CalcValueCodec.encode(combine(memory, value)));
      _haptics.medium();
    } on Object {
      _haptics.error();
    }
  }

  /// `M+`
  Future<void> memoryAdd() => _memory(_arithmetic.add);

  /// `M−`
  Future<void> memorySubtract() => _memory(_arithmetic.subtract);

  /// `MR`
  void memoryRecall() => insertVariable('M');

  /// `MC`
  void memoryClear() => clearVariable('M');
}

/// The history tape and its search filter.
class HistoryState {
  const HistoryState({this.entries = const <HistoryEntry>[], this.query = ''});

  final List<HistoryEntry> entries;
  final String query;
}

/// Loads, filters and prunes the history tape.
class HistoryNotifier extends Notifier<HistoryState> {
  late CalculatorRepository _repository;

  @override
  HistoryState build() {
    _repository = ref.read(repositoryProvider);
    scheduleMicrotask(refresh);
    return const HistoryState();
  }

  Future<void> refresh() async {
    final query = state.query;
    final entries = await _repository.history(query: query);
    if (query == state.query) state = HistoryState(entries: entries, query: query);
  }

  Future<void> setQuery(String query) async {
    state = HistoryState(entries: state.entries, query: query);
    await refresh();
  }

  Future<void> delete(int id) async {
    await _repository.deleteHistory(id);
    await refresh();
  }

  Future<void> clear() async {
    await _repository.clearHistory();
    await refresh();
  }
}
