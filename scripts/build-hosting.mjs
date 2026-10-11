// Builds what Firebase Hosting serves: the public site from site/ at the root
// and the Flutter web app under /app.
// Usage: node scripts/build-hosting.mjs --env production|staging [--skip-app]
import { cpSync, existsSync, mkdirSync, readFileSync, rmSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ENTRIES = { production: 'lib/main.dart', staging: 'lib/main_staging.dart' };
const args = process.argv.slice(2);
const environment = args[args.indexOf('--env') + 1];
const skipApp = args.includes('--skip-app');
if (!args.includes('--env') || !ENTRIES[environment] ||
  args.some(arg => !['--env', environment, '--skip-app'].includes(arg))) {
  console.error('Usage: node scripts/build-hosting.mjs --env production|staging [--skip-app]');
  process.exit(2);
}

// Flutter is often not on PATH here; the Android setup records where the SDK lives.
function flutterCommand() {
  const properties = join(root, 'android/local.properties');
  if (existsSync(properties)) {
    const sdk = readFileSync(properties, 'utf8').match(/^flutter\.sdk=(.+)$/m)?.[1]?.trim().replace(/\\\\/g, '\\');
    const candidate = sdk && join(sdk, 'bin', process.platform === 'win32' ? 'flutter.bat' : 'flutter');
    if (candidate && existsSync(candidate)) return candidate;
  }
  return 'flutter';
}

const output = join(root, 'build/hosting');
const appBuild = join(root, 'build/web');
if (!skipApp) {
  const result = spawnSync(flutterCommand(), ['build', 'web', '--release', '--no-pub', '-t', ENTRIES[environment],
    '--base-href', '/app/'], { cwd: root, stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
if (!existsSync(join(appBuild, 'index.html'))) throw new Error('No web app build found; run without --skip-app.');
if (!readFileSync(join(appBuild, 'index.html'), 'utf8').includes('<base href="/app/">')) {
  throw new Error('The web app was built for another path; rebuild without --skip-app.');
}

rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
cpSync(join(root, 'site'), output, { recursive: true });
cpSync(appBuild, join(output, 'app'), { recursive: true });
console.log(`Hosting folder ready for ${environment}: build/hosting (site at /, app at /app).`);
