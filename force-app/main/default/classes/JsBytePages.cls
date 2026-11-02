/** Byte storage in 512-code-unit pages. Immutable page text makes snapshots independent. */
public class JsBytePages {
  public static final Integer PAGE_BYTES = 512;
  public Integer capacity;
  private List<String> pages = new List<String>();
  public JsBytePages(Integer length) {
    capacity = length;
    String zero = String.fromCharArray(new List<Integer>{ 0 }).repeat(PAGE_BYTES);
    for (Integer i = 0; i < (length + PAGE_BYTES - 1) / PAGE_BYTES; i++)
      pages.add(zero);
  }
  public Integer read(Integer index) {
    return pages[index / PAGE_BYTES].charAt(Math.mod(index, PAGE_BYTES));
  }
  public void write(Integer index, Integer value) {
    Integer page = index / PAGE_BYTES, offset = Math.mod(index, PAGE_BYTES);
    String text = pages[page];
    pages[page] =
      text.substring(0, offset) +
      String.fromCharArray(new List<Integer>{ value }) +
      text.substring(offset + 1);
  }
  public String text(Integer offset, Integer count) {
    if (count == 0)
      return '';
    Integer page = offset / PAGE_BYTES,
      start = Math.mod(offset, PAGE_BYTES),
      first = Math.min(count, PAGE_BYTES - start);
    return pages[page].substring(start, start + first) +
      (first < count ? pages[page + 1].substring(0, count - first) : '');
  }
  public void putText(Integer offset, String text) {
    if (text.length() == 0)
      return;
    Integer page = offset / PAGE_BYTES,
      start = Math.mod(offset, PAGE_BYTES),
      first = Math.min(text.length(), PAGE_BYTES - start);
    String old = pages[page];
    pages[page] = old.substring(0, start) + text.substring(0, first) + old.substring(start + first);
    if (first < text.length()) {
      old = pages[page + 1];
      pages[page + 1] = text.substring(first) + old.substring(text.length() - first);
    }
  }
}
