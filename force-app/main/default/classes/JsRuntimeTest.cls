@IsTest
private class JsRuntimeTest {
  private static JsAstTestSupport.Response run(String source, String inputJson) {
    JsAstTestSupport.Request request = new JsAstTestSupport.Request();
    request.source = source;
    request.inputJson = inputJson;
    return JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ request })[0];
  }
  @IsTest
  static void computesQuoteWithCallbacks() {
    JsAstTestSupport.Response result = run(
      'const lines = input.lines.filter(function(x) { return x.active; }); ' +
      'return lines.map(function(x) { return x.qty * x.price; }).reduce(function(a,b) { return a + b; },0);',
      '{"lines":[{"active":true,"qty":3,"price":12.5},{"active":false,"qty":10,"price":100}]}'
    );
    Assert.isTrue(result.success, result.error == null ? 'Expected success.' : result.error);
    Assert.areEqual(37.5, Decimal.valueOf(result.resultJson));
    Assert.areEqual('number', result.resultType);
  }
  @IsTest
  static void preservesClosuresAndCase() {
    JsAstTestSupport.Response result = run(
      'function outer(n) { return function(x) { return n + x; }; } const Foo = outer(2); const foo = 9; return { value: Foo(3), same: "A" === "a", foo: foo };',
      null
    );
    Assert.isTrue(result.success, result.error == null ? 'Expected success.' : result.error);
    Map<String, Object> output = (Map<String, Object>) JSON.deserializeUntyped(result.resultJson);
    Assert.areEqual(5, output.get('value'));
    Assert.areEqual(false, output.get('same'));
    Assert.areEqual(9, output.get('foo'));
  }
  @IsTest
  static void exposesOnlyExplicitHostBindings() {
    JsAstTestSupport.Response result = run(
      'console.log("hashing", input); return Apex.sha256(input);',
      '"hello"'
    );
    Assert.isTrue(result.success, result.error == null ? 'Expected success.' : result.error);
    Assert.areEqual(
      '"2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"',
      result.resultJson
    );
    Assert.areEqual('["hashing hello"]', result.logsJson);
    Assert.isFalse(run('return Apex.query("SELECT Id FROM Account");', null).success);
  }
  @IsTest
  static void boundsInfiniteLoopsAndRecursion() {
    JsAstTestSupport.Request request = new JsAstTestSupport.Request();
    request.source = 'while (true) {}';
    request.maxSteps = 100;
    JsAstTestSupport.Response result = JsAstTestSupport.run(
      new List<JsAstTestSupport.Request>{ request }
    )[0];
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.contains('Instruction budget'));
    result = run('function recurse() { return recurse(); } return recurse();', null);
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.toLowerCase().contains('budget'));
  }
  @IsTest
  static void rejectsUnsupportedSyntaxAndBadInput() {
    Assert.isTrue(run('return 1 == "1";', null).error.contains('coercive equality'));
    Assert.isTrue(run('return input.map(x => x);', '[1]').error.contains('SyntaxError'));
    Assert.isTrue(run('return input;', '{broken').error.contains('Invalid JSON'));
    Assert.isTrue(run('const x = 1; x = 2;', null).error.contains('constant'));
    Assert.isTrue(run('return Missing;', null).error.contains('ReferenceError'));
    Assert.isTrue(run('return 1 / 0;', null).error.contains('Non-finite'));
  }
  @IsTest
  static void rejectsCyclesAndSupportsSparseArrays() {
    Assert.isTrue(run('const a = {}; a.self = a; return a;', null).error.contains('cyclic'));
    Assert.areEqual(
      '[100,[\"99\"]]',
      run('const a = []; a[99] = 1; return [a.length,Object.keys(a)];', null).resultJson
    );
    Assert.isTrue(run('return input.__proto__;', '{}').error.contains('Prototype'));
  }
  @IsTest
  static void returnsUndefinedAndHandlesLoopControl() {
    JsAstTestSupport.Response result = run('return\n42;', null);
    Assert.isTrue(result.success, result.error == null ? 'Expected success.' : result.error);
    Assert.areEqual('undefined', result.resultType);
    Assert.areEqual('null', result.resultJson);
    result = run(
      'let n = 0; for (const x of input) { if (x === 2) continue; if (x > 4) break; n += x; } return n;',
      '[1,2,3,4,5]'
    );
    Assert.isTrue(result.success, result.error == null ? 'Expected success.' : result.error);
    Assert.areEqual(8, Decimal.valueOf(result.resultJson));
  }
  @IsTest
  static void isolatesTwoHundredRequestsAndErrors() {
    List<JsAstTestSupport.Request> requests = new List<JsAstTestSupport.Request>();
    for (Integer i = 0; i < 200; i++) {
      JsAstTestSupport.Request request = new JsAstTestSupport.Request();
      request.source = 'let count = 0; count += input; return count;';
      request.inputJson = String.valueOf(i);
      requests.add(request);
    }
    Test.startTest();
    List<JsAstTestSupport.Response> results = JsAstTestSupport.run(requests);
    Test.stopTest();
    Assert.areEqual(200, results.size());
    for (Integer i = 0; i < results.size(); i++) {
      Assert.isTrue(
        results[i].success,
        results[i].error == null ? 'Expected success.' : results[i].error
      );
      Assert.areEqual(i, Decimal.valueOf(results[i].resultJson));
    }
    requests[0].source = 'return missing;';
    results = JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ requests[0], requests[1] });
    Assert.isFalse(results[0].success);
    Assert.isTrue(
      results[1].success,
      results[1].error == null ? 'Expected success.' : results[1].error
    );
  }
  @IsTest
  static void enforcesSourceAndConfiguredBudgets() {
    Assert.isFalse(run(' '.repeat(new JsBudget(10000).maxSourceCharacters + 1), null).success);
    JsAstTestSupport.Request request = new JsAstTestSupport.Request();
    request.source = 'return 1;';
    request.maxSteps = 500001;
    Assert.isFalse(JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ request })[0].success);
    Assert.isFalse(JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ null })[0].success);
    JsAstTestSupport.Response oversized = run(
      'let s = "a"; while (s.length < 65536) { s += s; } return [s,s];',
      null
    );
    Assert.isFalse(oversized.success);
    Assert.isTrue(oversized.error.contains('JSON output size'));
  }
  @IsTest
  static void isolatesLaboratoryParseLimitsAndMeasuresPhases() {
    JsBudget defaults = new JsBudget(10000);
    String source = '/*' + 'x'.repeat(defaults.maxSourceCharacters) + '*/return 42;';
    Assert.isFalse(run(source, null).success);
    JsBudget.trustedParseLimits = new JsBudget.ParseLimits(524288, 12000, 6000);
    try {
      JsAstTestSupport.Response response = run(source, null);
      Assert.isTrue(
        response.success,
        response.error == null ? 'Expected success.' : response.error
      );
      Assert.areEqual(42, Decimal.valueOf(response.resultJson));
      Assert.areEqual(source.length(), JsBudget.current.scannedCharacters);
      Assert.isTrue(JsBudget.current.lexerCompleted);
      Assert.isTrue(JsBudget.current.parserCompleted);
      Assert.isTrue(JsBudget.current.tokenCount > 0);
      Assert.isTrue(JsBudget.current.nodeCount > 0);
      Assert.isTrue(
        JsBudget.current.heapChecks <= 6,
        'Comment traversal should not repeatedly rescan an unchanged heap.'
      );
      Assert.isTrue(
        JsBudget.current.cpuChecks >= source.length() / 256,
        'CPU polling continues while scanning long comments.'
      );
      Assert.areEqual(524288, JsBudget.current.maxSourceCharacters);
    } finally {
      JsBudget.trustedParseLimits = null;
    }
    Assert.isFalse(run(source, null).success);
    Assert.areEqual(defaults.maxSourceCharacters, JsBudget.current.maxSourceCharacters);
    Assert.areEqual(defaults.maxTokens, JsBudget.current.maxTokens);
    Assert.areEqual(defaults.maxAstNodes, JsBudget.current.maxAstNodes);
    JsBudget.trustedParseLimits = new JsBudget.ParseLimits(65536, 4, 6000);
    try {
      Assert.isTrue(run('return 1+2;', null).error.contains('Token budget'));
    } finally {
      JsBudget.trustedParseLimits = null;
    }
    JsBudget.trustedParseLimits = new JsBudget.ParseLimits(65536, 12000, 1);
    try {
      Assert.isTrue(run('return 1;', null).error.contains('AST node budget'));
    } finally {
      JsBudget.trustedParseLimits = null;
    }
  }
  @IsTest
  static void preservesBinaryThroughTypedArrayAndBlob() {
    JsAstTestSupport.Response result = run(
      'const bytes = new Uint8Array([0,128,255]); const blob = new Blob([bytes], {type:"application/octet-stream"}); return { base64: Apex.blobToBase64(blob), size: blob.size };',
      null
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Binary binding should succeed.' : result.error
    );
    Map<String, Object> value = (Map<String, Object>) JSON.deserializeUntyped(result.resultJson);
    Assert.areEqual('AID/', value.get('base64'));
    Assert.areEqual(3, value.get('size'));
    result = run('const bytes = new Uint8Array(2); bytes.set([1,2],1); return bytes;', null);
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.contains('exceeds buffer'));
  }
  @IsTest
  static void preservesClassicLoopBindingsAndVarScope() {
    JsAstTestSupport.Response result = run(
      'const functions = []; for (let i = 0; i < 3; i++) { functions.push(function() { return i; }); } const before = typeof outer; if (true) { var outer = 9; } return { values: functions.map(function(f) { return f(); }), outer: outer, before: before };',
      null
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Loop bindings should succeed.' : result.error
    );
    Map<String, Object> value = (Map<String, Object>) JSON.deserializeUntyped(result.resultJson);
    Assert.areEqual(9, value.get('outer'));
    Assert.areEqual('undefined', value.get('before'));
    List<Object> values = (List<Object>) value.get('values');
    Assert.areEqual(3, values.size());
    for (Integer i = 0; i < values.size(); i++) {
      Assert.areEqual(i, Decimal.valueOf(String.valueOf(values[i])));
    }
  }
  @IsTest
  static void doesNotReuseIncompleteHoistingAfterBudgetFailure() {
    JsAstTestSupport.Request first = new JsAstTestSupport.Request();
    first.source = 'var a; var b; var c; return [a,b,c];';
    first.maxSteps = 2;
    JsAstTestSupport.Request second = new JsAstTestSupport.Request();
    second.source = first.source;
    second.maxSteps = 10000;
    List<JsAstTestSupport.Response> results = JsAstTestSupport.run(
      new List<JsAstTestSupport.Request>{ first, second }
    );
    Assert.isFalse(results[0].success);
    Assert.isTrue(results[0].error.contains('Instruction budget'));
    Assert.isTrue(
      results[1].success,
      results[1].error == null
        ? 'Fresh request should rebuild the complete hoist table.'
        : results[1].error
    );
    Assert.areEqual('[null,null,null]', results[1].resultJson);
  }
  @IsTest
  static void samplesHeapWithoutSkippingCpuOrLargeAllocationChecks() {
    JsBudget budget = new JsBudget(10000);
    Integer initial = budget.heapChecks;
    for (Integer i = 0; i < 100; i++)
      budget.poll();
    Assert.areEqual(
      initial,
      budget.heapChecks,
      'Repeated polling at one instruction should not rescan the heap.'
    );
    Assert.isTrue(budget.cpuChecks >= 101, 'CPU checks must continue between heap samples.');
    for (Integer i = 0; i < 256; i++)
      budget.tick();
    Assert.areEqual(initial + 1, budget.heapChecks);
    JsValue.str('x'.repeat(4096));
    Assert.areEqual(initial + 2, budget.heapChecks, 'Large strings force a heap check.');
    budget.allocate(512);
    Assert.areEqual(
      initial + 3,
      budget.heapChecks,
      'Collection allocation bursts force a heap check.'
    );
    budget.cpuReserveMs = budget.cpuLimitMs;
    Boolean rejected = false;
    try {
      budget.poll();
    } catch (JsException ex) {
      rejected = ex.getMessage().contains('CPU reserve');
    }
    Assert.isTrue(rejected, 'CPU reserve must reject immediately even when no heap sample is due.');
    budget.cpuReserveMs = 750;
    budget.heapReserveBytes = budget.heapLimitBytes;
    rejected = false;
    try {
      budget.guard();
    } catch (JsException ex) {
      rejected = ex.getMessage().contains('heap reserve');
    }
    Assert.isTrue(rejected, 'Forced heap checks must still enforce the reserve.');
  }
  @IsTest
  static void convertsNumericComplementAndTruncatesDenseArrays() {
    JsAstTestSupport.Response result = run(
      'const a=[1,2,3]; const alias=a;a.length=1;alias.push(9);return {values:a,bits:[~0,~2147483648,~4294967296,~-1.9]};',
      null
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected numeric complement and truncation.' : result.error
    );
    Map<String, Object> value = (Map<String, Object>) JSON.deserializeUntyped(result.resultJson);
    List<Object> values = (List<Object>) value.get('values');
    Assert.areEqual(2, values.size());
    Assert.areEqual(1, values[0]);
    Assert.areEqual(9, values[1]);
    List<Object> bits = (List<Object>) value.get('bits');
    Assert.areEqual(-1, bits[0]);
    Assert.areEqual(2147483647, bits[1]);
    Assert.areEqual(-1, bits[2]);
    Assert.areEqual(0, bits[3]);
    Assert.areEqual('[1,null,null]', run('const a=[1];a.length=3;return a;', null).resultJson);
  }
}
