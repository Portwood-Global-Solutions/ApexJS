/** Carries an interpreted throw value without confusing it with a host resource stop. */
public class JsThrownException extends Exception {
  public JsValue value;
  public static JsThrownException carrying(JsValue value) {
    String message = JsObjectNatives.objectLike(value) && value.kind != 'error'
      ? 'JavaScript threw an ' + value.kind + ' value.'
      : value.asString();
    JsThrownException result = new JsThrownException(message);
    result.value = value;
    return result;
  }
}
