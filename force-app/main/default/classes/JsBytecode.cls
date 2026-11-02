/** Experimental offline-compiled instruction VM. Uses the existing JS values and capability table. */
public with sharing class JsBytecode {
  /** Trusted Apex trusted admission overrides, never read from program JSON or Flow. */
  public static Integer trustedMaxProgramCharacters;
  public static Integer trustedMaxInstructions;
  public static Map<Integer, String> trustedIntrinsics;
  public static Boolean trustedCompactCode = false;
  public static Boolean trustedGrowthSampling = false;
  public static Map<String, Integer> lastStorageDiagnostics;
  public class Program {
    public Integer version;
    public String sourceSha256;
    public List<String> texts;
    public List<ConstantSpec> constants;
    public List<ScopeSpec> scopes;
    public List<FunctionSpec> functions;
  }
  public class ConstantSpec {
    public String kind;
    public String value;
  }
  public class ScopeSpec {
    public List<String> names;
    public List<String> kinds;
    public Integer allocationUnits;
  }
  public class FunctionSpec {
    public String name;
    public Integer rootScope;
    public Integer selfScope;
    public List<Integer> parameterSlots;
    public Integer argumentsSlot;
    public Boolean needsArguments;
    public List<Integer> code;
    public String compactCode; // Validated runtime cache only; never admitted from artifact JSON.
  }
  public class Environment {
    public Environment parent;
    public ScopeSpec layout;
    public Integer layoutIndex;
    public List<JsValue> slots;
  }
  private class Pending {
    public String kind;
    public JsValue value;
    public Environment targetEnv;
    public Integer targetPc;
    public Integer targetDepth;
  }
  private class Handler {
    public Environment env;
    public Integer height;
    public Integer catchPc;
    public Integer finallyPc;
    public Integer endPc;
    public String state = 'try';
    public Pending pending;
  }
  private class Unwind {
    public Environment env;
    public Integer pc;
    public Boolean complete = false;
    public JsValue value;
  }
  private static final Set<String> BINARY = new Set<String>{
    '+',
    '-',
    '*',
    '/',
    '%',
    '===',
    '!==',
    '==',
    '!=',
    '<',
    '<=',
    '>',
    '>=',
    '&',
    '|',
    '^',
    '<<',
    '>>',
    '>>>',
    'in',
    'instanceof'
  };
  private static final Set<String> UNARY = new Set<String>{ '!', '+', '-', '~', 'typeof', 'void' };
  private static final Set<String> KINDS = new Set<String>{ 'var', 'param', 'let', 'const' };
  private Program program;
  private JsRuntime runtime;
  private JsScope globals;
  private List<JsValue> constants = new List<JsValue>();
  private List<JsNode> metadata = new List<JsNode>();
  public Integer environmentSlotUnits = 0;
  public Map<String, Integer> firstObservedException;
  public Map<String, Integer> firstBudgetException;
  private void observeException(
    Integer functionIndex,
    Integer pc,
    List<Integer> code,
    String compact
  ) {
    if (firstObservedException == null) {
      Integer instruction = pc / 4 - 1;
      firstObservedException = new Map<String, Integer>{
        'functionIndex' => functionIndex,
        'instruction' => instruction,
        'opcode' => instruction >= 0
          ? (compact == null ? code[instruction * 4] : compact.charAt(instruction * 4))
          : -1
      };
    }
  }

  public JsBytecode(Program program, JsRuntime runtime) {
    this.program = program;
    this.runtime = runtime;
    runtime.bytecodeVm = this;
    if (trustedGrowthSampling)
      runtime.budget.configureHeapSampling(4096, 64);
    prepareCodeStorage();
    globals = new JsScope(null);
    JsNatives.install(globals, runtime);
    for (ConstantSpec c : program.constants) {
      constants.add(
        c.kind == 'string'
          ? JsValue.str(c.value)
          : c.kind == 'number'
              ? JsValue.num(Double.valueOf(c.value))
              : c.kind == 'boolean' ? JsValue.bool(c.value == 'true') : new JsValue(c.kind)
      );
    }
    if (!trustedCompactCode)
      for (FunctionSpec f : program.functions) {
        JsToken token = new JsToken('identifier', f.name, 0, 0);
        JsNode node = new JsNode('function', token);
        node.text = f.name;
        node.names = new List<String>();
        for (Integer slot : f.parameterSlots)
          node.names.add(program.scopes[f.rootScope].names[slot]);
        metadata.add(node);
      }
  }
  public Integer functionArity(Integer index) {
    return program.functions[index].parameterSlots.size();
  }
  public String functionName(Integer index) {
    return program.functions[index].name;
  }
  private void prepareCodeStorage() {
    Integer started = Limits.getCpuTime(),
      compactFunctions = 0,
      compactWords = 0,
      retainedWords = 0,
      inspected = 0,
      nextSample = 8192;
    for (FunctionSpec f : program.functions) {
      if (trustedCompactCode && f.compactCode == null) {
        Boolean eligible = true;
        List<Integer> negatives = new List<Integer>();
        for (Integer i = 0; i < f.code.size(); i++) {
          Integer word = f.code[i];
          if (word < -1 || word >= 65535) {
            eligible = false;
            break;
          }
          if (word == -1)
            negatives.add(i);
          if (++inspected >= nextSample) {
            nextSample = inspected + 8192;
            runtime.budget.guard();
          }
        }
        if (eligible) {
          // One UTF-16 unit per validated word, with U+FFFF representing -1.
          // Unrepresentable words retain the original list representation.
          for (Integer at : negatives)
            f.code[at] = 65535;
          f.compactCode = String.fromCharArray(f.code);
          f.code = null;
        }
      }
      if (f.compactCode == null)
        retainedWords += f.code.size();
      else {
        compactFunctions++;
        compactWords += f.compactCode.length();
      }
    }
    runtime.budget.guard();
    lastStorageDiagnostics = new Map<String, Integer>{
      'compactFunctions' => compactFunctions,
      'compactWords' => compactWords,
      'retainedWords' => retainedWords,
      'prepareCpuMs' => Limits.getCpuTime() - started
    };
  }
  public static Program load(String json, JsBudget budget) {
    Integer characterLimit = trustedMaxProgramCharacters == null
      ? 1048576
      : trustedMaxProgramCharacters;
    Integer instructionLimit = trustedMaxInstructions == null ? 50000 : trustedMaxInstructions;
    if (
      characterLimit < 1 ||
      characterLimit > 8388608 ||
      instructionLimit < 1 ||
      instructionLimit > 1000000
    )
      invalid('Invalid trusted admission limits.');
    if (json == null || json.length() > characterLimit)
      invalid('Program JSON exceeds ' + characterLimit + ' characters.');
    budget.guard();
    Program p;
    try {
      p = (Program) System.JSON.deserializeStrict(json, Program.class);
    } catch (Exception ex) {
      invalid('Invalid program JSON.');
    }
    budget.guard();
    if (
      p == null ||
      p.version != 1 ||
      p.sourceSha256 == null ||
      p.sourceSha256.length() != 64 ||
      p.texts == null ||
      p.constants == null ||
      p.scopes == null ||
      p.functions == null
    )
      invalid('Invalid version or program tables.');
    if (
      p.texts.size() > 8192 ||
      p.constants.size() > 8192 ||
      p.scopes.isEmpty() ||
      p.scopes.size() > 4096 ||
      p.functions.isEmpty() ||
      p.functions.size() > 2048
    )
      invalid('Program table limit exceeded.');
    for (String t : p.texts) {
      budget.poll();
      if (t == null || t.length() > 65536)
        invalid('Invalid text.');
    }
    for (ConstantSpec c : p.constants) {
      budget.poll();
      if (
        c == null ||
        c.value == null ||
        c.value.length() > 65536 ||
        !new Set<String>{ 'string', 'number', 'boolean', 'null', 'undefined' }.contains(c.kind)
      )
        invalid('Invalid constant.');
      if (c.kind == 'number') {
        try {
          JsValue.num(Double.valueOf(c.value));
        } catch (Exception ex) {
          invalid('Invalid number constant.');
        }
      }
      if (c.kind == 'boolean' && c.value != 'true' && c.value != 'false')
        invalid('Invalid boolean constant.');
    }
    for (ScopeSpec s : p.scopes) {
      budget.poll();
      if (
        s == null ||
        s.names == null ||
        s.kinds == null ||
        s.names.size() != s.kinds.size() ||
        s.names.size() > 4096 ||
        s.allocationUnits == null ||
        s.allocationUnits < 0 ||
        s.allocationUnits > 1
      )
        invalid('Invalid scope layout.');
      Set<String> seen = new Set<String>();
      for (Integer i = 0; i < s.names.size(); i++) {
        if (s.names[i] == null || seen.contains(s.names[i]) || !KINDS.contains(s.kinds[i]))
          invalid('Invalid scope binding.');
        seen.add(s.names[i]);
      }
    }
    Integer total = 0;
    for (FunctionSpec f : p.functions) {
      budget.poll();
      if (
        f == null ||
        f.name == null ||
        f.parameterSlots == null ||
        f.parameterSlots.size() > 100 ||
        f.needsArguments == null ||
        f.code == null ||
        f.code.isEmpty() ||
        Math.mod(f.code.size(), 4) != 0
      )
        invalid('Invalid function.');
      if (f.compactCode != null)
        invalid('Runtime code cache is not admitted from artifact JSON.');
      range(f.rootScope, p.scopes.size());
      if (f.selfScope == null || f.selfScope < -1)
        invalid('Invalid self scope.');
      if (f.selfScope >= 0) {
        range(f.selfScope, p.scopes.size());
        ScopeSpec self = p.scopes[f.selfScope];
        if (self.names.size() != 1 || self.kinds[0] != 'const')
          invalid('Invalid self binding.');
      }
      ScopeSpec root = p.scopes[f.rootScope];
      if (root.names.isEmpty() || root.names[0] != 'this' || root.kinds[0] != 'const')
        invalid('Invalid function receiver.');
      range(f.argumentsSlot, root.names.size());
      if (root.names[f.argumentsSlot] != 'arguments' || root.kinds[f.argumentsSlot] != 'var')
        invalid('Invalid arguments binding.');
      Set<Integer> parameters = new Set<Integer>();
      for (Integer slot : f.parameterSlots) {
        range(slot, root.names.size());
        if (root.kinds[slot] != 'param' || parameters.contains(slot))
          invalid('Invalid parameter slot.');
        parameters.add(slot);
      }
      total += f.code.size() / 4;
      if (total > instructionLimit)
        invalid('Instruction table limit exceeded.');
      for (Integer pc = 0; pc < f.code.size(); pc += 4) {
        if (Math.mod(pc, 128) == 0)
          budget.poll();
        Integer op = f.code[pc], a = f.code[pc + 1], b = f.code[pc + 2], c = f.code[pc + 3];
        if (op == null || op < 0 || op > 48 || a == null || b == null || c == null)
          invalid('Unknown instruction.');
        if (op == 0)
          range(a, p.constants.size());
        if (op == 1 || op == 2 || op == 26) {
          if (a < 0 || a > 128 || b < 0 || b > 4095)
            invalid('Invalid local address.');
        }
        if (op == 3 && (a < 0 || a > 4095))
          invalid('Invalid initializer slot.');
        if (op == 4 || op == 8 || op == 10 || op == 11 || op == 12 || op == 27) {
          range(a, p.texts.size());
          if (op == 11 && !BINARY.contains(p.texts[a]) || op == 12 && !UNARY.contains(p.texts[a]))
            invalid('Invalid operator.');
        }
        if (
          (op == 13 || op == 14) && (a < 0 || a > 5000) ||
          ((op == 22 || op == 23) && (a < 0 || a > 100))
        )
          invalid('Invalid collection or argument count.');
        if (op == 15)
          range(a, p.functions.size());
        if (op == 16)
          range(a, p.scopes.size());
        if (op == 19 || op == 20 || op == 21)
          range(a, f.code.size() / 4);
        if (op == 26 && (c < 0 || c > 3) || op == 29 && (a < 0 || a > 3))
          invalid('Invalid update mode.');
        if (op == 33 || op == 35 || op == 40) {
          if (a < 0 || a > 128 || b < 0 || b > 4095)
            invalid('Invalid fused local address.');
        }
        if (op == 33)
          range(c, p.texts.size());
        if (op == 34)
          range(a, p.texts.size());
        if (op == 36 || op == 37)
          range(a, p.constants.size());
        if (op == 37) {
          range(b, p.texts.size());
          if (!BINARY.contains(p.texts[b]))
            invalid('Invalid fused operator.');
        }
        if (op == 38 || op == 39) {
          if (a < 0 || a > 4095)
            invalid('Invalid fused slot.');
          range(c, p.texts.size());
          if (!BINARY.contains(p.texts[c]))
            invalid('Invalid fused operator.');
        }
        if (op == 38)
          range(b, p.constants.size());
        if (op == 39 && (b < 0 || b > 4095))
          invalid('Invalid fused slot.');
        if (op == 40 && (c < 0 || c > 3))
          invalid('Invalid fused update mode.');
        if (op == 43) {
          if (a < -1 || b < -1 || a < 0 && b < 0)
            invalid('Invalid exception handler.');
          if (a >= 0)
            range(a, f.code.size() / 4);
          if (b >= 0)
            range(b, f.code.size() / 4);
          range(c, f.code.size() / 4);
        }
        if (op == 46) {
          range(a, f.code.size() / 4);
          if (b < 0 || b > 64 || c < 0 || c > 128)
            invalid('Invalid abrupt target.');
        }
        if (op == 48) {
          range(b, p.texts.size());
          String mask = p.texts[b];
          if (a < 0 || a > 5000 || mask.length() != a || c < 0 || c > a)
            invalid('Invalid sparse array layout.');
          Integer count = 0;
          for (Integer i = 0; i < mask.length(); i++) {
            String bit = mask.substring(i, i + 1);
            if (bit == '1')
              count++;
            else if (bit != '0')
              invalid('Invalid sparse array mask.');
          }
          if (count != c)
            invalid('Invalid sparse array value count.');
        }
      }
    }
    budget.guard();
    return p;
  }
  private static void invalid(String message) {
    throw new JsException('BytecodeError: ' + message);
  }
  private static void range(Integer i, Integer size) {
    if (i == null || i < 0 || i >= size)
      invalid('Table index out of range.');
  }
  private Environment environment(Integer index, Environment parent) {
    ScopeSpec s = program.scopes[index];
    environmentSlotUnits += s.names.size() + 1;
    // Match AST accounting: JS values/for-of bindings are charged, internal scope slots are sampled by heap guards.
    runtime.budget.allocate(s.allocationUnits);
    Environment env = new Environment();
    env.parent = parent;
    env.layout = s;
    env.layoutIndex = index;
    env.slots = new List<JsValue>();
    for (String kind : s.kinds)
      env.slots.add(kind == 'var' || kind == 'param' ? new JsValue('undefined') : null);
    return env;
  }
  private Environment ancestor(Environment env, Integer depth) {
    for (Integer i = 0; i < depth; i++) {
      if (env == null)
        invalid('Invalid environment depth.');
      env = env.parent;
    }
    if (env == null)
      invalid('Invalid environment depth.');
    return env;
  }
  private JsValue read(Environment env, Integer slot) {
    range(slot, env.slots.size());
    JsValue value = env.slots[slot];
    if (value == null)
      throw new JsException(
        'ReferenceError: Cannot access ' + env.layout.names[slot] + ' before initialization.'
      );
    return value;
  }
  private void write(Environment env, Integer slot, JsValue value) {
    read(env, slot);
    if (env.layout.kinds[slot] == 'const')
      throw new JsException('TypeError: Assignment to constant ' + env.layout.names[slot]);
    env.slots[slot] = value;
  }
  private JsValue pop(List<JsValue> stack) {
    if (stack.isEmpty())
      invalid('Operand stack underflow.');
    return stack.remove(stack.size() - 1);
  }
  private JsValue peek(List<JsValue> stack) {
    if (stack.isEmpty())
      invalid('Operand stack underflow.');
    return stack[stack.size() - 1];
  }
  private JsValue closure(Integer index, Environment env) {
    if (trustedIntrinsics != null && trustedIntrinsics.containsKey(index))
      return JsValue.nativeFunction(trustedIntrinsics.get(index));
    runtime.budget.allocate(1);
    JsValue value = new JsValue('function');
    value.functionNode = metadata.isEmpty() ? null : metadata[index];
    value.bytecodeIndex = index;
    FunctionSpec f = program.functions[index];
    if (f.selfScope >= 0) {
      env = environment(f.selfScope, env);
      env.slots[0] = value;
    }
    value.bytecodeClosure = env;
    return value;
  }
  private Unwind resume(Pending pending, List<Handler> handlers, List<JsValue> stack) {
    Integer depth = pending.kind == 'jump' ? pending.targetDepth : 0;
    if (depth == null || depth < 0 || depth > handlers.size())
      invalid('Invalid handler depth.');
    while (handlers.size() > depth) {
      Handler h = handlers[handlers.size() - 1];
      if (stack.size() < h.height)
        invalid('Invalid handler stack state.');
      while (stack.size() > h.height)
        stack.remove(stack.size() - 1);
      Unwind target = new Unwind();
      target.env = h.env;
      if (pending.kind == 'throw' && h.state == 'try' && h.catchPc >= 0) {
        h.state = 'catch';
        stack.add(pending.value);
        target.pc = h.catchPc;
        return target;
      }
      if (h.state != 'finally' && h.finallyPc >= 0) {
        h.state = 'finally';
        h.pending = pending;
        target.pc = h.finallyPc;
        return target;
      }
      handlers.remove(handlers.size() - 1);
    }
    Unwind result = new Unwind();
    if (pending.kind == 'return') {
      result.complete = true;
      result.value = pending.value;
      return result;
    }
    if (pending.kind == 'throw')
      throw JsThrownException.carrying(pending.value);
    result.env = pending.targetEnv;
    result.pc = pending.targetPc;
    return result;
  }
  private Pending returned(JsValue value) {
    Pending p = new Pending();
    p.kind = 'return';
    p.value = value;
    return p;
  }
  private Pending thrown(JsValue value) {
    Pending p = new Pending();
    p.kind = 'throw';
    p.value = value;
    return p;
  }
  private Pending jumped(Environment env, Integer pc, Integer depth) {
    Pending p = new Pending();
    p.kind = 'jump';
    p.targetEnv = env;
    p.targetPc = pc;
    p.targetDepth = depth;
    return p;
  }
  public JsValue run(JsValue input) {
    return runtime.invoke(closure(0, null), new List<JsValue>{ input }, null);
  }
  public JsValue invoke(JsValue callable, List<JsValue> args, JsValue receiver) {
    runtime.budget.allocate(1);
    FunctionSpec f = program.functions[callable.bytecodeIndex];
    Environment env = environment(f.rootScope, callable.bytecodeClosure);
    env.slots[0] = receiver == null ? new JsValue('undefined') : receiver;
    for (Integer i = 0; i < f.parameterSlots.size(); i++)
      env.slots[f.parameterSlots[i]] = i < args.size() ? args[i] : new JsValue('undefined');
    if (f.needsArguments) {
      JsValue arguments = new JsValue('object');
      runtime.budget.allocate(args.size() + 1);
      for (Integer i = 0; i < args.size(); i++)
        arguments.props.put(String.valueOf(i), args[i]);
      arguments.props.put('length', JsValue.num(Double.valueOf(args.size())));
      arguments.attributes('length', false, true, true);
      env.slots[f.argumentsSlot] = arguments;
    }
    List<JsValue> stack = new List<JsValue>();
    List<Handler> handlers = new List<Handler>();
    List<Integer> code = f.code;
    String compact = f.compactCode;
    Integer codeLength = compact == null ? code.size() : compact.length(), pc = 0;
    while (true) {
      try {
        while (pc < codeLength) {
          Integer op, a, b, c;
          if (compact == null) {
            op = code[pc];
            a = code[pc + 1];
            b = code[pc + 2];
            c = code[pc + 3];
          } else {
            op = compact.charAt(pc);
            a = compact.charAt(pc + 1);
            b = compact.charAt(pc + 2);
            c = compact.charAt(pc + 3);
            if (a == 65535)
              a = -1;
            if (b == 65535)
              b = -1;
            if (c == 65535)
              c = -1;
          }
          pc += 4;
          runtime.budget.tick(op == 38 || op == 39 ? 3 : op >= 33 && op <= 40 ? 2 : 1);
          if (stack.size() > 1024)
            throw new JsException('BudgetError: Bytecode operand stack exceeded.');
          if (op >= 33 && op <= 40) {
            if (op == 33)
              stack.add(runtime.getProperty(read(ancestor(env, a), b), program.texts[c]));
            else if (op == 34)
              stack.add(runtime.getProperty(peek(stack), program.texts[a]));
            else if (op == 35)
              write(ancestor(env, a), b, pop(stack));
            else if (op == 36) {
              if (handlers.isEmpty())
                return constants[a];
              Unwind next = resume(returned(constants[a]), handlers, stack);
              if (next.complete)
                return next.value;
              env = next.env;
              pc = next.pc;
            } else if (op == 37)
              stack.add(runtime.binary(program.texts[b], pop(stack), constants[a]));
            else if (op == 38)
              stack.add(runtime.binary(program.texts[c], read(env, a), constants[b]));
            else if (op == 39) {
              JsValue lhs = read(env, a);
              stack.add(runtime.binary(program.texts[c], lhs, read(env, b)));
            } else if (op == 40) {
              Environment owner = ancestor(env, a);
              JsValue old = read(owner, b);
              write(
                owner,
                b,
                JsValue.num(old.asNumber() + (c >= 2 ? Double.valueOf('1') : Double.valueOf('-1')))
              );
            }
            continue;
          }
          if (op == 0)
            stack.add(constants[a]);
          else if (op == 1)
            stack.add(read(ancestor(env, a), b));
          else if (op == 2)
            write(ancestor(env, a), b, peek(stack));
          else if (op == 3) {
            range(a, env.slots.size());
            if (env.slots[a] != null)
              invalid('Binding is already initialized.');
            env.slots[a] = pop(stack);
          } else if (op == 4)
            stack.add(globals.read(program.texts[a]));
          else if (op == 5)
            pop(stack);
          else if (op == 6)
            stack.add(peek(stack));
          else if (op == 7) {
            String key = pop(stack).asString();
            stack.add(runtime.getProperty(pop(stack), key));
          } else if (op == 8)
            stack.add(runtime.getProperty(pop(stack), program.texts[a]));
          else if (op == 9 || op == 10) {
            JsValue value = pop(stack);
            String key = op == 9 ? pop(stack).asString() : program.texts[a];
            runtime.writeProperty(pop(stack), key, value);
            stack.add(value);
          } else if (op == 11) {
            JsValue right = pop(stack);
            stack.add(runtime.binary(program.texts[a], pop(stack), right));
          } else if (op == 12)
            stack.add(runtime.unary(program.texts[a], pop(stack)));
          else if (op == 13) {
            runtime.budget.allocate(a + 1);
            JsValue arrayValue = new JsValue('array');
            List<JsValue> reversed = new List<JsValue>();
            for (Integer i = 0; i < a; i++)
              reversed.add(pop(stack));
            for (Integer i = a - 1; i >= 0; i--)
              arrayValue.items.add(reversed[i]);
            stack.add(arrayValue);
          } else if (op == 14) {
            runtime.budget.allocate(a + 1);
            JsValue objectValue = new JsValue('object');
            List<JsValue> values = new List<JsValue>();
            List<String> keys = new List<String>();
            for (Integer i = 0; i < a; i++) {
              values.add(pop(stack));
              String key = pop(stack).asString();
              if (key == '__proto__')
                throw new JsException('TypeError: Prototype operations are outside this subset.');
              keys.add(key);
            }
            for (Integer i = a - 1; i >= 0; i--)
              objectValue.props.put(keys[i], values[i]);
            stack.add(objectValue);
          } else if (op == 15)
            stack.add(closure(a, env));
          else if (op == 16)
            env = environment(a, env);
          else if (op == 17) {
            if (env == null || env.parent == null)
              invalid('Cannot leave function environment.');
            env = env.parent;
          } else if (op == 18) {
            Environment next = environment(env.layoutIndex, env.parent);
            next.slots = new List<JsValue>(env.slots);
            env = next;
          } else if (op == 19)
            pc = a * 4;
          else if (op == 20 || op == 21) {
            Boolean truth = pop(stack).truthy();
            if (op == 20 ? !truth : truth)
              pc = a * 4;
          } else if (op == 22 || op == 23) {
            List<JsValue> reversed = new List<JsValue>(), callArgs = new List<JsValue>();
            for (Integer i = 0; i < a; i++)
              reversed.add(pop(stack));
            for (Integer i = a - 1; i >= 0; i--)
              callArgs.add(reversed[i]);
            JsValue target = pop(stack);
            JsValue result;
            if (op == 23)
              result = runtime.construct(target, callArgs);
            else
              result = runtime.invoke(target, callArgs, pop(stack));
            stack.add(result);
          } else if (op == 24) {
            if (handlers.isEmpty())
              return pop(stack);
            Unwind next = resume(returned(pop(stack)), handlers, stack);
            if (next.complete)
              return next.value;
            env = next.env;
            pc = next.pc;
          } else if (op == 25) {
            if (stack.size() < 2)
              invalid('Operand stack underflow.');
            JsValue first = stack[stack.size() - 2], second = peek(stack);
            stack.add(first);
            stack.add(second);
          } else if (op == 26) {
            Environment owner = ancestor(env, a);
            JsValue old = read(owner, b),
              value = JsValue.num(
                old.asNumber() + (c >= 2 ? Double.valueOf('1') : Double.valueOf('-1'))
              );
            write(owner, b, value);
            stack.add(Math.mod(c, 2) == 1 ? value : old);
          } else if (op == 27) {
            String name = program.texts[a];
            stack.add(
              globals.has(name)
                ? runtime.unary('typeof', globals.read(name))
                : JsValue.str('undefined')
            );
          } else if (op == 28) {
            JsValue last = pop(stack), prior = pop(stack);
            stack.add(last);
            stack.add(prior);
          } else if (op == 29) {
            String key = pop(stack).asString();
            JsValue target = pop(stack),
              old = runtime.getProperty(target, key),
              value = JsValue.num(
                old.asNumber() + (a >= 2 ? Double.valueOf('1') : Double.valueOf('-1'))
              );
            runtime.writeProperty(target, key, value);
            stack.add(Math.mod(a, 2) == 1 ? value : old);
          } else if (op == 30)
            throw JsThrownException.carrying(pop(stack));
          else if (op == 31 && peek(stack).kind != 'array')
            throw new JsException('TypeError: for...of currently requires an array.');
          else if (op == 32) {
            JsValue key = pop(stack), target = pop(stack);
            String normalized = runtime.referenceKey(target, key);
            stack.add(target);
            stack.add(JsValue.str(normalized));
          } else if (op == 41)
            stack.add(JsObjectNatives.enumerationKeys(pop(stack), runtime));
          else if (op == 42) {
            JsValue key = pop(stack);
            stack.add(runtime.deleteProperty(pop(stack), key));
          } else if (op == 43) {
            if (handlers.size() >= 64)
              throw new JsException('BudgetError: Exception handler depth exceeded.');
            Handler h = new Handler();
            h.env = env;
            h.height = stack.size();
            h.catchPc = a < 0 ? -1 : a * 4;
            h.finallyPc = b < 0 ? -1 : b * 4;
            h.endPc = c * 4;
            handlers.add(h);
          } else if (op == 44) {
            if (handlers.isEmpty() || handlers[handlers.size() - 1].state == 'finally')
              invalid('Invalid try completion.');
            Handler h = handlers[handlers.size() - 1];
            Unwind next = resume(jumped(h.env, h.endPc, handlers.size() - 1), handlers, stack);
            env = next.env;
            pc = next.pc;
          } else if (op == 45) {
            if (handlers.isEmpty())
              invalid('Finally has no handler.');
            Handler h = handlers.remove(handlers.size() - 1);
            if (h.state != 'finally' || h.pending == null)
              invalid('Invalid finally completion.');
            Unwind next = resume(h.pending, handlers, stack);
            if (next.complete)
              return next.value;
            env = next.env;
            pc = next.pc;
          } else if (op == 46) {
            Unwind next = resume(jumped(ancestor(env, c), a * 4, b), handlers, stack);
            env = next.env;
            pc = next.pc;
          } else if (op == 47) {
            String key = pop(stack).asString();
            stack.add(JsValue.bool(JsObjectNatives.enumerationHas(pop(stack), key, runtime)));
          } else if (op == 48) {
            if (a > 5000)
              throw new JsException('BudgetError: Array size exceeded.');
            runtime.budget.allocate(a + 1);
            JsValue value = new JsValue('array');
            String mask = program.texts[b];
            List<JsValue> values = new List<JsValue>();
            for (Integer i = 0; i < c; i++)
              values.add(pop(stack));
            Integer next = c - 1;
            for (Integer i = 0; i < a; i++) {
              runtime.budget.tick();
              value.items.add(mask.substring(i, i + 1) == '1' ? values[next--] : null);
            }
            stack.add(value);
          }
        }
        invalid('Function ended without return.');
      } catch (JsThrownException error) {
        observeException(callable.bytecodeIndex, pc, code, compact);
        Unwind next = resume(thrown(error.value), handlers, stack);
        env = next.env;
        pc = next.pc;
      } catch (JsException error) {
        if (error.getMessage().startsWith('BudgetError:') && firstBudgetException == null) {
          Integer at = pc / 4 - 1;
          firstBudgetException = new Map<String, Integer>{
            'functionIndex' => callable.bytecodeIndex,
            'instruction' => at,
            'opcode' => at >= 0 ? (compact == null ? code[at * 4] : compact.charAt(at * 4)) : -1
          };
        }
        observeException(callable.bytecodeIndex, pc, code, compact);
        if (
          error.getMessage().startsWith('BudgetError:') ||
          error.getMessage().startsWith('BytecodeError:')
        )
          throw error;
        Unwind next = resume(thrown(runtime.languageError(error)), handlers, stack);
        env = next.env;
        pc = next.pc;
      }
    }
    return null;
  }
}
