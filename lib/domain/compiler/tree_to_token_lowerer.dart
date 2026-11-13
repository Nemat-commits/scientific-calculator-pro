import '../models/editor_node.dart';

/// Lexical category of a [Token].
enum TokenKind {
  number,
  constant,
  variable,
  operator,
  postfix,
  prefix,
  leftParen,
  rightParen,
  comma,
  function,
  derivative,
  integral,
  equals,
}

/// One element of the structural token stream.
final class Token {
  const Token(this.kind, this.text, {this.implicit = false, this.tight = false, this.variable});

  final TokenKind kind;

  /// Lexeme as it reads in the linear form of the expression.
  final String text;

  /// Multiplication inserted by the implicit-multiplication normaliser.
  final bool implicit;

  /// Implicit multiplication that binds tighter than `×` and `÷`.
  final bool tight;

  /// Bound variable of a derivative / integral token.
  final String? variable;

  @override
  String toString() => implicit ? (tight ? '⊗' : '·') : text;
}

/// Flattens a 2D [EditorSequence] into a linear token stream.
///
/// Templates become explicitly parenthesised groups, so the parser never has
/// to guess where a numerator or an exponent ends:
///
/// | node          | tokens                               |
/// |---------------|--------------------------------------|
/// | fraction      | `( ( num ) / ( den ) )`              |
/// | power         | `^ ( exponent )`                     |
/// | square root   | `√ ( radicand )`                     |
/// | n-th root     | `root ( degree , radicand )`         |
/// | function      | `name ( arg , … )`                   |
/// | integral      | `∫ ( lower , upper , integrand )`    |
/// | derivative    | `d/dx ( body , x = point )`          |
abstract final class TreeToTokenLowerer {
  static const Token _open = Token(TokenKind.leftParen, '(');
  static const Token _close = Token(TokenKind.rightParen, ')');
  static const Token _comma = Token(TokenKind.comma, ',');

  /// Token stream of [sequence].
  static List<Token> lower(EditorSequence sequence) {
    final out = <Token>[];
    _lowerSequence(sequence, out);
    return out;
  }

  /// Linear text of [sequence], e.g. `((1)/(2))+3`.
  static String toText(EditorSequence sequence) => textOf(lower(sequence));

  /// Linear text for people (history tape, clipboard): [toText] without the
  /// parentheses that only delimit template slots - `5^2` rather than `5^(2)`,
  /// `(1/2)+3` rather than `((1)/(2))+3`. A pair is dropped only where the
  /// text still parses back to the same expression.
  static String toDisplayText(EditorSequence sequence) {
    final out = <Token>[];
    _lowerSequence(sequence, out, pretty: true);
    return textOf(out);
  }

  /// A slot that reads as one operand without parentheses: a plain number or
  /// a single symbol.
  static bool _isSimple(EditorSequence slot) {
    final nodes = slot.children;
    if (nodes.isEmpty) return false;
    if (nodes.length == 1) {
      final only = nodes.first;
      if (only is AtomNode && (only.kind == AtomKind.constant || only.kind == AtomKind.variable)) return true;
    }
    return nodes.every((n) => n is AtomNode && n.kind == AtomKind.digit && RegExp(r'^[0-9.]$').hasMatch(n.text));
  }

  /// Whether [next] cannot be glued onto a preceding bare operand.
  static bool _isBoundary(EditorNode? next) =>
      next == null ||
      (next is AtomNode &&
          (next.kind == AtomKind.binaryOp ||
              next.kind == AtomKind.separator ||
              (next.kind == AtomKind.paren && next.text == ')')));

  /// Concatenated lexemes of [tokens].
  static String textOf(List<Token> tokens) => tokens.where((t) => !t.implicit).map((t) => t.text).join();

  static void _lowerSequence(EditorSequence sequence, List<Token> out, {bool pretty = false}) {
    final literal = StringBuffer();

    void flush() {
      if (literal.isNotEmpty) {
        out.add(Token(TokenKind.number, literal.toString()));
        literal.clear();
      }
    }

    void plain(EditorSequence inner) => _lowerSequence(inner, out, pretty: pretty);

    void group(EditorSequence inner) {
      out.add(_open);
      plain(inner);
      out.add(_close);
    }

    final nodes = sequence.children;
    for (var i = 0; i < nodes.length; i++) {
      final node = nodes[i];
      switch (node) {
        case AtomNode(:final text, :final kind):
          // A sign directly behind the exponent marker belongs to the literal.
          final afterExponent = literal.isNotEmpty && literal.toString().endsWith('E');
          if (kind == AtomKind.digit) {
            literal.write(text);
          } else if (afterExponent && kind == AtomKind.binaryOp && (text == '−' || text == '-' || text == '+')) {
            literal.write(text == '+' ? '+' : '-');
          } else {
            flush();
            out.add(Token(_kindOf(kind, text), text));
          }
        case FractionNode(:final numerator, :final denominator):
          flush();
          // A fraction that fills its slot is delimited by the slot itself.
          final enclose = !pretty || nodes.length > 1;
          if (enclose) out.add(_open);
          if (pretty && _isSimple(numerator)) {
            plain(numerator);
          } else {
            group(numerator);
          }
          out.add(const Token(TokenKind.operator, '/'));
          if (pretty && _isSimple(denominator)) {
            plain(denominator);
          } else {
            group(denominator);
          }
          if (enclose) out.add(_close);
        case PowerNode(:final exponent):
          flush();
          out.add(const Token(TokenKind.operator, '^'));
          if (pretty && _isSimple(exponent) && _isBoundary(i + 1 < nodes.length ? nodes[i + 1] : null)) {
            plain(exponent);
          } else {
            group(exponent);
          }
        case RootNode(:final degree, :final radicand):
          flush();
          if (degree.isEmpty) {
            out.add(const Token(TokenKind.function, '√'));
            group(radicand);
          } else {
            out
              ..add(const Token(TokenKind.function, 'root'))
              ..add(_open);
            plain(degree);
            out.add(_comma);
            plain(radicand);
            out.add(_close);
          }
        case FunctionCallEditorNode(:final functionName, :final argSlots):
          flush();
          out
            ..add(Token(TokenKind.function, functionName))
            ..add(_open);
          for (var i = 0; i < argSlots.length; i++) {
            if (i > 0) out.add(_comma);
            plain(argSlots[i]);
          }
          out.add(_close);
        case CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand, :final dummyVariable):
          flush();
          out
            ..add(Token(TokenKind.integral, '∫', variable: dummyVariable))
            ..add(_open);
          plain(lowerBound);
          out.add(_comma);
          plain(upperBound);
          out.add(_comma);
          plain(integrand);
          out.add(_close);
        case DerivativeEditorNode(:final body, :final evalPoint, :final dummyVariable):
          flush();
          out
            ..add(Token(TokenKind.derivative, 'd/d$dummyVariable', variable: dummyVariable))
            ..add(_open);
          plain(body);
          out
            ..add(_comma)
            ..add(Token(TokenKind.variable, dummyVariable))
            ..add(const Token(TokenKind.equals, '='));
          plain(evalPoint);
          out.add(_close);
      }
    }
    flush();
  }

  static TokenKind _kindOf(AtomKind kind, String text) => switch (kind) {
        AtomKind.digit => TokenKind.number,
        AtomKind.binaryOp => TokenKind.operator,
        AtomKind.unaryPostfix => TokenKind.postfix,
        AtomKind.unaryPrefix => TokenKind.prefix,
        AtomKind.constant => TokenKind.constant,
        AtomKind.variable => TokenKind.variable,
        AtomKind.paren => text == '(' ? TokenKind.leftParen : TokenKind.rightParen,
        AtomKind.separator => TokenKind.comma,
      };
}
