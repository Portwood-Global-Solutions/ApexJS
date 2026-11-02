/** Shared bounded byte operations. Larger buffers use compact pages and can leave the VM as a Blob. */
public class JsBytes {
  public static Integer trustedMaxBytes;
  public static Boolean trustedPagedStorage = false;
  private static final String HEX = '0123456789abcdef';
  private static List<String> hexPairs;
  public static Integer maximum() {
    Integer value = trustedMaxBytes == null ? 32768 : trustedMaxBytes;
    if (value < 1 || value > 4194304)
      throw new JsException('BudgetError: Invalid byte-buffer policy.');
    return value;
  }
  public static void check(Integer n) {
    if (n < 0 || n > maximum())
      throw new JsException('BudgetError: Byte buffer exceeds ' + maximum() + ' bytes.');
  }
  public static Integer length(JsValue value) {
    return value.byteLength == null ? value.bytes.size() : value.byteLength;
  }
  public static Integer read(JsValue value, Integer index) {
    return value.bytePages == null
      ? value.bytes[value.byteOffset + index]
      : value.bytePages.read(value.byteOffset + index);
  }
  public static void write(JsValue value, Integer index, Integer byteValue) {
    if (value.bytePages == null)
      value.bytes[value.byteOffset + index] = byteValue;
    else
      value.bytePages.write(value.byteOffset + index, byteValue);
  }
  public static JsValue create(String kind, Integer n, JsRuntime runtime) {
    check(n);
    runtime.budget.guard();
    JsValue result = new JsValue(kind);
    result.byteLength = n;
    if (kind == 'uint8array' && runtime.byteArrayPrototype != null) {
      result.explicitPrototype = true;
      result.prototypeParent = runtime.byteArrayPrototype;
    }
    if (trustedPagedStorage) {
      runtime.budget.allocate((n + 511) / 512 + 1);
      result.bytes = null;
      result.bytePages = new JsBytePages(n);
    } else {
      runtime.budget.allocate(n + 1);
      for (Integer i = 0; i < n; i++)
        result.bytes.add(0);
    }
    return result;
  }
  public static JsValue alias(JsValue source, String kind, Integer start, Integer n) {
    JsValue result = new JsValue(kind);
    result.bytes = source.bytes;
    result.bytePages = source.bytePages;
    result.byteOffset = source.byteOffset + start;
    result.byteLength = n;
    if (kind == 'uint8array' && source.kind == 'uint8array') {
      result.explicitPrototype = source.explicitPrototype;
      result.prototypeParent = source.prototypeParent;
    }
    return result;
  }
  public static JsValue buffer(JsValue value) {
    if (value.byteBuffer == null) {
      Integer n = value.bytePages == null ? value.bytes.size() : value.bytePages.capacity;
      value.byteBuffer = alias(value, 'arraybuffer', -value.byteOffset, n);
      value.byteBuffer.explicitPrototype = true;
    }
    return value.byteBuffer;
  }
  public static void copy(
    JsValue target,
    Integer offset,
    JsValue source,
    Integer start,
    Integer count,
    JsRuntime runtime
  ) {
    if (
      offset < 0 ||
      start < 0 ||
      count < 0 ||
      offset + count > length(target) ||
      start + count > length(source)
    )
      throw new JsException('RangeError: Byte copy exceeds buffer bounds.');
    runtime.budget.guard();
    if (target.bytePages != null && source.bytePages != null) {
      List<String> snapshot = new List<String>();
      runtime.budget.allocate((count + 511) / 512 + 1);
      for (Integer i = 0; i < count; i += 512) {
        Integer size = Math.min(512, count - i);
        runtime.budget.tick(size);
        snapshot.add(source.bytePages.text(source.byteOffset + start + i, size));
      }
      Integer i = 0;
      for (String text : snapshot) {
        runtime.budget.poll();
        target.bytePages.putText(target.byteOffset + offset + i, text);
        i += text.length();
      }
    } else {
      runtime.budget.allocate(count);
      List<Integer> snapshot = new List<Integer>();
      for (Integer i = 0; i < count; i++) {
        runtime.budget.tick();
        snapshot.add(read(source, start + i));
      }
      for (Integer i = 0; i < count; i++) {
        runtime.budget.tick();
        write(target, offset + i, snapshot[i]);
      }
    }
    runtime.budget.guard();
  }
  public static JsValue slice(JsValue source, Integer start, Integer count, JsRuntime runtime) {
    JsValue result = create(source.kind, count, runtime);
    copy(result, 0, source, start, count, runtime);
    return result;
  }
  public static JsValue fromBlob(Blob data, String kind, JsRuntime runtime) {
    return fromHex(EncodingUtil.convertToHex(data), kind, runtime);
  }
  public static JsValue fromHex(String text, String kind, JsRuntime runtime) {
    JsValue result = create(kind, text.length() / 2, runtime);
    if (result.bytePages != null) {
      for (Integer start = 0; start < length(result); start += 512) {
        Integer count = Math.min(512, length(result) - start);
        runtime.budget.tick(count);
        List<Integer> codes = new List<Integer>();
        for (Integer i = start; i < start + count; i++)
          codes.add(
            HEX.indexOf(text.substring(i * 2, i * 2 + 1)) * 16 +
            HEX.indexOf(text.substring(i * 2 + 1, i * 2 + 2))
          );
        result.bytePages.putText(start, String.fromCharArray(codes));
      }
    } else
      for (Integer i = 0; i < length(result); i++) {
        runtime.budget.tick();
        write(
          result,
          i,
          HEX.indexOf(text.substring(i * 2, i * 2 + 1)) * 16 +
          HEX.indexOf(text.substring(i * 2 + 1, i * 2 + 2))
        );
      }
    return result;
  }
  public static Blob toBlob(JsValue value, JsRuntime runtime) {
    if (hexPairs == null) {
      hexPairs = new List<String>();
      for (Integer i = 0; i < 256; i++)
        hexPairs.add(
          HEX.substring(i / 16, i / 16 + 1) + HEX.substring(Math.mod(i, 16), Math.mod(i, 16) + 1)
        );
    }
    List<String> chunks = new List<String>();
    for (Integer start = 0; start < length(value); start += 512) {
      Integer count = Math.min(512, length(value) - start);
      runtime.budget.tick(count);
      List<String> parts = new List<String>();
      for (Integer i = start; i < start + count; i++)
        parts.add(hexPairs[read(value, i)]);
      chunks.add(String.join(parts, ''));
    }
    return EncodingUtil.convertFromHex(String.join(chunks, ''));
  }
  public static JsValue copyNative(List<JsValue> args, JsRuntime runtime) {
    if (args.size() != 3 || args[0].kind != 'uint8array' || args[2].kind != 'uint8array')
      throw new JsException('TypeError: copyBytes expects target, offset, source.');
    Integer offset = args[1].asNumber().intValue(), n = length(args[2]);
    copy(args[0], offset, args[2], 0, n, runtime);
    return JsValue.num(Double.valueOf(offset + n));
  }
}
