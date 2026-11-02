@IsTest
private class JsCollectionScriptTest {
  private static JsCollectionScriptAction.Request request(String source, String input) {
    JsCollectionScriptAction.Request q = new JsCollectionScriptAction.Request();
    q.source = source;
    q.inputJson = input;
    return q;
  }
  @IsTest
  static void acceptsRawSourceAndReportsTypedMetadata() {
    JsCollectionScriptAction.Response result = JsInterpreter.execute(
      'console.log("calculated");return {summary:{total:input.Prices.reduce(function(a,b){return a+b;},0)}};',
      '{"Prices":[12.5,20,9.5]}'
    );
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.areEqual('object', result.resultType);
    Assert.areEqual(1, result.inputCount);
    Assert.areEqual(new List<String>{ 'Prices' }, result.inputNames);
    Assert.areEqual(64, result.sourceSha256.length());
    Assert.isTrue(result.steps > 0);
    Assert.isTrue(result.logsJson.contains('calculated'));
    JsResultAction.Request selectValue = new JsResultAction.Request();
    selectValue.resultJson = result.resultJson;
    selectValue.path = 'summary.total';
    selectValue.outputType = 'Number';
    Assert.areEqual(
      42,
      JsResultAction.run(new List<JsResultAction.Request>{ selectValue })[0].numberValue
    );
  }
  @IsTest
  static void sourceOnlyBulkRequestsAreIsolated() {
    String source = 'if(input.Change)Object.prototype.changed=1;return {type:typeof ({}).changed};';
    List<JsCollectionScriptAction.Response> results = JsCollectionScriptAction.run(
      new List<JsCollectionScriptAction.Request>{
        request(source, '{"Change":true}'),
        request(source, '{}')
      }
    );
    Assert.isTrue(results[0].success);
    Assert.areEqual('{"type":"undefined"}', results[1].resultJson);
    Assert.areEqual(
      '42',
      JsCollectionScriptAction.run(
          new List<JsCollectionScriptAction.Request>{ request('return 42;', null) }
        )[0]
        .resultJson
    );
    Assert.areEqual(0, JsCollectionScriptAction.run(null).size());
  }
  @IsTest
  static void rejectsInvalidMixedAndExcessiveInput() {
    List<JsCollectionScriptAction.Request> cases = new List<JsCollectionScriptAction.Request>{
      null,
      request('', '{}'),
      request('return 1;', '[]'),
      request('return 1;', ''),
      request('return ; ???', '{}'),
      request('return input;', '{"constructor":1}')
    };
    JsCollectionScriptAction.Request q = request('return 1;', '{}');
    q.namedInputs = new List<JsFlowNamedInput>{ new JsFlowNamedInput() };
    cases.add(q);
    q = request('return 1;', null);
    q.dataMode = 'invalid';
    cases.add(q);
    q = request('return 1;', null);
    q.existingJson = '{}';
    cases.add(q);
    q = request('while(true){}', '{}');
    q.maxSteps = 100;
    cases.add(q);
    q = request('return 1;', '{}');
    q.maxSteps = 500001;
    cases.add(q);
    q = request(
      'return input;',
      JSON.serialize(
        new Map<String, Object>{ 'Large' => 'x'.repeat(JsDataPolicy.MAX_JSON_CHARACTERS) }
      )
    );
    cases.add(q);
    for (JsCollectionScriptAction.Response result : JsCollectionScriptAction.run(cases)) {
      Assert.isFalse(result.success);
      Assert.isNotNull(result.error);
      Assert.isNull(result.resultJson);
    }
  }
  @IsTest
  static void restoresHostStateAfterSuccessAndFailure() {
    JsBudget previous = new JsBudget(1000);
    Boolean previousBuiltins = JsLibraryBuiltins.enabled,
      previousPromises = JsPromiseNatives.enabled;
    try {
      JsLibraryBuiltins.enabled = false;
      JsPromiseNatives.enabled = false;
      List<JsCollectionScriptAction.Response> results = JsCollectionScriptAction.run(
        new List<JsCollectionScriptAction.Request>{
          request('return Promise.resolve(7).then(function(n){return n*6;});', '{}'),
          request('throw new Error("expected");', '{}')
        }
      );
      Assert.areEqual('42', results[0].resultJson);
      Assert.isFalse(results[1].success);
      Assert.isTrue(JsBudget.current === previous);
      Assert.isFalse(JsLibraryBuiltins.enabled);
      Assert.isFalse(JsPromiseNatives.enabled);
    } finally {
      JsLibraryBuiltins.enabled = previousBuiltins;
      JsPromiseNatives.enabled = previousPromises;
      JsBudget.current = null;
    }
  }
  @IsTest
  static void rejectsDenseDeepAndOversizedOutput() {
    for (
      String data : new List<String>{
        '{"Dense":[' +
        '[],'.repeat(30000) +
        '[]]}',
        '{"Deep":' +
        '['.repeat(40) +
        '0' +
        ']'.repeat(40) +
        '}'
      }
    ) {
      JsCollectionScriptAction.Response result = JsInterpreter.execute('return input;', data);
      Assert.isFalse(result.success);
      Assert.isNull(result.resultJson);
    }
    String source = 'var text="x";while(text.length<65536){text+=text;}return [text,text,text,text,text,text,text,text,text];';
    JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
    Assert.isFalse(result.success);
    Assert.isTrue(result.error.contains('524288'));
    Assert.isNull(result.resultJson);
  }
}
