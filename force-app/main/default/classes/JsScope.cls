public class JsScope {
  public JsScope parent;
  public Boolean functionScope = false;
  private Map<String, JsValue> values = new Map<String, JsValue>();
  private Set<String> constants = new Set<String>();
  private Set<String> uninitialized = new Set<String>();
  private Set<String> varNames = new Set<String>();
  public JsScope(JsScope parent) {
    this.parent = parent;
  }
  public void declare(String name, JsValue value, Boolean immutable) {
    if (values.containsKey(name)) {
      throw new JsException('SyntaxError: Duplicate binding ' + name);
    }
    values.put(name, value);
    if (immutable) {
      constants.add(name);
    }
  }
  public JsValue read(String name) {
    JsScope owner = this;
    while (owner != null) {
      JsValue value = owner.values.get(name);
      if (value != null) {
        if (owner.uninitialized.contains(name)) {
          throw new JsException(
            'ReferenceError: Cannot access ' + name + ' before initialization.'
          );
        }
        return value;
      }
      owner = owner.parent;
    }
    throw new JsException('ReferenceError: ' + name + ' is not defined.');
  }
  public Boolean has(String name) {
    JsScope owner = this;
    while (owner != null) {
      if (owner.values.containsKey(name)) {
        return true;
      }
      owner = owner.parent;
    }
    return false;
  }
  public void assign(String name, JsValue value) {
    JsScope owner = this;
    while (owner != null) {
      if (owner.values.containsKey(name)) {
        if (owner.uninitialized.contains(name)) {
          throw new JsException(
            'ReferenceError: Cannot access ' + name + ' before initialization.'
          );
        }
        if (owner.constants.contains(name)) {
          throw new JsException('TypeError: Assignment to constant ' + name);
        }
        owner.values.put(name, value);
        return;
      }
      owner = owner.parent;
    }
    throw new JsException('ReferenceError: ' + name + ' is not defined.');
  }
  public void reserve(String name, Boolean immutable) {
    declare(name, new JsValue('undefined'), immutable);
    uninitialized.add(name);
  }
  public void initialize(String name, JsValue value) {
    if (!uninitialized.contains(name)) {
      throw new JsException('SyntaxError: Duplicate binding ' + name);
    }
    values.put(name, value);
    uninitialized.remove(name);
  }
  public void parameter(String name, JsValue value) {
    declare(name, value, false);
    varNames.add(name);
  }
  public JsScope functionRoot() {
    JsScope owner = this;
    while (!owner.functionScope && owner.parent != null) {
      owner = owner.parent;
    }
    return owner;
  }
  public void declareVar(String name) {
    JsScope root = functionRoot();
    if (!root.values.containsKey(name)) {
      root.declare(name, new JsValue('undefined'), false);
      root.varNames.add(name);
    } else if (!root.varNames.contains(name)) {
      throw new JsException('SyntaxError: Conflicting var binding ' + name);
    }
  }
  public void functionDeclaration(String name, JsValue value) {
    if (functionScope) {
      declareVar(name);
      values.put(name, value);
    } else {
      declare(name, value, false);
    }
  }
}
