# ApexJS

Run JavaScript in Salesforce Flow, with named collections, optional JavaScript libraries, and typed outputs for later Flow elements. Execution stays in Apex; it uses no browser or external execution service.

This source release contains three Flow actions:

| Action                            | Use it for                                                                                                 |
| --------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| **Run JavaScript on Collections** | Calculations and transformations across named Flow data; optional CommonJS libraries from Static Resources |
| **Read JavaScript Result**        | Convert a returned JSON path into a native Flow value, collection, or Salesforce record collection         |
| **Prepare Portwood Data**         | Prepare named data or a calculation result for Portwood's JSON Data input; calculations are optional       |

Data setup uses **Name**, **Flow resource**, and **Add data**. Types are detected automatically. Account and Opportunity collections can be supplied together. Supported data includes records, text, numbers, booleans, dates, date/times, and scalar values. Literal values use ordinary form controls. JavaScript lives in a separate calculation section.

## Start here

- [Install ApexJS](docs/installation.md): unmanaged Salesforce installer and permission-set setup.
- [Admin guide](docs/admin-guide.md): installation, permissions, first Flow, downstream outputs, and troubleshooting.
- [Library guide](docs/libraries.md): upload and use your own compatible CommonJS libraries.
- [Examples](docs/examples.md): calculations, grouping, joining, deduplication, dates, and Portwood.
- [JavaScript support and limits](docs/javascript-support.md): the supported subset and execution policies.
- [Developer guide](docs/development.md): Apex API, tests, CI, and release checks.
- [Verification results](docs/verification.md): measured test coverage and real Salesforce Flow checks.
- [Architecture](docs/architecture.md) and [security](SECURITY.md).

For example, name an Opportunity collection **Orders**, then use:

```javascript
var total = input.Orders.reduce(function (sum, order) {
  return sum + (order.Amount || 0);
}, 0);
return { Summary: { Total: total, Count: input.Orders.length } };
```

Read `Summary.Total` as **Number** with Read JavaScript Result and use its `numberValue` output in a Decision or Assignment.

## Install

Use the [unmanaged package installation guide](docs/installation.md) for Salesforce installation links and post-install steps. No local development tools are needed for a package install. The package includes the interpreter, the three Flow actions, their editors, permission sets, and the example library.

### Install from source

Use an org that supports Apex, Flow, and Metadata API 68.0. Salesforce CLI is required for source deployment; Node.js 22 is required only for development tools and tests. The runtime has no npm dependency.

```sh
git clone https://github.com/Portwood-Global-Solutions/ApexJS.git
cd ApexJS
sf org login web --alias YOUR_ORG
sf project deploy start --source-dir force-app --target-org YOUR_ORG --test-level RunLocalTests --wait 30
sf org assign permset --name ApexJS_Author --target-org YOUR_ORG
```

Deploy to a sandbox first. See the [admin guide](docs/admin-guide.md#installation-and-permissions) for runtime-user permissions and the [developer guide](docs/development.md) for validation commands. Source deployment remains available alongside the unmanaged installer. Portwood is optional and is not bundled.

## Release scope

Version 0.1.0 is an initial source release of a bounded JavaScript subset. It is not a complete ECMAScript, Node.js, or browser runtime. Library compatibility must be tested; ESM imports, npm dependency resolution, DOM APIs, network requests, and external event loops are unavailable. Compatible CommonJS or UMD source is compiled inside Salesforce automatically.

The combined JSON input and JSON output policies are each **524,288 characters**. Individual JavaScript strings are limited to **65,536 characters**. CPU, heap, step, depth, and allocation budgets also apply, including other work in the same Flow transaction. A collection-count policy does not impose fixed slots; practical capacity depends on the data and work.

PDF/SVG rendering, pinned library accelerators, large-library Queueable experiments, benchmark assets, and downloaded vendor libraries are outside this release. The original research workspace is not part of this repository.

Licensed under the [MIT License](LICENSE). Development dependencies retain their own licenses. Downloaded vendor libraries are not bundled in the Salesforce package.
