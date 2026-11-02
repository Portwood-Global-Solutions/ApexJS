@IsTest
private class JsCompactBytecodeTest {
  private static JsBytecode.Program program(String source) {
    return JsBytecodeCompiler.compile(source, new JsBudget(100000));
  }
  @IsTest
  static void sharesOnlyCodeAcrossFreshRuntimes() {
    JsBytecode.Program code = program(
      'if(input)Object.prototype.changed=7;return typeof ({}).changed;'
    );
    JsBytecode.trustedCompactCode = true;
    try {
      JsRuntime first = new JsRuntime(new JsBudget(100000));
      Assert.areEqual('number', new JsBytecode(code, first).run(JsValue.bool(true)).asString());
      Assert.isNull(code.functions[0].code);
      Assert.isNotNull(code.functions[0].compactCode);
      JsRuntime second = new JsRuntime(new JsBudget(100000));
      Assert.areEqual(
        'undefined',
        new JsBytecode(code, second).run(JsValue.bool(false)).asString()
      );
    } finally {
      JsBytecode.trustedCompactCode = false;
    }
  }
  @IsTest
  static void retainsWideWordsAndRejectsExternalCaches() {
    JsBytecode.Program code = program('return 7;');
    code.functions[0].code[2] = 65535;
    code.functions[0].code[3] = Integer.valueOf('-2147483648');
    JsBytecode.trustedCompactCode = true;
    try {
      JsRuntime runtime = new JsRuntime(new JsBudget(100000));
      Assert.areEqual(
        Double.valueOf('7'),
        new JsBytecode(code, runtime).run(new JsValue('null')).asNumber()
      );
      Assert.isNotNull(code.functions[0].code);
    } finally {
      JsBytecode.trustedCompactCode = false;
    }
    code = program('return 7;');
    code.functions[0].compactCode = 'unvalidated';
    JsBytecodeTestSupport.Request request = new JsBytecodeTestSupport.Request();
    request.programJson = JSON.serialize(code);
    JsAstTestSupport.Response result = JsBytecodeTestSupport.runCompact(
      new List<JsBytecodeTestSupport.Request>{ request }
    )[0];
    Assert.isFalse(result.success);
    Assert.areEqual(0, result.steps);
    Assert.isTrue(result.error.contains('Runtime code cache'));
  }
  @IsTest
  static void growthSamplingKeepsCpuAndForcedHeapStops() {
    JsBudget budget = new JsBudget(10000);
    budget.configureHeapSampling(4096, 64);
    Integer before = budget.heapChecks;
    for (Integer i = 0; i < 256; i++)
      budget.tick();
    Assert.areEqual(before, budget.heapChecks);
    budget.allocate(64);
    Assert.areEqual(before + 1, budget.heapChecks);
    budget.cpuReserveMs = budget.cpuLimitMs + 1;
    Boolean rejected = false;
    try {
      budget.poll();
    } catch (JsException error) {
      rejected = error.getMessage().contains('CPU reserve');
    }
    Assert.isTrue(rejected);
    budget.cpuReserveMs = 750;
    budget.heapReserveBytes = budget.heapLimitBytes;
    rejected = false;
    try {
      budget.guard();
    } catch (JsException error) {
      rejected = error.getMessage().contains('heap reserve');
    }
    Assert.isTrue(rejected);
  }
  @IsTest
  static void numericFastPathRetainsFiniteBoundary() {
    for (String text : new List<String>{ '0', '-1', '4294967295', '9007199254740992', '1e100' })
      Assert.areEqual(Double.valueOf(text), JsValue.num(Double.valueOf(text)).asNumber());
    for (String text : new List<String>{ 'NaN', 'Infinity', '-Infinity' }) {
      Boolean rejected = false;
      try {
        JsValue.num(Double.valueOf(text));
      } catch (JsException error) {
        rejected = error.getMessage().contains('Non-finite');
      }
      Assert.isTrue(rejected, text);
    }
  }
  @IsTest
  static void pagedViewsShareAndCopiesRemainIndependent() {
    JsBudget budget = new JsBudget(100000);
    JsRuntime runtime = new JsRuntime(budget);
    JsTypedBuffers.trustedPagedStorage = true;
    try {
      JsValue buffer = JsTypedBuffers.construct(
        'Uint16Array',
        new List<JsValue>{ JsValue.num(260) },
        runtime
      );
      JsTypedBuffers.write(buffer, '127', JsValue.num(55296));
      JsTypedBuffers.write(buffer, '128', JsValue.num(56320));
      JsValue view = JsTypedBuffers.invoke(
        'typed.subarray',
        new List<JsValue>{ JsValue.num(120), JsValue.num(140) },
        buffer,
        runtime
      );
      JsValue copy = JsTypedBuffers.invoke('typed.slice', new List<JsValue>(), view, runtime);
      JsTypedBuffers.write(view, '7', JsValue.num(65535));
      Assert.areEqual(Double.valueOf('65535'), JsTypedBuffers.element(buffer, 127));
      Assert.areEqual(Double.valueOf('55296'), JsTypedBuffers.element(copy, 7));
      Assert.areEqual(Double.valueOf('56320'), JsTypedBuffers.element(view, 8));
      Assert.isNull(buffer.words);
      Assert.isNotNull(buffer.wordPages);
    } finally {
      JsTypedBuffers.trustedPagedStorage = false;
    }
  }
  @IsTest
  static void compactGetterKeepsReceiverAndFunctionMetadata() {
    JsBytecode.Program code = program(
      'let calls=0;function readX(unused){calls++;return this.value;}const p={};Object.defineProperty(p,"x",{get:readX});const o=Object.create(p);o.value=7;const d=Object.getOwnPropertyDescriptor(p,"x"),before=calls;return [before,o.x,calls,d.get.name,d.get.length,Object.hasOwn(d,"value")];'
    );
    JsBytecodeTestSupport.Request request = new JsBytecodeTestSupport.Request();
    request.programJson = JSON.serialize(code);
    JsAstTestSupport.Response result = JsBytecodeTestSupport.runPaged(
      new List<JsBytecodeTestSupport.Request>{ request }
    )[0];
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected getter execution' : result.error
    );
    Assert.areEqual('[0,7,1,"readX",1,false]', result.resultJson);
  }
  @IsTest
  static void trustedInfinitySentinelDoesNotAdmitNan() {
    JsRuntime runtime = new JsRuntime(new JsBudget(10000));
    JsValue.trustedInfinityNumbers = true;
    try {
      JsValue value = runtime.binary('/', JsValue.num(1), JsValue.num(0));
      Assert.areEqual('Infinity', value.asString());
      Assert.areEqual('null', JsCodec.stringify(value, runtime.budget, runtime));
      Boolean rejected = false;
      try {
        JsValue.num(Double.valueOf('NaN'));
      } catch (JsException error) {
        rejected = true;
      }
      Assert.isTrue(rejected);
    } finally {
      JsValue.trustedInfinityNumbers = false;
    }
    Boolean rejected = false;
    try {
      JsValue.num(Double.valueOf('Infinity'));
    } catch (JsException error) {
      rejected = true;
    }
    Assert.isTrue(rejected);
  }
}
