/** Design-time choices; runtime source loading is handled by JsLibraryLoader. */
public with sharing class JsLibraryController {
  public class Choice {
    @AuraEnabled
    public String label;
    @AuraEnabled
    public String value;
    public Choice(String name, String namespaceName) {
      value = String.isBlank(namespaceName) ? name : namespaceName + '__' + name;
      label = value;
    }
  }
  @AuraEnabled(cacheable=true)
  public static List<Choice> listLibraries() {
    List<Choice> choices = new List<Choice>();
    for (StaticResource resource : [
      SELECT Name, NamespacePrefix
      FROM StaticResource
      WHERE ContentType IN :JsLibraryLoader.CONTENT_TYPES
      ORDER BY Name
    ])
      choices.add(new Choice(resource.Name, resource.NamespacePrefix));
    return choices;
  }
}
