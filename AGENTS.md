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

- Phase: 4 (Production cut-over), planning since 2026-10-11
- Status doc: `docs/phase4-status.md`
- Update this section when the phase changes.

## Repository map

- `lib/main.dart`: production entry (accounts with a guest session, App Check, `CallableRoomBackend`; live at getwhatdoyouwant.app/app).
- `lib/main_staging.dart`: staging entry (app on the deployed room backend; `STAGING_CONNECTION_CHECK=true` for the connection check).
- `lib/main_local.dart`: emulator-only entry (app on the room emulators; Google sign-in uses the Auth emulator's fake provider).
- `lib/environment_guard.dart`, `lib/firebase_options.dart`, `lib/firebase_options_staging.dart`, `lib/firebase_options_local.dart`: per-environment config and guards.
- `lib/screens/`, `lib/services/`, `lib/models/`, `lib/themes/`: app UI and services (`setState` + `Navigator`, no state-management package). Screens use `RoomBackend` (`services/room_backend.dart`): `CallableRoomBackend` in every build. `services/site_links.dart` reads app links (`/app/host`, `/app/join[/<code>]`, `/app/account`); `screens/update_gate.dart` shows "please update" for builds below `config/liveSearch.minimumClientBuild`; `services/error_reporter.dart` sends uncaught errors in release builds to `reportClientError`.
- `rooms/`: the only Functions codebase: room callables (create/join/start/close/results/revoke/rotate code/delete account, app status, client error reports in `client-errors.js`), a weekly idle-guest cleanup (`cleanup.js`) and `sweepRooms` (every 15 minutes: closes rooms whose voting ran out, deletes expired decks). `handlers.js` holds the logic; `index.js` is the deployed entry for staging and production (each project listed with its own settings; runs as that project's `rooms-runtime`, App Check enforced); `firestore.rules` and `firestore.indexes.json` (TTL) serve both the emulators and staging. `search/` holds the restaurant search layer (request contract, cuisine whitelist, deck builder, fake provider, HERE adapter); `decks.js` shapes the stored `restaurantDecks`. `generation.js` is the one path for live decks (weekly cap, monthly provider ledger, `config/liveSearch` kill switch, lease, refunds); `quota.js` holds its week/month keys and config parsing.
- `local-testing/`: emulator harness and Node tests. `phase1/` wires `rooms/` into the emulators (App Check off) and holds the rules, account and callable tests. `search/` holds synthetic HERE fixtures and the search benchmark (`benchmark/record-here.cjs` makes live recordings only for an approved run).
- `staging/`: staging client config, deny-all rollback rules, empty indexes. `app-check-debug.json` is a local secret and ignored.
- `site/`: the public website (static HTML/CSS/JS: home page, legal and help pages, account menu). Built together with the web app by `scripts/build-hosting.mjs` into `build/hosting` (site at `/`, app at `/app`).
- `scripts/`: `local.mjs` (emulator launcher), `check-environments.mjs` (config preflight), `build-hosting.mjs`, `deploy-staging.mjs`, `deploy-production.mjs`, PowerShell launchers.
- `firebase.production.json` (production Hosting with security headers, room rules/TTL, rooms Functions), `firebase.phase1.emulators.json` (room emulators), `firebase.staging.json` (staging Firestore rules/TTL, Auth, rooms Functions).
- `android/app`: flavors `local`, `staging`, `production`; one is always required.
- `test/`: Flutter tests.
- `.github/workflows/checks.yml`: format, analyze, tests and a web build on pull requests and pushes to this branch.
- `.github/workflows/deploy-staging.yml`: manual rooms deploy to staging (dry run by default; owner approves each run).
- `docs/`: local-only, ignored.

## Commands

Run from the repository root. Node 22 or 24 is required. Flutter may not be on
PATH; the PowerShell launchers read the SDK location from `android/local.properties`.
Run `.ps1` launchers through `powershell.exe -NoProfile -ExecutionPolicy Bypass -File`:
invoking them directly from Git Bash makes bash parse them, and Windows blocks
local scripts by default. The bypass applies only to that process.

| Purpose | Command |
| --- | --- |
| Restore tools | `npm ci` and `npm ci --prefix rooms` |
| Config preflight | `node scripts/check-environments.mjs` |
| Format (check only) | `dart format --output=none --set-exit-if-changed lib test` |
| Analyze | `flutter analyze --no-pub lib test` (root-wide analysis also scans a Dart template inside `node_modules`) |
| Flutter tests | `flutter test --no-pub` |
| Functions/emulator tests | `npm run test:unit`, `npm run test:tooling` |
| Firestore rules + callable tests | `npm run test:policy` |
| Search benchmark (recorded or synthetic responses, no network) | `npm run benchmark:search` (`-- --recordings <dir>` for real recordings) |
| Staging function logs | `npx firebase functions:log --project whatdoyouwant-staging --config firebase.staging.json -n 50` (`--only <name>` for one function) |
| Deploy rooms to staging (needs approval) | `npm run deploy:staging -- --confirm whatdoyouwant-staging` (add `--dry-run` first) |
| Start emulators | `npm run local:preview` (room rules and callables; used by the app) |
| Run the app locally (web) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-local-app.ps1` (needs `npm run local:preview`; serves on `localhost:5080/` and opens the browser; `-WebPort` to change) |
| Run the app locally (Android) | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-local-app.ps1 -Android -Device <device-id>` |
| Run the app against staging | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File ./scripts/run-staging.ps1 -AppCheckDebugFile ./staging/app-check-debug.json` (`-Android -Device <id>`; web uses `localhost:7357`) |
| Web build | `flutter build web --release --no-pub` (base path is set at build time: `--base-href /app/` for Hosting) |
| Site + app hosting folder | `npm run build:hosting -- --env staging` (or `production`; `--skip-app` reuses the last web build) |
| Preview the hosting folder locally | `npx firebase emulators:start --only hosting --config firebase.production.json --project demo-whatdoyouwant` (serves `build/hosting` on port 5000; build with `--env staging`, since a production build talks to the live project) |
| Deploy to production (needs approval) | `npm run deploy:production -- --confirm what-do-you-want-8a404 --dry-run` (then without `--dry-run`; `--only site`, `--only backend`, or `--only functions` for the room functions without the rules or TTLs) |
| Android debug build | `flutter build apk --debug --no-pub --flavor production -t lib/main.dart` (staging: `--flavor staging -t lib/main_staging.dart`) |

There are no Functions lint scripts yet. Emulator tests must run with no other
emulator session using ports 4000, 4400, 4500, 5001, 8080 or 9099.

## Environments

- **Local / emulator** (`demo-whatdoyouwant`): default for all development and testing. Free to use.
- **Staging** (`whatdoyouwant-staging`): deploy only with `npm run deploy:staging` or the manual "Deploy rooms to staging" workflow (`ci-staging-deployer`, keyless, gated by the `staging` environment's required reviewer), and only after the owner approves that deploy. Functions run as `rooms-runtime`. No automatic deploys on push.
- **Production** (`what-do-you-want-8a404`): never deploy, change config, or modify data without explicit approval.

`.firebaserc` has no default project on purpose. Pass `--project` (and
`--config` for staging) on every Firebase CLI command; never run `firebase use`
to set one. Keep the Dart entry point and Android flavor matched to the same
environment.

## Git workflow

- Work on `v2-launch` unless told otherwise; never commit directly to `main`.
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
- Quick Pick and Group Room share one weekly fair-use cap (server-configured, UTC Monday-start) under a global no-cost provider stop and kill switch, all enforced server-side. No ads or payments at launch.
- We'll Help Decide What We Want (the person's own typed list; formerly "Our Usual Spots" and "We Know What We Want!") never calls a restaurant provider and never consumes a live search.
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
