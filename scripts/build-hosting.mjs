// Builds what Firebase Hosting serves: the public site from site/ at the root
// and the Flutter web app under /app.
// Usage: node scripts/build-hosting.mjs --env production|staging [--skip-app]
import { cpSync, existsSync, mkdirSync, readdirSync, readFileSync, renameSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const ENTRIES = { production: 'lib/main.dart', staging: 'lib/main_staging.dart' };
// Where each environment's site is served.
const ORIGINS = {
  production: 'https://getwhatdoyouwant.app',
  staging: 'https://staging.getwhatdoyouwant.app',
};
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
  // CanvasKit ships with the build instead of loading from Google's CDN.
  const result = spawnSync(flutterCommand(), ['build', 'web', '--release', '--no-pub', '-t', ENTRIES[environment],
    '--base-href', '/app/', '--no-web-resources-cdn'], { cwd: root, stdio: 'inherit', shell: process.platform === 'win32' });
  if (result.status !== 0) process.exit(result.status ?? 1);
}
if (!existsSync(join(appBuild, 'index.html'))) throw new Error('No web app build found; run without --skip-app.');
if (!readFileSync(join(appBuild, 'index.html'), 'utf8').includes('<base href="/app/">')) {
  throw new Error('The web app was built for another path; rebuild without --skip-app.');
}

// The site's account menu reads the sign-in the web app keeps on this origin,
// so it needs the same public web config the app uses. These values are
// public by design (they ship in every web build); access is controlled by
// Auth, App Check and the security rules.
function webConfig() {
  if (environment === 'staging') {
    const { apiKey, authDomain, projectId, appId } = JSON.parse(readFileSync(join(root, 'staging/firebase.web.json'), 'utf8'));
    return { apiKey, authDomain, projectId, appId };
  }
  const dart = readFileSync(join(root, 'lib/firebase_options.dart'), 'utf8');
  const block = dart.slice(dart.indexOf('static const FirebaseOptions web'));
  const field = name => block.match(new RegExp(`${name}: '([^']+)'`))?.[1];
  const config = { apiKey: field('apiKey'), authDomain: field('authDomain'), projectId: field('projectId'),
    appId: field('appId') };
  if (Object.values(config).some(value => !value)) throw new Error('Could not read the production web config.');
  return config;
}

// The web engine draws text it has no font for (emoji, other scripts) with
// fallback fonts it normally downloads from fonts.gstatic.com, and loads
// Roboto from there at start. Those files are copied next to the app and the
// engine is pointed at them, so visitors' browsers never contact Google Fonts.
// Downloads happen here, on the build machine, and are cached between builds.
const FALLBACK_SOURCE = 'https://fonts.gstatic.com/s/';
const fontCache = join(root, 'build/font-cache');
async function mirrorFallbackFonts(appDir) {
  const engine = readFileSync(join(appBuild, 'main.dart.js'), 'utf8');
  const files = [...new Set(engine.match(/[a-z0-9]+\/v\d+\/[A-Za-z0-9_.-]+\.woff2/g) ?? [])];
  if (files.length < 50) throw new Error(`Expected the engine's fallback font list; found ${files.length} files.`);
  for (const file of files) {
    const cached = join(fontCache, file);
    if (!existsSync(cached)) {
      const response = await fetch(FALLBACK_SOURCE + file);
      if (!response.ok) throw new Error(`Could not fetch fallback font ${file}: ${response.status}`);
      mkdirSync(dirname(cached), { recursive: true });
      writeFileSync(cached, Buffer.from(await response.arrayBuffer()));
    }
    mkdirSync(dirname(join(appDir, 'fonts', file)), { recursive: true });
    cpSync(cached, join(appDir, 'fonts', file));
  }
  return files.length;
}

// The rendering engine only changes when Flutter is upgraded, so it moves to
// a folder named after the engine version. Hosting can then let browsers keep
// it for good: a new version gets a new address instead of a stale copy.
function versionEngine(appDir) {
  const bootstrap = join(appDir, 'flutter_bootstrap.js');
  const revision = readFileSync(bootstrap, 'utf8').match(/"engineRevision":"([0-9a-f]{12})/)?.[1];
  if (!revision) throw new Error('Could not read the engine revision from flutter_bootstrap.js.');
  const folder = `canvaskit-${revision}`;
  renameSync(join(appDir, 'canvaskit'), join(appDir, folder));
  return folder;
}

// Points the loader at the local fallback fonts and the versioned engine.
// Both are relative to the page's base address, so they resolve under /app/.
function configureLoader(appDir, engineFolder) {
  const bootstrap = join(appDir, 'flutter_bootstrap.js');
  const loader = readFileSync(bootstrap, 'utf8');
  if (!loader.includes('_flutter.loader.load({')) throw new Error('Unexpected flutter_bootstrap.js; cannot configure the loader.');
  writeFileSync(bootstrap, loader.replace('_flutter.loader.load({',
    `_flutter.loader.load({\n  config: { fontFallbackBaseUrl: "fonts/", canvasKitBaseUrl: "${engineFolder}/" },`));
}

rmSync(output, { recursive: true, force: true });
mkdirSync(output, { recursive: true });
cpSync(join(root, 'site'), output, { recursive: true });
cpSync(appBuild, join(output, 'app'), { recursive: true });
const mirrored = await mirrorFallbackFonts(join(output, 'app'));
const engineFolder = versionEngine(join(output, 'app'));
configureLoader(join(output, 'app'), engineFolder);
// The home page starts downloading the app's largest files once it is idle,
// so opening the app from it is quicker. The engine comes in two builds; the
// page picks the one the loader will.
const appFiles = { code: '/app/main.dart.js', engine: `/app/${engineFolder}/`,
  chromiumEngine: `/app/${engineFolder}/chromium/` };
writeFileSync(join(output, 'firebase-config.js'), `window.wdywFirebaseConfig = ${JSON.stringify(webConfig())};\n`
  + `window.wdywAppFiles = ${JSON.stringify(appFiles)};\n`);
// Link previews need absolute image addresses.
for (const page of [...readdirSync(output).filter(name => name.endsWith('.html')), 'app/index.html']) {
  const path = join(output, page);
  writeFileSync(path, readFileSync(path, 'utf8').replaceAll('%SITE_ORIGIN%', ORIGINS[environment]));
}
console.log(`Hosting folder ready for ${environment}: build/hosting (site at /, app at /app; ${mirrored} fallback fonts served locally; engine in /app/${engineFolder}).`);
