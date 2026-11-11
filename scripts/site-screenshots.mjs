// Redraws the app screens the site's hero phone shows (site/media/demo) from
// the app's own code and the demo's made-up places. Run after changing Home,
// the lobby, the swipe screen or results.
// Usage: node scripts/site-screenshots.mjs
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');

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

const result = spawnSync(flutterCommand(), ['test', '--no-pub', 'tool/site_screenshots_test.dart'],
  { cwd: root, stdio: 'inherit', shell: process.platform === 'win32' });
process.exit(result.status ?? 1);
