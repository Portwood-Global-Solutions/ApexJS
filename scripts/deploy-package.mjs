import { readFileSync, readdirSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import assert from 'node:assert/strict';
import { sf, targetOrg } from './salesforce.mjs';

const org = targetOrg();
const version = JSON.parse(readFileSync('package.json', 'utf8')).version;
const archive = `dist/ApexJS-${version}-unmanaged.zip`;
assert.ok(existsSync(archive), 'Run npm run build:package first.');
const directory = 'force-app/main/default/classes/';
const tests = readdirSync(directory)
  .filter(
    (file) =>
      file.endsWith('.cls') &&
      /@IsTest\s+static\s+void/.test(readFileSync(directory + file, 'utf8')),
  )
  .map((file) => file.slice(0, -4));
assert.ok(tests.length > 0, 'No Apex test classes found.');
mkdirSync('reports', { recursive: true });
const response = sf(
  [
    'project',
    'deploy',
    'start',
    '--metadata-dir',
    archive,
    '--single-package',
    '--test-level',
    'RunSpecifiedTests',
    '--tests',
    ...tests,
    '--wait',
    '30',
  ],
  org,
);
writeFileSync('reports/package-deploy.json', JSON.stringify(response, null, 2) + '\n');
const result = response.result;
assert.equal(
  result?.success,
  true,
  'Package deployment failed; inspect reports/package-deploy.json.',
);
console.log(
  JSON.stringify({
    status: result.status,
    components: result.numberComponentsDeployed,
    tests: result.numberTestsCompleted,
    failed: result.numberTestErrors,
  }),
);
