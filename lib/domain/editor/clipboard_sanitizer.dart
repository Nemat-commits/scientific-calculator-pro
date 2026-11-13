import '../models/editor_node.dart';

/// Converts free text (clipboard content, typed formulas) into editor nodes.
///
/// * thousands separators are stripped (`1,250.50` → `1250.50`),
/// * typographic operators are mapped onto the editor's own atoms
///   (`×`/`*`/`·`, `÷`/`/`, `−`/`-`/`–`),
/// * superscripts (`²`, `³`, `⁻¹`) and `^` become [PowerNode]s,
/// * `√`, `∛`, `sqrt(…)`, `cbrt(…)`, `root(n, x)` become [RootNode]s,
/// * `name(…)`, `|…|`, `∫(a, b, f)` and `d/dx(f, x=a)` become the matching
///   templates,
/// * anything that is not part of a formula is dropped.
abstract final class ClipboardSanitizer {
  /// Function names understood in text, lower-case.
  static const Set<String> functionNames = <String>{
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh',
    'ln', 'log', 'log2', 'logb', 'exp', 'abs', 'sgn', 'floor', 'ceil', 'round', 'trunc', 'frac',
    'ncr', 'npr', 'gcd', 'lcm', 'mod', 'min', 'max', 'gamma', 'fact', 'atan2', 'pow',
    're', 'im', 'arg', 'conj', 'det', 'trn', 'inv', 'identity', 'rand',
    'sqrt', 'cbrt', 'root', 'int', 'diff',
  };

  static const Map<String, String> _aliases = <String, String>{
    'arcsin': 'asin', 'arccos': 'acos', 'arctan': 'atan', 'arsinh': 'asinh', 'arcosh': 'acosh', 'artanh': 'atanh',
    'log10': 'log', 'lg': 'log', 'sign': 'sgn', 'int': 'int', 'nchoosek': 'ncr', 'transpose': 'trn',
  };

  static const String _superscripts = '⁰¹²³⁴⁵⁶⁷⁸⁹';

  /// Editor nodes for [text]. With [radix] 2, 8 or 16 the text is read as a
  /// Base-N expression (hex digits are digits, `and`/`or`/`xor`/`not` are
  /// operators).
  static List<EditorNode> sanitize(String text, {int radix = 10}) => _Scanner(text, radix).parseAll();

  /// A complete root sequence for [text].
  static EditorSequence toSequence(String text, {int radix = 10}) => EditorSequence.root(sanitize(text, radix: radix));

  static bool _isDigit(String c) => c.length == 1 && c.codeUnitAt(0) >= 0x30 && c.codeUnitAt(0) <= 0x39;

  static bool _isLetter(String c) {
    if (c.length != 1) return false;
    final u = c.codeUnitAt(0);
    return (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }
}

final class _Scanner {
  _Scanner(String text, this.radix) : chars = text.runes.map(String.fromCharCode).toList();

  final List<String> chars;
  final int radix;
  int pos = 0;

  bool get atEnd => pos >= chars.length;
  String get cur => atEnd ? '' : chars[pos];
  String at(int offset) => pos + offset < chars.length && pos + offset >= 0 ? chars[pos + offset] : '';

  static const AtomNode _open = AtomNode('(', AtomKind.paren);
  static const AtomNode _close = AtomNode(')', AtomKind.paren);

  static const Map<String, (String, AtomKind)> _baseNWords = <String, (String, AtomKind)>{
    'and': ('and', AtomKind.binaryOp),
    'xor': ('xor', AtomKind.binaryOp),
    'or': ('or', AtomKind.binaryOp),
    'not': ('not', AtomKind.unaryPrefix),
    'mod': ('mod', AtomKind.binaryOp),
    'shl': ('<<', AtomKind.binaryOp),
    'shr': ('>>', AtomKind.binaryOp),
  };

  static final RegExp _continental = RegExp(r'\d{1,3}(?:\.\d{3})+,\d+');

  /// Functions that may be written without parentheses (`sin 30`, `ln 2`).
  static const Set<String> _bareFunctions = <String>{
    'sin', 'cos', 'tan', 'asin', 'acos', 'atan', 'sinh', 'cosh', 'tanh', 'asinh', 'acosh', 'atanh',
    'ln', 'log', 'log2', 'exp', 'abs', 'sqrt', 'cbrt',
  };

  void skipSpaces() {
    while (!atEnd && cur.trim().isEmpty) {
      pos++;
    }
  }

  bool _isRadixDigit(String c) {
    if (ClipboardSanitizer._isDigit(c)) return radix != 2 || c == '0' || c == '1';
    if (radix != 16 || c.length != 1) return false;
    final u = c.toUpperCase().codeUnitAt(0);
    return u >= 0x41 && u <= 0x46;
  }

  List<EditorNode> parseAll() {
    final out = <EditorNode>[];
    while (!atEnd) {
      final before = pos;
      out.addAll(parseRun(inArguments: false, stopAtBar: false));
      if (atEnd) break;
      if (cur == '=') break; // "2+2=4": keep the left-hand side only
      if (pos == before) pos++; // stray terminator at top level
    }
    return out;
  }

  /// Parses nodes until an unmatched `)`, a top-level `,` (inside argument
  /// lists), a closing `|` (inside an absolute value) or `=`.
  List<EditorNode> parseRun({required bool inArguments, required bool stopAtBar}) {
    final out = <EditorNode>[];
    var depth = 0;
    while (!atEnd) {
      final c = cur;
      if (c.trim().isEmpty) {
        pos++;
        continue;
      }
      if (c == '=') break;
      if (c == ')') {
        if (depth == 0) break;
        depth--;
        pos++;
        out.add(_close);
        continue;
      }
      if (c == '(') {
        depth++;
        pos++;
        out.add(_open);
        continue;
      }
      if (c == ',' || c == ';') {
        if (depth == 0 && inArguments) break;
        pos++;
        if (inArguments) out.add(const AtomNode(',', AtomKind.separator));
        continue;
      }
      if (c == '|') {
        if (stopAtBar && depth == 0) break;
        pos++;
        final inner = parseRun(inArguments: false, stopAtBar: true);
        if (cur == '|') pos++;
        out.add(_function('abs', <List<EditorNode>>[inner]));
        continue;
      }
      final node = parseItem(allowGrouping: !inArguments);
      if (node != null) out.addAll(node);
    }
    return out;
  }

  static EditorNode _function(String name, List<List<EditorNode>> args) => FunctionCallEditorNode(
        functionName: name,
        argSlots: List<EditorSequence>.unmodifiable(<EditorSequence>[for (final a in args) EditorSequence.fresh(a)]),
      );

  /// Parses one lexical item at the cursor (never a parenthesis or a comma).
  List<EditorNode>? parseItem({required bool allowGrouping}) {
    final c = cur;
    if (radix == 16 && ClipboardSanitizer._isLetter(c)) {
      // A run of letters is a hex word unless it spells an operator.
      var end = pos;
      while (end < chars.length && (ClipboardSanitizer._isLetter(chars[end]) || ClipboardSanitizer._isDigit(chars[end]))) {
        end++;
      }
      final word = chars.sublist(pos, end).join().toLowerCase();
      if (_baseNWords.containsKey(word)) {
        pos = end;
        final (text, kind) = _baseNWords[word]!;
        return <EditorNode>[AtomNode(text, kind)];
      }
      if (chars.sublist(pos, end).every(_isRadixDigit)) return number(allowGrouping: false);
      return identifier();
    }
    if (_isRadixDigit(c) || (c == '.' && radix == 10)) return number(allowGrouping: allowGrouping);
    if (ClipboardSanitizer._isLetter(c)) return identifier();
    pos++;
    switch (c) {
      case '+':
        return const <EditorNode>[AtomNode('+', AtomKind.binaryOp)];
      case '-' || '−' || '–' || '—' || '‒' || '‐':
        return const <EditorNode>[AtomNode('−', AtomKind.binaryOp)];
      case '*':
        if (cur == '*') {
          pos++;
          return <EditorNode>[PowerNode(exponent: EditorSequence.fresh(operand(allowSign: true)))];
        }
        return const <EditorNode>[AtomNode('×', AtomKind.binaryOp)];
      case '×' || '·' || '⋅' || '∙' || '✕' || '✖':
        return const <EditorNode>[AtomNode('×', AtomKind.binaryOp)];
      case '/' || '÷' || '∕' || '⁄':
        return const <EditorNode>[AtomNode('÷', AtomKind.binaryOp)];
      case '^':
        return <EditorNode>[PowerNode(exponent: EditorSequence.fresh(operand(allowSign: true)))];
      case '!':
        return const <EditorNode>[AtomNode('!', AtomKind.unaryPostfix)];
      case '%':
        return const <EditorNode>[AtomNode('%', AtomKind.unaryPostfix)];
      case '°':
        return const <EditorNode>[AtomNode('°', AtomKind.unaryPostfix)];
      case 'π':
        return const <EditorNode>[AtomNode('π', AtomKind.constant)];
      case 'φ' || 'ϕ':
        return const <EditorNode>[AtomNode('φ', AtomKind.constant)];
      case '√':
        return <EditorNode>[RootNode(degree: EditorSequence.fresh(), radicand: EditorSequence.fresh(operand()))];
      case '∛':
        return <EditorNode>[
          RootNode(
            degree: EditorSequence.fresh(const <EditorNode>[AtomNode('3', AtomKind.digit)]),
            radicand: EditorSequence.fresh(operand()),
          ),
        ];
      case '∫':
        skipSpaces();
        if (cur == '(') return <EditorNode>[integral()];
        return null;
      case '<' || '>':
        if (radix != 10 && cur == c) {
          pos++;
          return <EditorNode>[AtomNode('$c$c', AtomKind.binaryOp)];
        }
        return null;
      case '~':
        return radix != 10 ? const <EditorNode>[AtomNode('not', AtomKind.unaryPrefix)] : null;
      case '&':
        return radix != 10 ? const <EditorNode>[AtomNode('and', AtomKind.binaryOp)] : null;
    }
    // Superscript run: ², ³, ⁻¹, ¹⁰ ...
    if (ClipboardSanitizer._superscripts.contains(c) || c == '⁻' || c == '⁺') {
      pos--;
      final exponent = <EditorNode>[];
      while (!atEnd) {
        final s = cur;
        final digit = ClipboardSanitizer._superscripts.indexOf(s);
        if (digit >= 0) {
          exponent.add(AtomNode('$digit', AtomKind.digit));
        } else if (s == '⁻') {
          exponent.add(const AtomNode('−', AtomKind.binaryOp));
        } else if (s != '⁺') {
          break;
        }
        pos++;
      }
      return <EditorNode>[PowerNode(exponent: EditorSequence.fresh(exponent))];
    }
    return null; // not part of a formula: drop it
  }

  /// A numeric literal, with thousands separators removed.
  List<EditorNode> number({required bool allowGrouping}) {
    final out = <EditorNode>[];
    void digit(String d) => out.add(AtomNode(d.toUpperCase(), AtomKind.digit));
    if (radix != 10) {
      while (!atEnd && (_isRadixDigit(cur) || cur == '_')) {
        if (_isRadixDigit(cur)) digit(cur);
        pos++;
      }
      return out;
    }
    if (allowGrouping) {
      // Continental notation: 1.250.000,5 (dots group, the comma is decimal).
      final match = _continental.matchAsPrefix(chars.sublist(pos, pos + 40 > chars.length ? chars.length : pos + 40).join());
      if (match != null) {
        final text = match[0]!;
        final comma = text.indexOf(',');
        for (final d in text.substring(0, comma).replaceAll('.', '').split('')) {
          digit(d);
        }
        out.add(const AtomNode('.', AtomKind.digit));
        for (final d in text.substring(comma + 1).split('')) {
          digit(d);
        }
        pos += text.length;
        return out;
      }
    }
    while (!atEnd) {
      if (ClipboardSanitizer._isDigit(cur)) {
        digit(cur);
        pos++;
      } else if (allowGrouping &&
          (cur == ',' || cur == '\u202F' || cur == '\u00A0' || cur == "'") &&
          out.isNotEmpty &&
          ClipboardSanitizer._isDigit(at(1)) &&
          ClipboardSanitizer._isDigit(at(2)) &&
          ClipboardSanitizer._isDigit(at(3)) &&
          !ClipboardSanitizer._isDigit(at(4))) {
        pos++; // thousands separator
      } else {
        break;
      }
    }
    // A decimal point - or a decimal comma that is not a thousands separator.
    final decimalComma = allowGrouping && cur == ',' && out.isNotEmpty && ClipboardSanitizer._isDigit(at(1));
    if (decimalComma || (cur == '.' && (ClipboardSanitizer._isDigit(at(1)) || out.isNotEmpty))) {
      out.add(const AtomNode('.', AtomKind.digit));
      pos++;
      while (!atEnd && ClipboardSanitizer._isDigit(cur)) {
        digit(cur);
        pos++;
      }
    }
    // Scientific notation: 1e-25, 6.02E23
    if ((cur == 'e' || cur == 'E') && out.isNotEmpty) {
      final signed = at(1) == '-' || at(1) == '+' || at(1) == '−';
      if (ClipboardSanitizer._isDigit(at(signed ? 2 : 1))) {
        out.add(const AtomNode('E', AtomKind.digit));
        pos++;
        if (signed) {
          out.add(AtomNode(cur == '+' ? '+' : '−', AtomKind.binaryOp));
          pos++;
        }
        while (!atEnd && ClipboardSanitizer._isDigit(cur)) {
          digit(cur);
          pos++;
        }
      }
    }
    return out;
  }

  /// The operand of a prefix radical or of `^`: an optional sign, then a
  /// number, a symbol, a call or a parenthesised group, followed by `!` and
  /// further (right-associative) powers.
  List<EditorNode> operand({bool allowSign = false}) {
    final out = <EditorNode>[];
    skipSpaces();
    if (allowSign && (cur == '-' || cur == '−' || cur == '+')) {
      if (cur != '+') out.add(const AtomNode('−', AtomKind.binaryOp));
      pos++;
      skipSpaces();
    }
    if (cur == '(') {
      pos++;
      out.addAll(parseRun(inArguments: false, stopAtBar: false));
      if (cur == ')') pos++;
    } else if (_isRadixDigit(cur) || cur == '.') {
      out.addAll(number(allowGrouping: false));
    } else if (ClipboardSanitizer._isLetter(cur)) {
      out.addAll(identifier(single: true));
    } else if (cur == '√' || cur == '∛' || cur == 'π' || cur == 'φ' || cur == '|') {
      if (cur == '|') {
        pos++;
        final inner = parseRun(inArguments: false, stopAtBar: true);
        if (cur == '|') pos++;
        out.add(_function('abs', <List<EditorNode>>[inner]));
      } else {
        out.addAll(parseItem(allowGrouping: false) ?? const <EditorNode>[]);
      }
    }
    while (cur == '!' || cur == '^' || ClipboardSanitizer._superscripts.contains(cur) && cur.isNotEmpty) {
      out.addAll(parseItem(allowGrouping: false) ?? const <EditorNode>[]);
    }
    return out;
  }

  /// Arguments of a call whose `(` is at the cursor.
  List<List<EditorNode>> arguments() {
    pos++; // (
    final args = <List<EditorNode>>[];
    while (true) {
      args.add(parseRun(inArguments: true, stopAtBar: false));
      if (cur == ',' || cur == ';') {
        pos++;
        continue;
      }
      if (cur == ')') pos++;
      return args;
    }
  }

  EditorNode integral() {
    final args = arguments();
    List<EditorNode> arg(int i) => i < args.length ? args[i] : const <EditorNode>[];
    var variable = 'x';
    if (args.length > 3 && args[3].length == 1 && args[3].first is AtomNode) {
      variable = (args[3].first as AtomNode).text;
    }
    return CalculusIntegralNode(
      lowerBound: EditorSequence.fresh(arg(0)),
      upperBound: EditorSequence.fresh(arg(1)),
      integrand: EditorSequence.fresh(arg(2)),
      dummyVariable: variable,
    );
  }

  /// `d/dx(body, x = point)`; the cursor is on `(`.
  EditorNode derivative(String variable) {
    pos++; // (
    final body = parseRun(inArguments: true, stopAtBar: false);
    var point = const <EditorNode>[];
    if (cur == ',' || cur == ';') {
      pos++;
      skipSpaces();
      // optional "x ="
      var look = pos;
      if (look < chars.length && ClipboardSanitizer._isLetter(chars[look])) {
        look++;
        while (look < chars.length && chars[look].trim().isEmpty) {
          look++;
        }
        if (look < chars.length && chars[look] == '=') pos = look + 1;
      }
      point = parseRun(inArguments: true, stopAtBar: false);
    }
    if (cur == ')') pos++;
    return DerivativeEditorNode(
      body: EditorSequence.fresh(body),
      evalPoint: EditorSequence.fresh(point),
      dummyVariable: variable,
    );
  }

  /// Letters: function calls, named constants, variables.
  ///
  /// With [single] only the first symbol (or call) is consumed.
  List<EditorNode> identifier({bool single = false}) {
    // d/dx(
    if (cur == 'd' && at(1) == '/' && at(2) == 'd' && ClipboardSanitizer._isLetter(at(3))) {
      var look = pos + 4;
      while (look < chars.length && chars[look].trim().isEmpty) {
        look++;
      }
      if (look < chars.length && chars[look] == '(') {
        final variable = at(3);
        pos = look;
        return <EditorNode>[derivative(variable)];
      }
    }
    final start = pos;
    var end = pos;
    while (end < chars.length && ClipboardSanitizer._isLetter(chars[end])) {
      end++;
    }
    // trailing digits that belong to a function name: log2, log10, atan2
    var digitsEnd = end;
    while (digitsEnd < chars.length && ClipboardSanitizer._isDigit(chars[digitsEnd])) {
      digitsEnd++;
    }
    final out = <EditorNode>[];
    var p = start;

    // A call that starts at [from]: `name(` (the name may end in digits, as
    // in log2), or a bare unary function directly followed by its operand.
    EditorNode? callAt(int from) {
      for (var stop = digitsEnd; stop > from + 1; stop--) {
        if (stop > end && stop != digitsEnd) continue;
        final raw = chars.sublist(from, stop).join().toLowerCase();
        final name = ClipboardSanitizer._aliases[raw] ?? raw;
        if (!ClipboardSanitizer.functionNames.contains(name)) continue;
        var look = stop;
        while (look < chars.length && chars[look].trim().isEmpty) {
          look++;
        }
        final next = look < chars.length ? chars[look] : '';
        if (next == '(' && stop >= end) {
          pos = look;
          return _call(name);
        }
        final startsOperand = ClipboardSanitizer._isDigit(next) ||
            ClipboardSanitizer._isLetter(next) ||
            next == '.' ||
            next == 'π' ||
            next == '√';
        if (stop <= end && _bareFunctions.contains(name) && startsOperand) {
          pos = look;
          final argument = operand();
          return name == 'sqrt'
              ? RootNode(degree: EditorSequence.fresh(), radicand: EditorSequence.fresh(argument))
              : _function(name, <List<EditorNode>>[argument]);
        }
      }
      return null;
    }

    // Matrix variables of the lab: MatA, MatB, MatC.
    bool isMatrixAt(int from) =>
        end - from >= 4 && chars.sublist(from, from + 3).join() == 'Mat' && 'ABC'.contains(chars[from + 3]);

    bool isWordAt(int from) {
      final lower = chars.sublist(from, end).join().toLowerCase();
      return lower.startsWith('ans') || lower.startsWith('pi') || lower.startsWith('phi') || isMatrixAt(from);
    }

    // Prose ("price", "total") is not part of a formula: a run of four or
    // more letters that contains no call and no named constant is dropped.
    if (radix == 10 && end - start >= 4) {
      var meaningful = false;
      final probe = pos;
      for (var q = start; q < end && !meaningful; q++) {
        if (isWordAt(q)) meaningful = true;
        for (var stop = digitsEnd; stop > q + 1 && !meaningful; stop--) {
          if (stop > end && stop != digitsEnd) continue;
          final raw = chars.sublist(q, stop).join().toLowerCase();
          if (ClipboardSanitizer.functionNames.contains(ClipboardSanitizer._aliases[raw] ?? raw)) meaningful = true;
        }
      }
      pos = probe;
      if (!meaningful) {
        pos = end;
        return out;
      }
    }

    while (p < end) {
      final call = callAt(p);
      if (call != null) {
        out.add(call);
        return out;
      }
      final rest = chars.sublist(p, end).join();
      final lower = rest.toLowerCase();
      if (radix != 10) {
        final word = _baseNWords.entries.where((e) => lower.startsWith(e.key)).firstOrNull;
        if (word != null) {
          out.add(AtomNode(word.value.$1, word.value.$2));
          p += word.key.length;
          pos = p;
          if (single) return out;
          continue;
        }
      }
      if (isMatrixAt(p)) {
        out.add(AtomNode(chars.sublist(p, p + 4).join(), AtomKind.variable));
        p += 4;
      } else if (lower.startsWith('ans')) {
        out.add(const AtomNode('Ans', AtomKind.variable));
        p += 3;
      } else if (lower.startsWith('phi')) {
        out.add(const AtomNode('φ', AtomKind.constant));
        p += 3;
      } else if (lower.startsWith('pi')) {
        out.add(const AtomNode('π', AtomKind.constant));
        p += 2;
      } else if (lower.startsWith('mod') && rest.length == 3) {
        out.add(const AtomNode('mod', AtomKind.binaryOp));
        p += 3;
      } else {
        final letter = chars[p];
        out.add(letter == 'e' || letter == 'i' ? AtomNode(letter, AtomKind.constant) : AtomNode(letter, AtomKind.variable));
        p += 1;
      }
      pos = p;
      if (single) return out;
    }
    pos = p;
    return out;
  }

  /// A call of [name]; the cursor is on `(`.
  EditorNode _call(String name) {
    if (name == 'int') return integral();
    if (name == 'diff') return derivative('x');
    final args = arguments();
    List<EditorNode> arg(int i) => i < args.length ? args[i] : const <EditorNode>[];
    switch (name) {
      case 'sqrt':
        return RootNode(degree: EditorSequence.fresh(), radicand: EditorSequence.fresh(arg(0)));
      case 'cbrt':
        return RootNode(
          degree: EditorSequence.fresh(const <EditorNode>[AtomNode('3', AtomKind.digit)]),
          radicand: EditorSequence.fresh(arg(0)),
        );
      case 'root':
        return RootNode(degree: EditorSequence.fresh(arg(0)), radicand: EditorSequence.fresh(arg(1)));
      default:
        return _function(name, args);
    }
  }
}
