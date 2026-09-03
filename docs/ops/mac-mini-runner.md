# The Mac mini as GymSync's build machine

Set up 2026-09-03, when the repo went private.

## Why this exists

The repo went private to protect the IP. That part is free — GitHub's Free plan
allows unlimited private repositories, and privating `gymsync` costs nothing.

What is *not* free is GitHub-hosted Actions minutes. The difference is stark:

| | Public repo | Private repo (Free plan) |
|---|---|---|
| GitHub-hosted minutes | unmetered | 2,000 / month |
| Linux multiplier | — | 1× |
| **macOS multiplier** | — | **10×** |
| Artifact storage | unmetered | 500 MB |

`ios.yml` has four macOS jobs. One push to `master` runs `build-test` (45 min
cap), `screenshots` (45), and `deploy-testflight` (45) — about 135 macOS
minutes, which bills as **~1,350 minutes**. The monthly allowance is 2,000.
Privating without moving those jobs would have meant roughly *one and a half
pushes a month* before the pipeline started costing money.

Jobs that run on hardware you own are not metered at all. So the mini is not a
nice-to-have here — it is the thing that keeps a private GymSync free.

## What runs where

Everything runs on the mini. GitHub-hosted usage is zero, so the 2,000-minute
allowance is never touched at all.

The mini hosts **two runners**, distinguished by label:

| Job | Runner label | Notes |
|---|---|---|
| `ios.yml` › `build-test` | `gymsync` | Xcode + simulator |
| `ios.yml` › `screenshots` | `gymsync` | Xcode + simulator |
| `ios.yml` › `deploy-testflight` | `gymsync` | Xcode + signing identity |
| `ios.yml` › `watch-screenshot` | `gymsync` | watch simulator |
| `ios.yml` › `parity` | `gymsync-light` | Node + Puppeteer |
| `backend.yml` › `pgtap` | `gymsync-light` | Node, remote Postgres |
| `backend.yml` › `deno-test` | `gymsync-light` | Deno (3-leg matrix) |
| `backend.yml` › `deploy-functions` | `gymsync-light` | Supabase CLI |

Two, not one, because a runner takes a single job at a time. With everything on
one runner, `parity` and the whole `backend.yml` chain would queue behind a
45-minute `xcodebuild` — and a push touching both `GymSyncApp/` and `supabase/`
would serialise into one very long line. Splitting them means the light jobs run
while Xcode is busy, which is roughly what GitHub's fleet was doing for free.

Nothing about the light jobs actually needed Linux:

- **`pgtap`** — `run_pgtap.js` is a plain `pg` client against a remote Supabase
  URL. No local Postgres, no `psql` binary.
- **`deno-test`** — `denoland/setup-deno@v2` fetches a darwin-arm64 build and
  the pinned version (2.9.2) is unchanged.
- **`parity`** — a pixel diff, but a tolerant one. The two things that differ
  between Linux and macOS Chromium are antialiasing and font hinting, and
  `parity_diff.js:68` already discards both (`includeAA: false`,
  `threshold: 0.12` — "a coarse structural delta", per the report's own lede).
  Glyph metrics can't drift either, because the canvas serves its own `.woff2`
  files instead of resolving system fonts. And it is `continue-on-error`
  report-only, so a surprise surfaces for a human rather than blocking a merge.
- **`deploy-functions`** — the one genuine port. `supabase/setup-cli@v1` only
  branches on Linux libc and architecture and has no darwin path, so it is gone
  rather than moved: the CLI is already a devDependency, and `npx` runs the
  version the repo pins instead of the `version: latest` the action fetched.
  The deploy also gains `--use-api`, which bundles server-side; the default
  path shells out to Docker, which `ubuntu-latest` had preinstalled and the
  mini does not.

The runner assigns itself `self-hosted`, `macOS` and its architecture (`X64`
on this mini); the setup script adds `gymsync` or `gymsync-light`. The
workflows never name an architecture, so the same YAML will follow the label
onto an Apple Silicon replacement unchanged.

## This mini is Intel — what that means

Found out on first provisioning (2026-09-03), from Homebrew's own banner:

- **Homebrew does not support it.** Intel macOS support ended 2026-09. `brew`
  still runs, but with no bottles every install is a source build — `gh`
  pulled in a from-scratch Go toolchain, node is about an hour, deno is a Rust
  build that runs for hours. `scripts/mac-mini-setup.sh` therefore installs
  every tool from its project's own macOS artifact (nodejs.org `.pkg`, the
  deno and XcodeGen release zips, the gh `.pkg`), and `ios.yml` no longer
  falls back to `brew install` for anything. Do not `brew install` on this
  machine; if you need a tool, add it to the script the same way.
- **Getting Xcode onto it is not the App Store.** The store offers only the
  newest Xcode, and from 26.4 that requires macOS 26.2 — Tahoe, which does not
  support a 2018 mini and never will. **Xcode 26.3** (26 Feb 2026) is the last
  release that runs on Sequoia 15.6+, and it is a normal signed Apple download:
  <https://developer.apple.com/download/all/?q=Xcode%2026.3> (sign in with the
  developer account), expand the `.xip`, move `Xcode.app` to `/Applications`,
  open it once. Its iOS 26 SDK is all the app needs — deployment target is
  iOS 17 and nothing in the source is gated on a 26.x minor.
- **There is a clock on it, and it is short.** Xcode 27 ships alongside iOS 27
  in **September 2026** — now — and like 26.4 it will need a macOS this machine
  cannot run. App Store Connect has required each new major SDK from the
  following April for years running, so expect uploads built with the iOS 26
  SDK to be refused from **around April 2027**. That is roughly **seven
  months** as the deploy box, not the eighteen an earlier draft of this page
  claimed. Everything else — compiling, unit tests, screenshots, pgTAP, Deno,
  parity — has no such deadline and keeps working on Xcode 26.3 indefinitely.
  So the realistic shape after April 2027 is: this mini stays the test runner,
  and an Apple Silicon Mac (a base M4 mini, or a cloud Mac for deploys only)
  takes the `deploy-testflight` job. The runner labels are architecture-neutral
  on purpose so that split is a `--runner` on the new machine and a one-label
  edit to `deploy-testflight` — nothing else in the repo changes.
- **It is slower than what CI ran on.** GitHub's `macos-15` runners were Apple
  Silicon. Expect `build-test` and `screenshots` to take longer here; watch
  the first few runs against their 45-minute `timeout-minutes` before deciding
  whether to raise them. The persistent DerivedData helps a lot after the
  first build.
- **FoundationModels compiles, but may not run.** The Coach adapter links the
  framework, and the iOS 26 SDK carries it on Intel, so the build is fine.
  On-device Apple Intelligence itself needs Apple Silicon; any test that
  actually invokes the model on the simulator will not behave here the way it
  did on the hosted runner. Nothing in the suite is known to, but if a Coach
  test goes red only on this machine, that is the first place to look.

## One-time setup

### 1. Private the repo

<https://github.com/smolbwxt/gymsync/settings> → Danger Zone → Change
visibility → Private.

Do this **before** attaching the runner. A self-hosted runner on a public repo
is a genuine security hole: anyone can open a pull request from a fork, and the
`pull_request` trigger in `ios.yml` would execute their code on your hardware,
with access to your signing keychain. Private repos only run workflows from
collaborators, which closes it.

### 2. Provision the machine

```sh
git clone https://github.com/smolbwxt/gymsync.git
cd gymsync
./scripts/mac-mini-setup.sh
```

Installs `xcodegen`, `node`, `deno` and `gh` from their official macOS
artifacts (no Homebrew — see the Intel section below), verifies Xcode 26 and
its iOS 26 SDK, accepts the Xcode license, checks for iPhone and Apple Watch
simulators, disables system sleep, and bootstraps the workspace for hand builds
— seeding `Secrets.swift` / `TestSecrets.swift` from their templates (never
overwriting real ones), generating `GymSync.xcodeproj`, and running `npm ci`.

That last part is worth knowing about even outside CI: neither secrets file is
in the repo, and `xcodegen` fixes the source list at generate time, so a project
generated from a fresh clone *without* them does not contain them and the build
fails on missing symbols rather than on a missing file. After the script runs,
`xed GymSyncApp/GymSync.xcodeproj` opens a project that compiles. Edit
`Secrets.swift` with real Supabase values if you want the local app to reach the
backend.

Idempotent — re-run it after any OS or Xcode update.

Then prove the toolchain actually compiles Swift, before anything is registered:

```sh
./scripts/mac-mini-setup.sh --smoke
```

A build-only pass of the `GymSync` scheme for the iOS Simulator — a few minutes,
no signing identity needed, no runner involved. A mini that fails here would fail
`build-test` identically, just later and with a queued job in front of it.

### 3. Enable automatic login

System Settings → Users & Groups → Automatically log in as → *your user*.

This is load-bearing, not convenience. `svc.sh` installs the runner as a
**LaunchAgent**, so it lives inside a logged-in user session — which is the only
context that can reach the unlocked login keychain holding the signing identity.
A mini that reboots to the login window comes back with the runner down and no
way to sign a build.

Combined with the sleep settings the script applies, the mini should return to a
working runner unattended after a power cut.

### 4. Install the signing identity

```sh
./scripts/mac-mini-setup.sh --signing /path/to/AppleDevelopment.p12
```

Export the `.p12` from Keychain Access on a Mac that already signs GymSync
(Certificates → *Apple Development: …* → Export), including the private key.

It goes into the **login keychain, once** — not a per-run temporary keychain.
The old hosted-runner workflow rebuilt a throwaway keychain on every deploy and
then repointed the account's keychain search list at it. Harmless on a VM that
was destroyed after the job; on a machine that persists, it left the search list
naming a deleted file and would break `codesign` for every later build *and* for
Xcode.app itself.

The script also runs `security set-key-partition-list`, without which `codesign`
blocks on a GUI "allow access to key?" prompt that nobody is there to answer,
and the job hangs to its timeout.

### 5. Register the runner

Two runners, each needing its own registration token from
<https://github.com/smolbwxt/gymsync/settings/actions/runners/new>. Tokens are
single-use and expire in about an hour, so fetch them one at a time:

```sh
./scripts/mac-mini-setup.sh --runner       <TOKEN>   # Xcode jobs
./scripts/mac-mini-setup.sh --runner-light <TOKEN>   # Node/Deno jobs
```

Each downloads the current `actions/runner` into its own directory
(`~/actions-runner` and `~/actions-runner-light`), registers with its label and
a distinct name, installs a launchd service, and starts it. Both should appear
online under Settings → Actions → Runners.

Adding more light runners later is just more directories — the script's
`--runner-light` is safe to run again after moving the existing
`~/actions-runner-light` aside, and the three `deno-test` matrix legs are the
obvious thing to parallelise if the queue starts to bite.

### 6. Verify

```sh
./scripts/mac-mini-setup.sh --doctor
```

Then push a no-op commit touching `GymSyncApp/` — or use the workflow's
`workflow_dispatch` trigger — and watch the run land on the mini.

## Repo secrets

Still required (the mini does not hold these):

- `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SECRET_KEY`
- `TEST_USER_EMAIL`, `TEST_USER_PASSWORD`, `CI_TEST_USERNAME`
- `ASC_API_KEY` — the App Store Connect `.p8`
- `SENTRY_DSN`, `SENTRY_AUTH_TOKEN`
- `SUPABASE_DB_URL`, `SUPABASE_ACCESS_TOKEN` (`backend.yml`)

**No longer used, safe to delete:** `IOS_SIGNING_CERT_P12` and
`IOS_SIGNING_CERT_PASSWORD`. The certificate now lives in the mini's keychain;
`deploy-testflight` only asserts that an identity is present.

`ASC_API_KEY` is still written from a secret each run, but now into
`$RUNNER_TEMP` rather than `~/private_keys`. The runner wipes `_work/_temp` at
the start of every job, which gives the key back the short lifetime it used to
get for free from a disposable VM.

## Operating notes

**Serialisation.** Each runner takes one job at a time. On the `gymsync`
runner that means `build-test` → `deploy-testflight` run back to back; on
`gymsync-light`, `pgtap` and the three `deno-test` legs queue where they used to
fan out across GitHub's fleet — call it six minutes instead of three. Both
workflows now carry a `concurrency` block that cancels superseded runs on
non-`master` refs so a burst of pushes does not stack up; `master` is exempt in
both, so neither an archiving TestFlight build nor an in-flight function deploy
is ever cut off half-way.

**DerivedData persists** between runs, which is a large speed win over hosted
runners and a new source of stale-build weirdness. The existing fast-fail retry
in `build-test` already clears `~/Library/Developer/Xcode/DerivedData` when a
run dies in under five minutes.

**Xcode upgrades.** The workflow asserts on the *SDK* (`iphoneos26`), not the
bundle name, and selects the toolchain with `DEVELOPER_DIR` rather than
`sudo xcode-select` — so it needs no passwordless sudo and cannot leave the
machine globally pointed at another toolchain if a job dies mid-run. After
upgrading Xcode, re-run `./scripts/mac-mini-setup.sh` to re-accept the license.

**Service control:**

```sh
for d in ~/actions-runner ~/actions-runner-light; do (cd "$d" && ./svc.sh status); done
cd ~/actions-runner-light && ./svc.sh stop && ./svc.sh start
```

**Runner offline.** Check the mini is awake and logged in first — that is nearly
always the cause. `pmset -g custom | grep sleep` should show `0`. Note that with
no GitHub-hosted fallback, a mini that is down means *nothing* runs: no tests,
no TestFlight build, no function deploy. If that becomes a problem, the cheapest
insurance is putting `parity` and `backend.yml` back on `ubuntu-latest` — they
were within the free allowance by a wide margin.

## Consequences of privating, outside CI

- **App Store Support URL breaks.** It pointed at this repo's issues page. See
  `docs/appstore/APP_STORE_COPY.md` — it needs to move to the
  `gymsync-legal` Pages site before App Review sees a 404.
- **`smolbwxt/gymsync-legal` must stay public.** GitHub Pages does not serve
  from private repos on the Free plan, and that site hosts the privacy policy
  URL Apple requires.
- Forks, stars and watchers: none existed, so nothing was lost.
