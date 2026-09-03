# GymSync

iOS + watchOS app (SwiftUI, "Onyx" design system) on a Supabase backend. Everything —
compile, test, design parity, TestFlight — builds and ships from the Mac mini's
self-hosted runners. `docs/ops/mac-mini-runner.md` is the runbook; read it before
touching CI.

## Layout

- `GymSyncApp/` — Xcode project **generated** from `project.yml` by XcodeGen; the
  `.xcodeproj` is gitignored, never commit one.
  - `GymSync/` app · `GymSyncWatch/` watch app · `GymSyncShared/` · `GymSyncTests/`
    unit tests · `GymSyncUITests/` screenshot/UI tests
- `supabase/` — `migrations/`, pgTAP suite in `tests/`, edge functions in
  `functions/*` (Deno)
- `scripts/` — Node tooling: pgTAP runner, QA fixture seeding, design-parity harness,
  `mac-mini-setup.sh`
- `design-web/` — React/web edition of Onyx (`@gymsync/onyx`), hand-mirrored from the
  SwiftUI components; `docs/design/` holds the design canvas and proof frames
- `docs/` — specs (`superpowers/`), training science, App Store copy (`appstore/`),
  legal, ops runbooks (`ops/`)

## Build and test on the mini

Two gitignored files must exist before generating the project, or xcodegen silently
omits them and the build fails on missing symbols rather than a missing file:
`GymSyncApp/GymSync/Config/Secrets.swift` and `GymSyncApp/GymSyncTests/TestSecrets.swift`.
`scripts/mac-mini-setup.sh` seeds both from their `.template` siblings (placeholders;
network tests skip). Regenerate after adding files or restoring secrets.

```sh
./scripts/mac-mini-setup.sh            # toolchain, workspace bootstrap — idempotent
./scripts/mac-mini-setup.sh --smoke    # compile GymSync for the simulator, no runner needed
./scripts/mac-mini-setup.sh --doctor   # report state, change nothing

xcodegen generate --spec GymSyncApp/project.yml --project GymSyncApp

# Unit tests — same invocation CI's build-test uses. Pick the simulator by UDID;
# names differ per machine.
SIM=$(xcrun simctl list devices available | grep iPhone | head -1 | grep -oE '[0-9A-F-]{36}')
( cd GymSyncApp && xcodebuild test -project GymSync.xcodeproj -scheme GymSync -destination "id=$SIM" )

# UI/screenshot tests: slow, need real credentials — -scheme GymSyncScreenshots
# Watch app:  -scheme GymSyncWatch -destination 'generic/platform=watchOS Simulator'

node scripts/run_pgtap.js                 # SUPABASE_DB_URL from env or .env.local; every test rolls back
( cd supabase/functions/<fn> && deno test && deno check *.ts && deno lint )
npm run test:parity                       # parity-harness unit tests (node --test)
npm run build --prefix design-web         # web Onyx bundle
```

Never pass `CODE_SIGNING_ALLOWED=NO` to a **test** run: unsigned simulator bundles lack
keychain entitlements and supabase-swift silently drops its session. Build-only
invocations (the `--smoke` mode) are fine unsigned.

## CI shape

Both workflows run entirely on the mini — labels `gymsync` (Xcode jobs) and
`gymsync-light` (Node/Deno jobs). There is no GitHub-hosted fallback.

- `ios.yml` — `build-test` → `screenshots` → `parity`; `deploy-testflight` on a
  `master` push or `workflow_dispatch`; `watch-screenshot` on `[watch-shot]` commits.
  `screenshots`, `parity`, and `watch-screenshot` are `continue-on-error` — they
  produce artifacts, they do not gate.
- `backend.yml` — `pgtap`, `deno-test` (matrix over three functions),
  `deploy-functions` on a `master` push.

A push to `master` therefore **ships**: a TestFlight build (`CURRENT_PROJECT_VERSION`
= workflow run number) and an edge-function deploy. App Store *submission for review*
is not automated — CI uploads the build to App Store Connect; a human submits it.

## Conventions worth matching

- Comments say *why*, carry a date, and name the incident that motivated them. Match
  that density; a bare "what" comment is below the bar here.
- Commit subjects: `type(scope): summary` — `fix(onboarding):`, `ci(sentry):`,
  `docs:` — with a body that explains the reasoning, not the diff.
- Gitignored and must stay that way: `Secrets.swift`, `TestSecrets.swift`, `.env.local`,
  `*.xcodeproj`, `DerivedData/`, `node_modules/`.
