/** In-org compiler for the current JsParser subset. Emits the same validated VM format as the offline compiler. */
public with sharing class JsBytecodeCompiler {
  public static final String VERSION = 'apex-3';
  public static Integer trustedMaxInstructions;
  public static Map<String, Integer> lastStatistics;
  private class Lexical {
    public Lexical parent;
    public Integer index;
    public Map<String, Integer> slots = new Map<String, Integer>();
    public JsBytecode.ScopeSpec layout;
  }
  private class Control {
    public Lexical scope;
    public Integer handlers;
    public Boolean isLoop = true, breakable = true;
    public List<String> labels = new List<String>();
    public List<Integer> exits = new List<Integer>(), continues = new List<Integer>();
  }
  private class Frame {
    public JsBytecode.FunctionSpec functionSpec;
    public Lexical root, current;
    public Integer handlers = 0;
    public List<Control> loops = new List<Control>();
  }
  private class Address {
    public Integer depth, slot;
  }
  private JsBytecode.Program program;
  private JsBudget budget;
  private Map<String, Integer> textIndices = new Map<String, Integer>(),
    constantIndices = new Map<String, Integer>();
  private Integer instructions = 0;
  public static JsBytecode.Program compile(String source, JsBudget budget) {
    JsLexer lexer = new JsLexer(source, budget);
    lexer.allowRegex = true;
    JsParser parser = new JsParser(lexer.scan(), budget);
    parser.bytecodeSyntax = true;
    JsNode tree = parser.parse();
    lexer.releaseTokens();
    JsBytecodeCompiler compiler = new JsBytecodeCompiler();
    compiler.budget = budget;
    lastStatistics = new Map<String, Integer>{ 'functions' => 0, 'instructions' => 0 };
    compiler.program = new JsBytecode.Program();
    compiler.program.version = 1;
    compiler.program.sourceSha256 = EncodingUtil.convertToHex(
      Crypto.generateDigest('SHA-256', Blob.valueOf(source))
    );
    compiler.program.texts = new List<String>();
    compiler.program.constants = new List<JsBytecode.ConstantSpec>();
    compiler.program.scopes = new List<JsBytecode.ScopeSpec>();
    compiler.program.functions = new List<JsBytecode.FunctionSpec>();
    compiler.functionCode(tree, null, true);
    budget.guard();
    return compiler.program;
  }
  private void fail(JsNode node, String message) {
    throw new JsException('BytecodeCompileError at ' + node.row + ':' + node.col + ': ' + message);
  }
  private Integer text(String value) {
    if (!textIndices.containsKey(value)) {
      if (program.texts.size() >= 8192)
        throw new JsException('BytecodeCompileError: Text table exceeded.');
      textIndices.put(value, program.texts.size());
      program.texts.add(value);
    }
    return textIndices.get(value);
  }
  private Integer constant(String kind, String value) {
    String key = kind + ':' + value;
    if (!constantIndices.containsKey(key)) {
      if (program.constants.size() >= 8192)
        throw new JsException('BytecodeCompileError: Constant table exceeded.');
      JsBytecode.ConstantSpec spec = new JsBytecode.ConstantSpec();
      spec.kind = kind;
      spec.value = value;
      constantIndices.put(key, program.constants.size());
      program.constants.add(spec);
    }
    return constantIndices.get(key);
  }
  private Lexical scope(Lexical parent) {
    if (program.scopes.size() >= 4096)
      throw new JsException('BytecodeCompileError: Scope table exceeded.');
    Lexical result = new Lexical();
    result.parent = parent;
    result.index = program.scopes.size();
    result.layout = new JsBytecode.ScopeSpec();
    result.layout.names = new List<String>();
    result.layout.kinds = new List<String>();
    result.layout.allocationUnits = 0;
    program.scopes.add(result.layout);
    return result;
  }
  private Integer bind(Lexical lexical, String name, String kind, JsNode node) {
    if (name == 'eval' || name == 'arguments' && kind == 'param')
      fail(node, 'Restricted binding ' + name);
    if (lexical.slots.containsKey(name)) {
      Integer slot = lexical.slots.get(name);
      if (
        kind == 'var' &&
        (lexical.layout.kinds[slot] == 'var' ||
        lexical.layout.kinds[slot] == 'param')
      )
        return slot;
      fail(node, 'Duplicate binding ' + name);
    }
    if (lexical.layout.names.size() >= 4096)
      fail(node, 'Scope binding count exceeded');
    Integer slot = lexical.layout.names.size();
    lexical.slots.put(name, slot);
    lexical.layout.names.add(name);
    lexical.layout.kinds.add(kind);
    return slot;
  }
  private Integer emit(Frame frame, Integer op, Integer a, Integer b, Integer c) {
    budget.tick();
    if (++instructions > (trustedMaxInstructions == null ? 50000 : trustedMaxInstructions))
      throw new JsException('BytecodeCompileError: Instruction table exceeded.');
    Integer at = frame.functionSpec.code.size() / 4;
    frame.functionSpec.code.addAll(new List<Integer>{ op, a, b, c });
    return at;
  }
  private Integer emit(Frame frame, Integer op) {
    return emit(frame, op, 0, 0, 0);
  }
  private Integer one(Frame frame, Integer op, Integer a) {
    return emit(frame, op, a, 0, 0);
  }
  private Integer pc(Frame frame) {
    return frame.functionSpec.code.size() / 4;
  }
  private void patch(Frame frame, Integer at, Integer target) {
    frame.functionSpec.code[at * 4 + 1] = target;
  }
  private Address resolve(Frame frame, String name) {
    Lexical lexical = frame.current;
    Integer depth = 0;
    while (lexical != null) {
      if (lexical.slots.containsKey(name)) {
        if (lexical === frame.root && name == 'arguments')
          frame.functionSpec.needsArguments = true;
        Address result = new Address();
        result.depth = depth;
        result.slot = lexical.slots.get(name);
        return result;
      }
      if (++depth > 128)
        throw new JsException('BytecodeCompileError: Lexical depth exceeded.');
      lexical = lexical.parent;
    }
    return null;
  }
  private void load(Frame frame, String name) {
    Address ref = resolve(frame, name);
    if (ref != null)
      emit(frame, 1, ref.depth, ref.slot, 0);
    else if (name == 'undefined')
      one(frame, 0, constant('undefined', ''));
    else
      one(frame, 4, text(name));
  }
  private void store(Frame frame, String name, JsNode node) {
    Address ref = resolve(frame, name);
    if (ref == null)
      fail(node, 'Assignment to unresolved binding ' + name);
    emit(frame, 2, ref.depth, ref.slot, 0);
  }
  private void collectVars(JsNode node, Lexical root, Boolean top) {
    budget.tick();
    if (node.kind == 'functionDecl') {
      if (top)
        bind(root, node.text, 'var', node);
      return;
    }
    if (node.kind == 'function')
      return;
    if (node.kind == 'declare' && node.text == 'var')
      bind(root, node.names[0], 'var', node);
    if ((node.kind == 'forOf' || node.kind == 'forIn') && node.text == 'var')
      bind(root, node.names[0], 'var', node);
    for (JsNode child : node.children)
      collectVars(child, root, false);
  }
  private void reserve(List<JsNode> body, Lexical lexical, Boolean root) {
    for (JsNode node : body) {
      if (node.kind == 'declarations')
        reserve(node.children, lexical, root);
      else if (node.kind == 'declare' && node.text != 'var')
        bind(lexical, node.names[0], node.text, node);
      else if (node.kind == 'functionDecl' && !root)
        bind(lexical, node.text, 'let', node);
    }
  }
  private void hoist(Frame frame, List<JsNode> body, Boolean root) {
    for (JsNode node : body)
      if (node.kind == 'functionDecl') {
        one(frame, 15, functionCode(node, frame.current, false));
        if (root) {
          store(frame, node.text, node);
          emit(frame, 5);
        } else
          one(frame, 3, frame.current.slots.get(node.text));
      }
  }
  private void enter(Frame frame, Lexical lexical) {
    one(frame, 16, lexical.index);
    frame.current = lexical;
  }
  private void leave(Frame frame) {
    emit(frame, 17);
    frame.current = frame.current.parent;
  }
  private void sequence(Frame frame, List<JsNode> body) {
    for (JsNode node : body)
      statement(frame, node);
  }
  private Integer functionCode(JsNode node, Lexical parentScope, Boolean entry) {
    if (program.functions.size() >= 2048)
      fail(node, 'Function count exceeded');
    Frame frame = new Frame();
    JsBytecode.FunctionSpec f = new JsBytecode.FunctionSpec();
    frame.functionSpec = f;
    f.name = entry ? 'entry' : node.text == null ? '' : node.text;
    f.selfScope = -1;
    f.parameterSlots = new List<Integer>();
    f.needsArguments = false;
    f.code = new List<Integer>();
    Integer index = program.functions.size();
    program.functions.add(f);
    lastStatistics.put('functions', program.functions.size());
    lastStatistics.put('instructions', instructions);
    if (!entry && node.kind == 'function' && node.text != null) {
      Lexical self = scope(parentScope);
      bind(self, node.text, 'const', node);
      f.selfScope = self.index;
      parentScope = self;
    }
    frame.root = scope(parentScope);
    frame.current = frame.root;
    f.rootScope = frame.root.index;
    bind(frame.root, 'this', 'const', node);
    for (String name : entry ? new List<String>{ 'input' } : node.names)
      f.parameterSlots.add(bind(frame.root, name, 'param', node));
    f.argumentsSlot = bind(frame.root, 'arguments', 'var', node);
    List<JsNode> body = entry ? node.children : node.children[0].children;
    for (JsNode child : body)
      collectVars(child, frame.root, true);
    reserve(body, frame.root, true);
    hoist(frame, body, true);
    sequence(frame, body);
    one(frame, 0, constant('undefined', ''));
    emit(frame, 24);
    node.children.clear();
    return index;
  }
  private Control loop(Frame frame, List<String> labels, Boolean isLoop, Boolean breakable) {
    Control result = new Control();
    result.labels = labels;
    result.isLoop = isLoop;
    result.breakable = breakable;
    result.scope = frame.current;
    result.handlers = frame.handlers;
    frame.loops.add(result);
    return result;
  }
  private void finish(Frame frame, Control control, Integer updatePc) {
    for (Integer at : control.exits)
      patch(frame, at, pc(frame));
    for (Integer at : control.continues)
      patch(frame, at, updatePc);
    frame.loops.remove(frame.loops.size() - 1);
  }
  private void jumpOut(Frame frame, JsNode node) {
    Control control;
    for (Integer i = frame.loops.size() - 1; i >= 0; i--) {
      Control candidate = frame.loops[i];
      if (node.text != null) {
        Boolean matches = false;
        for (String name : candidate.labels)
          if (name.equals(node.text))
            matches = true;
        if (matches) {
          control = candidate;
          break;
        }
      } else if (node.kind == 'continue' ? candidate.isLoop : candidate.breakable) {
        control = candidate;
        break;
      }
    }
    if (control == null || node.kind == 'continue' && !control.isLoop)
      fail(node, 'Missing enclosing control target');
    Integer hops = 0;
    for (Lexical lexical = frame.current; lexical !== control.scope; lexical = lexical.parent)
      hops++;
    Integer at;
    if (frame.handlers != control.handlers)
      at = emit(frame, 46, 0, control.handlers, hops);
    else {
      for (Integer i = 0; i < hops; i++)
        emit(frame, 17);
      at = emit(frame, 19);
    }
    if (node.kind == 'break')
      control.exits.add(at);
    else
      control.continues.add(at);
  }
  private void statement(Frame frame, JsNode node) {
    statement(frame, node, new List<String>());
  }
  private void statement(Frame frame, JsNode node, List<String> labels) {
    budget.tick();
    String kind = node.kind;
    if (kind == 'empty' || kind == 'functionDecl')
      return;
    if (kind == 'label') {
      List<String> allLabels = new List<String>();
      allLabels.addAll(labels);
      allLabels.add(node.text);
      JsNode target = node.children[0];
      while (target.kind == 'label') {
        allLabels.add(target.text);
        target = target.children[0];
      }
      if (
        new Set<String>{ 'for', 'forOf', 'forIn', 'while', 'doWhile', 'switch' }
          .contains(target.kind)
      )
        statement(frame, target, allLabels);
      else {
        Control control = loop(frame, allLabels, false, false);
        statement(frame, target);
        finish(frame, control, pc(frame));
      }
      return;
    }
    if (kind == 'block') {
      Lexical lexical = scope(frame.current);
      reserve(node.children, lexical, false);
      if (!lexical.layout.names.isEmpty()) {
        enter(frame, lexical);
        hoist(frame, node.children, false);
        sequence(frame, node.children);
        leave(frame);
      } else
        sequence(frame, node.children);
      return;
    }
    if (kind == 'declarations') {
      sequence(frame, node.children);
      return;
    }
    if (kind == 'declare') {
      if (node.text == 'var') {
        if (!node.children.isEmpty()) {
          expression(frame, node.children[0]);
          store(frame, node.names[0], node);
          emit(frame, 5);
        }
      } else {
        if (node.children.isEmpty())
          one(frame, 0, constant('undefined', ''));
        else
          expression(frame, node.children[0]);
        one(frame, 3, frame.current.slots.get(node.names[0]));
      }
      return;
    }
    if (kind == 'expression') {
      expression(frame, node.children[0]);
      emit(frame, 5);
      return;
    }
    if (kind == 'return' || kind == 'throw') {
      if (node.children.isEmpty())
        one(frame, 0, constant('undefined', ''));
      else
        expression(frame, node.children[0]);
      emit(frame, kind == 'return' ? 24 : 30);
      return;
    }
    if (kind == 'if') {
      expression(frame, node.children[0]);
      Integer no = emit(frame, 20);
      statement(frame, node.children[1]);
      if (node.children.size() > 2) {
        Integer endAt = emit(frame, 19);
        patch(frame, no, pc(frame));
        statement(frame, node.children[2]);
        patch(frame, endAt, pc(frame));
      } else
        patch(frame, no, pc(frame));
      return;
    }
    if (kind == 'break' || kind == 'continue') {
      jumpOut(frame, node);
      return;
    }
    if (kind == 'while' || kind == 'doWhile') {
      Integer start = pc(frame), endAt;
      Control control = loop(frame, labels, true, true);
      if (kind == 'while') {
        expression(frame, node.children[0]);
        endAt = emit(frame, 20);
      }
      statement(frame, node.children[kind == 'while' ? 1 : 0]);
      Integer updatePc = pc(frame);
      if (kind == 'doWhile') {
        expression(frame, node.children[1]);
        one(frame, 21, start);
      } else
        one(frame, 19, start);
      if (endAt != null)
        patch(frame, endAt, pc(frame));
      finish(frame, control, kind == 'while' ? start : updatePc);
      return;
    }
    if (kind == 'for') {
      Lexical lexical = scope(frame.current);
      reserve(new List<JsNode>{ node.children[0] }, lexical, false);
      enter(frame, lexical);
      statement(frame, node.children[0]);
      if (lexical.layout.kinds.contains('let'))
        emit(frame, 18);
      Integer start = pc(frame), endAt;
      if (node.children[1].kind != 'empty') {
        expression(frame, node.children[1]);
        endAt = emit(frame, 20);
      }
      Control control = loop(frame, labels, true, true);
      statement(frame, node.children[3]);
      Integer updatePc = pc(frame);
      if (!lexical.layout.names.isEmpty())
        emit(frame, 18);
      if (node.children[2].kind != 'empty') {
        expression(frame, node.children[2]);
        emit(frame, 5);
      }
      one(frame, 19, start);
      if (endAt != null)
        patch(frame, endAt, pc(frame));
      finish(frame, control, updatePc);
      leave(frame);
      return;
    }
    if (kind == 'forOf' || kind == 'forIn') {
      Boolean enumeration = kind == 'forIn';
      Lexical lexical = scope(frame.current);
      Integer iterable = bind(lexical, '#iterable', 'var', node),
        index = bind(lexical, '#index', 'var', node),
        sourceSlot = enumeration ? bind(lexical, '#source', 'var', node) : null;
      if (node.text != 'var' && node.text != 'assign')
        bind(lexical, node.names[0], node.text, node);
      enter(frame, lexical);
      expression(frame, node.children[0]);
      if (enumeration) {
        emit(frame, 6);
        emit(frame, 2, 0, sourceSlot, 0);
        emit(frame, 5);
        emit(frame, 41);
      } else
        emit(frame, 31);
      emit(frame, 2, 0, iterable, 0);
      emit(frame, 5);
      one(frame, 0, constant('number', '0'));
      emit(frame, 2, 0, index, 0);
      emit(frame, 5);
      Integer start = pc(frame);
      emit(frame, 1, 0, index, 0);
      emit(frame, 1, 0, iterable, 0);
      one(frame, 8, text('length'));
      one(frame, 11, text('<'));
      Integer endAt = emit(frame, 20);
      Control control = loop(frame, labels, true, true);
      Lexical iteration = scope(frame.current);
      iteration.layout.allocationUnits = 1;
      if (node.text != 'var' && node.text != 'assign')
        bind(iteration, node.names[0], node.text, node);
      Integer keySlot = enumeration ? bind(iteration, '#key', 'var', node) : null;
      enter(frame, iteration);
      emit(frame, 1, 1, iterable, 0);
      emit(frame, 1, 1, index, 0);
      emit(frame, 7);
      Integer skip;
      if (enumeration) {
        emit(frame, 2, 0, keySlot, 0);
        emit(frame, 5);
        emit(frame, 1, 1, sourceSlot, 0);
        emit(frame, 1, 0, keySlot, 0);
        emit(frame, 47);
        skip = emit(frame, 20);
        emit(frame, 1, 0, keySlot, 0);
      }
      if (node.text == 'var' || node.text == 'assign') {
        store(frame, node.names[0], node);
        emit(frame, 5);
      } else
        one(frame, 3, 0);
      statement(frame, node.children[1]);
      if (skip != null)
        patch(frame, skip, pc(frame));
      leave(frame);
      Integer updatePc = pc(frame);
      emit(frame, 26, 0, index, 3);
      emit(frame, 5);
      one(frame, 19, start);
      patch(frame, endAt, pc(frame));
      finish(frame, control, updatePc);
      leave(frame);
      return;
    }
    if (kind == 'switch') {
      expression(frame, node.children[0]);
      Lexical lexical = scope(frame.current);
      Integer value = bind(lexical, '#switch', 'var', node);
      List<JsNode> body = new List<JsNode>();
      for (Integer i = 1; i < node.children.size(); i++)
        body.addAll(node.children[i].children[1].children);
      reserve(body, lexical, false);
      enter(frame, lexical);
      emit(frame, 2, 0, value, 0);
      emit(frame, 5);
      hoist(frame, body, false);
      Control control = loop(frame, labels, false, true);
      List<Integer> tests = new List<Integer>();
      Integer otherwise;
      for (Integer i = 1; i < node.children.size(); i++) {
        JsNode clause = node.children[i];
        if (clause.children[0].kind == 'empty')
          tests.add(null);
        else {
          emit(frame, 1, 0, value, 0);
          expression(frame, clause.children[0]);
          one(frame, 11, text('==='));
          tests.add(emit(frame, 21));
        }
      }
      Integer fallback = emit(frame, 19);
      for (Integer i = 1; i < node.children.size(); i++) {
        if (tests[i - 1] == null)
          otherwise = pc(frame);
        else
          patch(frame, tests[i - 1], pc(frame));
        sequence(frame, node.children[i].children[1].children);
      }
      patch(frame, fallback, otherwise == null ? pc(frame) : otherwise);
      finish(frame, control, pc(frame));
      leave(frame);
      return;
    }
    if (kind == 'try') {
      Boolean caught = node.children[1].kind != 'empty',
        finalized = node.children[2].kind != 'empty';
      Integer start = emit(frame, 43, -1, -1, 0);
      frame.handlers++;
      statement(frame, node.children[0]);
      emit(frame, 44);
      if (caught) {
        frame.functionSpec.code[start * 4 + 1] = pc(frame);
        Lexical lexical = scope(frame.current);
        Integer caughtSlot;
        if (node.names[0] != '')
          caughtSlot = bind(lexical, node.names[0], 'let', node);
        List<JsNode> body = node.children[1].children;
        reserve(body, lexical, false);
        enter(frame, lexical);
        if (caughtSlot == null)
          emit(frame, 5);
        else
          one(frame, 3, caughtSlot);
        hoist(frame, body, false);
        sequence(frame, body);
        leave(frame);
        emit(frame, 44);
      }
      if (finalized) {
        frame.functionSpec.code[start * 4 + 2] = pc(frame);
        statement(frame, node.children[2]);
        emit(frame, 45);
      }
      frame.handlers--;
      frame.functionSpec.code[start * 4 + 3] = pc(frame);
      return;
    }
    fail(node, 'Unsupported statement ' + kind);
  }
  private void expression(Frame frame, JsNode node) {
    budget.tick();
    String kind = node.kind;
    if (kind == 'number' || kind == 'string') {
      one(
        frame,
        0,
        constant(kind, kind == 'number' ? String.valueOf(Double.valueOf(node.text)) : node.text)
      );
      return;
    }
    if (kind == 'literal') {
      one(
        frame,
        0,
        constant(
          node.text == 'true' || node.text == 'false' ? 'boolean' : node.text,
          node.text == 'true' || node.text == 'false' ? node.text : ''
        )
      );
      return;
    }
    if (kind == 'identifier') {
      load(frame, node.text);
      return;
    }
    if (kind == 'function') {
      one(frame, 15, functionCode(node, frame.current, false));
      return;
    }
    if (kind == 'array') {
      String mask = '';
      Integer count = 0;
      for (JsNode child : node.children) {
        Boolean hole = child.kind == 'hole';
        mask += hole ? '0' : '1';
        if (!hole) {
          expression(frame, child);
          count++;
        }
      }
      if (count == node.children.size())
        one(frame, 13, count);
      else
        emit(frame, 48, node.children.size(), text(mask), count);
      return;
    }
    if (kind == 'object') {
      for (Integer i = 0; i < node.children.size(); i++) {
        one(frame, 0, constant('string', node.names[i]));
        expression(frame, node.children[i]);
      }
      one(frame, 14, node.children.size());
      return;
    }
    if (kind == 'member') {
      expression(frame, node.children[0]);
      if (node.children[1].kind == 'string')
        one(frame, 8, text(node.children[1].text));
      else {
        expression(frame, node.children[1]);
        emit(frame, 7);
      }
      return;
    }
    if (kind == 'unary') {
      if (node.text == 'delete') {
        JsNode target = node.children[0];
        if (target.kind != 'member')
          fail(node, 'Only property deletion is supported');
        expression(frame, target.children[0]);
        expression(frame, target.children[1]);
        emit(frame, 42);
        return;
      }
      if (
        node.text == 'typeof' &&
        node.children[0].kind == 'identifier' &&
        resolve(frame, node.children[0].text) == null
      )
        one(frame, 27, text(node.children[0].text));
      else {
        expression(frame, node.children[0]);
        one(frame, 12, text(node.text));
      }
      return;
    }
    if (kind == 'binary') {
      expression(frame, node.children[0]);
      if (node.text == '&&' || node.text == '||') {
        emit(frame, 6);
        Integer endAt = emit(frame, node.text == '&&' ? 20 : 21);
        emit(frame, 5);
        expression(frame, node.children[1]);
        patch(frame, endAt, pc(frame));
      } else {
        expression(frame, node.children[1]);
        one(frame, 11, text(node.text));
      }
      return;
    }
    if (kind == 'conditional') {
      expression(frame, node.children[0]);
      Integer no = emit(frame, 20);
      expression(frame, node.children[1]);
      Integer endAt = emit(frame, 19);
      patch(frame, no, pc(frame));
      expression(frame, node.children[2]);
      patch(frame, endAt, pc(frame));
      return;
    }
    if (kind == 'sequence') {
      for (Integer i = 0; i < node.children.size(); i++) {
        expression(frame, node.children[i]);
        if (i < node.children.size() - 1)
          emit(frame, 5);
      }
      return;
    }
    if (kind == 'assign') {
      JsNode lhs = node.children[0];
      Boolean compound = node.text != '=';
      if (lhs.kind == 'identifier') {
        if (compound)
          load(frame, lhs.text);
        expression(frame, node.children[1]);
        if (compound)
          one(frame, 11, text(node.text.substring(0, node.text.length() - 1)));
        store(frame, lhs.text, node);
      } else {
        expression(frame, lhs.children[0]);
        expression(frame, lhs.children[1]);
        emit(frame, 32);
        if (compound) {
          emit(frame, 25);
          emit(frame, 7);
        }
        expression(frame, node.children[1]);
        if (compound)
          one(frame, 11, text(node.text.substring(0, node.text.length() - 1)));
        emit(frame, 9);
      }
      return;
    }
    if (kind == 'update') {
      JsNode lhs = node.children[0];
      Integer mode = (node.text.startsWith('++') ? 2 : 0) + (node.text.endsWith('pre') ? 1 : 0);
      if (lhs.kind == 'identifier') {
        Address ref = resolve(frame, lhs.text);
        if (ref == null)
          fail(node, 'Unresolved update binding');
        emit(frame, 26, ref.depth, ref.slot, mode);
      } else {
        expression(frame, lhs.children[0]);
        expression(frame, lhs.children[1]);
        one(frame, 29, mode);
      }
      return;
    }
    if (kind == 'call' || kind == 'construct') {
      JsNode callee = node.children[0];
      Boolean construct = kind == 'construct';
      if (!construct && callee.kind == 'member') {
        expression(frame, callee.children[0]);
        emit(frame, 6);
        if (callee.children[1].kind == 'string')
          one(frame, 8, text(callee.children[1].text));
        else {
          expression(frame, callee.children[1]);
          emit(frame, 7);
        }
      } else {
        if (!construct)
          one(frame, 0, constant('undefined', ''));
        expression(frame, callee);
      }
      if (node.children.size() > 101)
        fail(node, 'Argument count exceeded');
      for (Integer i = 1; i < node.children.size(); i++)
        expression(frame, node.children[i]);
      one(frame, construct ? 23 : 22, node.children.size() - 1);
      return;
    }
    fail(node, 'Unsupported expression ' + kind);
  }
}
