/** Tokenizer for the deliberately bounded JavaScript subset in this lab. */
public class JsLexer {
  public Boolean allowRegex = false;
  private JsLexicalGoal lexicalGoal = new JsLexicalGoal();
  private String source;
  private Integer cursor = 0;
  private Integer row = 1;
  private Integer col = 1;
  private List<JsToken> tokens = new List<JsToken>();
  private JsBudget budget;
  private Integer nextGuardAt = 256;
  private Integer nextTokenHeapAt = JsBudget.PARSE_HEAP_SAMPLE_OBJECTS;
  private Boolean previousCR = false;
  private static final String DIGITS = '0123456789';
  private static final String LETTERS = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_$';
  private static final List<String> OPERATORS = new List<String>{
    '>>>=',
    '===',
    '!==',
    '>>>',
    '<<=',
    '>>=',
    '==',
    '!=',
    '<=',
    '>=',
    '&&',
    '||',
    '+=',
    '-=',
    '*=',
    '/=',
    '%=',
    '&=',
    '|=',
    '^=',
    '<<',
    '>>',
    '++',
    '--',
    '=>'
  };

  public JsLexer(String source, JsBudget budget) {
    budget.sourceCharacters = source == null ? 0 : source.length();
    if (source == null || source.length() > budget.maxSourceCharacters) {
      throw new JsException(
        'Source must be non-null and at most ' + budget.maxSourceCharacters + ' characters.'
      );
    }
    this.source = source;
    this.budget = budget;
    nextTokenHeapAt = budget.parseHeapSampleObjects;
  }

  public List<JsToken> scan() {
    Integer started = Limits.getCpuTime();
    try {
      while (cursor < source.length()) {
        String ch = peek(0);
        if (' \t\r\n'.contains(ch)) {
          take();
        } else if (ch == '/' && peek(1) == '/') {
          while (cursor < source.length() && peek(0) != '\n' && peek(0) != '\r') {
            take();
          }
        } else if (ch == '/' && peek(1) == '*') {
          Integer startRow = row;
          take();
          take();
          while (cursor < source.length() && !(peek(0) == '*' && peek(1) == '/')) {
            take();
          }
          if (cursor >= source.length()) {
            fail('Unterminated comment', startRow, 1);
          }
          take();
          take();
        } else {
          Integer startRow = row;
          Integer startCol = col;
          if (allowRegex && ch == '/' && lexicalGoal.expressionAllowed) {
            tokens.add(scanRegex(startRow, startCol));
          } else if (ch == '"' || ch == '\'') {
            tokens.add(new JsToken('string', scanString(), startRow, startCol));
          } else if (isDigit(ch) || (ch == '.' && isDigit(peek(1)))) {
            tokens.add(new JsToken('number', scanNumber(), startRow, startCol));
          } else if (isLetter(ch)) {
            Integer start = cursor;
            while (isLetter(peek(0)) || isDigit(peek(0))) {
              take();
            }
            tokens.add(new JsToken('id', source.substring(start, cursor), startRow, startCol));
          } else {
            String op;
            String prefix = source.substring(cursor, Math.min(source.length(), cursor + 4));
            for (String candidate : OPERATORS) {
              if (prefix.startsWith(candidate)) {
                op = candidate;
                break;
              }
            }
            if (op != null) {
              for (Integer i = 0; i < op.length(); i++) {
                take();
              }
            } else if ('{}[]().,;:?+-*/%<>=!~&|^'.contains(ch)) {
              op = take();
            } else {
              fail('Unsupported character ' + ch, row, col);
            }
            tokens.add(new JsToken('punct', op, startRow, startCol));
          }
          if (allowRegex)
            lexicalGoal.accept(tokens[tokens.size() - 1]);
          if (tokens.size() > budget.maxTokens) {
            fail('Token budget exceeded', row, col);
          }
          if (tokens.size() >= nextTokenHeapAt) {
            budget.guard();
            nextTokenHeapAt += budget.parseHeapSampleObjects;
          }
        }
      }
      tokens.add(new JsToken('eof', '', row, col));
      budget.guard();
      budget.lexerCompleted = true;
      return tokens;
    } finally {
      budget.scannedCharacters = cursor;
      budget.tokenCount = tokens.size();
      budget.lexerCpuMs = Limits.getCpuTime() - started;
    }
  }

  private JsToken scanRegex(Integer atRow, Integer atCol) {
    take();
    Integer start = cursor;
    Boolean escaped = false, inClass = false;
    while (cursor < source.length()) {
      String ch = peek(0);
      Integer code = ch.charAt(0);
      if (ch == '\n' || ch == '\r' || code == 8232 || code == 8233)
        fail('Unterminated regex literal', atRow, atCol);
      if (!escaped && ch == '/' && !inClass) {
        String pattern = source.substring(start, cursor);
        take();
        Integer flagStart = cursor;
        while (isLetter(peek(0)))
          take();
        String flags = source.substring(flagStart, cursor);
        Set<String> seen = new Set<String>();
        for (Integer i = 0; i < flags.length(); i++) {
          String flag = flags.substring(i, i + 1);
          if (!'dgimsuvy'.contains(flag) || seen.contains(flag))
            fail('Invalid regex flags', atRow, atCol);
          seen.add(flag);
        }
        if (seen.contains('u') && seen.contains('v'))
          fail('Invalid regex flags', atRow, atCol);
        JsToken result = new JsToken('regex', pattern, atRow, atCol);
        result.regexFlags = flags;
        return result;
      }
      if (!escaped) {
        if (ch == '[')
          inClass = true;
        else if (ch == ']')
          inClass = false;
      }
      escaped = !escaped && ch == '\\';
      take();
    }
    fail('Unterminated regex literal', atRow, atCol);
    return null;
  }
  public void releaseTokens() {
    tokens.clear();
  }
  private String scanNumber() {
    Integer start = cursor;
    if (
      peek(0) == '0' &&
      (peek(1) == 'x' ||
      peek(1) == 'X' ||
      peek(1) == 'b' ||
      peek(1) == 'B' ||
      peek(1) == 'o' ||
      peek(1) == 'O')
    ) {
      take();
      String marker = take().toLowerCase();
      Integer radix = marker == 'x' ? 16 : marker == 'b' ? 2 : 8;
      Integer digits = 0;
      Double value = 0;
      while (
        peek(0) != '' &&
        '0123456789abcdef'.indexOf(peek(0).toLowerCase()) >= 0 &&
        '0123456789abcdef'.indexOf(peek(0).toLowerCase()) < radix
      ) {
        value = value * radix + '0123456789abcdef'.indexOf(take().toLowerCase());
        digits++;
        if (cursor - start > 128) {
          fail('Unsupported numeric literal', row, col);
        }
      }
      if (digits == 0 || isLetter(peek(0)) || isDigit(peek(0))) {
        fail('Invalid base-prefixed numeric literal', row, col);
      }
      return String.valueOf(value);
    }
    while (isDigit(peek(0))) {
      take();
    }
    if (peek(0) == '.') {
      take();
      while (isDigit(peek(0))) {
        take();
      }
    }
    if (peek(0) == 'e' || peek(0) == 'E') {
      take();
      if (peek(0) == '+' || peek(0) == '-') {
        take();
      }
      if (!isDigit(peek(0))) {
        fail('Invalid numeric exponent', row, col);
      }
      while (isDigit(peek(0))) {
        take();
      }
    }
    String lexeme = source.substring(start, cursor);
    if (lexeme.length() > 128 || isLetter(peek(0))) {
      fail('Unsupported numeric literal', row, col);
    }
    if (lexeme.length() > 1 && lexeme.startsWith('0') && isDigit(lexeme.substring(1, 2))) {
      fail('Legacy octal literals are not supported', row, col);
    }
    return lexeme;
  }

  private void movePlain(Integer endAt) {
    col += endAt - cursor;
    cursor = endAt;
    if (cursor >= nextGuardAt) {
      budget.poll();
      nextGuardAt = cursor + 256;
    }
  }
  private String scanString() {
    String quote = take();
    List<String> parts = new List<String>();
    while (cursor < source.length()) {
      Integer close = source.indexOf(quote, cursor), escape = source.indexOf('\\', cursor);
      if (close < 0)
        fail('Unterminated string', row, col);
      Integer endAt = escape >= 0 && escape < close ? escape : close;
      String plain = source.substring(cursor, endAt);
      if (plain.contains('\n') || plain.contains('\r'))
        fail('Unterminated string', row, col);
      parts.add(plain);
      movePlain(endAt);
      if (plain.length() >= 4096)
        budget.guard();
      if (endAt == close) {
        take();
        return String.join(parts, '');
      }
      take();
      if (cursor >= source.length())
        fail('Unterminated escape', row, col);
      String ch = take();
      if (ch.equals('n'))
        ch = '\n';
      else if (ch.equals('r'))
        ch = '\r';
      else if (ch.equals('t'))
        ch = '\t';
      else if (ch.equals('b'))
        ch = String.fromCharArray(new List<Integer>{ 8 });
      else if (ch.equals('f'))
        ch = String.fromCharArray(new List<Integer>{ 12 });
      else if (allowRegex && ch.equals('v'))
        ch = String.fromCharArray(new List<Integer>{ 11 });
      else if (allowRegex && ch == '0') {
        if (isDigit(peek(0)))
          fail('Legacy octal escape is not supported', row, col);
        ch = String.fromCharArray(new List<Integer>{ 0 });
      } else if (allowRegex && (ch == '\n' || ch == '\r')) {
        if (ch == '\r' && peek(0) == '\n')
          take();
        continue;
      } else if (ch.equals('u') || ch.equals('x')) {
        Integer digits = ch.equals('u') ? 4 : 2, code = 0;
        for (Integer i = 0; i < digits; i++) {
          String digit = take().toLowerCase();
          Integer value = '0123456789abcdef'.indexOf(digit);
          if (digit == '' || value < 0)
            fail('Invalid Unicode escape', row, col);
          code = code * 16 + value;
        }
        ch = String.fromCharArray(new List<Integer>{ code });
      } else if (isDigit(ch) || !allowRegex && ch != '\\' && ch != '"' && ch != '\'')
        fail('Unsupported string escape', row, col);
      parts.add(ch);
    }
    fail('Unterminated string', row, col);
    return null;
  }

  private String peek(Integer ahead) {
    return cursor + ahead < source.length()
      ? source.substring(cursor + ahead, cursor + ahead + 1)
      : '';
  }
  private String take() {
    String ch = peek(0);
    if (ch == '') {
      return ch;
    }
    cursor++;
    if (cursor >= nextGuardAt) {
      budget.poll();
      nextGuardAt += 256;
    }
    if (ch == '\r') {
      row++;
      col = 1;
    } else if (ch == '\n') {
      if (!previousCR) {
        row++;
      }
      col = 1;
    } else {
      col++;
    }
    previousCR = ch == '\r';
    return ch;
  }
  private Boolean isDigit(String ch) {
    return ch != '' && DIGITS.contains(ch);
  }
  private Boolean isLetter(String ch) {
    return ch != '' && LETTERS.contains(ch);
  }
  private void fail(String message, Integer atRow, Integer atCol) {
    throw new JsException('SyntaxError at ' + atRow + ':' + atCol + ': ' + message);
  }
}
