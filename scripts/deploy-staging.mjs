// Deploys the room rules, TTL settings and callables to staging, and nowhere else.
// Usage: node scripts/deploy-staging.mjs --confirm whatdoyouwant-staging [--dry-run] [--skip-tests]
// Uses the Firebase CLI login of whoever runs it; no key files are involved.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const STAGING = 'whatdoyouwant-staging';
const args = process.argv.slice(2);
const confirm = args[args.indexOf('--confirm') + 1];
const dryRun = args.includes('--dry-run');
const skipTests = args.includes('--skip-tests');
const known = new Set(['--confirm', STAGING, '--dry-run', '--skip-tests']);
if (!args.includes('--confirm') || confirm !== STAGING || args.some(arg => !known.has(arg))) {
  console.error(`Usage: node scripts/deploy-staging.mjs --confirm ${STAGING} [--dry-run] [--skip-tests]`);
  process.exit(2);
}
if (![22, 24].includes(Number(process.versions.node.split('.')[0]))) {
  throw new Error('Deploying requires Node 22 or 24.');
}

const env = { ...process.env };
// Emulator variables would silently point the CLI or tests somewhere else.
for (const key of Object.keys(env)) if (/_EMULATOR_HOST$|^FUNCTIONS_EMULATOR$/.test(key)) delete env[key];

function step(title, command, commandArgs) {
  console.log(`\n== ${title}`);
  const result = spawnSync(command, commandArgs, { cwd: root, env, stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.status !== 0) {
    console.error(`Stopped: ${title} failed.`);
    process.exit(result.status ?? 1);
  }
}

step('Configuration preflight', process.execPath, ['scripts/check-environments.mjs']);
step('Restore rooms dependencies from the lockfile', 'npm', ['ci', '--prefix', 'rooms', '--no-audit', '--no-fund']);
if (!skipTests) {
  // The unit suite also covers the production search function, which needs its own dependencies.
  step('Restore functions dependencies from the lockfile', 'npm', ['ci', '--prefix', 'functions', '--no-audit', '--no-fund']);
  step('Unit tests', 'npm', ['run', 'test:unit']);
  step('Room rules and callable tests (local emulators)', 'npm', ['run', 'test:policy']);
}

const cli = join(root, 'node_modules/firebase-tools/lib/bin/firebase.js');
if (!existsSync(cli)) throw new Error('Firebase CLI not found. Run npm ci in the repository root.');
const expectedCli = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).devDependencies['firebase-tools'];
const actualCli = JSON.parse(readFileSync(join(root, 'node_modules/firebase-tools/package.json'), 'utf8')).version;
if (actualCli !== expectedCli) throw new Error(`Expected Firebase CLI ${expectedCli}; found ${actualCli}. Run npm ci.`);

step(dryRun ? `Dry run against ${STAGING}` : `Deploy to ${STAGING}`, process.execPath, [cli, 'deploy',
  '--config', 'firebase.staging.json', '--project', STAGING,
  '--only', 'firestore:rules,firestore:indexes,functions:rooms', '--non-interactive',
  ...(dryRun ? ['--dry-run'] : [])]);
console.log(dryRun ? '\nDry run finished; nothing was deployed.' : `\nDeployed to ${STAGING}.`);
