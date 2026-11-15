# Changelog

## Unreleased

- Date and Date/Time inputs compare their boundary markers by the year as written, so they work for users whose locale uses the Buddhist calendar (Thai, th_TH). For such a user, Apex read the year of the markers as a Buddhist year.
- JavaScript `Date` gives the same results for every user locale. For a th_TH user, `getFullYear()` returned the Buddhist year (2569 for 2026), and `Date.UTC`, the `set` methods and the `M/D/YYYY HH:mm UTC` format computed dates 543 years early.
- JavaScript `Date` uses the proleptic Gregorian calendar for every date, as JavaScript does: dates before 15 October 1582 no longer differ from JavaScript by several days, `getUTCMilliseconds()` before 1970 is no longer negative, years after 9999 render in the expanded ISO form (`+010000-01-01T00:00:00.000Z`), and ISO strings without seconds (`2026-11-01T09:30Z`) parse.

## Unmanaged installer 1.1 — 2026-11-02

- Salesforce installation links for source release 0.1.0, hosted in Portwood Global - Production with no namespace or Portwood dependency.
- Metadata API ZIP and checksum build tooling, an explicit-org deployment helper, and a guided installation document for admins.
- Expanded contract tests: 93 Apex tests, 84.6% aggregate coverage, and at least 75% coverage for every shipped production class.
- Optional uploaded-package validation through the Apex CI workflow.
- Dynamic record fixtures keep the publishing org's optional Opportunity Historical Trending feature out of the installation requirements.

## 0.1.0 — 2026-11-01

- Initial clean source distribution of ApexJS under Portwood Global Solutions.
- Three Flow actions: Run JavaScript on Collections, Read JavaScript Result, and Prepare Portwood Data.
- Repeatable named data form with mixed record types, primitive collections, native dates/date/times, scalar resources, and ordinary literal controls.
- Optional compatible CommonJS libraries loaded from JavaScript Static Resources.
- Direct JavaScript source or a Flow text resource for calculations; typed downstream outputs and optional Portwood normalization.
- Guarded execution, isolated request state, source hashes, metrics, and bounded synchronous Promise work.
- Source-only Apex convenience API, permission sets, tests, CI configuration, and admin/developer documentation.
- Research-only PDF/SVG, pinned accelerators, large-library Queueable jobs, vendor assets, probes, and benchmark outputs excluded.

This release replaces the experimental lab interfaces. Separate Bind actions, entry bundles, and fixed left/right collection slots are not part of the released API. Migrate lab Flows by recreating their inputs in the named-data form; validate output paths and object mappings before activation.
