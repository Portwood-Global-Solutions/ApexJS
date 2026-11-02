/** Tree-walking JavaScript subset interpreter. There is no eval, callout, or browser dependency. */
public with sharing class JsRuntime {
  private static final Double TWO32 = Double.valueOf('4294967296');
  private static final Double TWO31 = Double.valueOf('2147483648');
  private static final Set<String> HOIST_CONTAINERS = new Set<String>{
    'program',
    'block',
    'if',
    'while',
    'doWhile',
    'for',
    'forOf',
    'try',
    'declarations'
  };
  private static final Set<String> TYPEOF_PRIMITIVES = new Set<String>{
    'undefined',
    'string',
    'number',
    'boolean',
    'function'
  };
  private static final Set<String> ARRAY_METHODS = new Set<String>{
    'push',
    'join',
    'map',
    'filter',
    'reduce',
    'slice',
    'splice',
    'concat'
  };
  private static final Set<String> STRING_METHODS = new Set<String>{
    'toUpperCase',
    'toLowerCase',
    'trim',
    'charCodeAt',
    'codePointAt',
    'slice',
    'split',
    'replace',
    'padStart',
    'match',
    'indexOf'
  };
  private static final Set<String> ORDERED_OPERATORS = new Set<String>{ '<', '<=', '>', '>=' };
  public JsBudget budget;
  public JsBytecode bytecodeVm;
  public JsValue objectPrototype;
  public JsValue functionPrototype;
  public JsValue arrayPrototype;
  public JsValue mapPrototype;
  public JsValue promisePrototype;
  public JsValue arrayBufferPrototype;
  public JsValue byteArrayPrototype;
  private List<JsPromiseNatives.Job> promiseJobs = new List<JsPromiseNatives.Job>();
  private Integer promiseCursor = 0, promiseJobCount = 0;
  public void enqueuePromiseJob(JsPromiseNatives.Job job) {
    if (++promiseJobCount > 10000)
      throw new JsException('BudgetError: Promise job count exceeded.');
    budget.allocate(1);
    promiseJobs.add(job);
  }
  public void drainPromiseJobs() {
    while (promiseCursor < promiseJobs.size()) {
      budget.poll();
      JsPromiseNatives.Job job = promiseJobs[promiseCursor];
      promiseJobs[promiseCursor++] = null;
      JsPromiseNatives.runJob(job, this);
    }
    promiseJobs.clear();
    promiseCursor = 0;
  }
  public Map<String, JsValue> errorPrototypes = new Map<String, JsValue>();
  public List<String> logs = new List<String>();
  private Integer callDepth = 0;
  private Integer expressionDepth = 0;

  private class Completion {
    public String kind;
    public JsValue value;
    public Completion(String kind, JsValue value) {
      this.kind = kind;
      this.value = value;
    }
  }
  private class Reference {
    public JsScope scope;
    public String name;
    public JsValue target;
    public String key;
  }

  public JsRuntime(JsBudget budget) {
    this.budget = budget;
  }

  public JsValue run(JsNode program, JsValue input) {
    JsScope globals = new JsScope(null);
    JsNatives.install(globals, this);
    JsScope local = new JsScope(globals);
    local.functionScope = true;
    local.parameter('input', input);
    local.declare('this', new JsValue('undefined'), true);
    if (program.needsArguments)
      local.parameter('arguments', argumentsValue(new List<JsValue>{ input }));
    Completion completion = sequence(program.children, local, program);
    if (completion.kind == 'break' || completion.kind == 'continue') {
      throw new JsException('SyntaxError: ' + completion.kind + ' outside a loop.');
    }
    return completion.kind == 'return' ? completion.value : new JsValue('undefined');
  }

  private Completion sequence(List<JsNode> nodes, JsScope scope) {
    return sequence(nodes, scope, null);
  }
  private Completion sequence(List<JsNode> nodes, JsScope scope, JsNode body) {
    for (JsNode node : nodes) {
      reserveDeclarations(node, scope);
    }
    if (scope.functionScope) {
      if (body.hoistedNames == null) {
        List<String> collectedNames = new List<String>();
        for (JsNode node : nodes) {
          collectVars(node, collectedNames);
        }
        body.hoistedNames = collectedNames;
      }
      for (String name : body.hoistedNames) {
        scope.declareVar(name);
      }
    }
    for (JsNode node : nodes) {
      if (node.kind == 'functionDecl') {
        scope.functionDeclaration(node.text, makeFunction(node, scope));
      }
    }
    for (JsNode node : nodes) {
      Completion completion = execute(node, scope);
      if (completion.kind != 'normal') {
        return completion;
      }
    }
    return new Completion('normal', null);
  }
  private void reserveDeclarations(JsNode node, JsScope scope) {
    if (node.kind == 'declare' && !node.text.equals('var')) {
      scope.reserve(node.names[0], node.text.equals('const'));
    }
    if (node.kind == 'declarations') {
      for (JsNode child : node.children) {
        reserveDeclarations(child, scope);
      }
    }
  }
  private void collectVars(JsNode node, List<String> names) {
    budget.tick();
    if (node.kind == 'function' || node.kind == 'functionDecl') {
      return;
    }
    if (node.kind == 'declare' && node.text.equals('var')) {
      names.add(node.names[0]);
    }
    if (node.kind == 'forOf' && node.text.equals('var')) {
      names.add(node.names[0]);
    }
    if (!HOIST_CONTAINERS.contains(node.kind)) {
      return;
    }
    for (JsNode child : node.children) {
      collectVars(child, names);
    }
  }
  private Completion execute(JsNode node, JsScope scope) {
    budget.tick();
    if (node.kind == 'block') {
      return sequence(node.children, new JsScope(scope));
    }
    if (node.kind == 'declarations') {
      for (JsNode child : node.children) {
        execute(child, scope);
      }
    } else if (node.kind == 'declare') {
      JsValue value = node.children.isEmpty()
        ? new JsValue('undefined')
        : evaluate(node.children[0], scope);
      if (node.text.equals('var')) {
        if (!node.children.isEmpty()) {
          scope.assign(node.names[0], value);
        }
      } else {
        scope.initialize(node.names[0], value);
      }
    } else if (node.kind == 'functionDecl') {
      // Function declarations were initialized before this statement list ran.
    } else if (node.kind == 'return') {
      return new Completion(
        'return',
        node.children.isEmpty() ? new JsValue('undefined') : evaluate(node.children[0], scope)
      );
    } else if (node.kind == 'throw') {
      throw JsThrownException.carrying(evaluate(node.children[0], scope));
    } else if (node.kind == 'try') {
      return executeTry(node, scope);
    } else if (node.kind == 'break' || node.kind == 'continue') {
      return new Completion(node.kind, null);
    } else if (node.kind == 'expression') {
      evaluate(node.children[0], scope);
    } else if (node.kind == 'if') {
      if (evaluate(node.children[0], scope).truthy()) {
        return execute(node.children[1], scope);
      }
      if (node.children.size() == 3) {
        return execute(node.children[2], scope);
      }
    } else if (node.kind == 'while') {
      while (evaluate(node.children[0], scope).truthy()) {
        Completion completion = execute(node.children[1], scope);
        if (completion.kind == 'return') {
          return completion;
        }
        if (completion.kind == 'break') {
          break;
        }
      }
    } else if (node.kind == 'doWhile') {
      do {
        Completion completion = execute(node.children[0], scope);
        if (completion.kind == 'return')
          return completion;
        if (completion.kind == 'break')
          break;
      } while (evaluate(node.children[1], scope).truthy());
    } else if (node.kind == 'for') {
      JsScope iteration = new JsScope(scope);
      reserveDeclarations(node.children[0], iteration);
      execute(node.children[0], iteration);
      while (node.children[1].kind == 'empty' || evaluate(node.children[1], iteration).truthy()) {
        budget.tick();
        Completion completion = execute(node.children[3], iteration);
        if (completion.kind == 'return') {
          return completion;
        }
        if (completion.kind == 'break') {
          break;
        }
        JsScope nextIteration = new JsScope(scope);
        copyLoopBindings(node.children[0], iteration, nextIteration);
        iteration = nextIteration;
        if (node.children[2].kind != 'empty') {
          evaluate(node.children[2], iteration);
        }
      }
    } else if (node.kind == 'forOf') {
      JsScope iterableScope = new JsScope(scope);
      if (!node.text.equals('var')) {
        iterableScope.reserve(node.names[0], node.text.equals('const'));
      }
      JsValue iterable = evaluate(node.children[0], iterableScope);
      if (iterable.kind != 'array') {
        throw new JsException('TypeError: for...of currently requires an array.');
      }
      // Index-based iteration intentionally observes pushes, as the JS array iterator does.
      Integer index = 0;
      while (index < iterable.items.size()) {
        budget.tick();
        budget.allocate(1);
        JsScope iteration = new JsScope(scope);
        if (node.text.equals('var')) {
          scope.assign(node.names[0], getProperty(iterable, String.valueOf(index++)));
        } else {
          iteration.declare(
            node.names[0],
            getProperty(iterable, String.valueOf(index++)),
            node.text.equals('const')
          );
        }
        Completion completion = execute(node.children[1], iteration);
        if (completion.kind == 'return') {
          return completion;
        }
        if (completion.kind == 'break') {
          break;
        }
      }
    }
    return new Completion('normal', null);
  }
  private void copyLoopBindings(JsNode node, JsScope fromScope, JsScope toScope) {
    if (node.kind == 'declare' && !node.text.equals('var')) {
      toScope.declare(node.names[0], fromScope.read(node.names[0]), node.text.equals('const'));
    }
    if (node.kind == 'declarations') {
      for (JsNode child : node.children) {
        copyLoopBindings(child, fromScope, toScope);
      }
    }
  }
  public JsValue languageError(JsException error) {
    JsValue value = new JsValue('error');
    String message = error.getMessage();
    Integer colon = message.indexOf(': ');
    if (colon > 0) {
      value.errorName = message.substring(0, colon);
      message = message.substring(colon + 2);
    }
    value.scalar = message;
    value.hasErrorMessage = true;
    value.explicitPrototype = true;
    value.prototypeParent = errorPrototypes.containsKey(value.errorName)
      ? errorPrototypes.get(value.errorName)
      : errorPrototypes.get('Error');
    return value;
  }
  private Completion executeTry(JsNode node, JsScope scope) {
    Completion completion = new Completion('normal', null);
    JsThrownException thrown;
    JsException failure;
    try {
      completion = execute(node.children[0], scope);
    } catch (JsThrownException error) {
      thrown = error;
    } catch (JsException error) {
      if (error.getMessage().startsWith('BudgetError:'))
        throw error;
      failure = error;
    }
    if ((thrown != null || failure != null) && node.children[1].kind != 'empty') {
      JsScope caught = new JsScope(scope);
      if (node.names[0] != '')
        caught.declare(
          node.names[0],
          thrown != null ? thrown.value : languageError(failure),
          false
        );
      thrown = null;
      failure = null;
      try {
        completion = sequence(node.children[1].children, caught);
      } catch (JsThrownException error) {
        thrown = error;
      } catch (JsException error) {
        if (error.getMessage().startsWith('BudgetError:'))
          throw error;
        failure = error;
      }
    }
    if (node.children[2].kind != 'empty') {
      Completion finalCompletion = execute(node.children[2], scope);
      if (finalCompletion.kind != 'normal')
        return finalCompletion;
    }
    if (thrown != null)
      throw thrown;
    if (failure != null)
      throw failure;
    return completion;
  }

  public JsValue evaluate(JsNode node, JsScope scope) {
    budget.tick();
    expressionDepth++;
    try {
      if (expressionDepth > 90) {
        throw new JsException('BudgetError: Expression nesting exceeded.');
      }
      if (node.cachedLiteral != null) {
        return node.cachedLiteral;
      }
      if (node.kind == 'number') {
        node.cachedLiteral = JsValue.num(Double.valueOf(node.text));
        return node.cachedLiteral;
      }
      if (node.kind == 'string') {
        node.cachedLiteral = JsValue.str(node.text);
        return node.cachedLiteral;
      }
      if (node.kind == 'literal') {
        node.cachedLiteral = node.text.equals('true') || node.text.equals('false')
          ? JsValue.bool(node.text.equals('true'))
          : new JsValue(node.text);
        return node.cachedLiteral;
      }
      if (node.kind == 'identifier') {
        return scope.read(node.text);
      }
      if (node.kind == 'function') {
        return makeFunction(node, scope);
      }
      if (node.kind == 'array') {
        budget.allocate(node.children.size() + 1);
        JsValue result = new JsValue('array');
        for (JsNode child : node.children) {
          result.items.add(evaluate(child, scope));
        }
        return result;
      }
      if (node.kind == 'object') {
        budget.allocate(node.children.size() + 1);
        JsValue result = new JsValue('object');
        for (Integer i = 0; i < node.children.size(); i++) {
          checkKey(node.names[i]);
          result.props.put(node.names[i], evaluate(node.children[i], scope));
        }
        return result;
      }
      if (node.kind == 'conditional') {
        return evaluate(node.children[evaluate(node.children[0], scope).truthy() ? 1 : 2], scope);
      }
      if (node.kind == 'sequence') {
        JsValue result = new JsValue('undefined');
        for (JsNode child : node.children) {
          result = evaluate(child, scope);
        }
        return result;
      }
      if (node.kind == 'unary') {
        JsNode operand = node.children[0];
        if (
          node.text.equals('typeof') &&
          operand.kind == 'identifier' &&
          !scope.has(operand.text)
        ) {
          return JsValue.str('undefined');
        }
        JsValue value = evaluate(operand, scope);
        if (node.text.equals('!')) {
          return JsValue.bool(!value.truthy());
        }
        if (node.text.equals('-')) {
          return JsValue.num(-value.asNumber());
        }
        if (node.text.equals('+')) {
          return JsValue.num(value.asNumber());
        }
        if (node.text.equals('~')) {
          return JsValue.num(Double.valueOf('-1') - Double.valueOf(toInt32(bitwiseNumber(value))));
        }
        if (node.text.equals('void')) {
          return new JsValue('undefined');
        }
        if (node.text.equals('typeof')) {
          return JsValue.str(
            TYPEOF_PRIMITIVES.contains(value.kind)
              ? value.kind
              : value.kind == 'native' ? 'function' : 'object'
          );
        }
      }
      if (node.kind == 'binary') {
        JsValue lhs = evaluate(node.children[0], scope);
        if (node.text.equals('&&')) {
          return lhs.truthy() ? evaluate(node.children[1], scope) : lhs;
        }
        if (node.text.equals('||')) {
          return lhs.truthy() ? lhs : evaluate(node.children[1], scope);
        }
        return binary(node.text, lhs, evaluate(node.children[1], scope));
      }
      if (node.kind == 'member') {
        Reference ref = reference(node, scope);
        return getProperty(ref.target, ref.key);
      }
      if (node.kind == 'assign') {
        Reference ref = reference(node.children[0], scope);
        JsValue prior;
        if (!node.text.equals('=')) {
          prior = readReference(ref);
        }
        JsValue value = evaluate(node.children[1], scope);
        if (!node.text.equals('=')) {
          value = binary(node.text.substring(0, node.text.length() - 1), prior, value);
        }
        writeReference(ref, value);
        return value;
      }
      if (node.kind == 'update') {
        Reference ref = reference(node.children[0], scope);
        JsValue prior = readReference(ref);
        JsValue value = JsValue.num(
          prior.asNumber() +
          (node.text.startsWith('++') ? Double.valueOf('1') : Double.valueOf('-1'))
        );
        writeReference(ref, value);
        return node.text.endsWith('pre') ? value : prior;
      }
      if (node.kind == 'call' || node.kind == 'construct') {
        JsNode target = node.children[0];
        JsValue receiver;
        JsValue callable;
        if (target.kind == 'member') {
          Reference ref = reference(target, scope);
          receiver = ref.target;
          callable = getProperty(receiver, ref.key);
        } else {
          callable = evaluate(target, scope);
        }
        List<JsValue> args = new List<JsValue>();
        for (Integer i = 1; i < node.children.size(); i++) {
          args.add(evaluate(node.children[i], scope));
        }
        return node.kind == 'construct'
          ? construct(callable, args)
          : invoke(callable, args, receiver);
      }
      throw new JsException('Unsupported AST node ' + node.kind);
    } catch (JsException ex) {
      if (ex.getMessage().contains(' at ')) {
        throw ex;
      }
      throw new JsException(ex.getMessage() + ' at ' + node.row + ':' + node.col);
    } finally {
      expressionDepth--;
    }
  }

  public JsValue invoke(JsValue callable, List<JsValue> args, JsValue receiver) {
    budget.tick();
    callDepth++;
    try {
      if (callDepth > (JsPromiseNatives.enabled ? 64 : 24)) {
        throw new JsException('BudgetError: Call depth exceeded.');
      }
      if (callable.kind == 'native' && callable.promiseCapability != null)
        return JsPromiseNatives.invokeCapability(callable, args, this);
      if (callable.kind == 'native') {
        return JsNatives.invoke(callable.nativeName, args, receiver, this);
      }
      if (callable.kind != 'function') {
        throw new JsException('TypeError: Value is not callable.');
      }
      if (callable.bytecodeIndex != null) {
        return bytecodeVm.invoke(callable, args, receiver);
      }
      budget.allocate(1);
      JsScope local = new JsScope(callable.closure);
      local.functionScope = true;
      local.declare('this', receiver == null ? new JsValue('undefined') : receiver, true);
      for (Integer i = 0; i < callable.functionNode.names.size(); i++) {
        local.parameter(
          callable.functionNode.names[i],
          i < args.size() ? args[i] : new JsValue('undefined')
        );
      }
      if (
        callable.functionNode.needsArguments && !callable.functionNode.names.contains('arguments')
      ) {
        local.parameter('arguments', argumentsValue(args));
      }
      JsNode body = callable.functionNode.children[0];
      Completion completion = sequence(body.children, local, body);
      if (completion.kind == 'break' || completion.kind == 'continue') {
        throw new JsException('SyntaxError: ' + completion.kind + ' outside a loop.');
      }
      return completion.kind == 'return' ? completion.value : new JsValue('undefined');
    } finally {
      callDepth--;
    }
  }
  private JsValue makeFunction(JsNode node, JsScope scope) {
    budget.allocate(1);
    JsValue result = new JsValue('function');
    result.functionNode = node;
    result.closure = scope;
    if (node.kind == 'function' && node.text != null) {
      result.closure = new JsScope(scope);
      result.closure.declare(node.text, result, true);
    }
    return result;
  }
  private JsValue argumentsValue(List<JsValue> args) {
    JsValue result = new JsValue('object');
    budget.allocate(args.size() + 1);
    for (Integer i = 0; i < args.size(); i++)
      result.props.put(String.valueOf(i), args[i]);
    result.props.put('length', JsValue.num(Double.valueOf(args.size())));
    result.attributes('length', false, true, true);
    return result;
  }
  public JsValue construct(JsValue callable, List<JsValue> args) {
    if (callable.kind == 'native') {
      if (callable.nativeName.startsWith('compat.'))
        return JsCompatGlobals.construct(callable.nativeName, args, this);
      if (callable.nativeName == 'Promise.construct')
        return JsPromiseNatives.construct(args, this);
      if (callable.nativeName == 'Array.construct')
        return JsArrayNatives.construct(args, this);
      if (callable.nativeName == 'Object.construct' || callable.nativeName == 'Map.construct') {
        return JsObjectNatives.invoke(
          callable.nativeName == 'Map.construct' ? 'Map.new' : callable.nativeName,
          args,
          null,
          this
        );
      }
      JsValue result = JsWebNatives.construct(callable, args, this);
      if (
        JsObjectNatives.objectLike(result) &&
        callable.constructorPrototype != null &&
        !result.explicitPrototype
      ) {
        result.explicitPrototype = true;
        result.prototypeParent = callable.constructorPrototype;
      }
      return result;
    }
    if (callable.kind != 'function') {
      throw new JsException('TypeError: Value is not a constructor.');
    }
    budget.allocate(1);
    JsValue instance = new JsValue('object');
    JsValue proto = getProperty(callable, 'prototype');
    instance.explicitPrototype = true;
    instance.prototypeParent = JsObjectNatives.objectLike(proto) ? proto : objectPrototype;
    JsValue returned = invoke(callable, args, instance);
    return JsObjectNatives.objectLike(returned) ? returned : instance;
  }
  public JsValue prototypeOf(JsValue value) {
    if (value.explicitPrototype) {
      return value.prototypeParent;
    }
    if (value.kind == 'array')
      return arrayPrototype;
    return value.kind == 'function' || value.kind == 'native' ? functionPrototype : objectPrototype;
  }
  public JsValue functionPrototypeOf(JsValue value) {
    if (value.constructorPrototype == null) {
      budget.allocate(2);
      value.constructorPrototype = new JsValue('object');
      value.constructorPrototype.props.put('constructor', value);
      value.constructorPrototype.attributes('constructor', false, true, true);
    }
    return value.constructorPrototype;
  }
  public void writeProperty(JsValue target, String key, JsValue value) {
    checkKey(key);
    Reference ref = new Reference();
    ref.target = target;
    ref.key = key;
    writeReference(ref, value);
  }
  public String referenceKey(JsValue target, JsValue keyValue) {
    String key = keyValue.asString();
    checkKey(key);
    if (target.kind == 'null' || target.kind == 'undefined')
      throw new JsException('TypeError: Cannot access property of ' + target.kind);
    return key;
  }

  private Reference reference(JsNode node, JsScope scope) {
    Reference result = new Reference();
    if (node.kind == 'identifier') {
      result.scope = scope;
      result.name = node.text;
    } else {
      result.target = evaluate(node.children[0], scope);
      result.key = evaluate(node.children[1], scope).asString();
      checkKey(result.key);
      if (result.target.kind == 'null' || result.target.kind == 'undefined') {
        throw new JsException('TypeError: Cannot access property of ' + result.target.kind);
      }
    }
    return result;
  }
  private JsValue readReference(Reference ref) {
    return ref.scope == null ? getProperty(ref.target, ref.key) : ref.scope.read(ref.name);
  }
  private void writeReference(Reference ref, JsValue value) {
    if (ref.scope != null) {
      ref.scope.assign(ref.name, value);
      return;
    }
    Integer indexed = ref.target.kind == 'array' ? arrayIndex(ref.key) : null;
    Boolean arrayData =
      ref.target.kind == 'array' &&
      ref.key != 'length' &&
      indexed < 0 &&
      arrayNamedKey(ref.key);
    Boolean typedData =
      JsLibraryBuiltins.enabled &&
      (ref.target.kind == 'uint8array' || JsTypedBuffers.typed(ref.target)) &&
      ref.key.length() > 0 &&
      'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_$'.contains(ref.key.substring(0, 1)) &&
      !new Set<String>{ 'length', 'byteLength', 'byteOffset', 'buffer', 'NaN', 'Infinity' }
        .contains(ref.key);
    Boolean regexData =
      JsLibraryBuiltins.enabled &&
      ref.target.kind == 'regexp' &&
      ref.key == 'lastIndex';
    if (
      ref.target.kind == 'object' ||
      ref.target.kind == 'function' ||
      ref.target.kind == 'native' ||
      ref.target.kind == 'error' ||
      arrayData ||
      typedData ||
      regexData
    ) {
      if (ref.target.kind == 'error' && ref.key == 'message')
        ref.target.attributes('message', false, true, true);
      if (
        (ref.target.kind == 'function' || ref.target.constructorPrototype != null) &&
        ref.key.equals('prototype')
      ) {
        ref.target.constructorPrototype = value;
        return;
      }
      if (
        (ref.target.kind == 'function' || ref.target.kind == 'native') &&
        (ref.key.equals('name') || ref.key.equals('length'))
      ) {
        throw new JsException('TypeError: Function metadata is read-only.');
      }
      if (!ref.target.writable(ref.key)) {
        throw new JsException('TypeError: Property is read-only: ' + ref.key);
      }
      JsValue parent = prototypeOf(ref.target);
      Integer inheritedDepth = 0;
      while (
        (ref.target.props == null || !ref.target.props.containsKey(ref.key)) && parent != null
      ) {
        if (++inheritedDepth > 64) {
          throw new JsException('BudgetError: Prototype depth exceeded.');
        }
        if (parent.props != null && parent.props.containsKey(ref.key)) {
          if (!parent.writable(ref.key)) {
            throw new JsException('TypeError: Inherited property is read-only: ' + ref.key);
          }
          break;
        }
        parent = prototypeOf(parent);
      }
      if (ref.target.props == null) {
        ref.target.props = new Map<String, JsValue>();
      }
      if (!ref.target.props.containsKey(ref.key)) {
        budget.allocate(1);
      }
      ref.target.props.put(ref.key, value);
      return;
    }
    if (ref.target.kind == 'array') {
      if (ref.key.equals('length')) {
        Double length = value.asNumber();
        if (length < 0 || length > JsArrayNatives.maxLength() || length != Math.floor(length)) {
          throw new JsException('RangeError: Invalid bounded array length.');
        }
        JsArrayNatives.resize(ref.target, length.intValue(), this);
        return;
      }
      Integer index = indexed;
      if (index >= 0) {
        if (index >= JsArrayNatives.maxLength())
          throw new JsException('BudgetError: Array size exceeded.');
        if (index >= ref.target.items.size() || ref.target.items[index] == null) {
          JsValue parent = prototypeOf(ref.target);
          Integer depth = 0;
          while (parent != null) {
            if (++depth > 64)
              throw new JsException('BudgetError: Prototype depth exceeded.');
            if (ownProperty(parent, ref.key) != null) {
              if (!parent.writable(ref.key))
                throw new JsException('TypeError: Inherited property is read-only: ' + ref.key);
              break;
            }
            parent = prototypeOf(parent);
          }
        }
        if (index >= ref.target.items.size())
          JsArrayNatives.resize(ref.target, index + 1, this);
        ref.target.items[index] = value;
        return;
      }
    }
    if (JsTypedBuffers.typed(ref.target)) {
      JsTypedBuffers.write(ref.target, ref.key, value);
      return;
    }
    if (ref.target.kind == 'uint8array') {
      Integer index = arrayIndex(ref.key);
      if (index >= 0 && index < JsBytes.length(ref.target)) {
        JsBytes.write(ref.target, index, JsWebNatives.toByte(value));
        return;
      }
      if (index >= 0)
        return; // ECMAScript ignores writes beyond a typed array, without growing it.
      throw new JsException('TypeError: Unsupported typed array property assignment.');
    }
    throw new JsException('TypeError: Unsupported property assignment.');
  }
  public JsValue getProperty(JsValue target, String key) {
    checkKey(key);
    if (target === mapPrototype && key == 'size')
      throw new JsException('TypeError: Map size requires a Map receiver.');
    JsValue own = ownProperty(target, key);
    if (own != null && own.kind == 'arraybuffer' && own.prototypeParent == null)
      own.prototypeParent = arrayBufferPrototype;
    if (own != null) {
      return target.getters != null && target.getters.containsKey(key)
        ? readGetter(target.getters.get(key), target)
        : own;
    }
    JsValue parent = prototypeOf(target);
    Integer depth = 0;
    while (parent != null) {
      if (++depth > 64) {
        throw new JsException('BudgetError: Prototype depth exceeded.');
      }
      if (parent === mapPrototype && key == 'size') {
        if (target.kind != 'map')
          throw new JsException('TypeError: Map size requires a Map receiver.');
        return JsValue.num(Double.valueOf(target.items.size() / 2));
      }
      budget.poll();
      own = ownProperty(parent, key);
      if (own != null) {
        return parent.getters != null && parent.getters.containsKey(key)
          ? readGetter(parent.getters.get(key), target)
          : own;
      }
      parent = prototypeOf(parent);
    }
    return new JsValue('undefined');
  }
  private JsValue readGetter(JsValue getter, JsValue receiver) {
    return getter.kind == 'undefined' ? getter : invoke(getter, new List<JsValue>(), receiver);
  }
  public JsValue ownProperty(JsValue target, String key) {
    if (target.props != null && target.props.containsKey(key)) {
      return target.props.get(key);
    }
    if (target.kind == 'function' || target.kind == 'native') {
      if (
        key.equals('prototype') &&
        (target.kind == 'function' ||
        target.constructorPrototype != null)
      ) {
        return functionPrototypeOf(target);
      }
      if (key.equals('length') && target.kind == 'function') {
        return JsValue.num(
          Double.valueOf(
            target.bytecodeIndex == null
              ? target.functionNode.names.size()
              : bytecodeVm.functionArity(target.bytecodeIndex)
          )
        );
      }
      if (key.equals('name') && target.kind == 'function') {
        return JsValue.str(
          target.bytecodeIndex != null
            ? bytecodeVm.functionName(target.bytecodeIndex)
            : target.functionNode.text == null ? '' : target.functionNode.text
        );
      }
    }
    JsValue webProperty = JsWebNatives.property(target, key);
    if (webProperty != null) {
      return webProperty;
    }
    if (target.kind == 'array' || target.kind == 'string') {
      Integer length = target.kind == 'array'
        ? target.items.size()
        : ((String) target.scalar).length();
      if (key.equals('length')) {
        return JsValue.num(Double.valueOf(length));
      }
      Integer index = arrayIndex(key);
      if (index >= 0 && index < length) {
        return target.kind == 'array'
          ? target.items[index]
          : JsValue.str(((String) target.scalar).substring(index, index + 1));
      }
      if (target.kind == 'string' && STRING_METHODS.contains(key)) {
        return JsValue.nativeFunction('string.' + key);
      }
    }
    if (target.kind == 'null' || target.kind == 'undefined') {
      throw new JsException('TypeError: Cannot read property of ' + target.kind);
    }
    return null;
  }
  private Integer arrayIndex(String key) {
    if (key.length() == 0 || key.length() > 8) {
      return -1;
    }
    for (Integer i = 0; i < key.length(); i++) {
      if (!'0123456789'.contains(key.substring(i, i + 1))) {
        return -1;
      }
    }
    Integer value = Integer.valueOf(key);
    return String.valueOf(value).equals(key) ? value : -1;
  }
  private Boolean arrayNamedKey(String key) {
    if (key.length() == 0 || key.length() > 10 || key.length() > 1 && key.startsWith('0'))
      return true;
    for (Integer i = 0; i < key.length(); i++)
      if (!'0123456789'.contains(key.substring(i, i + 1)))
        return true;
    return Long.valueOf(key) >= 4294967295L;
  }
  private void checkKey(String key) {
    if (key.equals('__proto__')) {
      throw new JsException('TypeError: Prototype operations are outside this subset.');
    }
  }
  private static Integer toInt32(Double numberValue) {
    if (numberValue >= -TWO31 && numberValue < TWO31)
      return numberValue.intValue();
    if (numberValue >= -TWO32 && numberValue < TWO32)
      return numberValue.longValue().intValue();
    Double whole = numberValue < 0 ? Math.ceil(numberValue) : Math.floor(numberValue);
    Double word = whole - Math.floor(whole / TWO32) * TWO32;
    if (word >= TWO31) {
      word -= TWO32;
    }
    return word.intValue();
  }
  private Double bitwiseNumber(JsValue value) {
    if (value.kind == 'number')
      return value.nanNumber || String.valueOf(value.scalar).contains('Infinity')
        ? Double.valueOf('0')
        : value.asNumber();
    if (value.kind == 'null' || value.kind == 'undefined')
      return 0;
    if (value.kind == 'boolean')
      return (Boolean) value.scalar ? Double.valueOf('1') : Double.valueOf('0');
    if (value.kind != 'string')
      throw new JsException(
        'TypeError: Object coercion for bitwise operators is outside this subset.'
      );
    String text = JsNatives.trimEcma((String) value.scalar);
    if (text == '')
      return 0;
    String prefix = text.length() > 2 ? text.substring(0, 2).toLowerCase() : '';
    if (prefix == '0x' || prefix == '0b' || prefix == '0o') {
      Integer radix = prefix == '0x' ? 16 : prefix == '0b' ? 2 : 8;
      Double result = 0;
      for (Integer i = 2; i < text.length(); i++) {
        budget.tick();
        Integer digit = '0123456789abcdef'.indexOf(text.substring(i, i + 1).toLowerCase());
        if (digit < 0 || digit >= radix)
          return 0;
        result = result * radix + digit;
      }
      return String.valueOf(result).contains('Infinity') ? Double.valueOf('0') : result;
    }
    try {
      Double result = Double.valueOf(text);
      String representation = String.valueOf(result);
      return representation.contains('NaN') || representation.contains('Infinity')
        ? Double.valueOf('0')
        : result;
    } catch (Exception ex) {
      return 0;
    }
  }
  public JsValue unary(String op, JsValue value) {
    if (op == '!')
      return JsValue.bool(!value.truthy());
    if (op == '-')
      return JsValue.num(-numeric(value));
    if (op == '+')
      return JsValue.num(numeric(value));
    if (op == '~')
      return JsValue.num(Double.valueOf('-1') - Double.valueOf(toInt32(bitwiseNumber(value))));
    if (op == 'void')
      return new JsValue('undefined');
    if (op == 'typeof')
      return JsValue.str(
        TYPEOF_PRIMITIVES.contains(value.kind)
          ? value.kind
          : value.kind == 'native' ? 'function' : 'object'
      );
    throw new JsException('Unsupported unary operator ' + op);
  }
  public JsValue binary(String op, JsValue lhs, JsValue rhs) {
    if (op == '==' || op == '!=')
      return JsValue.bool(op == '==' ? looseEqual(lhs, rhs) : !looseEqual(lhs, rhs));
    if (op == 'in') {
      if (!JsObjectNatives.objectLike(rhs)) {
        throw new JsException('TypeError: Right operand of in must be an object.');
      }
      String key = lhs.asString();
      checkKey(key);
      JsValue target = rhs;
      Integer depth = 0;
      while (target != null) {
        if (++depth > 64) {
          throw new JsException('BudgetError: Prototype depth exceeded.');
        }
        if (ownProperty(target, key) != null) {
          return JsValue.bool(true);
        }
        target = prototypeOf(target);
      }
      return JsValue.bool(false);
    }
    if (op == 'instanceof') {
      if (rhs.kind != 'function' && rhs.kind != 'native') {
        throw new JsException('TypeError: Right operand of instanceof must be callable.');
      }
      if (!JsObjectNatives.objectLike(lhs)) {
        return JsValue.bool(false);
      }
      JsValue proto = getProperty(rhs, 'prototype');
      if (!JsObjectNatives.objectLike(proto)) {
        throw new JsException('TypeError: Constructor prototype must be an object.');
      }
      JsValue parent = prototypeOf(lhs);
      Integer depth = 0;
      while (parent != null) {
        if (++depth > 64) {
          throw new JsException('BudgetError: Prototype depth exceeded.');
        }
        if (parent === proto) {
          return JsValue.bool(true);
        }
        parent = prototypeOf(parent);
      }
      return JsValue.bool(false);
    }
    if (op.equals('===') || op.equals('!==')) {
      Boolean equal = false;
      if (lhs.kind == rhs.kind) {
        if (lhs.kind == 'null' || lhs.kind == 'undefined') {
          equal = true;
        } else if (lhs.kind == 'string') {
          equal = ((String) lhs.scalar).equals((String) rhs.scalar);
        } else if (lhs.kind == 'number') {
          equal =
            !lhs.nanNumber &&
            !rhs.nanNumber &&
            ((Math.abs(lhs.asNumber()) == 0 && Math.abs(rhs.asNumber()) == 0) ||
            lhs.asNumber() == rhs.asNumber());
        } else if (lhs.kind == 'boolean') {
          equal = lhs.scalar == rhs.scalar;
        } else {
          equal = lhs === rhs;
        }
      }
      return JsValue.bool(op.equals('===') ? equal : !equal);
    }
    if (op.equals('+') && (lhs.kind == 'string' || rhs.kind == 'string')) {
      return JsValue.str(lhs.asString() + rhs.asString());
    }
    if (lhs.kind == 'string' && rhs.kind == 'string' && ORDERED_OPERATORS.contains(op)) {
      Integer compared = ((String) lhs.scalar).compareTo((String) rhs.scalar);
      return JsValue.bool(
        op == '<'
          ? compared < 0
          : op == '<=' ? compared <= 0 : op == '>' ? compared > 0 : compared >= 0
      );
    }
    Boolean bitwise =
      op == '&' ||
      op == '|' ||
      op == '^' ||
      op == '<<' ||
      op == '>>' ||
      op == '>>>';
    Double a = bitwise ? bitwiseNumber(lhs) : numeric(lhs);
    Double b = bitwise ? bitwiseNumber(rhs) : numeric(rhs);
    if (ORDERED_OPERATORS.contains(op)) {
      if (lhs.nanNumber || rhs.nanNumber)
        return JsValue.bool(false);
      if (Math.abs(a) == 0)
        a = 0;
      if (Math.abs(b) == 0)
        b = 0;
    }
    if (op == '&') {
      return JsValue.num(Double.valueOf(toInt32(a) & toInt32(b)));
    }
    if (op == '|') {
      return JsValue.num(Double.valueOf(toInt32(a) | toInt32(b)));
    }
    if (op == '^') {
      return JsValue.num(Double.valueOf(toInt32(a) ^ toInt32(b)));
    }
    if (op == '<<' || op == '>>' || op == '>>>') {
      Integer count = toInt32(b) & 31, word = toInt32(a);
      if (op == '<<')
        return JsValue.num(Double.valueOf(word << count));
      if (op == '>>')
        return JsValue.num(Double.valueOf(word >> count));
      Integer unsigned = word >>> count;
      return JsValue.num(
        unsigned < 0 ? Double.valueOf(unsigned) + TWO32 : Double.valueOf(unsigned)
      );
    }
    if (op == '+') {
      return JsValue.num(a + b);
    }
    if (op == '-') {
      return JsValue.num(a - b);
    }
    if (op == '*') {
      return JsValue.num(a * b);
    }
    if (op == '/' || op == '%') {
      if (Math.abs(b) == 0) {
        if (op == '/' && JsValue.trustedInfinityNumbers && Math.abs(a) != 0) {
          Boolean negative = (a < 0) != String.valueOf(b).startsWith('-');
          return JsValue.num(Double.valueOf(negative ? '-Infinity' : 'Infinity'));
        }
        if (JsPromiseNatives.enabled)
          return JsValue.num(Double.valueOf('NaN'));
        throw new JsException('RangeError: Non-finite arithmetic is outside this subset.');
      }
      if (op == '/') {
        return JsValue.num(a / b);
      }
      Double quotient = a / b;
      Double truncated = quotient < 0 ? Math.ceil(quotient) : Math.floor(quotient);
      return JsValue.num(a - truncated * b);
    }
    if (op == '<') {
      return JsValue.bool(a < b);
    }
    if (op == '<=') {
      return JsValue.bool(a <= b);
    }
    if (op == '>') {
      return JsValue.bool(a > b);
    }
    if (op == '>=') {
      return JsValue.bool(a >= b);
    }
    throw new JsException('Unsupported operator ' + op);
  }
  private Double numeric(JsValue value) {
    if (!JsLibraryBuiltins.enabled || value.kind == 'number' || value.kind == 'date')
      return value.asNumber();
    if (value.kind == 'undefined')
      return Double.valueOf('NaN');
    if (value.kind == 'null')
      return 0;
    if (value.kind == 'boolean')
      return (Boolean) value.scalar ? 1 : 0;
    if (value.kind == 'string') {
      try {
        return JsWebNatives.invoke('web.Number', new List<JsValue>{ value }, null, this).asNumber();
      } catch (JsException error) {
        if (error.getMessage().startsWith('BudgetError:'))
          throw error;
        return Double.valueOf('NaN');
      }
    }
    return value.asNumber();
  }
  private Boolean looseEqual(JsValue lhs, JsValue rhs) {
    if (lhs.kind == rhs.kind)
      return binary('===', lhs, rhs).truthy();
    if (JsObjectNatives.objectLike(lhs) && JsObjectNatives.objectLike(rhs))
      return lhs === rhs;
    Boolean ln = lhs.kind == 'null' || lhs.kind == 'undefined',
      rn = rhs.kind == 'null' || rhs.kind == 'undefined';
    if (ln || rn)
      return ln && rn;
    if (lhs.kind == 'boolean')
      return looseEqual(
        JsValue.num((Boolean) lhs.scalar ? Double.valueOf('1') : Double.valueOf('0')),
        rhs
      );
    if (rhs.kind == 'boolean')
      return looseEqual(
        lhs,
        JsValue.num((Boolean) rhs.scalar ? Double.valueOf('1') : Double.valueOf('0'))
      );
    if (lhs.kind == 'number' && rhs.kind == 'string') {
      Double converted = looseStringNumber((String) rhs.scalar);
      return converted != null &&
        ((Math.abs(lhs.asNumber()) == 0 && Math.abs(converted) == 0) ||
        lhs.asNumber() == converted);
    }
    if (lhs.kind == 'string' && rhs.kind == 'number')
      return looseEqual(rhs, lhs);
    if (JsObjectNatives.objectLike(lhs) || JsObjectNatives.objectLike(rhs))
      throw new JsException(
        'TypeError: Object coercion for loose equality is outside this subset.'
      );
    return false;
  }
  private Double looseStringNumber(String value) {
    String text = JsNatives.trimEcma(value);
    if (text == '')
      return 0;
    String prefix = text.length() > 2 ? text.substring(0, 2).toLowerCase() : '';
    Double numberValue;
    if (prefix == '0x' || prefix == '0b' || prefix == '0o') {
      Integer radix = prefix == '0x' ? 16 : prefix == '0b' ? 2 : 8;
      numberValue = 0;
      for (Integer i = 2; i < text.length(); i++) {
        budget.tick();
        Integer digit = '0123456789abcdef'.indexOf(text.substring(i, i + 1).toLowerCase());
        if (digit < 0 || digit >= radix)
          return null;
        numberValue = numberValue * radix + digit;
      }
    } else {
      if (!Pattern.matches('^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?$', text))
        return null;
      try {
        numberValue = Double.valueOf(text);
      } catch (Exception ex) {
        return null;
      }
    }
    String representation = String.valueOf(numberValue);
    return representation.contains('NaN') || representation.contains('Infinity')
      ? null
      : numberValue;
  }
  public JsValue deleteProperty(JsValue target, JsValue keyValue) {
    String key = referenceKey(target, keyValue);
    if (target.props != null && target.props.containsKey(key)) {
      if (!target.configurable(key))
        throw new JsException('TypeError: Cannot delete non-configurable property ' + key);
      target.props.remove(key);
      if (target.getters != null)
        target.getters.remove(key);
      if (target.hiddenKeys != null)
        target.hiddenKeys.remove(key);
      if (target.readOnlyKeys != null)
        target.readOnlyKeys.remove(key);
      if (target.fixedKeys != null)
        target.fixedKeys.remove(key);
      return JsValue.bool(true);
    }
    if (target.kind == 'function' && (key == 'name' || key == 'length' || key == 'prototype'))
      throw new JsException(
        'TypeError: Deleting virtual function metadata is outside this subset.'
      );
    Integer index = arrayIndex(key);
    if (target.kind == 'array') {
      if (key == 'length')
        throw new JsException('TypeError: Cannot delete non-configurable array length.');
      if (index >= 0 && index < target.items.size())
        target.items[index] = null;
    }
    if (JsTypedBuffers.typed(target) && index >= 0 && index < target.wordLength)
      throw new JsException('TypeError: Cannot delete indexed property.');
    if (
      target.kind == 'string' &&
      (key == 'length' || index >= 0 && index < ((String) target.scalar).length()) ||
      target.kind == 'uint8array' && index >= 0 && index < JsBytes.length(target)
    )
      throw new JsException('TypeError: Cannot delete indexed property.');
    return JsValue.bool(true);
  }
}
