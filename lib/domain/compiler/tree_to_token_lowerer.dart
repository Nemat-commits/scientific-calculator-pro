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

  /// Concatenated lexemes of [tokens].
  static String textOf(List<Token> tokens) => tokens.where((t) => !t.implicit).map((t) => t.text).join();

  static void _lowerSequence(EditorSequence sequence, List<Token> out) {
    final literal = StringBuffer();

    void flush() {
      if (literal.isNotEmpty) {
        out.add(Token(TokenKind.number, literal.toString()));
        literal.clear();
      }
    }

    void group(EditorSequence inner) {
      out.add(_open);
      _lowerSequence(inner, out);
      out.add(_close);
    }

    for (final node in sequence.children) {
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
          out.add(_open);
          group(numerator);
          out.add(const Token(TokenKind.operator, '/'));
          group(denominator);
          out.add(_close);
        case PowerNode(:final exponent):
          flush();
          out.add(const Token(TokenKind.operator, '^'));
          group(exponent);
        case RootNode(:final degree, :final radicand):
          flush();
          if (degree.isEmpty) {
            out.add(const Token(TokenKind.function, '√'));
            group(radicand);
          } else {
            out
              ..add(const Token(TokenKind.function, 'root'))
              ..add(_open);
            _lowerSequence(degree, out);
            out.add(_comma);
            _lowerSequence(radicand, out);
            out.add(_close);
          }
        case FunctionCallEditorNode(:final functionName, :final argSlots):
          flush();
          out
            ..add(Token(TokenKind.function, functionName))
            ..add(_open);
          for (var i = 0; i < argSlots.length; i++) {
            if (i > 0) out.add(_comma);
            _lowerSequence(argSlots[i], out);
          }
          out.add(_close);
        case CalculusIntegralNode(:final lowerBound, :final upperBound, :final integrand, :final dummyVariable):
          flush();
          out
            ..add(Token(TokenKind.integral, '∫', variable: dummyVariable))
            ..add(_open);
          _lowerSequence(lowerBound, out);
          out.add(_comma);
          _lowerSequence(upperBound, out);
          out.add(_comma);
          _lowerSequence(integrand, out);
          out.add(_close);
        case DerivativeEditorNode(:final body, :final evalPoint, :final dummyVariable):
          flush();
          out
            ..add(Token(TokenKind.derivative, 'd/d$dummyVariable', variable: dummyVariable))
            ..add(_open);
          _lowerSequence(body, out);
          out
            ..add(_comma)
            ..add(Token(TokenKind.variable, dummyVariable))
            ..add(const Token(TokenKind.equals, '='));
          _lowerSequence(evalPoint, out);
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
