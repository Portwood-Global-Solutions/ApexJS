/** Integer storage in small mutable-by-copy string pages; all callers enforce typed-buffer bounds. */
public class JsIntegerPages {
  private static final Integer ELEMENTS = 128;
  private String kindName;
  private Integer units;
  private List<String> pages = new List<String>();
  public JsIntegerPages(Integer length, String kindName) {
    this.kindName = kindName;
    units = kindName == 'Uint16Array' ? 1 : 2;
    String zero = String.fromCharArray(new List<Integer>{ 0 }).repeat(ELEMENTS * units);
    for (Integer i = 0; i < (length + ELEMENTS - 1) / ELEMENTS; i++)
      pages.add(zero);
  }
  public Double read(Integer index) {
    String page = pages[index / ELEMENTS];
    Integer offset = Math.mod(index, ELEMENTS) * units;
    if (units == 1)
      return Double.valueOf(page.charAt(offset));
    Integer word = (page.charAt(offset) << 16) | page.charAt(offset + 1);
    return kindName == 'Uint32Array' &&
      word < 0
      ? Double.valueOf(word) + Double.valueOf('4294967296')
      : Double.valueOf(word);
  }
  public void write(Integer index, Double value) {
    Integer pageIndex = index / ELEMENTS,
      offset = Math.mod(index, ELEMENTS) * units,
      word = value.longValue().intValue();
    String encoded = units == 1
      ? String.fromCharArray(new List<Integer>{ word & 65535 })
      : String.fromCharArray(new List<Integer>{ (word >>> 16) & 65535, word & 65535 });
    String page = pages[pageIndex];
    pages[pageIndex] = page.substring(0, offset) + encoded + page.substring(offset + units);
  }
}
