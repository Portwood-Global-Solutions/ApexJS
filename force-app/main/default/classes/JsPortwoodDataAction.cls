/** Subscriber-side adapter: Flow collections -> optional JS -> Portwood JSON Data. No managed code changes. */
public with sharing class JsPortwoodDataAction {
  public class Response {
    @InvocableVariable
    public Boolean success;
    @InvocableVariable
    public String error;
    @InvocableVariable(label='Portwood JSON Data')
    public String jsonData;
    @InvocableVariable(label='Calculation Result JSON')
    public String resultJson;
    @InvocableVariable(label='Available template tags')
    public List<String> mergeTags;
    @InvocableVariable
    public Boolean javascriptExecuted;
    @InvocableVariable
    public String sourceSha256;
    @InvocableVariable
    public Integer compileCpuMs;
    @InvocableVariable
    public Integer runtimeCpuMs;
    @InvocableVariable
    public Integer cpuMs;
    @InvocableVariable
    public Integer inputCount;
    @InvocableVariable
    public List<String> inputNames;
  }
  private class Shape {
    JsBudget budget;
    Set<String> tags = new Set<String>();
    Integer nodes = 0;
    Shape(JsBudget budget) {
      this.budget = budget;
    }
    private void charge(Integer depth) {
      budget.tick();
      budget.allocate(1);
      nodes++;
      if (depth > 16 || nodes > 10000)
        throw new JsException('BudgetError: Merge data exceeds the depth or node policy.');
    }
    private void tag(String value) {
      if (tags.size() < 300)
        tags.add(value);
    }
    Object normalize(Object value, String path, Integer depth) {
      charge(depth);
      if (value instanceof List<Object>)
        return new Map<String, Object>{ 'records' => rows((List<Object>) value, path, depth + 1) };
      if (value instanceof Map<String, Object>) {
        Map<String, Object> source = (Map<String, Object>) value,
          result = new Map<String, Object>();
        for (String key : source.keySet()) {
          if (
            key == 'attributes' &&
            source.get(key) instanceof Map<String, Object> &&
            ((Map<String, Object>) source.get(key)).containsKey('type')
          ) {
            result.put(key, source.get(key));
            continue;
          }
          String child = String.isBlank(path) ? key : path + '.' + key;
          if (key == 'records' && !String.isBlank(path) && source.get(key) instanceof List<Object>)
            result.put(key, rows((List<Object>) source.get(key), path, depth + 1));
          else
            result.put(key, normalize(source.get(key), child, depth + 1));
        }
        return result;
      }
      if (!String.isBlank(path))
        tag('{' + path + '}');
      return value;
    }
    private List<Object> rows(List<Object> values, String path, Integer depth) {
      tag('{#' + path + '}...{/' + path + '}');
      List<Object> result = new List<Object>();
      for (Object value : values) {
        if (value instanceof Map<String, Object>)
          result.add(normalize(value, '', depth + 1));
        else
          result.add(new Map<String, Object>{ 'Value' => normalize(value, 'Value', depth + 1) });
      }
      return result;
    }
  }
  private static String collectionName(String value) {
    String name = String.isBlank(value) ? 'Items' : value.trim();
    JsDataPolicy.validateName(name);
    return name;
  }
  @InvocableMethod(
    label='Prepare Portwood Data'
    category='ApexJS'
    configurationEditor='c-js-portwood-data-editor'
    description='Prepare named Flow data or an earlier JSON result for Portwood. Calculations and Static Resource libraries are optional. Does not save records or generate documents.'
  )
  public static List<Response> run(List<JsCollectionScriptAction.Request> requests) {
    List<Response> results = new List<Response>();
    if (requests == null)
      return results;
    List<JsCollectionScriptAction.Request> scripts = new List<JsCollectionScriptAction.Request>();
    Map<Integer, Integer> positions = new Map<Integer, Integer>();
    for (Integer i = 0; i < requests.size(); i++)
      if (
        requests[i] != null &&
        !String.isBlank(requests[i].source) &&
        requests[i].existingJson == null &&
        requests[i].dataMode != 'JSON'
      ) {
        positions.put(i, scripts.size());
        scripts.add(requests[i]);
      }
    List<JsCollectionScriptAction.Response> calculated = JsCollectionScriptAction.run(scripts);
    for (Integer i = 0; i < requests.size(); i++) {
      Integer started = Limits.getCpuTime(), scriptCpu = 0;
      Response response = new Response();
      response.success = false;
      response.javascriptExecuted = false;
      response.compileCpuMs = 0;
      response.runtimeCpuMs = 0;
      JsBudget prior = JsBudget.current;
      try {
        JsBudget budget = new JsBudget(100000);
        JsCollectionScriptAction.Request request = requests[i];
        if (request == null)
          throw new JsException('InputError: Request is required.');
        if (
          !String.isBlank(request.dataMode) &&
          request.dataMode != 'Direct' &&
          request.dataMode != 'JSON'
        )
          throw new JsException('InputError: Choose Flow data or an earlier JSON result.');
        if (
          request.libraries != null &&
          !request.libraries.isEmpty() &&
          String.isBlank(request.source)
        )
          throw new JsException('InputError: Enter a calculation to use the selected libraries.');
        String name = collectionName(request.collectionName);
        Object raw;
        if (request.dataMode == 'JSON' || request.existingJson != null) {
          if (String.isBlank(request.existingJson))
            throw new JsException('InputError: The earlier JSON result is empty.');
          if (
            request.inputJson != null ||
            request.namedInputs != null && !request.namedInputs.isEmpty() ||
            JsCollectionScriptAction.hasDirectChannels(request) ||
            !String.isBlank(request.source) ||
            request.libraries != null && !request.libraries.isEmpty()
          )
            throw new JsException(
              'InputError: Use an earlier result or named data and calculations, not both.'
            );
          if (request.existingJson.length() > JsDataPolicy.MAX_JSON_CHARACTERS)
            throw new JsException(
              'BudgetError: Earlier JSON exceeds ' +
                JsDataPolicy.MAX_JSON_CHARACTERS +
                ' characters.'
            );
          JsDataPolicy.preflight(request.existingJson, budget.remainingAllocations(), 0);
          raw = JSON.deserializeUntyped(request.existingJson);
          response.resultJson = JSON.serialize(raw);
        } else if (positions.containsKey(i)) {
          JsCollectionScriptAction.Response execution = calculated[positions.get(i)];
          scriptCpu = execution.cpuMs;
          response.javascriptExecuted = true;
          response.sourceSha256 = execution.sourceSha256;
          response.compileCpuMs = execution.compileCpuMs;
          response.runtimeCpuMs = execution.runtimeCpuMs;
          response.inputNames = execution.inputNames;
          response.inputCount = execution.inputCount;
          if (!execution.success)
            throw new JsException(execution.error);
          response.resultJson = execution.resultJson;
          raw = JSON.deserializeUntyped(execution.resultJson);
        } else {
          Map<String, Object> input = JsCollectionScriptAction.prepareInput(request);
          response.inputNames = new List<String>(input.keySet());
          response.inputNames.sort();
          response.inputCount = input.size();
          raw = input;
          response.resultJson = JSON.serialize(raw);
        }
        Shape shape = new Shape(budget);
        Object root = raw instanceof Map<String, Object>
          ? raw
          : raw instanceof List<Object>
              ? new Map<String, Object>{ name => raw }
              : new Map<String, Object>{ 'Result' => raw };
        String prepared = JSON.serialize(shape.normalize(root, '', 0));
        if (
          prepared.length() > JsDataPolicy.MAX_JSON_CHARACTERS ||
          response.resultJson.length() > JsDataPolicy.MAX_JSON_CHARACTERS
        )
          throw new JsException(
            'BudgetError: Prepared JSON exceeds ' +
              JsDataPolicy.MAX_JSON_CHARACTERS +
              ' characters.'
          );
        budget.guard();
        response.mergeTags = new List<String>(shape.tags);
        response.mergeTags.sort();
        response.jsonData = prepared;
        response.success = true;
      } catch (Exception error) {
        response.error = error.getMessage();
        response.resultJson = null;
      } finally {
        JsBudget.current = prior;
      }
      response.cpuMs = Limits.getCpuTime() - started + scriptCpu;
      results.add(response);
    }
    return results;
  }
}
