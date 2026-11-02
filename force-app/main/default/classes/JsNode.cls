public class JsNode {
  public String kind;
  public String text;
  public Integer row;
  public Integer col;
  public List<JsNode> children = new List<JsNode>();
  public List<String> names = new List<String>();
  public JsValue cachedLiteral;
  public List<String> hoistedNames;
  public Boolean needsArguments = false;

  public JsNode(String kind, JsToken token) {
    this.kind = kind;
    this.row = token.row;
    this.col = token.col;
  }
}
