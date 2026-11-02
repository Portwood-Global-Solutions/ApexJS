@IsTest
private class JsBytecodeTest {
  private static JsBytecode.Program program(List<Integer> code) {
    String json =
      '{"version":1,"sourceSha256":"' +
      'a'.repeat(64) +
      '","texts":[],"constants":[{"kind":"number","value":"1"},{"kind":"number","value":"2"}],' +
      '"scopes":[{"names":["this","input","arguments"],"kinds":["const","param","var"],"allocationUnits":0}],' +
      '"functions":[{"name":"entry","rootScope":0,"selfScope":-1,"parameterSlots":[1],"argumentsSlot":2,"needsArguments":false,"code":' +
      JSON.serialize(code) +
      '}]}';
    return (JsBytecode.Program) System.JSON.deserialize(json, JsBytecode.Program.class);
  }
  private static JsAstTestSupport.Response run(JsBytecode.Program p, Integer steps) {
    JsBytecodeTestSupport.Request r = new JsBytecodeTestSupport.Request();
    r.programJson = JSON.serialize(p);
    r.inputJson = '{"value":7}';
    r.maxSteps = steps;
    return JsBytecodeTestSupport.run(new List<JsBytecodeTestSupport.Request>{ r })[0];
  }
  @IsTest
  static void returnsInputAndPreservesExistingResponseContract() {
    JsAstTestSupport.Response r = run(program(new List<Integer>{ 1, 0, 1, 0, 24, 0, 0, 0 }), 100);
    Assert.isTrue(r.success, r.error == null ? 'Expected input value.' : r.error);
    Assert.areEqual(7, ((Map<String, Object>) JSON.deserializeUntyped(r.resultJson)).get('value'));
    Assert.isTrue(r.steps > 0 && r.steps <= 100);
    Assert.isTrue(JsBytecodeTestSupport.lastTimings.containsKey('loadAndValidateCpuMs'));
  }
  @IsTest
  static void validatesArtifactBeforeDispatch() {
    for (
      List<Integer> code : new List<List<Integer>>{
        new List<Integer>{ 999, 0, 0, 0 },
        new List<Integer>{ 19, 999, 0, 0 },
        new List<Integer>{ 0, 999, 0, 0 }
      }
    ) {
      JsAstTestSupport.Response r = run(program(code), 100);
      Assert.isFalse(r.success);
      Assert.isTrue(r.error.startsWith('BytecodeError:'));
      Assert.areEqual(0, r.steps);
    }
    JsBytecode.Program p = program(new List<Integer>{ 0, 0, 0, 0, 24, 0, 0, 0 });
    p.version = 2;
    Assert.isTrue(run(p, 100).error.contains('version'));
  }
  @IsTest
  static void enforcesBudgetForBackwardJumps() {
    JsAstTestSupport.Response r = run(program(new List<Integer>{ 19, 0, 0, 0 }), 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('Instruction budget'));
    Assert.areEqual(101, r.steps);
  }
  @IsTest
  static void failsClosedOnMalformedStackAndEnvironmentAddresses() {
    JsAstTestSupport.Response r = run(program(new List<Integer>{ 5, 0, 0, 0, 24, 0, 0, 0 }), 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('stack underflow'));
    r = run(program(new List<Integer>{ 1, 128, 0, 0, 24, 0, 0, 0 }), 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('environment depth'));
    r = run(program(new List<Integer>{ 1, 0, 99, 0, 24, 0, 0, 0 }), 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('index out of range'));
  }
  @IsTest
  static void preservesTemporalDeadZoneAndConstantWrites() {
    JsBytecode.Program p = program(new List<Integer>{ 1, 0, 3, 0, 24, 0, 0, 0 });
    p.scopes[0].names.add('x');
    p.scopes[0].kinds.add('let');
    JsAstTestSupport.Response r = run(p, 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('before initialization'));
    p.scopes[0].kinds[3] = 'const';
    p.functions[0].code = new List<Integer>{
      0,
      0,
      0,
      0,
      3,
      3,
      0,
      0,
      0,
      1,
      0,
      0,
      2,
      0,
      3,
      0,
      24,
      0,
      0,
      0
    };
    r = run(p, 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('constant x'));
  }
  @IsTest
  static void doesNotExposeUnapprovedHostBindings() {
    JsBytecode.Program p = program(new List<Integer>{ 4, 0, 0, 0, 24, 0, 0, 0 });
    p.texts.add('Database');
    JsAstTestSupport.Response r = run(p, 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('Database is not defined'));
  }
  @IsTest
  static void chargesFusedInstructionsAndChecksTheirOperands() {
    JsAstTestSupport.Response baseline = run(
      program(new List<Integer>{ 0, 0, 0, 0, 24, 0, 0, 0 }),
      100
    );
    JsAstTestSupport.Response fused = run(program(new List<Integer>{ 36, 0, 0, 0 }), 100);
    Assert.isTrue(fused.success);
    Assert.areEqual(baseline.resultJson, fused.resultJson);
    Assert.areEqual(baseline.steps, fused.steps);
    JsAstTestSupport.Response invalid = run(program(new List<Integer>{ 38, 1, 999, 0 }), 100);
    Assert.isFalse(invalid.success);
    Assert.isTrue(invalid.error.startsWith('BytecodeError:'));
    Assert.areEqual(0, invalid.steps);
  }
  @IsTest
  static void keepsExpandedExecutionPolicyRestrictedToTrustedLabCode() {
    Boolean rejected = false;
    try {
      new JsBudget(500001);
    } catch (JsException ex) {
      rejected = ex.getMessage().contains('500000');
    }
    Assert.isTrue(rejected);
    JsBudget.trustedExecutionLimits = new JsBudget.ExecutionLimits(2000000, 125000);
    try {
      JsBudget budget = new JsBudget(2000000);
      Assert.areEqual(Limits.getLimitCpuTime() / 10, budget.cpuReserveMs);
      Assert.areEqual(Limits.getLimitHeapSize() / 10, budget.heapReserveBytes);
      Assert.areEqual(0, budget.steps);
    } finally {
      JsBudget.trustedExecutionLimits = null;
    }
    rejected = false;
    try {
      new JsBudget(500001);
    } catch (JsException ex) {
      rejected = true;
    }
    Assert.isTrue(rejected);
  }
  @IsTest
  static void validatesHandlerAndSparseArrayTables() {
    JsAstTestSupport.Response r = run(
      program(new List<Integer>{ 43, 999, -1, 1, 0, 0, 0, 0, 24, 0, 0, 0 }),
      100
    );
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.startsWith('BytecodeError:'));
    Assert.areEqual(0, r.steps);
    JsBytecode.Program p = program(new List<Integer>{ 48, 2, 0, 1, 24, 0, 0, 0 });
    p.texts.add('x0');
    r = run(p, 100);
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.contains('sparse array mask'));
    Assert.areEqual(0, r.steps);
  }
  @IsTest
  static void handlerCannotSwallowMalformedVmState() {
    JsAstTestSupport.Response r = run(
      program(
        new List<Integer>{
          43,
          3,
          -1,
          5,
          5,
          0,
          0,
          0,
          44,
          0,
          0,
          0,
          0,
          0,
          0,
          0,
          24,
          0,
          0,
          0,
          0,
          1,
          0,
          0,
          24,
          0,
          0,
          0
        }
      ),
      100
    );
    Assert.isFalse(r.success);
    Assert.isTrue(r.error.startsWith('BytecodeError:'));
    Assert.isTrue(r.error.contains('stack underflow'));
  }
  @IsTest
  static void admissionOverridesRemainTrustedAndResettable() {
    JsBytecode.Program p = program(new List<Integer>{ 0, 0, 0, 0, 24, 0, 0, 0 });
    JsBytecode.trustedMaxInstructions = 1;
    try {
      Assert.isFalse(run(p, 100).success);
    } finally {
      JsBytecode.trustedMaxInstructions = null;
    }
    Assert.isTrue(run(p, 100).success);
    Map<String, Object> data = (Map<String, Object>) JSON.deserializeUntyped(JSON.serialize(p));
    data.put('trustedMaxInstructions', 1000000);
    JsBytecode.trustedMaxInstructions = 1;
    Boolean rejected = false;
    try {
      try {
        JsBytecode.load(JSON.serialize(data), new JsBudget(100));
      } catch (JsException ex) {
        rejected = ex.getMessage().startsWith('BytecodeError:');
      }
      Assert.isTrue(rejected);
      Assert.areEqual(
        1,
        JsBytecode.trustedMaxInstructions,
        'JSON must not change trusted admission policy.'
      );
    } finally {
      JsBytecode.trustedMaxInstructions = null;
    }
  }
}
