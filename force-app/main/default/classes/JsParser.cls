/** Recursive-descent parser. Unsupported JavaScript is rejected rather than silently rewritten. */
public class JsParser {
  public Boolean bytecodeSyntax = false;
  public static Integer trustedMaxDepth;
  private List<JsToken> tokens;
  private Integer cursor = 0;
  private Integer depth = 0;
  private Integer nodeCount = 0;
  private Integer loopDepth = 0;
  private Boolean allowIn = true;
  private class ParseControl {
    public String label;
    public Boolean isLoop = false;
    public Boolean breakable = true;
  }
  private List<ParseControl> controls = new List<ParseControl>();
  private void pushLoop() {
    ParseControl c = new ParseControl();
    c.isLoop = true;
    controls.add(c);
    loopDepth++;
  }
  private void popLoop() {
    controls.remove(controls.size() - 1);
    loopDepth--;
  }
  private Boolean labelLoop(Integer at) {
    while (at + 1 < tokens.size() && tokens[at].kind == 'id' && tokens[at + 1].text == ':')
      at += 2;
    return new Set<String>{ 'for', 'while', 'do' }.contains(tokens[at].text);
  }
  private void validateJump(String kind, String label) {
    for (Integer i = controls.size() - 1; i >= 0; i--) {
      ParseControl c = controls[i];
      if (label != null) {
        if (c.label != null && c.label.equals(label)) {
          if (kind == 'continue' && !c.isLoop)
            fail('Continue label must identify a loop');
          return;
        }
      } else if (kind == 'continue' ? c.isLoop : c.breakable)
        return;
    }
    fail(label == null ? 'Missing enclosing control statement' : 'Unknown label ' + label);
  }
  private JsBudget budget;
  private JsNode activeFunction;
  private static final Set<String> RESERVED = new Set<String>{
    'const',
    'let',
    'var',
    'return',
    'if',
    'else',
    'for',
    'of',
    'while',
    'break',
    'continue',
    'function',
    'true',
    'false',
    'null',
    'undefined',
    'typeof',
    'new',
    'this',
    'class',
    'delete',
    'try',
    'catch',
    'throw',
    'switch',
    'do',
    'in',
    'instanceof',
    'void',
    'yield',
    'await',
    'async',
    'import',
    'export',
    'super',
    'with',
    'debugger',
    'default',
    'case',
    'finally',
    'extends'
  };

  public JsParser(List<JsToken> tokens, JsBudget budget) {
    this.tokens = tokens;
    this.budget = budget;
  }
  public JsNode parse() {
    Integer started = Limits.getCpuTime();
    try {
      JsNode program = make('program', peek());
      activeFunction = program;
      while (!atEnd()) {
        program.children.add(statement());
      }
      budget.parserCompleted = true;
      return program;
    } finally {
      budget.nodeCount = nodeCount;
      budget.parserCpuMs = Limits.getCpuTime() - started;
    }
  }

  private JsNode statement() {
    enter();
    JsToken start = peek();
    JsNode result;
    if (
      bytecodeSyntax &&
      peek().kind == 'id' &&
      cursor + 1 < tokens.size() &&
      tokens[cursor + 1].text == ':'
    ) {
      String name = identifier().text;
      expect(':');
      for (ParseControl active : controls)
        if (active.label != null && active.label.equals(name))
          fail('Duplicate active label');
      ParseControl labeled = new ParseControl();
      labeled.label = name;
      labeled.isLoop = labelLoop(cursor);
      labeled.breakable = false;
      controls.add(labeled);
      result = make('label', start);
      result.text = name;
      result.children.add(statement());
      controls.remove(controls.size() - 1);
    } else if (match(';')) {
      result = make('empty', start);
    } else if (check('{')) {
      result = block();
    } else if (match('const') || match('let') || match('var')) {
      result = declaration(previous());
      semicolon();
    } else if (match('function')) {
      JsToken name = identifier();
      result = functionBody(start);
      result.kind = 'functionDecl';
      result.text = name.text;
    } else if (match('return')) {
      result = make('return', start);
      if (!check(';') && !check('}') && !atEnd() && peek().row == start.row) {
        result.children.add(expression());
      }
      semicolon();
    } else if (match('try')) {
      result = make('try', start);
      result.children.add(block());
      Boolean caught = match('catch');
      String binding = '';
      if (caught) {
        if (match('(')) {
          binding = identifier().text;
          expect(')');
        }
        result.children.add(block());
      } else
        result.children.add(make('empty', peek()));
      result.names.add(binding);
      if (match('finally'))
        result.children.add(block());
      else {
        if (!caught)
          fail('try requires catch or finally');
        result.children.add(make('empty', peek()));
      }
    } else if (match('throw')) {
      if (peek().row > start.row) {
        fail('A throw expression must start on the same line');
      }
      result = make('throw', start);
      result.children.add(expression());
      semicolon();
    } else if (match('if')) {
      result = make('if', start);
      expect('(');
      result.children.add(expression());
      expect(')');
      result.children.add(subStatement());
      if (match('else')) {
        result.children.add(subStatement());
      }
    } else if (bytecodeSyntax && match('switch')) {
      result = make('switch', start);
      expect('(');
      result.children.add(expression());
      expect(')');
      expect('{');
      ParseControl control = new ParseControl();
      controls.add(control);
      Boolean defaultSeen = false;
      while (!check('}') && !atEnd()) {
        JsNode clause = make('case', peek());
        if (match('case'))
          clause.children.add(expression());
        else {
          expect('default');
          if (defaultSeen)
            fail('Duplicate default clause');
          defaultSeen = true;
          clause.children.add(make('empty', previous()));
        }
        expect(':');
        JsNode body = make('block', previous());
        while (!check('case') && !check('default') && !check('}') && !atEnd())
          body.children.add(statement());
        clause.children.add(body);
        result.children.add(clause);
      }
      expect('}');
      controls.remove(controls.size() - 1);
    } else if (match('while')) {
      result = make('while', start);
      expect('(');
      result.children.add(expression());
      expect(')');
      pushLoop();
      result.children.add(subStatement());
      popLoop();
    } else if (match('do')) {
      result = make('doWhile', start);
      pushLoop();
      result.children.add(subStatement());
      popLoop();
      expect('while');
      expect('(');
      result.children.add(expression());
      expect(')');
      semicolon();
    } else if (match('for')) {
      result = make('for', start);
      expect('(');
      JsNode initializer = make('empty', peek());
      Boolean enclosingIn = allowIn;
      allowIn = !bytecodeSyntax;
      if (match('const') || match('let') || match('var')) {
        initializer = declaration(previous());
        if (match('of') || bytecodeSyntax && match('in')) {
          String mode = previous().text;
          if (initializer.kind != 'declare' || !initializer.children.isEmpty())
            fail('Invalid iteration declaration');
          result.kind = mode == 'in' ? 'forIn' : 'forOf';
          result.text = initializer.text;
          result.names.add(initializer.names[0]);
          allowIn = enclosingIn;
          result.children.add(expression());
          expect(')');
        }
      } else if (!check(';')) {
        initializer = make('expression', peek());
        initializer.children.add(expression());
        if (bytecodeSyntax && (match('in') || match('of'))) {
          String mode = previous().text;
          JsNode target = initializer.children[0];
          if (target.kind != 'identifier')
            fail('Iteration assignment requires an identifier');
          result.kind = mode == 'in' ? 'forIn' : 'forOf';
          result.text = 'assign';
          result.names.add(target.text);
          allowIn = enclosingIn;
          result.children.add(expression());
          expect(')');
        }
      }
      allowIn = enclosingIn;
      if (result.kind == 'for') {
        result.children.add(initializer);
        expect(';');
        result.children.add(check(';') ? make('empty', peek()) : expression());
        expect(';');
        result.children.add(check(')') ? make('empty', peek()) : expression());
        expect(')');
      }
      pushLoop();
      result.children.add(subStatement());
      popLoop();
    } else if (match('break') || match('continue')) {
      String kind = previous().text;
      result = make(kind, start);
      if (bytecodeSyntax) {
        String label;
        if (peek().row == start.row && peek().kind == 'id' && !RESERVED.contains(peek().text))
          label = identifier().text;
        result.text = label;
        validateJump(kind, label);
      } else if (loopDepth == 0)
        fail('break/continue requires an enclosing loop in the same function');
      semicolon();
    } else {
      result = make('expression', start);
      result.children.add(expression());
      semicolon();
    }
    depth--;
    return result;
  }

  private JsNode declaration(JsToken start) {
    JsNode declarationsNode = make('declarations', start);
    do {
      JsNode result = make('declare', start);
      result.text = start.text;
      result.names.add(identifier().text);
      if (match('=')) {
        result.children.add(assignment());
      } else if (start.text.equals('const') && !check('of') && !(bytecodeSyntax && check('in'))) {
        fail('A const binding requires an initializer');
      }
      declarationsNode.children.add(result);
    } while (match(','));
    return declarationsNode.children.size() == 1 ? declarationsNode.children[0] : declarationsNode;
  }
  private JsNode subStatement() {
    JsNode result = statement();
    if (
      (result.kind == 'declare' && !result.text.equals('var')) ||
      result.kind == 'declarations' ||
      result.kind == 'functionDecl'
    ) {
      fail('Declarations in statement bodies require braces');
    }
    return result;
  }

  private JsNode block() {
    JsToken start = expect('{');
    JsNode result = make('block', start);
    while (!check('}') && !atEnd()) {
      result.children.add(statement());
    }
    expect('}');
    return result;
  }

  private JsNode functionBody(JsToken start) {
    JsNode result = make('function', start);
    expect('(');
    if (!check(')')) {
      do {
        String name = identifier().text;
        if (result.names.contains(name)) {
          fail('Duplicate function parameter');
        }
        result.names.add(name);
      } while (match(','));
    }
    expect(')');
    Integer enclosingLoopDepth = loopDepth;
    List<ParseControl> enclosingControls = controls;
    Boolean enclosingIn = allowIn;
    loopDepth = 0;
    controls = new List<ParseControl>();
    allowIn = true;
    JsNode parentFunction = activeFunction;
    activeFunction = result;
    result.children.add(block());
    activeFunction = parentFunction;
    loopDepth = enclosingLoopDepth;
    controls = enclosingControls;
    allowIn = enclosingIn;
    return result;
  }

  private JsNode expression() {
    enter();
    JsNode result = assignment();
    if (match(',')) {
      JsNode sequence = make('sequence', previous());
      sequence.children.add(result);
      do {
        sequence.children.add(assignment());
      } while (match(','));
      result = sequence;
    }
    depth--;
    return result;
  }
  private JsNode assignment() {
    enter();
    try {
      JsNode lhs = conditional();
      if (
        match('=') ||
        match('+=') ||
        match('-=') ||
        match('*=') ||
        match('/=') ||
        match('%=') ||
        match('&=') ||
        match('|=') ||
        match('^=') ||
        match('<<=') ||
        match('>>=') ||
        match('>>>=')
      ) {
        JsNode result = make('assign', previous());
        result.text = previous().text;
        if (lhs.kind != 'identifier' && lhs.kind != 'member') {
          fail('Invalid assignment target');
        }
        result.children.add(lhs);
        result.children.add(assignment());
        return result;
      }
      return lhs;
    } finally {
      depth--;
    }
  }
  private JsNode conditional() {
    JsNode result = logicalOr();
    if (match('?')) {
      JsNode choice = make('conditional', previous());
      choice.children.add(result);
      choice.children.add(assignment());
      expect(':');
      choice.children.add(assignment());
      return choice;
    }
    return result;
  }
  private JsNode logicalOr() {
    JsNode result = logicalAnd();
    while (match('||')) {
      result = binary(previous(), result, logicalAnd());
    }
    return result;
  }
  private JsNode logicalAnd() {
    JsNode result = bitwiseOr();
    while (match('&&')) {
      result = binary(previous(), result, bitwiseOr());
    }
    return result;
  }
  private JsNode bitwiseOr() {
    JsNode result = bitwiseXor();
    while (match('|')) {
      result = binary(previous(), result, bitwiseXor());
    }
    return result;
  }
  private JsNode bitwiseXor() {
    JsNode result = bitwiseAnd();
    while (match('^')) {
      result = binary(previous(), result, bitwiseAnd());
    }
    return result;
  }
  private JsNode bitwiseAnd() {
    JsNode result = equality();
    while (match('&')) {
      result = binary(previous(), result, equality());
    }
    return result;
  }
  private JsNode equality() {
    JsNode result = comparison();
    while (match('===') || match('!==') || bytecodeSyntax && (match('==') || match('!='))) {
      result = binary(previous(), result, comparison());
    }
    if (check('==') || check('!=')) {
      fail('Use === or !==; coercive equality is outside this subset');
    }
    return result;
  }
  private JsNode comparison() {
    JsNode result = shift();
    while (
      match('<') ||
      match('>') ||
      match('<=') ||
      match('>=') ||
      match('instanceof') ||
      allowIn && match('in')
    ) {
      result = binary(previous(), result, shift());
    }
    return result;
  }
  private JsNode shift() {
    JsNode result = term();
    while (match('<<') || match('>>') || match('>>>')) {
      result = binary(previous(), result, term());
    }
    return result;
  }
  private JsNode term() {
    JsNode result = factor();
    while (match('+') || match('-')) {
      result = binary(previous(), result, factor());
    }
    return result;
  }
  private JsNode factor() {
    JsNode result = unary();
    while (match('*') || match('/') || match('%')) {
      result = binary(previous(), result, unary());
    }
    return result;
  }
  private JsNode unary() {
    enter();
    JsNode result;
    if (match('++') || match('--')) {
      result = make('update', previous());
      result.text = previous().text + 'pre';
      result.children.add(unary());
      validateTarget(result.children[0]);
    } else if (
      match('!') ||
      match('~') ||
      match('-') ||
      match('+') ||
      match('typeof') ||
      match('void') ||
      bytecodeSyntax && match('delete')
    ) {
      result = make('unary', previous());
      result.text = previous().text;
      result.children.add(unary());
    } else {
      result = postfix();
    }
    depth--;
    return result;
  }
  private JsNode postfix() {
    JsNode result = primary();
    while (true) {
      if (match('.')) {
        JsNode member = make('member', previous());
        member.children.add(result);
        JsToken property = peek();
        if (property.kind != 'id') {
          fail('Expected property name');
        }
        cursor++;
        JsNode key = make('string', property);
        key.text = property.text;
        member.children.add(key);
        result = member;
      } else if (match('[')) {
        JsNode member = make('member', previous());
        member.children.add(result);
        member.children.add(expression());
        expect(']');
        result = member;
      } else if (match('(')) {
        JsNode call = make('call', previous());
        call.children.add(result);
        if (!check(')')) {
          do {
            call.children.add(assignment());
          } while (match(','));
        }
        expect(')');
        result = call;
      } else {
        break;
      }
    }
    if ((check('++') || check('--')) && peek().row == previous().row) {
      JsToken op = tokens[cursor++];
      JsNode updateNode = make('update', op);
      updateNode.text = op.text + 'post';
      validateTarget(result);
      updateNode.children.add(result);
      result = updateNode;
    }
    return result;
  }
  private JsNode primary() {
    JsToken token = peek();
    if (match('new')) {
      JsNode callee = primary();
      while (check('.') || check('[')) {
        JsToken access = tokens[cursor++];
        JsNode member = make('member', access);
        member.children.add(callee);
        if (access.text == '.') {
          JsToken key = peek();
          if (key.kind != 'id') {
            fail('Expected constructor property');
          }
          cursor++;
          JsNode name = make('string', key);
          name.text = key.text;
          member.children.add(name);
        } else {
          member.children.add(expression());
          expect(']');
        }
        callee = member;
      }
      JsNode construct = make('construct', token);
      construct.children.add(callee);
      if (match('(')) {
        if (!check(')')) {
          do {
            construct.children.add(assignment());
          } while (match(','));
        }
        expect(')');
      }
      return construct;
    }
    if (match('(')) {
      Boolean priorIn = allowIn;
      allowIn = true;
      JsNode result = expression();
      expect(')');
      allowIn = priorIn;
      return result;
    }
    if (match('function')) {
      String name;
      if (peek().kind == 'id' && !check('(')) {
        name = identifier().text;
      }
      JsNode fn = functionBody(token);
      fn.text = name;
      return fn;
    }
    if (match('this')) {
      JsNode self = make('identifier', token);
      self.text = 'this';
      return self;
    }
    if (match('[')) {
      JsNode result = make('array', token);
      if (bytecodeSyntax) {
        while (!check(']')) {
          if (match(',')) {
            result.children.add(make('hole', previous()));
            continue;
          }
          result.children.add(assignment());
          if (!match(','))
            break;
        }
      } else {
        if (!check(']')) {
          do {
            if (check(']')) {
              break;
            }
            result.children.add(assignment());
          } while (match(','));
        }
      }
      expect(']');
      return result;
    }
    if (match('{')) {
      JsNode result = make('object', token);
      if (!check('}')) {
        do {
          if (check('}')) {
            break;
          }
          JsToken key = peek();
          if (key.kind != 'id' && key.kind != 'string' && key.kind != 'number') {
            fail('Expected object key');
          }
          cursor++;
          result.names.add(
            key.kind == 'number' ? JsValue.num(Double.valueOf(key.text)).asString() : key.text
          );
          if (match(':')) {
            result.children.add(assignment());
          } else {
            if (key.kind != 'id' || RESERVED.contains(key.text)) {
              fail('Expected colon');
            }
            if (key.text == 'arguments' && activeFunction != null)
              activeFunction.needsArguments = true;
            JsNode shorthand = make('identifier', key);
            shorthand.text = key.text;
            result.children.add(shorthand);
          }
        } while (match(','));
      }
      expect('}');
      return result;
    }
    if (bytecodeSyntax && token.kind == 'regex') {
      cursor++;
      JsNode call = make('call', token), callee = make('identifier', token);
      callee.text = 'RegExp';
      call.children.add(callee);
      JsNode pattern = make('string', token);
      pattern.text = token.text;
      call.children.add(pattern);
      JsNode flags = make('string', token);
      flags.text = token.regexFlags;
      call.children.add(flags);
      return call;
    }
    if (token.kind == 'number' || token.kind == 'string') {
      cursor++;
      JsNode result = make(token.kind, token);
      result.text = token.text;
      return result;
    }
    if (match('true') || match('false') || match('null') || match('undefined')) {
      JsNode result = make('literal', token);
      result.text = token.text;
      return result;
    }
    if (token.kind == 'id' && !RESERVED.contains(token.text)) {
      if (token.text == 'arguments' && activeFunction != null) {
        activeFunction.needsArguments = true;
      }
      cursor++;
      JsNode result = make('identifier', token);
      result.text = token.text;
      return result;
    }
    fail('Unsupported or unexpected token ' + token.text);
    return null;
  }

  private JsNode binary(JsToken token, JsNode lhs, JsNode rhs) {
    JsNode result = make('binary', token);
    result.text = token.text;
    result.children.add(lhs);
    result.children.add(rhs);
    return result;
  }
  private void validateTarget(JsNode node) {
    if (node.kind != 'identifier' && node.kind != 'member') {
      fail('Invalid update target');
    }
  }
  private void semicolon() {
    if (match(';') || check('}') || atEnd() || peek().row > previous().row) {
      return;
    }
    fail('Expected semicolon (or unsupported syntax)');
  }
  private JsToken identifier() {
    JsToken token = peek();
    if (token.kind != 'id' || RESERVED.contains(token.text)) {
      fail('Expected identifier');
    }
    if (token.text == 'arguments' || token.text == 'eval')
      fail('Strict function bodies cannot bind arguments or eval');
    cursor++;
    return token;
  }
  private JsToken expect(String text) {
    if (!check(text)) {
      fail('Expected ' + text + ', found ' + peek().text);
    }
    return tokens[cursor++];
  }
  private Boolean match(String text) {
    if (!check(text)) {
      return false;
    }
    cursor++;
    return true;
  }
  private Boolean check(String text) {
    return peek().kind != 'string' &&
      peek().kind != 'number' &&
      peek().kind != 'regex' &&
      peek().text.equals(text);
  }
  private Boolean atEnd() {
    return peek().kind == 'eof';
  }
  private JsToken peek() {
    return tokens[cursor];
  }
  private JsToken previous() {
    return tokens[cursor - 1];
  }
  private JsNode make(String kind, JsToken token) {
    nodeCount++;
    if (Math.mod(nodeCount, 64) == 0) {
      if (Math.mod(nodeCount, budget.parseHeapSampleObjects) == 0) {
        budget.guard();
      } else {
        budget.poll();
      }
    }
    if (nodeCount > budget.maxAstNodes) {
      fail('AST node budget exceeded');
    }
    return new JsNode(kind, token);
  }
  private void enter() {
    depth++;
    Integer maximum = trustedMaxDepth == null ? 60 : trustedMaxDepth;
    if (maximum < 1 || maximum > 240)
      throw new JsException('BudgetError: Invalid parser depth profile.');
    if (depth > maximum)
      fail('Parser nesting budget exceeded');
  }
  private void fail(String message) {
    throw new JsException('SyntaxError at ' + peek().row + ':' + peek().col + ': ' + message);
  }
}
