@IsTest
private class JsLibraryTest {
  private static JsLibraryBinding binding(String name, String resource) {
    JsLibraryBinding value = new JsLibraryBinding();
    value.name = name;
    value.resource = resource;
    return value;
  }
  @IsTest
  static void executesRealStaticResourceAndListsAuthorChoices() {
    List<JsLibraryBinding> modules = new List<JsLibraryBinding>{
      binding('Tools', 'ApexJSExampleTools')
    };
    JsCollectionScriptAction.Response result = JsInterpreter.execute(
      'return {total:libraries.Tools.round(libraries.Tools.sum(input.Amounts),2)};',
      '{"Amounts":[12.25,29.75]}',
      modules,
      100000
    );
    Assert.isTrue(result.success, 'Execution result: ' + result.error);
    Assert.areEqual('{"total":42}', result.resultJson);
    Boolean found = false;
    for (JsLibraryController.Choice choice : JsLibraryController.listLibraries())
      if (choice.value == 'ApexJSExampleTools')
        found = true;
    Assert.isTrue(found);
    Assert.areEqual('vendor__Tools', new JsLibraryController.Choice('Tools', 'vendor').value);
  }
  @IsTest
  static void scopesModulesAndPreservesExportReassignment() {
    JsLibraryLoader.testSources = new Map<String, String>{
      'First' => 'var count=0;exports.next=function(){return ++count;};',
      'Second' => 'module.exports=function(n){return n*2;};'
    };
    try {
      List<JsLibraryBinding> modules = new List<JsLibraryBinding>{
        binding('Counter', 'First'),
        binding('Double', 'Second')
      };
      String source = 'return [libraries.Counter.next(),libraries.Counter.next(),libraries.Double(21)];';
      for (Integer i = 0; i < 2; i++) {
        JsCollectionScriptAction.Response result = JsInterpreter.execute(
          source,
          null,
          modules,
          100000
        );
        Assert.isTrue(result.success, 'Execution result: ' + result.error);
        Assert.areEqual('[1,2,42]', result.resultJson);
      }
    } finally {
      JsLibraryLoader.testSources = null;
    }
  }
  @IsTest
  static void rejectsMissingDuplicateMalformedAndOversizedLibraries() {
    JsLibraryLoader.testSources = new Map<String, String>{
      'Large' => 'x'.repeat(262144),
      'Valid' => 'exports.answer=42;'
    };
    try {
      List<List<JsLibraryBinding>> cases = new List<List<JsLibraryBinding>>{
        new List<JsLibraryBinding>{ null },
        new List<JsLibraryBinding>{ binding('Bad Name', 'Valid') },
        new List<JsLibraryBinding>{ binding('Tools', 'Missing') },
        new List<JsLibraryBinding>{ binding('Tools', 'https://example.com/code.js') },
        new List<JsLibraryBinding>{ binding('Tools', 'Valid'), binding('Tools', 'Valid') },
        new List<JsLibraryBinding>{ binding('Tools', 'Large') }
      };
      for (List<JsLibraryBinding> modules : cases) {
        JsCollectionScriptAction.Response result = JsInterpreter.execute(
          'return libraries;',
          null,
          modules,
          100000
        );
        Assert.isFalse(result.success);
        Assert.isNull(result.resultJson);
        Assert.isNotNull(result.error);
      }
    } finally {
      JsLibraryLoader.testSources = null;
    }
    JsCollectionScriptAction.Response missing = JsInterpreter.execute(
      'return 1;',
      null,
      new List<JsLibraryBinding>{ binding('Tools', 'DefinitelyMissingAsset') },
      100000
    );
    Assert.isFalse(missing.success);
    Assert.isTrue(missing.error.contains('not found'));
  }
  @IsTest
  static void libraryFailuresAndRunawayStartupAreBounded() {
    JsLibraryLoader.testSources = new Map<String, String>{
      'Throws' => 'throw new Error("startup failed");',
      'Runaway' => 'while(true){}',
      'Node' => 'module.exports=require("fs");'
    };
    try {
      for (String name : JsLibraryLoader.testSources.keySet()) {
        JsCollectionScriptAction.Response result = JsInterpreter.execute(
          'return 1;',
          null,
          new List<JsLibraryBinding>{ binding('Tools', name) },
          100
        );
        Assert.isFalse(result.success);
        Assert.isNull(result.resultJson);
      }
    } finally {
      JsLibraryLoader.testSources = null;
    }
  }
}
