import { existsSync, readFileSync, mkdirSync, writeFileSync, symlinkSync, realpathSync } from 'node:fs';
import { createRequire } from 'node:module';
import { dirname, delimiter, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawn } from 'node:child_process';
import net from 'node:net';
import { createInterface } from 'node:readline';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const mode = process.argv[2] || 'start';
if (!['start', 'test', 'unit', 'policy', 'preview'].includes(mode)) {
  throw new Error('Usage: node scripts/local.mjs [start|test|unit|policy|preview]');
}
if (![22, 24].includes(Number(process.versions.node.split('.')[0]))) {
  throw new Error('Local tooling requires Node 22 or 24. Use Node 22 to match the declared Functions runtime.');
}
const require = createRequire(join(root, 'functions/package.json'));
for (const dependency of ['firebase-functions', 'firebase-admin']) {
  try { require.resolve(dependency); } catch {
    throw new Error(`Missing ${dependency}. Restore the existing Functions lockfile with npm ci --prefix functions first.`);
  }
}
const env = { ...process.env };
// Child process only: never change the user's shell, CLI login or default project.
for (const key of ['GOOGLE_APPLICATION_CREDENTIALS', 'HERE_API_KEY', 'FIREBASE_TOKEN',
  'GOOGLE_OAUTH_ACCESS_TOKEN', 'FIREBASE_CONFIG', 'CLOUDSDK_AUTH_ACCESS_TOKEN']) delete env[key];
Object.assign(env, {
  FUNCTIONS_EMULATOR: 'true',
  GCLOUD_PROJECT: 'demo-whatdoyouwant',
  GOOGLE_CLOUD_PROJECT: 'demo-whatdoyouwant',
  FIRESTORE_EMULATOR_HOST: '127.0.0.1:8080',
  FIREBASE_AUTH_EMULATOR_HOST: '127.0.0.1:9099',
  FIREBASE_CLI_DISABLE_USAGE: 'true',
  GCE_METADATA_HOST: '127.0.0.1:9',
});
// Ensure the CLI and its Functions worker see the same Node runtime.
env.PATH = `${dirname(process.execPath)}${delimiter}${env.PATH || env.Path || ''}`;
delete env.Path;

function run(args) {
  const child = spawn(process.execPath, args, { cwd: root, env,
    stdio: mode === 'policy' ? ['inherit', 'pipe', 'pipe'] : 'inherit', windowsHide: true });
  if (mode === 'policy') {
    // Automated emulator tests need no clickable account-action links.
    for (const stream of [child.stdout, child.stderr]) {
      createInterface({ input: stream }).on('line', line =>
        console.log(line.replace(/oobCode=[^&\s]+/g, 'oobCode=REDACTED')));
    }
  }
  // The terminal delivers Ctrl+C to both foreground processes. Let Firebase clean up its emulators.
  const onInterrupt = () => {};
  process.on('SIGINT', onInterrupt);
  child.on('error', (error) => { console.error(error.message); process.exitCode = 1; });
  child.on('exit', (code) => { process.removeListener('SIGINT', onInterrupt); process.exitCode = code ?? 1; });
}

if (mode === 'unit') {
  run(['--test', 'local-testing/unit.test.cjs']);
} else {
  const candidate = ['policy', 'preview'].includes(mode);
  const configFile = candidate ? 'firebase.phase1.emulators.json' : 'firebase.emulators.json';
  const config = JSON.parse(readFileSync(join(root, configFile), 'utf8'));
  for (const [service, port] of Object.entries({ auth: 9099, firestore: 8080, functions: 5001 })) {
    if (config.emulators[service]?.host !== '127.0.0.1' || config.emulators[service]?.port !== port) {
      throw new Error(`Local ${service} must remain bound to 127.0.0.1:${port}.`);
    }
  }
  for (const port of [9099, 8080, 5001, 4000, 4400, 4500]) {
    await new Promise((accept, reject) => {
      const server = net.createServer();
      server.once('error', () => reject(new Error(`Port ${port} is occupied; stop your existing emulator session first.`)));
      server.listen(port, '127.0.0.1', () => server.close(accept));
    });
  }
  const candidates = [
    process.env.FIREBASE_CLI_PATH,
    join(root, 'node_modules/firebase-tools/lib/bin/firebase.js'),
    ...((process.env.PATH || process.env.Path || '').split(delimiter)
      .map(path => join(path, 'node_modules/firebase-tools/lib/bin/firebase.js'))),
  ];
  const cli = candidates.find(path => path && existsSync(path));
  if (!cli) throw new Error('Firebase CLI not found. Run npm ci in the repository root to restore the pinned local tools, then retry. Alternatively set FIREBASE_CLI_PATH to the verified CLI installation\'s lib/bin/firebase.js file.');
  const cliVersion = JSON.parse(readFileSync(resolve(dirname(cli), '../../package.json'), 'utf8')).version;
  const expectedCli = JSON.parse(readFileSync(join(root, 'package.json'), 'utf8')).devDependencies['firebase-tools'];
  if (!/^\d+\.\d+\.\d+$/.test(expectedCli) || cliVersion !== expectedCli) {
    throw new Error(`Expected the pinned Firebase CLI ${expectedCli}; found ${cliVersion}. Run npm ci to restore the local tools or correct FIREBASE_CLI_PATH.`);
  }
  // Isolated discovery entry: never scan production index.js or its secret bindings.
  const generated = join(root, 'build/local-functions');
  mkdirSync(generated, { recursive: true });
  const manifest = JSON.parse(readFileSync(join(root, 'functions/package.json'), 'utf8'));
  writeFileSync(join(generated, 'package.json'), JSON.stringify({
    name: 'local-functions-only', private: true, main: 'index.js',
    engines: { node: process.versions.node.split('.')[0] }, dependencies: manifest.dependencies,
  }, null, 2));
  writeFileSync(join(generated, 'index.js'), candidate
    // CLI discovery may inject its own ADC file path. The local entry never needs it.
    ? "delete process.env.GOOGLE_APPLICATION_CREDENTIALS;\nmodule.exports = require('../../local-testing/phase1/functions-entry.cjs');\n"
    : "module.exports = require('../../local-testing/functions-entry.cjs');\n");
  const modules = join(generated, 'node_modules');
  const sourceModules = join(root, 'functions/node_modules');
  if (!existsSync(modules)) symlinkSync(sourceModules, modules, process.platform === 'win32' ? 'junction' : 'dir');
  if (realpathSync(modules) !== realpathSync(sourceModules)) throw new Error('Unexpected local dependency link; inspect build/local-functions/node_modules.');
  console.log('Local demo project only; HERE fixtures; no production App Check or secret access.');
  console.log(candidate ? 'LOCAL-ONLY Phase 1 permissions and callable endpoints; no cloud deployment.' : 'Owner-supplied room rules are OPEN. These tests characterize current behavior, not a release policy.');
  console.log(`Functions declares Node ${manifest.engines.node}; local tests use Node ${process.versions.node}. No cloud runtime is changed.`);
  const args = [cli, ['test', 'policy'].includes(mode) ? 'emulators:exec' : 'emulators:start',
    '--config', configFile, '--project', 'demo-whatdoyouwant',
    '--only', 'auth,firestore,functions'];
  if (mode === 'test') args.push('node --test --test-concurrency=1 local-testing/unit.test.cjs local-testing/emulator.test.cjs');
  if (mode === 'policy') args.push('node --test --test-concurrency=1 local-testing/phase1/permissions.test.cjs local-testing/phase1/accounts.test.cjs local-testing/phase1/endpoints.test.cjs');
  run(args);
}
