@IsTest
private class JsDirectInputsTest {
  private static JsFlowNamedInput row(String name, String kind, Boolean collection) {
    JsFlowNamedInput value = new JsFlowNamedInput();
    value.name = name;
    value.kind = kind;
    value.isCollection = collection;
    return value;
  }
  private static JsCollectionScriptAction.Request request(List<JsFlowNamedInput> rows) {
    JsCollectionScriptAction.Request q = new JsCollectionScriptAction.Request();
    q.dataMode = 'Direct';
    q.namedInputs = rows;
    q.source = 'return input;';
    return q;
  }
  private static Map<String, Object> result(JsCollectionScriptAction.Request q) {
    JsCollectionScriptAction.Response r = JsCollectionScriptAction.run(
      new List<JsCollectionScriptAction.Request>{ q }
    )[0];
    Assert.isTrue(r.success, r.error == null ? 'Expected success' : r.error);
    return (Map<String, Object>) JSON.deserializeUntyped(r.resultJson);
  }
  @IsTest
  static void recordsRepeatedCollectionsAndScalars() {
    List<JsFlowNamedInput> rows = new List<JsFlowNamedInput>();
    JsFlowNamedInput r = row('accounts', 'Records', true);
    r.records = new List<SObject>{ new Account(Name = 'Acme') };
    rows.add(r);
    r = row('orders', 'Records', true);
    r.records = new List<SObject>{ new Opportunity(Name = 'Deal', Amount = 123) };
    rows.add(r);
    r = row('first', 'Number', true);
    r.numbers = new List<Decimal>{ 1, 2 };
    rows.add(r);
    r = row('second', 'Number', true);
    r.numbers = new List<Decimal>{ 3 };
    rows.add(r);
    r = row('flag', 'Boolean', false);
    r.booleanValue = false;
    rows.add(r);
    r = row('zero', 'Number', false);
    r.numberValue = 0;
    rows.add(r);
    r = row('empty', 'Text', true);
    rows.add(r);
    r = row('caption', 'Text', false);
    r.textValue = 'A "quote"\n';
    rows.add(r);
    Map<String, Object> value = result(request(rows));
    Assert.areEqual(8, value.size());
    Assert.areEqual(false, value.get('flag'));
    Assert.areEqual(0, value.get('zero'));
    Assert.areEqual(new List<Object>(), value.get('empty'));
    Assert.areEqual('A "quote"\n', value.get('caption'));
    Assert.areEqual(
      'Acme',
      ((Map<String, Object>) ((List<Object>) value.get('accounts'))[0]).get('Name')
    );
    Assert.areEqual(
      123,
      ((Map<String, Object>) ((List<Object>) value.get('orders'))[0]).get('Amount')
    );
  }
  @IsTest
  static void datesPreserveBoundariesNullsAndUtc() {
    JsCollectionScriptAction.Request q = request(
      new List<JsFlowNamedInput>{
        row('first', 'Date', true),
        row('empty', 'Date', true),
        row('instant', 'DateTime', false),
        row('second', 'Date', true)
      }
    );
    q.inputSizes = new JsFlowInputSizes();
    q.inputSizes.sizes = new List<Integer>{ 3, 0, 1 };
    Date marker = Date.newInstance(1900, 1, 1);
    q.nativeDates = new List<Date>{
      Date.newInstance(2026, 11, 1),
      null,
      marker,
      marker,
      null,
      marker,
      Date.newInstance(2027, 1, 1),
      marker
    };
    Datetime instant = Datetime.newInstanceGmt(2026, 11, 1, 9, 30, 0);
    q.nativeDateTimes = new List<Datetime>{ instant, Datetime.newInstanceGmt(1900, 1, 1, 0, 0, 0) };
    Map<String, Object> value = result(q);
    Assert.areEqual(new List<Object>{ '2026-11-01', null, '1900-01-01' }, value.get('first'));
    Assert.areEqual(new List<Object>(), value.get('empty'));
    Assert.areEqual('2026-11-01T09:30:00.000Z', value.get('instant'));
    Assert.areEqual(new List<Object>{ '2027-01-01' }, value.get('second'));
  }
  @IsTest
  static void malformedNativeChannelsAndConflictsFailAtomically() {
    List<JsCollectionScriptAction.Request> cases = new List<JsCollectionScriptAction.Request>();
    for (Integer scenario = 0; scenario < 5; scenario++) {
      JsCollectionScriptAction.Request q = request(
        new List<JsFlowNamedInput>{ row('days', 'Date', true) }
      );
      q.inputSizes = new JsFlowInputSizes();
      q.inputSizes.sizes = new List<Integer>{ 1 };
      q.nativeDates = new List<Date>{ Date.newInstance(2026, 11, 1), Date.newInstance(1900, 1, 1) };
      if (scenario == 0)
        q.inputSizes = null;
      if (scenario == 1)
        q.nativeDates.remove(1);
      if (scenario == 2)
        q.inputSizes.sizes.add(0);
      if (scenario == 3)
        q.nativeDates.add(null);
      if (scenario == 4)
        q.inputJson = '{}';
      cases.add(q);
    }
    for (JsCollectionScriptAction.Response r : JsCollectionScriptAction.run(cases)) {
      Assert.isFalse(r.success);
      Assert.isNotNull(r.error);
      Assert.areEqual(null, r.resultJson);
    }
  }
  @IsTest
  static void literalValuesAndAdmissionRules() {
    List<JsFlowNamedInput> rows = new List<JsFlowNamedInput>();
    JsFlowNamedInput r = row('label', 'Text', false);
    r.isLiteral = true;
    r.valueJson = '"\\u007b!caption\\u007d"';
    rows.add(r);
    r = row('flag', 'Boolean', false);
    r.isLiteral = true;
    r.valueJson = 'false';
    rows.add(r);
    r = row('zero', 'Number', false);
    r.isLiteral = true;
    r.valueJson = '0';
    rows.add(r);
    Map<String, Object> value = result(request(rows));
    Assert.areEqual('{!caption}', value.get('label'));
    Assert.areEqual(false, value.get('flag'));
    Assert.areEqual(0, value.get('zero'));
    List<JsCollectionScriptAction.Request> bad = new List<JsCollectionScriptAction.Request>();
    r = row('number', 'Number', false);
    r.isLiteral = true;
    r.valueJson = '"wrong"';
    bad.add(request(new List<JsFlowNamedInput>{ r }));
    bad.add(
      request(
        new List<JsFlowNamedInput>{
          row('duplicate', 'Text', true),
          row('duplicate', 'Number', true)
        }
      )
    );
    bad.add(request(new List<JsFlowNamedInput>{ row('constructor', 'Text', true) }));
    for (JsCollectionScriptAction.Response failure : JsCollectionScriptAction.run(bad)) {
      Assert.isFalse(failure.success);
      Assert.areEqual(null, failure.resultJson);
    }
  }
  @IsTest
  static void unlimitedRowsBulkIsolationAndLargePortwoodData() {
    List<JsFlowNamedInput> rows = new List<JsFlowNamedInput>();
    for (Integer i = 0; i < 201; i++) {
      JsFlowNamedInput r = row('data' + i, 'Number', true);
      r.numbers = new List<Decimal>{ i };
      rows.add(r);
    }
    JsCollectionScriptAction.Request q = request(rows);
    q.source = 'return {count:Object.keys(input).length,last:input.data200[0]};';
    JsFlowNamedInput only = row('data200', 'Number', true);
    only.numbers = new List<Decimal>{ 9 };
    JsCollectionScriptAction.Request second = request(new List<JsFlowNamedInput>{ only });
    second.source = q.source;
    List<JsCollectionScriptAction.Response> results = JsCollectionScriptAction.run(
      new List<JsCollectionScriptAction.Request>{ q, second }
    );
    Assert.isTrue(results[0].success);
    Assert.isTrue(results[1].success);
    Assert.areEqual(201, results[0].inputCount);
    Assert.areEqual(1, results[1].inputCount);
    Assert.areEqual(
      9,
      ((Map<String, Object>) JSON.deserializeUntyped(results[1].resultJson)).get('last')
    );
    JsFlowNamedInput large = row('Labels', 'Text', true);
    large.texts = new List<String>{ 'x'.repeat(35000), 'y'.repeat(35000) };
    q = request(new List<JsFlowNamedInput>{ large });
    q.source = null;
    JsPortwoodDataAction.Response prepared = JsPortwoodDataAction.run(
      new List<JsCollectionScriptAction.Request>{ q }
    )[0];
    Assert.isTrue(
      prepared.success,
      prepared.error == null ? 'Expected Portwood data' : prepared.error
    );
    Assert.isFalse(prepared.javascriptExecuted);
    Assert.isTrue(prepared.jsonData.length() > 65536);
  }
}
