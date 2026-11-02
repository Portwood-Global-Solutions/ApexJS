@IsTest
private class JsPortwoodDataTest {
  private static JsCollectionScriptAction.Request data(String json) {
    JsCollectionScriptAction.Request q = new JsCollectionScriptAction.Request();
    q.inputJson = json;
    return q;
  }
  private static JsPortwoodDataAction.Response prepare(JsCollectionScriptAction.Request q) {
    return JsPortwoodDataAction.run(new List<JsCollectionScriptAction.Request>{ q })[0];
  }
  @IsTest
  static void preparesNamedDataWithoutCalculations() {
    JsPortwoodDataAction.Response result = prepare(
      data('{"Title":"Proposal","Customers":[{"Name":"Acme"}],"Labels":["A",null]}')
    );
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.isFalse(result.javascriptExecuted);
    Assert.areEqual(3, result.inputCount);
    Map<String, Object> json = (Map<String, Object>) JSON.deserializeUntyped(result.jsonData);
    Assert.areEqual('Proposal', json.get('Title'));
    List<Object> records = (List<Object>) ((Map<String, Object>) json.get('Customers'))
      .get('records');
    Assert.areEqual('Acme', ((Map<String, Object>) records[0]).get('Name'));
    Assert.isTrue(result.mergeTags.contains('{Title}'));
    Assert.isTrue(result.mergeTags.contains('{#Customers}...{/Customers}'));
    Assert.isTrue(result.mergeTags.contains('{Value}'));
  }
  @IsTest
  static void executesCalculationsAndReusesExistingJson() {
    JsCollectionScriptAction.Request q = data('{"Amounts":[12.5,29.5]}');
    q.source = 'return {Summary:{Total:input.Amounts.reduce(function(a,b){return a+b;},0)},Items:input.Amounts};';
    JsPortwoodDataAction.Response result = prepare(q);
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.isTrue(result.javascriptExecuted);
    Assert.isTrue(result.mergeTags.contains('{Summary.Total}'));
    Assert.areEqual(64, result.sourceSha256.length());
    q = new JsCollectionScriptAction.Request();
    q.dataMode = 'JSON';
    q.existingJson = result.resultJson;
    JsPortwoodDataAction.Response reused = prepare(q);
    Assert.isTrue(reused.success, 'Execution result: ' + reused.error);
    Assert.isFalse(reused.javascriptExecuted);
    Assert.areEqual(result.jsonData, reused.jsonData);
    q.existingJson = '[1,2]';
    q.collectionName = 'Figures';
    reused = prepare(q);
    Assert.isTrue(reused.success);
    Assert.isTrue(reused.jsonData.contains('"Figures"'));
    q.existingJson = 'false';
    reused = prepare(q);
    Assert.isTrue(reused.jsonData.contains('"Result":false'));
  }
  @IsTest
  static void keepsBulkResultsAndErrorsIndependent() {
    JsCollectionScriptAction.Request first = data('{"Value":1}');
    first.source = 'return input;';
    JsCollectionScriptAction.Request bad = data('{}');
    bad.source = 'throw new Error("expected");';
    List<JsPortwoodDataAction.Response> results = JsPortwoodDataAction.run(
      new List<JsCollectionScriptAction.Request>{ first, bad, data('{"Value":3}') }
    );
    Assert.isTrue(results[0].success);
    Assert.isFalse(results[1].success);
    Assert.isNull(results[1].jsonData);
    Assert.isNull(results[1].resultJson);
    Assert.isTrue(results[2].success);
    Assert.areEqual(0, JsPortwoodDataAction.run(null).size());
  }
  @IsTest
  static void rejectsConflictsAndUnsafeExpansion() {
    List<JsCollectionScriptAction.Request> cases = new List<JsCollectionScriptAction.Request>{
      null
    };
    JsCollectionScriptAction.Request q = data('{}');
    q.dataMode = 'wrong';
    cases.add(q);
    q = data('{}');
    q.existingJson = '{}';
    cases.add(q);
    q = new JsCollectionScriptAction.Request();
    q.dataMode = 'JSON';
    cases.add(q);
    q = data('{}');
    q.collectionName = 'bad.name';
    cases.add(q);
    q = data('{}');
    JsLibraryBinding module = new JsLibraryBinding();
    module.name = 'Tools';
    module.resource = 'ApexJSExampleTools';
    q.libraries = new List<JsLibraryBinding>{ module };
    cases.add(q);
    q = data('{"Items":[' + '0,'.repeat(11000) + '0]}');
    cases.add(q);
    q = new JsCollectionScriptAction.Request();
    q.existingJson = '"' + 'x'.repeat(JsDataPolicy.MAX_JSON_CHARACTERS) + '"';
    cases.add(q);
    for (JsPortwoodDataAction.Response result : JsPortwoodDataAction.run(cases)) {
      Assert.isFalse(result.success);
      Assert.isNotNull(result.error);
      Assert.isNull(result.jsonData);
      Assert.isNull(result.resultJson);
    }
  }
  @IsTest
  static void handlesLargeTextAndExistingRecordsWrappers() {
    JsPortwoodDataAction.Response result = prepare(
      data(
        JSON.serialize(
          new Map<String, Object>{
            'Labels' => new List<String>{ 'x'.repeat(35000), 'y'.repeat(35000) },
            'Rows' => new Map<String, Object>{
              'records' => new List<Object>{
                new Map<String, Object>{
                  'attributes' => new Map<String, Object>{ 'type' => 'Account' },
                  'Name' => 'Acme'
                }
              }
            }
          }
        )
      )
    );
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.isTrue(result.jsonData.length() > 65536);
    Assert.isTrue(result.jsonData.contains('"attributes"'));
  }
}
