/** Copy named inputs once at the JS boundary. Flow binds resources; Apex never looks up a resource name. */
public class JsDirectInputs {
  private static final Map<String, Object> BOUNDARIES = new Map<String, Object>{
    'Date' => Date.newInstance(1900, 1, 1),
    'DateTime' => Datetime.newInstanceGmt(1900, 1, 1, 0, 0, 0),
    'Text' => '__js_flow_boundary__',
    'Number' => Decimal.valueOf('0'),
    'Boolean' => false
  };
  private class NativeValues {
    Map<String, List<Object>> lanes = new Map<String, List<Object>>();
    Map<String, Integer> offsets = new Map<String, Integer>();
    Integer groupIndex = 0;
    List<Integer> sizes;
    NativeValues(JsCollectionScriptAction.Request request) {
      for (String kind : BOUNDARIES.keySet()) {
        lanes.put(kind, new List<Object>());
        offsets.put(kind, 0);
      }
      sizes = request.inputSizes == null ? new List<Integer>() : request.inputSizes.sizes;
      if (request.nativeDates != null)
        for (Date value : request.nativeDates)
          lanes.get('Date').add(value);
      if (request.nativeDateTimes != null)
        for (Datetime value : request.nativeDateTimes)
          lanes.get('DateTime').add(value);
      if (request.nativeTexts != null)
        for (String value : request.nativeTexts)
          lanes.get('Text').add(value);
      if (request.nativeNumbers != null)
        for (Decimal value : request.nativeNumbers)
          lanes.get('Number').add(value);
      if (request.nativeBooleans != null)
        for (Boolean value : request.nativeBooleans)
          lanes.get('Boolean').add(value);
    }
    Object take(JsFlowNamedInput row) {
      Integer count = 1;
      if (row.isCollection != false) {
        if (sizes == null || groupIndex >= sizes.size())
          throw new JsException(
            'InputError: Native input sizes are missing. Reopen and save the action.'
          );
        count = sizes[groupIndex++];
      }
      List<Object> values = lanes.get(row.kind);
      Integer offset = offsets.get(row.kind);
      if (
        values == null ||
        count == null ||
        count < 0 ||
        (row.isCollection == false &&
        count != 1) ||
        count > values.size() - offset
      )
        throw new JsException('InputError: Invalid native input size for ' + row.name + '.');
      List<Object> selected = new List<Object>();
      for (Integer i = 0; i < count; i++)
        selected.add(values[offset++]);
      // An unset Flow resource can contribute a null placeholder instead of an empty array.
      if (count == 0 && offset < values.size() && values[offset] == null)
        offset++;
      if (offset >= values.size() || values[offset] != BOUNDARIES.get(row.kind))
        throw new JsException(
          'InputError: Native input boundaries do not match ' +
            row.name +
            '. Reopen and save the action.'
        );
      offsets.put(row.kind, offset + 1);
      return row.isCollection == false ? selected[0] : selected;
    }
    void finish() {
      if (sizes != null && groupIndex != sizes.size())
        throw new JsException(
          'InputError: Unmatched native input sizes. Reopen and save the action.'
        );
      for (String kind : lanes.keySet())
        if (offsets.get(kind) != lanes.get(kind).size())
          throw new JsException(
            'InputError: Unmatched native input data. Reopen and save the action.'
          );
    }
  }
  public static Map<String, Object> prepare(List<JsFlowNamedInput> inputs) {
    JsCollectionScriptAction.Request request = new JsCollectionScriptAction.Request();
    request.namedInputs = inputs;
    return prepare(request);
  }
  public static Map<String, Object> prepare(JsCollectionScriptAction.Request request) {
    List<JsFlowNamedInput> inputs = request.namedInputs;
    if (inputs == null)
      inputs = new List<JsFlowNamedInput>();
    Map<String, Object> result = new Map<String, Object>();
    Integer characters = 2,
      remaining = (JsBudget.current == null ? 25000 : JsBudget.current.remainingAllocations()) - 1;
    NativeValues nativeValues = new NativeValues(request);
    for (JsFlowNamedInput row : inputs) {
      if (row == null)
        throw new JsException('InputError: A data entry is missing.');
      JsDataPolicy.validateName(row.name);
      if (result.containsKey(row.name))
        throw new JsException('InputError: Duplicate input name: ' + row.name + '.');
      Boolean collection = row.isCollection != false,
        isTemporal = row.kind == 'Date' || row.kind == 'DateTime',
        nativeInput = isTemporal || row.resource != null;
      Map<String, Object> collections = new Map<String, Object>{
        'Records' => row.records,
        'Text' => row.texts,
        'Number' => row.numbers,
        'Boolean' => row.booleans,
        'Date' => row.dates,
        'DateTime' => row.dateTimes
      };
      Map<String, Object> scalars = new Map<String, Object>{
        'Records' => row.recordValue,
        'Text' => row.textValue,
        'Number' => row.numberValue,
        'Boolean' => row.booleanValue
      };
      if (!collections.containsKey(row.kind) && row.kind != 'JSON')
        throw new JsException('InputError: Choose a supported type for ' + row.name + '.');
      for (String kind : collections.keySet())
        if (collections.get(kind) != null && (!collection || kind != row.kind || nativeInput))
          throw new JsException('InputError: Supply only the selected type for ' + row.name + '.');
      for (String kind : scalars.keySet())
        if (
          scalars.get(kind) != null &&
          (collection ||
          kind != row.kind ||
          row.isLiteral == true ||
          nativeInput)
        )
          throw new JsException('InputError: Supply only the selected type for ' + row.name + '.');
      Object selected;
      String payload;
      if (nativeInput)
        selected = nativeValues.take(row);
      else if (row.isLiteral == true || row.kind == 'JSON') {
        if (String.isBlank(row.valueJson))
          throw new JsException('InputError: A value is required for ' + row.name + '.');
        payload = row.valueJson;
      } else {
        if (row.valueJson != null)
          throw new JsException('InputError: Supply only the selected value for ' + row.name + '.');
        selected = collection ? collections.get(row.kind) : scalars.get(row.kind);
        if (collection && selected == null)
          selected = new List<Object>();
      }
      if (payload == null)
        payload = JSON.serialize(selected);
      characters +=
        JSON.serialize(row.name).length() +
        1 +
        payload.length() +
        (result.isEmpty() ? 0 : 1);
      if (characters > JsDataPolicy.MAX_JSON_CHARACTERS)
        throw new JsException(
          'BudgetError: Named input JSON exceeds ' +
            JsDataPolicy.MAX_JSON_CHARACTERS +
            ' characters.'
        );
      remaining -= JsDataPolicy.preflight(payload, remaining, 1);
      Object decoded = JSON.deserializeUntyped(payload);
      if (row.isLiteral == true && !isTemporal) {
        Boolean numberValue =
          decoded instanceof Decimal ||
          decoded instanceof Integer ||
          decoded instanceof Long ||
          decoded instanceof Double;
        if (
          collection ||
          !(row.kind == 'Text' && decoded instanceof String ||
          row.kind == 'Number' && numberValue ||
          row.kind == 'Boolean' && decoded instanceof Boolean)
        )
          throw new JsException(
            'InputError: Literal value has the wrong type for ' + row.name + '.'
          );
      }
      result.put(row.name, decoded);
      if (JsBudget.current != null)
        JsBudget.current.guard();
    }
    nativeValues.finish();
    return result;
  }
}
