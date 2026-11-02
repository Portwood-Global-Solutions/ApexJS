/** Strict JSON-to-Flow type adapter. No JavaScript or database execution in this action. */
public with sharing class JsResultAction {
  public class Request {
    @InvocableVariable(required=true label='JavaScript result JSON')
    public String resultJson;
    @InvocableVariable(label='Result path (e.g. summary.total or rows[0].amount)')
    public String path;
    @InvocableVariable(required=true label='Flow result type')
    public String outputType;
    @InvocableVariable(label='Object API name for Records output')
    public String objectApiName;
  }
  public class Response {
    @InvocableVariable
    public Boolean success;
    @InvocableVariable
    public Boolean found;
    @InvocableVariable
    public Boolean isNull;
    @InvocableVariable
    public String error;
    @InvocableVariable
    public String jsonValue;
    @InvocableVariable
    public String textValue;
    @InvocableVariable
    public Decimal numberValue;
    @InvocableVariable
    public Boolean booleanValue;
    @InvocableVariable
    public Date dateValue;
    @InvocableVariable
    public Datetime dateTimeValue;
    @InvocableVariable
    public List<String> textValues;
    @InvocableVariable
    public List<Decimal> numberValues;
    @InvocableVariable
    public List<Boolean> booleanValues;
    @InvocableVariable
    public List<Date> dateValues;
    @InvocableVariable
    public List<Datetime> dateTimeValues;
    @InvocableVariable
    public List<SObject> records;
  }
  private static Set<String> types = new Set<String>{
    'Text',
    'Number',
    'Boolean',
    'Date',
    'DateTime',
    'TextCollection',
    'NumberCollection',
    'BooleanCollection',
    'DateCollection',
    'DateTimeCollection',
    'Records',
    'JSON'
  };
  private static List<String> segments(String path) {
    if (String.isBlank(path) || path == '$')
      return new List<String>();
    if (path.length() > 512)
      throw new JsException('PathError: Result path exceeds 512 characters.');
    List<String> result = new List<String>();
    if (path.startsWith('/')) {
      for (String token : path.substring(1).split('/', -1)) {
        if (Pattern.compile('~(?![01])').matcher(token).find())
          throw new JsException('PathError: Invalid JSON Pointer escape.');
        result.add(token.replace('~1', '/').replace('~0', '~'));
      }
    } else {
      String source = path.startsWith('$.') ? path.substring(2) : path;
      Matcher m = Pattern.compile('([A-Za-z_][A-Za-z0-9_]*|\\[(0|[1-9][0-9]*)\\])').matcher(source);
      Integer at = 0;
      while (m.find()) {
        String token = m.group();
        String gap = source.substring(at, m.start());
        if (at == 0 ? gap != '' : (token.startsWith('[') ? gap != '' : gap != '.'))
          throw new JsException('PathError: Use fields, [index], or a JSON Pointer.');
        result.add(token.startsWith('[') ? token.substring(1, token.length() - 1) : token);
        at = m.end();
      }
      if (result.isEmpty() || at != source.length())
        throw new JsException('PathError: Malformed result path.');
    }
    if (result.size() > 32)
      throw new JsException('PathError: Result path exceeds 32 segments.');
    return result;
  }
  private static Object atPath(Object value, String path) {
    for (String key : segments(path)) {
      if (value instanceof Map<String, Object>) {
        Map<String, Object> row = (Map<String, Object>) value;
        if (!row.containsKey(key))
          throw new JsException('PathError: Missing result field ' + key + '.');
        value = row.get(key);
      } else if (value instanceof List<Object>) {
        if (!Pattern.matches('0|[1-9][0-9]*', key) || key.length() > 6)
          throw new JsException('PathError: Invalid array index.');
        Integer index = Integer.valueOf(key);
        List<Object> rows = (List<Object>) value;
        if (index >= rows.size())
          throw new JsException('PathError: Array index out of range.');
        value = rows[index];
      } else
        throw new JsException('PathError: Cannot traverse a scalar or null.');
    }
    return value;
  }
  private static Decimal numeric(Object value) {
    if (
      !(value instanceof Decimal) &&
      !(value instanceof Integer) &&
      !(value instanceof Long) &&
      !(value instanceof Double)
    )
      throw new JsException('TypeError: Expected a JSON number.');
    return Decimal.valueOf(String.valueOf(value));
  }
  private static String text(Object value) {
    if (!(value instanceof String))
      throw new JsException('TypeError: Expected a JSON string.');
    return (String) value;
  }
  private static Boolean bool(Object value) {
    if (!(value instanceof Boolean))
      throw new JsException('TypeError: Expected a JSON boolean.');
    return (Boolean) value;
  }
  private static Date dateValue(Object value) {
    String textValue = text(value);
    if (!Pattern.matches('[0-9]{4}-[0-9]{2}-[0-9]{2}', textValue))
      throw new JsException('TypeError: Date must use YYYY-MM-DD.');
    return Date.valueOf(textValue);
  }
  private static Datetime dateTimeValue(Object value) {
    String textValue = text(value);
    if (
      !Pattern.matches(
        '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(\\.[0-9]{3})?Z',
        textValue
      )
    )
      throw new JsException('TypeError: DateTime must be an ISO UTC string.');
    return (Datetime) JSON.deserialize(JSON.serialize(textValue), Datetime.class);
  }
  private static List<SObject> records(Object value, String objectApiName) {
    if (String.isBlank(objectApiName))
      throw new JsException('TypeError: Records output requires an object API name.');
    Schema.SObjectType target = Schema.getGlobalDescribe().get(objectApiName);
    if (target == null)
      throw new JsException('TypeError: Unknown output object.');
    Schema.DescribeSObjectResult description = target.getDescribe();
    String canonical = description.getName();
    Map<String, Schema.SObjectField> fields = description.fields.getMap();
    List<SObject> result = new List<SObject>();
    List<Object> rows = (List<Object>) value;
    if (rows.size() > 2000)
      throw new JsException('BudgetError: Record output exceeds 2000 rows.');
    for (Object raw : rows) {
      if (!(raw instanceof Map<String, Object>))
        throw new JsException('TypeError: Every output record must be an object.');
      Map<String, Object> row = (Map<String, Object>) raw;
      if (row.containsKey('attributes')) {
        if (!(row.get('attributes') instanceof Map<String, Object>))
          throw new JsException('TypeError: Invalid record attributes.');
        Object declared = ((Map<String, Object>) row.get('attributes')).get('type');
        if (declared != null && String.valueOf(declared) != canonical)
          throw new JsException('TypeError: Output record type does not match ' + canonical + '.');
      }
      JSONGenerator generator = JSON.createGenerator(false);
      generator.writeStartObject();
      generator.writeFieldName('attributes');
      generator.writeStartObject();
      generator.writeStringField('type', canonical);
      generator.writeEndObject();
      for (String field : row.keySet()) {
        if (field == 'attributes')
          continue;
        if (!fields.containsKey(field))
          throw new JsException('TypeError: Unknown ' + canonical + ' field ' + field + '.');
        Object cell = row.get(field);
        if (cell instanceof Map<String, Object> || cell instanceof List<Object>)
          throw new JsException('TypeError: Output records support flat fields only.');
        String name = fields.get(field).getDescribe().getName();
        if (name == 'Id' && cell != null) {
          Id recordId = Id.valueOf(text(cell));
          if (recordId.getSObjectType() != target)
            throw new JsException('TypeError: Record Id belongs to a different object.');
        }
        if (cell == null)
          generator.writeNullField(name);
        else
          generator.writeObjectField(name, cell);
      }
      generator.writeEndObject();
      result.add((SObject) JSON.deserialize(generator.getAsString(), SObject.class));
    }
    return result;
  }
  @InvocableMethod(
    label='Read JavaScript Result'
    category='ApexJS'
    configurationEditor='c-js-result-editor'
    description='Select a JSON path and return a strict Flow number, text, boolean, date, collection, or typed Salesforce record collection. No records are saved.'
  )
  public static List<Response> run(List<Request> requests) {
    List<Response> responses = new List<Response>();
    if (requests == null)
      return responses;
    for (Request request : requests) {
      Response response = new Response();
      response.success = false;
      response.found = false;
      response.isNull = false;
      try {
        if (
          request == null ||
          request.resultJson == null ||
          request.resultJson.length() > JsDataPolicy.MAX_JSON_CHARACTERS
        )
          throw new JsException(
            'BudgetError: Result JSON must be supplied and at most ' +
              JsDataPolicy.MAX_JSON_CHARACTERS +
              ' characters.'
          );
        if (!types.contains(request.outputType))
          throw new JsException('TypeError: Choose a supported Flow output type.');
        JsDataPolicy.preflight(request.resultJson, 125000, 0);
        Object value = atPath(JSON.deserializeUntyped(request.resultJson), request.path);
        response.found = true;
        response.isNull = value == null;
        if (value != null) {
          if (request.outputType == 'Text')
            response.textValue = text(value);
          else if (request.outputType == 'Number')
            response.numberValue = numeric(value);
          else if (request.outputType == 'Boolean')
            response.booleanValue = bool(value);
          else if (request.outputType == 'Date')
            response.dateValue = dateValue(value);
          else if (request.outputType == 'DateTime')
            response.dateTimeValue = dateTimeValue(value);
          else if (request.outputType != 'JSON') {
            if (!(value instanceof List<Object>))
              throw new JsException('TypeError: Collection output requires a JSON array.');
            if (request.outputType == 'Records')
              response.records = records(value, request.objectApiName);
            else if (request.outputType == 'TextCollection') {
              List<String> values = new List<String>();
              for (Object cell : (List<Object>) value)
                values.add(cell == null ? null : text(cell));
              response.textValues = values;
            } else if (request.outputType == 'NumberCollection') {
              List<Decimal> values = new List<Decimal>();
              for (Object cell : (List<Object>) value)
                values.add(cell == null ? null : numeric(cell));
              response.numberValues = values;
            } else if (request.outputType == 'BooleanCollection') {
              List<Boolean> values = new List<Boolean>();
              for (Object cell : (List<Object>) value)
                values.add(cell == null ? null : bool(cell));
              response.booleanValues = values;
            } else if (request.outputType == 'DateCollection') {
              List<Date> values = new List<Date>();
              for (Object cell : (List<Object>) value)
                values.add(cell == null ? null : dateValue(cell));
              response.dateValues = values;
            } else if (request.outputType == 'DateTimeCollection') {
              List<Datetime> values = new List<Datetime>();
              for (Object cell : (List<Object>) value)
                values.add(cell == null ? null : dateTimeValue(cell));
              response.dateTimeValues = values;
            }
          }
        }
        response.jsonValue = JSON.serialize(value);
        response.success = true;
      } catch (Exception error) {
        response.error = error.getMessage();
      }
      responses.add(response);
    }
    return responses;
  }
}
