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
        return utcMilliseconds(
          year,
          Integer.valueOf(legacy.group(1)) - 1,
          Integer.valueOf(legacy.group(2)),
          Integer.valueOf(legacy.group(4)) * 3600000L + Integer.valueOf(legacy.group(5)) * 60000L
        );
      }
    }
    Matcher iso = Pattern.compile(
        '^(\\d{4})-(\\d{2})-(\\d{2})(?:[T ](\\d{2}):(\\d{2})(?::(\\d{2})(?:\\.(\\d+))?)?)?Z?$'
      )
      .matcher(text);
    if (!iso.matches())
      throw new JsException('TypeError: Unsupported Date input: ' + text);
    Integer month = Integer.valueOf(iso.group(2)), day = Integer.valueOf(iso.group(3));
    Integer hour = iso.group(4) == null ? 0 : Integer.valueOf(iso.group(4));
    Integer minute = iso.group(5) == null ? 0 : Integer.valueOf(iso.group(5));
    Integer second = iso.group(6) == null ? 0 : Integer.valueOf(iso.group(6));
    Integer ms = iso.group(7) == null ? 0 : Integer.valueOf((iso.group(7) + '00').substring(0, 3));
    if (
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31 ||
      hour > 24 ||
      minute > 59 ||
      second > 59 ||
      (hour == 24 &&
      (minute > 0 ||
      second > 0 ||
      ms > 0))
    )
      throw new JsException('TypeError: Unsupported Date input: ' + text);
    return utcMilliseconds(
      Integer.valueOf(iso.group(1)),
      month - 1,
      day,
      hour * 3600000L + minute * 60000L + second * 1000L + ms
    );
  }
  private static Long components(List<JsValue> args) {
    Integer year = numberAt(args, 0, 1970);
    if (year >= 0 && year <= 99)
      year += 1900;
    return utcMilliseconds(
      year,
      numberAt(args, 1, 0),
      numberAt(args, 2, 1),
      numberAt(args, 3, 0) * 3600000L +
        numberAt(args, 4, 0) * 60000L +
        numberAt(args, 5, 0) * 1000L +
        numberAt(args, 6, 0)
    );
  }
  // Dates are computed in the proleptic Gregorian calendar, as JavaScript does.
  // Apex date constructors and getters are not used: for a user whose locale
  // has a Buddhist-era calendar (th_TH), Date.newInstance and
  // Datetime.newInstanceGmt read the year as a Buddhist year, and yearGmt()
  // adds 543 to it.
  private static final Long DAY_MS = 86400000L;
  private static Long floorDiv(Long dividend, Long divisor) {
    Long quotient = dividend / divisor;
    return quotient * divisor != dividend && (dividend < 0) != (divisor < 0)
      ? quotient - 1
      : quotient;
  }
  // month is zero-based and may be outside 0-11; day may be outside the month.
  private static Long utcMilliseconds(Long year, Long month, Long day, Long timeOfDay) {
    Long years = floorDiv(month, 12);
    year += years;
    month = month - years * 12 + 1;
    Long y = month <= 2 ? year - 1 : year;
    Long era = floorDiv(y, 400);
    Long yearOfEra = y - era * 400;
    Long dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5;
    Long dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear;
    return (era * 146097 + dayOfEra - 719468 + day - 1) * DAY_MS + timeOfDay;
  }
  // Returns year, zero-based month, day, hour, minute, second, millisecond and
  // day of the week (0 is Sunday).
  private static List<Long> utcFields(Long milliseconds) {
    Long days = floorDiv(milliseconds, DAY_MS);
    Long timeOfDay = milliseconds - days * DAY_MS;
    Long shifted = days + 719468;
    Long era = floorDiv(shifted, 146097);
    Long dayOfEra = shifted - era * 146097;
    Long yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146096) / 365;
    Long dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100);
    Long monthIndex = (5 * dayOfYear + 2) / 153;
    Long month = monthIndex < 10 ? monthIndex + 3 : monthIndex - 9;
    return new List<Long>{
      yearOfEra + era * 400 + (month <= 2 ? 1 : 0),
      month - 1,
      dayOfYear - (153 * monthIndex + 2) / 5 + 1,
      timeOfDay / 3600000,
      Math.mod(timeOfDay, 3600000) / 60000,
      Math.mod(timeOfDay, 60000) / 1000,
      Math.mod(timeOfDay, 1000),
      days + 4 - floorDiv(days + 4, 7) * 7
    };
  }
  private static String padded(Long value, Integer width) {
    return String.valueOf(value).leftPad(width, '0');
  }
  private static void setDate(JsValue value, Long timestamp) {
    value.dateMilliseconds = timestamp;
    List<Long> utc = utcFields(timestamp);
    Long year = utc[0];
    value.scalar =
      (year >= 0 && year <= 9999
        ? padded(year, 4)
        : (year < 0 ? '-' : '+') + padded(Math.abs(year), 6)) +
      '-' +
      padded(utc[1] + 1, 2) +
      '-' +
      padded(utc[2], 2) +
      'T' +
      padded(utc[3], 2) +
      ':' +
      padded(utc[4], 2) +
      ':' +
      padded(utc[5], 2) +
      '.' +
      padded(utc[6], 3) +
      'Z';
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
      List<Long> utc = utcFields(milliseconds);
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
          List<JsValue> fields = new List<JsValue>();
          for (Integer i = 0; i < 7; i++)
            fields.add(JsValue.num(utc[i]));
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
      Long result = part == 'FullYear'
        ? utc[0]
        : part == 'Year'
            ? utc[0] - 1900
            : part == 'Month'
                ? utc[1]
                : part == 'Date'
                    ? utc[2]
                    : part == 'Day'
                        ? utc[7]
                        : part == 'Hours'
                            ? utc[3]
                            : part == 'Minutes' ? utc[4] : part == 'Seconds' ? utc[5] : utc[6];
      return JsValue.num(result);
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
