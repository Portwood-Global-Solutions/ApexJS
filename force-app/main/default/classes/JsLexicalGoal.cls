/** ES5 lexical context for regex versus division, including control headers and function/object bodies. */
public class JsLexicalGoal {
  public Boolean expressionAllowed = true;
  private Boolean statementStart = true, lastProperty = false;
  private JsToken previous;
  private String pendingFunction, awaitingBody;
  private List<String> parens = new List<String>(), braces = new List<String>();
  private static final Set<String> CONTROLS = new Set<String>{
    'if',
    'while',
    'for',
    'with',
    'switch',
    'catch'
  };
  private static final Set<String> PREFIX = new Set<String>{
    'return',
    'throw',
    'case',
    'delete',
    'void',
    'typeof',
    'new',
    'in',
    'instanceof',
    'yield',
    'await',
    'var',
    'let',
    'const'
  };
  public void accept(JsToken token) {
    String word = token.text;
    Boolean property = previous != null && previous.text == '.';
    if (previous != null && previous.text.equals('return') && token.row > previous.row)
      statementStart = true;
    if (token.kind == 'number' || token.kind == 'string' || token.kind == 'regex') {
      expressionAllowed = false;
      statementStart = false;
    } else if (word.equals('function') && !property) {
      pendingFunction = statementStart ? 'declaration' : 'expression';
      expressionAllowed = true;
      statementStart = false;
    } else if (word == '(') {
      String kind = pendingFunction != null
        ? 'function:' + pendingFunction
        : previous != null &&
            !lastProperty &&
            CONTROLS.contains(previous.text)
            ? 'control'
            : 'expression';
      pendingFunction = null;
      parens.add(kind);
      expressionAllowed = true;
      statementStart = false;
    } else if (word == ')') {
      String kind = parens.isEmpty() ? 'expression' : parens.remove(parens.size() - 1);
      if (kind.startsWith('function:'))
        awaitingBody = kind;
      expressionAllowed = kind == 'control';
      statementStart = expressionAllowed;
    } else if (word == '{') {
      String kind = awaitingBody != null ? awaitingBody : statementStart ? 'block' : 'object';
      awaitingBody = null;
      braces.add(kind);
      expressionAllowed = true;
      statementStart = kind != 'object';
    } else if (word == '}') {
      String kind = braces.isEmpty() ? 'block' : braces.remove(braces.size() - 1);
      expressionAllowed = kind == 'block' || kind == 'function:declaration';
      statementStart = expressionAllowed;
    } else if (word == ']') {
      expressionAllowed = false;
      statementStart = false;
    } else if (word == ';') {
      expressionAllowed = true;
      statementStart = true;
    } else if (word == ':') {
      pendingFunction = null;
      expressionAllowed = true;
      statementStart = braces.isEmpty() || braces[braces.size() - 1] != 'object';
    } else if (word == '++' || word == '--') {
      statementStart = false;
    } else if (token.kind == 'id') {
      if (
        !property &&
        (word.equals('else') ||
        word.equals('do') ||
        word.equals('try') ||
        word.equals('finally'))
      ) {
        expressionAllowed = true;
        statementStart = true;
      } else {
        expressionAllowed = !property && PREFIX.contains(word);
        statementStart = false;
      }
    } else {
      expressionAllowed = word != '.';
      statementStart = false;
    }
    previous = token;
    lastProperty = property;
  }
}
