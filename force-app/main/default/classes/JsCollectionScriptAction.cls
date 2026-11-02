/** General bounded script action. Collections are copied to JSON; no database capabilities enter JS. */
public with sharing class JsCollectionScriptAction {
  public class Request {
    @InvocableVariable(label='JavaScript function body')
    public String source;
    @InvocableVariable(label='JavaScript Static Resource libraries')
    public List<JsLibraryBinding> libraries;
    @InvocableVariable(label='Input JSON object (Apex API)')
    public String inputJson;
    @InvocableVariable(label='Named collections and values')
    public List<JsFlowNamedInput> namedInputs;
    @InvocableVariable(label='Internal native date values')
    public List<Date> nativeDates;
    @InvocableVariable(label='Internal native date/time values')
    public List<Datetime> nativeDateTimes;
    @InvocableVariable(label='Internal native text values')
    public List<String> nativeTexts;
    @InvocableVariable(label='Internal native number values')
    public List<Decimal> nativeNumbers;
    @InvocableVariable(label='Internal native checkbox values')
    public List<Boolean> nativeBooleans;
    @InvocableVariable(label='Internal named input sizes')
    public JsFlowInputSizes inputSizes;
    @InvocableVariable(label='Name for an earlier JSON collection')
    public String collectionName;
    @InvocableVariable(label='Existing Flow JSON result for Portwood')
    public String existingJson;
    @InvocableVariable(label='Input mode: Direct or JSON')
    public String dataMode;
    @InvocableVariable(label='Maximum execution steps (default 100000)')
    public Integer maxSteps;
  }
  public class Response {
    @InvocableVariable
    public Boolean success;
    @InvocableVariable
    public String error;
    @InvocableVariable
    public String resultJson;
    @InvocableVariable
    public String resultType;
    @InvocableVariable
    public String logsJson;
    @InvocableVariable
    public String sourceSha256;
    @InvocableVariable
    public Integer compileCpuMs;
    @InvocableVariable
    public Integer runtimeCpuMs;
    @InvocableVariable
    public Integer cpuMs;
    @InvocableVariable
    public Integer steps;
    @InvocableVariable
    public Integer peakObservedHeapBytes;
    @InvocableVariable
    public Integer inputCount;
    @InvocableVariable
    public List<String> inputNames;
  }
  public static Map<String, Object> prepareInput(Request request) {
    if (request == null)
      throw new JsException('InputError: Request is required.');
    if (!String.isBlank(request.dataMode) && request.dataMode != 'Direct')
      throw new JsException('InputError: Choose Flow data for JavaScript execution.');
    if (request.existingJson != null)
      throw new JsException(
        'InputError: Use Prepare Portwood Data to prepare an earlier JSON result.'
      );
    if (request.inputJson != null) {
      if (
        request.namedInputs != null && !request.namedInputs.isEmpty() || hasDirectChannels(request)
      )
        throw new JsException('InputError: Supply named Flow data or input JSON, not both.');
      return JsDataPolicy.parseObject(request.inputJson);
    }
    return JsDirectInputs.prepare(request);
  }
  public static Boolean hasDirectChannels(Request request) {
    return request.nativeDates != null ||
      request.nativeDateTimes != null ||
      request.nativeTexts != null ||
      request.nativeNumbers != null ||
      request.nativeBooleans != null ||
      request.inputSizes != null;
  }
  @InvocableMethod(
    label='Run JavaScript on Collections'
    category='ApexJS'
    configurationEditor='c-js-collection-script-editor'
    description='Run JavaScript with named Flow data and optional Static Resource libraries. Returns JSON for typed Flow extraction. No records are saved.'
  )
  public static List<Response> run(List<Request> requests) {
    List<Response> responses = new List<Response>();
    if (requests == null)
      return responses;
    String previousSource;
    JsBytecode.Program previousProgram;
    for (Request request : requests) {
      Integer started = Limits.getCpuTime();
      Response response = new Response();
      response.success = false;
      JsBudget prior = JsBudget.current, budget;
      JsRuntime runtime;
      Boolean priorBuiltins = JsLibraryBuiltins.enabled, priorPromises = JsPromiseNatives.enabled;
      try {
        if (request == null || String.isBlank(request.source))
          throw new JsException('InputError: JavaScript source is required.');
        JsLibraryBuiltins.enabled = true;
        JsPromiseNatives.enabled = true;
        budget = new JsBudget(request.maxSteps == null ? 100000 : request.maxSteps);
        Map<String, Object> inputData = prepareInput(request);
        budget.guard();
        response.inputNames = new List<String>(inputData.keySet());
        response.inputNames.sort();
        response.inputCount = inputData.size();
        Integer phase = Limits.getCpuTime();
        JsBytecode.Program program;
        String source = JsLibraryLoader.build(request.source, request.libraries, budget);
        if (previousProgram != null && source.equals(previousSource))
          program = previousProgram;
        else {
          program = JsBytecodeCompiler.compile(source, budget);
          previousSource = source;
          previousProgram = program;
        }
        response.compileCpuMs = Limits.getCpuTime() - phase;
        response.sourceSha256 = program.sourceSha256;
        phase = Limits.getCpuTime();
        JsValue input = JsCodec.fromJsonData(inputData, budget);
        inputData = null;
        runtime = new JsRuntime(budget);
        JsValue value = JsPromiseNatives.finish(
          new JsBytecode(program, runtime).run(input),
          runtime
        );
        String result = JsCodec.stringify(value, budget, runtime, JsDataPolicy.MAX_JSON_CHARACTERS);
        budget.guard();
        response.resultJson = result;
        response.resultType = value.kind;
        response.runtimeCpuMs = Limits.getCpuTime() - phase;
        response.success = true;
      } catch (Exception error) {
        response.error = error.getMessage();
      } finally {
        response.logsJson = JSON.serialize(runtime == null ? new List<String>() : runtime.logs);
        response.steps = budget == null ? 0 : budget.steps;
        response.peakObservedHeapBytes = budget == null
          ? Limits.getHeapSize()
          : budget.peakObservedHeapBytes;
        response.cpuMs = Limits.getCpuTime() - started;
        JsBudget.current = prior;
        JsLibraryBuiltins.enabled = priorBuiltins;
        JsPromiseNatives.enabled = priorPromises;
      }
      responses.add(response);
    }
    return responses;
  }
}
