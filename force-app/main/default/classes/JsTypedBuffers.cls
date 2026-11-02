/** Bounded integer typed buffers. Subarray shares same-type storage; ArrayBuffer reinterpretation is separate work. */
public class JsTypedBuffers {
  public static Integer trustedMaxBytes;
  public static Boolean trustedPagedStorage = false;
  private static Integer byteLimit() {
    Integer allowed = trustedMaxBytes == null ? 32768 : trustedMaxBytes;
    if (allowed < 1 || allowed > 1048576)
      throw new JsException('BudgetError: Invalid trusted typed buffer limit.');
    return allowed;
  }
  public static Boolean typed(JsValue value) {
    return value.kind == 'typedarray';
  }
  private static Integer width(String name) {
    return name == 'Uint16Array' ? 2 : 4;
  }
  public static JsValue construct(String name, List<JsValue> args, JsRuntime runtime) {
    if (args.size() > 1)
      throw new JsException('TypeError: Typed buffer constructors currently accept one input.');
    JsValue result = new JsValue('typedarray');
    result.scalar = name;
    result.wordOffset = 0;
    result.wordLength = 0;
    runtime.budget.allocate(1);
    if (args.isEmpty() || args[0].kind == 'undefined')
      return result;
    JsValue source = args[0];
    Integer length;
    if (source.kind == 'number') {
      Double n = source.asNumber();
      n = n < 0 ? Math.ceil(n) : Math.floor(n);
      if (n < 0 || n > byteLimit() / width(name))
        throw new JsException('BudgetError: Typed buffer byte size exceeded.');
      length = n.intValue();
    } else {
      if (source.kind != 'array' && source.kind != 'uint8array' && !typed(source))
        throw new JsException(
          'TypeError: Typed buffer input must be an array or integer typed buffer.'
        );
      length = runtime.getProperty(source, 'length').asNumber().intValue();
      if (length > byteLimit() / width(name))
        throw new JsException('BudgetError: Typed buffer byte size exceeded.');
    }
    runtime.budget.allocate(length);
    result.wordLength = length;
    if (trustedPagedStorage) {
      result.words = null;
      result.wordPages = new JsIntegerPages(length, name);
      if (source.kind == 'number')
        runtime.budget.tick(length);
      else
        for (Integer i = 0; i < length; i++) {
          runtime.budget.tick();
          put(result, i, convert(runtime.getProperty(source, String.valueOf(i)), name));
        }
      runtime.budget.guard();
      return result;
    }
    if (source.kind == 'number') {
      // Native block copies share immutable Double zero values, not mutable JS elements.
      // Keep exactly the same logical charge as the former per-element fill loop.
      runtime.budget.tick(length);
      Integer remaining = length;
      List<Double> block = new List<Double>{ 0.0 };
      while (remaining > 0) {
        runtime.budget.guard();
        if (Math.mod(remaining, 2) == 1)
          result.words.addAll(block);
        remaining = remaining / 2;
        if (remaining > 0)
          block.addAll(new List<Double>(block));
      }
    } else
      for (Integer i = 0; i < length; i++) {
        runtime.budget.tick();
        result.words.add(convert(runtime.getProperty(source, String.valueOf(i)), name));
      }
    runtime.budget.guard();
    return result;
  }
  public static Double element(JsValue value, Integer index) {
    return value.wordPages == null
      ? value.words[value.wordOffset + index]
      : value.wordPages.read(value.wordOffset + index);
  }
  private static void put(JsValue value, Integer index, Double item) {
    if (value.wordPages == null)
      value.words[value.wordOffset + index] = item;
    else
      value.wordPages.write(value.wordOffset + index, item);
  }
  public static void storeUnsigned16(JsValue value, Integer index, Integer word) {
    if (
      !typed(value) ||
      (String) value.scalar != 'Uint16Array' ||
      index < 0 ||
      index >= value.wordLength ||
      word < 0 ||
      word > 65535
    )
      throw new JsException('RangeError: Invalid Uint16 element.');
    put(value, index, Double.valueOf(word));
  }
  private static Double convert(JsValue value, String name) {
    if (JsLibraryBuiltins.enabled && value.nanNumber)
      return 0;
    Double n = value.kind == 'undefined' ||
      value.kind == 'null'
      ? 0
      : value.kind == 'boolean'
          ? ((Boolean) value.scalar ? Double.valueOf('1') : Double.valueOf('0'))
          : value.asNumber();
    n = n < 0 ? Math.ceil(n) : Math.floor(n);
    Double modulus = name == 'Uint16Array' ? Double.valueOf('65536') : Double.valueOf('4294967296');
    n -= Math.floor(n / modulus) * modulus;
    if (name == 'Int32Array' && n >= Double.valueOf('2147483648'))
      n -= Double.valueOf('4294967296');
    return n;
  }
  public static JsValue property(JsValue value, String key) {
    if (!typed(value))
      return null;
    if (key == 'length')
      return JsValue.num(Double.valueOf(value.wordLength));
    if (key == 'byteLength')
      return JsValue.num(Double.valueOf(value.wordLength * width((String) value.scalar)));
    if (key == 'byteOffset')
      return JsValue.num(Double.valueOf(value.wordOffset * width((String) value.scalar)));
    if (key == 'set' || key == 'slice' || key == 'subarray')
      return JsValue.nativeFunction('typed.' + key);
    if (key == 'buffer')
      throw new JsException(
        'TypeError: Shared ArrayBuffer reinterpretation requires additional backend support.'
      );
    Integer index = index(key);
    return index >= 0 && index < value.wordLength ? JsValue.num(element(value, index)) : null;
  }
  private static Integer index(String key) {
    if (key.length() == 0 || key.length() > 8 || key.length() > 1 && key.startsWith('0'))
      return -1;
    for (Integer i = 0; i < key.length(); i++)
      if (!'0123456789'.contains(key.substring(i, i + 1)))
        return -1;
    return Integer.valueOf(key);
  }
  public static void write(JsValue value, String key, JsValue item) {
    Integer index = index(key);
    if (index >= 0) {
      if (index < value.wordLength)
        put(value, index, convert(item, (String) value.scalar));
      return;
    }
    throw new JsException('TypeError: Unsupported typed buffer property assignment.');
  }
  private static Integer offset(JsValue value, Integer n) {
    Double d = value.kind == 'undefined' ? 0 : value.asNumber();
    d = d < 0 ? Math.ceil(d) : Math.floor(d);
    if (d < -n)
      return 0;
    if (d > n)
      return n;
    Integer i = d.intValue();
    return i < 0 ? n + i : i;
  }
  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    if (receiver == null || !typed(receiver))
      throw new JsException('TypeError: Invalid typed buffer receiver.');
    if (name == 'typed.set') {
      if (args.isEmpty() || args.size() > 2)
        throw new JsException('TypeError: set expects source and optional offset.');
      JsValue source = args[0];
      if (source.kind != 'array' && source.kind != 'uint8array' && !typed(source))
        throw new JsException('TypeError: set requires array-like buffer input.');
      Integer length = runtime.getProperty(source, 'length').asNumber().intValue();
      Double raw = args.size() < 2 || args[1].kind == 'undefined' ? 0 : args[1].asNumber();
      raw = raw < 0 ? Math.ceil(raw) : Math.floor(raw);
      if (raw < 0 || raw > receiver.wordLength || raw + length > receiver.wordLength)
        throw new JsException('RangeError: Typed buffer set exceeds bounds.');
      Integer start = raw.intValue();
      runtime.budget.allocate(length);
      List<Double> snapshot = new List<Double>();
      for (Integer i = 0; i < length; i++) {
        runtime.budget.tick();
        snapshot.add(
          convert(runtime.getProperty(source, String.valueOf(i)), (String) receiver.scalar)
        );
      }
      for (Integer i = 0; i < length; i++) {
        runtime.budget.tick();
        put(receiver, start + i, snapshot[i]);
      }
      return new JsValue('undefined');
    }
    if (args.size() > 2)
      throw new JsException('TypeError: Typed buffer slicing expects at most two bounds.');
    Integer start = args.isEmpty() ? 0 : offset(args[0], receiver.wordLength),
      endIndex = args.size() < 2 ||
        args[1].kind == 'undefined'
        ? receiver.wordLength
        : offset(args[1], receiver.wordLength);
    endIndex = Math.max(start, endIndex);
    JsValue result = new JsValue('typedarray');
    result.scalar = receiver.scalar;
    result.wordLength = endIndex - start;
    result.explicitPrototype = receiver.explicitPrototype;
    result.prototypeParent = receiver.prototypeParent;
    runtime.budget.allocate(1);
    if (name == 'typed.subarray') {
      result.words = receiver.words;
      result.wordPages = receiver.wordPages;
      result.wordOffset = receiver.wordOffset + start;
    } else {
      runtime.budget.allocate(result.wordLength);
      if (receiver.wordPages != null) {
        result.words = null;
        result.wordPages = new JsIntegerPages(result.wordLength, (String) result.scalar);
      }
      for (Integer i = start; i < endIndex; i++) {
        runtime.budget.tick();
        if (result.wordPages == null)
          result.words.add(element(receiver, i));
        else
          put(result, i - start, element(receiver, i));
      }
    }
    return result;
  }
}
