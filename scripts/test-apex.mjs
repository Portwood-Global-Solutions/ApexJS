import { mkdirSync, writeFileSync, readdirSync, readFileSync } from 'node:fs';
import assert from 'node:assert/strict';
import { sf, targetOrg } from './salesforce.mjs';
const org = targetOrg();
mkdirSync('reports', { recursive: true });
let response = sf(
  [
    'apex',
    'run',
    'test',
    '--test-level',
    'RunLocalTests',
    '--code-coverage',
    '--result-format',
    'json',
    '--wait',
    '30',
  ],
  org,
);
writeFileSync('reports/apex-tests.json', JSON.stringify(response, null, 2) + '\n');
const result = response.result;
assert.equal(
  result?.summary?.outcome,
  'Passed',
  JSON.stringify(
    result?.tests
      ?.filter((test) => test.Outcome !== 'Pass')
      .map((test) => ({ name: test.FullName, message: test.Message })) || response.message,
  ),
);
const names = new Set(
  readdirSync('force-app/main/default/classes')
    .filter(
      (file) =>
        file.endsWith('.cls') &&
        !readFileSync('force-app/main/default/classes/' + file, 'utf8').includes('@IsTest'),
    )
    .map((file) => file.slice(0, -4)),
);
const classes = (result.coverage?.coverage || []).filter((row) => names.has(row.name));
const totals = classes.reduce(
  (sum, row) => ({ covered: sum.covered + row.totalCovered, total: sum.total + row.totalLines }),
  { covered: 0, total: 0 },
);
const coverage = Math.round((1000 * totals.covered) / totals.total) / 10;
assert.ok(
  coverage >= 80,
  'Release Apex coverage must be at least 80%; measured ' + coverage + '%.',
);
writeFileSync(
  'reports/apex-coverage-summary.json',
  JSON.stringify(
    {
      passed: result.summary.passing,
      failed: result.summary.failing,
      coverage,
      classes: classes.map((row) => ({
        name: row.name,
        covered: row.totalCovered,
        total: row.totalLines,
        percent: row.coveredPercent,
      })),
    },
    null,
    2,
  ) + '\n',
);
console.log(
  JSON.stringify({
    passed: result.summary.passing,
    failed: result.summary.failing,
    coverage: coverage + '%',
  }),
);
