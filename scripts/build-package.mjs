import { execFileSync } from 'node:child_process';
import { mkdirSync, readFileSync, rmSync, writeFileSync, readdirSync } from 'node:fs';
import { resolve, join, relative } from 'node:path';
import { createHash } from 'node:crypto';
import assert from 'node:assert/strict';

const version = JSON.parse(readFileSync('package.json', 'utf8')).version;
assert.match(version, /^\d+\.\d+\.\d+$/);
const directory = resolve('dist/apexjs-unmanaged');
const filename = `ApexJS-${version}-unmanaged.zip`;
const archive = resolve('dist', filename);
mkdirSync('dist', { recursive: true });
rmSync(directory, { recursive: true, force: true });
rmSync(archive, { force: true });

const converted = JSON.parse(
  execFileSync(
    'sf',
    [
      'project',
      'convert',
      'source',
      '--root-dir',
      'force-app',
      '--output-dir',
      directory,
      '--package-name',
      'ApexJS',
      '--json',
    ],
    { encoding: 'utf8', stdio: ['ignore', 'pipe', 'inherit'] },
  ),
);
assert.equal(converted.status, 0, 'Metadata conversion failed.');
const manifest = readFileSync(join(directory, 'package.xml'), 'utf8');
assert.ok(manifest.includes('<fullName>ApexJS</fullName>'));
assert.deepEqual([...manifest.matchAll(/<name>([^<]+)<\/name>/g)].map((row) => row[1]).sort(), [
  'ApexClass',
  'LightningComponentBundle',
  'PermissionSet',
  'StaticResource',
]);
assert.ok(!manifest.includes('<members>*</members>'), 'Use explicit package members.');
const walk = (path) =>
  readdirSync(path, { withFileTypes: true }).flatMap((entry) =>
    entry.isDirectory()
      ? walk(join(path, entry.name))
      : [relative(directory, join(path, entry.name))],
  );
const files = walk(directory);
assert.ok(
  !files.some((file) => /__tests__|\.test\.|\.sf\/|\.sfdx\/|node_modules|Probe|JsLab/.test(file)),
);
execFileSync('zip', ['-q', '-r', archive, '.'], { cwd: directory });
const sha256 = createHash('sha256').update(readFileSync(archive)).digest('hex');
writeFileSync(archive + '.sha256', `${sha256}  ${filename}\n`);
console.log(
  JSON.stringify({ archive: relative(process.cwd(), archive), sha256, files: files.length }),
);
