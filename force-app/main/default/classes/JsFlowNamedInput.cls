/** One named input row. Flow binds record references here; primitive resources use typed channels. */
public class JsFlowNamedInput {
  @AuraEnabled
  public String name;
  @AuraEnabled
  public String kind;
  @AuraEnabled
  public Boolean isCollection;
  @AuraEnabled
  public Boolean isLiteral;
  @AuraEnabled
  public String resource;
  @AuraEnabled
  public String textValue;
  @AuraEnabled
  public Decimal numberValue;
  @AuraEnabled
  public Boolean booleanValue;
  @AuraEnabled
  public SObject recordValue;
  @AuraEnabled
  public List<SObject> records;
  @AuraEnabled
  public List<String> texts;
  @AuraEnabled
  public List<Decimal> numbers;
  @AuraEnabled
  public List<Boolean> booleans;
  @AuraEnabled
  public List<Date> dates;
  @AuraEnabled
  public List<Datetime> dateTimes;
  @AuraEnabled
  public String valueJson;
  public JsFlowNamedInput() {
  }
}
