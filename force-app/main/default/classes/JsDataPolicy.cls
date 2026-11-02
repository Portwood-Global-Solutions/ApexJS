/** Shared JSON admission and naming rules for the public data boundary. */
public class JsDataPolicy {
  public static final Integer MAX_JSON_CHARACTERS = 524288;
  public static void validateName(String name) {
    if (
      String.isBlank(name) ||
      !Pattern.matches('[A-Za-z][A-Za-z0-9_]*', name) ||
      new Set<String>{ 'constructor', 'prototype' }.contains(name)
    )
      throw new JsException(
        'InputError: Names must start with a letter and contain only letters, numbers, or underscores; constructor and prototype are reserved.'
      );
  }
  public static Map<String, Object> parseObject(String payload) {
    if (String.isBlank(payload))
      throw new JsException('InputError: Input JSON is empty.');
    if (payload.length() > MAX_JSON_CHARACTERS)
      throw new JsException(
        'BudgetError: Input JSON exceeds ' + MAX_JSON_CHARACTERS + ' characters.'
      );
    preflight(
      payload,
      JsBudget.current == null ? 25000 : JsBudget.current.remainingAllocations(),
      0
    );
    Object value = JSON.deserializeUntyped(payload);
    if (!(value instanceof Map<String, Object>))
      throw new JsException('InputError: Input JSON must be an object.');
    Map<String, Object> result = (Map<String, Object>) value;
    for (String name : result.keySet())
      validateName(name);
    return result;
  }
  public static Integer preflight(String payload, Integer maximumNodes, Integer startingDepth) {
    JSONParser parser = JSON.createParser(payload);
    Integer nodes = 0, depth = startingDepth;
    JSONToken token;
    while ((token = parser.nextToken()) != null) {
      if (token == JSONToken.END_ARRAY || token == JSONToken.END_OBJECT) {
        depth--;
        continue;
      }
      if (token == JSONToken.FIELD_NAME)
        continue;
      if (depth > 32)
        throw new JsException('BudgetError: JSON nesting exceeded.');
      nodes++;
      if (nodes > maximumNodes)
        throw new JsException(
          'BudgetError: Value allocation budget exceeded before JSON decoding.'
        );
      if (token == JSONToken.START_ARRAY || token == JSONToken.START_OBJECT)
        depth++;
      if (Math.mod(nodes, 512) == 0 && JsBudget.current != null)
        JsBudget.current.guard();
    }
    if (nodes == 0)
      throw new JsException('SyntaxError: JSON value is required.');
    return nodes;
  }
}
