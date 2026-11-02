@IsTest
private class JsRuntimeV2Test {
  private static JsAstTestSupport.Response run(String source) {
    JsAstTestSupport.Request request = new JsAstTestSupport.Request();
    request.source = source;
    request.maxSteps = 10000;
    return JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ request })[0];
  }
  @IsTest
  static void executesConstructorInheritanceAndStrictReceivers() {
    JsAstTestSupport.Response response = run(
      'function Base(x){this.x=x;}Base.prototype.read=function(){return this.x;};function Child(x){Base.call(this,x);}Child.prototype=Object.create(Base.prototype);const p=new Child(7);return [p.read(),p instanceof Base,p instanceof Child,p.read.call({x:9})];'
    );
    Assert.isTrue(
      response.success,
      response.error == null ? 'Constructors should execute.' : response.error
    );
    Assert.areEqual('[7,true,true,9]', response.resultJson);
  }
  @IsTest
  static void preservesThrownValuesFinallyAndBudgetStops() {
    JsAstTestSupport.Response response = run(
      'let completed=0;const value={x:4};try{throw value;}catch(e){completed=e===value?e.x:0;}finally{completed++;}return completed;'
    );
    Assert.isTrue(
      response.success,
      response.error == null ? 'Catch/finally should execute.' : response.error
    );
    Assert.areEqual(5, Decimal.valueOf(response.resultJson));
    JsAstTestSupport.Request request = new JsAstTestSupport.Request();
    request.source = 'try{while(true){}}catch(e){return 1;}finally{return 2;}';
    request.maxSteps = 100;
    response = JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ request })[0];
    Assert.isFalse(response.success);
    Assert.isTrue(response.error.contains('Instruction budget'));
    Assert.isTrue(run('return 3;').success);
  }
  @IsTest
  static void preservesMapIdentityAndPrototypeIsolation() {
    JsAstTestSupport.Response response = run(
      'const a={},b={};const m=new Map([[a,1],[b,2],[0,3],[-0,4]]);return [m.size,m.get(a),m.get(b),m.get(0)];'
    );
    Assert.isTrue(
      response.success,
      response.error == null ? 'Map should execute.' : response.error
    );
    Assert.areEqual('[3,1,2,4]', response.resultJson);
    JsAstTestSupport.Request first = new JsAstTestSupport.Request();
    first.source = 'Object.prototype.polluted=1;return 1;';
    JsAstTestSupport.Request second = new JsAstTestSupport.Request();
    second.source = 'return typeof ({}).polluted;';
    List<JsAstTestSupport.Response> responses = JsAstTestSupport.run(
      new List<JsAstTestSupport.Request>{ first, second }
    );
    Assert.isTrue(responses[0].success);
    Assert.areEqual('"undefined"', responses[1].resultJson);
  }
  @IsTest
  static void supportsNumericOperatorsAndArguments() {
    JsAstTestSupport.Response response = run(
      'function f(a){arguments[0]=9;return [a,arguments[0],arguments.length];}return [0xff|0,0x80000000>>>31,-1>>>0,1<<31,f(3)];'
    );
    Assert.isTrue(
      response.success,
      response.error == null ? 'Numeric operators should execute.' : response.error
    );
    List<Object> values = (List<Object>) JSON.deserializeUntyped(response.resultJson);
    Assert.areEqual(255, values[0]);
    Assert.areEqual(1, values[1]);
    Assert.areEqual(Decimal.valueOf('4294967295'), values[2]);
  }
  @IsTest
  static void enforcesDataDescriptorsAndHostBoundary() {
    JsAstTestSupport.Response response = run(
      'const o={visible:1};Object.defineProperty(o,"hidden",{value:2});return [Object.keys(o),o.hidden,JSON.parse(JSON.stringify(o))];'
    );
    Assert.isTrue(
      response.success,
      response.error == null ? 'Descriptors should execute.' : response.error
    );
    List<Object> values = (List<Object>) JSON.deserializeUntyped(response.resultJson);
    Assert.areEqual(1, ((List<Object>) values[0]).size());
    Assert.isFalse(((Map<String, Object>) values[2]).containsKey('hidden'));
    response = run('return ({}).constructor.constructor("return Apex")();');
    Assert.isFalse(response.success);
    Assert.isTrue(response.error.contains('wrapper'));
  }
}
