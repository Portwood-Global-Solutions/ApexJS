@IsTest
private class JsStorageTest {
  @IsTest
  static void pagedByteViewsOverlapSafelyAndCopiesAreIndependent() {
    Boolean prior = JsBytes.trustedPagedStorage;
    JsBudget previous = JsBudget.current;
    try {
      JsBytes.trustedPagedStorage = true;
      JsRuntime runtime = new JsRuntime(new JsBudget(100000));
      Blob data = Blob.valueOf('x'.repeat(510) + 'ABCDEF' + 'y'.repeat(200));
      JsValue bytes = JsBytes.fromBlob(data, 'uint8array', runtime);
      JsValue view = JsBytes.alias(bytes, 'uint8array', 509, 10);
      Assert.areEqual(65, JsBytes.read(view, 1));
      JsBytes.copy(bytes, 512, bytes, 510, 6, runtime);
      Assert.areEqual(
        'ABABCDEF',
        JsBytes.toBlob(JsBytes.alias(bytes, 'uint8array', 510, 8), runtime).toString()
      );
      JsValue copy = JsBytes.slice(view, 0, 10, runtime);
      JsBytes.write(view, 0, 90);
      Assert.areEqual(120, JsBytes.read(copy, 0));
      Assert.areEqual(90, JsBytes.read(bytes, 509));
      Assert.areEqual(data.size(), JsBytes.length(JsBytes.buffer(view)));
      Boolean rejected = false;
      try {
        JsBytes.copy(bytes, -1, bytes, 0, 1, runtime);
      } catch (JsException error) {
        rejected = true;
      }
      Assert.isTrue(rejected);
    } finally {
      JsBytes.trustedPagedStorage = prior;
      JsBudget.current = previous;
    }
  }
  @IsTest
  static void mapIteratorsRemainLiveAcrossChanges() {
    JsCollectionScriptAction.Response result = JsInterpreter.execute(
      'var m=new Map([["A",1],["B",2]]);var it=m.keys();m.delete("A");m.set("C",3);return [it.next().value,it.next().value,it.next().done];',
      null
    );
    Assert.isTrue(result.success, 'Execution: ' + result.error);
    Assert.areEqual('["B","C",true]', result.resultJson);
    result = JsInterpreter.execute(
      'var m=new Map([["A",1],["B",2]]);var it=m.values();m.set("A",3);var first=it.next().value;m.clear();m.set("C",4);return [first,it.next().value,it.next().done];',
      null
    );
    Assert.isTrue(result.success, 'Execution: ' + result.error);
    Assert.areEqual('[3,4,true]', result.resultJson);
    result = JsInterpreter.execute(
      'var m=new Map([["A",1],["B",2]]);var out=[];var it=m.entries();var next=it.next();while(!next.done){out.push(next.value[0]+next.value[1]);next=it.next();}return out;',
      null
    );
    Assert.isTrue(result.success, 'Execution: ' + result.error);
    Assert.areEqual('["A1","B2"]', result.resultJson);
  }
}
