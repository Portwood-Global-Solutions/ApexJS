@IsTest
private class JsLanguageTest {
  private static Object run(String source) {
    JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    return JSON.deserializeUntyped(result.resultJson);
  }
  @IsTest
  static void arrayMutationSortingAndCallbackMethods() {
    Object value = run(
      'var a=[3,1,2];a.sort(function(x,y){return x-y;});a.unshift(0);a.push(4);var shifted=a.shift(),popped=a.pop();a.reverse();return {a:a,shifted:shifted,popped:popped,includes:a.includes(2),index:a.indexOf(1),some:a.some(function(n){return n>2;}),every:a.every(function(n){return n>0;})};'
    );
    Map<String, Object> result = (Map<String, Object>) value;
    Assert.areEqual(new List<Object>{ 3, 2, 1 }, result.get('a'));
    Assert.areEqual(0, result.get('shifted'));
    Assert.areEqual(4, result.get('popped'));
    Assert.areEqual(true, result.get('includes'));
    Assert.areEqual(2, result.get('index'));
    Assert.areEqual(true, result.get('some'));
    Assert.areEqual(true, result.get('every'));
    Assert.areEqual(
      new List<Object>{ 'A', 'B' },
      run('return Array.from({0:"A",1:"B",length:2});')
    );
    Assert.areEqual(
      new List<Object>{ 1, 2, 3 },
      run('var a=[];Array.of(1,2,3).forEach(function(n){a.push(n);});return a;')
    );
    Assert.areEqual(
      new List<Object>{ 1, 9, 8, 3 },
      run('var a=[1,2,3];a.splice(1,1,9,8);return a;')
    );
  }
  @IsTest
  static void datesUseUtcAndCanBeCalculated() {
    Assert.areEqual(
      new List<Object>{ '2026-11-01T09:30:00.000Z', 2026, 10, 1, 0 },
      run(
        'var d=new Date("2026-11-01T09:30:00.000Z");return [d.toISOString(),d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate(),d.getTimezoneOffset()];'
      )
    );
    Assert.areEqual(
      '2027-01-02T03:04:05.006Z',
      run(
        'var d=new Date(Date.UTC(2026,11,31));d.setUTCFullYear(2027);d.setUTCMonth(0);d.setUTCDate(2);d.setUTCHours(3,4,5,6);return d.toISOString();'
      )
    );
    Assert.areEqual(
      true,
      run(
        'return Date.parse("2026-11-01T09:30:00.000Z")===new Date("2026-11-01T09:30:00.000Z").getTime();'
      )
    );
  }
  @IsTest
  static void datesUseTheProlepticGregorianCalendarOutsideTheModernRange() {
    Assert.areEqual(
      new List<Object>{
        '2027-02-01T02:02:02.001Z',
        1,
        '1969-12-31T23:59:59.999Z',
        3,
        999,
        true,
        -14826672000000L,
        4,
        '+010000-01-01T00:00:00.000Z',
        1793491200000L,
        126
      },
      run(
        'var a=new Date(Date.UTC(2026,13,0,25,61,61,1001)),b=new Date(-1),c=new Date("1500-03-01T00:00:00Z"),e=new Date(Date.UTC(10000,0,1)),f=new Date("2026-11-01");' +
        'return [a.toISOString(),a.getUTCDay(),b.toISOString(),b.getUTCDay(),b.getUTCMilliseconds(),c.getTime()===Date.UTC(1500,2,1),c.getTime(),c.getUTCDay(),e.toISOString(),f.getTime(),f.getYear()];'
      )
    );
  }
  @IsTest
  static void datesIgnoreABuddhistEraLocale() {
    Profile p = [SELECT Id FROM Profile WHERE Name = 'System Administrator' LIMIT 1];
    User thai = new User(
      FirstName = 'Era',
      LastName = 'Dates',
      Alias = 'eradates',
      Email = 'eradates@apexjs.example.com',
      Username = 'eradates' + Datetime.now().getTime() + '@apexjs.example.com',
      TimeZoneSidKey = 'Asia/Bangkok',
      LocaleSidKey = 'th_TH',
      EmailEncodingKey = 'UTF-8',
      LanguageLocaleKey = 'en_US',
      ProfileId = p.Id
    );
    insert thai;
    System.runAs(thai) {
      Assert.areEqual(
        new List<Object>{ '2026-11-01T09:30:00.000Z', 2026, 10, 1, 0, '2026-12-31T00:00:00.000Z' },
        run(
          'var d=new Date("2026-11-01T09:30:00.000Z"),u=new Date(Date.UTC(2026,11,31));return [d.toISOString(),d.getUTCFullYear(),d.getUTCMonth(),d.getUTCDate(),d.getUTCDay(),u.toISOString()];'
        )
      );
    }
  }
  @IsTest
  static void regularExpressionsAndStringOperations() {
    Assert.areEqual(
      new List<Object>{ 'b', 'bc', 'bcd', 3 },
      run('var s="abcde";return [s.charAt(1),s.substr(1,2),s.substring(4,1),s.lastIndexOf("d")];')
    );
    Assert.areEqual(new List<Object>{ 'A1', 'B2' }, run('return "A1 B2".match(/[A-Z][0-9]/g);'));
    Assert.areEqual('12-AA', run('return "AA12".replace(/([A-Z]+)([0-9]+)/,"$2-$1");'));
    Assert.areEqual(
      'A2 B3',
      run('return "A1 B2".replace(/[0-9]/g,function(n){return Number(n)+1;});')
    );
    Assert.areEqual(new List<Object>{ 'A', 'B' }, run('return "A,B".split(/,/);'));
    Assert.areEqual(2, run('return "ab12".search(/[0-9]/);'));
    Assert.areEqual(
      new List<Object>{ true, 2, false, 0 },
      run(
        'var r=/ab/g;var first=r.test("ab");var index=r.lastIndex;var second=r.test("xx");return [first,index,second,r.lastIndex];'
      )
    );
  }
  @IsTest
  static void boundedPromisesResolveAdoptAndReject() {
    Assert.areEqual(
      42,
      run(
        'return new Promise(function(resolve){resolve(20);resolve(99);}).then(function(n){return Promise.resolve(n+1);}).then(function(n){return n*2;});'
      )
    );
    Assert.areEqual(
      7,
      run('return Promise.reject("expected").catch(function(e){return e==="expected"?7:0;});')
    );
    Assert.areEqual(3, run('return Promise.resolve({then:function(resolve){resolve(3);}});'));
    Assert.areEqual(
      9,
      run('return new Promise(function(resolve,reject){throw 9;}).catch(function(n){return n;});')
    );
    Assert.areEqual(5, run('return Promise.resolve(5).then().then(null);'));
    for (
      String source : new List<String>{
        'return new Promise(function(resolve){});',
        'return Promise.reject("unhandled");',
        'var p=Promise.resolve(1);var q=p.then(function(){return q;});return q;',
        'return Promise();',
        'return new Promise(1);'
      }
    ) {
      JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
      Assert.isFalse(result.success);
      Assert.isNull(result.resultJson);
    }
  }
  @IsTest
  static void numericConversionsTypedBuffersAndHostIsolation() {
    Assert.areEqual(
      new List<Object>{ 16, 1.25, true, true, false, true },
      run(
        'return [parseInt("0x10"),parseFloat("1.25xyz"),isNaN("bad"),isFinite("42"),Boolean(0),Boolean("yes")];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 2, 255, 1 },
      run(
        'var b=new ArrayBuffer(2);var a=new Uint8Array(b);a[0]=255;a[1]=1;return [b.byteLength,a[0],a[1]];'
      )
    );
    Assert.areEqual('SGVsbG8=', run('return Apex.base64Encode("Hello");'));
    for (
      String source : new List<String>{
        'return Database.query("SELECT Id FROM Account");',
        'return fetch("https://example.com");',
        'return require("fs");',
        'return Function("return 1")();'
      }
    ) {
      JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
      Assert.isFalse(result.success);
      Assert.isNull(result.resultJson);
    }
  }
}
