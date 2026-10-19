// Deploys the site, the web app and the room backend to production, and nowhere else.
// Usage: node scripts/deploy-production.mjs --confirm what-do-you-want-8a404
//          [--only site|backend|functions] [--dry-run] [--skip-tests]
// Every run needs the owner's approval. Uses the Firebase CLI login of whoever
// runs it; no key files are involved.
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const PRODUCTION = 'what-do-you-want-8a404';
const TARGETS = {
  site: 'hosting',
  backend: 'firestore:rules,firestore:indexes,functions:rooms',
  // The room functions alone. The live app still writes to Firestore directly
  // until the cut-over replaces it, and the room rules would lock it out; the
  // Firestore step checks the rules even when only indexes are named, so the
  // rules and TTLs go out together with the site.
  functions: 'functions:rooms',
};
const args = process.argv.slice(2);
const valueOf = flag => (args.includes(flag) ? args[args.indexOf(flag) + 1] : undefined);
const confirm = valueOf('--confirm');
const only = valueOf('--only');
const dryRun = args.includes('--dry-run');
const skipTests = args.includes('--skip-tests');
const known = new Set(['--confirm', PRODUCTION, '--only', 'site', 'backend', 'functions', '--dry-run', '--skip-tests']);
const usage = `Usage: node scripts/deploy-production.mjs --confirm ${PRODUCTION} [--only site|backend|functions] [--dry-run] [--skip-tests]`;
if (confirm !== PRODUCTION || (args.includes('--only') && !TARGETS[only]) || args.some(arg => !known.has(arg))) {
  console.error(usage);
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

const deploysSite = !only || only === 'site';
const deploysBackend = !only || only === 'backend' || only === 'functions';
step('Configuration preflight', process.execPath, ['scripts/check-environments.mjs']);
if (deploysBackend) {
  step('Restore rooms dependencies from the lockfile', 'npm', ['ci', '--prefix', 'rooms', '--no-audit', '--no-fund']);
}
if (!skipTests) {
  step('Unit tests', 'npm', ['run', 'test:unit']);
  step('Room rules and callable tests (local emulators)', 'npm', ['run', 'test:policy']);
}
if (deploysSite) step('Build the site and web app', process.execPath, ['scripts/build-hosting.mjs', '--env', 'production']);

const cli = join(root, 'node_modules/firebase-tools/lib/bin/firebase.js');
if (!existsSync(cli)) throw new Error('Firebase CLI not found. Run npm ci in the repository root.');
const expectedCli = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).devDependencies['firebase-tools'];
const actualCli = JSON.parse(readFileSync(join(root, 'node_modules/firebase-tools/package.json'), 'utf8')).version;
if (actualCli !== expectedCli) throw new Error(`Expected Firebase CLI ${expectedCli}; found ${actualCli}. Run npm ci.`);

const targets = only ? TARGETS[only] : Object.values(TARGETS).join(',');
step(dryRun ? `Dry run against ${PRODUCTION}` : `Deploy to ${PRODUCTION}`, process.execPath, [cli, 'deploy',
  '--config', 'firebase.production.json', '--project', PRODUCTION, '--only', targets, '--non-interactive',
  ...(dryRun ? ['--dry-run'] : [])]);
console.log(dryRun ? '\nDry run finished; nothing was deployed.' : `\nDeployed to ${PRODUCTION}.`);
