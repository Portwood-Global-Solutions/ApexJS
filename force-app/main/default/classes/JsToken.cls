public class JsToken {
  public String kind;
  public String regexFlags;
  public String text;
  public Integer row;
  public Integer col;

  public JsToken(String kind, String text, Integer row, Integer col) {
    this.kind = kind;
    this.text = text;
    this.row = row;
    this.col = col;
  }
}
