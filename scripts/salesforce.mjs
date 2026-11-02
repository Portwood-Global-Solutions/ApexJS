import { execFileSync } from 'node:child_process';
export function sf(args, org) {
  try {
    return JSON.parse(
      execFileSync('sf', [...args, ...(org ? ['--target-org', org] : []), '--json'], {
        encoding: 'utf8',
        maxBuffer: 32 * 1024 * 1024,
        stdio: ['ignore', 'pipe', 'pipe'],
      }),
    );
  } catch (error) {
    try {
      return JSON.parse(error.stdout);
    } catch {
      throw new Error(
        'Salesforce CLI did not return JSON. Check your CLI installation and authentication.',
      );
    }
  }
}
export function targetOrg() {
  const at = process.argv.indexOf('--org');
  const org = at >= 0 ? process.argv[at + 1] : undefined;
  if (!org || org.startsWith('--')) throw new Error('Supply --org YOUR_VALIDATION_ORG explicitly.');
  return org;
}
