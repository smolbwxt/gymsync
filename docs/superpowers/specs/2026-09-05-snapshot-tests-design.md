# Snapshot tests as the primary design renderer — design

Owner approved the approach 2026-09-05 (after the CI screenshot pipeline was fixed, PR #25). This is the
design to review before an implementation plan. It stands up **Tier 1** from the pipeline discussion; the
fixed UI-test walks (`GymSyncUITests`) stay as **Tier 2** integration truth.

## Goal

Render each screen and widget state in-process, in the Onyx palette, from injected fixtures, and commit a
reference PNG per state so every design change shows a per-PR pixel diff. This makes "perturb only what I
was told" checkable, and reaches live-session states (set page, group turn, rest, PR) that the signed-in
walks cannot without a real session.

## Why a new tier rather than more UI tests

| | UI-test walk (Tier 2, exists) | Snapshot test (Tier 1, new) |
|---|---|---|
| Launches the app / signs in | Yes | No — renders a view in a host |
| Deterministic | No (network, timing, shared account) | Yes |
| Reaches live-session states | Only inside a real session | Yes, by fixture |
| Cost per frame | one app launch | milliseconds |
| Per-PR before/after diff | manual | built in (reference PNG in git) |

## Library

`pointfreeco/swift-snapshot-testing`, one pinned SPM package added to `GymSyncApp/project.yml` under
`packages:` (exact-version pin, matching the repo's deliberate no-`from:` convention documented at
`project.yml:19-56`). No other dependency. It records a reference on first run and fails a later run whose
render drifts, writing the failed and reference images for the diff.

## Where it lives

A new **unit-test** target `GymSyncSnapshotTests` (type `bundle.unit-test`, depends on `GymSync`), NOT the
UI-test target — snapshots run in-process like unit tests, need no Supabase credentials, and must run in the
fast `build-test` job, not the slow credentialed `GymSyncScreenshots` scheme. References committed under
`GymSyncApp/GymSyncSnapshotTests/__Snapshots__/`.

## The fixtures are the asset, and they already exist

`CatalogHostView`'s `content_*` builders already construct every hermetic fixture (routine, exercises, prior
sets, personas, the `solo-live-set` session seeded in PR #25). The one refactor that carries the whole
design: **extract those builders into a shared `CatalogFixtures` enum** that both `CatalogHostView` and the
snapshot tests call. One source of truth for fixtures; the catalog and the snapshots can never drift.

## What renders, and how the look is pinned

- Host each view in a fixed iPhone-16-Pro-sized container via the library's `.image(layout:)` config.
- Force Onyx + sky the same way the app now does: construct the view under a `ThemeStore` pinned through the
  `launchPin` seam PR #25 added, so snapshots and the CI walks share one palette path.
- Register the Archivo faces in the test bundle's `setUp` (they are app resources; a snapshot in the CI
  simulator has them, a snapshot on a bare unit host needs the explicit registration) — otherwise text
  falls back silently and every reference is subtly wrong. This is the one real setup risk.
- `record` mode is committed as `false`; a deliberate reference refresh is a reviewed commit, never the
  default (the same "checker that stops checking" doctrine as `OneShotFlags`).

## First coverage set (the plan will sequence these)

1. Design-system components in every state: `GS3DButton`, `GSSettingsRow`, `GSStatTile`, `GSPlateToken`,
   `GSBarLoader`, the talk pill, `RPESwipeTrack`. Small, high-churn, highest diff value.
2. The screens this redesign round touches: the solo set page (already a catalog fixture), the rest page,
   Home, the recap, the PR splash.
3. Multi-state screens as parameterized cases (empty / populated / error) where the builder allows.

Group my-turn stays deferred until its view takes injected state (the L item from the pipeline
investigation, `GroupSessionLiveView`).

## CI

Snapshots run inside the existing `build-test` job (they are unit tests) — no new job, no extra runtime tier,
and a drift fails `build-test` loudly (unlike the screenshots job's `continue-on-error`). The library writes
failed/reference/diff PNGs into the test bundle output; add them to the uploaded artifacts so a red diff is
reviewable without a Mac.

## Risks

- **Font registration** (above) — the one thing that makes references silently wrong; the plan verifies it
  on the first recorded reference by eyeballing one text-heavy snapshot.
- **Simulator/OS drift** — snapshot pixels are tied to the renderer; pin the simulator (already done for the
  screenshots job: iPhone 16 Pro) and the Xcode image (`macos-15`, Xcode 26). A future runner-image bump is
  a deliberate reference refresh.
- **Reference churn** — keep the first set small; every reference is a file a human approved once.

## Not in scope

The Tier 2 walks (kept, now fixed). Group my-turn fixture. Pixel-diffing the UI-test captures (the walks
stay layout-only; snapshots are where pixel diffing lives).
