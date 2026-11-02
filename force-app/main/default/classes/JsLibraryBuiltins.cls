/** Bounded Date/string/RegExp host operations for standard-library operations. Dates use UTC. */
public class JsLibraryBuiltins {
  public static Boolean enabled = false;
  private static final Set<String> ARRAY_METHODS = new Set<String>{ 'forEach', 'some', 'every' };
  private static final Set<String> STRING_METHODS = new Set<String>{
    'charAt',
    'substr',
    'substring',
    'lastIndexOf',
    'match',
    'replace',
    'split',
    'search'
  };
  private static final Set<String> DATE_METHODS = new Set<String>{
    'getTime',
    'valueOf',
    'toISOString',
    'getFullYear',
    'getUTCFullYear',
    'getYear',
    'getMonth',
    'getUTCMonth',
    'getDate',
    'getUTCDate',
    'getDay',
    'getUTCDay',
    'getHours',
    'getUTCHours',
    'getMinutes',
    'getUTCMinutes',
    'getSeconds',
    'getUTCSeconds',
    'getMilliseconds',
    'getUTCMilliseconds',
    'getTimezoneOffset',
    'setTime',
    'setDate',
    'setUTCDate',
    'setFullYear',
    'setUTCFullYear',
    'setMonth',
    'setUTCMonth',
    'setHours',
    'setUTCHours',
    'setMinutes',
    'setUTCMinutes',
    'setSeconds',
    'setUTCSeconds',
    'setMilliseconds',
    'setUTCMilliseconds'
  };
  public static JsValue property(JsValue value, String key) {
    if (!enabled)
      return null;
    if (value.kind == 'date' && DATE_METHODS.contains(key))
      return JsValue.nativeFunction('library.date.' + key);
    if (
      value.kind == 'native' &&
      value.nativeName == 'web.Date' &&
      (key == 'UTC' ||
      key == 'now' ||
      key == 'parse')
    )
      return JsValue.nativeFunction('library.Date.' + key);
    if (value.kind == 'regexp') {
      if (key == 'exec' || key == 'test')
        return JsValue.nativeFunction('library.regex.' + key);
      if (key == 'source')
        return JsValue.str(value.pattern);
      if (key == 'global' || key == 'ignoreCase' || key == 'multiline')
        return JsValue.bool(
          value.flags.contains(key == 'global' ? 'g' : key == 'ignoreCase' ? 'i' : 'm')
        );
      if (key == 'lastIndex')
        return JsValue.num(0);
    }
    if (value.kind == 'array' && ARRAY_METHODS.contains(key))
      return JsValue.nativeFunction('library.array.' + key);
    if (value.kind == 'string' && STRING_METHODS.contains(key))
      return JsValue.nativeFunction('library.string.' + key);
    return null;
  }
  private static Integer numberAt(List<JsValue> args, Integer at, Integer fallback) {
    return at >= args.size() ||
      args[at].kind == 'undefined'
      ? fallback
      : args[at].nanNumber ? 0 : args[at].asNumber().intValue();
  }
  public static JsValue date(List<JsValue> args) {
    Long timestamp;
    if (args.isEmpty())
      timestamp = Datetime.now().getTime();
    else if (args.size() == 1) {
      JsValue value = args[0];
      timestamp = value.kind == 'date'
        ? value.dateMilliseconds
        : value.kind == 'string' ? parseDate(value.asString()) : value.asNumber().longValue();
    } else
      timestamp = components(args);
    JsValue result = new JsValue('date');
    setDate(result, timestamp);
    return result;
  }
  private static Long parseDate(String text) {
    if (text.contains('/')) {
      Matcher legacy = Pattern.compile(
          '^(\\d{1,2})/(\\d{1,2})/(\\d{2}|\\d{4}) (\\d{1,2}):(\\d{2}) UTC$'
        )
        .matcher(text);
      if (legacy.matches()) {
        Integer year = Integer.valueOf(legacy.group(3));
        if (year < 100)
          year += year < 50 ? 2000 : 1900;
        return Datetime.newInstanceGmt(
            year,
            Integer.valueOf(legacy.group(1)),
            Integer.valueOf(legacy.group(2)),
            Integer.valueOf(legacy.group(4)),
            Integer.valueOf(legacy.group(5)),
            0
          )
          .getTime();
      }
    }
    String value = text.replace('T', ' ').replace('Z', '');
    if (value.length() == 10)
      value += ' 00:00:00';
    Integer dot = value.indexOf('.'), ms = 0;
    if (dot >= 0) {
      String fraction = value.substring(dot + 1);
      ms = Integer.valueOf((fraction + '000').substring(0, 3));
      value = value.substring(0, dot);
    }
    try {
      return Datetime.valueOfGmt(value).getTime() + ms;
    } catch (Exception error) {
      throw new JsException('TypeError: Unsupported Date input: ' + text);
    }
  }
  private static Long components(List<JsValue> args) {
    Integer year = numberAt(args, 0, 1970), month = numberAt(args, 1, 0);
    if (year >= 0 && year <= 99)
      year += 1900;
    Integer years = (Integer) Math.floor(Double.valueOf(month) / 12);
    year += years;
    month -= years * 12;
    Date day = Date.newInstance(year, month + 1, 1).addDays(numberAt(args, 2, 1) - 1);
    return Datetime.newInstanceGmt(day, Time.newInstance(0, 0, 0, 0)).getTime() +
      numberAt(args, 3, 0) * 3600000L +
      numberAt(args, 4, 0) * 60000L +
      numberAt(args, 5, 0) * 1000L +
      numberAt(args, 6, 0);
  }
  private static void setDate(JsValue value, Long timestamp) {
    value.dateMilliseconds = timestamp;
    value.scalar = Datetime.newInstance(timestamp).formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
  }
  public static JsValue regex(List<JsValue> args) {
    JsValue value = new JsValue('regexp');
    value.pattern = args.isEmpty()
      ? ''
      : args[0].kind == 'regexp' ? args[0].pattern : args[0].asString();
    value.flags = args.size() < 2 ||
      args[1].kind == 'undefined'
      ? (args.size() > 0 && args[0].kind == 'regexp' ? args[0].flags : '')
      : args[1].asString();
    if (value.pattern.length() > 2048)
      throw new JsException('BudgetError: Regex pattern too long.');
    Set<String> flags = new Set<String>();
    for (Integer i = 0; i < value.flags.length(); i++) {
      String flag = value.flags.substring(i, i + 1);
      if (!'gim'.contains(flag) || flags.contains(flag))
        throw new JsException('TypeError: Raw-library regex supports g/i/m flags.');
      flags.add(flag);
    }
    value.props = new Map<String, JsValue>{ 'lastIndex' => JsValue.num(0) };
    value.attributes('lastIndex', false, true, false);
    return value;
  }
  private static Matcher matcher(JsValue regex, String text) {
    if (regex.compiledRegex == null) {
      String flags =
        (regex.flags.contains('i') ? '(?i)' : '') + (regex.flags.contains('m') ? '(?m)' : '');
      regex.compiledRegex = Pattern.compile(
        flags + JsWebNatives.translatedPattern(regex.pattern, regex.flags.contains('m'))
      );
    }
    return regex.compiledRegex.matcher(text);
  }
  private static JsValue matchArray(Matcher m, String text, JsRuntime runtime) {
    JsValue value = new JsValue('array');
    runtime.budget.allocate(m.groupCount() + 3);
    for (Integer i = 0; i <= m.groupCount(); i++) {
      String capture = m.group(i);
      value.items.add(capture == null ? new JsValue('undefined') : JsValue.str(capture));
    }
    value.props = new Map<String, JsValue>{
      'index' => JsValue.num(m.start()),
      'input' => JsValue.str(text)
    };
    return value;
  }
  private static String replacement(String format, Matcher m, String text) {
    List<String> result = new List<String>();
    for (Integer i = 0; i < format.length(); i++) {
      String ch = format.substring(i, i + 1);
      if (ch != '$' || i + 1 == format.length()) {
        result.add(ch);
        continue;
      }
      String next = format.substring(i + 1, i + 2);
      if (next == '$') {
        result.add('$');
        i++;
      } else if (next == '&') {
        result.add(m.group());
        i++;
      } else if (next == '`') {
        result.add(text.substring(0, m.start()));
        i++;
      } else if (next == '\'') {
        result.add(text.substring(m.end()));
        i++;
      } else if ('123456789'.contains(next)) {
        Integer captureIndex = Integer.valueOf(next), consumed = 1;
        if (i + 2 < format.length() && '0123456789'.contains(format.substring(i + 2, i + 3))) {
          Integer longer = captureIndex * 10 + Integer.valueOf(format.substring(i + 2, i + 3));
          if (longer <= m.groupCount()) {
            captureIndex = longer;
            consumed++;
          }
        }
        if (captureIndex <= m.groupCount()) {
          result.add(m.group(captureIndex) == null ? '' : m.group(captureIndex));
          i += consumed;
        } else
          result.add('$');
      } else
        result.add('$');
    }
    return String.join(result, '');
  }
  public static JsValue invoke(
    String name,
    List<JsValue> args,
    JsValue receiver,
    JsRuntime runtime
  ) {
    runtime.budget.poll();
    if (name.startsWith('library.array.')) {
      JsValue callback = args[0], thisArg = args.size() > 1 ? args[1] : null;
      Integer length = receiver.items.size();
      for (Integer i = 0; i < length; i++) {
        runtime.budget.tick();
        if (!runtime.binary('in', JsValue.str(String.valueOf(i)), receiver).truthy())
          continue;
        JsValue result = runtime.invoke(
          callback,
          new List<JsValue>{
            runtime.getProperty(receiver, String.valueOf(i)),
            JsValue.num(i),
            receiver
          },
          thisArg
        );
        if (name.endsWith('some') && result.truthy())
          return JsValue.bool(true);
        if (name.endsWith('every') && !result.truthy())
          return JsValue.bool(false);
      }
      return name.endsWith('forEach')
        ? new JsValue('undefined')
        : JsValue.bool(name.endsWith('every'));
    }
    if (name.startsWith('library.Date.')) {
      if (name.endsWith('now'))
        return JsValue.num(Double.valueOf(Datetime.now().getTime()));
      return JsValue.num(
        Double.valueOf(name.endsWith('UTC') ? components(args) : parseDate(args[0].asString()))
      );
    }
    if (name.startsWith('library.date.')) {
      String method = name.substring(13);
      Long milliseconds = receiver.dateMilliseconds;
      Datetime dateValue = Datetime.newInstance(milliseconds);
      if (method == 'toISOString')
        return JsValue.str((String) receiver.scalar);
      if (method == 'getTime' || method == 'valueOf')
        return JsValue.num(Double.valueOf(milliseconds));
      if (method == 'getTimezoneOffset')
        return JsValue.num(0);
      if (method.startsWith('set')) {
        if (method == 'setTime')
          setDate(receiver, args[0].asNumber().longValue());
        else {
          String part = method.replace('UTC', '').substring(3);
          List<JsValue> fields = new List<JsValue>{
            JsValue.num(dateValue.yearGmt()),
            JsValue.num(dateValue.monthGmt() - 1),
            JsValue.num(dateValue.dayGmt()),
            JsValue.num(dateValue.hourGmt()),
            JsValue.num(dateValue.minuteGmt()),
            JsValue.num(dateValue.secondGmt()),
            JsValue.num(Math.mod(milliseconds, 1000))
          };
          Integer start = part == 'FullYear'
            ? 0
            : part == 'Month'
                ? 1
                : part == 'Date'
                    ? 2
                    : part == 'Hours' ? 3 : part == 'Minutes' ? 4 : part == 'Seconds' ? 5 : 6;
          for (Integer i = 0; i < args.size() && start + i < 7; i++)
            fields[start + i] = args[i];
          setDate(receiver, components(fields));
        }
        return JsValue.num(Double.valueOf(receiver.dateMilliseconds));
      }
      String part = method.replace('UTC', '').substring(3);
      Integer result = part == 'FullYear'
        ? dateValue.yearGmt()
        : part == 'Year'
            ? dateValue.yearGmt() - 1900
            : part == 'Month'
                ? dateValue.monthGmt() - 1
                : part == 'Date'
                    ? dateValue.dayGmt()
                    : part == 'Day'
                        ? Math.mod(Date.newInstance(1970, 1, 4).daysBetween(dateValue.dateGmt()), 7)
                        : part == 'Hours'
                            ? dateValue.hourGmt()
                            : part == 'Minutes'
                                ? dateValue.minuteGmt()
                                : part == 'Seconds'
                                    ? dateValue.secondGmt()
                                    : Math.mod(milliseconds, 1000).intValue();
      return JsValue.num(result < 0 && part == 'Day' ? result + 7 : result);
    }
    String text = receiver.kind == 'string'
      ? receiver.asString()
      : args.isEmpty() ? 'undefined' : args[0].asString();
    if (text.length() > 65536)
      throw new JsException('BudgetError: Regex/string input too long.');
    if (name == 'library.string.charAt') {
      Integer index = numberAt(args, 0, 0);
      return JsValue.str(
        index < 0 || index >= text.length() ? '' : text.substring(index, index + 1)
      );
    }
    if (name == 'library.string.substr' || name == 'library.string.substring') {
      Integer length = text.length(), start = numberAt(args, 0, 0), finish;
      if (name.endsWith('substr')) {
        start = Math.min(length, start < 0 ? Math.max(0, length + start) : start);
        finish = Math.min(length, start + Math.max(0, numberAt(args, 1, length - start)));
      } else {
        start = Math.min(length, Math.max(0, start));
        finish = Math.min(length, Math.max(0, numberAt(args, 1, length)));
        if (finish < start) {
          Integer swap = start;
          start = finish;
          finish = swap;
        }
      }
      return JsValue.str(text.substring(start, finish));
    }
    if (name == 'library.string.lastIndexOf')
      return JsValue.num(
        text.lastIndexOf(
          args[0].asString(),
          Math.min(text.length(), numberAt(args, 1, text.length()))
        )
      );
    JsValue pattern = name.startsWith('library.regex.')
      ? receiver
      : args.isEmpty() ? regex(new List<JsValue>()) : args[0];
    if (pattern.kind != 'regexp') {
      if (name == 'library.string.match' || name == 'library.string.search')
        pattern = regex(new List<JsValue>{ pattern });
      else {
        if (name == 'library.string.split' && args.isEmpty()) {
          JsValue value = new JsValue('array');
          value.items.add(receiver);
          return value;
        }
        if (name == 'library.string.split' && args.size() > 1)
          throw new JsException('TypeError: String split limit is not supported in ApexJS.');
        return JsWebNatives.invoke('string.' + name.substring(15), args, receiver, runtime);
      }
    }
    Matcher m = matcher(pattern, text);
    JsValue matches = new JsValue('array');
    if (name.startsWith('library.regex.')) {
      Integer start = pattern.flags.contains('g')
        ? numberAt(new List<JsValue>{ pattern.props.get('lastIndex') }, 0, 0)
        : 0;
      Boolean found = false;
      while (m.find()) {
        runtime.budget.tick();
        if (m.start() >= start) {
          found = true;
          break;
        }
      }
      if (pattern.flags.contains('g'))
        pattern.props.put('lastIndex', JsValue.num(found ? m.end() : 0));
      return name.endsWith('test')
        ? JsValue.bool(found)
        : found ? matchArray(m, text, runtime) : new JsValue('null');
    }
    if (name == 'library.string.search')
      return JsValue.num(m.find() ? m.start() : -1);
    if (name == 'library.string.match') {
      if (!pattern.flags.contains('g'))
        return m.find() ? matchArray(m, text, runtime) : new JsValue('null');
      while (m.find()) {
        runtime.budget.tick();
        runtime.budget.allocate(1);
        matches.items.add(JsValue.str(m.group()));
      }
      pattern.props.put('lastIndex', JsValue.num(0));
      return matches.items.isEmpty() ? new JsValue('null') : matches;
    }
    Integer cursor = 0, total = 0;
    List<String> parts = new List<String>();
    while (m.find()) {
      runtime.budget.tick();
      if (name == 'library.string.split') {
        runtime.budget.allocate(1);
        matches.items.add(JsValue.str(text.substring(cursor, m.start())));
        for (Integer i = 1; i <= m.groupCount(); i++)
          matches.items.add(
            m.group(i) == null ? new JsValue('undefined') : JsValue.str(m.group(i))
          );
      } else {
        String value;
        if (args[1].kind == 'function' || args[1].kind == 'native') {
          List<JsValue> values = matchArray(m, text, runtime).items;
          values.add(JsValue.num(m.start()));
          values.add(receiver);
          value = runtime.invoke(args[1], values, null).asString();
        } else
          value = replacement(args[1].asString(), m, text);
        String before = text.substring(cursor, m.start());
        parts.add(before);
        parts.add(value);
        total += before.length() + value.length();
        if (total > 65536)
          throw new JsException('BudgetError: Replacement output too long.');
      }
      cursor = m.end();
      if (name != 'library.string.split' && !pattern.flags.contains('g'))
        break;
    }
    if (name == 'library.string.split') {
      matches.items.add(JsValue.str(text.substring(cursor)));
      return matches;
    }
    parts.add(text.substring(cursor));
    return JsValue.str(String.join(parts, ''));
  }
}
