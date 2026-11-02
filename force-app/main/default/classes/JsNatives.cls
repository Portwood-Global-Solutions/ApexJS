/** Explicit host capability table. Scripts cannot resolve arbitrary Apex classes or methods. */
public with sharing class JsNatives {
  public static void install(JsScope scope, JsRuntime runtime) {
    JsWebNatives.install(scope);
    JsObjectNatives.install(scope, runtime);
    JsArrayNatives.install(scope, runtime);
    if (JsPromiseNatives.enabled) {
      JsPromiseNatives.install(scope, runtime);
      JsCompatGlobals.install(scope, runtime);
    }
    bind(scope, 'JSON', new List<String>{ 'parse', 'stringify' });
    bind(
      scope,
      'Math',
      new List<String>{
        'abs',
        'floor',
        'ceil',
        'round',
        'min',
        'max',
        'sin',
        'cos',
        'tan',
        'pow',
        'sqrt',
        'log',
        'sign',
        'atan2'
      }
    );
    JsValue mathValue = scope.read('Math');
    mathValue.props.put('PI', JsValue.num(Double.valueOf('3.141592653589793')));
    mathValue.attributes('PI', false, false, false);
    if (JsLibraryBuiltins.enabled) {
      mathValue.props.put('LOG10E', JsValue.num(Double.valueOf('0.4342944819032518')));
      mathValue.props.put('LN2', JsValue.num(Double.valueOf('0.6931471805599453')));
      mathValue.attributes('LOG10E', false, false, false);
      mathValue.attributes('LN2', false, false, false);
    }
    bind(scope, 'console', new List<String>{ 'log' });
    bind(
      scope,
      'Apex',
      new List<String>{
        'sha256',
        'base64Encode',
        'base64Decode',
        'utf8ByteLength',
        'blobToBase64',
        'latin1Bytes',
        'cpuTime',
        'copyBytes'
      }
    );
    if (JsLibraryBuiltins.enabled)
      scope.read('Apex')
        .props.put(
          'fillDeflateDistanceTable',
          JsValue.nativeFunction('Apex.fillDeflateDistanceTable')
        );
  }
  private static void bind(JsScope scope, String name, List<String> methods) {
    JsValue host = new JsValue('object');
    for (String method : methods) {
      host.props.put(method, JsValue.nativeFunction(name + '.' + method));
    }
    scope.declare(name, host, true);
  }

  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    runtime.budget.poll();
    if (name.startsWith('library.'))
      return JsLibraryBuiltins.invoke(name, args, receiver, runtime);
    if (name.startsWith('compat.'))
      return JsCompatGlobals.invoke(name, args, runtime);
    if (name.startsWith('Promise.') || name.startsWith('promise.'))
      return JsPromiseNatives.invoke(name, args, receiver, runtime);
    if (name == 'Apex.copyBytes')
      return JsBytes.copyNative(args, runtime);
    if (name == 'Array.construct')
      return JsArrayNatives.construct(args, runtime);
    if (name == 'Array.from')
      return JsArrayNatives.fromArrayLike(args, runtime);
    if (name == 'array.sort')
      return JsArrayNatives.sort(args, receiver, runtime);
    if (name == 'array.includes')
      return JsArrayNatives.includes(args, receiver, runtime);
    if (name == 'array.indexOf')
      return JsArrayNatives.indexOf(args, receiver, runtime);
    if (name == 'Array.of') {
      JsValue value = new JsValue('array');
      runtime.budget.allocate(args.size() + 1);
      value.items.addAll(args);
      return value;
    }
    if (name.startsWith('Object.') || name.startsWith('Map.') || name.equals('Function.empty')) {
      return JsObjectNatives.invoke(name, args, receiver, runtime);
    }
    if (name.equals('Apex.cpuTime')) {
      requireCount(args, 0);
      return JsValue.num(Double.valueOf(Limits.getCpuTime()));
    }
    if (JsWebNatives.handles(name)) {
      return JsWebNatives.invoke(name, args, receiver, runtime);
    }
    if (name.equals('Array.isArray')) {
      requireCount(args, 1);
      return JsValue.bool(args[0].kind == 'array');
    }
    if (name.equals('JSON.parse')) {
      requireCount(args, 1);
      requireKind(args[0], 'string');
      return JsCodec.parse((String) args[0].scalar, runtime.budget);
    }
    if (name.equals('JSON.stringify')) {
      requireCount(args, 1);
      if (args[0].kind == 'undefined' || args[0].kind == 'function' || args[0].kind == 'native') {
        return new JsValue('undefined');
      }
      return JsValue.str(JsCodec.stringify(args[0], runtime.budget, runtime));
    }
    if (name.equals('console.log')) {
      if (runtime.logs.size() >= 50) {
        throw new JsException('BudgetError: Console entry budget exceeded.');
      }
      List<String> parts = new List<String>();
      for (JsValue arg : args) {
        parts.add(
          arg.kind == 'object' ||
            arg.kind == 'array'
            ? JsCodec.stringify(arg, runtime.budget, runtime)
            : arg.asString()
        );
      }
      String line = String.join(parts, ' ');
      if (line.length() > 1000) {
        throw new JsException('BudgetError: Console line budget exceeded.');
      }
      runtime.logs.add(line);
      return new JsValue('undefined');
    }
    if (name.startsWith('Apex.')) {
      requireCount(args, 1);
      requireKind(args[0], 'string');
      String text = (String) args[0].scalar;
      if (name.equals('Apex.sha256')) {
        return JsValue.str(
          EncodingUtil.convertToHex(Crypto.generateDigest('SHA-256', Blob.valueOf(text)))
        );
      }
      if (name.equals('Apex.base64Encode')) {
        return JsValue.str(EncodingUtil.base64Encode(Blob.valueOf(text)));
      }
      if (name.equals('Apex.base64Decode')) {
        try {
          return JsValue.str(EncodingUtil.base64Decode(text).toString());
        } catch (Exception ex) {
          throw new JsException('TypeError: Invalid base64 or non-UTF-8 data.');
        }
      }
      if (name.equals('Apex.utf8ByteLength')) {
        return JsValue.num(Double.valueOf(Blob.valueOf(text).size()));
      }
    }
    if (name.startsWith('Math.')) {
      if (name == 'Math.pow' || name == 'Math.atan2') {
        requireCount(args, 2);
        return JsValue.num(
          name == 'Math.pow'
            ? Math.pow(args[0].asNumber(), args[1].asNumber())
            : Math.atan2(args[0].asNumber(), args[1].asNumber())
        );
      }
      if (name.equals('Math.min') || name.equals('Math.max')) {
        if (args.isEmpty()) {
          throw new JsException('RangeError: Infinity is outside this subset.');
        }
        Double result = args[0].asNumber();
        for (JsValue arg : args) {
          Double numberValue = arg.asNumber();
          if (name.equals('Math.min') ? numberValue < result : numberValue > result) {
            result = numberValue;
          }
        }
        return JsValue.num(result);
      }
      requireCount(args, 1);
      Double numberValue = args[0].asNumber();
      if (name.equals('Math.abs')) {
        return JsValue.num(Math.abs(numberValue));
      }
      if (name.equals('Math.floor')) {
        return JsValue.num(Math.floor(numberValue));
      }
      if (name.equals('Math.ceil')) {
        return JsValue.num(Math.ceil(numberValue));
      }
      if (name.equals('Math.round')) {
        return JsValue.num(Math.floor(numberValue + Double.valueOf('0.5')));
      }
      if (name.equals('Math.sin')) {
        return JsValue.num(Math.sin(numberValue));
      }
      if (name == 'Math.tan')
        return JsValue.num(Math.tan(numberValue));
      if (name.equals('Math.cos')) {
        return JsValue.num(Math.cos(numberValue));
      }
      if (name == 'Math.sqrt')
        return JsValue.num(Math.sqrt(numberValue));
      if (name == 'Math.log')
        return JsValue.num(Math.log(numberValue));
      if (name == 'Math.sign')
        return JsValue.num(
          Math.abs(numberValue) == 0
            ? numberValue
            : numberValue < 0 ? Double.valueOf('-1') : Double.valueOf('1')
        );
    }
    if (name.startsWith('string.')) {
      requireReceiver(receiver, 'string');
      requireCount(args, 0);
      String text = (String) receiver.scalar;
      if (name.equals('string.toUpperCase')) {
        return JsValue.str(text.toUpperCase());
      }
      if (name.equals('string.toLowerCase')) {
        return JsValue.str(text.toLowerCase());
      }
      if (name.equals('string.trim')) {
        return JsValue.str(trimEcma(text));
      }
    }
    if (name.startsWith('array.')) {
      return arrayMethod(name, args, receiver, runtime);
    }
    throw new JsException('TypeError: Unknown native function ' + name);
  }

  private static final Set<Integer> TRIM_CODES = new Set<Integer>{
    9,
    10,
    11,
    12,
    13,
    32,
    160,
    5760,
    8192,
    8193,
    8194,
    8195,
    8196,
    8197,
    8198,
    8199,
    8200,
    8201,
    8202,
    8232,
    8233,
    8239,
    8287,
    12288,
    65279
  };
  public static String trimEcma(String text) {
    Integer start = 0;
    Integer endIndex = text.length();
    while (start < endIndex && TRIM_CODES.contains(text.charAt(start))) {
      start++;
    }
    while (endIndex > start && TRIM_CODES.contains(text.charAt(endIndex - 1))) {
      endIndex--;
    }
    return text.substring(start, endIndex);
  }
  private static JsValue arrayMethod(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    requireReceiver(receiver, 'array');
    if (
      name == 'array.shift' ||
      name == 'array.pop' ||
      name == 'array.unshift' ||
      name == 'array.reverse' ||
      name == 'array.push'
    )
      return JsArrayNatives.mutate(name, args, receiver, runtime);
    if (name.equals('array.join')) {
      if (args.size() > 1) {
        throw new JsException('TypeError: join expects zero or one argument.');
      }
      String separator = args.isEmpty() || args[0].kind == 'undefined' ? ',' : args[0].asString();
      List<String> parts = new List<String>();
      Integer outputLength = 0;
      for (Integer i = 0; i < receiver.items.size(); i++) {
        JsValue item = runtime.getProperty(receiver, String.valueOf(i));
        runtime.budget.tick();
        String part = item.kind == 'null' || item.kind == 'undefined' ? '' : item.asString();
        outputLength += part.length() + (parts.isEmpty() ? 0 : separator.length());
        if (outputLength > 65536) {
          throw new JsException('BudgetError: String size exceeded.');
        }
        parts.add(part);
      }
      return JsValue.str(String.join(parts, separator));
    }
    if (name.equals('array.map') || name.equals('array.filter') || name.equals('array.reduce')) {
      Boolean reducing = name.equals('array.reduce');
      if (args.isEmpty() || args.size() > (reducing ? 2 : 1)) {
        throw new JsException('TypeError: Unsupported callback arguments.');
      }
      if (args[0].kind != 'function' && args[0].kind != 'native') {
        throw new JsException('TypeError: Callback must be a function.');
      }
      Integer originalLength = receiver.items.size();
      Integer index = 0;
      JsValue accumulator;
      if (reducing) {
        if (args.size() == 2)
          accumulator = args[1];
        else {
          while (index < originalLength) {
            runtime.budget.tick();
            accumulator = JsArrayNatives.slot(receiver, index++, runtime);
            if (accumulator != null)
              break;
          }
          if (accumulator == null)
            throw new JsException('TypeError: Reduce of empty array with no initial value.');
        }
      }
      JsValue result = new JsValue('array');
      if (name == 'array.map')
        JsArrayNatives.resize(result, originalLength, runtime);
      for (; index < originalLength; index++) {
        runtime.budget.tick();
        JsValue item = JsArrayNatives.slot(receiver, index, runtime);
        if (item == null)
          continue;
        List<JsValue> callbackArgs = new List<JsValue>();
        if (reducing)
          callbackArgs.add(accumulator);
        callbackArgs.add(item);
        callbackArgs.add(JsValue.num(Double.valueOf(index)));
        callbackArgs.add(receiver);
        JsValue mapped = runtime.invoke(args[0], callbackArgs, null);
        if (reducing)
          accumulator = mapped;
        else if (name == 'array.map')
          result.items[index] = mapped;
        else if (mapped.truthy()) {
          runtime.budget.allocate(1);
          result.items.add(item);
        }
      }
      return reducing ? accumulator : result;
    }
    throw new JsException('TypeError: Unknown array method.');
  }
  private static void requireCount(List<JsValue> args, Integer count) {
    if (args.size() != count) {
      throw new JsException('TypeError: Native function expects ' + count + ' argument(s).');
    }
  }
  private static void requireKind(JsValue value, String kind) {
    if (value.kind != kind) {
      throw new JsException('TypeError: Expected ' + kind + '.');
    }
  }
  private static void requireReceiver(JsValue receiver, String kind) {
    if (receiver == null || receiver.kind != kind) {
      throw new JsException('TypeError: Invalid method receiver.');
    }
  }
}
