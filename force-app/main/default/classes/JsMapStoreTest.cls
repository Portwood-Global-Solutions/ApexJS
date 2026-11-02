@IsTest
private class JsMapStoreTest {
  private static void equalValues(String expected, String actual) {
    List<Object> e = (List<Object>) JSON.deserializeUntyped(expected),
      a = (List<Object>) JSON.deserializeUntyped(actual);
    Assert.areEqual(e.size(), a.size());
    for (Integer i = 0; i < e.size(); i++)
      Assert.areEqual(e[i], a[i], 'Element ' + i);
  }
  private static JsAstTestSupport.Response run(String source) {
    JsAstTestSupport.Request r = new JsAstTestSupport.Request();
    r.source = source;
    r.maxSteps = 10000;
    return JsAstTestSupport.run(new List<JsAstTestSupport.Request>{ r })[0];
  }
  @IsTest
  static void preservesPrimitiveIdentityAndSignedZero() {
    JsAstTestSupport.Response r = run(
      'const m=new Map();m.set("A",1).set("a",2).set(0,3).set(-0,4).set("0",5).set(false,6).set(null,7).set(undefined,8);return [m.size,m.get("A"),m.get("a"),m.get(0),m.get(-0),m.get("0"),m.get(false),m.get(null),m.get(undefined)];'
    );
    Assert.isTrue(r.success, r.error == null ? 'Expected indexed Map.' : r.error);
    equalValues('[7,1,2,4,4,5,6,7,8]', r.resultJson);
  }
  @IsTest
  static void retainsIdentityAfterMutationAndDeletion() {
    JsAstTestSupport.Response r = run(
      'const a={},b={},f=function(){};const m=new Map([[a,1],[b,2],["x",3],[f,4]]);a.changed=7;Object.setPrototypeOf(a,null);m.delete(b);m.set("x",5);m.set(b,6);return [m.size,m.get(a),m.get(b),m.get("x"),m.get(f),m.has({})];'
    );
    Assert.isTrue(r.success, r.error == null ? 'Expected stable identity.' : r.error);
    equalValues('[4,1,6,5,4,false]', r.resultJson);
  }
  @IsTest
  static void keepsNumericKeysDistinctWithoutStringConversion() {
    JsAstTestSupport.Response r = run(
      'const m=new Map([[9007199254740991,1],[9007199254740990,2],[1e100,3],[-1e100,4]]);return [m.size,m.get(9007199254740991),m.get(9007199254740990),m.get(1e100),m.get(-1e100)];'
    );
    Assert.isTrue(r.success, r.error == null ? 'Expected exact numeric keys.' : r.error);
    equalValues('[4,1,2,3,4]', r.resultJson);
  }
  @IsTest
  static void clearsIndexesAndDoesNotExposeHostFields() {
    JsAstTestSupport.Response r = run(
      'const key={};const m=new Map([[key,1],["x",2]]);m.clear();m.set("x",3);return [m.size,m.has(key),m.get("x"),Object.keys(m),typeof m.mapIndex,typeof key.mapIdentity];'
    );
    Assert.isTrue(r.success, r.error == null ? 'Expected clear and isolation.' : r.error);
    equalValues('[1,false,3,[],"undefined","undefined"]', r.resultJson);
  }
}
