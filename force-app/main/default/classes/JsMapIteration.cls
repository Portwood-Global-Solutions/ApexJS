/** Live ordered Map iterators. History records keep deletion and reinsertion semantics stable. */
public class JsMapIteration {
  public class Entry {
    public JsValue key, value;
    public Boolean alive = true;
  }
  private static Entry entry(JsValue key, JsValue value, JsRuntime runtime) {
    runtime.budget.allocate(1);
    Entry result = new Entry();
    result.key = key;
    result.value = value;
    return result;
  }
  public static JsValue create(JsValue mapValue, String type, JsRuntime runtime) {
    if (mapValue.mapHistory == null) {
      mapValue.mapHistory = new List<Entry>();
      mapValue.mapRecords = new List<Entry>();
      for (Integer i = 0; i < mapValue.items.size(); i += 2) {
        runtime.budget.tick();
        Entry record = entry(mapValue.items[i], mapValue.items[i + 1], runtime);
        mapValue.mapHistory.add(record);
        mapValue.mapRecords.add(record);
      }
    }
    runtime.budget.allocate(1);
    JsValue iterator = new JsValue('mapiterator');
    iterator.iteratorMap = mapValue;
    iterator.iteratorType = type;
    iterator.props = new Map<String, JsValue>{
      'next' => JsValue.nativeFunction('Map.iteratorNext')
    };
    iterator.attributes('next', false, true, true);
    return iterator;
  }
  public static void appended(JsValue mapValue, JsValue key, JsValue value, JsRuntime runtime) {
    if (mapValue.mapHistory == null)
      return;
    if (mapValue.mapHistory.size() >= 10000)
      throw new JsException('BudgetError: Map iteration history exceeded.');
    Entry record = entry(key, value, runtime);
    mapValue.mapHistory.add(record);
    mapValue.mapRecords.add(record);
  }
  public static void changed(JsValue mapValue, Integer slot, JsValue value) {
    if (mapValue.mapHistory != null)
      mapValue.mapRecords[slot / 2].value = value;
  }
  public static void removed(JsValue mapValue, Integer slot) {
    if (mapValue.mapHistory != null) {
      mapValue.mapRecords[slot / 2].alive = false;
      mapValue.mapRecords.remove(slot / 2);
    }
  }
  public static void cleared(JsValue mapValue) {
    if (mapValue.mapHistory != null) {
      for (Entry record : mapValue.mapRecords)
        record.alive = false;
      mapValue.mapRecords.clear();
    }
  }
  public static JsValue take(JsValue iterator, JsRuntime runtime) {
    if (iterator == null || iterator.kind != 'mapiterator')
      throw new JsException('TypeError: Map iterator receiver required.');
    while (
      !iterator.iteratorFinished && iterator.iteratorCursor < iterator.iteratorMap.mapHistory.size()
    ) {
      runtime.budget.tick();
      Entry record = iterator.iteratorMap.mapHistory[iterator.iteratorCursor++];
      if (!record.alive)
        continue;
      if (iterator.iteratorType == 'keys')
        return record.key;
      if (iterator.iteratorType == 'values')
        return record.value;
      runtime.budget.allocate(3);
      JsValue pair = new JsValue('array');
      pair.items.add(record.key);
      pair.items.add(record.value);
      return pair;
    }
    iterator.iteratorFinished = true;
    return null;
  }
  public static JsValue next(JsValue iterator, JsRuntime runtime) {
    JsValue value = take(iterator, runtime);
    runtime.budget.allocate(3);
    JsValue result = new JsValue('object');
    result.props.put('done', JsValue.bool(value == null));
    result.props.put('value', value == null ? new JsValue('undefined') : value);
    return result;
  }
}
