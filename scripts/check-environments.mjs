import { readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const json = path => JSON.parse(readFileSync(resolve(root, path), 'utf8').replace(/^\uFEFF/, ''));
function check(condition, name) { if (!condition) throw new Error(`Environment configuration mismatch: ${name}`); }
const staging = 'whatdoyouwant-staging';
const production = 'what-do-you-want-8a404';
const web = json('staging/firebase.web.json');
const native = json('android/app/src/staging/google-services.json');
const downloaded = json('staging/google-services.json');
check(web.projectId === staging && native.project_info.project_id === staging, 'staging project');
check(JSON.stringify(native) === JSON.stringify(downloaded), 'Android download/native copy');
check(json('android/app/google-services.json').project_info.project_id === production, 'production native project');
check(json('.firebaserc').projects.staging === staging, 'staging alias');
check(json('.firebaserc').projects.default === production, 'existing default alias');
const client = native.client.find(c => c.client_info.android_client_info.package_name === 'com.daltontewanger.whatdoyouwant.staging');
check(!!client, 'Android staging package');
const dart = readFileSync(resolve(root, 'lib/firebase_options_staging.dart'), 'utf8');
for (const value of [web.appId, web.apiKey, client.client_info.mobilesdk_app_id, client.api_key[0].current_key]) {
  check(typeof value === 'string' && dart.includes(`'${value}'`), 'Dart/native SDK configuration');
}
check(json('firebase.staging.json').firestore.rules === 'staging/firestore.rules', 'cloud deny-all rules path');
check(json('firebase.phase1.emulators.json').firestore.rules === 'local-testing/phase1/firestore.rules', 'candidate local rules path');
const local = json('android/app/src/local/google-services.json');
check(local.project_info.project_id === 'demo-whatdoyouwant', 'local native project');
const localClient = local.client.find(c => c.client_info.android_client_info.package_name === 'com.daltontewanger.whatdoyouwant.local');
check(!!localClient, 'local package');
const localDart = readFileSync(resolve(root, 'lib/firebase_options_local.dart'), 'utf8');
for (const value of [local.project_info.project_id, local.project_info.project_number,
  localClient.client_info.mobilesdk_app_id, localClient.api_key[0].current_key]) {
  check(typeof value === 'string' && localDart.includes(`'${value}'`), 'local Dart/native options');
}
const localLaunch = json('.vscode/launch.json').configurations.find(c => c.name === 'Local preview - Android emulator');
check(localLaunch?.program === 'lib/main_local.dart' && localLaunch.toolArgs[localLaunch.toolArgs.indexOf('--flavor') + 1] === 'local', 'local VS Code launch');
check(!Object.hasOwn(json('firebase.json'), 'emulators'), 'emulators use dedicated local configurations');
check(!/FIREBASE_APPCHECK_DEBUG_TOKEN\s*=/.test(readFileSync(resolve(root, 'web/index.html'), 'utf8')), 'web entry does not enable App Check debug');
check(!readFileSync(resolve(root, '.github/workflows/deploy.yml'), 'utf8').includes('HERE_API_KEY'), 'HERE credential stays out of the browser build');
console.log('PASS: local/staging/production configuration boundaries; values withheld.');
