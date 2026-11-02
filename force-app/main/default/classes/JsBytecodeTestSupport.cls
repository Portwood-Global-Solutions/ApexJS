/** Test-only bytecode admission and execution harness. */
@IsTest
public class JsBytecodeTestSupport {
  public static Map<String, Integer> lastTimings;
  public class Request {
    public String programJson;
    public String inputJson;
    public Integer maxSteps;
  }
  public static List<JsAstTestSupport.Response> run(List<Request> requests) {
    List<JsAstTestSupport.Response> results = new List<JsAstTestSupport.Response>();
    for (Request request : requests) {
      JsAstTestSupport.Response result = new JsAstTestSupport.Response();
      result.success = false;
      JsBudget prior = JsBudget.current, budget;
      JsRuntime runtime;
      Integer started = Limits.getCpuTime();
      try {
        budget = new JsBudget(request.maxSteps);
        Integer phase = Limits.getCpuTime();
        JsBytecode.Program program = JsBytecode.load(request.programJson, budget);
        lastTimings = new Map<String, Integer>{
          'loadAndValidateCpuMs' => Limits.getCpuTime() - phase
        };
        runtime = new JsRuntime(budget);
        JsValue input = JsCodec.parse(
          request.inputJson == null ? 'null' : request.inputJson,
          budget
        );
        JsValue value = new JsBytecode(program, runtime).run(input);
        result.resultJson = JsCodec.stringify(value, budget, runtime);
        result.resultType = value.kind;
        result.success = true;
      } catch (Exception error) {
        result.error = error.getMessage();
      } finally {
        result.steps = budget == null ? 0 : budget.steps;
        result.cpuMs = Limits.getCpuTime() - started;
        result.logsJson = JSON.serialize(runtime == null ? new List<String>() : runtime.logs);
        JsBudget.current = prior;
      }
      results.add(result);
    }
    return results;
  }
  public static List<JsAstTestSupport.Response> runCompact(List<Request> requests) {
    Boolean prior = JsBytecode.trustedCompactCode;
    JsBytecode.trustedCompactCode = true;
    try {
      return run(requests);
    } finally {
      JsBytecode.trustedCompactCode = prior;
    }
  }
  public static List<JsAstTestSupport.Response> runPaged(List<Request> requests) {
    Boolean prior = JsBytecode.trustedCompactCode, priorPaged = JsTypedBuffers.trustedPagedStorage;
    JsBytecode.trustedCompactCode = true;
    JsTypedBuffers.trustedPagedStorage = true;
    try {
      return run(requests);
    } finally {
      JsBytecode.trustedCompactCode = prior;
      JsTypedBuffers.trustedPagedStorage = priorPaged;
    }
  }
}
