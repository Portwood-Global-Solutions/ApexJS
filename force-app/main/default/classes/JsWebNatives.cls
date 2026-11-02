/** Bounded language and byte-oriented host primitives. */
public with sharing class JsWebNatives {
  private static final Set<String> FUNCTIONS = new Set<String>{
    'Uint8Array',
    'Uint16Array',
    'Uint32Array',
    'Int32Array',
    'Blob',
    'Date',
    'RegExp',
    'String',
    'Number',
    'Error',
    'TypeError',
    'RangeError',
    'ReferenceError',
    'SyntaxError'
  };
  private static final Set<String> STRING_METHODS = new Set<String>{
    'charCodeAt',
    'codePointAt',
    'slice',
    'split',
    'replace',
    'padStart',
    'match',
    'indexOf'
  };
  private static final Set<String> ARRAY_METHODS = new Set<String>{
    'array.slice',
    'array.splice',
    'array.concat'
  };
  private static final Set<String> CONSTRUCTORS = new Set<String>{
    'web.Uint8Array',
    'web.Uint16Array',
    'web.Uint32Array',
    'web.Int32Array',
    'web.Blob',
    'web.Date',
    'web.RegExp',
    'web.Error',
    'web.TypeError',
    'web.RangeError',
    'web.ReferenceError',
    'web.SyntaxError'
  };
  private static final Set<String> REGEX_FLAGS = new Set<String>{ '', 'g', 'i', 'gi', 'ig' };
  private static final Set<String> REGEX_PATTERNS = new Set<String>{
    '\\\\',
    '\\(',
    '\\)',
    '[-:T]',
    '([astvzqmhlc])([^astvzqmhlc]*)',
    '-?[0-9]*\\.?[0-9]+(?:e[-+]?\\d+)?',
    '<(/?)([A-Za-z][A-Za-z0-9]*)([^<>]*?)(/?)>',
    '([A-Za-z_:][A-Za-z0-9_.:-]*)\\s*=\\s*"([^"]*)"',
    '([A-Za-z]+)\\s*\\(([^)]*)\\)'
  };
  private static final String HEX = '0123456789abcdef';
  private static List<String> HEX_BYTES;
  public static void install(JsScope scope) {
    for (String name : FUNCTIONS) {
      scope.declare(name, JsValue.nativeFunction('web.' + name), true);
    }
  }
  public static Boolean handles(String name) {
    return name.startsWith('number.') ||
      name.startsWith('web.') ||
      name.startsWith('Function.') ||
      name.startsWith('uint8.') ||
      name.startsWith('typed.') ||
      name.equals('date.toISOString') ||
      ARRAY_METHODS.contains(name) ||
      (name.startsWith('string.') && STRING_METHODS.contains(name.substring(7))) ||
      name.equals('Apex.blobToBase64') ||
      name.equals('Apex.latin1Bytes');
  }
  public static JsValue construct(JsValue callable, List<JsValue> args, JsRuntime runtime) {
    if (callable.kind != 'native' || !CONSTRUCTORS.contains(callable.nativeName)) {
      throw new JsException('TypeError: Only the documented native constructors are supported.');
    }
    return invoke(callable.nativeName, args, null, runtime);
  }
  public static JsValue property(JsValue value, String key) {
    JsValue libraryProperty = JsLibraryBuiltins.property(value, key);
    if (libraryProperty != null)
      return libraryProperty;
    if (value.kind == 'number' && key == 'toString')
      return JsValue.nativeFunction('number.toString');
    if (JsTypedBuffers.typed(value))
      return JsTypedBuffers.property(value, key);
    if (
      value.kind == 'native' &&
      value.nativeName == 'web.String' &&
      (key == 'fromCharCode' ||
      key == 'fromCodePoint')
    )
      return JsValue.nativeFunction('web.String.' + key);
    if (
      value.kind == 'native' &&
      value.nativeName == 'web.Number' &&
      (key.equals('isFinite') ||
      key.equals('isNaN') ||
      key.equals('isInteger'))
    ) {
      return JsValue.nativeFunction('web.Number.' + key);
    }
    if (value.kind == 'arraybuffer' && key == 'byteLength')
      return JsValue.num(Double.valueOf(JsBytes.length(value)));
    if (value.kind == 'uint8array') {
      if (key == 'buffer' && JsPromiseNatives.enabled) {
        return JsBytes.buffer(value);
      }
      if (key == 'byteOffset')
        return JsValue.num(Double.valueOf(value.byteOffset));
      if (key.equals('length') || key.equals('byteLength')) {
        return JsValue.num(Double.valueOf(JsBytes.length(value)));
      }
      if (key.equals('set') || key.equals('slice') || key.equals('subarray')) {
        return JsValue.nativeFunction('uint8.' + key);
      }
      Integer index = indexKey(key);
      if (index < 0)
        return null;
      return index < JsBytes.length(value)
        ? JsValue.num(Double.valueOf(JsBytes.read(value, index)))
        : new JsValue('undefined');
    }
    if (value.kind == 'blob') {
      if (key.equals('size')) {
        return JsValue.num(Double.valueOf(JsBytes.length(value)));
      }
      if (key.equals('type')) {
        return JsValue.str((String) value.scalar);
      }
    }
    if (value.kind == 'date' && key.equals('toISOString')) {
      return JsValue.nativeFunction('date.toISOString');
    }
    if (value.kind == 'error' && key.equals('message') && value.hasErrorMessage) {
      return JsValue.str((String) value.scalar);
    }
    return null;
  }
  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    runtime.budget.tick();
    runtime.budget.poll();
    if (JsLibraryBuiltins.enabled && name == 'web.Date')
      return JsLibraryBuiltins.date(args);
    if (JsLibraryBuiltins.enabled && name == 'web.RegExp')
      return JsLibraryBuiltins.regex(args);
    if (name == 'number.toString') {
      expectReceiver(receiver, 'number');
      arity(args, 0, 1);
      Double raw = receiver.asNumber();
      Integer radix = args.isEmpty() || args[0].kind == 'undefined'
        ? 10
        : args[0].asNumber().intValue();
      if (radix < 2 || radix > 36)
        throw new JsException('RangeError: Invalid number radix.');
      if (receiver.nanNumber || String.valueOf(raw).contains('Infinity'))
        return JsValue.str(receiver.asString());
      if (radix == 10)
        return JsValue.str(JsCodec.finiteNumberText(raw));
      if (raw != Math.floor(raw) || Math.abs(raw) > Double.valueOf('9007199254740992'))
        throw new JsException('RangeError: Nondecimal conversion requires a bounded integer.');
      Long remaining = Math.abs(raw).longValue();
      String digits = '0123456789abcdefghijklmnopqrstuvwxyz', result = '';
      do {
        runtime.budget.tick();
        Integer digit = (remaining - (remaining / radix) * radix).intValue();
        result = digits.substring(digit, digit + 1) + result;
        remaining = remaining / radix;
      } while (remaining > 0);
      return JsValue.str((raw < 0 ? '-' : '') + result);
    }
    if (name == 'web.Uint16Array' || name == 'web.Uint32Array' || name == 'web.Int32Array')
      return JsTypedBuffers.construct(name.substring(4), args, runtime);
    if (name.startsWith('typed.'))
      return JsTypedBuffers.invoke(name, args, receiver, runtime);
    if (name == 'web.String.fromCharCode' || name == 'web.String.fromCodePoint') {
      if (args.size() > 5000)
        throw new JsException('BudgetError: Character argument count exceeded.');
      List<Integer> codes = new List<Integer>();
      for (JsValue arg : args) {
        runtime.budget.tick();
        Double value = arg.asNumber();
        if (JsLibraryBuiltins.enabled && arg.nanNumber) {
          if (name == 'web.String.fromCodePoint')
            throw new JsException('RangeError: Invalid Unicode code point.');
          codes.add(0);
          continue;
        }
        if (name == 'web.String.fromCodePoint') {
          if (value < 0 || value > 1114111 || value != Math.floor(value))
            throw new JsException('RangeError: Invalid Unicode code point.');
          Integer point = value.intValue();
          if (point > 65535) {
            point -= 65536;
            codes.add(55296 + point / 1024);
            codes.add(56320 + Math.mod(point, 1024));
          } else
            codes.add(point);
        } else {
          Double whole = value < 0 ? Math.ceil(value) : Math.floor(value);
          codes.add((whole - Math.floor(whole / 65536) * 65536).intValue());
        }
      }
      runtime.budget.allocate(codes.size());
      return JsValue.str(String.fromCharArray(codes));
    }
    if (
      name.equals('web.Number.isFinite') ||
      name.equals('web.Number.isNaN') ||
      name.equals('web.Number.isInteger')
    ) {
      arity(args, 1, 1);
      // Numeric predicates do not coerce. The async trusted path can carry NaN.
      if (args[0].nanNumber)
        return JsValue.bool(name == 'web.Number.isNaN');
      if (args[0].kind == 'number' && String.valueOf(args[0].scalar).contains('Infinity'))
        return JsValue.bool(false);
      return JsValue.bool(
        args[0].kind == 'number' &&
        (name == 'web.Number.isFinite' ||
        (name == 'web.Number.isInteger' &&
        args[0].asNumber() == Math.floor(args[0].asNumber())))
      );
    }
    if (name.equals('web.String')) {
      arity(args, 0, 1);
      return JsValue.str(args.isEmpty() ? '' : args[0].asString());
    }
    if (name.equals('web.Number')) {
      if (args.isEmpty() || args[0].kind == 'null') {
        return JsValue.num(Double.valueOf('0'));
      }
      if (args[0].kind == 'number') {
        return args[0];
      }
      if (args[0].kind == 'boolean') {
        return JsValue.num(Double.valueOf((Boolean) args[0].scalar ? '1' : '0'));
      }
      String text = stringArg(args[0]).trim();
      try {
        return JsValue.num(text.length() == 0 ? Double.valueOf('0') : Double.valueOf(text));
      } catch (Exception ex) {
        throw new JsException('TypeError: Non-finite Number conversion is outside this subset.');
      }
    }
    if (
      name == 'web.Error' ||
      name == 'web.TypeError' ||
      name == 'web.RangeError' ||
      name == 'web.ReferenceError' ||
      name == 'web.SyntaxError'
    ) {
      arity(args, 0, 1);
      JsValue result = new JsValue('error');
      result.errorName = name.substring(4);
      result.hasErrorMessage = !args.isEmpty() && args[0].kind != 'undefined';
      result.scalar = result.hasErrorMessage ? args[0].asString() : '';
      result.explicitPrototype = true;
      result.prototypeParent = runtime.errorPrototypes.get(result.errorName);
      return result;
    }
    if (name.equals('Apex.latin1Bytes')) {
      arity(args, 1, 1);
      String text = stringArg(args[0]);
      checkBufferSize(text.length());
      runtime.budget.allocate(text.length());
      JsValue result = new JsValue('uint8array');
      for (Integer i = 0; i < text.length(); i++) {
        if (Math.mod(i, 256) == 0) {
          runtime.budget.guard();
        }
        Integer code = text.charAt(i);
        result.bytes.add(code > 255 ? 63 : code);
      }
      return result;
    }
    if (name.equals('web.Date')) {
      arity(args, 0, 0);
      JsValue result = new JsValue('date');
      result.scalar = Datetime.now().formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
      return result;
    }
    if (name.equals('date.toISOString')) {
      expectReceiver(receiver, 'date');
      arity(args, 0, 0);
      return JsValue.str((String) receiver.scalar);
    }
    if (name.equals('web.RegExp')) {
      arity(args, 1, 2);
      JsValue result = new JsValue('regexp');
      result.pattern = stringArg(args[0]);
      result.flags = args.size() == 2 ? stringArg(args[1]) : '';
      if (!REGEX_FLAGS.contains(result.flags)) {
        throw new JsException('TypeError: This regex subset supports only g/i flags.');
      }
      if (!REGEX_PATTERNS.contains(result.pattern)) {
        throw new JsException('TypeError: Regex pattern is outside the tested host subset.');
      }
      return result;
    }
    if (name.equals('web.Uint8Array')) {
      arity(args, 0, 3);
      JsValue source = args.isEmpty() ? new JsValue('undefined') : args[0];
      Integer n;
      if (source.kind == 'arraybuffer') {
        Integer start = args.size() < 2 ? 0 : integerArg(args[1]);
        n = args.size() < 3 ? JsBytes.length(source) - start : integerArg(args[2]);
        if (start < 0 || n < 0 || start + n > JsBytes.length(source))
          throw new JsException('RangeError: ArrayBuffer view exceeds bounds.');
        runtime.budget.allocate(1);
        JsValue view = JsBytes.alias(source, 'uint8array', start, n);
        view.byteBuffer = source;
        return view;
      }
      if (args.size() > 1)
        throw new JsException('TypeError: Extra Uint8Array bounds require an ArrayBuffer.');
      if (source.kind == 'undefined')
        n = 0;
      else if (source.kind == 'number')
        n = integerArg(source);
      else if (source.kind == 'array')
        n = source.items.size();
      else if (JsTypedBuffers.typed(source))
        n = source.wordLength;
      else if (source.kind == 'uint8array')
        n = JsBytes.length(source);
      else
        throw new JsException('TypeError: Uint8Array expects a length, array, or byte buffer.');
      JsValue result = JsBytes.create('uint8array', n, runtime);
      if (source.kind == 'uint8array')
        JsBytes.copy(result, 0, source, 0, n, runtime);
      else if (source.kind != 'number' && source.kind != 'undefined')
        for (Integer i = 0; i < n; i++) {
          runtime.budget.tick();
          JsBytes.write(result, i, toByte(runtime.getProperty(source, String.valueOf(i))));
        }
      return result;
    }
    if (name.equals('web.Blob')) {
      arity(args, 1, 2);
      expectKind(args[0], 'array');
      List<JsValue> parts = new List<JsValue>();
      Integer n = 0;
      for (Integer i = 0; i < args[0].items.size(); i++) {
        runtime.budget.tick();
        JsValue part = runtime.getProperty(args[0], String.valueOf(i));
        JsValue snapshot = part.kind == 'uint8array' ||
          part.kind == 'blob'
          ? JsBytes.slice(part, 0, JsBytes.length(part), runtime)
          : JsBytes.fromBlob(Blob.valueOf(stringArg(part)), 'uint8array', runtime);
        n += JsBytes.length(snapshot);
        JsBytes.check(n);
        parts.add(snapshot);
      }
      JsValue result = JsBytes.create('blob', n, runtime);
      result.scalar = '';
      Integer start = 0;
      for (JsValue part : parts) {
        JsBytes.copy(result, start, part, 0, JsBytes.length(part), runtime);
        start += JsBytes.length(part);
      }
      if (args.size() == 2) {
        expectKind(args[1], 'object');
        JsValue mime = args[1].props.get('type');
        if (mime != null)
          result.scalar = stringArg(mime).toLowerCase();
      }
      return result;
    }
    if (name == 'Apex.blobToBase64') {
      arity(args, 1, 1);
      expectKind(args[0], 'blob');
      return JsValue.str(EncodingUtil.base64Encode(JsBytes.toBlob(args[0], runtime)));
    }
    if (name.equals('Function.apply') || name.equals('Function.call')) {
      if (receiver == null || (receiver.kind != 'function' && receiver.kind != 'native')) {
        throw new JsException('TypeError: Invalid function receiver.');
      }
      if (
        JsLibraryBuiltins.enabled &&
        name == 'Function.apply' &&
        receiver.kind == 'native' &&
        receiver.nativeName == 'web.String.fromCharCode' &&
        args.size() == 2 &&
        (args[1].kind == 'uint8array' ||
        args[1].kind == 'array' ||
        JsTypedBuffers.typed(args[1]))
      ) {
        JsValue bytes = args[1];
        Integer length = bytes.kind == 'uint8array'
          ? JsBytes.length(bytes)
          : bytes.kind == 'array' ? bytes.items.size() : bytes.wordLength;
        if (length > 65536)
          throw new JsException('BudgetError: Character output size exceeded.');
        List<String> chunks = new List<String>();
        for (Integer start = 0; start < length; start += 512) {
          Integer count = Math.min(512, length - start);
          runtime.budget.tick(count);
          if (bytes.kind == 'uint8array' && bytes.bytePages != null)
            chunks.add(bytes.bytePages.text(bytes.byteOffset + start, count));
          else {
            List<Integer> codes = new List<Integer>();
            for (Integer i = 0; i < count; i++) {
              if (bytes.kind == 'uint8array')
                codes.add(JsBytes.read(bytes, start + i));
              else {
                JsValue value = runtime.getProperty(bytes, String.valueOf(start + i));
                Double raw = value.kind == 'undefined' ||
                  value.kind == 'null' ||
                  value.nanNumber
                  ? 0
                  : value.kind == 'boolean' ? ((Boolean) value.scalar ? 1 : 0) : value.asNumber();
                Double whole = raw < 0 ? Math.ceil(raw) : Math.floor(raw);
                codes.add((whole - Math.floor(whole / 65536) * 65536).intValue());
              }
            }
            chunks.add(String.fromCharArray(codes));
          }
        }
        return JsValue.str(String.join(chunks, ''));
      }
      List<JsValue> passed = new List<JsValue>();
      if (name.equals('Function.apply')) {
        arity(args, 0, 2);
        if (args.size() == 2 && args[1].kind != 'undefined' && args[1].kind != 'null') {
          if (args[1].kind == 'array') {
            for (Integer i = 0; i < args[1].items.size(); i++) {
              runtime.budget.tick();
              passed.add(runtime.getProperty(args[1], String.valueOf(i)));
            }
          } else {
            if (!JsObjectNatives.objectLike(args[1]))
              throw new JsException('TypeError: apply requires an array-like object.');
            JsValue size = runtime.getProperty(args[1], 'length');
            Integer length = size.kind == 'undefined' ? 0 : integerArg(size);
            if (length < 0 || length > 5000)
              throw new JsException('BudgetError: apply argument count exceeded.');
            for (Integer i = 0; i < length; i++) {
              runtime.budget.tick();
              passed.add(runtime.getProperty(args[1], String.valueOf(i)));
            }
          }
        }
      } else {
        for (Integer i = 1; i < args.size(); i++) {
          passed.add(args[i]);
        }
      }
      return runtime.invoke(receiver, passed, args.isEmpty() ? null : args[0]);
    }
    if (name == 'uint8.set') {
      expectReceiver(receiver, 'uint8array');
      arity(args, 1, 2);
      JsValue source = args[0];
      Integer offset = args.size() < 2 || args[1].kind == 'undefined' ? 0 : integerArg(args[1]);
      if (source.kind != 'uint8array') {
        if (source.kind != 'array' && !JsTypedBuffers.typed(source))
          throw new JsException('TypeError: set requires an array or typed buffer.');
        Integer n = source.kind == 'array' ? source.items.size() : source.wordLength;
        JsValue snapshot = JsBytes.create('uint8array', n, runtime);
        for (Integer i = 0; i < n; i++) {
          runtime.budget.tick();
          JsBytes.write(snapshot, i, toByte(runtime.getProperty(source, String.valueOf(i))));
        }
        source = snapshot;
      }
      JsBytes.copy(receiver, offset, source, 0, JsBytes.length(source), runtime);
      return new JsValue('undefined');
    }
    if (name == 'uint8.slice' || name == 'uint8.subarray') {
      expectReceiver(receiver, 'uint8array');
      arity(args, 0, 2);
      Integer n = JsBytes.length(receiver),
        start = args.isEmpty() ? 0 : sliceIndex(args[0], n),
        endIndex = args.size() < 2 || args[1].kind == 'undefined' ? n : sliceIndex(args[1], n);
      endIndex = Math.max(start, endIndex);
      if (name == 'uint8.slice')
        return JsBytes.slice(receiver, start, endIndex - start, runtime);
      runtime.budget.allocate(1);
      JsValue view = JsBytes.alias(receiver, 'uint8array', start, endIndex - start);
      view.byteBuffer = JsBytes.buffer(receiver);
      return view;
    }
    if (name == 'string.indexOf') {
      expectReceiver(receiver, 'string');
      arity(args, 1, 2);
      String text = stringArg(receiver);
      Integer start = args.size() == 1 || args[1].kind == 'undefined' ? 0 : integerArg(args[1]);
      start = Math.max(0, Math.min(text.length(), start));
      return JsValue.num(Double.valueOf(text.indexOf(stringArg(args[0]), start)));
    }
    if (name == 'array.concat' || name == 'array.splice')
      return JsArrayNatives.mutate(name, args, receiver, runtime);
    if (name.equals('array.slice') || name.equals('uint8.slice') || name.equals('string.slice')) {
      if (name == 'array.slice')
        return JsArrayNatives.slice(args, receiver, runtime);
      arity(args, 0, 2);
      Integer length = stringArg(receiver).length();
      Integer start = args.isEmpty() ? 0 : sliceIndex(args[0], length);
      Integer stop = args.size() < 2 ||
        args[1].kind == 'undefined'
        ? length
        : sliceIndex(args[1], length);
      stop = Math.max(start, stop);
      if (receiver.kind == 'string') {
        return JsValue.str(stringArg(receiver).substring(start, stop));
      }
      JsValue result = new JsValue(receiver.kind);
      runtime.budget.allocate(stop - start);
      for (Integer i = start; i < stop; i++) {
        if (receiver.kind == 'array') {
          result.items.add(receiver.items[i]);
        } else {
          result.bytes.add(receiver.bytes[i]);
        }
      }
      return result;
    }
    if (name.startsWith('string.')) {
      return stringMethod(name, args, receiver, runtime);
    }
    throw new JsException('TypeError: Unknown web native ' + name);
  }

  private static JsValue stringMethod(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    String text = stringArg(receiver);
    if (name == 'string.codePointAt') {
      arity(args, 0, 1);
      Integer index = args.isEmpty() || args[0].kind == 'undefined' ? 0 : integerArg(args[0]);
      if (index < 0 || index >= text.length())
        return new JsValue('undefined');
      Integer first = text.charAt(index);
      if (first >= 55296 && first <= 56319 && index + 1 < text.length()) {
        Integer second = text.charAt(index + 1);
        if (second >= 56320 && second <= 57343)
          return JsValue.num(Double.valueOf((first - 55296) * 1024 + second - 56320 + 65536));
      }
      return JsValue.num(Double.valueOf(first));
    }
    if (name.equals('string.match')) {
      arity(args, 1, 1);
      expectKind(args[0], 'regexp');
      if (!args[0].flags.contains('g')) {
        throw new JsException('TypeError: match currently requires a global regex.');
      }
      Matcher matcher = regexMatcher(args[0], text);
      JsValue result = new JsValue('array');
      while (matcher.find()) {
        runtime.budget.tick();
        runtime.budget.allocate(1);
        result.items.add(JsValue.str(matcher.group()));
      }
      return result.items.isEmpty() ? new JsValue('null') : result;
    }
    if (name.equals('string.charCodeAt')) {
      arity(args, 0, 1);
      Integer index = args.isEmpty() ? 0 : integerArg(args[0]);
      if (index < 0 || index >= text.length()) {
        throw new JsException('RangeError: NaN from charCodeAt is outside this subset.');
      }
      return JsValue.num(Double.valueOf(text.charAt(index)));
    }
    if (name.equals('string.padStart')) {
      arity(args, 1, 2);
      Integer length = Math.max(0, integerArg(args[0]));
      if (length > 65536) {
        throw new JsException('BudgetError: String size exceeded.');
      }
      String fill = args.size() == 2 ? stringArg(args[1]) : ' ';
      if (fill.length() == 0 || length <= text.length()) {
        return JsValue.str(text);
      }
      Integer needed = length - text.length();
      List<String> chunks = new List<String>();
      for (Integer i = 0; i < needed; i += fill.length()) {
        runtime.budget.tick();
        chunks.add(fill.substring(0, Math.min(fill.length(), needed - i)));
      }
      return JsValue.str(String.join(chunks, '') + text);
    }
    if (name.equals('string.split')) {
      arity(args, 1, 1);
      String separator = stringArg(args[0]);
      JsValue result = new JsValue('array');
      if (separator.length() == 0) {
        for (Integer i = 0; i < text.length(); i++) {
          runtime.budget.tick();
          runtime.budget.allocate(1);
          result.items.add(JsValue.str(text.substring(i, i + 1)));
        }
      } else {
        Integer cursor = 0;
        Integer found = text.indexOf(separator, cursor);
        while (found >= 0) {
          runtime.budget.tick();
          runtime.budget.allocate(1);
          result.items.add(JsValue.str(text.substring(cursor, found)));
          cursor = found + separator.length();
          found = text.indexOf(separator, cursor);
        }
        runtime.budget.allocate(1);
        result.items.add(JsValue.str(text.substring(cursor)));
      }
      return result;
    }
    if (name.equals('string.replace')) {
      arity(args, 2, 2);
      Boolean callback = args[1].kind == 'function' || args[1].kind == 'native';
      String replacement = callback ? null : stringArg(args[1]);
      if (!callback && replacement.contains('$')) {
        throw new JsException(
          'TypeError: Replacement substitutions are outside this regex subset.'
        );
      }
      if (args[0].kind == 'string') {
        String search = stringArg(args[0]);
        Integer found = text.indexOf(search);
        if (callback && found >= 0) {
          replacement = runtime.invoke(
              args[1],
              new List<JsValue>{
                JsValue.str(search),
                JsValue.num(Double.valueOf(found)),
                receiver
              },
              null
            )
            .asString();
        }
        return JsValue.str(
          found < 0
            ? text
            : text.substring(0, found) + replacement + text.substring(found + search.length())
        );
      }
      expectKind(args[0], 'regexp');
      Matcher matcher = regexMatcher(args[0], text);
      List<String> parts = new List<String>();
      Integer cursor = 0;
      Integer outputLength = 0;
      while (matcher.find()) {
        runtime.budget.tick();
        String before = text.substring(cursor, matcher.start());
        if (callback) {
          List<JsValue> callbackArgs = new List<JsValue>{ JsValue.str(matcher.group()) };
          for (Integer i = 1; i <= matcher.groupCount(); i++) {
            String capture = matcher.group(i);
            callbackArgs.add(capture == null ? new JsValue('undefined') : JsValue.str(capture));
          }
          callbackArgs.add(JsValue.num(Double.valueOf(matcher.start())));
          callbackArgs.add(receiver);
          runtime.budget.allocate(callbackArgs.size());
          replacement = runtime.invoke(args[1], callbackArgs, null).asString();
        }
        outputLength += before.length() + replacement.length();
        if (outputLength > 65536) {
          throw new JsException('BudgetError: String size exceeded.');
        }
        parts.add(before);
        parts.add(replacement);
        cursor = matcher.end();
        if (!args[0].flags.contains('g')) {
          break;
        }
      }
      parts.add(text.substring(cursor));
      return JsValue.str(String.join(parts, ''));
    }
    throw new JsException('TypeError: Unsupported string method.');
  }
  private static Matcher regexMatcher(JsValue regex, String text) {
    if (regex.compiledRegex == null)
      regex.compiledRegex = Pattern.compile(
        (regex.flags.contains('i') ? '(?i)' : '') + translatedPattern(regex.pattern)
      );
    return regex.compiledRegex.matcher(text);
  }
  private static String translatedPattern(String source) {
    return translatedPattern(source, false);
  }
  public static String translatedPattern(String source, Boolean multiline) {
    if (source == '[.*+?^${}()|[\\]\\\\]')
      return '[\\x2e\\x2a\\x2b\\x3f\\x5e\\x24\\x7b\\x7d\\x28\\x29\\x7c\\x5b\\x5d\\x5c]';
    List<String> parts = new List<String>();
    Boolean characterClass = false;
    for (Integer i = 0; i < source.length(); i++) {
      String c = source.substring(i, i + 1);
      if (c == '\\' && i + 1 < source.length()) {
        String next = source.substring(++i, i + 1);
        if (next == '0')
          parts.add('\\x00');
        else if (next == 'v')
          parts.add('\\x0b');
        else if (next == 'b' && characterClass)
          parts.add('\\x08');
        else if (next == 's')
          parts.add(
            '[\\u0009-\\u000d\\u0020\\u00a0\\u1680\\u2000-\\u200a\\u2028\\u2029\\u202f\\u205f\\u3000\\ufeff]'
          );
        else
          parts.add('\\' + next);
      } else {
        if (c == '[')
          characterClass = true;
        else if (c == ']')
          characterClass = false;
        parts.add(
          c == '.' && !characterClass
            ? '[^\\n\\r\\u2028\\u2029]'
            : c == '$' && !characterClass && !multiline ? '\\z' : c
        );
      }
    }
    return String.join(parts, '');
  }
  public static Integer toByte(JsValue value) {
    if (JsLibraryBuiltins.enabled && value.nanNumber)
      return 0;
    Double raw = value.kind == 'null' ||
      value.kind == 'undefined'
      ? 0.0
      : value.kind == 'boolean' ? ((Boolean) value.scalar ? 1.0 : 0.0) : value.asNumber();
    Double whole = raw < 0 ? Math.ceil(raw) : Math.floor(raw);
    Double rem = whole - Math.floor(whole / Double.valueOf('256')) * Double.valueOf('256');
    return Integer.valueOf(String.valueOf(rem).replace('.0', ''));
  }
  private static Integer integerArg(JsValue value) {
    if (JsLibraryBuiltins.enabled && value.nanNumber)
      return 0;
    Double raw = value.asNumber();
    Double truncated = raw < 0 ? Math.ceil(raw) : Math.floor(raw);
    if (truncated > 2147483647 || truncated < -2147483647) {
      throw new JsException('RangeError: Index is outside this bounded host subset.');
    }
    return Integer.valueOf(String.valueOf(truncated).replace('.0', ''));
  }
  private static Integer sliceIndex(JsValue value, Integer length) {
    Integer index = integerArg(value);
    return index < 0 ? Math.max(0, length + index) : Math.min(length, index);
  }
  private static Integer indexKey(String key) {
    if (key.length() == 0 || key.length() > 8) {
      return -1;
    }
    for (Integer i = 0; i < key.length(); i++) {
      if (!'0123456789'.contains(key.substring(i, i + 1))) {
        return -1;
      }
    }
    Integer value = Integer.valueOf(key);
    return String.valueOf(value).equals(key) ? value : -1;
  }
  private static List<Integer> bytesOf(JsValue value) {
    if (value.kind == 'uint8array' || value.kind == 'blob') {
      return value.bytes;
    }
    expectKind(value, 'string');
    String hexValue = EncodingUtil.convertToHex(Blob.valueOf((String) value.scalar));
    List<Integer> bytes = new List<Integer>();
    for (Integer i = 0; i < hexValue.length(); i += 2) {
      bytes.add(
        HEX.indexOf(hexValue.substring(i, i + 1)) * 16 +
        HEX.indexOf(hexValue.substring(i + 1, i + 2))
      );
    }
    return bytes;
  }
  private static Blob toApexBlob(List<Integer> bytes) {
    if (HEX_BYTES == null) {
      HEX_BYTES = new List<String>();
      for (Integer i = 0; i < 256; i++) {
        Integer high = i / 16;
        Integer low = Math.mod(i, 16);
        HEX_BYTES.add(HEX.substring(high, high + 1) + HEX.substring(low, low + 1));
      }
    }
    List<String> hexParts = new List<String>();
    for (Integer value : bytes) {
      hexParts.add(HEX_BYTES[value]);
    }
    return EncodingUtil.convertFromHex(String.join(hexParts, ''));
  }
  private static void checkBufferSize(Integer length) {
    JsBytes.check(length);
  }
  private static String stringArg(JsValue value) {
    expectKind(value, 'string');
    return (String) value.scalar;
  }
  private static void expectKind(JsValue value, String kind) {
    if (value == null || value.kind != kind) {
      throw new JsException('TypeError: Expected ' + kind);
    }
  }
  private static void expectReceiver(JsValue value, String kind) {
    expectKind(value, kind);
  }
  private static void arity(List<JsValue> args, Integer minimum, Integer maximum) {
    if (args.size() < minimum || args.size() > maximum) {
      throw new JsException('TypeError: Unsupported host argument count.');
    }
  }
}
