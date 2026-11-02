/** Native indexes accelerate Map lookup while the ordered key/value list preserves identity and order. */
public class JsMapStore {
  /** Trusted benchmark control; not exposed through Flow or the JS capability table. */
  public static Boolean linearLookupForLab = false;
  public class Index {
    public Map<String, Integer> strings = new Map<String, Integer>();
    public Map<Double, Integer> numbers = new Map<Double, Integer>();
    public Map<Integer, Integer> objects = new Map<Integer, Integer>();
    public Map<String, Integer> primitives = new Map<String, Integer>();
  }
  private static Integer nextIdentity = 0;
  private static Integer identity(JsValue value) {
    if (value.mapIdentity == null)
      value.mapIdentity = ++nextIdentity;
    return value.mapIdentity;
  }
  private static Double numberKey(JsValue value) {
    Double n = value.asNumber();
    return Math.abs(n) == 0 ? Double.valueOf('0') : n;
  }
  private static String primitiveKey(JsValue value) {
    return value.kind == 'boolean' ? ((Boolean) value.scalar ? 'true' : 'false') : value.kind;
  }
  public static Integer find(JsValue collection, JsValue key, JsRuntime runtime) {
    if (linearLookupForLab) {
      for (Integer i = 0; i < collection.items.size(); i += 2) {
        runtime.budget.tick();
        if (JsObjectNatives.same(collection.items[i], key))
          return i;
      }
      return -1;
    }
    if (collection.mapIndex == null)
      rebuild(collection, runtime);
    Integer result;
    if (key.kind == 'string')
      result = collection.mapIndex.strings.get((String) key.scalar);
    else if (key.kind == 'number')
      result = collection.mapIndex.numbers.get(numberKey(key));
    else if (JsObjectNatives.objectLike(key))
      result = collection.mapIndex.objects.get(identity(key));
    else
      result = collection.mapIndex.primitives.get(primitiveKey(key));
    return result == null ? -1 : result;
  }
  public static void record(JsValue collection, JsValue key, Integer position) {
    if (linearLookupForLab) {
      collection.mapIndex = null;
      return;
    }
    if (collection.mapIndex == null)
      collection.mapIndex = new Index();
    if (key.kind == 'string')
      collection.mapIndex.strings.put((String) key.scalar, position);
    else if (key.kind == 'number')
      collection.mapIndex.numbers.put(numberKey(key), position);
    else if (JsObjectNatives.objectLike(key))
      collection.mapIndex.objects.put(identity(key), position);
    else
      collection.mapIndex.primitives.put(primitiveKey(key), position);
  }
  public static void rebuild(JsValue collection, JsRuntime runtime) {
    collection.mapIndex = null;
    if (linearLookupForLab)
      return;
    collection.mapIndex = new Index();
    for (Integer i = 0; i < collection.items.size(); i += 2) {
      runtime.budget.tick();
      record(collection, collection.items[i], i);
    }
  }
}
