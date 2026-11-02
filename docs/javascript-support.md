# Supported JavaScript and policies

ApexJS implements a bounded subset rather than delegating to a browser or Node engine. The following describes the release API; runtime internals are not a promise of broader compatibility.

## Language and builtins

| Area                | Supported behavior                                                                                                                                          |
| ------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Values              | JSON primitives, objects, arrays, null/undefined; floating-point numbers                                                                                    |
| Functions           | Function declarations/expressions, closures, recursion within limits, arguments, call/apply, supported constructor/prototype behavior                       |
| Variables           | var, let, const, lexical scopes, hoisting, temporal dead zones                                                                                              |
| Control flow        | if/else, loops including array for/of, break/continue, return, try/catch/finally, throw; consume Map iterators with next()                                  |
| Operators           | Arithmetic, comparisons, strict equality, bitwise operations, property/index access, supported delete/in behavior; use strict equality in calculations      |
| Arrays              | map/filter/reduce, mutation, slice/splice/concat/join, sort, includes/indexOf, forEach/some/every, Array.from (one array-like value, no mapper), of/isArray |
| Objects             | keys, data/getter property descriptors, prototypes, and supported Object methods; setter descriptors are unavailable                                        |
| Map                 | Keyed storage, object-key identity, ordered live iterators, keys/values/entries                                                                             |
| Strings and regex   | Common string operations; bounded regular expressions with g/i/m flags and supported translation to the Apex regex engine                                   |
| Date                | Bounded construction/parsing and supported methods; all calendar/time operations use UTC                                                                    |
| JSON                | Parse/stringify with size, value, depth, and cycle controls                                                                                                 |
| Math and conversion | Documented native Math functions, Number/String/Boolean conversions, parseInt/parseFloat, isNaN/isFinite within the finite-number subset                    |
| Bytes               | Bounded Uint8Array/ArrayBuffer/Blob and supported typed-buffer operations; not an external file-generation service                                          |
| Promise             | Bounded synchronous executors, resolve/reject, then/catch, and runnable microtasks drained before output; no timers or external event loop                  |
| Host helpers        | Bounded hashing, base64/text/byte helpers, and runtime metrics through the explicit Apex host table; no arbitrary Apex dispatch                             |

Use the [tested examples](examples.md) as starting points. The runtime is not certified for complete ECMAScript conformance. Regular-expression dialects, number edge cases, Date parsing, and some prototype details differ from full JavaScript engines. In particular, Infinity is not generally admitted, and exact decimal arithmetic is not provided.

## Unavailable capabilities

Dynamic eval/Function compilation, arbitrary Apex class resolution, SOQL/DML from scripts, HTTP/fetch, browser DOM/canvas, Node modules, ESM imports, classes, arrow syntax, async/await, workers, timers, and external event loops are unavailable. Promises needing outside work fail rather than waiting indefinitely.

Only JSON-data copies of Flow values enter the VM. Source resources are loaded by configured Apex code, not by script-controlled network access. Returned record-shaped objects are not persisted automatically.

## Default release policies

| Policy                            | Value                                                       |
| --------------------------------- | ----------------------------------------------------------- |
| Combined input JSON               | 524,288 characters                                          |
| Returned/prepared JSON            | 524,288 characters each                                     |
| Individual JavaScript string      | 65,536 characters                                           |
| JSON.parse input string           | 65,536 characters                                           |
| JSON nesting                      | 32 levels                                                   |
| Default / maximum requested steps | 100,000 / 500,000                                           |
| Value allocations                 | Depends on the requested step budget; 25,000 at the default |
| Synchronous combined source       | 262,144 characters, including library wrappers              |
| Synchronous tokens / AST nodes    | 32,768 / 16,384                                             |
| Returned record collection        | 2,000 records                                               |
| Portwood normalization            | Depth 16 and 10,000 nodes                                   |
| Available template tags list      | Up to 300 representative entries                            |
| Console output                    | 50 entries, up to 1,000 characters per line                 |
| Byte/typed buffer policy          | 32,768 bytes; other budgets can be reached first            |
| Promise jobs                      | Up to 10,000, subject to normal budgets                     |

Character policies count string length, not UTF-8 bytes or document-file size. No fixed collection-slot limit is imposed. These policies do not override Salesforce governor limits, and are not measured maximum workload sizes.

CPU and heap guards normally leave 10% of the platform transaction allowance reserved, with minimum reserves of 750 ms CPU and 500,000 bytes heap. Other Flow/Apex work consumes the same transaction limits. Guards are cooperative and cannot guarantee that every platform governor failure is caught. Provide fault paths and test realistic bulk workloads.

Explicit API policies apply to all release entry points. Host-only implementation flags are internal and unsupported configuration; administrators cannot increase them through Flow inputs.
