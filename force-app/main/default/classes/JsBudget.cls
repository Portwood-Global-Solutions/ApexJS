/** Cooperative limits reduce, but cannot remove, the risk of platform governor failures. */
public class JsBudget {
  public static JsBudget current;
  /** Trusted opt-in instrumentation; no change to normal limits or sampling policy. */
  public static Boolean trustedProfileHeap = false;
  public Integer heapMeasurementCpuMs = 0;
  public Integer largestHeapMeasurementCpuMs = 0;
  public Integer forcedGuards = 0;
  /** Opt-in scratch benchmark limits; never set by interpreted JavaScript or Flow inputs. */
  public class ParseLimits {
    public Integer sourceCharacters;
    public Integer tokens;
    public Integer nodes;
    public ParseLimits(Integer sourceCharacters, Integer tokens, Integer nodes) {
      if (
        sourceCharacters == null ||
        sourceCharacters < 1 ||
        sourceCharacters > 16777216 ||
        tokens == null ||
        tokens < 1 ||
        tokens > 1000000 ||
        nodes == null ||
        nodes < 1 ||
        nodes > 1000000
      ) {
        throw new JsException('BudgetError: Invalid trusted parse limits.');
      }
      this.sourceCharacters = sourceCharacters;
      this.tokens = tokens;
      this.nodes = nodes;
    }
  }
  public static ParseLimits trustedParseLimits;
  /** Trusted Apex trusted override; never supplied by interpreted JavaScript or Flow. */
  public class ExecutionLimits {
    public Integer steps;
    public Integer allocations;
    public ExecutionLimits(Integer steps, Integer allocations) {
      if (
        steps == null ||
        steps < 1 ||
        steps > 10000000 ||
        allocations == null ||
        allocations < 1 ||
        allocations > 5000000
      )
        throw new JsException('BudgetError: Invalid trusted execution limits.');
      this.steps = steps;
      this.allocations = allocations;
    }
  }
  public static ExecutionLimits trustedExecutionLimits;
  public Integer maxSourceCharacters;
  public Integer maxTokens;
  public Integer maxAstNodes;
  public Integer sourceCharacters = 0;
  public Integer scannedCharacters = 0;
  public Integer tokenCount = 0;
  public Integer nodeCount = 0;
  public Integer lexerCpuMs = 0;
  public Integer parserCpuMs = 0;
  public Boolean lexerCompleted = false;
  public Boolean parserCompleted = false;
  public static final Integer HEAP_SAMPLE_STEPS = 256;
  public static final Integer HEAP_SAMPLE_ALLOCATIONS = 512;
  public static final Integer PARSE_HEAP_SAMPLE_OBJECTS = 512;
  public Integer parseHeapSampleObjects = PARSE_HEAP_SAMPLE_OBJECTS;
  public void configureParseHeapSampling(Integer interval) {
    if (interval == null || interval < 32 || interval > 8192)
      throw new JsException('BudgetError: Invalid parser heap sampling interval.');
    parseHeapSampleObjects = interval;
  }
  public Integer heapSampleSteps = HEAP_SAMPLE_STEPS;
  public Integer heapSampleAllocations = HEAP_SAMPLE_ALLOCATIONS;
  /** Trusted host policy tuning, never read from JS values or artifact metadata. */
  public void configureHeapSampling(Integer stepInterval, Integer allocationInterval) {
    if (
      stepInterval == null ||
      stepInterval < 32 ||
      stepInterval > 8192 ||
      allocationInterval == null ||
      allocationInterval < 1 ||
      allocationInterval > 512
    )
      throw new JsException('BudgetError: Invalid heap sampling policy.');
    heapSampleSteps = stepInterval;
    heapSampleAllocations = allocationInterval;
  }
  public Integer heapChecks = 0;
  public Integer cpuChecks = 0;
  public Integer steps = 0;
  public Integer allocated = 0;
  public Integer heapLimitBytes;
  public Integer cpuLimitMs;
  public Integer heapReserveBytes;
  public Integer cpuReserveMs;
  public Integer peakObservedHeapBytes = 0;
  private Integer maximum;
  private Integer allocationMaximum;
  private Integer nextGuardStep = 32;
  private Integer lastHeapStep = 0;
  private Integer lastHeapAllocation = 0;
  public JsBudget(Integer maximum) {
    heapLimitBytes = Limits.getLimitHeapSize();
    cpuLimitMs = Limits.getLimitCpuTime();
    Boolean asynchronous = cpuLimitMs > 10000;
    maxSourceCharacters = trustedParseLimits == null
      ? (asynchronous ? 1048576 : 262144)
      : trustedParseLimits.sourceCharacters;
    maxTokens = trustedParseLimits == null
      ? (asynchronous ? 200000 : 32768)
      : trustedParseLimits.tokens;
    maxAstNodes = trustedParseLimits == null
      ? (asynchronous ? 100000 : 16384)
      : trustedParseLimits.nodes;
    if (maximum == null) {
      maximum = 10000;
    }
    Integer stepCeiling = trustedExecutionLimits == null ? 500000 : trustedExecutionLimits.steps;
    if (maximum < 1 || maximum > stepCeiling) {
      throw new JsException('BudgetError: maxSteps must be between 1 and ' + stepCeiling + '.');
    }
    this.maximum = maximum;
    allocationMaximum = Math.max(
      5000,
      Math.min(
        trustedExecutionLimits == null ? 125000 : trustedExecutionLimits.allocations,
        maximum / 4
      )
    );
    heapReserveBytes = Math.max(500000, heapLimitBytes / 10);
    cpuReserveMs = Math.max(750, cpuLimitMs / 10);
    guard();
    current = this;
  }
  public void tick() {
    steps++;
    if (steps > maximum) {
      throw new JsException('BudgetError: Instruction budget exceeded.');
    }
    if (steps >= nextGuardStep) {
      nextGuardStep = steps + 32;
      poll();
    }
  }
  /** Fused VM instructions retain their original logical operation cost. */
  public void tick(Integer cost) {
    steps += cost;
    if (steps > maximum)
      throw new JsException('BudgetError: Instruction budget exceeded.');
    if (steps >= nextGuardStep) {
      nextGuardStep = steps + 32;
      poll();
    }
  }
  public void allocate(Integer count) {
    allocated += count;
    if (allocated > allocationMaximum) {
      throw new JsException('BudgetError: Value allocation budget exceeded.');
    }
    if (allocated - lastHeapAllocation >= heapSampleAllocations) {
      guard();
    }
  }
  /** Host JSON admission checks the same remaining value capacity before native decoding. */
  public Integer remainingAllocations() {
    return allocationMaximum - allocated;
  }
  private void checkCpu() {
    cpuChecks++;
    if (Limits.getCpuTime() > cpuLimitMs - cpuReserveMs) {
      throw new JsException('BudgetError: Transaction CPU reserve reached.');
    }
  }
  /** Cheap hot-path checks; expensive heap traversal is sampled separately. */
  public void poll() {
    checkCpu();
    if (
      steps - lastHeapStep >= heapSampleSteps ||
      allocated - lastHeapAllocation >= heapSampleAllocations
    ) {
      sampleHeap();
    }
  }
  /** Force both checks at parse boundaries and bounded large allocations. */
  public void guard() {
    forcedGuards++;
    checkCpu();
    sampleHeap();
  }
  private void sampleHeap() {
    heapChecks++;
    Integer started = trustedProfileHeap ? Limits.getCpuTime() : null;
    Integer observedHeap = Limits.getHeapSize();
    if (started != null) {
      Integer elapsed = Limits.getCpuTime() - started;
      heapMeasurementCpuMs += elapsed;
      largestHeapMeasurementCpuMs = Math.max(largestHeapMeasurementCpuMs, elapsed);
    }
    lastHeapStep = steps;
    lastHeapAllocation = allocated;
    peakObservedHeapBytes = Math.max(peakObservedHeapBytes, observedHeap);
    if (observedHeap > heapLimitBytes - heapReserveBytes) {
      throw new JsException('BudgetError: Transaction heap reserve reached.');
    }
  }
}
