@IsTest
private class JsResultActionTest {
  private static JsResultAction.Request request(String json, String path, String type) {
    JsResultAction.Request q = new JsResultAction.Request();
    q.resultJson = json;
    q.path = path;
    q.outputType = type;
    return q;
  }
  private static JsResultAction.Response read(String json, String path, String type) {
    return JsResultAction.run(new List<JsResultAction.Request>{ request(json, path, type) })[0];
  }
  @IsTest
  static void extractsEveryScalarWithStrictTypes() {
    String json = '{"text":"A","number":0,"flag":false,"day":"2026-11-01","instant":"2026-11-01T09:30:00.000Z","nil":null}';
    Assert.areEqual('A', read(json, 'text', 'Text').textValue);
    Assert.areEqual(0, read(json, 'number', 'Number').numberValue);
    Assert.areEqual(false, read(json, 'flag', 'Boolean').booleanValue);
    Assert.areEqual(Date.newInstance(2026, 11, 1), read(json, 'day', 'Date').dateValue);
    Assert.areEqual(
      Datetime.newInstanceGmt(2026, 11, 1, 9, 30, 0),
      read(json, 'instant', 'DateTime').dateTimeValue
    );
    JsResultAction.Response nil = read(json, 'nil', 'Text');
    Assert.isTrue(nil.success);
    Assert.isTrue(nil.found);
    Assert.isTrue(nil.isNull);
    Assert.isNull(nil.textValue);
    Assert.isFalse(read(json, 'text', 'Number').success);
    Assert.isFalse(read(json, 'number', 'Text').success);
    Assert.isFalse(read(json, 'flag', 'Number').success);
    Assert.isFalse(read(json, 'day', 'DateTime').success);
  }
  @IsTest
  static void extractsEveryPrimitiveCollectionIncludingNulls() {
    Assert.areEqual(
      new List<String>{ 'A', null },
      read('["A",null]', '$', 'TextCollection').textValues
    );
    Assert.areEqual(
      new List<Decimal>{ 0, 1.5, null },
      read('[0,1.5,null]', '', 'NumberCollection').numberValues
    );
    Assert.areEqual(
      new List<Boolean>{ false, null, true },
      read('[false,null,true]', '', 'BooleanCollection').booleanValues
    );
    Assert.areEqual(
      new List<Date>{ Date.newInstance(2026, 11, 1), null },
      read('["2026-11-01",null]', '', 'DateCollection').dateValues
    );
    Assert.areEqual(
      new List<Datetime>{ Datetime.newInstanceGmt(2026, 11, 1, 9, 30, 0) },
      read('["2026-11-01T09:30:00Z"]', '', 'DateTimeCollection').dateTimeValues
    );
    Assert.areEqual(new List<Decimal>(), read('[]', '', 'NumberCollection').numberValues);
    Assert.isFalse(read('[1,"2"]', '', 'NumberCollection').success);
    Assert.isFalse(read('{}', '', 'NumberCollection').success);
  }
  @IsTest
  static void supportsNestedIndicesAndJsonPointers() {
    String json = '{"summary":{"rows":[{"amount":42}]},"a/b":{"~key":[false]}}';
    Assert.areEqual(42, read(json, 'summary.rows[0].amount', 'Number').numberValue);
    Assert.areEqual(false, read(json, '/a~1b/~0key/0', 'Boolean').booleanValue);
    Assert.isTrue(read(json, '$', 'JSON').jsonValue.contains('summary'));
    for (
      String path : new List<String>{
        'summary..rows',
        'summary.rows[9]',
        'summary.missing',
        '/a~2b',
        'summary.rows.bad',
        'summary.rows[0].amount.value'
      }
    ) {
      JsResultAction.Response result = read(json, path, 'Number');
      Assert.isFalse(result.success);
      Assert.isNotNull(result.error);
      Assert.isNull(result.numberValue);
    }
  }
  @IsTest
  static void createsFlatTypedRecordsWithoutDatabaseWrites() {
    JsResultAction.Request q = request(
      '[{"Name":"Acme","AnnualRevenue":42,"attributes":{"type":"Account"}}]',
      '',
      'Records'
    );
    q.objectApiName = 'Account';
    Integer writes = Limits.getDmlStatements();
    JsResultAction.Response result = JsResultAction.run(new List<JsResultAction.Request>{ q })[0];
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.areEqual(Account.SObjectType, result.records[0].getSObjectType());
    Assert.areEqual('Acme', result.records[0].get('Name'));
    Assert.areEqual(writes, Limits.getDmlStatements());
    for (
      String invalid : new List<String>{
        '[1]',
        '[{"MissingField":1}]',
        '[{"Name":{"nested":1}}]',
        '[{"attributes":"bad"}]',
        '[{"attributes":{"type":"Opportunity"}}]',
        '[{"Id":"' +
        UserInfo.getUserId() +
        '"}]'
      }
    ) {
      q.resultJson = invalid;
      result = JsResultAction.run(new List<JsResultAction.Request>{ q })[0];
      Assert.isFalse(result.success);
      Assert.isNull(result.records);
    }
    q.objectApiName = 'DoesNotExist__c';
    q.resultJson = '[]';
    Assert.isFalse(JsResultAction.run(new List<JsResultAction.Request>{ q })[0].success);
    q.objectApiName = null;
    Assert.isFalse(JsResultAction.run(new List<JsResultAction.Request>{ q })[0].success);
  }
  @IsTest
  static void rejectsExcessiveAndInvalidResults() {
    List<JsResultAction.Request> cases = new List<JsResultAction.Request>{
      null,
      request(null, '', 'JSON'),
      request('{}', '', 'unknown'),
      request('not json', '', 'JSON'),
      request('"2026-99-99"', '', 'Date'),
      request('"local time"', '', 'DateTime'),
      request('"' + 'x'.repeat(JsDataPolicy.MAX_JSON_CHARACTERS) + '"', '', 'JSON'),
      request('['.repeat(40) + '0' + ']'.repeat(40), '', 'JSON')
    };
    for (JsResultAction.Response result : JsResultAction.run(cases)) {
      Assert.isFalse(result.success);
      Assert.isNotNull(result.error);
    }
    Assert.areEqual(0, JsResultAction.run(null).size());
    JsResultAction.Request records = request('[' + '{},'.repeat(2000) + '{}]', '', 'Records');
    records.objectApiName = 'Account';
    Assert.isFalse(JsResultAction.run(new List<JsResultAction.Request>{ records })[0].success);
  }
}
