/** Loads configured org assets only; no remote code or arbitrary Apex invocation. */
public with sharing class JsLibraryLoader {
  public static final Set<String> CONTENT_TYPES = new Set<String>{
    'application/javascript',
    'text/javascript',
    'application/x-javascript',
    'text/plain'
  };
  private static Map<String, String> sources = new Map<String, String>();
  @TestVisible
  private static Map<String, String> testSources;
  private static String read(String qualifiedName, JsBudget budget) {
    if (sources.containsKey(qualifiedName))
      return sources.get(qualifiedName);
    if (Test.isRunningTest() && testSources != null) {
      if (!testSources.containsKey(qualifiedName))
        throw new JsException('LibraryError: Static Resource not found: ' + qualifiedName + '.');
      return testSources.get(qualifiedName);
    }
    String name = qualifiedName, namespaceName;
    Integer separator = qualifiedName.indexOf('__');
    if (separator > 0) {
      namespaceName = qualifiedName.substring(0, separator);
      name = qualifiedName.substring(separator + 2);
    }
    if (Limits.getQueries() + 2 > Limits.getLimitQueries())
      throw new JsException('BudgetError: Not enough SOQL queries remain to load a library.');
    List<StaticResource> matches = [
      SELECT Id, ContentType, BodyLength
      FROM StaticResource
      WHERE Name = :name AND NamespacePrefix = :namespaceName
      LIMIT 1
    ];
    if (matches.isEmpty())
      throw new JsException('LibraryError: Static Resource not found: ' + qualifiedName + '.');
    StaticResource resource = matches[0];
    if (!CONTENT_TYPES.contains(resource.ContentType.toLowerCase()))
      throw new JsException(
        'LibraryError: Use an uncompressed JavaScript or plain-text Static Resource: ' +
          qualifiedName +
          '.'
      );
    if (resource.BodyLength > budget.maxSourceCharacters * 4)
      throw new JsException(
        'BudgetError: Library source exceeds the source policy: ' + qualifiedName + '.'
      );
    Blob body = [SELECT Body FROM StaticResource WHERE Id = :resource.Id].Body;
    String source;
    try {
      source = body.toString();
    } catch (Exception error) {
      throw new JsException(
        'LibraryError: Library source must be UTF-8 text: ' + qualifiedName + '.'
      );
    }
    if (source.length() > budget.maxSourceCharacters)
      throw new JsException(
        'BudgetError: Library source exceeds the source policy: ' + qualifiedName + '.'
      );
    budget.guard();
    sources.put(qualifiedName, source);
    return source;
  }
  public static String build(
    String calculation,
    List<JsLibraryBinding> libraries,
    JsBudget budget
  ) {
    if (libraries == null || libraries.isEmpty())
      return calculation;
    List<String> parts = new List<String>{ 'var libraries = {};\n' };
    Set<String> names = new Set<String>();
    Integer length = parts[0].length() + calculation.length() + 100;
    for (JsLibraryBinding library : libraries) {
      if (library == null)
        throw new JsException('LibraryError: A library entry is missing.');
      JsDataPolicy.validateName(library.name);
      if (names.contains(library.name))
        throw new JsException('LibraryError: Duplicate library name: ' + library.name + '.');
      names.add(library.name);
      if (
        String.isBlank(library.resource) ||
        !Pattern.matches('[A-Za-z][A-Za-z0-9_]*', library.resource)
      )
        throw new JsException(
          'LibraryError: Choose a JavaScript Static Resource for ' + library.name + '.'
        );
      String body = read(library.resource, budget);
      String module =
        'libraries[' +
        JSON.serialize(library.name) +
        '] = (function(){\nvar exports = {}; var module = {exports:exports};\n' +
        body +
        '\nreturn module.exports;\n})();\n';
      length += module.length();
      if (length > budget.maxSourceCharacters)
        throw new JsException(
          'BudgetError: Combined libraries and calculation exceed the source policy.'
        );
      parts.add(module);
      budget.guard();
    }
    parts.add('return (function(input, libraries){\n' + calculation + '\n})(input, libraries);');
    return String.join(parts, '');
  }
}
