/** Bounded Array constructor/prototype and presence-aware array-like conversions used by library helpers. */
public class JsArrayNatives {
  public static Integer maxLength() {
    return JsLibraryBuiltins.enabled ? 65536 : 5000;
  }
  public static void install(JsScope scope, JsRuntime runtime) {
    runtime.arrayPrototype = new JsValue('array');
    runtime.arrayPrototype.explicitPrototype = true;
    runtime.arrayPrototype.prototypeParent = runtime.objectPrototype;
    runtime.arrayPrototype.props = new Map<String, JsValue>();
    JsValue ctor = JsValue.nativeFunction('Array.construct');
    ctor.constructorPrototype = runtime.arrayPrototype;
    ctor.props = new Map<String, JsValue>();
    for (String name : new List<String>{ 'isArray', 'from', 'of' }) {
      ctor.props.put(name, JsValue.nativeFunction('Array.' + name));
      ctor.attributes(name, false, true, true);
    }
    for (
      String name : new List<String>{
        'push',
        'pop',
        'shift',
        'unshift',
        'reverse',
        'sort',
        'indexOf',
        'includes',
        'join',
        'map',
        'filter',
        'reduce',
        'slice',
        'splice',
        'concat'
      }
    ) {
      runtime.arrayPrototype.props.put(name, JsValue.nativeFunction('array.' + name));
      runtime.arrayPrototype.attributes(name, false, true, true);
    }
    runtime.arrayPrototype.props.put('constructor', ctor);
    runtime.arrayPrototype.attributes('constructor', false, true, true);
    scope.declare('Array', ctor, true);
  }
  public static JsValue construct(List<JsValue> args, JsRuntime runtime) {
    JsValue value = new JsValue('array');
    runtime.budget.allocate(args.size() + 1);
    if (args.size() == 1 && args[0].kind == 'number') {
      Double size = args[0].asNumber();
      if (size < 0 || size != Math.floor(size) || size > maxLength())
        throw new JsException('RangeError: Invalid bounded Array length.');
      resize(value, size.intValue(), runtime);
      return value;
    }
    if (args.size() > maxLength())
      throw new JsException('BudgetError: Array size exceeded.');
    value.items.addAll(args);
    return value;
  }
  private static Integer length(JsValue value, JsRuntime runtime) {
    if (value.kind == 'null' || value.kind == 'undefined')
      throw new JsException('TypeError: Array-like value cannot be null.');
    JsValue size = runtime.getProperty(value, 'length');
    if (size.kind == 'undefined')
      return 0;
    Double n = size.asNumber();
    if (n > maxLength())
      throw new JsException('BudgetError: Array-like size exceeded.');
    return n <= 0 ? 0 : Math.floor(n).intValue();
  }
  public static JsValue fromArrayLike(List<JsValue> args, JsRuntime runtime) {
    if (args.size() != 1)
      throw new JsException('TypeError: Array.from currently accepts one array-like value.');
    JsValue input = args[0], result = new JsValue('array');
    runtime.budget.allocate(1);
    if (input.kind == 'mapiterator') {
      JsValue item;
      while ((item = JsMapIteration.take(input, runtime)) != null) {
        runtime.budget.tick();
        if (result.items.size() >= maxLength())
          throw new JsException('BudgetError: Array size exceeded.');
        runtime.budget.allocate(1);
        result.items.add(item);
      }
      return result;
    }
    if (input.kind == 'map')
      throw new JsException('TypeError: Map iteration requires additional backend support.');
    if (input.kind == 'string') {
      String s = (String) input.scalar;
      for (Integer i = 0; i < s.length(); i++) {
        runtime.budget.tick();
        if (result.items.size() >= maxLength())
          throw new JsException('BudgetError: Array size exceeded.');
        Integer startIndex = i, endIndex = i + 1, first = s.charAt(i);
        if (first >= 55296 && first <= 56319 && endIndex < s.length()) {
          Integer second = s.charAt(endIndex);
          if (second >= 56320 && second <= 57343) {
            endIndex++;
            i++;
          }
        }
        runtime.budget.allocate(1);
        result.items.add(JsValue.str(s.substring(startIndex, endIndex)));
      }
      return result;
    }
    Integer n = length(input, runtime);
    runtime.budget.allocate(n);
    for (Integer i = 0; i < n; i++) {
      runtime.budget.tick();
      result.items.add(runtime.getProperty(input, String.valueOf(i)));
    }
    return result;
  }
  public static JsValue slice(List<JsValue> args, JsValue receiver, JsRuntime runtime) {
    if (args.size() > 2)
      throw new JsException('TypeError: slice accepts at most two indices.');
    Integer n = length(receiver, runtime);
    Integer start = args.isEmpty() ? 0 : offset(args[0], n),
      endIndex = args.size() < 2 || args[1].kind == 'undefined' ? n : offset(args[1], n);
    endIndex = Math.max(start, endIndex);
    JsValue result = new JsValue('array');
    runtime.budget.allocate(endIndex - start + 1);
    for (Integer i = start; i < endIndex; i++) {
      runtime.budget.tick();
      String key = String.valueOf(i);
      result.items.add(slot(receiver, i, runtime));
    }
    return result;
  }
  public static JsValue indexOf(List<JsValue> args, JsValue receiver, JsRuntime runtime) {
    if (args.size() > 2)
      throw new JsException('TypeError: indexOf accepts at most two arguments.');
    Integer n = length(receiver, runtime), start = args.size() < 2 ? 0 : offset(args[1], n);
    JsValue needle = args.isEmpty() ? new JsValue('undefined') : args[0];
    for (Integer i = start; i < n; i++) {
      runtime.budget.tick();
      String key = String.valueOf(i);
      if (
        JsObjectNatives.objectLike(receiver) &&
        !runtime.binary('in', JsValue.str(key), receiver).truthy()
      )
        continue;
      if (JsObjectNatives.same(runtime.getProperty(receiver, key), needle))
        return JsValue.num(Double.valueOf(i));
    }
    return JsValue.num(Double.valueOf('-1'));
  }
  public static JsValue includes(List<JsValue> args, JsValue receiver, JsRuntime runtime) {
    if (args.size() > 2)
      throw new JsException('TypeError: includes accepts at most two arguments.');
    Integer n = length(receiver, runtime),
      start = args.size() < 2 || args[1].nanNumber ? 0 : offset(args[1], n);
    JsValue needle = args.isEmpty() ? new JsValue('undefined') : args[0];
    for (Integer i = start; i < n; i++) {
      runtime.budget.tick();
      JsValue value = runtime.getProperty(receiver, String.valueOf(i));
      if (
        value.nanNumber && needle.nanNumber ||
        !value.nanNumber && !needle.nanNumber && JsObjectNatives.same(value, needle)
      )
        return JsValue.bool(true);
    }
    return JsValue.bool(false);
  }
  /** Grow with absent properties, charging slots without allocating a JS object per hole. */
  public static void resize(JsValue value, Integer n, JsRuntime runtime) {
    if (n < 0 || n > maxLength())
      throw new JsException('BudgetError: Array size exceeded.');
    if (n > value.items.size())
      runtime.budget.allocate(n - value.items.size());
    while (value.items.size() < n) {
      runtime.budget.tick();
      value.items.add(null);
    }
    while (value.items.size() > n) {
      runtime.budget.tick();
      value.items.remove(value.items.size() - 1);
    }
  }
  /** null means no property anywhere in the prototype chain; undefined is a real value. */
  public static JsValue slot(JsValue value, Integer index, JsRuntime runtime) {
    if (value.kind == 'array' && index < value.items.size() && value.items[index] != null)
      return value.items[index];
    String key = String.valueOf(index);
    if (
      JsObjectNatives.objectLike(value) && !runtime.binary('in', JsValue.str(key), value).truthy()
    )
      return null;
    if (value.kind == 'string' && index >= ((String) value.scalar).length())
      return null;
    return runtime.getProperty(value, key);
  }
  private static void putSlot(JsValue value, Integer index, JsValue item, JsRuntime runtime) {
    if (item == null)
      runtime.deleteProperty(value, JsValue.str(String.valueOf(index)));
    else
      runtime.writeProperty(value, String.valueOf(index), item);
  }
  private static JsValue lengthValue(JsValue value) {
    return JsValue.num(Double.valueOf(value.items.size()));
  }
  public static JsValue mutate(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    if (receiver == null || receiver.kind != 'array')
      throw new JsException('TypeError: Invalid array method receiver.');
    Integer n = receiver.items.size();
    if (name == 'array.pop' || name == 'array.shift') {
      if (!args.isEmpty())
        throw new JsException('TypeError: Native function expects zero arguments.');
      if (n == 0)
        return new JsValue('undefined');
      JsValue result = runtime.getProperty(
        receiver,
        name == 'array.pop' ? String.valueOf(n - 1) : '0'
      );
      if (name == 'array.shift')
        for (Integer i = 1; i < n; i++) {
          runtime.budget.tick();
          putSlot(receiver, i - 1, slot(receiver, i, runtime), runtime);
        }
      resize(receiver, n - 1, runtime);
      return result;
    }
    if (name == 'array.push' || name == 'array.unshift') {
      if (n + args.size() > maxLength())
        throw new JsException('BudgetError: Array size exceeded.');
      if (name == 'array.unshift' && !args.isEmpty())
        for (Integer i = n - 1; i >= 0; i--) {
          runtime.budget.tick();
          putSlot(receiver, i + args.size(), slot(receiver, i, runtime), runtime);
        }
      for (Integer i = 0; i < args.size(); i++)
        runtime.writeProperty(receiver, String.valueOf(name == 'array.push' ? n + i : i), args[i]);
      resize(receiver, n + args.size(), runtime);
      return lengthValue(receiver);
    }
    if (name == 'array.reverse') {
      if (!args.isEmpty())
        throw new JsException('TypeError: Native function expects zero arguments.');
      for (Integer i = 0; i < n / 2; i++) {
        runtime.budget.tick();
        Integer j = n - 1 - i;
        JsValue lower = slot(receiver, i, runtime), upper = slot(receiver, j, runtime);
        putSlot(receiver, i, upper, runtime);
        putSlot(receiver, j, lower, runtime);
      }
      return receiver;
    }
    if (name == 'array.concat') {
      JsValue result = new JsValue('array');
      List<JsValue> sources = new List<JsValue>{ receiver };
      sources.addAll(args);
      for (JsValue source : sources) {
        Integer count = source.kind == 'array' ? source.items.size() : 1;
        if (result.items.size() + count > maxLength())
          throw new JsException('BudgetError: Array size exceeded.');
        runtime.budget.allocate(count);
        for (Integer i = 0; i < count; i++) {
          runtime.budget.tick();
          result.items.add(source.kind == 'array' ? slot(source, i, runtime) : source);
        }
      }
      return result;
    }
    if (name == 'array.splice') {
      JsValue removed = new JsValue('array');
      if (args.isEmpty())
        return removed;
      Integer start = offset(args[0], n),
        count = n - start,
        inserted = Math.max(0, args.size() - 2);
      if (args.size() > 1) {
        Double d = args[1].kind == 'undefined' ? 0 : args[1].asNumber();
        count = d < 0 ? 0 : d > n - start ? n - start : Math.floor(d).intValue();
      }
      if (n - count + inserted > maxLength())
        throw new JsException('BudgetError: Array size exceeded.');
      runtime.budget.allocate(count);
      for (Integer i = 0; i < count; i++) {
        runtime.budget.tick();
        removed.items.add(slot(receiver, start + i, runtime));
      }
      if (inserted < count) {
        for (Integer i = start; i < n - count; i++) {
          runtime.budget.tick();
          putSlot(receiver, i + inserted, slot(receiver, i + count, runtime), runtime);
        }
      } else if (inserted > count) {
        for (Integer i = n - count - 1; i >= start; i--) {
          runtime.budget.tick();
          putSlot(receiver, i + inserted, slot(receiver, i + count, runtime), runtime);
        }
      }
      for (Integer i = 0; i < inserted; i++)
        runtime.writeProperty(receiver, String.valueOf(start + i), args[i + 2]);
      resize(receiver, n - count + inserted, runtime);
      return removed;
    }
    throw new JsException('TypeError: Unknown array method.');
  }
  public static JsValue sort(List<JsValue> args, JsValue receiver, JsRuntime runtime) {
    if (receiver == null || receiver.kind != 'array')
      throw new JsException('TypeError: Invalid array sort receiver.');
    if (args.size() > 1)
      throw new JsException('TypeError: sort accepts at most one comparator.');
    JsValue comparator = args.isEmpty() ? new JsValue('undefined') : args[0];
    if (
      comparator.kind != 'undefined' &&
      comparator.kind != 'function' &&
      comparator.kind != 'native'
    )
      throw new JsException('TypeError: Sort comparator must be callable.');
    Integer length = receiver.items.size(), undefinedCount = 0;
    List<JsValue> values = new List<JsValue>();
    runtime.budget.allocate(length * 2);
    for (Integer i = 0; i < length; i++) {
      runtime.budget.tick();
      JsValue item = slot(receiver, i, runtime);
      if (item == null)
        continue;
      if (item.kind == 'undefined')
        undefinedCount++;
      else
        values.add(item);
    }
    List<JsValue> work = new List<JsValue>();
    for (Integer i = 0; i < values.size(); i++)
      work.add(null);
    // Stable bottom-up merge avoids recursive Apex calls and quadratic insertion sorting.
    for (Integer width = 1; width < values.size(); width *= 2) {
      for (Integer start = 0; start < values.size(); start += width * 2) {
        Integer middle = Math.min(start + width, values.size()),
          endIndex = Math.min(start + width * 2, values.size()),
          left = start,
          right = middle;
        for (Integer at = start; at < endIndex; at++) {
          runtime.budget.tick();
          Boolean takeLeft;
          if (left >= middle)
            takeLeft = false;
          else if (right >= endIndex)
            takeLeft = true;
          else if (comparator.kind == 'undefined')
            takeLeft = values[left].asString().compareTo(values[right].asString()) <= 0;
          else
            takeLeft =
              runtime.invoke(comparator, new List<JsValue>{ values[left], values[right] }, null)
                .asNumber() <= 0;
          work[at] = values[takeLeft ? left++ : right++];
        }
      }
      List<JsValue> previous = values;
      values = work;
      work = previous;
    }
    Integer next = 0;
    for (JsValue item : values)
      runtime.writeProperty(receiver, String.valueOf(next++), item);
    for (Integer i = 0; i < undefinedCount; i++)
      runtime.writeProperty(receiver, String.valueOf(next++), new JsValue('undefined'));
    while (next < length) {
      runtime.budget.tick();
      runtime.deleteProperty(receiver, JsValue.str(String.valueOf(next++)));
    }
    return receiver;
  }
  private static Integer offset(JsValue value, Integer n) {
    if (value.kind == 'undefined')
      return 0;
    Double d = value.asNumber();
    d = d < 0 ? Math.ceil(d) : Math.floor(d);
    if (d < -n)
      return 0;
    if (d > n)
      return n;
    Integer i = d.intValue();
    return i < 0 ? Math.max(0, n + i) : i;
  }
}
