/** The interpreter boundary accepts JSON data, never live sObjects or Apex instances. */
public class JsCodec {
  private class ExportCounter {
    public Integer chars = 0;
    private Integer maximum;
    ExportCounter(Integer maximum) {
      this.maximum = maximum;
    }
    public void add(Integer count) {
      chars += count;
      if (chars > maximum) {
        throw new JsException(
          'BudgetError: JSON output size exceeded (maximum ' + maximum + ' characters).'
        );
      }
    }
  }
  /** Host-only import of already validated JSON data. Never receives live Apex objects. */
  public static JsValue fromJsonData(Object raw, JsBudget budget) {
    budget.guard();
    return importValue(raw, budget, 0);
  }
  public static JsValue parse(String source, JsBudget budget) {
    if (source == null || source.length() > 65536) {
      throw new JsException('BudgetError: JSON.parse input must be at most 65536 characters.');
    }
    Object raw;
    try {
      JsDataPolicy.preflight(source, budget.remainingAllocations(), 0);
      raw = JSON.deserializeUntyped(source);
    } catch (JsException ex) {
      throw ex;
    } catch (Exception ex) {
      throw new JsException('SyntaxError: Invalid JSON.');
    }
    return importValue(raw, budget, 0);
  }
  private static JsValue importValue(Object raw, JsBudget budget, Integer depth) {
    budget.tick();
    budget.allocate(1);
    if (depth > 32) {
      throw new JsException('BudgetError: JSON nesting exceeded.');
    }
    if (raw == null) {
      return new JsValue('null');
    }
    if (raw instanceof String) {
      return JsValue.str((String) raw);
    }
    if (raw instanceof Boolean) {
      return JsValue.bool((Boolean) raw);
    }
    if (raw instanceof List<Object>) {
      JsValue result = new JsValue('array');
      for (Object child : (List<Object>) raw) {
        result.items.add(importValue(child, budget, depth + 1));
      }
      return result;
    }
    if (raw instanceof Map<String, Object>) {
      JsValue result = new JsValue('object');
      for (String key : ((Map<String, Object>) raw).keySet()) {
        result.props.put(key, importValue(((Map<String, Object>) raw).get(key), budget, depth + 1));
      }
      return result;
    }
    return JsValue.num(Double.valueOf(String.valueOf(raw)));
  }
  public static String stringify(JsValue value, JsBudget budget) {
    return stringify(value, budget, null);
  }
  public static String stringify(JsValue value, JsBudget budget, JsRuntime runtime) {
    return stringify(value, budget, runtime, 65536);
  }
  public static String stringify(
    JsValue value,
    JsBudget budget,
    JsRuntime runtime,
    Integer maximum
  ) {
    if (maximum == null || maximum < 1 || maximum > 1048576)
      throw new JsException('BudgetError: Invalid JSON output policy.');
    String result = exportJson(
      value,
      budget,
      new Set<JsValue>(),
      0,
      new ExportCounter(maximum),
      runtime
    );
    budget.guard();
    return result;
  }
  public static String finiteNumberText(Double value) {
    return numberToken(String.valueOf(value));
  }
  private static String numberToken(String token) {
    Boolean negative = token.startsWith('-');
    String text = negative ? token.substring(1) : token;
    List<String> exponent = text.toLowerCase().split('e');
    String mantissa = exponent[0];
    Integer dot = mantissa.indexOf('.');
    Integer position =
      (dot < 0 ? mantissa.length() : dot) +
      (exponent.size() == 1 ? 0 : Integer.valueOf(exponent[1]));
    String digits = mantissa.replace('.', '');
    while (digits.length() > 1 && digits.startsWith('0')) {
      digits = digits.substring(1);
      position--;
    }
    while (digits.length() > 1 && digits.endsWith('0'))
      digits = digits.substring(0, digits.length() - 1);
    if (digits == '0')
      return '0';
    String result;
    if (position > 0 && position <= 21) {
      if (digits.length() > position)
        result = digits.substring(0, position) + '.' + digits.substring(position);
      else {
        result = digits;
        while (result.length() < position)
          result += '0';
      }
    } else if (position <= 0 && position > -6) {
      result = '0.';
      for (Integer i = 0; i < -position; i++)
        result += '0';
      result += digits;
    } else
      result =
        digits.substring(0, 1) +
        (digits.length() > 1 ? '.' + digits.substring(1) : '') +
        'e' +
        (position > 0 ? '+' : '') +
        String.valueOf(position - 1);
    return (negative ? '-' : '') + result;
  }
  private static String exportJson(
    JsValue value,
    JsBudget budget,
    Set<JsValue> ancestors,
    Integer depth,
    ExportCounter size,
    JsRuntime runtime
  ) {
    budget.tick();
    if (depth > 32)
      throw new JsException('BudgetError: JSON nesting exceeded.');
    if (
      value == null ||
      value.kind == 'undefined' ||
      value.kind == 'null' ||
      value.kind == 'function' ||
      value.kind == 'native'
    ) {
      size.add(4);
      return 'null';
    }
    if (value.kind == 'number') {
      String representation = String.valueOf(value.scalar);
      if (value.nanNumber || representation.contains('Infinity')) {
        size.add(4);
        return 'null';
      }
      String token = numberToken(representation);
      size.add(token.length());
      return token;
    }
    if (value.kind == 'string' || value.kind == 'boolean') {
      String token = JSON.serialize(value.scalar);
      size.add(token.length());
      return token;
    }
    if (ancestors.contains(value))
      throw new JsException('TypeError: Cannot serialize a cyclic value.');
    ancestors.add(value);
    size.add(2);
    List<String> parts = new List<String>();
    Boolean arrayValue = value.kind == 'array';
    if (arrayValue) {
      for (Integer i = 0; i < value.items.size(); i++) {
        if (i > 0)
          size.add(1);
        JsValue child = value.items[i];
        if (child == null && runtime != null)
          child = runtime.getProperty(value, String.valueOf(i));
        parts.add(exportJson(child, budget, ancestors, depth + 1, size, runtime));
      }
    } else if (value.kind == 'uint8array' || JsTypedBuffers.typed(value)) {
      Integer length = JsTypedBuffers.typed(value) ? value.wordLength : JsBytes.length(value);
      for (Integer i = 0; i < length; i++) {
        budget.tick();
        String key = JSON.serialize(String.valueOf(i)),
          token = numberToken(
            String.valueOf(
              JsTypedBuffers.typed(value)
                ? JsTypedBuffers.element(value, i)
                : Double.valueOf(JsBytes.read(value, i))
            )
          );
        size.add(key.length() + 1 + token.length() + (i == 0 ? 0 : 1));
        parts.add(key + ':' + token);
      }
    } else if (value.props != null) {
      for (String key : JsObjectNatives.orderedDataKeys(value)) {
        budget.tick();
        if (!value.enumerable(key))
          continue;
        JsValue child = value.props.get(key);
        if (value.getters != null && value.getters.containsKey(key)) {
          if (runtime == null)
            throw new JsException('TypeError: Getter serialization requires an active runtime.');
          child = runtime.getProperty(value, key);
        }
        if (child.kind == 'undefined' || child.kind == 'function' || child.kind == 'native')
          continue;
        String encoded = JSON.serialize(key);
        size.add(encoded.length() + 1 + (parts.isEmpty() ? 0 : 1));
        parts.add(encoded + ':' + exportJson(child, budget, ancestors, depth + 1, size, runtime));
      }
    }
    ancestors.remove(value);
    return (arrayValue ? '[' : '{') + String.join(parts, ',') + (arrayValue ? ']' : '}');
  }
}
