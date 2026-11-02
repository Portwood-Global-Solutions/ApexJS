/** Explicit value types keep JS equality, truthiness, and object identity out of Apex coercions. */
public class JsValue {
  public static Boolean trustedInfinityNumbers = false;
  public Boolean nanNumber = false;
  private static final Double FAST_FINITE_BOUND = Double.valueOf('9007199254740992');
  public String kind;
  public Object scalar;
  public Map<String, JsValue> props;
  public Map<String, JsValue> getters;
  // In arrays only, a null slot is an absent property (a hole), never JS undefined.
  public List<JsValue> items;
  public JsNode functionNode;
  public JsScope closure;
  public Integer bytecodeIndex;
  public JsBytecode.Environment bytecodeClosure;
  public JsMapStore.Index mapIndex;
  public Integer mapIdentity;
  public String nativeName;
  public List<Integer> bytes;
  public JsBytePages bytePages;
  public Integer byteOffset = 0, byteLength;
  public List<Double> words;
  public JsIntegerPages wordPages;
  public JsPromiseNatives.State promiseState;
  public JsPromiseNatives.Capability promiseCapability;
  public Integer wordOffset = 0, wordLength = 0;
  public String pattern;
  public String flags;
  public Pattern compiledRegex;
  public Long dateMilliseconds;
  public String errorName = 'Error';
  public Boolean hasErrorMessage = false;
  public JsValue byteBuffer;
  public List<JsMapIteration.Entry> mapHistory, mapRecords;
  public JsValue iteratorMap;
  public String iteratorType;
  public Integer iteratorCursor = 0;
  public Boolean iteratorFinished = false;
  public JsValue prototypeParent;
  public Boolean explicitPrototype = false;
  public JsValue constructorPrototype;
  public Set<String> hiddenKeys;
  public Set<String> readOnlyKeys;
  public Set<String> fixedKeys;

  public JsValue(String kind) {
    this.kind = kind;
    if (kind == 'object') {
      props = new Map<String, JsValue>();
    }
    if (kind == 'array' || kind == 'map') {
      items = new List<JsValue>();
    }
    if (kind == 'typedarray')
      words = new List<Double>();
    if (kind == 'uint8array' || kind == 'blob' || kind == 'arraybuffer') {
      bytes = new List<Integer>();
    }
  }
  public static JsValue num(Double value) {
    // Common finite values need no decimal string allocation merely to validate them.
    Boolean isNan = false;
    if (!(value != null && value >= -FAST_FINITE_BOUND && value <= FAST_FINITE_BOUND)) {
      String representation = String.valueOf(value);
      isNan = representation.contains('NaN');
      if (
        representation.contains('NaN') && !JsPromiseNatives.enabled ||
        representation.contains('Infinity') && !trustedInfinityNumbers
      )
        throw new JsException('RangeError: Non-finite numbers are outside this subset.');
    }
    JsValue result = new JsValue('number');
    result.scalar = value;
    result.nanNumber = isNan;
    return result;
  }
  public static JsValue str(String value) {
    if (value.length() > 65536) {
      throw new JsException('BudgetError: String size exceeded.');
    }
    if (value.length() >= 4096 && JsBudget.current != null) {
      JsBudget.current.guard();
    }
    JsValue result = new JsValue('string');
    result.scalar = value;
    return result;
  }
  public static JsValue bool(Boolean value) {
    JsValue result = new JsValue('boolean');
    result.scalar = value;
    return result;
  }
  public static JsValue nativeFunction(String name) {
    JsValue result = new JsValue('native');
    result.nativeName = name;
    return result;
  }
  public Boolean enumerable(String key) {
    return hiddenKeys == null || !hiddenKeys.contains(key);
  }
  public Boolean writable(String key) {
    return readOnlyKeys == null || !readOnlyKeys.contains(key);
  }
  public Boolean configurable(String key) {
    return fixedKeys == null || !fixedKeys.contains(key);
  }
  public void attributes(String key, Boolean enumerable, Boolean writable, Boolean configurable) {
    if (!enumerable && hiddenKeys == null) {
      hiddenKeys = new Set<String>();
    }
    if (!writable && readOnlyKeys == null) {
      readOnlyKeys = new Set<String>();
    }
    if (!configurable && fixedKeys == null) {
      fixedKeys = new Set<String>();
    }
    if (hiddenKeys != null) {
      if (enumerable)
        hiddenKeys.remove(key);
      else
        hiddenKeys.add(key);
    }
    if (readOnlyKeys != null) {
      if (writable)
        readOnlyKeys.remove(key);
      else
        readOnlyKeys.add(key);
    }
    if (fixedKeys != null) {
      if (configurable)
        fixedKeys.remove(key);
      else
        fixedKeys.add(key);
    }
  }
  public Boolean truthy() {
    if (kind == 'undefined' || kind == 'null') {
      return false;
    }
    if (kind == 'boolean') {
      return (Boolean) scalar;
    }
    if (kind == 'number') {
      return !nanNumber && Math.abs((Double) scalar) != 0;
    }
    if (kind == 'string') {
      return ((String) scalar).length() > 0;
    }
    return true;
  }
  public String asString() {
    if (kind == 'error') {
      String name = props != null && props.containsKey('name')
        ? props.get('name').asString()
        : errorName;
      String message = props != null && props.containsKey('message')
        ? props.get('message').asString()
        : (String) scalar;
      return name == '' ? message : message == '' ? name : name + ': ' + message;
    }
    if (kind == 'undefined' || kind == 'null') {
      return kind;
    }
    if (kind == 'string') {
      return (String) scalar;
    }
    if (kind == 'boolean') {
      return (Boolean) scalar ? 'true' : 'false';
    }
    if (kind == 'number') {
      if (Math.abs((Double) scalar) == 0)
        return '0';
      String text = String.valueOf(scalar);
      return text.endsWith('.0') ? text.substring(0, text.length() - 2) : text;
    }
    throw new JsException(
      'TypeError: Implicit object-to-string conversion is outside this subset.'
    );
  }
  public Double asNumber() {
    if (kind == 'date' && JsLibraryBuiltins.enabled && dateMilliseconds != null)
      return Double.valueOf(dateMilliseconds);
    if (kind != 'number') {
      throw new JsException('TypeError: Expected a number.');
    }
    return (Double) scalar;
  }
}
