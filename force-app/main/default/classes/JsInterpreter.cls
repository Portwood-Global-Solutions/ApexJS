/** Apex convenience API. Input is a JSON object; outputs use the Flow execution contract. */
public with sharing class JsInterpreter {
  public static JsCollectionScriptAction.Response execute(String source, String inputJson) {
    return execute(source, inputJson, null, 100000);
  }
  public static JsCollectionScriptAction.Response execute(
    String source,
    String inputJson,
    List<JsLibraryBinding> libraries,
    Integer maxSteps
  ) {
    JsCollectionScriptAction.Request request = new JsCollectionScriptAction.Request();
    request.source = source;
    request.dataMode = 'Direct';
    request.inputJson = inputJson == null ? '{}' : inputJson;
    request.libraries = libraries;
    request.maxSteps = maxSteps;
    return JsCollectionScriptAction.run(new List<JsCollectionScriptAction.Request>{ request })[0];
  }
}
