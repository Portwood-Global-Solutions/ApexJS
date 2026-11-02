@IsTest
private class JsCompilerTest {
  private static JsAstTestSupport.Response run(String source) {
    JsBudget budget = new JsBudget(100000);
    JsBytecode.Program program = JsBytecodeCompiler.compile(source, budget);
    JsBytecodeTestSupport.Request request = new JsBytecodeTestSupport.Request();
    request.programJson = JSON.serialize(program);
    request.inputJson = 'null';
    request.maxSteps = 100000;
    return JsBytecodeTestSupport.run(new List<JsBytecodeTestSupport.Request>{ request })[0];
  }
  @IsTest
  static void emitsExecutableClosuresAndLoopBindings() {
    JsAstTestSupport.Response result = run(
      'const f=[];for(let i=0;i<3;i++){f.push(function(){return i;});}function add(n){return function(v){return n+v;};}return [f.map(function(g){return g();}),add(3)(4)];'
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected compiled execution success' : result.error
    );
    Assert.areEqual('[[0,1,2],7]', result.resultJson);
  }
  @IsTest
  static void emitsHoistingSelfRecursionAndArguments() {
    JsAstTestSupport.Response result = run(
      'const r=f(4);function f(n){if(n<2)return 1;return n*f(n-1);}const g=function local(n){return n===0?arguments.length:local(n-1);};return [r,g(3),typeof local];'
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected compiled execution success' : result.error
    );
    Assert.areEqual('[24,1,"undefined"]', result.resultJson);
  }
  @IsTest
  static void emitsTryFinallyAndLoopUnwind() {
    JsAstTestSupport.Response result = run(
      'const seen=[];for(let i=0;i<3;i++){try{if(i===1)continue;if(i===2)break;seen.push(i);}finally{seen.push("f"+i);}}function f(){try{return 1;}finally{return 2;}}return [seen,f()];'
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected compiled execution success' : result.error
    );
    Assert.areEqual('[[0,"f0","f1","f2"],2]', result.resultJson);
  }
  @IsTest
  static void retainsConstAndTdzValidation() {
    JsAstTestSupport.Response result = run('let a=1;{return a;let a=2;}');
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.contains('before initialization'));
    result = run('const a=1;a=2;');
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.contains('constant'));
  }
  @IsTest
  static void supportsSparseDeleteLooseEqualityAndInitializerClone() {
    JsAstTestSupport.Response result = run(
      'const a=[,1,,];delete a[1];let initial;const f=[];for(let i=(initial=function(){return i;},0),j=1;i<2;i++){f.push(function(){return i+j;});}return [a.length,Object.keys(a),initial(),f.map(function(g){return g();}),1=="1"];'
    );
    Assert.isTrue(
      result.success,
      result.error == null ? 'Expected extended compiler syntax' : result.error
    );
    Assert.areEqual('[3,[],0,[1,2],true]', result.resultJson);
  }

  @IsTest
  static void emitsEnumerationSwitchAndLabeledBlockUnwind() {
    JsAstTestSupport.Response result = run(
      'const values={a:1,b:2};let total=0;for(const key in values){total+=values[key];}let labelValue=0;outer:{for(let i=0;i<3;i++){if(i===1){labelValue=i;break outer;}}}switch(total){case 3:total+=4;break;default:total=-1;}return [total,labelValue];'
    );
    Assert.isTrue(result.success, 'Compiled execution: ' + result.error);
    Assert.areEqual('[7,1]', result.resultJson);
  }
}
