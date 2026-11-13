import 'package:decimal/decimal.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_typography.dart';
import '../../domain/compiler/tree_to_token_lowerer.dart';
import '../../domain/evaluator/algebra_solver_engine.dart';
import '../../domain/evaluator/number_formatter.dart';
import '../../domain/math_engine.dart';
import '../../domain/models/calc_error.dart';
import '../../domain/models/calc_value.dart';
import '../../domain/models/math_context.dart';
import '../state/calculator_notifier.dart';
import '../widgets/calc_key_button.dart';
import '../widgets/lab_widgets.dart';
import '../widgets/segmented_tab_bar.dart';

/// Value typed into a lab field (`3`, `−2.5`, `1/3`, `4E-3`); empty is zero.
CalcValue _fieldValue(String text) => text.trim().isEmpty ? Values.zero : MathEngine.evaluateText(text).value;

Decimal _fieldDecimal(String text) => _fieldValue(text).asDecimal;

String _show(CalcValue v, [int prec = 12]) => NumberFormatter.formatValue(v, prec: prec);

String _showDec(Decimal? d, [int prec = 10]) => d == null ? '—' : NumberFormatter.formatDec(d, prec: prec);

/// Tab 3: Solver, Matrix, Table, Stats and Base-N sub-modes.
class AdvancedLabTabView extends StatefulWidget {
  const AdvancedLabTabView({super.key});

  static const List<String> modes = <String>['Solver', 'Matrix', 'Table', 'Stats', 'Base-N'];

  @override
  State<AdvancedLabTabView> createState() => _AdvancedLabTabViewState();
}

class _AdvancedLabTabViewState extends State<AdvancedLabTabView> {
  int _mode = 0;

  @override
  Widget build(BuildContext context) => Column(
        children: <Widget>[
          SegmentedTabBar(
            labels: AdvancedLabTabView.modes,
            selectedIndex: _mode,
            height: 36,
            onSelected: (i) => setState(() => _mode = i),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: IndexedStack(
              index: _mode,
              children: const <Widget>[_SolverView(), _MatrixView(), _TableView(), _StatsView(), _BaseNView()],
            ),
          ),
        ],
      );
}

/// Content above a [MiniKeypad].
class _WithKeypad extends StatelessWidget {
  const _WithKeypad({required this.content, required this.keypad});

  final Widget content;
  final Widget keypad;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final pad = (constraints.maxHeight * 0.46).clamp(120.0, 200.0);
          return Column(
            children: <Widget>[
              Expanded(child: Panel(child: content)),
              const SizedBox(height: 8),
              SizedBox(height: pad, child: keypad),
            ],
          );
        },
      );
}

Widget _errorText(String message) => Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Text(message, style: AppTypography.ui(size: 12.5, weight: AppWeight.medium, color: AppColors.error)),
    );

Widget _mathLabel(String text) =>
    Text(text, style: AppTypography.mono(size: 15, weight: AppWeight.medium, color: AppColors.textSecondary));

// ----------------------------------------------------------------------------
// Solver
// ----------------------------------------------------------------------------

class _SolverView extends StatefulWidget {
  const _SolverView();

  @override
  State<_SolverView> createState() => _SolverViewState();
}

class _SolverViewState extends State<_SolverView> {
  int _degree = 2;
  String _active = 'a';
  final Map<String, String> _values = <String, String>{'a': '', 'b': '', 'c': '', 'd': ''};
  PolynomialSolution? _solution;
  String? _error;

  List<String> get _fields => _degree == 2 ? const <String>['a', 'b', 'c'] : const <String>['a', 'b', 'c', 'd'];

  void _edit(String Function(String) change) => setState(() {
        _values[_active] = change(_values[_active]!);
        _solution = null;
        _error = null;
      });

  void _solve() {
    setState(() {
      try {
        _solution = PolynomialSolver.solve(<CalcValue>[for (final f in _fields) _fieldValue(_values[f]!)]);
        _error = null;
      } on CalcError catch (e) {
        _solution = null;
        _error = e.message;
      }
    });
  }

  void _enter() {
    final index = _fields.indexOf(_active);
    if (index + 1 < _fields.length) {
      setState(() => _active = _fields[index + 1]);
    } else {
      _solve();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String id) => LabField(
          value: _values[id]!,
          active: _active == id,
          label: id,
          onTap: () => setState(() => _active = id),
        );
    final solution = _solution;
    final terms = _degree == 2 ? const <String>['x² +', 'x +', '= 0'] : const <String>['x³ +', 'x² +', 'x +', '= 0'];
    return _WithKeypad(
      keypad: MiniKeypad(
        onInput: (c) => _edit((v) => FieldInput.append(v, c)),
        onBackspace: () => _edit(FieldInput.backspace),
        onClear: () => _edit((_) => ''),
        onEnter: _enter,
        enterLabel: _active == _fields.last ? 'Solve' : '⏎',
      ),
      content: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: ChoiceChips(
                  labels: const <String>['Quadratic', 'Cubic'],
                  selected: _degree - 2,
                  onSelected: (i) => setState(() {
                    _degree = i + 2;
                    if (!_fields.contains(_active)) _active = 'a';
                    _solution = null;
                    _error = null;
                  }),
                ),
              ),
              SmallButton('Solve', primary: true, onTap: _solve),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              for (var i = 0; i < _fields.length; i++) ...<Widget>[field(_fields[i]), _mathLabel(terms[i])],
            ],
          ),
          if (_error != null) _errorText(_error!),
          if (solution != null) ...<Widget>[
            const SizedBox(height: 10),
            const SectionLabel('Roots'),
            for (var i = 0; i < solution.roots.length; i++)
              ValueRow(
                'x${i + 1}',
                () {
                  final exact = NumberFormatter.formatSecondary(solution.roots[i]);
                  final decimal = _show(solution.roots[i]);
                  return exact == null ? decimal : '$exact  =  $decimal';
                }(),
                emphasised: true,
              ),
            if (solution.discriminant != null) ValueRow('Δ = b² − 4ac', _show(solution.discriminant!)),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Matrix
// ----------------------------------------------------------------------------

class _MatrixView extends StatefulWidget {
  const _MatrixView();

  @override
  State<_MatrixView> createState() => _MatrixViewState();
}

class _MatrixViewState extends State<_MatrixView> {
  String _matrix = 'A';
  final Map<String, int> _rows = <String, int>{'A': 2, 'B': 2};
  final Map<String, int> _cols = <String, int>{'A': 2, 'B': 2};
  final Map<String, String> _cells = <String, String>{};
  int _row = 0;
  int _col = 0;
  String? _resultLabel;
  CalcValue? _result;
  String? _error;

  String _id(String m, int r, int c) => '$m:$r:$c';

  String get _activeId => _id(_matrix, _row, _col);

  void _edit(String Function(String) change) => setState(() {
        _cells[_activeId] = change(_cells[_activeId] ?? '');
      });

  void _enter() => setState(() {
        if (_col + 1 < _cols[_matrix]!) {
          _col++;
        } else if (_row + 1 < _rows[_matrix]!) {
          _row++;
          _col = 0;
        } else {
          _row = 0;
          _col = 0;
        }
      });

  void _resize(String m, {int rows = 0, int cols = 0}) => setState(() {
        _rows[m] = (_rows[m]! + rows).clamp(1, MatrixOps.maxDimension);
        _cols[m] = (_cols[m]! + cols).clamp(1, MatrixOps.maxDimension);
        if (_row >= _rows[_matrix]!) _row = _rows[_matrix]! - 1;
        if (_col >= _cols[_matrix]!) _col = _cols[_matrix]! - 1;
      });

  MatrixVal _build(String m) => MatrixOps.of(<List<Decimal>>[
        for (var r = 0; r < _rows[m]!; r++)
          <Decimal>[for (var c = 0; c < _cols[m]!; c++) _fieldDecimal(_cells[_id(m, r, c)] ?? '')],
      ]);

  void _run(String label, CalcValue Function(MatrixVal a, MatrixVal b, MatrixVal selected) operation) {
    setState(() {
      try {
        final a = _build('A'), b = _build('B');
        _result = operation(a, b, _matrix == 'A' ? a : b);
        _resultLabel = label;
        _error = null;
      } on CalcError catch (e) {
        _result = null;
        _error = e.message;
      }
    });
  }

  CalcValue _expression(String text, MatrixVal a, MatrixVal b) =>
      MathEngine.evaluateText(text, variables: <String, CalcValue>{'MatA': a, 'MatB': b}).value;

  void _storeResult() {
    final result = _result;
    if (result is! MatrixVal) return;
    setState(() {
      _rows[_matrix] = result.rows;
      _cols[_matrix] = result.cols;
      for (var r = 0; r < result.rows; r++) {
        for (var c = 0; c < result.cols; c++) {
          _cells[_id(_matrix, r, c)] = NumberFormatter.formatDec(result.grid[r][c], prec: 12).replaceAll('-', '−');
        }
      }
      _row = 0;
      _col = 0;
    });
  }

  Widget _stepper(String label, int value, VoidCallback minus, VoidCallback plus) => Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('$label ', style: AppTypography.ui(size: 12, color: AppColors.textMuted)),
          SmallButton('−', onTap: value > 1 ? minus : null),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text('$value', style: AppTypography.mono(size: 14, weight: AppWeight.medium)),
          ),
          SmallButton('+', onTap: value < MatrixOps.maxDimension ? plus : null),
        ],
      );

  Widget _grid(MatrixVal m) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          for (final row in m.grid)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  for (final cell in row)
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          AppTypography.signs(NumberFormatter.formatDec(cell, prec: 8)),
                          style: AppTypography.mono(size: 15, weight: AppWeight.medium),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final m = _matrix;
    final result = _result;
    return _WithKeypad(
      keypad: MiniKeypad(
        onInput: (c) => _edit((v) => FieldInput.append(v, c)),
        onBackspace: () => _edit(FieldInput.backspace),
        onClear: () => _edit((_) => ''),
        onEnter: _enter,
      ),
      content: ListView(
        children: <Widget>[
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 96,
                child: ChoiceChips(
                  labels: const <String>['A', 'B'],
                  selected: m == 'A' ? 0 : 1,
                  onSelected: (i) => setState(() {
                    _matrix = i == 0 ? 'A' : 'B';
                    _row = 0;
                    _col = 0;
                  }),
                ),
              ),
              _stepper('rows', _rows[m]!, () => _resize(m, rows: -1), () => _resize(m, rows: 1)),
              _stepper('cols', _cols[m]!, () => _resize(m, cols: -1), () => _resize(m, cols: 1)),
            ],
          ),
          const SizedBox(height: 8),
          for (var r = 0; r < _rows[m]!; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: <Widget>[
                  for (var c = 0; c < _cols[m]!; c++) ...<Widget>[
                    if (c > 0) const SizedBox(width: 6),
                    Expanded(
                      child: LabField(
                        value: _cells[_id(m, r, c)] ?? '',
                        active: r == _row && c == _col,
                        minWidth: 0,
                        onTap: () => setState(() {
                          _row = r;
                          _col = c;
                        }),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              SmallButton('A + B', onTap: () => _run('A + B', (a, b, _) => _expression('MatA+MatB', a, b))),
              SmallButton('A − B', onTap: () => _run('A − B', (a, b, _) => _expression('MatA−MatB', a, b))),
              SmallButton('A × B', onTap: () => _run('A × B', (a, b, _) => _expression('MatA×MatB', a, b))),
              SmallButton('det $m', onTap: () => _run('det $m', (_, __, s) => DecimalVal(MatrixOps.determinant(s)))),
              SmallButton('$m⁻¹', onTap: () => _run('$m⁻¹', (_, __, s) => MatrixOps.inverse(s))),
              SmallButton('trn $m', onTap: () => _run('trn $m', (_, __, s) => MatrixOps.transpose(s))),
              SmallButton('rank $m', onTap: () => _run('rank $m', (_, __, s) => Values.ofInt(MatrixOps.rank(s)))),
              SmallButton('tr $m', onTap: () => _run('tr $m', (_, __, s) => DecimalVal(MatrixOps.trace(s)))),
            ],
          ),
          if (_error != null) _errorText(_error!),
          if (result != null) ...<Widget>[
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                Expanded(child: SectionLabel(_resultLabel ?? 'Result')),
                if (result is MatrixVal) SmallButton('→ $m', onTap: _storeResult),
              ],
            ),
            if (result is MatrixVal) _grid(result) else ValueRow('=', _show(result), emphasised: true),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Table
// ----------------------------------------------------------------------------

class _TableView extends ConsumerStatefulWidget {
  const _TableView();

  @override
  ConsumerState<_TableView> createState() => _TableViewState();
}

class _TableViewState extends ConsumerState<_TableView> {
  static const List<String> _order = <String>['start', 'end', 'step'];

  String _active = 'start';
  final Map<String, String> _values = <String, String>{'start': '1', 'end': '5', 'step': '1'};
  List<FunctionTableRow>? _rows;
  String? _error;

  void _edit(String Function(String) change) => setState(() {
        _values[_active] = change(_values[_active]!);
      });

  void _generate() {
    final state = ref.read(calculatorProvider);
    setState(() {
      try {
        _rows = FunctionTableEngine.generate(
          function: state.rootSequence,
          start: _fieldDecimal(_values['start']!),
          end: _fieldDecimal(_values['end']!),
          step: _fieldDecimal(_values['step']!),
          context: state.mathContext,
          variables: const <String, CalcValue>{},
          precision: 10,
        );
        _error = null;
      } on CalcError catch (e) {
        _rows = null;
        _error = e.message;
      }
    });
  }

  void _enter() {
    final index = _order.indexOf(_active);
    if (index + 1 < _order.length) {
      setState(() => _active = _order[index + 1]);
    } else {
      _generate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final root = ref.watch(calculatorProvider.select((s) => s.rootSequence));
    final expression = TreeToTokenLowerer.toDisplayText(root);
    final rows = _rows;
    return _WithKeypad(
      keypad: MiniKeypad(
        onInput: (c) => _edit((v) => FieldInput.append(v, c)),
        onBackspace: () => _edit(FieldInput.backspace),
        onClear: () => _edit((_) => ''),
        onEnter: _enter,
        enterLabel: _active == 'step' ? 'Run' : '⏎',
      ),
      content: ListView(
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('f(x) = ', style: AppTypography.mono(size: 15, weight: AppWeight.medium, color: AppColors.textMuted)),
              Expanded(
                child: Text(
                  expression.isEmpty ? 'type a formula with x on the keypad' : expression,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: expression.isEmpty
                      ? AppTypography.ui(size: 12.5, color: AppColors.textFaint)
                      : AppTypography.mono(size: 15, weight: AppWeight.medium),
                ),
              ),
              SmallButton('Run', primary: true, onTap: expression.isEmpty ? null : _generate),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              for (final id in _order) ...<Widget>[
                if (id != _order.first) const SizedBox(width: 6),
                Expanded(
                  child: LabField(
                    value: _values[id]!,
                    active: _active == id,
                    label: id,
                    minWidth: 0,
                    onTap: () => setState(() => _active = id),
                  ),
                ),
              ],
            ],
          ),
          if (_error != null) _errorText(_error!),
          if (rows != null) ...<Widget>[
            const SizedBox(height: 8),
            for (final row in rows)
              ValueRow('x = ${row.x.replaceAll('-', '−')}', row.value ?? row.error!, numeric: row.value != null),
            if (rows.length >= FunctionTableEngine.maxRows)
              _errorText('Stopped after ${FunctionTableEngine.maxRows} rows'),
          ],
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// Statistics
// ----------------------------------------------------------------------------

class _StatsView extends StatefulWidget {
  const _StatsView();

  @override
  State<_StatsView> createState() => _StatsViewState();
}

class _StatsViewState extends State<_StatsView> {
  bool _paired = false;
  String _active = 'x';
  String _x = '';
  String _y = '';
  final List<(String, String)> _data = <(String, String)>[];
  String? _error;

  void _edit(String Function(String) change) => setState(() {
        if (_active == 'x') {
          _x = change(_x);
        } else {
          _y = change(_y);
        }
        _error = null;
      });

  void _enter() {
    if (_paired && _active == 'x') {
      setState(() => _active = 'y');
      return;
    }
    if (_x.isEmpty || (_paired && _y.isEmpty)) return;
    setState(() {
      try {
        _fieldDecimal(_x);
        if (_paired) _fieldDecimal(_y);
        _data.add((_x, _paired ? _y : ''));
        _x = '';
        _y = '';
        _active = 'x';
        _error = null;
      } on CalcError catch (e) {
        _error = e.message;
      }
    });
  }

  List<Widget> _results() {
    if (_data.isEmpty) {
      return <Widget>[
        Text('Type a value and press Add.', style: AppTypography.ui(size: 12.5, color: AppColors.textFaint)),
      ];
    }
    try {
      final xs = <Decimal>[for (final d in _data) _fieldDecimal(d.$1)];
      if (!_paired) {
        final s = StatisticsEngine.oneVariable(xs);
        return <Widget>[
          ValueRow('n', '${s.n}'),
          ValueRow('mean', _showDec(s.mean), emphasised: true),
          ValueRow('Σx', _showDec(s.sum)),
          ValueRow('Σx²', _showDec(s.sumOfSquares)),
          ValueRow('σ (population)', _showDec(s.populationStdDev)),
          ValueRow('s (sample)', _showDec(s.sampleStdDev)),
          ValueRow('min', _showDec(s.min)),
          ValueRow('Q1', _showDec(s.q1)),
          ValueRow('median', _showDec(s.median)),
          ValueRow('Q3', _showDec(s.q3)),
          ValueRow('max', _showDec(s.max)),
        ];
      }
      final t = StatisticsEngine.twoVariable(xs, <Decimal>[for (final d in _data) _fieldDecimal(d.$2)]);
      return <Widget>[
        ValueRow('n', '${t.x.n}'),
        ValueRow('mean x', _showDec(t.x.mean)),
        ValueRow('mean y', _showDec(t.y.mean)),
        ValueRow('σx', _showDec(t.x.populationStdDev)),
        ValueRow('σy', _showDec(t.y.populationStdDev)),
        ValueRow('Σxy', _showDec(t.sumOfProducts)),
        ValueRow('y = a + b·x', 'a = ${_showDec(t.intercept, 8)}', emphasised: true),
        ValueRow('', 'b = ${_showDec(t.slope, 8)}', emphasised: true),
        ValueRow('r', _showDec(t.correlation)),
        ValueRow('r²', _showDec(t.rSquared)),
      ];
    } on CalcError catch (e) {
      return <Widget>[_errorText(e.message)];
    }
  }

  @override
  Widget build(BuildContext context) => _WithKeypad(
        keypad: MiniKeypad(
          onInput: (c) => _edit((v) => FieldInput.append(v, c)),
          onBackspace: () => _edit(FieldInput.backspace),
          onClear: () => _edit((_) => ''),
          onEnter: _enter,
          enterLabel: _paired && _active == 'x' ? '⏎' : 'Add',
        ),
        content: ListView(
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: ChoiceChips(
                    labels: const <String>['1-Var', '2-Var'],
                    selected: _paired ? 1 : 0,
                    onSelected: (i) => setState(() {
                      _paired = i == 1;
                      _data.clear();
                      _active = 'x';
                      _x = '';
                      _y = '';
                    }),
                  ),
                ),
                SmallButton('Clear', danger: true, onTap: _data.isEmpty ? null : () => setState(_data.clear)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Expanded(
                  child: LabField(value: _x, active: _active == 'x', label: 'x', minWidth: 0, onTap: () => setState(() => _active = 'x')),
                ),
                if (_paired) ...<Widget>[
                  const SizedBox(width: 6),
                  Expanded(
                    child: LabField(value: _y, active: _active == 'y', label: 'y', minWidth: 0, onTap: () => setState(() => _active = 'y')),
                  ),
                ],
              ],
            ),
            if (_error != null) _errorText(_error!),
            if (_data.isNotEmpty) ...<Widget>[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: <Widget>[
                  for (var i = 0; i < _data.length; i++)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() => _data.removeAt(i)),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.bgObsidian,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.panelBorder),
                        ),
                        child: Text(
                          AppTypography.signs(_paired ? '(${_data[i].$1}, ${_data[i].$2}) ×' : '${_data[i].$1} ×'),
                          style: AppTypography.mono(size: 12.5, color: AppColors.textSecondary),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            ..._results(),
          ],
        ),
      );
}

// ----------------------------------------------------------------------------
// Base-N
// ----------------------------------------------------------------------------

class _BaseNView extends StatefulWidget {
  const _BaseNView();

  @override
  State<_BaseNView> createState() => _BaseNViewState();
}

class _BaseNViewState extends State<_BaseNView> {
  static const List<int> _radices = <int>[16, 10, 8, 2];
  static const List<String> _radixNames = <String>['HEX', 'DEC', 'OCT', 'BIN'];
  static const List<int> _words = <int>[8, 16, 32, 64];
  static const List<String> _wordTokens = <String>[' AND ', ' OR ', ' XOR ', 'NOT ', ' << ', ' >> '];

  BaseNConfig _config = const BaseNConfig(radix: 16, wordSize: 32);
  String _input = '';
  BitwiseVal? _value;
  String? _error;

  void _evaluate() {
    if (_input.trim().isEmpty) {
      _value = null;
      _error = null;
      return;
    }
    try {
      final v = MathEngine.evaluateText(_input, context: MathContext(baseN: _config)).value;
      _value = v is BitwiseVal ? v : null;
      _error = null;
    } on CalcError catch (e) {
      _value = null;
      _error = e.message;
    }
  }

  void _type(String token) => setState(() {
        if (_input.length < 120) _input += token;
        _evaluate();
      });

  void _backspace() => setState(() {
        for (final word in _wordTokens) {
          if (_input.endsWith(word)) {
            _input = _input.substring(0, _input.length - word.length);
            _evaluate();
            return;
          }
        }
        if (_input.isNotEmpty) _input = _input.substring(0, _input.length - 1);
        _evaluate();
      });

  /// `=`: the result becomes the new input.
  void _commit() => setState(() {
        final v = _value;
        if (v != null) _input = NumberFormatter.formatBitwise(v, radix: _config.radix).replaceAll('-', '−');
        _evaluate();
      });

  void _reconfigure(BaseNConfig next) => setState(() {
        final v = _value;
        _config = next;
        _input = v == null ? '' : NumberFormatter.formatBitwise(BaseN.convert(v, next), radix: next.radix).replaceAll('-', '−');
        _evaluate();
      });

  bool _digitAllowed(String d) {
    final v = int.parse(d, radix: 16);
    return v < _config.radix;
  }

  @override
  Widget build(BuildContext context) {
    Widget digit(String d) => CalcKeyButton(
          label: d,
          fontSize: 17,
          radius: 10,
          onPressed: _digitAllowed(d) ? () => _type(d) : null,
        );
    Widget op(String label, String token, {KeyTone tone = KeyTone.operator, double size = 15}) => CalcKeyButton(
          label: label,
          tone: tone,
          fontSize: size,
          radius: 10,
          onPressed: () => _type(token),
        );
    final value = _value;
    String word(int radix) {
      if (value == null) return '—';
      final text = NumberFormatter.formatBitwise(value, radix: radix);
      return radix == 10 ? NumberFormatter.groupThousands(text) : NumberFormatter.groupWord(text);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final pad = (constraints.maxHeight * 0.52).clamp(150.0, 230.0);
        return Column(
          children: <Widget>[
            Expanded(
              child: Panel(
                child: ListView(
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: ChoiceChips(
                            labels: <String>[for (final w in _words) '$w-bit'],
                            selected: _words.indexOf(_config.wordSize),
                            onSelected: (i) => _reconfigure(_config.copyWith(wordSize: _words[i])),
                          ),
                        ),
                        SmallButton(
                          _config.isSigned ? 'signed' : 'unsigned',
                          onTap: () => _reconfigure(_config.copyWith(isSigned: !_config.isSigned)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: AppColors.bgObsidian,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _error == null ? AppColors.accentSoft : AppColors.error),
                      ),
                      child: Text(
                        _input.isEmpty ? '0' : AppTypography.signs(_input),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: AppTypography.mono(
                          size: 18,
                          weight: AppWeight.medium,
                          color: _input.isEmpty ? AppColors.textFaint : AppColors.textPrimary,
                        ),
                      ),
                    ),
                    if (_error != null) _errorText(_error!),
                    const SizedBox(height: 6),
                    for (var i = 0; i < _radices.length; i++)
                      ValueRow(
                        _radixNames[i],
                        word(_radices[i]),
                        emphasised: _radices[i] == _config.radix,
                        onTap: () => _reconfigure(_config.copyWith(radix: _radices[i])),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: pad,
              child: KeyGrid(
                gap: 5,
                rows: <List<Widget>>[
                  <Widget>[digit('A'), digit('B'), digit('C'), digit('D'), digit('E'), digit('F')],
                  <Widget>[digit('7'), digit('8'), digit('9'), op('÷', '÷', size: 18), op('AND', ' AND ', tone: KeyTone.function, size: 12), op('OR', ' OR ', tone: KeyTone.function, size: 12)],
                  <Widget>[digit('4'), digit('5'), digit('6'), op('×', '×', size: 18), op('XOR', ' XOR ', tone: KeyTone.function, size: 12), op('NOT', 'NOT ', tone: KeyTone.function, size: 12)],
                  <Widget>[digit('1'), digit('2'), digit('3'), op('−', '−', size: 18), op('<<', ' << ', tone: KeyTone.function, size: 13), op('>>', ' >> ', tone: KeyTone.function, size: 13)],
                  <Widget>[
                    digit('0'),
                    op('(', '(', tone: KeyTone.function, size: 16),
                    op(')', ')', tone: KeyTone.function, size: 16),
                    op('+', '+', size: 18),
                    CalcKeyButton(
                      label: '⌫',
                      tone: KeyTone.danger,
                      fontSize: 16,
                      radius: 10,
                      repeats: true,
                      semanticLabel: 'Backspace',
                      onPressed: _backspace,
                      onLongPress: () => setState(() {
                        _input = '';
                        _evaluate();
                      }),
                    ),
                    CalcKeyButton(label: '=', tone: KeyTone.equals, fontSize: 18, radius: 10, onPressed: _commit),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
