/** Test-only AST conformance harness. No Flow action is exposed. */
@IsTest
public with sharing class JsAstTestSupport {
  public class Request {
    public String source;
    public String inputJson;
    public Integer maxSteps;
    public Request() {
    }
  }
  public class Response {
    public Boolean success;
    public String resultJson;
    public String resultType;
    public String logsJson;
    public String error;
    public Integer steps;
    public Integer cpuMs;
    public Integer heapBytes;
    public Integer heapLimitBytes;
    public Integer cpuLimitMs;
    public Integer peakObservedHeapBytes;
    public Response() {
    }
  }

  public static List<Response> run(List<Request> requests) {
    List<Response> results = new List<Response>();
    if (requests == null) {
      return results;
    }
    String previousSource;
    JsNode previousProgram;
    for (Request request : requests) {
      Integer startCpu = Limits.getCpuTime();
      Integer startHeap = Limits.getHeapSize();
      Response response = new Response();
      response.success = false;
      JsBudget budget;
      JsRuntime runtime;
      try {
        if (request == null) {
          throw new JsException('TypeError: Request cannot be null.');
        }
        budget = new JsBudget(request.maxSteps);
        JsNode program;
        if (request.source != null && request.source.equals(previousSource)) {
          program = previousProgram;
        } else {
          program = new JsParser(new JsLexer(request.source, budget).scan(), budget).parse();
          previousSource = request.source;
          previousProgram = program;
        }
        budget.guard();
        JsValue input = JsCodec.parse(
          request.inputJson == null ? 'null' : request.inputJson,
          budget
        );
        runtime = new JsRuntime(budget);
        JsValue value = runtime.run(program, input);
        response.resultJson = JsCodec.stringify(value, budget, runtime);
        response.resultType = value.kind;
        response.success = true;
      } catch (JsThrownException ex) {
        response.error = ex.getMessage();
      } catch (JsException ex) {
        response.error = ex.getMessage();
      } catch (Exception ex) {
        response.error = 'ExecutionError: ' + ex.getMessage();
      }
      response.logsJson = JSON.serialize(runtime == null ? new List<String>() : runtime.logs);
      response.steps = budget == null ? 0 : budget.steps;
      response.heapLimitBytes = Limits.getLimitHeapSize();
      response.cpuLimitMs = Limits.getLimitCpuTime();
      response.peakObservedHeapBytes = budget == null
        ? Limits.getHeapSize()
        : budget.peakObservedHeapBytes;
      response.cpuMs = Limits.getCpuTime() - startCpu;
      response.heapBytes = Limits.getHeapSize() - startHeap;
      results.add(response);
    }
    return results;
  }
}
