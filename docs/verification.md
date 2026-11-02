# Release verification

Verified on 2026-11-01 for the initial 0.1.0 source release, using a fresh Salesforce scratch org with Metadata API 68.0. No Portwood installation was needed to deploy or test the adapter.

| Check                            | Result                                                                                                |
| -------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Apex tests                       | 88 passed, none failed                                                                                |
| Shipped production Apex coverage | 80.4% aggregate line coverage; repository gate: 80%                                                   |
| Editor tests                     | 17 passed across 6 suites                                                                             |
| Editor coverage                  | 92.98% lines/statements, 80.79% branches, 89.15% functions                                            |
| Real Flow execution              | All 3 included example Flows passed                                                                   |
| Flow Builder                     | Mixed Account/Opportunity inputs edited, saved as a new version, activated, and executed successfully |
| Source hygiene                   | Release surface checks, formatting, and a credential-pattern scan passed                              |

## Flow contracts exercised

- Multiple named record types in one action, including actual Account and Opportunity Get Records resources.
- Native Number, Date, and DateTime collections, including null elements and UTC values across a daylight-saving transition.
- A calculation supplied by a plain-text Flow Text Template.
- A Static Resource library loaded and executed with the calculation.
- Strict Number, Date collection, DateTime collection, and Opportunity record outputs consumed downstream.
- Empty input handling and no-code Portwood preparation.
- No DML performed by the calculation, result reader, or Portwood preparation actions. The integration runner creates and removes its own synthetic record fixtures separately.

The example Flows are in [`examples/main/default/flows`](../examples/main/default/flows). The saved-editor verification executed the activated Flow after saving, without redeploying its original XML first.

## Raw third-party source experiment

An unmodified 1,656-character CommonJS Adler-32 implementation from pako was uploaded temporarily as a Static Resource. ApexJS loaded its source and calculated **851975** for the byte sequence `[1, 2, 3]` with seed `1`, matching a separate Node.js execution. It used no offline compilation or source-specific native accelerator.

The temporary resource was removed after verification. Its source and research vendor bundles are not distributed in this repository. This proves the tested module path; larger libraries and different syntax still need their own compatibility and workload tests.

## Capacity evidence and limits

An Apex test passed input and output JSON longer than 100,000 characters and extracted its three 35,000-character text elements through Read JavaScript Result. This confirms there is no 32 KB aggregate result boundary in the release. It is not a maximum-capacity benchmark.

The configured JSON input/output policies are each 524,288 characters, and an individual JavaScript string is limited to 65,536 characters. Source, allocations, steps, depth, CPU, heap, and other work in the transaction also constrain capacity. See [supported JavaScript and policies](javascript-support.md).

## Repeat the checks

Follow the [developer guide](development.md) to run local editor checks, deploy to a fresh scratch org, and run the Apex and Flow verification scripts. Raw reports remain under ignored `reports/` because they can contain org identifiers. This document retains only sanitized results.

The regular GitHub workflow runs credential-free checks. The optional Apex validation workflow needs the dedicated `SF_DEV_HUB_AUTH_URL` repository secret before it can provision its own scratch org.
