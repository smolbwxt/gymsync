#!/usr/bin/env bash
#
# mac-mini-setup.sh — provision a Mac mini as the GymSync build machine.
#
# Context (2026-09-03): the repo went private to protect the IP. Private repos
# are free, but GitHub-hosted Actions minutes are not: macOS runners bill at a
# 10x multiplier against a 2,000 min/month allowance, so a single push that ran
# build-test + screenshots + deploy (~135 macOS minutes) would have burned
# ~1,350 billed minutes — most of a month, in one push. Jobs that run on
# hardware you own are unmetered, so the mini is what keeps the whole pipeline
# free. .github/workflows/ios.yml points its four macOS jobs at
# [self-hosted, macOS, gymsync]; this script produces a machine that answers to
# that label.
#
# Everything here is idempotent — re-run it after an OS update or an Xcode
# upgrade and it will only do what is still missing.
#
#   ./scripts/mac-mini-setup.sh                      # deps + toolchain + power
#   ./scripts/mac-mini-setup.sh --signing cert.p12   # install the Apple cert
#   ./scripts/mac-mini-setup.sh --runner <TOKEN>     # register the Xcode runner
#   ./scripts/mac-mini-setup.sh --runner-light <TOKEN>  # register the light runner
#   ./scripts/mac-mini-setup.sh --smoke              # compile the app, no runner needed
#   ./scripts/mac-mini-setup.sh --doctor             # report, change nothing
#
# See docs/ops/mac-mini-runner.md for the surrounding procedure.

set -euo pipefail

REPO_URL="https://github.com/smolbwxt/gymsync"
# Two runners, one machine. The Xcode jobs get a runner to themselves; the
# Node/Deno jobs get their own so they are not stuck behind a 45-minute
# xcodebuild. See docs/ops/mac-mini-runner.md for why both live here.
RUNNER_LABEL="gymsync"            # build-test, screenshots, deploy, watch
RUNNER_DIR="$HOME/actions-runner"
RUNNER_LABEL_LIGHT="gymsync-light"  # pgtap, deno-test, parity, deploy-functions
RUNNER_DIR_LIGHT="$HOME/actions-runner-light"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '  \033[31m✗\033[0m %s\n' "$*" >&2; exit 1; }

require_macos() {
  [ "$(uname -s)" = "Darwin" ] || die "This script only runs on macOS (this is $(uname -s))."
}

# ---------------------------------------------------------------- toolchain

setup_homebrew() {
  bold "Homebrew"
  if command -v brew >/dev/null 2>&1; then
    ok "brew $(brew --version | head -1 | awk '{print $2}')"
    return
  fi
  # Not installed silently: Homebrew's installer wants an interactive sudo and
  # prints its own prompts, so hand the user the command rather than pretending
  # to have done it.
  die "Homebrew is not installed. Install it first:
      /bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"
      then re-run this script."
}

setup_packages() {
  bold "Build dependencies"
  # xcodegen: the repo has no committed .xcodeproj — project.yml is the source
  #   of truth and every job generates from it.
  # node: scripts/ (seed_qa_fixtures, parity harness, sentry-cli via npx).
  # deno: supabase/functions/* test + check + lint.
  # git-lfs is deliberately NOT installed — this repo does not use it.
  for pkg in xcodegen node deno; do
    if brew list --formula "$pkg" >/dev/null 2>&1; then
      ok "$pkg $(brew list --versions "$pkg" | awk '{print $2}')"
    else
      warn "installing $pkg"
      brew install "$pkg"
    fi
  done
}

setup_xcode() {
  bold "Xcode"
  local xcode
  xcode="$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$xcode" ] && [ -d /Applications/Xcode.app ]; then
    xcode=/Applications/Xcode.app
  fi
  [ -n "$xcode" ] || die "No Xcode in /Applications. Install Xcode 26 from the App Store, open it once, then re-run."

  export DEVELOPER_DIR="$xcode/Contents/Developer"
  ok "$xcode — $(xcodebuild -version | head -1)"

  # The workflow asserts on the SDK rather than the bundle name, so check the
  # same thing here: App Store Connect rejects archives built against an SDK
  # older than iOS 26, and FoundationModels (the Coach conversation adapter)
  # does not exist before it.
  if xcodebuild -showsdks 2>/dev/null | grep -q 'iphoneos26'; then
    ok "iOS 26 SDK present"
  else
    die "$xcode has no iOS 26 SDK. The deploy job will fail against App Store Connect."
  fi

  if ! xcodebuild -checkFirstLaunchStatus >/dev/null 2>&1; then
    warn "running xcodebuild -runFirstLaunch (needs sudo)"
    sudo xcodebuild -runFirstLaunch
  fi
  ok "first-launch components installed"

  # A runner cannot answer a license prompt; an unaccepted license fails every
  # job with a message that looks nothing like a license problem.
  if ! xcodebuild -license check >/dev/null 2>&1; then
    warn "accepting the Xcode license (needs sudo)"
    sudo xcodebuild -license accept
  fi
  ok "license accepted"
}

setup_simulators() {
  bold "Simulators"
  local iphone watch
  iphone="$(xcrun simctl list devices available 2>/dev/null | grep -c 'iPhone' || true)"
  watch="$(xcrun simctl list devices available 2>/dev/null | grep -cE 'Apple Watch' || true)"

  if [ "$iphone" -gt 0 ]; then
    ok "$iphone iPhone simulator(s) — build-test, screenshots"
  else
    die "No iPhone simulators. Xcode > Settings > Components: install an iOS runtime."
  fi

  if [ "$watch" -gt 0 ]; then
    ok "$watch Apple Watch simulator(s) — watch-screenshot"
  else
    # Not fatal: watch-screenshot is continue-on-error and only fires on
    # [watch-shot] commits. It creates its own device if a runtime exists.
    warn "No Apple Watch simulators. The watch-screenshot job will only work once a watchOS runtime is installed (Xcode > Settings > Components)."
  fi
}

setup_power() {
  bold "Power management"
  # A sleeping mini is an offline runner: queued jobs sit until the six-hour
  # GitHub timeout and the deploy never ships. Wake-on-LAN is not enough — the
  # runner holds a long-poll connection that sleep drops.
  if [ "$(pmset -g custom 2>/dev/null | awk '/ sleep/ {print $2; exit}')" = "0" ]; then
    ok "system sleep already disabled"
  else
    warn "disabling system sleep (needs sudo)"
    sudo pmset -c sleep 0
    sudo pmset -c disksleep 0
  fi
  # The display may sleep freely — that does not suspend the user session.
  ok "display sleep left alone (harmless)"
}

setup_workspace() {
  bold "Local build workspace"
  # CI writes these two from repo secrets on every run and .gitignore keeps them
  # out of the repo, so a fresh clone has neither. That matters more than it
  # looks: xcodegen fixes the source list at generate time, so a project
  # generated without them does not contain them, and the build fails on
  # missing symbols rather than on a missing file. Seed from the templates so
  # the mini can open and compile the project by hand straight away — edit
  # Secrets.swift with real values if you want the local app to reach Supabase.
  local secrets="GymSyncApp/GymSync/Config/Secrets.swift"
  local test_secrets="GymSyncApp/GymSyncTests/TestSecrets.swift"

  if [ -f "$secrets" ]; then
    ok "Secrets.swift present (left alone)"
  else
    cp "$secrets.template" "$secrets"
    warn "Secrets.swift seeded from template — placeholders, network tests will skip"
  fi

  if [ -f "$test_secrets" ]; then
    ok "TestSecrets.swift present (left alone)"
  else
    cp "$test_secrets.template" "$test_secrets"
    warn "TestSecrets.swift seeded from template"
  fi

  xcodegen generate --spec GymSyncApp/project.yml --project GymSyncApp >/dev/null
  ok "GymSync.xcodeproj generated — open it with: xed GymSyncApp/GymSync.xcodeproj"

  if [ -d node_modules ]; then
    ok "node_modules present"
  else
    warn "installing node dependencies (npm ci)"
    npm ci
  fi
}

find_xcode() {
  local xcode
  xcode="$(ls -d /Applications/Xcode_26*.app 2>/dev/null | sort -V | tail -1 || true)"
  if [ -z "$xcode" ] && [ -d /Applications/Xcode.app ]; then
    xcode=/Applications/Xcode.app
  fi
  [ -n "$xcode" ] || die "No Xcode in /Applications."
  printf '%s' "$xcode"
}

smoke_build() {
  bold "Smoke build — compile GymSync for the iOS Simulator"
  # Proves the toolchain end to end — Xcode, SDK, xcodegen output, SPM
  # resolution, the Swift compile itself — before any runner is registered,
  # in a few minutes rather than the 20+ a full test run costs. A mini that
  # fails here would have failed build-test the same way, just later and
  # with a queued job in front of it.
  #
  # Signing is disabled ONLY here. ios.yml's rule against unsigned simulator
  # bundles is about TESTS: unsigned test hosts lack keychain entitlements
  # and supabase-swift silently drops its session. This is a build, nothing
  # signs in, and it means the smoke works before --signing has been run.
  [ -d GymSyncApp/GymSync.xcodeproj ] \
    || die "No GymSync.xcodeproj — run this script with no arguments first."
  local xcode
  xcode="$(find_xcode)"
  export DEVELOPER_DIR="$xcode/Contents/Developer"
  ok "using $xcode"
  ( cd GymSyncApp && set -o pipefail && xcodebuild build \
      -project GymSync.xcodeproj \
      -scheme GymSync \
      -destination 'generic/platform=iOS Simulator' \
      CODE_SIGNING_ALLOWED=NO | tail -25 )
  ok "GymSync compiles on this machine"
}

# ------------------------------------------------------------------ signing

setup_signing() {
  local p12="${1:-}"
  bold "Code signing identity"

  if security find-identity -v -p codesigning | grep -q 'Apple Development'; then
    ok "Apple Development identity already in the login keychain"
    security find-identity -v -p codesigning | sed 's/^/    /'
    if [ -z "$p12" ]; then return; fi
    warn "a .p12 was supplied anyway — importing it as well (rotation)"
  fi

  if [ -z "$p12" ]; then
    die "No Apple Development identity, and no .p12 given.
      Export one from Keychain Access on a Mac that already signs GymSync
      (Certificates > Apple Development: ... > Export, as .p12), copy it here,
      then run: $0 --signing /path/to/cert.p12"
  fi
  [ -f "$p12" ] || die "No such file: $p12"

  # Into the LOGIN keychain, once — not a per-run temporary keychain. The old
  # workflow built a throwaway keychain on every deploy and then pointed the
  # account's keychain search list at it. On a VM that died after the job that
  # was fine; on a machine that persists it leaves the search list naming a
  # deleted file and breaks codesign for everything afterwards.
  local login_keychain
  login_keychain="$(security default-keychain | tr -d ' "')"
  printf 'Password for %s: ' "$(basename "$p12")"
  read -rs P12_PASS; echo

  security import "$p12" -k "$login_keychain" -P "$P12_PASS" \
    -T /usr/bin/codesign -T /usr/bin/security
  unset P12_PASS

  # Without this, codesign blocks on a GUI "allow access to key?" prompt that
  # nobody is sitting in front of, and the job hangs until its timeout.
  printf 'Login keychain password (your macOS user password): '
  read -rs LOGIN_PASS; echo
  security set-key-partition-list -S apple-tool:,apple: -s -k "$LOGIN_PASS" "$login_keychain" >/dev/null
  unset LOGIN_PASS

  security find-identity -v -p codesigning | grep -q 'Apple Development' \
    || die "Import finished but no Apple Development identity is visible. Check the .p12 contains the private key."
  ok "identity imported and unlocked for codesign"
  security find-identity -v -p codesigning | sed 's/^/    /'
}

# ------------------------------------------------------------------- runner

setup_runner() {
  local token="${1:-}" label="${2:?}" dir="${3:?}" suffix="${4:-}"
  bold "GitHub Actions runner — $label"

  if [ -z "$token" ]; then
    die "Needs a registration token (valid ~1 hour), from:
      ${REPO_URL}/settings/actions/runners/new
      A token is single-use, so grab a fresh one for each runner."
  fi

  if [ -f "$dir/.runner" ]; then
    ok "already configured in $dir"
    ( cd "$dir" && ./svc.sh status 2>/dev/null | sed 's/^/    /' ) || true
    return
  fi

  mkdir -p "$dir"
  local arch version tarball
  case "$(uname -m)" in
    arm64)  arch="osx-arm64" ;;
    x86_64) arch="osx-x64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac

  version="$(curl -fsSL https://api.github.com/repos/actions/runner/releases/latest \
            | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p' | head -1)"
  [ -n "$version" ] || die "Could not determine the latest actions/runner release."
  tarball="actions-runner-${arch}-${version}.tar.gz"

  warn "downloading runner ${version} (${arch})"
  curl -fsSL -o "$dir/$tarball" \
    "https://github.com/actions/runner/releases/download/v${version}/${tarball}"
  tar xzf "$dir/$tarball" -C "$dir"
  rm -f "$dir/$tarball"

  # --labels adds ours on top of the ones the runner assigns itself
  # (self-hosted, macOS, ARM64); together they are exactly what the workflows'
  # `runs-on:` arrays ask for. Each runner needs a distinct --name, hence the
  # suffix — two runners registering under one name would replace each other.
  ( cd "$dir" && ./config.sh \
      --url "$REPO_URL" \
      --token "$token" \
      --name "$(scutil --get LocalHostName 2>/dev/null || hostname -s)${suffix}" \
      --labels "$label" \
      --work "_work" \
      --unattended \
      --replace )
  ok "registered with label: $label"

  # svc.sh installs a LaunchAgent, so the runner lives inside the logged-in
  # user session. That is deliberate and load-bearing: only a session-scoped
  # process can reach the unlocked login keychain holding the signing identity.
  # It is also why the mini needs automatic login enabled — see the runbook.
  ( cd "$dir" && ./svc.sh install && ./svc.sh start )
  ok "installed as a launchd service and started"
}

runner_status() {
  local label="$1" dir="$2"
  if [ -f "$dir/.runner" ]; then
    ok "runner '$label' configured"
    ( cd "$dir" && ./svc.sh status 2>/dev/null | sed 's/^/    /' ) || warn "  service not running"
  else
    warn "runner '$label' not configured"
  fi
}

# ------------------------------------------------------------------- doctor

doctor() {
  bold "GymSync Mac mini — status"
  printf '\n'
  command -v brew     >/dev/null 2>&1 && ok "homebrew"  || warn "homebrew missing"
  command -v xcodegen >/dev/null 2>&1 && ok "xcodegen"  || warn "xcodegen missing"
  command -v node     >/dev/null 2>&1 && ok "node $(node --version)" || warn "node missing"
  command -v deno     >/dev/null 2>&1 && ok "deno $(deno --version | head -1 | awk '{print $2}')" || warn "deno missing"

  if xcodebuild -version >/dev/null 2>&1; then
    ok "$(xcodebuild -version | head -1) at $(xcode-select -p)"
    xcodebuild -showsdks 2>/dev/null | grep -q 'iphoneos26' \
      && ok "iOS 26 SDK" || warn "no iOS 26 SDK — deploys will be rejected"
  else
    warn "xcodebuild unavailable"
  fi

  security find-identity -v -p codesigning 2>/dev/null | grep -q 'Apple Development' \
    && ok "Apple Development signing identity" \
    || warn "no signing identity — deploy-testflight will fail (run --signing)"

  [ "$(pmset -g custom 2>/dev/null | awk '/ sleep/ {print $2; exit}')" = "0" ] \
    && ok "system sleep disabled" || warn "system sleep is ENABLED — the runner will go offline"

  [ -f GymSyncApp/GymSync/Config/Secrets.swift ] \
    && ok "Secrets.swift present" || warn "no Secrets.swift — xcodegen will omit it and the build will fail"
  [ -d GymSyncApp/GymSync.xcodeproj ] \
    && ok "GymSync.xcodeproj generated" || warn "no .xcodeproj — run this script with no arguments"

  runner_status "$RUNNER_LABEL" "$RUNNER_DIR"
  runner_status "$RUNNER_LABEL_LIGHT" "$RUNNER_DIR_LIGHT"
  printf '\n'
}

# --------------------------------------------------------------------- main

require_macos
cd "$REPO_ROOT"

case "${1:-}" in
  --signing) shift; setup_signing "${1:-}" ;;
  --runner)
    shift; setup_runner "${1:-}" "$RUNNER_LABEL" "$RUNNER_DIR" "" ;;
  --runner-light)
    shift; setup_runner "${1:-}" "$RUNNER_LABEL_LIGHT" "$RUNNER_DIR_LIGHT" "-light" ;;
  --smoke)   smoke_build ;;
  --doctor)  doctor ;;
  ""|--all)
    setup_homebrew
    setup_packages
    setup_xcode
    setup_simulators
    setup_power
    setup_workspace
    printf '\n'
    bold "Base toolchain ready."
    printf '  Next: %s --smoke                       # prove it compiles\n' "$0"
    printf '        %s --signing /path/to/cert.p12\n' "$0"
    printf '        %s --runner       <TOKEN>   # Xcode jobs\n' "$0"
    printf '        %s --runner-light <TOKEN>   # Node/Deno jobs\n' "$0"
    printf '  Tokens (one each, single-use): %s/settings/actions/runners/new\n\n' "$REPO_URL"
    ;;
  -h|--help)
    sed -n '2,25p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    ;;
  *) die "Unknown option: $1  (try --help)" ;;
esac
