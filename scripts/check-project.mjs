import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { join, basename } from 'node:path';
import assert from 'node:assert/strict';
const walk = (directory) =>
  readdirSync(directory, { withFileTypes: true }).flatMap((row) =>
    row.isDirectory() ? walk(join(directory, row.name)) : [join(directory, row.name)],
  );
const files = walk('force-app');
const actions = [];
for (const path of files) {
  assert.ok(
    !/Probe|JsLab|JsRawLibrary|JsPdf|JsSvg|\.page$/.test(path),
    'Research component in release: ' + path,
  );
  if (path.endsWith('.cls')) {
    const source = readFileSync(path, 'utf8');
    assert.ok(
      /^[A-Za-z][A-Za-z0-9_]*\.cls$/.test(basename(path)),
      'Unexpected backup or invalid Apex filename: ' + path,
    );
    assert.ok(existsSync(path + '-meta.xml'), 'Missing Apex metadata: ' + path);
    if (source.includes('@InvocableMethod')) actions.push(basename(path));
  }
}
assert.deepEqual(actions.sort(), [
  'JsCollectionScriptAction.cls',
  'JsPortwoodDataAction.cls',
  'JsResultAction.cls',
]);
for (const directory of ['vendor', 'tmp', 'artifacts', 'tools'])
  assert.ok(!existsSync(directory), 'Research directory in clean checkout: ' + directory);
for (const file of [
  'README.md',
  'LICENSE',
  'SECURITY.md',
  'CONTRIBUTING.md',
  'CHANGELOG.md',
  'docs/admin-guide.md',
  'docs/installation.md',
  'docs/libraries.md',
  'docs/javascript-support.md',
  'docs/development.md',
  'docs/verification.md',
])
  assert.ok(existsSync(file), 'Missing release document: ' + file);
const libraryFiles = files.filter((path) => path.endsWith('.resource'));
assert.deepEqual(libraryFiles, [
  'force-app/main/default/staticresources/ApexJSExampleTools.resource',
]);
console.log(
  'Release surface verified: three Flow actions, runtime, editors, permissions, and one example module.',
);
