# watchOS Capture Infrastructure — Implementation Plan (Phase D prerequisite)

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or executing-plans. **This plan needs a Mac to execute** (the capture-mechanism half is unverifiable from Windows/CI-only reasoning — see §Risk). The catalog half (Task A) is compile-verifiable anywhere; the capture half (Task B) needs a real watch simulator to iterate on.

**Goal:** give Phase D's Watch family what every other family already has — a way to render each watch screen deterministically and capture it, so designer frames can be measured against reality by the parity harness.

**Why this is a plan, not shipped code (Opus pre-GA closeout, 2026-07-20):** the iOS capture pipeline is XCUITest-driven (`GymSyncScreenshots` scheme → drives `CatalogHostView` → screenshots as `.xcresult` attachments → `xcresulttool`/`xcparse` export). watchOS XCUITest screenshot support is historically broken/absent, and this controller cannot iterate on watch-simulator behavior from Windows. Shipping an unverifiable watch UITest scheme would burn CI cycles diagnosable only on a Mac. The catalog (Task A) is buildable+compile-verifiable now; the capture mechanism (Task B) is the genuine uncertainty and is scoped with a recommendation rather than guessed at blind.

## Task A — Watch debug catalog (compile-verifiable; do this first)

**Files:** create `GymSyncApp/GymSyncWatch/WatchCatalogHostView.swift`; modify `GymSyncWatch/WatchSessionStore.swift` (fixture seam), `GymSyncWatch/GymSyncWatchApp.swift` (launch-arg host), `GymSyncApp/project.yml` if a launch-arg scheme is needed.

- [ ] **Fixture seam on `WatchSessionStore`**: `sessionState`/`idleState`/`isStale` are `private(set)`, so add a `#if DEBUG` initializer IN THE SAME FILE (private is file-scoped) that sets them directly — mirror the iOS `CatalogHostView` fixture-init idiom exactly (`CampaignsTabView.init(catalogFixture...)`). Provide factory statics for the 3 whose-turn states (LIVE / ENDED / IDLE) + a live state with `currentExerciseID` set (for `LogSetView.canLog`) + favorites+labels (for `SoundboardView`) + burpee counts (for `LedgerView`). Build fixture `WatchSessionStatePayload`/`WatchIdleStatePayload` values (both are `Codable` structs in `GymSyncShared/WatchEnvelope.swift` — memberwise init, all fields).
- [ ] **`WatchCatalogHostView`**: `#if DEBUG`, a `List`/`TabView` of every surface × state: `WhoseTurnView`(live/ended/idle), `LogSetView`(live), `SoundboardView`, `LedgerView`, each fed a fixture store, each wrapped in `.environment(\.gsWatchTheme, .midnight)`. One case per intended capture id; name the ids to match the design brief's requested watch captures (`docs/design/requests/2026-07-20-phase-d-watch.md`).
- [ ] **Launch-arg host** in `GymSyncWatchApp`: gate on a `ProcessInfo` launch arg (`UITEST_WATCH_CATALOG` or similar) → show `WatchCatalogHostView` instead of `ContentView`, exactly the `#if DEBUG` + launch-arg pattern the iOS `GymSyncApp` uses for `CatalogHostView`. No launch prompt, compiled out of release.
- [ ] Commit. CI `build-test` compiles the watch target transitively → proves it builds. (Rendering correctness is unverifiable until Task B or manual Mac inspection.)

## Task B — Capture mechanism (needs a Mac to iterate)

Two candidate approaches, in recommended order:

1. **RECOMMENDED — `ImageRenderer` in a watch unit test.** watchOS 10 has SwiftUI `ImageRenderer` (rasterize a view to `CGImage`/`UIImage` synchronously, in-process). Add a minimal `GymSyncWatchTests` target (project.yml — the handoff notes none exists; this is the infra), one test that iterates the catalog cases, `ImageRenderer`s each to a PNG, and attaches it (`XCTAttachment`) so the existing `.xcresult`-export CI step harvests it identically to iOS. Watch UNIT tests are far more reliable in CI than watch UITests. Uncertainties to resolve on a Mac: does `ImageRenderer` honor the `gsWatchTheme` environment + fixed frame; does the watch test target link cleanly; does `xcodebuild test` on a paired watch sim produce the `.xcresult` attachments. Keep the CI job `continue-on-error: true` (like the iOS `screenshots` job already is) so a capture miss never blocks a merge.

2. **FALLBACK — XCUITest on a watch simulator** (mirror the iOS `GymSyncScreenshots` scheme). Only if (1) proves unworkable. High risk: watchOS XCUITest `.screenshot()` support is historically incomplete; expect to discover it produces empty attachments (the exact failure mode iOS hit at "run 29297982021", but with no known fix on watch). Document the result either way.

- [ ] Whichever path: add the CI job to `.github/workflows/ios.yml` modeled on the `screenshots` job (checkout → xcodegen → seed → `xcodebuild test` on a watch destination → export attachments → upload artifact), `continue-on-error: true`, `needs: build-test`.
- [ ] Feed captured `watch-*.png` into the parity harness `frame-map.json` alongside the iOS `app-*.png` set so Phase D's Watch family measures against them.

## Risk / honesty note
Task A is low-risk and verifiable-by-compile. Task B is the real unknown: no one has proven watchOS capture in this CI, and it can only be iterated on a Mac. If Task B (1) and (2) both fail, the honest fallback is **manual Mac captures** (run the Task-A catalog on a watch sim, screenshot by hand) feeding `frame-map.json` — Phase D's Watch family still gets its reality baseline, just not automated. That is an acceptable v1; automation is the nice-to-have.

## Also file when executing (from the D-briefs findings, ledgered)
The 4 built watch screens never got `accepted-deviations.json` entries at ship time (process gap). File real entries for whose-turn/log-set/soundboard/ledger when their catalog ids exist, so the parity harness tracks them like every other system-designed screen.
