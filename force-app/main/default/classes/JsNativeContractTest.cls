@IsTest
private class JsNativeContractTest {
  private static Object value(String source) {
    JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
    Assert.isTrue(result.success, 'Execution: ' + result.error);
    return JSON.deserializeUntyped(result.resultJson);
  }
  @IsTest
  static void mathAndNumberFormattingHavePredictableResults() {
    Assert.areEqual(
      new List<Object>{ 2, 1, 2, -1, 1, 3, 0, 1, 0, 8, 3, 0, -1, 0 },
      value(
        'return [Math.abs(-2),Math.floor(1.9),Math.ceil(1.1),Math.round(-1.5),Math.min(3,1,2),Math.max(1,3,2),Math.sin(0),Math.cos(0),Math.tan(0),Math.pow(2,3),Math.sqrt(9),Math.log(1),Math.sign(-4),Math.atan2(0,1)];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 'ff', '101', '42', true, true, true, false },
      value(
        'return [(255).toString(16),(5).toString(2),String(42),Number.isInteger(2),Number.isFinite(2.5),Number.isNaN(NaN),Number.isInteger(2.5)];'
      )
    );
  }
  @IsTest
  static void unicodeStringsAndSlicesPreserveCodePoints() {
    Assert.areEqual(
      new List<Object>{ 2, 128512, 'AB', '005', 'bc', 1, 65 },
      value(
        'var s=String.fromCodePoint(128512);return [s.length,s.codePointAt(0),String.fromCharCode(65,66),"5".padStart(3,"0"),"abc".slice(-2),"abc".indexOf("b"),"A".charCodeAt(0)];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 'Hello', 2, 'SGVsbG8=' },
      value(
        'return [Apex.base64Decode("SGVsbG8="),Apex.utf8ByteLength("é"),Apex.base64Encode("Hello")];'
      )
    );
  }
  @IsTest
  static void typedBuffersCopyOverlappingViewsAndNormalizeWords() {
    Assert.areEqual(
      new List<Object>{ 1, 1, 2, 3, 1, 2 },
      value(
        'var a=new Uint8Array([1,2,3,4]);a.set(a.subarray(0,3),1);var copy=a.slice(1,3);return [a[0],a[1],a[2],a[3],copy[0],copy[1]];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 1, 1, 65535, -1 },
      value(
        'var a=new Uint16Array([1,65537,-1]);var b=new Int32Array([4294967295]);return [a[0],a[1],a[2],b[0]];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 4, 'QQD/Qg==' },
      value(
        'var b=new Blob(["A",new Uint8Array([0,255]),"B"]);return [b.size,Apex.blobToBase64(b)];'
      )
    );
  }
  @IsTest
  static void descriptorsPrototypesAndFunctionCallsRemainDataOnly() {
    Assert.areEqual(
      new List<Object>{ 7, 1, true, false },
      value(
        'var p={base:1};var o=Object.create(p);var stored=7;Object.defineProperty(o,"x",{get:function(){return stored;},enumerable:true});return [o.x,o.base,Object.getPrototypeOf(o)===p,Object.hasOwn(o,"base")];'
      )
    );
    Assert.areEqual(
      6,
      value('function add(a,b){return this.base+a+b;}return add.call({base:1},2,3);')
    );
    Assert.areEqual(
      6,
      value('function add(a,b){return this.base+a+b;}return add.apply({base:1},[2,3]);')
    );
    Assert.areEqual(
      new List<Object>{ 'a', 'b' },
      value('return Object.keys(Object.assign({}, {a:1}, {b:2})).sort();')
    );
  }
  @IsTest
  static void arraySpliceConcatAndSparseEnumerationStayConsistent() {
    Assert.areEqual(
      new List<Object>{ 1, 2, 9, 8 },
      value('var a=[1,2,3,4];a.splice(-2,2,9,8);return a;')
    );
    Assert.areEqual(new List<Object>{ 1, 2, 3, 4 }, value('return [1].concat([2,3],4);'));
    Assert.areEqual(new List<Object>{ '1' }, value('var a=[,1,,];return Object.keys(a);'));
    Assert.areEqual(new List<Object>{ 'A', 'B' }, value('return ["B","A"].sort();'));
  }
  @IsTest
  static void largeJsonIsAdmittedAndExtractedWithoutA32kBoundary() {
    String text = 'x'.repeat(35000);
    String input = JSON.serialize(
      new Map<String, Object>{ 'Labels' => new List<String>{ text, text, text } }
    );
    JsCollectionScriptAction.Response result = JsInterpreter.execute(
      'return {Labels:input.Labels};',
      input
    );
    Assert.isTrue(result.success, 'Execution: ' + result.error);
    Assert.isTrue(result.resultJson.length() > 100000);
    JsResultAction.Request selectValue = new JsResultAction.Request();
    selectValue.resultJson = result.resultJson;
    selectValue.path = 'Labels';
    selectValue.outputType = 'TextCollection';
    JsResultAction.Response selected = JsResultAction.run(
      new List<JsResultAction.Request>{ selectValue }
    )[0];
    Assert.isTrue(selected.success, 'Extraction: ' + selected.error);
    Assert.areEqual(3, selected.textValues.size());
    Assert.areEqual(text, selected.textValues[2]);
  }

  @IsTest
  static void invalidNativeCallsFailWithoutPartialResults() {
    for (
      String source : new List<String>{
        'return Math.min();',
        'return Apex.sha256(1);',
        'return Apex.base64Decode("!");',
        'return new Uint8Array(32769);',
        'return new Uint8Array(-1);',
        'var a=new Uint8Array([1]);a.set([2,3],0);return a;',
        'return String.fromCodePoint(1114112);',
        'return new Date("not a date");',
        'return new RegExp("x","gg");',
        'return new RegExp("x","z");',
        'return "x".padStart(70000,"a");',
        'return Object.create(1);',
        'return "A".charCodeAt(99);',
        'return (2).toString(1);',
        'return (2.5).toString(16);',
        'return Number("not a number");',
        'return new Uint16Array([1]).buffer;',
        'var a=new Uint32Array(1);a.set([1,2]);return a;',
        'return "a".replace("a","$1");',
        'var o={};Object.defineProperty(o,"x",{set:function(v){}});return o;'
      }
    ) {
      JsCollectionScriptAction.Response result = JsInterpreter.execute(source, null);
      Assert.isFalse(result.success, 'Expected rejection: ' + source);
      Assert.isNull(result.resultJson);
      Assert.isNotNull(result.error);
    }
  }

  @IsTest
  static void stringAndObjectBoundaryValuesAreExplicit() {
    Assert.areEqual('undefined', value('return typeof "A".codePointAt(99);'));
    Assert.areEqual(
      new List<Object>{ 1, false, false, true },
      value(
        'var o={};Object.defineProperty(o,"x",{value:1});var d=Object.getOwnPropertyDescriptor(o,"x");return [o.x,d.enumerable,d.writable,Object.keys(o).length===0];'
      )
    );
    Assert.areEqual(
      'TypeError',
      value(
        'try{var o={};Object.defineProperty(o,"x",{value:1});o.x=2;}catch(e){return e.name;}return "unexpected";'
      )
    );
    Assert.areEqual(
      3,
      value(
        'var total=0;var it=new Map([["A",1],["B",2]]).values();var step=it.next();while(!step.done){total+=step.value;step=it.next();}return total;'
      )
    );
  }

  @IsTest
  static void typedViewsAliasWhileSlicesRemainIndependent() {
    Assert.areEqual(
      new List<Object>{ 1, 9, 2, 3, 9, 8, 2, 6 },
      value(
        'var a=new Uint16Array([1,2,3,4]);a.set(a.subarray(0,3),1);var view=a.subarray(1);var copy=a.slice(1);view[0]=9;copy[0]=8;return [a[0],a[1],a[2],a[3],view[0],copy[0],view.byteOffset,view.byteLength];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 0, 0, 1, 0, 0 },
      value(
        'var a=new Uint32Array(2);var b=new Uint32Array([true,null,undefined]);return [a[0],a[1],b[0],b[1],b[2]];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 9, 1, 2 },
      value(
        'var a=new Uint8Array([1,2,3]);var v=new Uint8Array(a.buffer,1,2);v[0]=9;return [a[1],v.byteOffset,v.byteLength];'
      )
    );
  }

  @IsTest
  static void replacementCallbacksAndArrayLikeApplyHaveExplicitArguments() {
    Assert.areEqual(
      new List<Object>{ 'a[12]b[3]', 'ab13c', null, 'a', 'b', 1 },
      value(
        'var letters="ab".split("");return ["a12b3".replace(/[0-9]+/g,function(m){return "["+m+"]";}),"abc".replace("b",function(m,i,s){return m+i+s.length;}),"abc".match(/[0-9]+/g),letters[0],letters[1],"abc".indexOf("b",-2)];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 6, 0, 1, 0, '', false, false, '-ff' },
      value(
        'function add(a,b){return this.base+a+b;}return [add.apply({base:1},{0:2,1:3,length:2}),Number(),Number(true),Number(null),String(),Number.isFinite("1"),Number.isInteger("1"),(-255).toString(16)];'
      )
    );
    Assert.areEqual(
      new List<Object>{ 65, 63, 'text/plain' },
      value(
        'var a=Apex.latin1Bytes("A中");return [a[0],a[1],new Blob(["x"],{type:"TEXT/PLAIN"}).type];'
      )
    );
  }

  @IsTest
  static void arrayConstructionAndUnicodeIterationPreserveValues() {
    Assert.areEqual(
      new List<Object>{
        3,
        new List<Object>{ '1' },
        new List<Object>{ 'x', 'y' },
        new List<Object>{ 'A', '😀' },
        new List<Object>{ 1 }
      },
      value(
        'var a=Array(3);a[1]=7;return [a.length,Object.keys(a),new Array("x","y"),Array.from("A😀"),Array.from(new Map([["A",1]]).values())];'
      )
    );
  }

  @IsTest
  static void characterApplyHandlesBytesWordsAndPrimitiveConversions() {
    Assert.areEqual(
      new List<Object>{ 'ABÿ', 'CD', 3, 0, 1, 0, 3.5, '42' },
      value(
        'var a=String.fromCharCode.apply(null,[65,null,true]);return [String.fromCharCode.apply(null,new Uint8Array([65,66,255])),String.fromCharCode.apply(null,new Uint16Array([67,68])),a.length,a.charCodeAt(1),a.charCodeAt(2),String.fromCharCode(NaN).charCodeAt(0),Number(3.5),(42).toString()];'
      )
    );
  }

  @IsTest
  static void numericPredicatesHonorPrimitiveConversion() {
    Assert.areEqual(
      new List<Object>{ -255, true, true, true, false, true, true, true },
      value(
        'return [parseInt("-fftail",16),isNaN(parseInt("xyz",10)),Number.isNaN(parseInt("10",1)),isNaN(),isFinite(),isFinite(null),isFinite({valueOf:function(){return "12";}}),isNaN([1,2])];'
      )
    );
  }

  @IsTest
  static void descriptorReconfigurationHonorsFlagsAndGetterIdentity() {
    Assert.areEqual(
      new List<Object>{ 1, true, true, 'undefined', true, true, 3 },
      value(
        'var o={};Object.defineProperty(o,"x",{value:1,writable:true,configurable:true});Object.defineProperty(o,"x",{enumerable:true});var d=Object.getOwnPropertyDescriptor(o,"x");var before=o.x;var removed=delete o.x;var getter=function(){return 3;};Object.defineProperty(o,"y",{get:getter,enumerable:true});var g=Object.getOwnPropertyDescriptor(o,"y");return [before,d.enumerable,d.writable,typeof o.x,removed,g.get===getter,o.y];'
      )
    );
    for (
      String descriptor : new List<String>{
        '{value:2}',
        '{configurable:true}',
        '{enumerable:true}',
        '{writable:true}',
        '{get:function(){return 1;}}'
      }
    ) {
      Assert.areEqual(
        'TypeError',
        value(
          'var o={};Object.defineProperty(o,"x",{value:1});try{Object.defineProperty(o,"x",' +
            descriptor +
            ');}catch(e){return e.name;}return "unexpected";'
        )
      );
    }
    Assert.areEqual(
      new List<Object>{ 1, 'TypeError', false },
      value(
        'var o={};Object.defineProperty(o,"x",{value:1});Object.defineProperty(o,"x",{value:1});var error="unexpected";try{delete o.x;}catch(e){error=e.name;}return [o.x,error,Object.getOwnPropertyDescriptor(o,"x").configurable];'
      )
    );
  }
}
