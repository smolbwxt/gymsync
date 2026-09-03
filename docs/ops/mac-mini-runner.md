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

| Job | Runner | Why |
|---|---|---|
| `ios.yml` › `build-test` | mini | needs macOS + Xcode |
| `ios.yml` › `screenshots` | mini | needs a simulator |
| `ios.yml` › `deploy-testflight` | mini | needs macOS + the signing identity |
| `ios.yml` › `watch-screenshot` | mini | needs a watch simulator |
| `ios.yml` › `parity` | GitHub `ubuntu-latest` | Puppeteer + pixel diff, no Mac needed |
| `backend.yml` › `pgtap`, `deno-test`, `deploy-functions` | GitHub `ubuntu-latest` | no Mac needed |

The Linux jobs stay on GitHub deliberately. At the 1× multiplier they total
~20 billed minutes per full run, so the 2,000-minute allowance covers roughly a
hundred pushes a month — comfortably free, and one less toolchain (Postgres,
Deno, Chromium) to maintain on the mini.

The workflow selects the mini with `runs-on: [self-hosted, macOS, gymsync]`.
The runner assigns itself `self-hosted`, `macOS` and `ARM64`; the setup script
adds `gymsync`.

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

Installs Homebrew packages (`xcodegen`, `node`, `deno`), verifies Xcode 26 and
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

Get a registration token (valid ~1 hour) from
<https://github.com/smolbwxt/gymsync/settings/actions/runners/new>, then:

```sh
./scripts/mac-mini-setup.sh --runner <TOKEN>
```

Downloads the current `actions/runner`, registers it against the repo with the
`gymsync` label, installs it as a launchd service, and starts it.

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
- `SUPABASE_DB_URL`, `SUPABASE_ACCESS_TOKEN` (Linux jobs)

**No longer used, safe to delete:** `IOS_SIGNING_CERT_P12` and
`IOS_SIGNING_CERT_PASSWORD`. The certificate now lives in the mini's keychain;
`deploy-testflight` only asserts that an identity is present.

`ASC_API_KEY` is still written from a secret each run, but now into
`$RUNNER_TEMP` rather than `~/private_keys`. The runner wipes `_work/_temp` at
the start of every job, which gives the key back the short lifetime it used to
get for free from a disposable VM.

## Operating notes

**Serialisation.** One runner takes one job at a time, so `build-test` →
`deploy-testflight` now run back to back instead of in parallel with anything.
The `concurrency` block cancels superseded runs on non-`master` refs so a burst
of pushes does not queue for hours; `master` is exempt so a deploy already
archiving is never killed part-way to TestFlight. If the wait becomes annoying,
register a second runner instance from a second directory on the same mini.

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
cd ~/actions-runner
./svc.sh status
./svc.sh stop
./svc.sh start
```

**Runner offline.** Check the mini is awake and logged in first — that is nearly
always the cause. `pmset -g custom | grep sleep` should show `0`.

## Consequences of privating, outside CI

- **App Store Support URL breaks.** It pointed at this repo's issues page. See
  `docs/appstore/APP_STORE_COPY.md` — it needs to move to the
  `gymsync-legal` Pages site before App Review sees a 404.
- **`smolbwxt/gymsync-legal` must stay public.** GitHub Pages does not serve
  from private repos on the Free plan, and that site hosts the privacy policy
  URL Apple requires.
- Forks, stars and watchers: none existed, so nothing was lost.
