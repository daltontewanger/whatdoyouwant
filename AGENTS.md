# AGENTS.md

Operating rules for any AI agent (Claude, Codex, etc.) working in this repository.
Product decisions and architecture live in the playbook; this file covers how to work here.

## Read first, every session

1. This file.
2. `docs/playbook.md`: approved product intent, architecture, phase order, human gates (Section 13).
3. `docs/project-state.md`: current verified state.
4. The current phase status doc (e.g. `docs/phase1-status.md`) and any doc it links to.

Repository files and verified console evidence describe actual state. The playbook describes intended state. When they conflict, report the conflict and propose the smallest safe resolution. Don't silently pick one.

## Current focus

- Phase: 1 (Account and environment boundaries)
- Status doc: `docs/phase1-status.md`
- Update this section when the phase changes.

## Repository map

- `lib/main.dart`: production entry (anonymous Auth, App Check).
- `lib/main_staging.dart`: staging entry (app on the deployed room backend; `STAGING_CONNECTION_CHECK=true` for the connection check).
- `lib/main_local.dart`: emulator-only entry (app on the room emulators; Google sign-in uses the Auth emulator's fake provider).
- `lib/environment_guard.dart`, `lib/firebase_options.dart`, `lib/firebase_options_staging.dart`, `lib/firebase_options_local.dart`: per-environment config and guards.
- `lib/screens/`, `lib/services/`, `lib/models/`, `lib/themes/`: app UI and services (`setState` + `Navigator`; `provider`/`flutter_riverpod` are declared but unused). Screens use `RoomBackend` (`services/room_backend.dart`): `LegacyRoomBackend` in production, `CallableRoomBackend` in local/staging.
- `functions/`: `fetchNearbyRestaurants` callable (`index.js`) and its handler (`search.js`), on Node 22 in production.
- `rooms/`: room callables (create/join/start/close/results/revoke/rotate code/delete account) and a daily idle-guest cleanup (`cleanup.js`). `handlers.js` holds the logic; `index.js` is the staging-only deployed entry (runs as `rooms-runtime`, App Check enforced); `firestore.rules` and `firestore.indexes.json` (TTL) serve both the emulators and staging. Separate from production `functions/`.
- `local-testing/`: emulator harness and Node tests. `firestore.rules` is the open baseline copy; `phase1/` wires `rooms/` into the emulators (App Check off) and holds the rules, account and callable tests.
- `staging/`: staging client config, deny-all rollback rules, empty indexes. `app-check-debug.json` is a local secret and ignored.
- `scripts/`: `local.mjs` (emulator launcher), `check-environments.mjs` (config preflight), PowerShell launchers.
- `firebase.json` (production Functions), `firebase.emulators.json` (baseline emulators), `firebase.phase1.emulators.json` (room emulators), `firebase.staging.json` (staging Firestore rules/TTL, Auth, rooms Functions).
- `android/app`: flavors `local`, `staging`, `production`; one is always required.
- `test/`: Flutter tests.
- `.github/workflows/deploy.yml`: builds and publishes web to GitHub Pages on every push to `main`.
- `docs/`: local-only, ignored.

## Commands

Run from the repository root. Node 22 or 24 is required. Flutter may not be on
PATH; the PowerShell launchers read the SDK location from `android/local.properties`.
Run `.ps1` launchers through `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`:
invoking them directly from Git Bash makes bash parse them, and Windows blocks
local scripts by default. The bypass applies only to that process.

| Purpose | Command |
| --- | --- |
| Restore tools | `npm ci` and `npm ci --prefix functions` |
| Config preflight | `node scripts/check-environments.mjs` |
| Format (check only) | `dart format --output=none --set-exit-if-changed lib test` |
| Analyze | `flutter analyze --no-pub lib test` (root-wide analysis also scans a Dart template inside `node_modules`) |
| Flutter tests | `flutter test --no-pub` |
| Functions/emulator tests | `npm run test:unit`, `npm run test:local`, `npm run test:tooling` |
| Firestore rules + callable tests | `npm run test:policy` |
| Deploy rooms to staging (needs approval) | `npm run deploy:staging -- --confirm whatdoyouwant-staging` (add `--dry-run` first) |
| Start emulators | `npm run local:preview` (room rules and callables; used by the app) or `npm run local` (legacy open-rules baseline, tests only) |
| Run the app locally (web) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-local-app.ps1` (needs `npm run local:preview`; serves on `localhost:5080` and opens the browser; `-WebPort` to change) |
| Run the app locally (Android) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-local-app.ps1 -Android -Device <device-id>` |
| Run the app against staging | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-staging.ps1 -AppCheckDebugFile ./staging/app-check-debug.json` (`-Android -Device <id>`; web uses `localhost:7357`) |
| Web build | `flutter build web --release --no-pub` |
| Android debug build | `flutter build apk --debug --no-pub --flavor production -t lib/main.dart` (staging: `--flavor staging -t lib/main_staging.dart`) |

There are no Functions lint scripts yet. Emulator tests must run with no other
emulator session using ports 4000, 4400, 4500, 5001, 8080 or 9099.

## Environments

- **Local / emulator** (`demo-whatdoyouwant`): default for all development and testing. Free to use.
- **Staging** (`whatdoyouwant-staging`): deploy only with `npm run deploy:staging`, and only after the owner approves that deploy. Functions run as `rooms-runtime`. No automated or CI deploys until a scoped deployer identity exists.
- **Production** (`what-do-you-want-8a404`): never deploy, change config, or modify data without explicit approval.

`.firebaserc` has no default project on purpose. Pass `--project` (and
`--config` for staging) on every Firebase CLI command; never run `firebase use`
to set one. Keep the Dart entry point and Android flavor matched to the same
environment.

## Git workflow

- Work on `codex/v2-launch` unless told otherwise; never commit directly to `main`.
- Never force-push, rewrite history, or move or delete the `pre-codex-v2-baseline` tag.
- Small commits, one logical change each, with clear messages.
- If `git status` shows changes you didn't make, ask before touching those files.
- Some generated plugin registrant files show line-ending-only changes. Leave them alone.
- Don't merge to `main`. Prepare the branch and summarize it for review.

## Docs are local-only

`docs/` is intentionally gitignored. It's versioned separately outside this repo.
Read and update files there as instructed, but never add them to Git, suggest
tracking them, or change the ignore rule.

## Code comments and commit messages

Write like a developer on the team, in plain natural language.

- Comments explain *why* something is done when it isn't obvious from the code.
  Don't narrate what the code does line by line, and don't reference this file,
  the playbook, phases, or any instructions you were given.
- Commit messages: a short summary line in the imperative ("Add weekly quota
  reservation"), then an optional body explaining what changed and why.
  No rule lists, checklists, or references to agent instructions.
- Don't add tool-generated signatures or trailers to commits.

## Non-negotiable invariants

- Clients are untrusted. The backend derives UID from verified Auth and never from request bodies.
- Only registered, verified accounts can trigger live deck generation. Anonymous guests can join and vote but never cause a HERE call.
- Quick Pick and Group Room share one weekly allowance (5 included + 5 rewarded, UTC Monday-start), enforced server-side.
- One immutable deck per decision. Joins, votes, reconnects, and rerolls reuse it.
- HERE stays behind `RestaurantProvider`. Flutter never sees HERE transport objects.
- Never store, log, or send exact location to analytics or crash reports.
- Quota, provider-usage, reward, and idempotency records are server-only; rules deny client access.
- Secrets live only in managed secret storage. Never print, commit, or log them, and never read local credential files such as `staging/app-check-debug.json`.
- No live HERE calls except a benchmark I've explicitly approved. Use fakes, fixtures, and emulators.
- Test ad units only, unless production ad config is approved.

## Definition of done for a change

1. Tests added or updated for the behavior change.
2. Format, analyze, and relevant tests pass (plus rules/emulator tests if backend or rules changed).
3. Exact commands and results reported. Never claim a check passed without running it.
4. No control (Auth, App Check, quota, rules, validation) weakened to make a test pass.
5. `docs/project-state.md` updated at milestones: what changed, commands, results, risks, next step.

## Stop and ask before

Anything in playbook Section 13, including:
- billing, paid services, or new vendors/providers;
- IAM, repository, Firebase, store, or ad permission changes;
- legal, privacy, or compliance statements;
- changing app IDs, bundle IDs, Firebase projects, or domains;
- deploying anywhere beyond the local emulator, or any store submission;
- destructive or hard-to-reverse data changes.

When stopping, give a short decision packet: recommendation, alternatives, cost/security/privacy impact, how to reverse it, and the exact action needed from me. Then continue with other safe work.

## Communication

- Say which phase and milestone you're on before editing.
- Keep progress updates brief; flag blockers and plan changes immediately.
- Challenge an approach when you have evidence for a better one, but get approval before changing approved architecture or scope.
