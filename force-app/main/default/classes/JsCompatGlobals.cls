/** Bounded compatibility globals used by the experimental async library path. Dynamic code remains disabled. */
public class JsCompatGlobals {
  private static final String DIGITS = '0123456789abcdefghijklmnopqrstuvwxyz';
  public static void install(JsScope scope, JsRuntime runtime) {
    scope.declare('NaN', JsValue.num(Double.valueOf('NaN')), true);
    for (String name : new List<String>{ 'parseInt', 'isNaN', 'isFinite', 'Boolean' })
      scope.declare(name, JsValue.nativeFunction('compat.' + name), true);
    if (JsLibraryBuiltins.enabled)
      scope.declare('parseFloat', JsValue.nativeFunction('compat.parseFloat'), true);
    JsValue functionCtor = JsValue.nativeFunction('compat.Function');
    functionCtor.constructorPrototype = runtime.functionPrototype;
    scope.declare('Function', functionCtor, true);
    runtime.functionPrototype.props.put('constructor', functionCtor);
    runtime.functionPrototype.attributes('constructor', false, true, true);
    runtime.arrayBufferPrototype = new JsValue('object');
    JsValue bufferCtor = JsValue.nativeFunction('compat.ArrayBuffer');
    bufferCtor.constructorPrototype = runtime.arrayBufferPrototype;
    runtime.arrayBufferPrototype.props.put('constructor', bufferCtor);
    runtime.arrayBufferPrototype.attributes('constructor', false, true, true);
    scope.declare('ArrayBuffer', bufferCtor, true);
  }
  public static JsValue construct(String name, List<JsValue> args, JsRuntime runtime) {
    if (name != 'compat.ArrayBuffer')
      throw new JsException('TypeError: Dynamic Function compilation is disabled.');
    if (args.size() > 1)
      throw new JsException('TypeError: ArrayBuffer accepts one bounded length.');
    Double n = args.isEmpty() || args[0].kind == 'undefined' ? 0 : args[0].asNumber();
    n = n < 0 ? Math.ceil(n) : Math.floor(n);
    JsValue result = JsBytes.create('arraybuffer', n.intValue(), runtime);
    result.explicitPrototype = true;
    result.prototypeParent = runtime.arrayBufferPrototype;
    return result;
  }
  public static JsValue invoke(String name, List<JsValue> args, JsRuntime runtime) {
    JsValue value = args.isEmpty() ? new JsValue('undefined') : args[0];
    if (name == 'compat.Function')
      throw new JsException('TypeError: Dynamic Function compilation is disabled.');
    if (name == 'compat.ArrayBuffer')
      throw new JsException('TypeError: ArrayBuffer requires new.');
    if (name == 'compat.Boolean')
      return JsValue.bool(value.truthy());
    if (name == 'compat.parseFloat') {
      String text = JsNatives.trimEcma(value.asString());
      Matcher match = Pattern.compile(
          '^[+-]?(?:[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+)(?:[eE][+-]?[0-9]+)?'
        )
        .matcher(text);
      return match.find()
        ? JsValue.num(Double.valueOf(match.group()))
        : JsValue.num(Double.valueOf('NaN'));
    }
    if (name == 'compat.parseInt') {
      String input = JsNatives.trimEcma(value.asString()).toLowerCase();
      Boolean negative = input.startsWith('-');
      if (input.startsWith('-') || input.startsWith('+'))
        input = input.substring(1);
      Integer radix = args.size() < 2 ||
        args[1].kind == 'undefined'
        ? 0
        : args[1].asNumber().longValue().intValue();
      if (radix == 0)
        radix = input.startsWith('0x') ? 16 : 10;
      if (radix < 2 || radix > 36)
        return JsValue.num(Double.valueOf('NaN'));
      if (radix == 16 && input.startsWith('0x'))
        input = input.substring(2);
      Double result = 0;
      Integer count = 0;
      for (Integer i = 0; i < input.length(); i++) {
        runtime.budget.tick();
        Integer digit = DIGITS.indexOf(input.substring(i, i + 1));
        if (digit < 0 || digit >= radix)
          break;
        result = result * radix + digit;
        count++;
      }
      if (count == 0)
        return JsValue.num(Double.valueOf('NaN'));
      return JsValue.num(negative ? -result : result);
    }
    if (value.kind == 'undefined')
      return JsValue.bool(name == 'compat.isNaN');
    if (value.kind == 'number') {
      String text = String.valueOf(value.scalar);
      return JsValue.bool(
        name == 'compat.isNaN'
          ? text.contains('NaN')
          : !text.contains('NaN') && !text.contains('Infinity')
      );
    }
    if (value.kind == 'null' || value.kind == 'boolean')
      return JsValue.bool(name == 'compat.isFinite');
    if (value.kind != 'string') {
      for (String method : new List<String>{ 'valueOf', 'toString' }) {
        JsValue fn = runtime.getProperty(value, method);
        if (fn.kind != 'function' && fn.kind != 'native')
          continue;
        JsValue primitive;
        if (
          method == 'toString' &&
          fn.kind == 'native' &&
          fn.nativeName == 'Object.prototype.toString' &&
          (value.kind == 'uint8array' || JsTypedBuffers.typed(value))
        ) {
          Integer n = value.kind == 'uint8array' ? JsBytes.length(value) : value.wordLength;
          primitive = n == 0
            ? JsValue.str('')
            : n == 1 ? runtime.getProperty(value, '0') : JsValue.str('NaN');
        } else if (
          method == 'toString' &&
          fn.kind == 'native' &&
          fn.nativeName == 'Object.prototype.toString' &&
          value.kind == 'array'
        )
          primitive = JsNatives.invoke('array.join', new List<JsValue>(), value, runtime);
        else
          primitive = runtime.invoke(fn, new List<JsValue>(), value);
        if (!JsObjectNatives.objectLike(primitive))
          return invoke(name, new List<JsValue>{ primitive }, runtime);
      }
      throw new JsException('TypeError: Numeric conversion did not produce a primitive.');
    }
    try {
      JsValue numberValue = JsWebNatives.invoke(
        'web.Number',
        new List<JsValue>{ value },
        null,
        runtime
      );
      return invoke(name, new List<JsValue>{ numberValue }, runtime);
    } catch (JsException error) {
      if (error.getMessage().startsWith('BudgetError:'))
        throw error;
      return JsValue.bool(name == 'compat.isNaN');
    }
  }
}
