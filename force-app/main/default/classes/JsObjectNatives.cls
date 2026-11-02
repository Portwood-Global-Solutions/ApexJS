/** Bounded, per-request object model. All prototypes are interpreter values, never Apex objects. */
public class JsObjectNatives {
  private static final Set<String> PRIMITIVES = new Set<String>{
    'undefined',
    'null',
    'string',
    'number',
    'boolean'
  };
  public static Boolean objectLike(JsValue value) {
    return value != null && !PRIMITIVES.contains(value.kind);
  }
  private static void arity(List<JsValue> args, Integer minimum, Integer maximum) {
    if (args.size() < minimum || args.size() > maximum) {
      throw new JsException('TypeError: Invalid object/collection argument count.');
    }
  }
  private static void requireObject(JsValue value) {
    if (!objectLike(value)) {
      throw new JsException('TypeError: Expected an object.');
    }
  }
  private static void dataTarget(JsValue value) {
    if (value.kind != 'object' && value.kind != 'function' && value.kind != 'native') {
      throw new JsException('TypeError: Data descriptors require an ordinary object or function.');
    }
  }
  private static String key(JsValue value) {
    String result = value.asString();
    if (result.equals('__proto__')) {
      throw new JsException(
        'TypeError: Direct __proto__ access is outside this subset; use Object prototype APIs.'
      );
    }
    return result;
  }
  public static void install(JsScope scope, JsRuntime runtime) {
    runtime.objectPrototype = new JsValue('object');
    runtime.objectPrototype.explicitPrototype = true;
    runtime.functionPrototype = JsValue.nativeFunction('Function.empty');
    runtime.functionPrototype.explicitPrototype = true;
    runtime.functionPrototype.prototypeParent = runtime.objectPrototype;
    runtime.functionPrototype.props = new Map<String, JsValue>();
    for (String method : new List<String>{ 'call', 'apply' }) {
      runtime.functionPrototype.props.put(method, JsValue.nativeFunction('Function.' + method));
      runtime.functionPrototype.attributes(method, false, true, true);
    }
    for (
      String method : new List<String>{
        'hasOwnProperty',
        'propertyIsEnumerable',
        'toString',
        'valueOf'
      }
    ) {
      runtime.objectPrototype.props.put(
        method,
        JsValue.nativeFunction('Object.prototype.' + method)
      );
      runtime.objectPrototype.attributes(method, false, true, true);
    }
    JsValue objectConstructor = JsValue.nativeFunction('Object.construct');
    objectConstructor.constructorPrototype = runtime.objectPrototype;
    objectConstructor.props = new Map<String, JsValue>();
    for (
      String method : new List<String>{
        'keys',
        'create',
        'getPrototypeOf',
        'setPrototypeOf',
        'defineProperty',
        'getOwnPropertyDescriptor',
        'assign',
        'hasOwn'
      }
    ) {
      objectConstructor.props.put(method, JsValue.nativeFunction('Object.' + method));
      objectConstructor.attributes(method, false, true, true);
    }
    runtime.objectPrototype.props.put('constructor', objectConstructor);
    runtime.objectPrototype.attributes('constructor', false, true, true);
    scope.declare('Object', objectConstructor, true);
    for (
      String name : new List<String>{
        'Error',
        'TypeError',
        'RangeError',
        'ReferenceError',
        'SyntaxError'
      }
    ) {
      JsValue constructor = scope.read(name);
      JsValue proto = new JsValue('object');
      proto.explicitPrototype = true;
      proto.prototypeParent = name == 'Error'
        ? runtime.objectPrototype
        : runtime.errorPrototypes.get('Error');
      proto.props.put('name', JsValue.str(name));
      proto.props.put('message', JsValue.str(''));
      proto.props.put('constructor', constructor);
      for (String property : new List<String>{ 'name', 'message', 'constructor' })
        proto.attributes(property, false, true, true);
      constructor.constructorPrototype = proto;
      runtime.errorPrototypes.put(name, proto);
    }
    for (
      String name : new List<String>{
        'Uint8Array',
        'Uint16Array',
        'Uint32Array',
        'Int32Array',
        'Blob',
        'Date',
        'RegExp'
      }
    ) {
      JsValue constructor = scope.read(name);
      constructor.constructorPrototype = new JsValue('object');
      if (name == 'Uint8Array')
        runtime.byteArrayPrototype = constructor.constructorPrototype;
      constructor.constructorPrototype.props.put('constructor', constructor);
      constructor.constructorPrototype.attributes('constructor', false, true, true);
    }
    JsValue mapConstructor = JsValue.nativeFunction('Map.construct');
    runtime.mapPrototype = new JsValue('object');
    mapConstructor.constructorPrototype = runtime.mapPrototype;
    runtime.mapPrototype.props.put('constructor', mapConstructor);
    runtime.mapPrototype.attributes('constructor', false, true, true);
    runtime.mapPrototype.props.put('size', JsValue.nativeFunction('Map.size'));
    runtime.mapPrototype.attributes('size', false, false, true);
    for (
      String method : new List<String>{
        'get',
        'set',
        'has',
        'delete',
        'clear',
        'keys',
        'values',
        'entries'
      }
    ) {
      runtime.mapPrototype.props.put(method, JsValue.nativeFunction('Map.' + method));
      runtime.mapPrototype.attributes(method, false, true, true);
    }
    scope.declare('Map', mapConstructor, true);
  }
  public static List<String> ownKeys(JsValue value, JsRuntime runtime) {
    if (value.kind == 'null' || value.kind == 'undefined') {
      throw new JsException('TypeError: Object.keys requires a value.');
    }
    List<String> keys = new List<String>();
    if (
      value.kind == 'array' ||
      value.kind == 'string' ||
      value.kind == 'uint8array' ||
      JsTypedBuffers.typed(value)
    ) {
      Integer size = value.kind == 'array'
        ? value.items.size()
        : value.kind == 'string'
            ? ((String) value.scalar).length()
            : JsTypedBuffers.typed(value) ? value.wordLength : JsBytes.length(value);
      for (Integer i = 0; i < size; i++) {
        runtime.budget.tick();
        if (value.kind != 'array' || value.items[i] != null)
          keys.add(String.valueOf(i));
      }
    }
    if (value.props != null)
      for (String property : value.props.keySet()) {
        runtime.budget.tick();
        if (value.enumerable(property))
          keys.add(property);
      }
    if (keys.size() > 5000) {
      throw new JsException('BudgetError: Object key count exceeded.');
    }
    return keys;
  }
  public static Boolean same(JsValue a, JsValue b) {
    if (a.kind != b.kind)
      return false;
    if (a.kind == 'null' || a.kind == 'undefined')
      return true;
    if (a.kind == 'string')
      return ((String) a.scalar).equals((String) b.scalar);
    if (a.kind == 'number')
      return (Math.abs(a.asNumber()) == 0 && Math.abs(b.asNumber()) == 0) ||
        a.asNumber() == b.asNumber();
    if (a.kind == 'boolean')
      return a.scalar == b.scalar;
    return a === b;
  }
  private static List<String> allOwnKeys(JsValue value) {
    List<String> keys = new List<String>();
    if (
      value.kind == 'array' ||
      value.kind == 'string' ||
      value.kind == 'uint8array' ||
      JsTypedBuffers.typed(value)
    ) {
      Integer size = value.kind == 'array'
        ? value.items.size()
        : value.kind == 'string'
            ? ((String) value.scalar).length()
            : JsTypedBuffers.typed(value) ? value.wordLength : JsBytes.length(value);
      for (Integer i = 0; i < size; i++)
        if (value.kind != 'array' || value.items[i] != null)
          keys.add(String.valueOf(i));
      if (value.kind == 'array' || value.kind == 'string')
        keys.add('length');
    }
    if (value.props != null)
      keys.addAll(value.props.keySet());
    if (value.kind == 'function') {
      for (String key : new List<String>{ 'name', 'length', 'prototype' })
        if (!keys.contains(key))
          keys.add(key);
    }
    if (value.kind == 'native' && value.constructorPrototype != null && !keys.contains('prototype'))
      keys.add('prototype');
    if (value.kind == 'error' && value.hasErrorMessage && !keys.contains('message'))
      keys.add('message');
    List<Long> indices = new List<Long>();
    List<String> strings = new List<String>();
    for (String key : keys) {
      Boolean numeric =
        key.length() > 0 &&
        key.length() <= 10 &&
        (key.length() == 1 || !key.startsWith('0'));
      if (numeric)
        for (Integer i = 0; i < key.length(); i++)
          if (!'0123456789'.contains(key.substring(i, i + 1))) {
            numeric = false;
            break;
          }
      Long n = numeric ? Long.valueOf(key) : null;
      if (n != null && n < 4294967295L)
        indices.add(n);
      else
        strings.add(key);
    }
    indices.sort();
    keys = new List<String>();
    for (Long n : indices)
      keys.add(String.valueOf(n));
    keys.addAll(strings);
    return keys;
  }
  public static List<String> orderedDataKeys(JsValue value) {
    List<String> result = new List<String>();
    for (String key : allOwnKeys(value))
      if (value.props != null && value.props.containsKey(key))
        result.add(key);
    return result;
  }
  private static Boolean ownEnumerable(JsValue value, String key) {
    if (value.props != null && value.props.containsKey(key))
      return value.enumerable(key);
    return value.kind == 'array' ||
      value.kind == 'string' ||
      value.kind == 'uint8array' ||
      JsTypedBuffers.typed(value)
      ? key != 'length'
      : false;
  }
  public static JsValue enumerationKeys(JsValue value, JsRuntime runtime) {
    JsValue result = new JsValue('array');
    runtime.budget.allocate(1);
    Set<String> visited = new Set<String>();
    Integer depth = 0;
    if (value.kind == 'null' || value.kind == 'undefined')
      return result;
    while (value != null) {
      if (++depth > 64)
        throw new JsException('BudgetError: Prototype depth exceeded.');
      for (String key : allOwnKeys(value)) {
        runtime.budget.tick();
        if (visited.contains(key))
          continue;
        visited.add(key);
        if (ownEnumerable(value, key)) {
          if (result.items.size() >= 5000)
            throw new JsException('BudgetError: Enumeration key count exceeded.');
          runtime.budget.allocate(1);
          result.items.add(JsValue.str(key));
        }
      }
      value = runtime.prototypeOf(value);
    }
    return result;
  }
  public static Boolean enumerationHas(JsValue value, String key, JsRuntime runtime) {
    Integer depth = 0;
    if (value.kind == 'null' || value.kind == 'undefined')
      return false;
    while (value != null) {
      if (++depth > 64)
        throw new JsException('BudgetError: Prototype depth exceeded.');
      if (runtime.ownProperty(value, key) != null)
        return ownEnumerable(value, key);
      value = runtime.prototypeOf(value);
    }
    return false;
  }
  private static Boolean hasProperty(JsValue target, String property, JsRuntime runtime) {
    Integer depth = 0;
    while (target != null) {
      if (++depth > 64)
        throw new JsException('BudgetError: Prototype depth exceeded.');
      if (runtime.ownProperty(target, property) != null)
        return true;
      target = runtime.prototypeOf(target);
    }
    return false;
  }
  private static void setPrototype(JsValue target, JsValue prototype, JsRuntime runtime) {
    requireObject(target);
    if (prototype.kind != 'null')
      requireObject(prototype);
    JsValue parent = prototype.kind == 'null' ? null : prototype;
    Integer depth = 0;
    while (parent != null) {
      if (parent === target)
        throw new JsException('TypeError: Cyclic prototype chain.');
      if (++depth > 63)
        throw new JsException('BudgetError: Prototype depth exceeded.');
      runtime.budget.poll();
      parent = runtime.prototypeOf(parent);
    }
    target.explicitPrototype = true;
    target.prototypeParent = prototype.kind == 'null' ? null : prototype;
  }
  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    runtime.budget.tick();
    if (name == 'Function.empty')
      return new JsValue('undefined');
    if (name == 'Object.construct') {
      arity(args, 0, 1);
      if (!args.isEmpty() && objectLike(args[0]))
        return args[0];
      if (!args.isEmpty() && args[0].kind != 'null' && args[0].kind != 'undefined')
        throw new JsException('TypeError: Primitive wrapper objects are outside this subset.');
      runtime.budget.allocate(1);
      return new JsValue('object');
    }
    if (name == 'Object.keys') {
      arity(args, 1, 1);
      JsValue result = new JsValue('array');
      for (String property : ownKeys(args[0], runtime)) {
        runtime.budget.allocate(1);
        result.items.add(JsValue.str(property));
      }
      return result;
    }
    if (name == 'Object.create') {
      arity(args, 1, 1);
      runtime.budget.allocate(1);
      JsValue value = new JsValue('object');
      setPrototype(value, args[0], runtime);
      return value;
    }
    if (name == 'Object.getPrototypeOf') {
      arity(args, 1, 1);
      requireObject(args[0]);
      JsValue proto = runtime.prototypeOf(args[0]);
      return proto == null ? new JsValue('null') : proto;
    }
    if (name == 'Object.setPrototypeOf') {
      arity(args, 2, 2);
      setPrototype(args[0], args[1], runtime);
      return args[0];
    }
    if (
      name == 'Object.hasOwn' ||
      name == 'Object.prototype.hasOwnProperty' ||
      name == 'Object.prototype.propertyIsEnumerable'
    ) {
      Boolean direct = name == 'Object.hasOwn';
      arity(args, direct ? 2 : 1, direct ? 2 : 1);
      JsValue target = direct ? args[0] : receiver;
      String property = key(direct ? args[1] : args[0]);
      if (target == null || target.kind == 'null' || target.kind == 'undefined')
        throw new JsException('TypeError: Own property check requires a value.');
      Boolean present = runtime.ownProperty(target, property) != null;
      if (name == 'Object.prototype.propertyIsEnumerable') {
        if (
          (target.kind == 'function' || target.kind == 'native') &&
          (property == 'prototype' ||
          property == 'name' ||
          property == 'length')
        )
          return JsValue.bool(false);
        if ((target.kind == 'array' || target.kind == 'string') && property == 'length')
          return JsValue.bool(false);
        present = present && target.enumerable(property);
      }
      return JsValue.bool(present);
    }
    if (name == 'Object.prototype.valueOf') {
      arity(args, 0, 0);
      requireObject(receiver);
      return receiver;
    }
    if (name == 'Object.prototype.toString') {
      arity(args, 0, 0);
      String kind = receiver == null ? 'undefined' : receiver.kind;
      String tag = kind == 'typedarray'
        ? (String) receiver.scalar
        : kind == 'array'
            ? 'Array'
            : kind == 'function' ||
                kind == 'native'
                ? 'Function'
                : kind == 'map'
                    ? 'Map'
                    : kind == 'arraybuffer'
                        ? 'ArrayBuffer'
                        : kind == 'promise'
                            ? 'Promise'
                            : kind == 'uint8array'
                                ? 'Uint8Array'
                                : kind == 'null'
                                    ? 'Null'
                                    : kind == 'undefined'
                                        ? 'Undefined'
                                        : kind == 'string'
                                            ? 'String'
                                            : kind == 'number'
                                                ? 'Number'
                                                : kind == 'boolean' ? 'Boolean' : 'Object';
      return JsValue.str('[object ' + tag + ']');
    }
    if (name == 'Object.assign') {
      arity(args, 1, 100);
      dataTarget(args[0]);
      for (Integer i = 1; i < args.size(); i++) {
        if (args[i].kind == 'null' || args[i].kind == 'undefined')
          continue;
        for (String property : ownKeys(args[i], runtime))
          runtime.writeProperty(
            args[0],
            key(JsValue.str(property)),
            runtime.getProperty(args[i], property)
          );
      }
      return args[0];
    }
    if (name == 'Object.defineProperty' || name == 'Object.getOwnPropertyDescriptor') {
      Boolean define = name == 'Object.defineProperty';
      arity(args, define ? 3 : 2, define ? 3 : 2);
      dataTarget(args[0]);
      JsValue target = args[0];
      String property = key(args[1]);
      if (target === runtime.mapPrototype && property == 'size')
        throw new JsException(
          'TypeError: Native accessor descriptor reflection is outside this subset.'
        );
      if (
        (target.kind == 'function' || target.kind == 'native') &&
        (property == 'prototype' ||
        property == 'name' ||
        property == 'length')
      )
        throw new JsException(
          'TypeError: Defining virtual function metadata is outside this subset.'
        );
      JsValue previous = target.props == null ? null : target.props.get(property);
      Boolean exists = previous != null;
      Boolean previousGetter = target.getters != null && target.getters.containsKey(property);
      if (!define) {
        if (!exists)
          return new JsValue('undefined');
        JsValue descriptor = new JsValue('object');
        if (previousGetter) {
          descriptor.props.put('get', target.getters.get(property));
          descriptor.props.put('set', new JsValue('undefined'));
        } else {
          descriptor.props.put('value', previous);
          descriptor.props.put('writable', JsValue.bool(target.writable(property)));
        }
        descriptor.props.put('enumerable', JsValue.bool(target.enumerable(property)));
        descriptor.props.put('configurable', JsValue.bool(target.configurable(property)));
        return descriptor;
      }
      requireObject(args[2]);
      JsValue descriptor = args[2];
      Boolean hasGet = hasProperty(descriptor, 'get', runtime),
        hasSet = hasProperty(descriptor, 'set', runtime),
        suppliesValue = hasProperty(descriptor, 'value', runtime),
        hasWritable = hasProperty(descriptor, 'writable', runtime);
      if ((hasGet || hasSet) && (suppliesValue || hasWritable))
        throw new JsException('TypeError: Cannot mix accessor and data descriptors.');
      JsValue getter = hasGet
        ? runtime.getProperty(descriptor, 'get')
        : previousGetter ? target.getters.get(property) : new JsValue('undefined');
      if (getter.kind != 'undefined' && getter.kind != 'function' && getter.kind != 'native')
        throw new JsException('TypeError: Getter must be callable or undefined.');
      if (hasSet && runtime.getProperty(descriptor, 'set').kind != 'undefined')
        throw new JsException('TypeError: Setter descriptors are outside the tested subset.');
      Boolean useGetter = hasGet || hasSet || previousGetter && !suppliesValue && !hasWritable;
      Boolean enumerable = exists && target.enumerable(property),
        writable = exists && !previousGetter && target.writable(property),
        configurable = exists && target.configurable(property);
      if (hasProperty(descriptor, 'enumerable', runtime))
        enumerable = runtime.getProperty(descriptor, 'enumerable').truthy();
      if (hasWritable)
        writable = runtime.getProperty(descriptor, 'writable').truthy();
      if (hasProperty(descriptor, 'configurable', runtime))
        configurable = runtime.getProperty(descriptor, 'configurable').truthy();
      JsValue value = suppliesValue
        ? runtime.getProperty(descriptor, 'value')
        : new JsValue('undefined');
      Boolean sameValue = same(previous == null ? new JsValue('undefined') : previous, value);
      if (
        previous != null &&
        previous.kind == 'number' &&
        value.kind == 'number' &&
        Math.abs(previous.asNumber()) == 0 &&
        Math.abs(value.asNumber()) == 0
      )
        sameValue =
          String.valueOf(previous.scalar).startsWith('-') ==
          String.valueOf(value.scalar).startsWith('-');
      if (exists && !target.configurable(property)) {
        if (
          configurable ||
          enumerable != target.enumerable(property) ||
          useGetter != previousGetter
        )
          throw new JsException('TypeError: Cannot redefine a non-configurable property.');
        if (
          previousGetter && hasGet && !same(target.getters.get(property), getter) ||
          !previousGetter && !target.writable(property) && (writable || suppliesValue && !sameValue)
        )
          throw new JsException('TypeError: Cannot redefine a non-configurable property.');
      }
      if (target.props == null)
        target.props = new Map<String, JsValue>();
      if (!exists)
        runtime.budget.allocate(1);
      if (useGetter) {
        if (target.getters == null)
          target.getters = new Map<String, JsValue>();
        target.getters.put(property, getter);
        target.props.put(property, new JsValue('undefined'));
        writable = false;
      } else {
        if (target.getters != null)
          target.getters.remove(property);
        target.props.put(
          property,
          suppliesValue ? value : exists && !previousGetter ? previous : new JsValue('undefined')
        );
      }
      target.attributes(property, enumerable, writable, configurable);
      return target;
    }
    if (name == 'Map.construct')
      throw new JsException('TypeError: Map requires new.');
    if (name == 'Map.new') {
      arity(args, 0, 1);
      runtime.budget.allocate(1);
      JsValue collection = new JsValue('map');
      collection.explicitPrototype = true;
      collection.prototypeParent = runtime.mapPrototype;
      if (!args.isEmpty() && args[0].kind != 'null' && args[0].kind != 'undefined') {
        if (args[0].kind != 'array')
          throw new JsException('TypeError: Map initializer requires dense entry pairs.');
        for (Integer i = 0; i < args[0].items.size(); i++) {
          runtime.budget.tick();
          JsValue pair = runtime.getProperty(args[0], String.valueOf(i));
          if (!objectLike(pair))
            throw new JsException('TypeError: Map initializer requires entry pairs.');
          invoke(
            'Map.set',
            new List<JsValue>{ runtime.getProperty(pair, '0'), runtime.getProperty(pair, '1') },
            collection,
            runtime
          );
        }
      }
      return collection;
    }
    if (name == 'Map.iteratorNext') {
      arity(args, 0, 0);
      return JsMapIteration.next(receiver, runtime);
    }
    if (name.startsWith('Map.')) {
      if (receiver == null || receiver.kind != 'map')
        throw new JsException('TypeError: Map method requires a Map receiver.');
      if (name == 'Map.keys' || name == 'Map.values' || name == 'Map.entries') {
        arity(args, 0, 0);
        return JsMapIteration.create(receiver, name.substring(4), runtime);
      }
      if (name == 'Map.clear') {
        arity(args, 0, 0);
        JsMapIteration.cleared(receiver);
        receiver.items.clear();
        receiver.mapIndex = null;
        return new JsValue('undefined');
      }
      arity(args, name == 'Map.set' ? 2 : 1, name == 'Map.set' ? 2 : 1);
      Integer found = JsMapStore.find(receiver, args[0], runtime);
      if (name == 'Map.get')
        return found < 0 ? new JsValue('undefined') : receiver.items[found + 1];
      if (name == 'Map.has')
        return JsValue.bool(found >= 0);
      if (name == 'Map.delete') {
        if (found >= 0) {
          JsMapIteration.removed(receiver, found);
          receiver.items.remove(found);
          receiver.items.remove(found);
          JsMapStore.rebuild(receiver, runtime);
        }
        return JsValue.bool(found >= 0);
      }
      if (name == 'Map.set') {
        if (found < 0) {
          if (receiver.items.size() >= 10000)
            throw new JsException('BudgetError: Map entry count exceeded.');
          runtime.budget.allocate(2);
          Integer position = receiver.items.size();
          JsMapIteration.appended(receiver, args[0], args[1], runtime);
          receiver.items.add(args[0]);
          receiver.items.add(args[1]);
          JsMapStore.record(receiver, args[0], position);
        } else {
          receiver.items[found + 1] = args[1];
          JsMapIteration.changed(receiver, found, args[1]);
        }
        return receiver;
      }
    }
    throw new JsException('TypeError: Unsupported object/collection native ' + name);
  }
}
