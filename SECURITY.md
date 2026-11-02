# Security model

ApexJS is a bounded interpreter for trusted, admin-authored Flow calculations. It does not execute JavaScript using an external service or expose arbitrary Apex methods.

## Trust and data

- Flow authors control source, library choices, and input data. Review that code and library licenses before activation. Do not treat untrusted user-supplied source as an approved calculation.
- Scripts receive JSON-data copies. They cannot query or update Salesforce records, dispatch arbitrary Apex, make callouts, use Node modules, or access a browser DOM.
- The configured loader can read JavaScript Static Resources. It checks names, types, source size, and remaining query capacity; it does not fetch URLs. Libraries run with the same input-data access as the calculation.
- Typed record outputs construct records only. Separate Flow record actions determine persistence. The Flow's execution mode, sharing, and data-access design remain important; ApexJS does not apply an additional field-level-security filter to values already supplied by Flow.
- Results and console messages can contain input data. Apply your usual controls to downstream storage, documents, screens, and logs. ApexJS does not write calculation data to debug logs automatically.

## Resource controls

Source, JSON, strings, depth, values, steps, console entries, buffers, Promise jobs, CPU, and heap are bounded. Budget failures do not return partial calculated/prepared data. Uncatchable Salesforce governor failures remain possible; configure fault paths and validate realistic transaction workloads.

Dynamic eval/Function compilation and arbitrary Apex dispatch remain unavailable, including through function constructors. Host-only runtime flags are implementation details, not supported ways to bypass the public release policies.

## Reporting an issue

Contact the Portwood Global Solutions maintainers through your existing private support channel. Do not open a public issue containing org credentials, real customer records, sensitive calculations, or exploit payloads with secrets. Provide the release version, a minimized synthetic example, expected/actual behavior, and relevant error category.

See [JavaScript support](docs/javascript-support.md) for compatibility boundaries. Coverage and a successful deployment do not establish security certification or guarantee every workload.
