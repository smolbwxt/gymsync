# Goal-first programming — the goal, the ladder, and the block (phase 1) — implementation plan

**For agentic workers.** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Every task below is
one subagent, one commit, one review. Do not batch tasks; do not start a stream before Task 0 is pushed.

**Goal.** Put a named, measurable goal in front of the generator and a weekly ladder behind it, so that every
block is the pursuit of one milestone and the Home strip is one rung of that pursuit.

**Architecture.** A `BlockGoal` (metric + target + date) is created at a new front door and handed to
`ProgramGenerator` as an input; the block it generates is then *read out* onto the goal's metric as a `Ladder`
of one rung per week, so the ladder and the plan cannot disagree. Each week the current rung is materialised
into the shipped `weekly_goals` row that Home already renders, and Coach re-derives the remaining rungs from
actuals — proposing, never moving, the athlete's own milestone and date.

**Tech stack.** Swift 6 / SwiftUI (iOS 18 target), Supabase Postgres + PostgREST + RLS, pgTAP, XCTest +
XCUITest, GitHub Actions (`ios.yml`, `backend.yml`), XcodeGen (`project.yml`).

**Spec (the authority):** `docs/superpowers/specs/2026-09-07-goal-first-programming-design.md`.
Phase 1 is §10's first bullet; **every section binds**. Design language:
`docs/superpowers/specs/2026-09-05-design-language.md`. Context map with file:line facts:
`.superpowers/sdd/2026-09-07-design-round/context-map.md`. Round decisions:
`.superpowers/sdd/2026-09-07-design-round/decisions.md`. Format exemplar (the shape this plan copies):
`docs/superpowers/plans/2026-09-06-home-v3-production-plan.md`.

---

## Base branch — read this first

**Every stream forks from `origin/master` (`4ed32d0` or later).** Master already carries the entire weekly-goal
system this plan builds on: `weekly_goals` + its RLS and trigger (`20260906000001`), `WeeklyGoal`/`WeekMath`,
`WeeklyGoalRepository` + `StubWeeklyGoalRepository`, `WeeklyGoalProgressMath`, `WeeklyGoalDetector`,
`WeeklyGoalWriteRule`, `WeeklyGoalProposalRule`, `LiveWeeklyGoalRepository`, `HomeWeeklyGoalStrip`,
`WeeklyGoalEditorSheet`, `MuscleGroup`, and the catalog at 81 ids / `FLOOR` **98**.

Verify against `origin/master`, never a local `master` ref — the Home v3 plan lost a day to exactly that
(its own "Correction" note). `feat/congruence-b1` is in flight on the same tree; it touches design-system
colour and hero surfaces only, and none of the files this plan names. If it merges first, rebase; do not wait
for it.

Task 0 lands on `feat/goal-first-release` forked from `origin/master`; the four streams fork from the tip of
**Task 0.5**; integration merges them back into `feat/goal-first-release`, which becomes the single release PR.

---

## Global Constraints

These bind **every** task. A task that breaks one says so in its commit body, and why.

1. **Swift compiles only in CI.** No macOS toolchain on this machine: no `xcodebuild`, no `swift build`, no
   simulator. Read the code you are changing, reason about the types, push. `.github/workflows/ios.yml` is
   the compiler.
2. **One commit per task**, with this trailer, verbatim:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni
   ```
   Use `git commit -F <file>` or a single-quoted heredoc. A `-m` message containing backticked identifiers has
   silently deleted words in this repo before.
3. **The catalog four-part contract, in ONE commit per id.** A new `CatalogScreen` id lands in all four places
   in the *same* commit:
   - the `case` in `App/CatalogHostView.swift`'s `enum CatalogScreen` (:16-111) **and** its builder arm in the
     same file's `switch` (:120-201);
   - the id string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array — the test asserts
     `CatalogScreen.allCases.count == ids.count`, so a case without a list entry fails the build;
   - a `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`
     (helper at :334-349);
   - an entry in `docs/design/frame-map.json` (`"<id>": {"frame": <n>, "title": "<title>"}`). Frames 71–92 are
     taken; **new ids start at frame 93**.
   **The FLOOR is bumped only at integration** (task I4), once, for all eight ids. A stream branch that raises
   `FLOOR` before its ids exist on the integration branch turns CI red for the other three streams.
4. **Never `XCTUnwrap(await …)`.** `try XCTUnwrap` on an `await` expression is a compile error in this target's
   Swift mode. Bind first (`let value = await …`), then `let unwrapped = try XCTUnwrap(value)`.
5. **Never raise a HealthKit sheet from a unit test.** `HealthKitBridge.requestPermission()` and
   `requestWorkoutAndDistancePermission()` present a system sheet that hangs the simulator run. New readers
   (`lissMinutes`, stretch counts) are tested through the **pure** functions that take samples as parameters;
   the store-touching wrapper is exercised only by the app.
6. **Live-DB tests use the `TestSession` teardown factory and far-future rows.** `GymSyncTests/TestSession.swift`
   is the only place a test may create a session; register cleanup with `addTeardownBlock` **before** the write
   (XCTest awaits teardown; `defer { Task { … } }` loses the race with process exit —
   `ModerationRepositoryTests.swift:20-27`). Every row a live-DB test writes is dated **2099**
   (`WeeklyGoalLiveRepositoryTests.swift:15-19`): these run as the shared CI account, and a current-week row
   would fight `scripts/seed_qa_fixtures.js` and change what `app-tab-home` captures.
7. **No `Date.now` and no live repository reachable from a catalog builder.** Every `content_*` in
   `CatalogHostView` renders from fixture integers and strings (`HomeV2Fixtures.swift:1-10`,
   `WeeklyGoalFixtures.swift:10-14`). New builders take `StubBlockGoalRepository` and a fixture `today`.
8. **The frozen Home frames must stay byte-identical.** `app-home-v3-08a-targets-above-calendar` and
   `app-home-v3-08b-targets-above-join` are the owner-approved compositions. They render
   `HomeWeeklyGoalStrip` with a *fixture* `WeeklyGoalProgress` whose `kicker` is a literal string, so the
   block kicker (task D2) must not reach them. I5's canary is those two captures unchanged.
9. **Design rules, by number** (`2026-09-05-design-language.md`). The ones this plan leans on:
   - **1** — two raised surfaces only (`.gs3DCard` to read, `.gs3DCardStyle` to press); furniture inside a
     raised box stays flat; strips are `surface` at 14 pt radius; radii cards 24 / small 16 / strips 14 /
     chips 999.
   - **2** — default text; **gold has exactly two jobs** (the week-streak number, the check-in window) and
     neither is here; accent is spent on the one primary action, an invitation line, and the current item;
     green means done; red is errors only; no decorative emoji, SF Symbols only.
   - **3** — kickers are 10–11 pt caps, 0.1–0.13 em tracking, `muted`; numbers tabular.
   - **4** — **one primary per screen**; questions above the fold, readouts below; three doors in a row at most.
   - **7** — Coach is one line, first person, tappable.
   - **9** — sentence case for sentences, caps for kickers; a button says exactly what happens.
10. **Migrations are applied to the live project at a controller gate before pgTAP runs.**
    `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js` against the **live**
    `SUPABASE_DB_URL` secret. There is no `supabase db push` anywhere in CI — grep-verified. A pgTAP test for a
    table that has not been applied to project `chjkkwqwdlmaxacwglzm` **will fail**. Stream A's migrations are
    applied by the operator (or via the Supabase MCP `apply_migration`) before the matching pgTAP task's CI
    run; the commit body says so.
11. **`params` / `target` JSON keys are camelCase, with no `keyEncodingStrategy`.** The app sets none anywhere,
    so the synthesized encoder's Swift property names are the wire names — `20260906000001_weekly_goals.sql:35-40`
    and `supabase/tests/weekly_goals_test.sql:23-27` both state this. `block_goals.target` and
    `block_goal_rungs.target` follow the identical rule. Absent, never null, for a field a metric does not use.
12. **Do not change `ProgramGenerator.weeklyMuscleSets`** (`ProgramGenerator.swift:1871-1887`) or
    `VolumeAccountingTests`. The Home v3 plan froze it and the divergence between its per-muscle-string credit
    and `MuscleGroup.credit`'s six-group capped credit is a documented open item, not this plan's to close.
13. **Do not change the shipped weekly-goal contract's shape.** `WeeklyGoalProgress` (its fields), the
    `WeeklyGoalRepository` protocol, `WeeklyGoalWriteRule`'s two rules, and `WeekMath` are frozen. This plan is
    **additive**: four new `WeeklyGoalKind` cases, seven new `WeeklyGoalParams` fields, two new `weekly_goals`
    columns. Nothing existing is renamed or removed.

---

## File structure

### Created

| File | Responsibility |
|---|---|
| `GymSyncApp/GymSync/Models/BlockGoal.swift` | `GoalMetric`, `GoalTarget`, `GoalPreset`, `GoalOutcome`, `BlockGoal`, `BlockGoalDraft` — the goal model (Task 0.1) |
| `GymSyncApp/GymSync/Models/Ladder.swift` | `RungStatus`, `LadderRung`, `Ladder`, `LadderRow`, `LadderPageModel` — the ladder and its render boundary (Task 0.2) |
| `GymSyncApp/GymSync/Models/BlockGoalRepository.swift` | The repository protocol + `StubBlockGoalRepository`'s fixture ladder (Task 0.4) |
| `GymSyncApp/GymSync/Models/LadderRule.swift` | `LadderConstraints`, the `LadderRule` protocol, the `LadderRules` registry (Task 0.5) |
| `GymSyncApp/GymSync/Models/LadderRules+Ramps.swift` | The ramp rules for the metrics the lifting generator does not prescribe (A7) |
| `GymSyncApp/GymSync/Models/LadderReadout.swift` | Strength / rep-strength / muscle rungs read off `Program.weeks` + prescriptions (A8) |
| `GymSyncApp/GymSync/Models/LadderMath.swift` | Re-laddering, standing, projection, rung → `WeeklyGoal` materialisation (A9, A10) |
| `GymSyncApp/GymSync/Models/BlockGoalMetricMath.swift` | The metric readers: body weight, cumulative volume, benchmark time, reps at load, LISS minutes, stretching count (A5, A6) |
| `GymSyncApp/GymSync/Models/BlockGoalLiveRepository.swift` | `LiveBlockGoalRepository` — Supabase reads/writes for `block_goals` + `block_goal_rungs` (A11) |
| `GymSyncApp/GymSync/Models/GoalBlockLength.swift` | Block length in weeks from the milestone date, and the reach computation + copy (B2, B5) |
| `GymSyncApp/GymSync/Features/Coach/GoalScreenView.swift` | The front door: preset grid + the Pro door (C1) |
| `GymSyncApp/GymSync/Features/Coach/GoalMilestoneView.swift` | One milestone card per preset, its levers, Coach's line, `BUILD MY BLOCK` (C2, C3) |
| `GymSyncApp/GymSync/Features/Coach/LadderPageView.swift` | The ladder page (spec §6) — headline, standing, rungs, levers (D1) |
| `GymSyncApp/GymSync/Features/Coach/LadderCard.swift` | The ladder card `ProgramScheduleView` puts above "Why this block" (D4) |
| `GymSyncApp/GymSync/Features/Coach/GoalFixtures.swift` | Hermetic fixtures for the eight new catalog ids (C5, D7) |
| `supabase/migrations/20260907000001_block_goals.sql` | `block_goals` + `block_goal_rungs`, RLS, `updated_at` trigger (A1) |
| `supabase/migrations/20260907000002_weekly_goals_block_link.sql` | `weekly_goals.goal_id` + `.rung_index`, widened `kind` CHECK (A2) |
| `supabase/tests/block_goals_test.sql` | pgTAP for both new tables (A3) |
| `GymSyncApp/GymSyncTests/BlockGoalModelTests.swift` | `GoalTarget`/`BlockGoal` Codable round trips, camelCase keys (0.1) |
| `GymSyncApp/GymSyncTests/LadderRuleTests.swift` | Every ramp rule, every edge (A7) |
| `GymSyncApp/GymSyncTests/LadderReadoutTests.swift` | Strength/muscle read-out against fixture `Program`s (A8) |
| `GymSyncApp/GymSyncTests/LadderMathTests.swift` | Re-laddering, standing, materialisation (A9, A10) |
| `GymSyncApp/GymSyncTests/BlockGoalMetricMathTests.swift` | The six readers (A5, A6) |
| `GymSyncApp/GymSyncTests/BlockGoalLiveRepositoryTests.swift` | Live-DB round trips, 2099-dated (A11) |
| `GymSyncApp/GymSyncTests/GoalBlockLengthTests.swift` | Weeks-from-date, reach, the copy (B2, B5) |
| `GymSyncApp/GymSyncTests/GoalGeneratorInputTests.swift` | The goal → `Inputs` mapping (B1, B3) |
| `GymSyncApp/GymSyncTests/ProgramBuilderGoalTests.swift` | The builder's goal seam — duration, the week walk (B4) |
| `GymSyncApp/GymSyncTests/WeekBookerUnchangedTests.swift` | `isLadderWeek` and the untouched overwrite rule (B6) |
| `GymSyncApp/GymSync/Features/Coach/GoalFirstBuildFlow.swift` | The one build path: goal screen → milestone → consult → builder → ladder (C4) |
| `GymSyncApp/GymSyncTests/GoalScreenCopyTests.swift` | The preset grid's copy table (C1) |
| `GymSyncApp/GymSyncTests/GoalMilestoneCopyTests.swift` | Coach's line and every preset's draft (C2) |
| `GymSyncApp/GymSyncTests/LadderRowStyleTests.swift` | Status → style, and no red anywhere (D1) |
| `GymSyncApp/GymSyncTests/WeeklyGoalEditorParamsTests.swift` | An override stays attached to its rung (D3) |
| `GymSyncApp/GymSyncTests/LadderCardTests.swift` | The schedule card's three-row window (D4) |
| `GymSyncApp/GymSyncTests/LedgerGoalLineTests.swift` | The ledger's goal line and its outcome (D5) |

### Modified

| File | Change |
|---|---|
| `GymSyncApp/GymSync/Models/WeeklyGoal.swift` | +4 `WeeklyGoalKind` cases, +7 `WeeklyGoalParams` fields (0.3) |
| `GymSyncApp/GymSync/Models/WeeklyGoalProgressMath.swift` | +4 dispatcher arms; `blockKicker(...)` (0.3, A14) |
| `GymSyncApp/GymSync/Models/WeeklyGoalProposalRule.swift` | +4 arms in `isMeaningful` and `sentence` (0.3) |
| `GymSyncApp/GymSync/Models/WeeklyGoalLiveRepository.swift` | +4 arms in `progress(for:)` (0.3); block context on the kicker (A14) |
| `GymSyncApp/GymSync/Features/Home/V2/HomeWeeklyGoalStrip.swift` | +4 arms in `reading(for:)` and `spokenReading(for:)` (0.3) |
| `GymSyncApp/GymSync/Features/Home/WeeklyGoalEditorSheet.swift` | +4 arms in `chipLabel`/`levers`/`incompleteReason`/`params()` (0.3); rung-override mode (D3) |
| `GymSyncApp/GymSync/Models/ProgramGenerator.swift` | `Inputs.goal`; goal-driven focus band, focus exercise, cardio/mobility placement (B1, B3) |
| `GymSyncApp/GymSync/Models/ProgramBuilder.swift` | `build(goal:)` requires a `BlockGoalDraft`; writes the goal + ladder after the enrollment (B4) |
| `GymSyncApp/GymSync/Models/TrainingProfile.swift` | `generatorInputs(goal:…)` passes the goal through (B1) |
| `GymSyncApp/GymSync/Services/HealthKitBridge.swift` | `lissMinutes(from:to:)` and its tags (A6) |
| `GymSyncApp/GymSync/Features/Coach/CoachHomeView.swift` | `BUILD MY PROGRAM` routes to the goal screen; `.wizard` route deleted (C4) |
| `GymSyncApp/GymSync/Features/Coach/ConsultEntryView.swift` | Takes a `BlockGoalDraft`; hands it to `ProgramBuilder.build` (C3) |
| `GymSyncApp/GymSync/Features/Coach/ProgramLedgerView.swift` | The build door routes through the goal screen; the goal/outcome row (C4, D5) |
| `GymSyncApp/GymSync/Features/Coach/BlockCalendarView.swift` | Its build door routes through the goal screen (C4) |
| `GymSyncApp/GymSync/Features/Coach/CoachOfferFlow.swift` | Its build door routes through the goal screen (C4) |
| `GymSyncApp/GymSync/Features/Coach/ProgramScheduleView.swift` | The ladder card, above `reasoningCard` (D4) |
| `GymSyncApp/GymSync/Features/Home/HomeView.swift` | Block context on the strip; tap → ladder page; `coachSentence` rung (a) (D2, D6) |
| `GymSyncApp/GymSync/App/CatalogHostView.swift` | 8 new cases + builders (C5, D7) |
| `GymSyncApp/GymSyncTests/CatalogScreenTests.swift` | 8 new ids (C5, D7) |
| `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` | 8 new capture methods (C5, D7) |
| `docs/design/frame-map.json` | Frames 93–100 (C5, D7) |
| `.github/workflows/ios.yml` | `FLOOR=98` → `FLOOR=106` (I4, and only I4) |
| `scripts/seed_qa_fixtures.js` | A `block_goals` + rungs world for `ci_test_user` (I2) |
| `supabase/tests/weekly_goals_test.sql` | `plan(22)` → `plan(28)`; the new kinds and the two new columns (A4) |
| `GymSyncApp/GymSyncTests/WeeklyGoalModelTests.swift` | Round trips for the four new kinds and seven new params (0.3) |
| `GymSyncApp/GymSyncTests/WeeklyGoalProgressTests.swift` | `blockKicker` (A14) |
| `GymSyncApp/GymSyncTests/HomeCompositionTests.swift` | The strip's destination (D2) and `coachSentence`'s precedence (D6) |
| `GymSyncApp/GymSyncTests/HealthGateTests.swift`, `RuleLeverTests.swift` | Comments that name `CoachWizardView` re-point to `ProgramBuilder` (C4) |

### Deleted

| File | Why |
|---|---|
| `GymSyncApp/GymSync/Features/Coach/CoachWizardView.swift` | **Retired** (C4). Grep-verified: its only call site is `CoachHomeView.swift:116`, inside a `case .wizard:` that nothing ever sets — `route = .wizard` appears nowhere in the repo. It is also a **second program-writing path** that bypasses `ProgramBuilder.build` entirely (`create()` at :1748 writes routines, `:790` enrolls), so leaving it would leave a door that builds a block with no goal. `CoachBuildLanding` (:31) lives in this file and has no other user. Spec §11.3 defers this decision to the plan; the plan decides: **retire**. |

---

## New catalog ids (8) and the FLOOR

| id | frame | title | owner |
|---|---|---|---|
| `goal-screen` | 93 | Goal screen — the presets and the Pro door | Stream C |
| `goal-milestone-strength` | 94 | Milestone card — strength | Stream C |
| `goal-milestone-body-composition` | 95 | Milestone card — body composition | Stream C |
| `goal-milestone-recovery` | 96 | Milestone card — recovery | Stream C |
| `ladder-on-track` | 97 | Ladder page — on track | Stream D |
| `ladder-behind` | 98 | Ladder page — behind, with a proposal | Stream D |
| `ladder-met` | 99 | Ladder page — milestone met | Stream D |
| `home-goal-strip-block` | 100 | Weekly goal strip — the block kicker | Stream D |

`FLOOR` **98 → 106**, bumped once, in integration task **I4**.

Three milestone cards, not eleven, and that is the controller's calibration of the spec: the eleven lever sets
differ by *which steppers* they show, and a capture per stepper set is eleven near-identical frames for a
reviewer to scroll. The three chosen are the three **shapes**: Strength (a picker + a weight stepper + a date,
and the segmented "a max / reps at a load" that carries the eleventh preset), Body composition (a rate-or-target
switch — the only card with two ways to state the same milestone), and Recovery (the one card with **two**
metrics and **no** date). The other eight are one lever-tap apart in a build.

---

## Dependency graph

```
                       ┌──────────────────────────────────────────┐
    origin/master ───► │  Task 0 — THE INTERFACE  (0.1 … 0.5)     │  branch: feat/goal-first-release
       (4ed32d0)       │  5 commits, sequential, one worktree     │
                       └──────────────────┬───────────────────────┘
                                          │  everything below forks from the tip of 0.5
              ┌───────────────┬───────────┴───────────┬────────────────┐
              ▼               ▼                       ▼                ▼
      ┌───────────────┐ ┌───────────────┐   ┌──────────────────┐ ┌──────────────┐
      │ STREAM A      │ │ STREAM B      │   │ STREAM C         │ │ STREAM D     │
      │ data + ladder │ │ the generator │   │ the door         │ │ ladder page  │
      │ math          │ │               │   │                  │ │ + Home       │
      │ A1 … A14      │ │ B1 … B6       │   │ C1 … C5          │ │ D1 … D7      │
      │ wt-goal-data  │ │ wt-goal-gen   │   │ wt-goal-door     │ │ wt-goal-ui   │
      └───────┬───────┘ └───────┬───────┘   └────────┬─────────┘ └──────┬───────┘
              └─────────────────┴────────────────────┴──────────────────┘
                                          ▼
                       ┌──────────────────────────────────────────┐
                       │  INTEGRATION  I1 … I6                    │
                       │  (feat/goal-first-release) → ONE PR       │
                       └──────────────────────────────────────────┘
```

**Cross-stream edges — the only ones that exist:**

| Edge | Why it is not a blocker |
|---|---|
| C and D need real goals and ladders | Task **0.4** ships `BlockGoalRepository` as a protocol with `StubBlockGoalRepository`, whose fixture ladder is the design's own bench-225 block. C and D wire to the protocol. A ships `LiveBlockGoalRepository`; **I1** swaps the binding. |
| C needs the builder to take a goal | Task **0.1** ships `BlockGoalDraft`. C composes one and calls `ProgramBuilder.build(profile:answers:catalog:userID:goal:)`; B makes that parameter required and load-bearing. Until B lands, C's call compiles against the parameter's default (`nil`) — **and B's first act (B4) removes the default**, so a C call site that forgot it fails at integration rather than shipping goal-less. |
| D needs the strip to render four new kinds | Task **0.3** lands the four kinds with every exhaustive switch closed and the subject-chip contract honoured, so Home compiles and renders from 0.3 onward. |
| D needs the block kicker | **A14** ships `WeeklyGoalProgressMath.blockKicker(...)`; until it lands, D2 renders `progress.kicker` exactly as today. The swap is one line in **I1**. |
| A needs the ladder types | Task 0.2. A never edits them. |
| C and D both touch `CatalogHostView` / `CatalogScreenTests` / `ScreenshotTests` / `frame-map.json` | Append-only lists. Resolve in **I1** by concatenating in frame order; do not renumber. |

Streams A, B, C, D touch disjoint file sets except those four catalog files and `ProgramLedgerView.swift`
(C4 rewires its build door, D5 adds its outcome row — different functions, one file; **C lands before D** at
integration for that reason).

---

# Task 0 — THE INTERFACE

Branch `feat/goal-first-release`, forked from `origin/master` (`4ed32d0` or later). Five commits.
**Nothing forks until 0.5 is pushed.**

### 0.1 — the goal model — **M**

**File (new):** `GymSyncApp/GymSync/Models/BlockGoal.swift`

Write exactly this. `BlockGoal`'s stored properties are spec §2.1 verbatim, plus the two outcome columns §8's
DDL carries (phase 3 writes them; the ledger row in D5 reads them, and a DTO that cannot decode a column the
table has is a decode failure waiting for the first phase-3 row).

```swift
import Foundation

// MARK: - BlockGoal
//
// Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md
// §2. Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// task 0.1.
//
// ONE PRIMARY GOAL PER BLOCK (owner decision 2). The goal and the program are
// one object at two time scales: this type is the block's whole time scale,
// and `WeeklyGoal` — already shipped — is the week's.
//
// THE REGISTRY IS OPEN BY DESIGN (owner decision 5): a new goal is a new
// `GoalMetric` case plus a reader plus a ladder rule, and the door does not
// change.

/// What a goal measures. The raw values are `block_goals.metric`'s registry
/// keys, so the enum and the column cannot drift apart silently — the same
/// contract `WeeklyGoalKind` has with `weekly_goals.kind`.
///
/// The metric's PARAMETERS (which lift, which group, which routine) do not
/// live here: they live in `GoalTarget`, beside the number they qualify,
/// exactly as `WeeklyGoalParams` carries `exerciseID` beside
/// `targetWeightLbs`. An enum with associated values would put the same
/// discriminator in two places — the `metric` column and the payload's own
/// tag — with nothing keeping them honest.
enum GoalMetric: String, Codable, CaseIterable, Sendable {
    case liftOneRepMax              = "lift_one_rep_max"
    case weeklyMuscleSets           = "weekly_muscle_sets"
    case weeklyDistance             = "weekly_distance"
    case trainingDaysPerWeek        = "training_days_per_week"
    case sessionsOfTypePerWeek      = "sessions_of_type_per_week"
    case lissMinutesPerWeek         = "liss_minutes_per_week"
    case stretchingExercisesPerWeek = "stretching_exercises_per_week"
    case bodyWeight                 = "body_weight"
    case cumulativeVolume           = "cumulative_volume"
    case benchmarkTime              = "benchmark_time"
    case liftRepsAtLoad             = "lift_reps_at_load"
}

/// A target, typed per metric — the milestone's value, and a rung's value,
/// in one shape.
///
/// ONE payload type with per-metric optional fields, for the reason
/// `WeeklyGoalParams`' own doc comment gives. Every field encodes only when
/// set (the synthesized encoder uses `encodeIfPresent`), so a `days` goal's
/// target is `{"days":4}` rather than fifteen nulls and a number.
///
/// CAMELCASE ON THE WIRE, and no `keyEncodingStrategy` anywhere in this app —
/// `20260906000001_weekly_goals.sql:35-40` states the same contract for
/// `weekly_goals.params`, and `block_goals.target` inherits it.
///
/// CANONICAL POUNDS for every weight (`Models/Units.swift:7-12`). The unit a
/// number is READ in is the athlete's; the unit it is STORED in is pounds.
struct GoalTarget: Codable, Equatable, Sendable {
    // liftOneRepMax, liftRepsAtLoad
    var exerciseID: UUID? = nil
    var targetWeightLbs: Decimal? = nil     // CANONICAL POUNDS
    var targetReps: Int? = nil
    var loadLbs: Decimal? = nil             // liftRepsAtLoad: the fixed load
    // weeklyMuscleSets — a map, because Maintenance is EVERY major group
    // (owner decision 9) and Muscle is one of them.
    var muscleTargets: [String: Int]? = nil // MuscleGroup.rawValue -> weekly sets
    // weeklyDistance
    var activity: String? = nil             // run | bike | row | walk
    var distance: Double? = nil             // in the athlete's unit (mi with lb, km with kg)
    // trainingDaysPerWeek
    var days: Int? = nil
    // sessionsOfTypePerWeek
    var sessionType: String? = nil          // hiit | mobility | cardio | class
    var sessions: Int? = nil
    // lissMinutesPerWeek, stretchingExercisesPerWeek (Recovery carries both)
    var lissMinutes: Int? = nil
    var stretchingExercises: Int? = nil
    // bodyWeight
    var bodyWeightLbs: Decimal? = nil       // CANONICAL POUNDS
    var bodyWeightRatePercent: Double? = nil // per week, signed: -0.75 = lose 0.75 %/wk
    // cumulativeVolume
    var volumeLbs: Double? = nil
    // benchmarkTime
    var routineID: UUID? = nil
    var targetSeconds: Int? = nil
}

/// The named, ready-made goals over the registry (spec §2.3). ALL FREE, all
/// offered from launch (owner decision 10).
///
/// ELEVEN presets, TEN tiles. `repStrength` is the eleventh preset and the
/// spec is explicit that it is NOT an eleventh tile (§2.3: "Rep strength
/// appears as a second lever on the Strength card — 'a max' or 'reps at a
/// load' — not as an eighth tile"), so the grid renders ten and the Strength
/// milestone card carries this case behind its own segmented switch.
enum GoalPreset: String, Codable, CaseIterable, Sendable {
    case strength
    case repStrength      = "rep_strength"
    case muscle
    case endurance
    case consistency
    case conditioning
    case maintenance
    case recovery
    case bodyComposition  = "body_composition"
    case volume
    case benchmark

    /// The metric this preset measures. Recovery's PRIMARY metric is the
    /// stretching count — what the block actually schedules; LISS minutes is
    /// its companion read on the same rung (spec §2.3's note).
    var metric: GoalMetric {
        switch self {
        case .strength:        return .liftOneRepMax
        case .repStrength:     return .liftRepsAtLoad
        case .muscle:          return .weeklyMuscleSets
        case .endurance:       return .weeklyDistance
        case .consistency:     return .trainingDaysPerWeek
        case .conditioning:    return .sessionsOfTypePerWeek
        case .maintenance:     return .weeklyMuscleSets
        case .recovery:        return .stretchingExercisesPerWeek
        case .bodyComposition: return .bodyWeight
        case .volume:          return .cumulativeVolume
        case .benchmark:       return .benchmarkTime
        }
    }

    /// Does the door ask for a date? Maintenance and Recovery do not — they
    /// are "held for the block" (spec §2.1: `byDate == nil`), and asking for
    /// one would invent a deadline for a goal that has none.
    var asksForDate: Bool {
        switch self {
        case .maintenance, .recovery, .consistency: return false
        default:                                    return true
        }
    }

    /// The ten tiles the grid renders, in the spec §2.3 table's order.
    /// `repStrength` is absent on purpose — see the type's doc comment.
    static let tiles: [GoalPreset] = [
        .strength, .muscle, .endurance, .consistency, .conditioning,
        .maintenance, .recovery, .bodyComposition, .volume, .benchmark,
    ]
}

/// How a finished block's milestone came out (spec §7). PHASE 3 WRITES THESE
/// — the column exists now because the table does, and `ProgramLedgerView`
/// (task D5) renders the outcome when it is present and the milestone alone
/// when it is not.
enum GoalOutcome: String, Codable, Equatable, Sendable {
    case met, missed, partial
}

/// A row of `public.block_goals` — spec §2.1, verbatim, plus §8's two
/// outcome columns.
struct BlockGoal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let enrollmentID: UUID            // the block this goal drives (program_enrollments.id)
    var metric: GoalMetric            // what is measured (registry, §2.2)
    var target: GoalTarget            // the milestone value, typed per metric
    var byDate: Date?                 // the milestone date; nil = "held for the block"
    var preset: GoalPreset?           // which preset produced it; nil = Coach-guided or custom
    var source: WeeklyGoalSource      // coach | user — who last set the milestone
    var outcome: GoalOutcome?         // phase 3
    var outcomeValue: GoalTarget?     // phase 3
    let createdAt: Date
    var updatedAt: Date
}

/// A goal BEFORE its block exists.
///
/// `BlockGoal.enrollmentID` is `let` and non-optional because a goal without
/// a block is not a goal — but the door composes the goal FIRST and
/// `ProgramBuilder.build` writes the enrollment SECOND, so there is a real
/// moment with a milestone and no id to hang it on. This is that moment, and
/// making it its own type is what keeps `enrollmentID` honest instead of
/// optional forever after.
struct BlockGoalDraft: Equatable, Sendable {
    var metric: GoalMetric
    var target: GoalTarget
    var byDate: Date?
    var preset: GoalPreset?
    /// The door is the athlete choosing, so a drafted goal is theirs — which
    /// is also what makes `WeeklyGoalWriteRule` protect the rungs it
    /// materialises from being overwritten by a later detection.
    var source: WeeklyGoalSource = .user
}

extension BlockGoal {
    /// The draft, once the block it drives has an id.
    init(draft: BlockGoalDraft, id: UUID = UUID(), userID: UUID,
         enrollmentID: UUID, now: Date = .now) {
        self.init(id: id, userID: userID, enrollmentID: enrollmentID,
                  metric: draft.metric, target: draft.target,
                  byDate: draft.byDate, preset: draft.preset,
                  source: draft.source, outcome: nil, outcomeValue: nil,
                  createdAt: now, updatedAt: now)
    }
}
```

**Interfaces** — *consumes:* `WeeklyGoalSource` (`Models/WeeklyGoal.swift:32`), `MuscleGroup.rawValue`
(`Models/MuscleGroup.swift:35`). *Produces:* every type above; all four streams read them.

**TDD steps.**

1. Write the failing test first — `GymSyncApp/GymSyncTests/BlockGoalModelTests.swift`:

```swift
import XCTest
@testable import GymSync

/// The goal model's wire contract. `block_goals.target` is jsonb with
/// CAMELCASE keys and no `keyEncodingStrategy` (global constraint 11), and
/// absent fields must be ABSENT rather than null — the same round trip
/// `WeeklyGoalModelTests` proves for `weekly_goals.params`.
final class BlockGoalModelTests: XCTestCase {

    private func json(_ target: GoalTarget) throws -> [String: Any] {
        let data = try JSONEncoder().encode(target)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTargetEncodesOnlyTheFieldsAMetricUses() throws {
        let days = try json(GoalTarget(days: 4))
        XCTAssertEqual(days.keys.sorted(), ["days"])

        let lift = try json(GoalTarget(exerciseID: UUID(), targetWeightLbs: 225))
        XCTAssertEqual(lift.keys.sorted(), ["exerciseID", "targetWeightLbs"])

        let recovery = try json(GoalTarget(lissMinutes: 120, stretchingExercises: 6))
        XCTAssertEqual(recovery.keys.sorted(), ["lissMinutes", "stretchingExercises"])
    }

    func testTargetRoundTripsEveryField() throws {
        let full = GoalTarget(
            exerciseID: UUID(), targetWeightLbs: 225, targetReps: 10, loadLbs: 225,
            muscleTargets: ["chest": 12, "back": 12], activity: "run", distance: 15,
            days: 4, sessionType: "hiit", sessions: 3, lissMinutes: 120,
            stretchingExercises: 6, bodyWeightLbs: 180, bodyWeightRatePercent: -0.75,
            volumeLbs: 100_000, routineID: UUID(), targetSeconds: 2700)
        let data = try JSONEncoder().encode(full)
        XCTAssertEqual(try JSONDecoder().decode(GoalTarget.self, from: data), full)
    }

    func testEveryMetricKeyIsSnakeCaseAndUnique() {
        let keys = GoalMetric.allCases.map(\.rawValue)
        XCTAssertEqual(keys.count, Set(keys).count, "duplicate registry key")
        for key in keys {
            XCTAssertEqual(key, key.lowercased(), "registry keys are lowercase: \(key)")
            XCTAssertFalse(key.contains(" "), "registry keys have no spaces: \(key)")
        }
    }

    func testEveryPresetHasAMetricAndTenTilesAreOffered() {
        XCTAssertEqual(GoalPreset.allCases.count, 11)
        XCTAssertEqual(GoalPreset.tiles.count, 10)
        XCTAssertFalse(GoalPreset.tiles.contains(.repStrength),
                       "rep strength is Strength's second lever, not a tile (spec §2.3)")
        XCTAssertEqual(GoalPreset.strength.metric, .liftOneRepMax)
        XCTAssertEqual(GoalPreset.maintenance.metric, .weeklyMuscleSets)
        XCTAssertEqual(GoalPreset.recovery.metric, .stretchingExercisesPerWeek)
        XCTAssertFalse(GoalPreset.maintenance.asksForDate)
        XCTAssertFalse(GoalPreset.recovery.asksForDate)
        XCTAssertTrue(GoalPreset.strength.asksForDate)
    }

    func testDraftBecomesAGoalWithItsEnrollment() {
        let userID = UUID()
        let enrollmentID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let draft = BlockGoalDraft(metric: .liftOneRepMax,
                                   target: GoalTarget(targetWeightLbs: 225),
                                   byDate: now, preset: .strength)
        let goal = BlockGoal(draft: draft, userID: userID,
                             enrollmentID: enrollmentID, now: now)
        XCTAssertEqual(goal.enrollmentID, enrollmentID)
        XCTAssertEqual(goal.source, .user, "the door is the athlete choosing")
        XCTAssertEqual(goal.createdAt, now)
        XCTAssertEqual(goal.updatedAt, now)
        XCTAssertNil(goal.outcome)
    }
}
```

2. Push; CI fails to compile (`BlockGoal.swift` does not exist).
3. Add `Models/BlockGoal.swift` exactly as written above.
4. Push; `BlockGoalModelTests` green.
5. Commit: `feat(goal): the block goal model — metric registry, typed target, eleven presets` + the trailer.

### 0.2 — the ladder — **S**

**File (new):** `GymSyncApp/GymSync/Models/Ladder.swift`

`LadderRung` and `Ladder` are spec §3.1 verbatim. `LadderRow` and `LadderPageModel` are the **render
boundary** — the same posture `WeeklyGoalProgress` takes: the numbers arrive resolved so no view does
arithmetic, and Stream D can build the page against the stub while Stream A builds the derivation.

```swift
import Foundation

// MARK: - Ladder
//
// Spec §3. THE LADDER IS A READ-OUT of the generated block projected onto
// the goal's metric — not a second schedule. `ProgramGenerator` already
// produces `Program.weeks` (volumeMultiplier / intensityMultiplier /
// isDeload) and per-slot prescriptions (sets, repsLow/High, percentOfMax,
// RIR); the rungs are computed FROM those, which is what makes it impossible
// for the ladder and the plan to disagree.

enum RungStatus: String, Codable, Equatable, Sendable {
    case ahead, current, met, missed, overridden
}

struct LadderRung: Codable, Equatable, Sendable {
    let weekIndex: Int            // 0-based within the block
    let weekStartString: String   // WeekMath's device-calendar week key, same as weekly_goals
    var target: GoalTarget        // this week's subgoal, typed per metric
    var status: RungStatus        // ahead | current | met | missed | overridden
}

struct Ladder: Codable, Equatable, Sendable {
    let goalID: UUID
    var rungs: [LadderRung]       // exactly enrollment.weeks entries
    var derivedAt: Date
}

/// One row of the ladder page, already worded.
///
/// The page prints strings; it does not read a `GoalTarget` and decide how a
/// bench rung is spelled. That decision is `LadderReadout`'s (task A8) and
/// the ramp rules' (A7), which is what keeps "3 × 5 at 190" identical on the
/// ladder page, on the schedule card and in Coach's line.
struct LadderRow: Equatable, Sendable {
    let weekNumber: Int          // 1-based, what the page prints
    let weekStartString: String
    let targetText: String       // "3 × 5 at 190" · "12 chest sets" · "120 LISS min · 6 stretches"
    /// The second line, when a rung implies something the target text does
    /// not say — a strength rung's e1RM ("≈ 214 e1RM"). nil when there is
    /// none; never an empty string, so a view can branch on presence.
    let implication: String?
    let status: RungStatus
    let isDeload: Bool
    /// The generator's own decision-log line for this week, when one names
    /// it (`Program.notes`) — spec §6: "so the ladder says why a week is
    /// what it is". nil is the normal case.
    let note: String?
}

/// Everything the ladder page renders, resolved.
struct LadderPageModel: Equatable, Sendable {
    /// The milestone as the headline — "Bench 225 by Oct 18".
    var headline: String = ""
    /// The date on its own line, or "" for a held-for-the-block goal.
    var dateLine: String = ""
    /// Coach's one line on standing — "On track" /
    /// "This ladder reaches 218 — move the date?" (spec §6).
    var coachLine: String = ""
    var rows: [LadderRow] = []
    /// False when the re-derived ladder can no longer reach the milestone by
    /// the date. The page shows the gap honestly either way (spec §3.5); this
    /// only decides whether Coach's line is a proposal.
    var reachesMilestone: Bool = true
    /// 1-based, for the strip's block kicker and the page's own subtitle.
    var weekNumber: Int = 1
    var weekCount: Int = 1
    /// Whose milestone this is, for the kicker's COACH'S GOAL / YOUR GOAL.
    var source: WeeklyGoalSource = .coach
}
```

**Interfaces** — *consumes:* `GoalTarget`, `WeeklyGoalSource`. *Produces:* `RungStatus`, `LadderRung`,
`Ladder`, `LadderRow`, `LadderPageModel`.

**TDD steps.**

1. No behaviour, so no unit test of its own: these are value types with synthesized conformances, and
   `LadderMathTests` (A9) and `LadderRuleTests` (A7) are what exercise them. Adding an assertion that
   `Ladder` round-trips through `JSONEncoder` would test the standard library.
2. Add `Models/Ladder.swift` exactly as written above.
3. Push; the target compiles (nothing consumes these yet).
4. Commit: `feat(goal): the ladder — rungs, statuses, and the page's render boundary` + the trailer.

### 0.3 — the four new weekly-goal kinds, landed CLOSED — **L**

**Files:** `Models/WeeklyGoal.swift`, `Models/WeeklyGoalProgressMath.swift`,
`Models/WeeklyGoalProposalRule.swift`, `Models/WeeklyGoalLiveRepository.swift`,
`Features/Home/V2/HomeWeeklyGoalStrip.swift`, `Features/Home/WeeklyGoalEditorSheet.swift`.

**This is the task that would otherwise break three streams at once.** There are **nine exhaustive switches
over `WeeklyGoalKind` with no `default:` arm** — deliberately, so a new kind is a compile error rather than a
blank strip (`HomeWeeklyGoalStrip.swift:102-105` says exactly that). Adding four cases therefore breaks the
build until every one of them is closed. They are, grep-verified at `origin/master`:

| # | site | file:line |
|---|---|---|
| 1 | `HomeWeeklyGoalStrip.reading(for:)` | `HomeWeeklyGoalStrip.swift:131` |
| 2 | `HomeWeeklyGoalStrip.spokenReading(for:)` | `HomeWeeklyGoalStrip.swift:688` |
| 3 | `WeeklyGoalEditorSheet.chipLabel(_:unit:)` | `WeeklyGoalEditorSheet.swift:310` |
| 4 | `WeeklyGoalEditorSheet.levers` | `WeeklyGoalEditorSheet.swift:353` |
| 5 | `WeeklyGoalEditorSheet.incompleteReason` | `WeeklyGoalEditorSheet.swift:717` |
| 6 | `WeeklyGoalEditorSheet.params()` | `WeeklyGoalEditorSheet.swift:881` (its `switch` at :883) |
| 7 | `WeeklyGoalProgressMath.progress(goal:…)` | the dispatcher, `WeeklyGoalProgressMath.swift` §"A4: the dispatcher" |
| 8 | `LiveWeeklyGoalRepository.progress(for:)` | `WeeklyGoalLiveRepository.swift:352` |
| 9 | `WeeklyGoalProposalRule.isMeaningful` **and** `.sentence` | `WeeklyGoalProposalRule.swift:57`, `:93` |

**The additions** — in `Models/WeeklyGoal.swift`, appended to the existing declarations, nothing renamed:

```swift
enum WeeklyGoalKind: String, Codable, CaseIterable, Sendable {
    case muscleSets = "muscle_sets"
    case distance
    case sessionsOfType = "sessions_of_type"
    case days
    case lift
    // Goal-first programming phase 1 (spec §4's mapping table). Additive:
    // every one of these is a rung a block goal materialises into, and a
    // standalone weekly goal may still be any of the five above.
    case recovery
    case bodyWeight = "body_weight"
    case volume
    case benchmark
}
```

```swift
struct WeeklyGoalParams: Codable, Equatable, Sendable {
    var muscleTargets: [String: Int]? = nil
    var targetSource: String? = nil
    var activity: String? = nil
    var distanceTarget: Double? = nil
    var sessionType: String? = nil
    var count: Int? = nil
    var exerciseID: UUID? = nil
    var targetWeightLbs: Decimal? = nil
    var byDate: Date? = nil
    // ── goal-first programming phase 1 (spec §4) ──────────────────────────
    /// `recovery`: the companion read beside the stretching count. Recovery
    /// is the one goal with two metrics and it is still ONE goal — `count`
    /// is the primary (stretching exercises), this is what rides with it.
    var lissMinutes: Int? = nil
    /// `bodyWeight`: CANONICAL POUNDS, like every other weight in this app.
    var bodyWeightLbs: Decimal? = nil
    /// `volume`: the week's tonnage rung, in pounds.
    var volumeLbs: Double? = nil
    /// `benchmark`: the named routine and the time to beat.
    var routineID: UUID? = nil
    var targetSeconds: Int? = nil
    /// `lift` when the goal is REPS AT A LOAD rather than a max
    /// (`liftRepsAtLoad`): `targetWeightLbs` is then the fixed load and this
    /// is the rep target. Absent for an ordinary lift goal, which is what
    /// tells the strip which of the two readings to draw.
    var targetReps: Int? = nil
    /// The `block_goals` row whose ladder materialised this week
    /// (`weekly_goals.goal_id`). nil = a standalone weekly goal, exactly as
    /// today — spec §4: "a row with goal_id = null is a standalone weekly
    /// goal exactly as today".
    var goalID: UUID? = nil
}
```

> `goalID` lives in `params` **and** in a `goal_id` column (task A2). That is not a mirror by accident: the
> COLUMN is what the foreign key, the `ON DELETE SET NULL` and any future join need, and the PARAM is what
> survives a round trip through `WeeklyGoal` — which is not `Codable` and has no column-backed field for it.
> `LiveWeeklyGoalRepository`'s row DTO writes both from the same value (A11), and the pgTAP in A4 asserts they
> agree.

**The nine arms.** Each kind renders through the shipped **subject-chip contract**: one chip named for the
subject, `done`/`target` on the meter (`HomeWeeklyGoalStrip`'s "The subject chip" section, and
`distanceProgress`/`sessionsOfTypeProgress`'s own comments). So the four new readings are the *existing*
full-width meter with a different subject and a different unit — no new geometry:

| kind | subject chip | reading | editor chip | levers |
|---|---|---|---|---|
| `recovery` | `STRETCHES` (`done`/`target` = exercises) | `4 / 6 stretches` with `120 / 150 LISS min` under it | `RECOVERY` | stretch-count stepper + LISS-minutes stepper |
| `bodyWeight` | `WEIGHT` | `183 → 178 lb` with the arrow, meter from the block's start weight | `BODY WEIGHT` | weight stepper in the athlete's unit |
| `volume` | `VOLUME` | `62,400 / 100,000 lb`, tabular | `VOLUME` | tonnage stepper (2,500 lb steps) |
| `benchmark` | the routine's name | `47:10 → 45:00`, lower is better | `BENCHMARK` | routine picker + a minutes:seconds stepper |

`incompleteReason` gains: `recovery` → nil (both steppers are bounded away from zero); `bodyWeight` → nil;
`volume` → nil; `benchmark` → `"Pick the routine this goal is about."` when `routineID == nil`.
`WeeklyGoalProposalRule.isMeaningful` gains one grouped arm — `case .recovery, .bodyWeight, .volume, .benchmark: return false` — with the comment the existing `days`/`sessionsOfType` arm carries: these four are
only ever proposed as *a different kind entirely*, because every number in them is one the athlete stated. And
`.sentence` gains four one-line sentences, in Coach's voice (rule 7):

- `recovery` → `"Coach suggests \(count) stretching sessions and \(minutes) easy minutes this week."`
- `bodyWeight` → `"Coach suggests a body-weight target of \(weight) \(unit.label) this week."`
- `volume` → `"Coach suggests \(tonnage) \(unit.label) moved this week."`
- `benchmark` → `"Coach suggests putting this week behind one benchmark."`

**Interfaces** — *consumes:* `WeeklyGoalKind`, `WeeklyGoalParams`, `WeeklyGoalProgress`. *Produces:* the same
types, widened. Streams B, C and D compile against the widened enum from this commit.

**TDD steps.**

1. Extend `GymSyncApp/GymSyncTests/WeeklyGoalModelTests.swift` with the failing round trips:

```swift
    func testNewKindsRoundTripThroughTheirOwnParamsOnly() throws {
        let cases: [(WeeklyGoalKind, WeeklyGoalParams, [String])] = [
            (.recovery, WeeklyGoalParams(count: 6, lissMinutes: 120),
             ["count", "lissMinutes"]),
            (.bodyWeight, WeeklyGoalParams(bodyWeightLbs: 178),
             ["bodyWeightLbs"]),
            (.volume, WeeklyGoalParams(volumeLbs: 100_000),
             ["volumeLbs"]),
            (.benchmark, WeeklyGoalParams(routineID: UUID(), targetSeconds: 2700),
             ["routineID", "targetSeconds"]),
        ]
        for (kind, params, expected) in cases {
            let data = try JSONEncoder().encode(params)
            let object = try XCTUnwrap(
                JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(object.keys.sorted(), expected.sorted(),
                           "\(kind.rawValue) writes only its own keys")
            XCTAssertEqual(try JSONDecoder().decode(WeeklyGoalParams.self, from: data),
                           params)
        }
    }

    func testEveryKindHasADistinctColumnSpelling() {
        let raws = WeeklyGoalKind.allCases.map(\.rawValue)
        XCTAssertEqual(raws.count, 9)
        XCTAssertEqual(raws.count, Set(raws).count)
        XCTAssertTrue(raws.contains("body_weight"))
    }
```

2. Push; CI fails to compile (`.recovery` does not exist), then fails again on the nine switches.
3. Land the enum cases, the seven params fields, and all nine switch arms in this one commit.
4. Push; `GymSyncTests` green, and `app-tab-home` / `app-home-goal-strip-*` unchanged — the four new arms are
   unreachable from every existing fixture.
5. Commit: `feat(goal): four new weekly-goal kinds — recovery, body weight, volume, benchmark` + the trailer.

### 0.4 — `BlockGoalRepository` and its stub — **M**

**File (new):** `GymSyncApp/GymSync/Models/BlockGoalRepository.swift`

```swift
import Foundation

// MARK: - The block goal's repository surface
//
// Plan task 0.4. THIS IS THE INTERFACE STREAMS C AND D FORK AGAINST. Stream
// A ships `LiveBlockGoalRepository` behind the same protocol and integration
// task I1 swaps the binding; until then `StubBlockGoalRepository` is what
// everything sees — deterministic, no network, no clock — so the door and the
// ladder page are correct and capturable at every point in the build rather
// than only at the end.

/// Reads and writes the block's goal and its ladder.
///
/// `async` with no `throws`, matching `WeeklyGoalRepository`: every read on
/// these surfaces is best-effort, and a network blip must render the page's
/// empty state rather than an error dialog.
protocol BlockGoalRepository: Sendable {
    /// The goal driving the active enrollment, or nil when there is no block
    /// or the block predates goals.
    func activeGoal() async -> BlockGoal?
    /// The persisted rungs for a goal.
    func ladder(goalID: UUID) async -> Ladder?
    /// Everything the ladder page renders, already worded (task A12).
    func page(goalID: UUID) async -> LadderPageModel?
    /// The athlete editing their own milestone or date. Always stamps
    /// `source = .user`, for the same reason `WeeklyGoalRepository.save`
    /// does: the milestone and its date belong to the athlete (owner
    /// decision 8), and Coach may only propose against a `user` row.
    @discardableResult func save(_ goal: BlockGoal) async -> Bool
    /// LET COACH RE-LADDER: re-derive the remaining rungs from actuals and
    /// persist them. Rewrites only rungs whose status is `ahead` or
    /// `current` (spec §8), so a missed or overridden week stays visible.
    func reLadder(goalID: UUID) async -> Ladder?
    /// Write this week's rung into `weekly_goals` as the current weekly goal
    /// (spec §4). Returns the row now in effect — which may be the athlete's
    /// own, because this consults `WeeklyGoalWriteRule` exactly as every
    /// other Coach write does.
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal?
}

// MARK: - The stub

/// The shipping default until Stream A's `LiveBlockGoalRepository` lands
/// (integration task I1).
///
/// HERMETIC: no `AppState`, no repository, no `Date.now`. The fixture is the
/// spec's own worked example — bench 225 by Oct 18, an eight-week block,
/// currently week 3 — so the ladder page's captures, the door's captures and
/// the design's prose all describe one block.
struct StubBlockGoalRepository: BlockGoalRepository {

    /// Fixed ids, so nothing in a screenshot diff moves between runs.
    static let fixtureUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b1") ?? UUID()
    static let fixtureGoalID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b2") ?? UUID()
    static let fixtureEnrollmentID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b3") ?? UUID()
    static let fixtureExerciseID = UUID(uuidString: "00000000-0000-0000-0000-0000000000b4") ?? UUID()

    /// 2026-08-24T12:00:00Z — the block's start. A fixture, not a clock.
    static let fixtureCreatedAt = Date(timeIntervalSince1970: 1_787_745_600)
    /// 2026-10-18T12:00:00Z — the milestone date the spec names.
    static let fixtureByDate = Date(timeIntervalSince1970: 1_792_411_200)

    static let fixtureGoal = BlockGoal(
        id: fixtureGoalID, userID: fixtureUserID, enrollmentID: fixtureEnrollmentID,
        metric: .liftOneRepMax,
        target: GoalTarget(exerciseID: fixtureExerciseID, targetWeightLbs: 225),
        byDate: fixtureByDate, preset: .strength, source: .user,
        outcome: nil, outcomeValue: nil,
        createdAt: fixtureCreatedAt, updatedAt: fixtureCreatedAt)

    /// Eight rungs off the block's own prescribed loading, with the wave's
    /// deload at week 6 (`ProgramGenerator`'s ¾-mark rule for an 8-week
    /// block) — the ladder shows the deload as what it is (spec §3.2), it
    /// does not smooth it away.
    static let fixtureLadder = Ladder(
        goalID: fixtureGoalID,
        rungs: [
            .init(weekIndex: 0, weekStartString: "2026-08-23",
                  target: GoalTarget(targetWeightLbs: 190), status: .met),
            .init(weekIndex: 1, weekStartString: "2026-08-30",
                  target: GoalTarget(targetWeightLbs: 195), status: .met),
            .init(weekIndex: 2, weekStartString: "2026-09-06",
                  target: GoalTarget(targetWeightLbs: 200), status: .current),
            .init(weekIndex: 3, weekStartString: "2026-09-13",
                  target: GoalTarget(targetWeightLbs: 205), status: .ahead),
            .init(weekIndex: 4, weekStartString: "2026-09-20",
                  target: GoalTarget(targetWeightLbs: 210), status: .ahead),
            .init(weekIndex: 5, weekStartString: "2026-09-27",
                  target: GoalTarget(targetWeightLbs: 175), status: .ahead),
            .init(weekIndex: 6, weekStartString: "2026-10-04",
                  target: GoalTarget(targetWeightLbs: 220), status: .ahead),
            .init(weekIndex: 7, weekStartString: "2026-10-11",
                  target: GoalTarget(targetWeightLbs: 225), status: .ahead),
        ],
        derivedAt: fixtureCreatedAt)

    /// The page as the spec words it (§6): the milestone as the headline,
    /// the date, Coach's one line on standing.
    static let fixturePage = LadderPageModel(
        headline: "Bench 225 by Oct 18",
        dateLine: "Sunday 18 October",
        coachLine: "On track",
        rows: [
            .init(weekNumber: 1, weekStartString: "2026-08-23", targetText: "3 × 5 at 190",
                  implication: "≈ 214 e1RM", status: .met, isDeload: false, note: nil),
            .init(weekNumber: 2, weekStartString: "2026-08-30", targetText: "3 × 5 at 195",
                  implication: "≈ 219 e1RM", status: .met, isDeload: false, note: nil),
            .init(weekNumber: 3, weekStartString: "2026-09-06", targetText: "3 × 5 at 200",
                  implication: "≈ 225 e1RM", status: .current, isDeload: false, note: nil),
            .init(weekNumber: 4, weekStartString: "2026-09-13", targetText: "4 × 3 at 205",
                  implication: "≈ 223 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 5, weekStartString: "2026-09-20", targetText: "4 × 3 at 210",
                  implication: "≈ 228 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 6, weekStartString: "2026-09-27", targetText: "2 × 5 at 175",
                  implication: nil, status: .ahead, isDeload: true,
                  note: "Deload — move fast, leave fresh."),
            .init(weekNumber: 7, weekStartString: "2026-10-04", targetText: "3 × 2 at 220",
                  implication: "≈ 232 e1RM", status: .ahead, isDeload: false, note: nil),
            .init(weekNumber: 8, weekStartString: "2026-10-11", targetText: "2 × 1 at 225",
                  implication: "≈ 232 e1RM", status: .ahead, isDeload: false, note: nil),
        ],
        reachesMilestone: true, weekNumber: 3, weekCount: 8, source: .user)

    func activeGoal() async -> BlockGoal? { Self.fixtureGoal }
    func ladder(goalID: UUID) async -> Ladder? { Self.fixtureLadder }
    func page(goalID: UUID) async -> LadderPageModel? { Self.fixturePage }

    /// The stub stores nothing — a save "succeeds" so the page's happy path
    /// is walkable and the next read still returns the fixture.
    @discardableResult func save(_ goal: BlockGoal) async -> Bool { true }
    func reLadder(goalID: UUID) async -> Ladder? { Self.fixtureLadder }
    @discardableResult
    func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? { nil }
}
```

**Interfaces** — *consumes:* `BlockGoal`, `Ladder`, `LadderPageModel`, `WeeklyGoal`, `WeeklyGoalWriteRule`.
*Produces:* `protocol BlockGoalRepository`, `StubBlockGoalRepository` + its five `static let` fixtures, which
C5 and D7's catalog builders read.

**TDD steps.**

1. Failing test — append to `BlockGoalModelTests.swift`:

```swift
    func testTheStubIsHermeticAndConsistent() async {
        let repository = StubBlockGoalRepository()
        let goal = await repository.activeGoal()
        let ladder = await repository.ladder(goalID: StubBlockGoalRepository.fixtureGoalID)
        let page = await repository.page(goalID: StubBlockGoalRepository.fixtureGoalID)

        XCTAssertEqual(goal?.id, StubBlockGoalRepository.fixtureGoalID)
        XCTAssertEqual(ladder?.rungs.count, 8, "eight rungs for an eight-week block")
        XCTAssertEqual(page?.rows.count, ladder?.rungs.count,
                       "the page has one row per rung — the fixtures cannot describe two blocks")
        XCTAssertEqual(page?.weekCount, ladder?.rungs.count)
        XCTAssertEqual(ladder?.rungs.filter { $0.status == .current }.count, 1,
                       "exactly one current rung")
        XCTAssertEqual(page?.rows.filter(\.isDeload).count, 1,
                       "the wave's deload is a rung, not smoothed away")
    }
```

2. Push; fails to compile.
3. Add the file exactly as written.
4. Push; green.
5. Commit: `feat(goal): the block-goal repository surface and its fixture ladder` + the trailer.

### 0.5 — the ladder-rule protocol and registry — **S**

**File (new):** `GymSyncApp/GymSync/Models/LadderRule.swift`

```swift
import Foundation

// MARK: - LadderRule
//
// Spec §3.4: "Each rule is a pure function (current, target, weeks) ->
// [target per week] with tests." The fourth parameter is the block's own
// shape — the deload and taper weeks the generator already decided — because
// a ramp that ignored the deload would put a peak week on top of the week the
// block halves the volume in.
//
// PURE, and the registry is a plain switch rather than a runtime table: the
// set of metrics is closed at compile time (`GoalMetric.allCases`), and a
// switch makes a new metric without a rule a compile error.

/// What the block already decided, handed to a ramp so it can respect it.
struct LadderConstraints: Equatable, Sendable {
    /// 0-based week indices the generator marked `isDeload`.
    var deloadWeeks: Set<Int> = []
    /// 0-based week indices carrying the strength taper (`Program.weeks`'
    /// final-week volume cut).
    var taperWeeks: Set<Int> = []
    /// The athlete's display unit. A ramp rounds in the unit the plates and
    /// the road signs are marked in, never in pounds and then converted —
    /// the doctrine `Units.roundToIncrement` and
    /// `WeeklyGoalDetector.liftTarget` both follow.
    var unit: WeightUnit = .lbs
}

/// One rung per week, from where the athlete is to where they said they want
/// to be.
protocol LadderRule: Sendable {
    /// Exactly `weeks` targets, 0-based by week index. `current` is the
    /// measured state (task A5's readers); `target` is the milestone.
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget]
}

/// A ladder that holds one value for the whole block — Maintenance and
/// Recovery's shape (spec §2.3), and the honest fallback for any metric whose
/// milestone is "keep doing this".
struct HoldLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        Array(repeating: target, count: max(0, weeks))
    }
}

/// Which rule builds which metric's ladder.
///
/// Stream A task A7 replaces every `HoldLadderRule` below with the metric's
/// real ramp, and A8 replaces the three the GENERATOR prescribes
/// (`liftOneRepMax`, `liftRepsAtLoad`, `weeklyMuscleSets`) with the read-out
/// — which is not a rule at all but a projection of `Program.weeks`, and is
/// why those three route through `LadderReadout` at the call site rather than
/// through here. The stub keeps every metric answerable from Task 0 onward.
enum LadderRules {
    static func rule(for metric: GoalMetric) -> any LadderRule {
        switch metric {
        case .liftOneRepMax, .liftRepsAtLoad, .weeklyMuscleSets:
            return HoldLadderRule()
        case .weeklyDistance, .trainingDaysPerWeek, .sessionsOfTypePerWeek,
             .lissMinutesPerWeek, .stretchingExercisesPerWeek, .bodyWeight,
             .cumulativeVolume, .benchmarkTime:
            return HoldLadderRule()
        }
    }
}
```

**Interfaces** — *consumes:* `GoalTarget`, `GoalMetric`, `WeightUnit` (`Models/Units.swift`).
*Produces:* `LadderConstraints`, `protocol LadderRule`, `HoldLadderRule`, `LadderRules.rule(for:)`.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/LadderRuleTests.swift`:

```swift
import XCTest
@testable import GymSync

final class LadderRuleTests: XCTestCase {

    func testEveryMetricHasARule() {
        for metric in GoalMetric.allCases {
            let rungs = LadderRules.rule(for: metric).rungs(
                current: GoalTarget(), target: GoalTarget(days: 4), weeks: 6,
                constraints: LadderConstraints())
            XCTAssertEqual(rungs.count, 6, "\(metric.rawValue) must answer for six weeks")
        }
    }

    func testAZeroWeekBlockProducesNoRungsRatherThanCrashing() {
        let rungs = HoldLadderRule().rungs(current: GoalTarget(), target: GoalTarget(),
                                           weeks: 0, constraints: LadderConstraints())
        XCTAssertTrue(rungs.isEmpty)
    }
}
```

2. Push; fails to compile.
3. Add the file exactly as written.
4. Push; green.
5. Commit: `feat(goal): the ladder-rule protocol and its metric registry` + the trailer.

**Push `feat/goal-first-release` here. The four streams fork from this commit.**

---
# STREAM A — data & ladder math

Worktree `wt-goal-data`, branch `feat/block-goal-data`. Zero SwiftUI. 14 tasks.

> **Migration gate, read once.** `.github/workflows/backend.yml:24-27` runs `node scripts/run_pgtap.js`
> against the **live** `SUPABASE_DB_URL`. There is no `supabase db push` anywhere in CI. A1 and A2's
> migrations must be applied to project `chjkkwqwdlmaxacwglzm` — by the operator, or via the Supabase MCP
> `apply_migration` — **before** A3 and A4's CI runs. Say so in each commit body (global constraint 10).

### A1 — `block_goals` + `block_goal_rungs` — **M**

**File (new):** `supabase/migrations/20260907000001_block_goals.sql`
(naming: `2026MMDD00000N_<slug>.sql`; latest existing is `20260906000002_friends_live.sql`).

Spec §8's DDL, plus the RLS and trigger conventions `20260906000001_weekly_goals.sql` set.

```sql
-- 20260907000001_block_goals.sql
--
-- Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md §8.
-- Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md, A1.
--
-- ONE PRIMARY GOAL PER BLOCK (owner decision 2) — enforced by
-- `unique (enrollment_id)`, not by client logic. A block that has no goal is a
-- block that predates this feature; a block with two is impossible.
--
-- `target` AND `block_goal_rungs.target` CARRY CAMELCASE KEYS, exactly as
-- `weekly_goals.params` does (`20260906000001_weekly_goals.sql:35-40`): the app
-- sets no `keyEncodingStrategy` anywhere, so `GoalTarget`'s synthesized encoder
-- writes its Swift property names, and those names ARE the wire contract.
--
-- RUNGS ARE PERSISTED, NOT ONLY COMPUTED (spec §8), for two reasons the design
-- states: a missed or overridden week must stay visible after re-laddering, and
-- the ledger has to be able to show the climb after the block is over.
-- Re-laddering rewrites only rows whose status is 'ahead' or 'current'.

CREATE TABLE public.block_goals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  enrollment_id uuid NOT NULL REFERENCES public.program_enrollments(id) ON DELETE CASCADE,
  metric        text NOT NULL,
  target        jsonb NOT NULL DEFAULT '{}'::jsonb,
  by_date       date,
  preset        text,
  source        text NOT NULL DEFAULT 'coach' CHECK (source IN ('coach','user')),
  outcome       text CHECK (outcome IN ('met','missed','partial')),
  outcome_value jsonb,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (enrollment_id)
);

-- NO CHECK ON `metric` OR `preset`, and that is deliberate rather than lax.
-- The registry is OPEN by owner decision 5: phases 2 and 3 add `zone2`,
-- `vo2_max`, `skill_reps` and `pattern_load_percent`, and a CHECK here would
-- make every one of those a migration on a table that did not otherwise change,
-- applied to the live project before the client that writes the value ships.
-- `GoalMetric(rawValue:)` is the gate on the read side — a row this build
-- cannot spell decodes to nil and the page renders empty, which is the same
-- forward-compatibility posture `WeeklyGoalRow.model` already takes
-- (`WeeklyGoalLiveRepository.swift:55-71`). `source` and `outcome` DO carry
-- CHECKs: those two vocabularies are closed by their own rulings.

ALTER TABLE public.block_goals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner reads own block goal"
  ON public.block_goals FOR SELECT TO authenticated
  USING (user_id = auth.uid());
CREATE POLICY "owner inserts own block goal"
  ON public.block_goals FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner updates own block goal"
  ON public.block_goals FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "owner deletes own block goal"
  ON public.block_goals FOR DELETE TO authenticated
  USING (user_id = auth.uid());

CREATE TABLE public.block_goal_rungs (
  goal_id     uuid NOT NULL REFERENCES public.block_goals(id) ON DELETE CASCADE,
  week_index  int  NOT NULL CHECK (week_index >= 0),
  week_start  date NOT NULL,
  target      jsonb NOT NULL DEFAULT '{}'::jsonb,
  status      text NOT NULL DEFAULT 'ahead'
              CHECK (status IN ('ahead','current','met','missed','overridden')),
  derived_at  timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (goal_id, week_index)
);

ALTER TABLE public.block_goal_rungs ENABLE ROW LEVEL SECURITY;

-- Rungs have no `user_id` of their own — they belong to a goal, and the goal
-- belongs to a user. Every policy therefore reaches through `block_goals`, and
-- that subquery is safe under INVOKER RLS here (unlike `friends_live`'s
-- sessions/participants cycle, `20260906000002_friends_live.sql:12-18`):
-- `block_goals`' own policies read only `auth.uid()` and never re-enter this
-- table, so there is no cycle to break and no reason for SECURITY DEFINER.
CREATE POLICY "owner reads own rungs"
  ON public.block_goal_rungs FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner inserts own rungs"
  ON public.block_goal_rungs FOR INSERT TO authenticated
  WITH CHECK (EXISTS (SELECT 1 FROM public.block_goals g
                      WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner updates own rungs"
  ON public.block_goal_rungs FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.block_goals g
                      WHERE g.id = goal_id AND g.user_id = auth.uid()));
CREATE POLICY "owner deletes own rungs"
  ON public.block_goal_rungs FOR DELETE TO authenticated
  USING (EXISTS (SELECT 1 FROM public.block_goals g
                 WHERE g.id = goal_id AND g.user_id = auth.uid()));

-- `updated_at` is `BlockGoal.updatedAt`, which the ladder page reads as "when
-- this milestone was last set". `DEFAULT now()` fires on INSERT only and the
-- client write path is an upsert whose row omits the column — the never-bumps
-- bug this repo has fixed three times now
-- (`20260726000005`, `20260726000006`, `20260906000001`).
--
-- clock_timestamp(), not now(): now() is frozen at transaction start, so a
-- transaction that creates and then updates the same row would stamp both
-- identically — which is also what lets A3's pgTAP compare GREATER rather than
-- equal. In `private`, not `public`, so it mints no PostgREST RPC endpoint
-- (`20260722000001_is_blocked_private_schema.sql`'s schema-purpose COMMENT).
CREATE OR REPLACE FUNCTION private.touch_block_goals_updated_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at := clock_timestamp();
  RETURN NEW;
END;
$$;

CREATE TRIGGER block_goals_touch_updated_at
  BEFORE UPDATE ON public.block_goals
  FOR EACH ROW
  EXECUTE FUNCTION private.touch_block_goals_updated_at();
```

**Interfaces** — *consumes:* `public.profiles(id)`, `public.program_enrollments(id)`, the `private` schema.
*Produces:* `public.block_goals`, `public.block_goal_rungs`, `private.touch_block_goals_updated_at()`.

**TDD steps.** SQL has no unit test; A3 is its test, and it cannot run until this is applied.

1. Write the migration exactly as above.
2. Apply it to the live project (operator, or Supabase MCP `apply_migration`).
3. Push. The Backend workflow runs the existing pgTAP suite; it must stay green (this migration adds tables
   and touches nothing existing).
4. Commit: `feat(goal): block_goals and block_goal_rungs — tables, RLS, updated_at trigger` + the trailer.
   Body records that the migration was applied to `chjkkwqwdlmaxacwglzm` before the push, and by whom.

### A2 — `weekly_goals` gains the ladder link and the four kinds — **S**

**File (new):** `supabase/migrations/20260907000002_weekly_goals_block_link.sql`

```sql
-- 20260907000002_weekly_goals_block_link.sql
--
-- Spec §4: the shipped weekly goal BECOMES the materialised current rung.
-- Two additive columns so a row knows the ladder it belongs to, and four
-- additive `kind` values so a rung of any phase-1 metric has a row shape.
--
-- ADDITIVE IN BOTH DIRECTIONS. `goal_id` is nullable with ON DELETE SET NULL:
-- "a row with goal_id = null is a standalone weekly goal exactly as today"
-- (spec §4), and deleting a block must not delete the weeks it happened to
-- describe — the athlete trained those weeks.

ALTER TABLE public.weekly_goals
  ADD COLUMN goal_id    uuid REFERENCES public.block_goals(id) ON DELETE SET NULL,
  ADD COLUMN rung_index int CHECK (rung_index IS NULL OR rung_index >= 0);

-- The CHECK is REPLACED rather than added to: a column may carry only one
-- constraint of this name, and Postgres has no "extend a CHECK". The five
-- shipped values are repeated verbatim so the diff shows exactly four
-- additions and no removals.
ALTER TABLE public.weekly_goals DROP CONSTRAINT weekly_goals_kind_check;
ALTER TABLE public.weekly_goals ADD CONSTRAINT weekly_goals_kind_check
  CHECK (kind IN ('muscle_sets','distance','sessions_of_type','days','lift',
                  'recovery','body_weight','volume','benchmark'));

-- `goal_id` is written in BOTH the column and `params.goalID`, and that is not
-- an accident: the COLUMN is what the foreign key and the ON DELETE SET NULL
-- need, and the PARAM is what survives into `WeeklyGoal` — a struct that is
-- deliberately not Codable and has no field per column
-- (`WeeklyGoalLiveRepository.swift:9-13`). One value, written twice by one
-- function (`LiveWeeklyGoalRepository`'s row DTO, task A11); pgTAP asserts they
-- agree (task A4).
COMMENT ON COLUMN public.weekly_goals.goal_id IS
  'The block_goals row whose ladder materialised this week. NULL = a standalone weekly goal. Mirrored into params.goalID for the client model.';
COMMENT ON COLUMN public.weekly_goals.rung_index IS
  '0-based week index within that ladder, matching block_goal_rungs.week_index.';
```

**Interfaces** — *consumes:* `public.block_goals(id)` (A1). *Produces:* `weekly_goals.goal_id`,
`weekly_goals.rung_index`, the widened `kind` vocabulary.

**TDD steps.**

1. Write the migration exactly as above.
2. Confirm the existing constraint's name before pushing:
   `SELECT conname FROM pg_constraint WHERE conrelid = 'public.weekly_goals'::regclass AND contype = 'c';`
   The inline `CHECK` in `20260906000001` gets Postgres's default name `weekly_goals_kind_check`. **If it is
   named otherwise, use the real name** — a `DROP CONSTRAINT` on a name that does not exist fails the whole
   migration.
3. Apply to the live project.
4. Push; the existing `weekly_goals_test.sql` must stay green. Its assertion 6 rejects the invented kind
   `'steps'` (`weekly_goals_test.sql:102-108`) — **not** one of the four this migration adds, so it still
   passes. Its message string says "outside the five"; A4 updates that wording to "outside the nine".
5. Commit: `feat(goal): weekly_goals gains goal_id, rung_index and four kinds` + the trailer.

### A3 — pgTAP for `block_goals` and `block_goal_rungs` — **M**

**File (new):** `supabase/tests/block_goals_test.sql`. Follow `supabase/tests/weekly_goals_test.sql` exactly:
`BEGIN; CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions; SELECT plan(n);`, two fixture
`auth.users` + `profiles`, `SET LOCAL role authenticated` + `SET LOCAL request.jwt.claim.sub`, `ROLLBACK;`.

Assertions, `plan(20)`:

1. owner inserts a goal for their own enrollment;
2. defaults apply when omitted — `source = 'coach'`, `target = '{}'::jsonb`, `outcome IS NULL`;
3. `UNIQUE (enrollment_id)` rejects a second goal for the same block — **this is owner decision 2 in the
   database**, and the assertion names it;
4. `source` outside `{coach,user}` is rejected;
5. `outcome` outside `{met,missed,partial}` is rejected;
6. a `metric` string the app has never heard of is **accepted** — the open-registry posture A1's header
   states, asserted so a future CHECK cannot be added without failing this;
7. camelCase survives the round trip:
   `target -> 'targetWeightLbs'` reads back `225` from `'{"targetWeightLbs":225}'::jsonb`;
8. `updated_at` is bumped by the trigger: capture it, `UPDATE`, assert the new value is **greater**
   (`clock_timestamp()` is why this is `>` and not `>=`);
9. rungs insert against an owned goal;
10. `PRIMARY KEY (goal_id, week_index)` rejects a duplicate week;
11. `week_index` negative is rejected;
12. `status` outside the five is rejected;
13. deleting the goal cascades its rungs to zero;
14. deleting the **enrollment** cascades the goal (and therefore the rungs) — the FK's own promise;
15–18. **the four RLS denials**: an outsider sees zero goals; cannot insert a goal for another user_id; sees
    zero rungs for someone else's goal; cannot insert a rung against someone else's goal (this is the one that
    proves the `EXISTS` subquery in the rung policies actually gates);
19. an outsider cannot UPDATE another user's goal (zero rows affected, not an error);
20. `weekly_goals.goal_id` set to a goal, then the goal deleted → the weekly row **survives** with
    `goal_id IS NULL` (A2's `ON DELETE SET NULL`).

**TDD steps.**

1. Write the file. Do not run it locally — there is no local Postgres; CI is the runner.
2. Push. The Backend workflow runs it (paths filter `supabase/**` matches).
3. Read the failure list; fix; push again. A failing assertion here is a real defect in A1/A2, not a test bug,
   until proven otherwise.
4. Commit: `test(goal): pgTAP for block_goals and block_goal_rungs — 20 assertions` + the trailer.
   **Proves it:** `node scripts/run_pgtap.js` green in the Backend workflow.

### A4 — extend `weekly_goals`' pgTAP for the new columns and kinds — **S**

**File:** `supabase/tests/weekly_goals_test.sql`. `SELECT plan(22)` → `SELECT plan(28)`.

Six assertions, appended after the existing block so the numbering above it does not move:

23. each of the four new `kind` values is accepted (`recovery`, `body_weight`, `volume`, `benchmark`);
24. an invented kind is still rejected — assertion 6 already covers `'steps'`
    (`weekly_goals_test.sql:102-108`); this one re-asserts it *after* the CHECK was replaced, which is the
    thing A2 could have got wrong. Also update assertion 6's message from "outside the five" to
    "outside the nine";
25. `goal_id` accepts a real `block_goals.id`;
26. `goal_id` rejects an id no goal has (the FK);
27. `rung_index` negative is rejected;
28. a row written with `goal_id = <id>` and `params -> 'goalID'` = the same id reads both back equal — the
    mirror A2's COMMENT promises, asserted rather than trusted.

**TDD steps.** Same as A3: write, push, read CI, fix.
Commit: `test(goal): weekly_goals pgTAP covers the ladder link and the four new kinds` + the trailer.

### A5 — the four new metric readers — **M**

**File (new):** `GymSyncApp/GymSync/Models/BlockGoalMetricMath.swift`

**Pure.** Every input passed in, including the clock and the calendar — the posture
`WeeklyGoalProgressMath.swift:9-13` sets and the reason its agreement law is testable.

```swift
import Foundation

// MARK: - BlockGoalMetricMath
//
// Spec §2.2's registry, read side. "Where am I now" for the metrics phase 1
// adds. The five shipped metrics already have readers in
// `WeeklyGoalProgressMath` (liftProgress, muscleSetsProgress, distanceProgress,
// distinctTrainingDays, sessionsOfTypeProgress) and are NOT duplicated here —
// two readers for one metric is exactly the drift the agreement law forbids.
//
// PURE. No network, no `Date.now`, no HealthKit store. The HealthKit-backed
// reader (A6) takes samples as a parameter for the same reason, which is also
// global constraint 5: a unit test must never raise a permission sheet.
enum BlockGoalMetricMath {

    /// `bodyWeight` — the most recent logged body weight, in CANONICAL POUNDS.
    ///
    /// The app's OWN log is the source (`BodyWeightLogRepository.recent`,
    /// `Models/BodyWeightLog.swift:37`), which stores pounds with `unit = "lbs"`
    /// whatever the athlete typed (`BodyWeightLogSheet.swift:94-96`). A row
    /// whose `unit` is anything else is a row this app did not write; it is
    /// skipped rather than converted on a guess.
    ///
    /// nil when there is no log at all — which the ladder renders as "log a
    /// weight", never as 0 lb.
    static func currentBodyWeightPounds(logs: [BodyWeightLog]) -> Decimal? {
        logs.filter { $0.unit.lowercased() == "lbs" && $0.weight > 0 }
            .max { $0.loggedAt < $1.loggedAt }?
            .weight
    }

    /// `cumulativeVolume` — pounds moved across `logs`, the same arithmetic the
    /// plate milestone catalog counts.
    ///
    /// `completedReps`, never raw `reps`, and penalties excluded: the failure
    /// doctrine `WeeklyGoalProgressMath.muscleSetCredit` states in full. A
    /// failed triple moved two reps' worth of iron and counts them; a failed
    /// single moved none.
    static func volumePounds(logs: [SetLog]) -> Double {
        logs.reduce(0.0) { total, log in
            guard !log.isPenalty,
                  let reps = log.completedReps, reps > 0,
                  let weight = log.weight, weight > 0 else { return total }
            return total + NSDecimalNumber(decimal: weight).doubleValue * Double(reps)
        }
    }

    /// `benchmarkTime` — the fastest completed run of one named routine, in
    /// seconds, or nil when it has never been finished.
    ///
    /// FASTEST, not most recent: a benchmark is a record of the best you have
    /// done, the same reading `StatMath.estimatedOneRepMax`'s consumers take of
    /// a lift. A session with no `startedAt` is skipped rather than measured
    /// from its `completedAt` alone.
    static func bestBenchmarkSeconds(sessions: [WorkoutSession],
                                     routineID: UUID) -> Int? {
        sessions
            .compactMap { session -> Int? in
                guard session.routineID == routineID,
                      let started = session.startedAt,
                      let completed = session.completedAt,
                      completed > started else { return nil }
                return Int(completed.timeIntervalSince(started).rounded())
            }
            .min()
    }

    /// `liftRepsAtLoad` — the most reps completed in a single set at or above
    /// `loadLbs`, for one exercise.
    ///
    /// AT OR ABOVE, because "10 at 225" is satisfied by ten at 235. A set below
    /// the load says nothing about the goal and is not scaled into it — that
    /// would be an e1RM, which is a different metric with its own reader.
    static func bestRepsAtLoad(logs: [SetLog], exerciseID: UUID,
                               loadLbs: Decimal) -> Int? {
        logs
            .filter { $0.exerciseID == exerciseID && !$0.isPenalty }
            .compactMap { log -> Int? in
                guard let weight = log.weight, weight >= loadLbs,
                      let reps = log.completedReps, reps > 0 else { return nil }
                return reps
            }
            .max()
    }
}
```

**Interfaces** — *consumes:* `BodyWeightLog` (`Models/BodyWeightLog.swift:12`), `SetLog`
(`.isPenalty`, `.completedReps`, `.weight`, `.exerciseID`), `WorkoutSession`
(`.routineID`, `.startedAt`, `.completedAt`). *Produces:* `BlockGoalMetricMath` and its four statics; A11 and
A12 call them.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/BlockGoalMetricMathTests.swift`:

```swift
import XCTest
@testable import GymSync

final class BlockGoalMetricMathTests: XCTestCase {

    // MARK: - Fixtures
    //
    // PRIVATE HELPERS BUILT ON THE REAL INITIALIZERS, which is this repo's
    // only fixture idiom — grep-verified: there is no `SetLog.fixture` or
    // `Exercise.fixture` anywhere, and `WeeklyGoalProgressTests:14-37` and
    // `HomeCompositionTests:196-213` each declare their own. Copy those
    // helpers' shape rather than adding a shared one: a second builder for
    // one model is how two suites come to disagree about what a failed set is.
    //
    // `reps` + `isFailed`, never a `completedReps:` argument — `completedReps`
    // is DERIVED (`SetLog.swift:41-45`), and a fixture that set it directly
    // would let a test pass against arithmetic production cannot produce.

    private func id(_ n: Int) -> UUID {
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))!
    }

    private func log(_ exerciseID: UUID, weight: Decimal, reps: Int?,
                     failed: Bool = false, penalty: Bool = false,
                     sessionID: UUID? = nil, at seconds: TimeInterval = 0) -> SetLog {
        SetLog(id: UUID(), userID: id(9001), sessionID: sessionID ?? id(9002),
               exerciseID: exerciseID, setIndex: 1, reps: reps, weight: weight,
               rpe: nil, isFailed: failed, isPenalty: penalty, note: nil,
               loggedAt: Date(timeIntervalSince1970: seconds))
    }

    private func exercise(_ n: Int, category: String,
                          primary: String = "chest") -> Exercise {
        Exercise(id: id(n), name: "Fixture \(n)", slug: "fixture-\(n)",
                 category: category, primaryMuscle: primary,
                 secondaryMuscles: [], equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func session(routineID: UUID?, startedAt: Date?,
                         completedAt: Date?) -> WorkoutSession {
        WorkoutSession(id: UUID(), routineID: routineID, organizerID: id(9001),
                       state: "completed", startedAt: startedAt,
                       completedAt: completedAt,
                       createdAt: Date(timeIntervalSince1970: 0),
                       groupID: nil, roomCode: nil, scheduledFor: nil,
                       seriesID: nil, currentTurnUserID: nil,
                       currentTurnStartedAt: nil)
    }

    func testBodyWeightTakesTheLatestPoundsRow() {
        let userID = UUID()
        let logs = [
            BodyWeightLog(id: UUID(), userID: userID, weight: 185, unit: "lbs",
                          loggedAt: Date(timeIntervalSince1970: 100)),
            BodyWeightLog(id: UUID(), userID: userID, weight: 183, unit: "lbs",
                          loggedAt: Date(timeIntervalSince1970: 300)),
            BodyWeightLog(id: UUID(), userID: userID, weight: 83, unit: "kg",
                          loggedAt: Date(timeIntervalSince1970: 400)),
        ]
        XCTAssertEqual(BlockGoalMetricMath.currentBodyWeightPounds(logs: logs), 183,
                       "the kg row is not this app's and is skipped, not converted")
        XCTAssertNil(BlockGoalMetricMath.currentBodyWeightPounds(logs: []))
    }

    func testVolumeCountsCompletedRepsAndSkipsPenalties() {
        let bench = id(1)
        let logs = [
            log(bench, weight: 100, reps: 10),                       // 1000
            log(bench, weight: 100, reps: 3, failed: true),          // 200 — a failed triple
            log(bench, weight: 100, reps: 1, failed: true),          // a failed single: nothing
            log(bench, weight: 100, reps: 10, penalty: true),        // the burpee tax
        ]
        XCTAssertEqual(BlockGoalMetricMath.volumePounds(logs: logs), 1200, accuracy: 0.001)
    }

    func testBenchmarkTakesTheFastestFinishedRun() {
        let murph = id(2)
        let sessions = [
            session(routineID: murph, startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: Date(timeIntervalSince1970: 2_830)),
            session(routineID: murph, startedAt: Date(timeIntervalSince1970: 10_000),
                    completedAt: Date(timeIntervalSince1970: 12_700)),
            session(routineID: murph, startedAt: nil,
                    completedAt: Date(timeIntervalSince1970: 20_000)),
            session(routineID: id(3), startedAt: Date(timeIntervalSince1970: 0),
                    completedAt: Date(timeIntervalSince1970: 60)),
        ]
        XCTAssertEqual(BlockGoalMetricMath.bestBenchmarkSeconds(sessions: sessions,
                                                               routineID: murph), 2_700)
        XCTAssertNil(BlockGoalMetricMath.bestBenchmarkSeconds(sessions: [], routineID: murph))
    }

    func testRepsAtLoadCountsSetsAtOrAboveTheLoad() {
        let bench = id(1)
        let logs = [
            log(bench, weight: 225, reps: 8),
            log(bench, weight: 235, reps: 6),
            log(bench, weight: 215, reps: 15),   // below the load: says nothing
        ]
        XCTAssertEqual(BlockGoalMetricMath.bestRepsAtLoad(logs: logs, exerciseID: bench,
                                                          loadLbs: 225), 8)
        XCTAssertNil(BlockGoalMetricMath.bestRepsAtLoad(logs: logs, exerciseID: id(9),
                                                        loadLbs: 225))
    }
}
```

2. Push; fails to compile.
3. Add `Models/BlockGoalMetricMath.swift` exactly as written.
4. Push; `BlockGoalMetricMathTests` green.
5. Commit: `feat(goal): readers for body weight, cumulative volume, benchmark time and reps at load` + trailer.

### A6 — Recovery's two readers — **M**

**Files:** `GymSyncApp/GymSync/Models/BlockGoalMetricMath.swift` (extend),
`GymSyncApp/GymSync/Services/HealthKitBridge.swift`.

Recovery is the one preset with two metrics, and it is still ONE goal (spec §2.3): the primary is
`stretchingExercisesPerWeek` — what the block schedules — and `lissMinutesPerWeek` is its companion read on the
same rung.

**`HealthKitBridge`** gains one reader, alongside `workoutTags(from:to:)` (:196) and reusing
`workouts(from:to:)` (:117) so the query and its guards are not written twice:

```swift
    /// Minutes of LOW-INTENSITY STEADY-STATE work in the window (spec §2.2's
    /// `lissMinutesPerWeek`, NEW).
    ///
    /// The activity families, not a heart-rate zone: walking, cycling, rowing,
    /// elliptical and stair climbing — the five `workoutTags` already treats as
    /// `cardio`, minus running, which is where LISS stops being low intensity
    /// for most lifters.
    ///
    /// WHAT THIS CANNOT DO, and it is the spec's own open item (§11.2):
    /// distinguish an easy ride from an interval session. That needs the
    /// watch's heart-rate samples, which is phase 2's `zone2MinutesPerWeek`.
    /// Until then a bike is a bike. Stated here rather than papered over, and
    /// the reason `BlockGoalMetricMath.lissMinutes` also counts a cardio-only
    /// APP session for an athlete with no Health at all.
    ///
    /// Best-effort: 0 on no availability, no permission, or any error — never
    /// nil, so the ladder renders `0 / 150 min` rather than an error. The
    /// CONNECT HEALTH read is `weeklyGoalHealthNeedsConnecting()`'s job, as it
    /// is for distance.
    static func lissMinutes(from start: Date, to end: Date) async -> Int {
        let families: Set<HKWorkoutActivityType> = [
            .walking, .cycling, .rowing, .elliptical, .stairClimbing,
        ]
        let seconds = await workouts(from: start, to: end)
            .filter { families.contains($0.workoutActivityType) }
            .reduce(0.0) { $0 + $1.duration }
        return Int((seconds / 60).rounded())
    }
```

**`BlockGoalMetricMath`** gains the two pure readers:

```swift
    /// `lissMinutesPerWeek` — Health's minutes plus the app's own cardio-only
    /// sessions, de-duplicated by overlap.
    ///
    /// An athlete with no Health connected still has a reading: a session whose
    /// routine is cardio-only is LISS by prescription. An athlete WITH Health
    /// gets both, and a session the watch also recorded must not count twice —
    /// `HealthWorkoutTag.matches(type:sessionStart:sessionEnd:)` is the same
    /// interval-overlap test `sessionCounts` uses, and the same 15-minute
    /// tolerance, so the two readings cannot disagree about what one piece of
    /// training was.
    static func lissMinutes(healthMinutes: Int,
                            sessions: [WorkoutSession],
                            routines: [UUID: Routine],
                            routineExercises: [UUID: [RoutineExercise]],
                            catalog: [UUID: Exercise],
                            healthWorkouts: [HealthWorkoutTag]) -> Int {
        var appMinutes = 0
        for session in sessions {
            guard let completed = session.completedAt,
                  let routineID = session.routineID,
                  isCardioOnly(routineID: routineID,
                               routineExercises: routineExercises,
                               catalog: catalog) else { continue }
            let started = session.startedAt ?? completed
            // Already counted on the Health side — the watch closed its own
            // workout around this session.
            if healthWorkouts.contains(where: { $0.matches(type: "cardio",
                                                           sessionStart: started,
                                                           sessionEnd: completed) }) {
                continue
            }
            appMinutes += Int((completed.timeIntervalSince(started) / 60).rounded())
        }
        return max(0, healthMinutes) + appMinutes
    }

    /// Every exercise in the routine is `cardio`. Not "half or more" — that is
    /// `sessionCounts`' threshold for "was this a cardio session", and this is
    /// a stricter question: LISS is the whole session being easy work, and a
    /// lifting day with a finisher on the bike is not it.
    static func isCardioOnly(routineID: UUID,
                             routineExercises: [UUID: [RoutineExercise]],
                             catalog: [UUID: Exercise]) -> Bool {
        let categories = (routineExercises[routineID] ?? [])
            .compactMap { catalog[$0.exerciseID]?.category.lowercased() }
        guard !categories.isEmpty else { return false }
        return categories.allSatisfy { $0 == "cardio" }
    }

    /// `stretchingExercisesPerWeek` — completed mobility exercises this week.
    ///
    /// Counted by DISTINCT EXERCISE per session, not by set: "six stretching
    /// exercises" is six movements, and three sets of a hamstring stretch is
    /// one of them. A penalty log is not training, for the same reason it
    /// credits no muscle sets.
    static func stretchingExerciseCount(logs: [SetLog],
                                        catalog: [UUID: Exercise]) -> Int {
        var seen: Set<String> = []
        for log in logs {
            guard !log.isPenalty, log.completedReps != nil,
                  let exercise = catalog[log.exerciseID],
                  exercise.category.lowercased() == "mobility" else { continue }
            seen.insert("\(log.sessionID.uuidString)-\(log.exerciseID.uuidString)")
        }
        return seen.count
    }
```

**Interfaces** — *consumes:* `HealthWorkoutTag` (`WeeklyGoalProgressMath.swift:24`, with `matches` and
`sessionMatchTolerance`), `Exercise.category`, `RoutineExercise.exerciseID`, `SetLog.sessionID`.
*Produces:* `HealthKitBridge.lissMinutes(from:to:)`, `BlockGoalMetricMath.lissMinutes(...)`,
`.isCardioOnly(...)`, `.stretchingExerciseCount(...)`.

**TDD steps.**

1. Failing test — append to `BlockGoalMetricMathTests.swift`. **No HealthKit store is touched** (global
   constraint 5): `healthMinutes` is a parameter.

```swift
    private func row(_ routineID: UUID, _ exerciseID: UUID) -> RoutineExercise {
        RoutineExercise(id: UUID(), routineID: routineID, exerciseID: exerciseID,
                        position: 1, targetSets: 3, targetReps: "10",
                        targetWeight: nil, restSeconds: 90, notes: nil)
    }

    func testLissAddsAppCardioSessionsAndNeverDoubleCountsAWatchedOne() {
        let routineID = id(10)
        let bike = id(11)
        let catalog = [bike: exercise(11, category: "cardio", primary: "quads")]
        let rows = [routineID: [row(routineID, bike)]]
        let started = Date(timeIntervalSince1970: 10_000)
        let ended = started.addingTimeInterval(1_800)   // 30 min
        let ride = session(routineID: routineID, startedAt: started, completedAt: ended)

        let unwatched = BlockGoalMetricMath.lissMinutes(
            healthMinutes: 60, sessions: [ride], routines: [:],
            routineExercises: rows, catalog: catalog, healthWorkouts: [])
        XCTAssertEqual(unwatched, 90, "60 from Health plus the app's own 30")

        let watched = BlockGoalMetricMath.lissMinutes(
            healthMinutes: 60, sessions: [ride], routines: [:],
            routineExercises: rows, catalog: catalog,
            healthWorkouts: [HealthWorkoutTag(type: "cardio", start: started, end: ended)])
        XCTAssertEqual(watched, 60, "the watch already counted this session")
    }

    func testCardioOnlyIsStricterThanTheSessionTypeThreshold() {
        let routineID = id(10)
        let bike = id(11), bench = id(12)
        let catalog = [bike: exercise(11, category: "cardio", primary: "quads"),
                       bench: exercise(12, category: "compound")]
        let mixed = [routineID: [row(routineID, bike), row(routineID, bench)]]
        XCTAssertFalse(BlockGoalMetricMath.isCardioOnly(routineID: routineID,
                                                        routineExercises: mixed,
                                                        catalog: catalog),
                       "half cardio is a cardio SESSION, but it is not LISS")

        let cardioOnly = [routineID: [row(routineID, bike)]]
        XCTAssertTrue(BlockGoalMetricMath.isCardioOnly(routineID: routineID,
                                                       routineExercises: cardioOnly,
                                                       catalog: catalog))
    }

    func testStretchingCountsMovementsNotSets() {
        let sessionID = id(20)
        let hamstring = id(21), hip = id(22), bench = id(23)
        let catalog = [
            hamstring: exercise(21, category: "mobility", primary: "hamstrings"),
            hip: exercise(22, category: "mobility", primary: "hip_flexors"),
            bench: exercise(23, category: "compound"),
        ]
        let logs = [
            log(hamstring, weight: 0, reps: 10, sessionID: sessionID),
            log(hamstring, weight: 0, reps: 10, sessionID: sessionID),
            log(hip, weight: 0, reps: 10, sessionID: sessionID),
            log(bench, weight: 135, reps: 5, sessionID: sessionID),
            log(hip, weight: 0, reps: 10, penalty: true, sessionID: sessionID),
        ]
        XCTAssertEqual(BlockGoalMetricMath.stretchingExerciseCount(logs: logs,
                                                                   catalog: catalog), 2)
    }
```

2. Push; fails to compile.
3. Add the three pure functions and `HealthKitBridge.lissMinutes(from:to:)`.
4. Push; green.
5. Commit: `feat(goal): LISS minutes and the stretching count — Recovery's two readers` + the trailer.

### A7 — the ramp rules — **L**

**File (new):** `GymSyncApp/GymSync/Models/LadderRules+Ramps.swift`, replacing the `HoldLadderRule`
placeholders in `LadderRules.rule(for:)` for the eight metrics the lifting generator does not prescribe.

Spec §3.4 and §2.3's ladder-shape column are the specification. Each rule is a pure struct; each gets tests.

| metric | rule | shape (spec §2.3) |
|---|---|---|
| `weeklyDistance` | `PercentRampLadderRule(step: 0.10, downWeekEvery: 4, downFactor: 0.7)` | +10 % a week, every fourth week down |
| `trainingDaysPerWeek` | `StepEveryNWeeksLadderRule(step: 1, everyWeeks: 2)` | +1 day every two weeks until the target holds |
| `sessionsOfTypePerWeek` | `StepEveryNWeeksLadderRule(step: 1, everyWeeks: 2)` | the same ramp as Consistency |
| `lissMinutesPerWeek` | `HoldLadderRule` | flat — Recovery's companion read |
| `stretchingExercisesPerWeek` | `HoldLadderRule` | flat or gently descending; **flat**, and the plan says which |
| `bodyWeight` | `RateOfChangeLadderRule` | lose 0.5–1 %/wk, gain 0.25–0.5 %/wk |
| `cumulativeVolume` | `CumulativeLadderRule` | weekly tonnage rising to the total |
| `benchmarkTime` | `DescendingLadderRule` | time descends across the block |

Two rules carry decisions the spec left as a range, and the plan makes them:

- **`RateOfChangeLadderRule`.** The spec gives *bands* (lose 0.5–1 % a week, gain 0.25–0.5 %). The rung is the
  **implied weekly rate needed to reach the target by the date, clamped into the band** — so an athlete who
  asks for something achievable gets exactly their own plan, and one who asks for 20 lb in three weeks gets
  the band's edge and a `reachesMilestone: false` standing (task A12) that says so. Direction decides the
  band: `target < current` → clamp into `[-1.0, -0.5]`; `target > current` → `[0.25, 0.5]`; equal → flat.
- **`DescendingLadderRule`.** Benchmark time descends **linearly** from the measured current time to the
  target, because there is no evidence-cited curve for it in `GeneratorScience` and inventing one would be a
  number with no source. Deload weeks hold the previous rung rather than descending.

Every rule honours `constraints.deloadWeeks`: **a deload week never advances.** It repeats the previous rung
(or, for `PercentRampLadderRule`, applies `downFactor`), and the week after resumes from where the ramp was —
the deload does not consume a step. That single rule is why `LadderConstraints` exists.

```swift
import Foundation

// MARK: - The ramp rules (spec §3.4)
//
// The lifting generator prescribes `liftOneRepMax`, `liftRepsAtLoad` and
// `weeklyMuscleSets`; their rungs are READ OFF the plan (task A8). Everything
// else needs a rule, and these are them — pure, tested, and each one a single
// documented shape rather than a knob.
//
// THE DELOAD LAW, once, here, because all four rules obey it: a deload week
// never advances. The block already decided that week is lighter
// (`ProgramGenerator.swift:922-935`), and a ladder that climbed through it
// would be a second opinion about the athlete's week.

/// +`step` a fraction each week, with every `downWeekEvery`-th week cut to
/// `downFactor` of the week before it. Endurance's shape.
struct PercentRampLadderRule: LadderRule {
    let step: Double
    let downWeekEvery: Int
    let downFactor: Double
    /// Which field of `GoalTarget` this rule ramps — the one thing that
    /// differs between a distance ladder and a minutes ladder.
    let read: @Sendable (GoalTarget) -> Double?
    let write: @Sendable (inout GoalTarget, Double) -> Void

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = read(current) ?? 0
        let finish = read(target) ?? start
        // A ramp needs somewhere to ramp FROM. With no measured current state
        // the honest ladder is the milestone held flat, not a climb out of
        // zero that would prescribe a first week nobody can train.
        guard start > 0, finish > start else {
            return Array(repeating: target, count: weeks)
        }
        var value = start
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            let isDown = constraints.deloadWeeks.contains(index)
                || (downWeekEvery > 0 && (index + 1) % downWeekEvery == 0)
            if isDown {
                var rung = target
                write(&rung, (value * downFactor).rounded(.toNearestOrEven))
                out.append(rung)
                continue                      // the down week does not consume a step
            }
            value = min(finish, value * (1 + step))
            var rung = target
            write(&rung, (value * 10).rounded() / 10)
            out.append(rung)
        }
        // The last rung IS the milestone. A ramp that lands at 14.9 of a 15
        // target would make the final week a miss by arithmetic.
        if var last = out.last { write(&last, finish); out[out.count - 1] = last }
        return out
    }
}

/// +`step` every `everyWeeks` weeks until the target, then hold. Consistency
/// and Conditioning's shape ("+1 day every two weeks until the target holds").
struct StepEveryNWeeksLadderRule: LadderRule {
    let step: Int
    let everyWeeks: Int
    let read: @Sendable (GoalTarget) -> Int?
    let write: @Sendable (inout GoalTarget, Int) -> Void

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = read(current) ?? 0
        let finish = read(target) ?? start
        guard finish > start else { return Array(repeating: target, count: weeks) }
        var value = start
        var sinceStep = 0
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            if constraints.deloadWeeks.contains(index) {
                var rung = target
                write(&rung, value)
                out.append(rung)
                continue
            }
            sinceStep += 1
            if sinceStep >= max(1, everyWeeks) {
                value = min(finish, value + step)
                sinceStep = 0
            }
            var rung = target
            write(&rung, value)
            out.append(rung)
        }
        if var last = out.last { write(&last, finish); out[out.count - 1] = last }
        return out
    }
}

/// Body composition: the implied weekly rate, clamped into the evidence band
/// for its direction.
struct RateOfChangeLadderRule: LadderRule {
    /// Losing: 0.5–1.0 % of body weight a week. Gaining: 0.25–0.5 %.
    static let lossBand = (min: 0.005, max: 0.010)
    static let gainBand = (min: 0.0025, max: 0.005)

    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        let start = double(current.bodyWeightLbs)
        let finish = double(target.bodyWeightLbs)
        guard start > 0, finish > 0, start != finish else {
            return Array(repeating: target, count: weeks)
        }
        let losing = finish < start
        let band = losing ? Self.lossBand : Self.gainBand
        let impliedPerWeek = abs(finish - start) / start / Double(weeks)
        let rate = Swift.min(Swift.max(impliedPerWeek, band.min), band.max)

        var value = start
        var out: [GoalTarget] = []
        for index in 0..<weeks {
            if !constraints.deloadWeeks.contains(index) {
                value = losing ? value * (1 - rate) : value * (1 + rate)
                value = losing ? Swift.max(value, finish) : Swift.min(value, finish)
            }
            var rung = target
            rung.bodyWeightLbs = Decimal((value * 10).rounded() / 10)
            rung.bodyWeightRatePercent = (losing ? -rate : rate) * 100
            out.append(rung)
        }
        return out
    }

    private func double(_ value: Decimal?) -> Double {
        value.map { NSDecimalNumber(decimal: $0).doubleValue } ?? 0
    }
}

/// Cumulative volume: the WEEK's tonnage, rising so the block's sum is the
/// milestone.
///
/// The rungs are per-week tonnage, not a running total — that is what the
/// strip's `volumeLbs` param means and what the athlete can act on. A deload
/// week takes half (the generator's own `deloadVolumeMultiplier` reasoning),
/// and the remaining weeks carry what it gave up, so the block still sums to
/// the milestone.
struct CumulativeLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0, let total = target.volumeLbs, total > 0 else {
            return Array(repeating: target, count: Swift.max(0, weeks))
        }
        let weights = (0..<weeks).map { constraints.deloadWeeks.contains($0) ? 0.5 : 1.0 }
        let denominator = weights.reduce(0, +)
        guard denominator > 0 else { return Array(repeating: target, count: weeks) }
        return weights.map { weight in
            var rung = target
            rung.volumeLbs = (total * weight / denominator / 100).rounded() * 100
            return rung
        }
    }
}

/// Benchmark time descends linearly from the measured current time to the
/// target. A deload week holds the week before it.
struct DescendingLadderRule: LadderRule {
    func rungs(current: GoalTarget, target: GoalTarget, weeks: Int,
               constraints: LadderConstraints) -> [GoalTarget] {
        guard weeks > 0 else { return [] }
        guard let start = current.targetSeconds, let finish = target.targetSeconds,
              start > finish else {
            return Array(repeating: target, count: weeks)
        }
        var out: [GoalTarget] = []
        var previous = start
        for index in 0..<weeks {
            var rung = target
            if constraints.deloadWeeks.contains(index) {
                rung.targetSeconds = previous
            } else {
                let progress = Double(index + 1) / Double(weeks)
                previous = start - Int((Double(start - finish) * progress).rounded())
                rung.targetSeconds = previous
            }
            out.append(rung)
        }
        return out
    }
}

extension LadderRules {
    /// The eight ramp-driven metrics. `liftOneRepMax`, `liftRepsAtLoad` and
    /// `weeklyMuscleSets` are absent BY DESIGN: their rungs are read off
    /// `Program.weeks` (task A8), never ramped.
    static func rampRule(for metric: GoalMetric) -> (any LadderRule)? {
        switch metric {
        case .weeklyDistance:
            return PercentRampLadderRule(
                step: 0.10, downWeekEvery: 4, downFactor: 0.7,
                read: { $0.distance }, write: { $0.distance = $1 })
        case .trainingDaysPerWeek:
            return StepEveryNWeeksLadderRule(
                step: 1, everyWeeks: 2,
                read: { $0.days }, write: { $0.days = $1 })
        case .sessionsOfTypePerWeek:
            return StepEveryNWeeksLadderRule(
                step: 1, everyWeeks: 2,
                read: { $0.sessions }, write: { $0.sessions = $1 })
        case .lissMinutesPerWeek, .stretchingExercisesPerWeek:
            return HoldLadderRule()
        case .bodyWeight:      return RateOfChangeLadderRule()
        case .cumulativeVolume: return CumulativeLadderRule()
        case .benchmarkTime:   return DescendingLadderRule()
        case .liftOneRepMax, .liftRepsAtLoad, .weeklyMuscleSets:
            return nil
        }
    }
}
```

`LadderRules.rule(for:)` (Task 0.5) becomes `rampRule(for: metric) ?? HoldLadderRule()`, so every metric still
answers and the three read-out metrics route through A8 at the call site.

**Interfaces** — *consumes:* `LadderRule`, `LadderConstraints`, `GoalTarget`, `GoalMetric`.
*Produces:* the five rule structs and `LadderRules.rampRule(for:)`; A9 and A12 call them.

**TDD steps.**

1. Failing tests — extend `GymSyncApp/GymSyncTests/LadderRuleTests.swift`:

```swift
    func testDistanceRampsTenPercentWithEveryFourthWeekDown() {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .weeklyDistance) as? PercentRampLadderRule)
        let rungs = rule.rungs(current: GoalTarget(distance: 10),
                               target: GoalTarget(activity: "run", distance: 15),
                               weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(rungs.count, 8)
        XCTAssertEqual(try XCTUnwrap(rungs[0].distance), 11.0, accuracy: 0.05)
        XCTAssertLessThan(try XCTUnwrap(rungs[3].distance),
                          try XCTUnwrap(rungs[2].distance),
                          "every fourth week is a down week")
        XCTAssertGreaterThan(try XCTUnwrap(rungs[4].distance),
                             try XCTUnwrap(rungs[3].distance),
                             "the down week does not consume a step")
        XCTAssertEqual(try XCTUnwrap(rungs[7].distance), 15, accuracy: 0.001,
                       "the last rung IS the milestone")
        XCTAssertEqual(rungs[0].activity, "run", "the subject rides on every rung")
    }

    func testDaysStepOnceEveryTwoWeeksAndThenHold() {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .trainingDaysPerWeek))
        let rungs = rule.rungs(current: GoalTarget(days: 2), target: GoalTarget(days: 4),
                               weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(rungs.compactMap(\.days), [2, 3, 3, 4, 4, 4, 4, 4])
    }

    func testADeloadWeekNeverAdvances() {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .trainingDaysPerWeek))
        let rungs = rule.rungs(current: GoalTarget(days: 2), target: GoalTarget(days: 5),
                               weeks: 6,
                               constraints: LadderConstraints(deloadWeeks: [2]))
        XCTAssertEqual(rungs[2].days, rungs[1].days, "week 3 is a deload; it holds")
    }

    func testBodyWeightClampsIntoItsBandAndLandsOnTheTarget() {
        let rule = RateOfChangeLadderRule()
        // 190 -> 178 in 4 weeks is 1.6 %/wk implied: clamped to the 1 % ceiling,
        // so the ladder falls SHORT and says so by not reaching the target.
        let fast = rule.rungs(current: GoalTarget(bodyWeightLbs: 190),
                              target: GoalTarget(bodyWeightLbs: 178),
                              weeks: 4, constraints: LadderConstraints())
        XCTAssertEqual(fast.count, 4)
        XCTAssertGreaterThan(try XCTUnwrap(fast.last?.bodyWeightLbs), 178,
                             "a clamped ladder does not pretend to arrive")
        XCTAssertEqual(try XCTUnwrap(fast[0].bodyWeightRatePercent), -1.0, accuracy: 0.001)

        // 190 -> 183 in 8 weeks is 0.46 %/wk: inside the band, so the ladder
        // is exactly the athlete's own plan and lands on it.
        let steady = rule.rungs(current: GoalTarget(bodyWeightLbs: 190),
                                target: GoalTarget(bodyWeightLbs: 183),
                                weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(try XCTUnwrap(steady.last?.bodyWeightLbs), 183, accuracy: 0.6)

        let gaining = rule.rungs(current: GoalTarget(bodyWeightLbs: 160),
                                 target: GoalTarget(bodyWeightLbs: 175),
                                 weeks: 8, constraints: LadderConstraints())
        XCTAssertEqual(try XCTUnwrap(gaining[0].bodyWeightRatePercent), 0.5, accuracy: 0.001,
                       "gaining rides the 0.25-0.5 % band, not the loss band")
    }

    func testVolumeWeeksSumToTheMilestoneWithAHalfDeload() {
        let rungs = CumulativeLadderRule().rungs(
            current: GoalTarget(volumeLbs: 0), target: GoalTarget(volumeLbs: 100_000),
            weeks: 8, constraints: LadderConstraints(deloadWeeks: [5]))
        let total = rungs.compactMap(\.volumeLbs).reduce(0, +)
        XCTAssertEqual(total, 100_000, accuracy: 800, "rounding to 100 lb, eight weeks")
        XCTAssertEqual(try XCTUnwrap(rungs[5].volumeLbs) * 2,
                       try XCTUnwrap(rungs[4].volumeLbs), accuracy: 200,
                       "the deload week is half a week")
    }

    func testBenchmarkTimeDescendsAndHoldsThroughADeload() {
        let rungs = DescendingLadderRule().rungs(
            current: GoalTarget(targetSeconds: 3_300),
            target: GoalTarget(routineID: UUID(), targetSeconds: 2_700),
            weeks: 6, constraints: LadderConstraints(deloadWeeks: [3]))
        XCTAssertEqual(rungs.count, 6)
        XCTAssertEqual(rungs[3].targetSeconds, rungs[2].targetSeconds)
        XCTAssertEqual(rungs.last?.targetSeconds, 2_700)
        XCTAssertNotNil(rungs[0].routineID, "the routine rides on every rung")
    }

    func testARuleWithNoMeasuredCurrentStateHoldsTheMilestone() {
        let rule = try XCTUnwrap(LadderRules.rampRule(for: .weeklyDistance))
        let rungs = rule.rungs(current: GoalTarget(), target: GoalTarget(distance: 15),
                               weeks: 4, constraints: LadderConstraints())
        XCTAssertEqual(rungs.compactMap(\.distance), [15, 15, 15, 15],
                       "no floor to climb from is a flat ladder, not a climb out of zero")
    }
```

2. Push; fails to compile.
3. Add `Models/LadderRules+Ramps.swift` and re-point `LadderRules.rule(for:)`.
4. Push; `LadderRuleTests` green.
5. Commit: `feat(goal): the ramp ladder rules — distance, days, sessions, weight, volume, benchmark` + trailer.

### A8 — the strength / rep-strength / muscle read-out — **L**

**File (new):** `GymSyncApp/GymSync/Models/LadderReadout.swift`

**Owner decision 6 in code:** *the strength ladder is the %1RM loading the programming prescribes, never a
cycle imposed on top.* This file is a projection of an already-generated `Program`, not a rule.

```swift
import Foundation

// MARK: - LadderReadout
//
// Spec §3.2 and §3.3. THE LADDER IS A READ-OUT of the block, projected onto
// the goal's metric — "so the ladder and the plan cannot disagree" (§3.1).
//
// PURE, and it takes the `Program` rather than fetching one: the generator is
// deterministic and synchronous, and a projection of it has to be too or the
// tests stop being able to state what the ladder IS.
enum LadderReadout {

    /// Week `k`'s rung for a strength goal: the top working load the block
    /// prescribes for the goal lift's MAIN slot (spec §3.2), which is
    ///     baselineE1RM × percentOfMax(slot) × intensityMultiplier(week k)
    /// and the e1RM that set implies.
    ///
    /// The DELOAD IS A RUNG (§3.2): the wave's lower week appears as the lower
    /// number it is, labelled, rather than smoothed away.
    ///
    /// nil when the block prescribes no `percentOfMax` for the lift — a
    /// bodyweight or explosive main carries none on purpose
    /// (`ProgramGenerator.swift:1657-1665`), and a ladder that invented one
    /// would print a load nobody prescribed.
    static func strengthRungs(program: ProgramGenerator.Program,
                              exerciseID: UUID,
                              baselineE1RMLbs: Decimal,
                              unit: WeightUnit) -> [GoalTarget]? {
        guard let slot = mainSlot(program: program, exerciseID: exerciseID),
              let percent = slot.percentOfMax, percent > 0,
              baselineE1RMLbs > 0 else { return nil }
        let base = NSDecimalNumber(decimal: baselineE1RMLbs).doubleValue * percent / 100

        return program.weeks.map { week in
            let raw = base * week.intensityMultiplier
            let loadLbs = Units.toPounds(
                Units.roundToIncrement(Units.fromPounds(Decimal(raw), to: unit), unit: unit),
                from: unit)
            var target = GoalTarget(exerciseID: exerciseID)
            target.targetWeightLbs = loadLbs
            // The reps the block prescribes for that slot, so the rung can be
            // read as "3 × 5 at 190" rather than as a bare number.
            target.targetReps = slot.repsLow
            return target
        }
    }

    /// A rep-strength rung: the same prescribed loading, but the goal's LOAD is
    /// fixed and the TOP-SET REP TARGET is the rung (spec §2.3, "Rep strength").
    static func repStrengthRungs(program: ProgramGenerator.Program,
                                 exerciseID: UUID,
                                 loadLbs: Decimal,
                                 currentReps: Int,
                                 targetReps: Int) -> [GoalTarget]? {
        guard mainSlot(program: program, exerciseID: exerciseID) != nil,
              targetReps > currentReps, !program.weeks.isEmpty else { return nil }
        let span = Double(targetReps - currentReps)
        let weeks = program.weeks.count
        return program.weeks.enumerated().map { index, week in
            var target = GoalTarget(exerciseID: exerciseID, targetReps: targetReps,
                                    loadLbs: loadLbs)
            let progress = Double(index + 1) / Double(weeks)
            let reps = currentReps + Int((span * progress).rounded())
            // A deload week does not ask for more reps at the same load.
            target.targetReps = week.isDeload
                ? Swift.max(currentReps, reps - 1)
                : reps
            target.targetWeightLbs = loadLbs
            return target
        }
    }

    /// Muscle and Maintenance: the WEEK'S PLANNED EFFECTIVE SETS per group ARE
    /// the rungs (spec §3.3), after `balanceWeeklyVolume`, scaled by the wave's
    /// own `volumeMultiplier` so a deload week reads as the lighter week it is.
    ///
    /// THE ROLLUP IS `MuscleGroup.credit`, not
    /// `ProgramGenerator.weeklyMuscleSets`. Those two accountings differ and
    /// the divergence is a documented open item (global constraint 12); the
    /// strip renders SIX GROUPS with capped secondary credit, and a rung the
    /// strip cannot render is not a rung. The ladder therefore reads the
    /// block's own `sets` through the strip's arithmetic — one number, one
    /// meaning, on both surfaces.
    static func muscleRungs(program: ProgramGenerator.Program,
                            catalog: [UUID: Exercise],
                            groups: [MuscleGroup]) -> [GoalTarget] {
        var perGroup: [MuscleGroup: Double] = [:]
        for day in program.days {
            for exercise in day.exercises where exercise.cardioZone == nil {
                guard let row = catalog[exercise.exerciseID] else { continue }
                let credit = MuscleGroup.credit(primary: row.primaryMuscle,
                                                secondaries: row.secondaryMuscles)
                for (group, share) in credit {
                    perGroup[group, default: 0] += share * Double(exercise.sets)
                }
            }
        }
        let wanted = groups.isEmpty ? MuscleGroup.allCases : groups
        return program.weeks.map { week in
            var targets: [String: Int] = [:]
            for group in wanted {
                let sets = Int(((perGroup[group] ?? 0) * week.volumeMultiplier).rounded())
                if sets > 0 { targets[group.rawValue] = sets }
            }
            return GoalTarget(muscleTargets: targets)
        }
    }

    /// The block's main-slot prescription for one lift, or nil when the block
    /// does not train it as a main. Days are searched in order and the FIRST
    /// main wins — the same lift appearing as an accessory later does not
    /// describe the goal.
    static func mainSlot(program: ProgramGenerator.Program,
                         exerciseID: UUID) -> ProgramGenerator.Exercise? {
        for day in program.days {
            if let match = day.exercises.first(where: {
                $0.exerciseID == exerciseID && $0.isMain && $0.cardioZone == nil
            }) { return match }
        }
        return nil
    }

    /// `LadderConstraints` from the block the generator produced — the deload
    /// and taper weeks every ramp rule has to respect.
    static func constraints(program: ProgramGenerator.Program,
                            unit: WeightUnit) -> LadderConstraints {
        var deloads: Set<Int> = []
        var tapers: Set<Int> = []
        for (index, week) in program.weeks.enumerated() {
            if week.isDeload { deloads.insert(index) }
            if week.volumeMultiplier < 1.0 && !week.isDeload { tapers.insert(index) }
        }
        return LadderConstraints(deloadWeeks: deloads, taperWeeks: tapers, unit: unit)
    }

    /// "3 × 5 at 190" and its implication "≈ 214 e1RM" — spec §3.2's own
    /// wording, built once so the ladder page, the schedule card and Coach's
    /// line cannot spell one rung three ways.
    static func strengthRungText(_ target: GoalTarget, sets: Int,
                                 unit: WeightUnit) -> (text: String, implication: String?) {
        guard let lbs = target.targetWeightLbs, let reps = target.targetReps else {
            return ("—", nil)
        }
        let shown = Units.fromPounds(lbs, to: unit)
        let load = NSDecimalNumber(decimal: shown).intValue
        let text = "\(sets) × \(reps) at \(load)"
        let implied = StatMath.estimatedOneRepMax(weight: lbs, reps: reps)
        let impliedShown = NSDecimalNumber(
            decimal: Units.fromPounds(implied, to: unit)).intValue
        return (text, "≈ \(impliedShown) e1RM")
    }
}
```

**Interfaces** — *consumes:* `ProgramGenerator.Program` / `.Week` / `.Exercise`
(`ProgramGenerator.swift:290-310`), `MuscleGroup.credit`, `StatMath.estimatedOneRepMax`
(`StatMath.swift:125`), `Units.fromPounds` / `.toPounds` / `.roundToIncrement`.
*Produces:* `LadderReadout` and its six statics; A9, A12 and B5 call them.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/LadderReadoutTests.swift`. Build the `Program` by hand rather than
   running the generator: this tests the projection, not the pipeline.

```swift
import XCTest
@testable import GymSync

final class LadderReadoutTests: XCTestCase {

    private let bench = UUID()

    /// A catalog row, built on the real initializer — the same private-helper
    /// idiom `WeeklyGoalProgressTests:18-25` uses. There is no shared
    /// `Exercise.fixture` in this repo and this task does not add one.
    private func exercise(_ id: UUID, primaryMuscle: String,
                          secondaryMuscles: [String]) -> Exercise {
        Exercise(id: id, name: "Bench Press", slug: "bench-press",
                 category: "compound", primaryMuscle: primaryMuscle,
                 secondaryMuscles: secondaryMuscles, equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private func program(weeks: [ProgramGenerator.Week],
                         percentOfMax: Double? = 80,
                         sets: Int = 3, repsLow: Int = 5) -> ProgramGenerator.Program {
        let exercise = ProgramGenerator.Exercise(
            exerciseID: bench, name: "Bench Press", sets: sets,
            repsLow: repsLow, repsHigh: repsLow + 3, restSeconds: 180,
            percentOfMax: percentOfMax, isMain: true)
        return ProgramGenerator.Program(days: [.init(name: "Push A", exercises: [exercise])],
                                        weeks: weeks, notes: [])
    }

    private func wave(_ count: Int, deloadAt: Int? = nil) -> [ProgramGenerator.Week] {
        (0..<count).map { index in
            .init(number: index + 1,
                  volumeMultiplier: index == deloadAt ? 0.5 : 1.0,
                  intensityMultiplier: index == deloadAt
                      ? 0.95 : 1.0 + Double(index) / Double(max(1, count - 1)) * 0.05,
                  isDeload: index == deloadAt,
                  note: nil)
        }
    }

    func testStrengthRungsAreThePrescribedLoadingAndTheDeloadIsARung() throws {
        let rungs = try XCTUnwrap(LadderReadout.strengthRungs(
            program: program(weeks: wave(8, deloadAt: 5)),
            exerciseID: bench, baselineE1RMLbs: 250, unit: .lbs))
        XCTAssertEqual(rungs.count, 8)
        // week 1 = 250 × 80 % × 1.0 = 200, rounded to the 5 lb grid
        XCTAssertEqual(try XCTUnwrap(rungs[0].targetWeightLbs), 200)
        XCTAssertLessThan(try XCTUnwrap(rungs[5].targetWeightLbs),
                          try XCTUnwrap(rungs[4].targetWeightLbs),
                          "the wave's deload appears as the lower rung it is")
        XCTAssertEqual(rungs[0].targetReps, 5, "the rung carries the prescribed reps")
    }

    func testAMainWithNoPercentOfMaxHasNoStrengthLadder() {
        XCTAssertNil(LadderReadout.strengthRungs(
            program: program(weeks: wave(4), percentOfMax: nil),
            exerciseID: bench, baselineE1RMLbs: 250, unit: .lbs),
            "a bodyweight main carries no %1RM, and the ladder does not invent one")
    }

    func testALiftTheBlockDoesNotTrainAsAMainHasNoLadder() {
        XCTAssertNil(LadderReadout.strengthRungs(
            program: program(weeks: wave(4)), exerciseID: UUID(),
            baselineE1RMLbs: 250, unit: .lbs))
    }

    func testRepStrengthClimbsRepsAtAFixedLoadAndEasesOnADeload() throws {
        let rungs = try XCTUnwrap(LadderReadout.repStrengthRungs(
            program: program(weeks: wave(6, deloadAt: 3)),
            exerciseID: bench, loadLbs: 225, currentReps: 5, targetReps: 10))
        XCTAssertEqual(rungs.count, 6)
        XCTAssertEqual(rungs.last?.targetReps, 10)
        XCTAssertEqual(try XCTUnwrap(rungs[0].targetWeightLbs), 225,
                       "the load is fixed; the reps are the rung")
        XCTAssertLessThanOrEqual(try XCTUnwrap(rungs[3].targetReps),
                                 try XCTUnwrap(rungs[2].targetReps))
    }

    func testMuscleRungsScaleWithTheWavesVolumeMultiplier() throws {
        let catalog = [bench: exercise(bench, primaryMuscle: "chest",
                                       secondaryMuscles: ["triceps"])]
        let rungs = LadderReadout.muscleRungs(
            program: program(weeks: wave(4, deloadAt: 2), sets: 4),
            catalog: catalog, groups: [.chest, .arms])
        XCTAssertEqual(rungs.count, 4)
        XCTAssertEqual(rungs[0].muscleTargets?["chest"], 4, "4 sets, full primary credit")
        XCTAssertEqual(rungs[0].muscleTargets?["arms"], 2, "0.5 secondary credit × 4 sets")
        XCTAssertEqual(rungs[2].muscleTargets?["chest"], 2, "the deload halves the week")
    }

    func testConstraintsCarryTheWavesDeloadAndTaper() {
        var weeks = wave(8, deloadAt: 5)
        weeks[7].volumeMultiplier = 0.5      // the strength taper
        let constraints = LadderReadout.constraints(
            program: program(weeks: weeks), unit: .lbs)
        XCTAssertEqual(constraints.deloadWeeks, [5])
        XCTAssertEqual(constraints.taperWeeks, [7])
    }

    func testRungTextIsSpelledOnceForEverySurface() {
        let (text, implication) = LadderReadout.strengthRungText(
            GoalTarget(targetWeightLbs: 190, targetReps: 5), sets: 3, unit: .lbs)
        XCTAssertEqual(text, "3 × 5 at 190")
        XCTAssertEqual(implication, "≈ 214 e1RM")
    }
}
```

2. Push; fails to compile.
3. Add `Models/LadderReadout.swift`.
4. Push; green. If `≈ 214 e1RM` is off by a pound, **change the test to the number `StatMath` actually
   produces** and say so in the commit body — the Epley constant is the authority, not the spec's prose.
5. Commit: `feat(goal): the ladder read-out — strength, rep strength and muscle rungs from the block` + trailer.

### A9 — adaptive re-laddering — **L**

**File (new):** `GymSyncApp/GymSync/Models/LadderMath.swift`

Owner decision 8, option 1: **Coach re-ladders from actuals weekly; the milestone and its date belong to the
athlete; Coach proposes date moves and never makes them.**

```swift
import Foundation

// MARK: - LadderMath
//
// Spec §3.5 (adaptive re-laddering), §4 (materialisation) and §6 (standing).
// PURE — the repository fetches, this decides.
//
// THE TWO LAWS THIS FILE ENFORCES:
//   1. re-laddering rewrites ONLY rungs whose status is `ahead` or `current`
//      (spec §8), so a missed week and an overridden week stay visible after
//      the ladder moves;
//   2. the milestone and its date are NEVER moved here. When the re-derived
//      ladder can no longer reach the milestone, `standing` says so and Coach
//      PROPOSES through the shipped propose channel — it does not write.
enum LadderMath {

    /// Mark each rung against the week it describes and what was measured.
    ///
    /// `met` is decided by the metric's own direction: a benchmark TIME is met
    /// by going lower, everything else by going higher. Getting that backwards
    /// would paint a whole ladder green for an athlete who got slower.
    static func statuses(rungs: [LadderRung], metric: GoalMetric,
                         measuredByWeek: [String: GoalTarget],
                         currentWeekStart: String,
                         overriddenWeeks: Set<String> = []) -> [LadderRung] {
        rungs.map { rung in
            var updated = rung
            if overriddenWeeks.contains(rung.weekStartString) {
                updated.status = .overridden
                return updated
            }
            if let measured = measuredByWeek[rung.weekStartString],
               reached(metric: metric, measured: measured, target: rung.target) {
                updated.status = .met
                return updated
            }
            if rung.weekStartString == currentWeekStart {
                updated.status = .current
            } else if rung.weekStartString < currentWeekStart {
                updated.status = .missed
            } else {
                updated.status = .ahead
            }
            return updated
        }
    }

    /// Did `measured` reach `target` for this metric?
    static func reached(metric: GoalMetric, measured: GoalTarget,
                        target: GoalTarget) -> Bool {
        switch metric {
        case .benchmarkTime:
            guard let want = target.targetSeconds, let got = measured.targetSeconds
            else { return false }
            return got <= want                     // lower is better
        case .bodyWeight:
            guard let want = target.bodyWeightLbs, let got = measured.bodyWeightLbs
            else { return false }
            // Direction comes from the goal, not from the number: a cut is met
            // by going under, a gain by going over. `bodyWeightRatePercent` is
            // signed by the rule that wrote the rung (A7).
            let losing = (target.bodyWeightRatePercent ?? 0) < 0
            return losing ? got <= want : got >= want
        case .weeklyMuscleSets:
            let wanted = target.muscleTargets ?? [:]
            let got = measured.muscleTargets ?? [:]
            guard !wanted.isEmpty else { return false }
            return wanted.allSatisfy { (got[$0.key] ?? 0) >= $0.value }
        case .liftOneRepMax:
            return compare(measured.targetWeightLbs, target.targetWeightLbs)
        case .liftRepsAtLoad:
            guard let want = target.targetReps, let got = measured.targetReps
            else { return false }
            return got >= want
        case .weeklyDistance:
            return compare(measured.distance, target.distance)
        case .trainingDaysPerWeek:
            return compare(measured.days, target.days)
        case .sessionsOfTypePerWeek:
            return compare(measured.sessions, target.sessions)
        case .lissMinutesPerWeek:
            return compare(measured.lissMinutes, target.lissMinutes)
        case .stretchingExercisesPerWeek:
            return compare(measured.stretchingExercises, target.stretchingExercises)
        case .cumulativeVolume:
            return compare(measured.volumeLbs, target.volumeLbs)
        }
    }

    private static func compare<T: Comparable>(_ measured: T?, _ target: T?) -> Bool {
        guard let target, let measured else { return false }
        return measured >= target
    }

    /// Re-derive the remaining rungs from `current` — the MEASURED state, not
    /// last week's rung (spec §3.5: "a missed week does not leave a hole to
    /// catch up; the ladder moves").
    ///
    /// Only `ahead` and `current` rungs are replaced. The rungs already met,
    /// missed or overridden are returned exactly as they came in, which is
    /// what makes the ladder page a record of the climb rather than a rolling
    /// forecast that erases its own history.
    static func reLadder(existing: Ladder, metric: GoalMetric,
                         current: GoalTarget, milestone: GoalTarget,
                         constraints: LadderConstraints,
                         rule: any LadderRule,
                         derivedAt: Date) -> Ladder {
        let mutable = existing.rungs.filter { $0.status == .ahead || $0.status == .current }
        guard !mutable.isEmpty else { return existing }

        let fresh = rule.rungs(current: current, target: milestone,
                               weeks: mutable.count, constraints: constraints)
        var byWeek: [String: GoalTarget] = [:]
        for (rung, target) in zip(mutable, fresh) {
            byWeek[rung.weekStartString] = target
        }
        var out = existing
        out.derivedAt = derivedAt
        out.rungs = existing.rungs.map { rung in
            guard let replacement = byWeek[rung.weekStartString] else { return rung }
            var updated = rung
            updated.target = replacement
            return updated
        }
        return out
    }
}
```

**Interfaces** — *consumes:* `Ladder`, `LadderRung`, `GoalMetric`, `GoalTarget`, `LadderRule`,
`LadderConstraints`. *Produces:* `LadderMath.statuses(...)`, `.reached(...)`, `.reLadder(...)`; A11 and A12
call them.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/LadderMathTests.swift`:

```swift
import XCTest
@testable import GymSync

final class LadderMathTests: XCTestCase {

    private func ladder(_ statuses: [RungStatus]) -> Ladder {
        Ladder(goalID: UUID(),
               rungs: statuses.enumerated().map { index, status in
                   .init(weekIndex: index,
                         weekStartString: String(format: "2026-09-%02d", 6 + index * 7),
                         target: GoalTarget(days: 3), status: status)
               },
               derivedAt: Date(timeIntervalSince1970: 0))
    }

    func testLowerIsBetterForABenchmarkAndHigherForEverythingElse() {
        XCTAssertTrue(LadderMath.reached(metric: .benchmarkTime,
                                         measured: GoalTarget(targetSeconds: 2_650),
                                         target: GoalTarget(targetSeconds: 2_700)))
        XCTAssertFalse(LadderMath.reached(metric: .benchmarkTime,
                                          measured: GoalTarget(targetSeconds: 2_750),
                                          target: GoalTarget(targetSeconds: 2_700)))
        XCTAssertTrue(LadderMath.reached(metric: .liftOneRepMax,
                                         measured: GoalTarget(targetWeightLbs: 230),
                                         target: GoalTarget(targetWeightLbs: 225)))
    }

    func testACutIsMetByGoingUnderAndAGainByGoingOver() {
        let cut = GoalTarget(bodyWeightLbs: 178, bodyWeightRatePercent: -0.75)
        XCTAssertTrue(LadderMath.reached(metric: .bodyWeight,
                                         measured: GoalTarget(bodyWeightLbs: 177), target: cut))
        XCTAssertFalse(LadderMath.reached(metric: .bodyWeight,
                                          measured: GoalTarget(bodyWeightLbs: 180), target: cut))
        let gain = GoalTarget(bodyWeightLbs: 175, bodyWeightRatePercent: 0.4)
        XCTAssertTrue(LadderMath.reached(metric: .bodyWeight,
                                         measured: GoalTarget(bodyWeightLbs: 176), target: gain))
    }

    func testAPastWeekWithNoReadingIsMissedAndTheCurrentOneIsCurrent() {
        let marked = LadderMath.statuses(
            rungs: ladder([.ahead, .ahead, .ahead]).rungs,
            metric: .trainingDaysPerWeek,
            measuredByWeek: ["2026-09-06": GoalTarget(days: 3)],
            currentWeekStart: "2026-09-13")
        XCTAssertEqual(marked.map(\.status), [.met, .current, .ahead])
    }

    func testAnOverriddenWeekStaysOverriddenEvenWhenItWasMet() {
        let marked = LadderMath.statuses(
            rungs: ladder([.ahead, .ahead]).rungs,
            metric: .trainingDaysPerWeek,
            measuredByWeek: ["2026-09-06": GoalTarget(days: 9)],
            currentWeekStart: "2026-09-13",
            overriddenWeeks: ["2026-09-06"])
        XCTAssertEqual(marked[0].status, .overridden,
                       "the athlete's own edit is the record of that week")
    }

    func testReLadderRewritesOnlyAheadAndCurrentRungs() {
        let existing = ladder([.met, .missed, .overridden, .current, .ahead, .ahead])
        let out = LadderMath.reLadder(
            existing: existing, metric: .trainingDaysPerWeek,
            current: GoalTarget(days: 2), milestone: GoalTarget(days: 5),
            constraints: LadderConstraints(),
            rule: StepEveryNWeeksLadderRule(step: 1, everyWeeks: 1,
                                            read: { $0.days }, write: { $0.days = $1 }),
            derivedAt: Date(timeIntervalSince1970: 100))

        XCTAssertEqual(out.rungs[0].target.days, 3, "a met week is history, untouched")
        XCTAssertEqual(out.rungs[1].target.days, 3, "a missed week stays visible")
        XCTAssertEqual(out.rungs[2].target.days, 3, "an override is the athlete's")
        XCTAssertEqual(out.rungs[3].target.days, 3, "current is re-derived: 2 + 1")
        XCTAssertEqual(out.rungs[4].target.days, 4)
        XCTAssertEqual(out.rungs[5].target.days, 5)
        XCTAssertEqual(out.rungs.map(\.status), existing.rungs.map(\.status),
                       "re-laddering moves TARGETS, never statuses")
        XCTAssertEqual(out.derivedAt, Date(timeIntervalSince1970: 100))
    }

    func testAFullyClosedLadderIsReturnedUnchanged() {
        let closed = ladder([.met, .missed, .overridden])
        let out = LadderMath.reLadder(
            existing: closed, metric: .trainingDaysPerWeek,
            current: GoalTarget(days: 2), milestone: GoalTarget(days: 5),
            constraints: LadderConstraints(), rule: HoldLadderRule(),
            derivedAt: Date(timeIntervalSince1970: 100))
        XCTAssertEqual(out, closed, "nothing left to move")
    }
}
```

2. Push; fails to compile.
3. Add `Models/LadderMath.swift`.
4. Push; green.
5. Commit: `feat(goal): adaptive re-laddering — statuses, reach, and rewrite-ahead-only` + the trailer.

### A10 — the current rung becomes the week's goal — **M**

**File:** `GymSyncApp/GymSync/Models/LadderMath.swift` (extend).

Spec §4's mapping table, in code. This is the seam where the block system meets the shipped weekly one.

```swift
extension LadderMath {

    /// Spec §4: the shipped weekly goal IS the materialised current rung.
    ///
    /// `source = .coach` on purpose and by rule: this is a Coach write, which
    /// `WeeklyGoalWriteRule.shouldOverwrite` permits over no row and over
    /// Coach's own — and refuses over a row the athlete set, which is exactly
    /// the rung-override the design wants (§4: "an athlete's edit of this
    /// week's row is an override of the rung").
    ///
    /// nil when the metric has no weekly shape — there is none in phase 1, and
    /// the `nil` return exists so phase 2's `vo2Max` (a test day, not a week)
    /// has somewhere honest to land.
    static func weeklyGoal(from rung: LadderRung, goal: BlockGoal,
                           userID: UUID, now: Date) -> WeeklyGoal? {
        var params = WeeklyGoalParams()
        params.goalID = goal.id
        params.byDate = goal.byDate
        let kind: WeeklyGoalKind

        switch goal.metric {
        case .liftOneRepMax:
            kind = .lift
            params.exerciseID = rung.target.exerciseID ?? goal.target.exerciseID
            params.targetWeightLbs = rung.target.targetWeightLbs
        case .liftRepsAtLoad:
            kind = .lift
            params.exerciseID = rung.target.exerciseID ?? goal.target.exerciseID
            params.targetWeightLbs = rung.target.loadLbs ?? goal.target.loadLbs
            params.targetReps = rung.target.targetReps
        case .weeklyMuscleSets:
            kind = .muscleSets
            params.muscleTargets = rung.target.muscleTargets
            // Where the number came from, for the strip's own provenance —
            // "block" is a third value beside the shipped "titration" and
            // "routines", and it is the truthful one here: this target is the
            // block's prescribed volume, not the search's and not a template's.
            params.targetSource = "block"
        case .weeklyDistance:
            kind = .distance
            params.activity = rung.target.activity ?? goal.target.activity
            params.distanceTarget = rung.target.distance
        case .trainingDaysPerWeek:
            // NO `count` (the controller's 2026-09-06 ruling, which
            // `WeeklyGoalDetector.daysParams` records): the profile's weekly
            // session goal is the single source of truth for this number, and a
            // mirror in `params` is precisely how the strip and the streak tile
            // would come to disagree. The rung's own days number reaches the
            // athlete through the ladder page, not through this row.
            kind = .days
        case .sessionsOfTypePerWeek:
            kind = .sessionsOfType
            params.sessionType = rung.target.sessionType ?? goal.target.sessionType
            params.count = rung.target.sessions
        case .stretchingExercisesPerWeek, .lissMinutesPerWeek:
            // ONE goal, two metrics (spec §2.3). Whichever of the pair the goal
            // names, the row carries both numbers, because the strip renders
            // them on one rung.
            kind = .recovery
            params.count = rung.target.stretchingExercises
            params.lissMinutes = rung.target.lissMinutes
        case .bodyWeight:
            kind = .bodyWeight
            params.bodyWeightLbs = rung.target.bodyWeightLbs
        case .cumulativeVolume:
            kind = .volume
            params.volumeLbs = rung.target.volumeLbs
        case .benchmarkTime:
            kind = .benchmark
            params.routineID = rung.target.routineID ?? goal.target.routineID
            params.targetSeconds = rung.target.targetSeconds
        }

        return WeeklyGoal(userID: userID, weekStartString: rung.weekStartString,
                          kind: kind, params: params, source: .coach, setAt: now)
    }

    /// The rung for a week, or nil when the block does not cover it.
    static func rung(in ladder: Ladder, weekStart: String) -> LadderRung? {
        ladder.rungs.first { $0.weekStartString == weekStart }
    }
}
```

**Interfaces** — *consumes:* `LadderRung`, `BlockGoal`, `WeeklyGoal`, `WeeklyGoalParams`, `WeeklyGoalKind`.
*Produces:* `LadderMath.weeklyGoal(from:goal:userID:now:)`, `.rung(in:weekStart:)`; A11's
`materialiseRung` calls them.

**TDD steps.**

1. Failing test — append to `LadderMathTests.swift`:

```swift
    private func blockGoal(_ metric: GoalMetric, target: GoalTarget) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(), metric: metric,
                  target: target, byDate: nil, preset: nil, source: .user,
                  outcome: nil, outcomeValue: nil,
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    private func rung(_ target: GoalTarget) -> LadderRung {
        .init(weekIndex: 2, weekStartString: "2026-09-06", target: target, status: .current)
    }

    func testEveryPhaseOneMetricMaterialisesIntoARow() throws {
        let userID = UUID()
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let routineID = UUID(), exerciseID = UUID()

        let cases: [(GoalMetric, GoalTarget, WeeklyGoalKind)] = [
            (.liftOneRepMax, GoalTarget(exerciseID: exerciseID, targetWeightLbs: 200), .lift),
            (.liftRepsAtLoad, GoalTarget(exerciseID: exerciseID, targetReps: 8,
                                         loadLbs: 225), .lift),
            (.weeklyMuscleSets, GoalTarget(muscleTargets: ["chest": 12]), .muscleSets),
            (.weeklyDistance, GoalTarget(activity: "run", distance: 12), .distance),
            (.trainingDaysPerWeek, GoalTarget(days: 4), .days),
            (.sessionsOfTypePerWeek, GoalTarget(sessionType: "hiit", sessions: 3),
             .sessionsOfType),
            (.stretchingExercisesPerWeek, GoalTarget(lissMinutes: 120,
                                                     stretchingExercises: 6), .recovery),
            (.lissMinutesPerWeek, GoalTarget(lissMinutes: 150,
                                             stretchingExercises: 4), .recovery),
            (.bodyWeight, GoalTarget(bodyWeightLbs: 183), .bodyWeight),
            (.cumulativeVolume, GoalTarget(volumeLbs: 12_500), .volume),
            (.benchmarkTime, GoalTarget(routineID: routineID, targetSeconds: 2_800),
             .benchmark),
        ]

        for (metric, target, expected) in cases {
            let goal = blockGoal(metric, target: target)
            let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                          userID: userID, now: now))
            XCTAssertEqual(row.kind, expected, "\(metric.rawValue)")
            XCTAssertEqual(row.source, .coach,
                           "materialisation is a Coach write — WeeklyGoalWriteRule governs it")
            XCTAssertEqual(row.params.goalID, goal.id, "the row knows its ladder")
            XCTAssertEqual(row.weekStartString, "2026-09-06")
        }
    }

    func testADaysRungWritesNoCountMirror() throws {
        let goal = blockGoal(.trainingDaysPerWeek, target: GoalTarget(days: 4))
        let row = try XCTUnwrap(LadderMath.weeklyGoal(
            from: rung(GoalTarget(days: 4)), goal: goal, userID: UUID(),
            now: Date(timeIntervalSince1970: 0)))
        XCTAssertNil(row.params.count,
                     "profiles.weekly_session_goal is the single source of truth for days")
    }

    func testRecoveryCarriesBothNumbersOnOneRow() throws {
        let target = GoalTarget(lissMinutes: 120, stretchingExercises: 6)
        let goal = blockGoal(.stretchingExercisesPerWeek, target: target)
        let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                      userID: UUID(),
                                                      now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(row.params.count, 6)
        XCTAssertEqual(row.params.lissMinutes, 120)
    }

    func testMuscleRungsRecordTheirProvenanceAsTheBlock() throws {
        let target = GoalTarget(muscleTargets: ["chest": 12])
        let goal = blockGoal(.weeklyMuscleSets, target: target)
        let row = try XCTUnwrap(LadderMath.weeklyGoal(from: rung(target), goal: goal,
                                                      userID: UUID(),
                                                      now: Date(timeIntervalSince1970: 0)))
        XCTAssertEqual(row.params.targetSource, "block")
    }
```

2. Push; fails.
3. Add the extension.
4. Push; green.
5. Commit: `feat(goal): materialise the current rung into weekly_goals` + the trailer.

### A11 — `LiveBlockGoalRepository` — **L**

**File (new):** `GymSyncApp/GymSync/Models/BlockGoalLiveRepository.swift`

Its own file, for the reason `WeeklyGoalLiveRepository.swift:9-13` gives: `Models/BlockGoal.swift` is the
frozen interface three streams read, and keeping the persistence out of it keeps that file untouched for the
whole parallel build.

**Shape** (write it against `LiveWeeklyGoalRepository` as the template — same idioms, same error posture):

- `private struct BlockGoalRow: Codable` with `CodingKeys` mapping snake_case columns
  (`user_id`, `enrollment_id`, `by_date`, `outcome_value`, `created_at`, `updated_at`) and a `var model:
  BlockGoal?` that returns nil for an unknown `metric`/`preset`/`source` — the forward-compatibility guard
  `WeeklyGoalRow.model` sets, and the reason A1's header can leave `metric` un-CHECKed.
- **`by_date` is a raw DATE string**, never a `Date` (`ProgramEnrollment.swift:34-36`). Store it as
  `String?` on the row and convert with `WeekMath.date(fromWeekStartString:)` /
  `SessionSeries.dayString(for:in:)`. This is the single most likely defect in the whole stream.
- `private struct RungRow: Codable` likewise, with `week_start` as a String.
- `activeGoal()` → `ProgramRepository.active()`, then `.from("block_goals").eq("enrollment_id", …).limit(1)`.
- `ladder(goalID:)` → `.from("block_goal_rungs").eq("goal_id", …).order("week_index", ascending: true)`.
- `save(_:)` stamps `source = .user` (the milestone belongs to the athlete) and upserts on `id`.
- `reLadder(goalID:)` → read the goal, read the ladder, read the actuals, call `LadderMath.statuses` then
  `LadderMath.reLadder`, then **upsert only the changed rungs** on `(goal_id, week_index)`.
- `materialiseRung(goalID:weekStart:)` → `LadderMath.rung(in:weekStart:)` →
  `LadderMath.weeklyGoal(from:goal:userID:now:)` → **consult `WeeklyGoalWriteRule.shouldOverwrite` against the
  existing `weekly_goals` row**, then write through `LiveWeeklyGoalRepository`. It must **not** open a second
  write path into `weekly_goals`: `LiveWeeklyGoalRepository.upsert` is `private` on purpose
  (`WeeklyGoalLiveRepository.swift:174-179`), so this task adds **one** internal method there —
  `writeMaterialisedRung(_ goal: WeeklyGoal) async -> Bool` — whose doc comment states that it is the ladder's
  only door and that the caller has already consulted the write rule.
- `page(goalID:)` → task A12.

**The actuals read**, per metric, so a `days` goal does not page the 1,300-row exercise catalog — the same
"only what this kind needs" discipline `LiveWeeklyGoalRepository.progress(for:)` documents at :339-341.

**Interfaces** — *consumes:* every A5–A10 pure function, `ProgramRepository.active()`,
`SessionRepository.history` / `.upcoming` / `.exerciseHistory`, `BodyWeightLogRepository.recent`,
`ExerciseRepository.fetchAll`, `RoutineRepository.fetchAll` / `.exercisesForRoutines`,
`HealthKitBridge.lissMinutes`, `WeeklyGoalWriteRule.shouldOverwrite`, `ThemeStore.shared.weightUnit`
(read via `await MainActor.run`, as `LiveWeeklyGoalRepository.detect` does at :217).
*Produces:* `LiveBlockGoalRepository: BlockGoalRepository`, and
`LiveWeeklyGoalRepository.writeMaterialisedRung(_:)`.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/BlockGoalLiveRepositoryTests.swift`, in the live-DB idiom
   (global constraint 6). **Every row is 2099-dated and every deletion is registered before the write.**

```swift
import XCTest
@testable import GymSync

/// `LiveBlockGoalRepository` against the real `block_goals` /
/// `block_goal_rungs` tables, in the repo's live-DB idiom
/// (`WeeklyGoalLiveRepositoryTests`' header states it in full):
/// `TestAuth.signInIfConfigured()` skips when secrets are placeholders, every
/// test registers its cleanup with `addTeardownBlock` BEFORE it writes, and
/// every date is far-future so nothing here can reach a screenshot.
final class BlockGoalLiveRepositoryTests: XCTestCase {

    private let repository = LiveBlockGoalRepository()

    /// Registers the delete first, then hands back the id to write against.
    /// `block_goal_rungs` cascades from the goal, so one delete cleans both.
    private func temporaryGoal(_ id: UUID) -> UUID {
        let repository = self.repository
        addTeardownBlock { await repository.deleteGoal(id: id) }
        return id
    }

    func testAGoalAndItsRungsRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let userID = await SupabaseService.shared.currentUserID()
        let owner = try XCTUnwrap(userID)          // never XCTUnwrap(await …)
        let enrollment = await ProgramRepository.activeOrNil()
        try XCTSkipIf(enrollment == nil, "no active block on the CI account")
        let block = try XCTUnwrap(enrollment)

        let goalID = temporaryGoal(UUID())
        let goal = BlockGoal(
            id: goalID, userID: owner, enrollmentID: block.id, metric: .liftOneRepMax,
            target: GoalTarget(exerciseID: UUID(), targetWeightLbs: 225),
            byDate: Date(timeIntervalSince1970: 4_070_000_000),   // 2099
            preset: .strength, source: .user, outcome: nil, outcomeValue: nil,
            createdAt: Date(), updatedAt: Date())

        XCTAssertTrue(await repository.save(goal))
        let read = await repository.goal(id: goalID)
        XCTAssertEqual(read?.target.targetWeightLbs, 225)
        XCTAssertEqual(read?.metric, .liftOneRepMax)
        XCTAssertEqual(read?.source, .user, "save stamps the athlete")
        XCTAssertEqual(read?.byDate?.timeIntervalSince1970,
                       Date(timeIntervalSince1970: 4_070_000_000).timeIntervalSince1970,
                       accuracy: 86_400,
                       "a DATE column round trips through the day string, not the timestamp decoder")

        let ladder = Ladder(goalID: goalID, rungs: [
            .init(weekIndex: 0, weekStartString: "2099-01-04",
                  target: GoalTarget(targetWeightLbs: 190), status: .met),
            .init(weekIndex: 1, weekStartString: "2099-01-11",
                  target: GoalTarget(targetWeightLbs: 195), status: .current),
        ], derivedAt: Date())
        XCTAssertTrue(await repository.saveLadder(ladder))
        let back = await repository.ladder(goalID: goalID)
        XCTAssertEqual(back?.rungs.count, 2)
        XCTAssertEqual(back?.rungs.first?.weekStartString, "2099-01-04")
        XCTAssertEqual(back?.rungs.first?.status, .met)
    }

    func testASecondGoalForTheSameBlockIsRefused() async throws {
        try await TestAuth.signInIfConfigured()
        // ... same fixture; the second `save` returns false rather than throwing,
        // because `UNIQUE (enrollment_id)` is owner decision 2 in the database.
    }
}
```

2. Push; fails to compile.
3. Implement `LiveBlockGoalRepository` (plus the internal `goal(id:)`, `saveLadder(_:)` and `deleteGoal(id:)`
   the tests need — each with a doc comment saying it is internal **only** because the teardown needs it, the
   posture `LiveWeeklyGoalRepository.deleteRow` states at :149-157).
4. Push; green (or skipped on a runner with placeholder secrets, which is a pass).
5. Commit: `feat(goal): LiveBlockGoalRepository — goals, rungs, re-laddering, materialisation` + the trailer.

### A12 — the ladder page's model — **M**

**File:** `GymSyncApp/GymSync/Models/LadderMath.swift` (extend) and `BlockGoalLiveRepository.swift`
(`page(goalID:)`).

Builds `LadderPageModel` — the headline, the date line, Coach's line on standing, and one `LadderRow` per
rung. **This is the only place the ladder's words are chosen**, so the page, the schedule card and Coach's
line cannot spell one rung three ways.

Copy, from the spec, verbatim where it gives it:

| element | copy |
|---|---|
| headline, a lift | `Bench 225 by Oct 18` — `{lift} {load} by {MMM d}` |
| headline, muscle | `12 chest sets a week` |
| headline, held-for-the-block | `Hold the recommended volumes` (Maintenance) · `A recovery block` (Recovery) |
| Coach's line, on track | `On track` |
| Coach's line, behind | `This ladder reaches 218 — move the date?` |
| Coach's line, no date | `Held for the block.` |
| a deload row | the row's status chip reads `DELOAD` |

`reachesMilestone` is `LadderMath.reached(metric:measured:target:)` applied to the **last rung** against the
**milestone**. When it is false, the coach line is the proposal — and **nothing is written**: spec §3.5's whole
point is that Coach proposes and the athlete accepts.

**Interfaces** — *consumes:* `Ladder`, `BlockGoal`, `LadderReadout.strengthRungText`, `Units`, `WeekMath`.
*Produces:*

```swift
    static func page(goal: BlockGoal, ladder: Ladder, liftName: String,
                     rungSets: Int, notesByWeek: [Int: String],
                     deloadWeeks: Set<Int> = [], unit: WeightUnit,
                     now: Date, calendar: Calendar) -> LadderPageModel
```

and `LiveBlockGoalRepository.page(goalID:)` calling it with the block's own `Program.notes` and
`LadderReadout.constraints(program:unit:).deloadWeeks`.

**TDD steps.**

1. Failing test — append to `LadderMathTests.swift`:

```swift
    func testAStrengthPageIsHeadlinedByTheMilestoneItself() {
        let bench = UUID()
        let goal = BlockGoal(
            id: UUID(), userID: UUID(), enrollmentID: UUID(), metric: .liftOneRepMax,
            target: GoalTarget(exerciseID: bench, targetWeightLbs: 225),
            byDate: Date(timeIntervalSince1970: 1_792_411_200),   // 2026-10-18
            preset: .strength, source: .user, outcome: nil, outcomeValue: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0))
        let page = LadderMath.page(
            goal: goal, ladder: StubBlockGoalRepository.fixtureLadder,
            liftName: "Bench", rungSets: 3, notesByWeek: [:], unit: .lbs,
            now: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(page.headline, "Bench 225 by Oct 18")
        XCTAssertEqual(page.rows.count, 8)
        XCTAssertEqual(page.weekCount, 8)
        XCTAssertEqual(page.source, .user)
        XCTAssertEqual(page.coachLine, "On track")
        XCTAssertTrue(page.reachesMilestone)
    }

    func testALadderThatFallsShortSaysSoAndNamesTheNumber() {
        var ladder = StubBlockGoalRepository.fixtureLadder
        ladder.rungs[7].target.targetWeightLbs = 218     // the spec's own example
        let goal = BlockGoal(
            id: ladder.goalID, userID: UUID(), enrollmentID: UUID(),
            metric: .liftOneRepMax,
            target: GoalTarget(targetWeightLbs: 225),
            byDate: Date(timeIntervalSince1970: 1_792_411_200), preset: .strength,
            source: .user, outcome: nil, outcomeValue: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0))
        let page = LadderMath.page(
            goal: goal, ladder: ladder, liftName: "Bench", rungSets: 3,
            notesByWeek: [:], unit: .lbs,
            now: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertFalse(page.reachesMilestone)
        XCTAssertTrue(page.coachLine.contains("218"),
                      "the ladder never lies about the gap")
    }

    func testAHeldForTheBlockGoalHasNoDateLine() {
        let goal = BlockGoal(
            id: UUID(), userID: UUID(), enrollmentID: UUID(),
            metric: .weeklyMuscleSets,
            target: GoalTarget(muscleTargets: ["chest": 12, "back": 14]),
            byDate: nil, preset: .maintenance, source: .coach,
            outcome: nil, outcomeValue: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0))
        let page = LadderMath.page(
            goal: goal, ladder: StubBlockGoalRepository.fixtureLadder,
            liftName: "", rungSets: 3, notesByWeek: [:], unit: .lbs,
            now: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(page.dateLine, "")
        XCTAssertEqual(page.coachLine, "Held for the block.")
    }

    func testADeloadRungCarriesItsFlagAndTheGeneratorsOwnNote() {
        var ladder = StubBlockGoalRepository.fixtureLadder
        ladder.rungs[5].status = .ahead
        let goal = BlockGoal(
            id: ladder.goalID, userID: UUID(), enrollmentID: UUID(),
            metric: .liftOneRepMax, target: GoalTarget(targetWeightLbs: 225),
            byDate: nil, preset: .strength, source: .coach,
            outcome: nil, outcomeValue: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 0))
        let page = LadderMath.page(
            goal: goal, ladder: ladder, liftName: "Bench", rungSets: 2,
            notesByWeek: [5: "Deload — move fast, leave fresh."],
            deloadWeeks: [5], unit: .lbs,
            now: Date(timeIntervalSince1970: 1_789_000_000),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertTrue(page.rows[5].isDeload)
        XCTAssertEqual(page.rows[5].note, "Deload — move fast, leave fresh.")
        XCTAssertEqual(page.rows.filter(\.isDeload).count, 1)
    }
```

2. Push; fails to compile.
3. Implement `LadderMath.page(goal:ladder:liftName:rungSets:notesByWeek:deloadWeeks:unit:now:calendar:)` and
   `LiveBlockGoalRepository.page(goalID:)` calling it with the block's own `Program.notes` and
   `LadderReadout.constraints(program:unit:).deloadWeeks`.
4. Push; green.
5. Commit: `feat(goal): the ladder page's model — headline, standing, and one row per rung` + the trailer.

### A13 — existing enrollments get a Coach-detected goal — **M**

**File:** `GymSyncApp/GymSync/Models/BlockGoalLiveRepository.swift` (extend).

Spec §5.4: *"Existing enrollments without a goal get a Coach-detected one on first Home load, derived from the
enrollment's `focus` and `baseline` the way Home already fills an empty week."*

```swift
extension LiveBlockGoalRepository {

    /// Derive and persist a goal for a block that predates goals.
    ///
    /// Mirrors `LiveWeeklyGoalRepository.detectIfMissing` exactly — the read
    /// happens, the rule decides, one attempt is made and the caller moves on —
    /// so an offline launch renders the block without a ladder and retries next
    /// refresh rather than looping.
    ///
    /// `source = .coach`, which is what makes the athlete's later edit on the
    /// ladder page an override Coach must respect (owner decision 8).
    ///
    /// The derivation is the enrollment's own evidence and nothing else:
    ///   * `focus.exerciseIDs.first` WITH a `baseline` → `liftOneRepMax`,
    ///     target `baseline × 1.05` rounded in the athlete's unit — the same
    ///     step `WeeklyGoalDetector.liftTarget` takes, called rather than
    ///     re-derived;
    ///   * `focus.muscleGroup` → `weeklyMuscleSets` for that group, target from
    ///     `volume_targets` when the titration has a row and from the block's
    ///     own prescribed sets otherwise (`LadderReadout.muscleRungs`);
    ///   * anything else → `trainingDaysPerWeek` at `Profile.effectiveWeeklyGoal`
    ///     — the same "never returns nil" floor `WeeklyGoalDetector`'s rule 3
    ///     is, for the same reason: a block with no goal is the state this
    ///     function exists to end.
    /// `byDate` is the block's end (`WeeklyGoalDetector.blockEnd`), and
    /// `preset` is nil — this goal was not chosen at a door.
    func detectGoalIfMissing(enrollment: ProgramEnrollment) async -> BlockGoal?
}
```

The ladder is derived immediately after and persisted, so a migrated block has rungs on its first Home load
rather than an empty page.

**TDD steps.**

1. The derivation is pure and lives in
   `LadderMath.detectedGoal(enrollment:volumeTargets:effectiveWeeklyGoal:unit:now:calendar:) -> BlockGoalDraft`;
   the repository only fetches and writes. Failing test, appended to `LadderMathTests.swift`:

```swift
    private func enrollment(focus: ProgramFocus, baseline: [String: Double],
                            weeks: Int = 8) -> ProgramEnrollment {
        // `ProgramEnrollment` is Decodable-only — build it through JSON, the
        // way a row arrives, so the test cannot drift from the wire shape.
        let json = """
        {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
         "template_slug":"coach-fixture","focus":\(String(
            data: try! JSONEncoder().encode(focus), encoding: .utf8)!),
         "baseline":\(String(
            data: try! JSONEncoder().encode(baseline), encoding: .utf8)!),
         "started_on":"2026-08-23","weeks":\(weeks),
         "ended_at":null,"ended_reason":null,
         "created_at":"2026-08-23T12:00:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try! decoder.decode(ProgramEnrollment.self,
                                   from: Data(json.utf8))
    }

    func testAFocusLiftWithABaselineDetectsAStrengthGoalFivePercentUp() {
        let bench = UUID()
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(exerciseIDs: [bench]),
                                   baseline: [bench.uuidString.lowercased(): 200]),
            volumeTargets: [], effectiveWeeklyGoal: 3, unit: .lbs,
            now: Date(timeIntervalSince1970: 1_787_745_600),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .liftOneRepMax)
        XCTAssertEqual(draft.target.exerciseID, bench)
        XCTAssertEqual(draft.target.targetWeightLbs, 210,
                       "200 × 1.05, rounded on the 5 lb grid — the same step "
                       + "WeeklyGoalDetector.liftTarget takes, called not re-derived")
        XCTAssertEqual(draft.source, .coach)
        XCTAssertNil(draft.preset, "this goal was not chosen at a door")
        XCTAssertNotNil(draft.byDate, "the block's end is the milestone date")
    }

    func testAMuscleGroupFocusDetectsWeeklyMuscleSets() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(muscleGroup: "chest"),
                                   baseline: [:]),
            volumeTargets: [VolumeTarget(muscle: "chest", weeklySets: 14, reason: nil)],
            effectiveWeeklyGoal: 3, unit: .lbs,
            now: Date(timeIntervalSince1970: 1_787_745_600),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .weeklyMuscleSets)
        XCTAssertEqual(draft.target.muscleTargets?["chest"], 14,
                       "the titration is read first when it has a row")
    }

    func testAnEnrollmentWithNeitherFallsToDaysAndNeverToNil() {
        let draft = LadderMath.detectedGoal(
            enrollment: enrollment(focus: ProgramFocus(), baseline: [:]),
            volumeTargets: [], effectiveWeeklyGoal: 5, unit: .lbs,
            now: Date(timeIntervalSince1970: 1_787_745_600),
            calendar: Calendar(identifier: .gregorian))

        XCTAssertEqual(draft.metric, .trainingDaysPerWeek)
        XCTAssertEqual(draft.target.days, 5,
                       "the same never-empty floor WeeklyGoalDetector's rule 3 is")
    }
```

> `VolumeTarget` (`Models/RecoveryProbeRepository.swift:150-158`) is a plain `Codable` struct with a
> memberwise init and **no default on `reason`**, so all three labels are required — hence
> `VolumeTarget(muscle:weeklySets:reason:)` above. `ProgramEnrollment` is `Decodable`-only (`:26`), which is
> why the enrollment fixture goes through JSON.

2. Push; fails.
3. Implement the pure function, then `LiveBlockGoalRepository.detectGoalIfMissing(enrollment:)`, which
   fetches, calls it, writes the goal and then writes the derived ladder.
4. Push; green.
5. Commit: `feat(goal): blocks that predate goals get a Coach-detected one` + the trailer.

### A14 — the strip's block kicker — **S**

**Files:** `GymSyncApp/GymSync/Models/WeeklyGoalProgressMath.swift`,
`GymSyncApp/GymSync/Models/WeeklyGoalLiveRepository.swift`.

Spec §6: the kicker gains the block context — `WEEK 3 OF 8 · COACH'S GOAL`, or `YOUR GOAL` after an override.

```swift
    /// The kicker WITH the block behind it (spec §6). `THIS WEEK` becomes
    /// `WEEK 3 OF 8` when the row belongs to a ladder, and stays `THIS WEEK`
    /// for a standalone weekly goal — which is what the whole existing
    /// `kicker(source:met:daysLeft:)` still builds, unchanged and still called
    /// by every kind that has no block.
    ///
    /// The met kicker is untouched: `GOAL MET · {n} DAYS LEFT` is about the
    /// WEEK, and prefixing a block onto it would put two facts where the strip
    /// has room for one.
    static func blockKicker(source: WeeklyGoalSource, met: Bool, daysLeft: Int,
                            weekNumber: Int?, weekCount: Int?) -> String {
        if met { return kicker(source: source, met: true, daysLeft: daysLeft) }
        guard let weekNumber, let weekCount, weekCount > 0 else {
            return kicker(source: source, met: false, daysLeft: daysLeft)
        }
        let whose = source == .user ? "YOUR GOAL" : "COACH'S GOAL"
        return "WEEK \(weekNumber) OF \(weekCount) · \(whose)"
    }
```

`LiveWeeklyGoalRepository.progress(for:)` gains a **block context read**: when `goal.params.goalID` is
non-nil, look up the rung index and the ladder's length once, and rewrite `progress.kicker` through
`blockKicker`. One read, only for rows that belong to a ladder; a standalone weekly goal pays nothing.

**TDD steps.**

1. Failing test in `WeeklyGoalProgressTests.swift`:

```swift
    func testTheBlockKickerNamesTheWeekAndWhoseGoalItIs() {
        XCTAssertEqual(
            WeeklyGoalProgressMath.blockKicker(source: .coach, met: false, daysLeft: 3,
                                               weekNumber: 3, weekCount: 8),
            "WEEK 3 OF 8 · COACH'S GOAL")
        XCTAssertEqual(
            WeeklyGoalProgressMath.blockKicker(source: .user, met: false, daysLeft: 3,
                                               weekNumber: 3, weekCount: 8),
            "WEEK 3 OF 8 · YOUR GOAL")
    }

    func testAStandaloneWeekKeepsTheShippedKicker() {
        XCTAssertEqual(
            WeeklyGoalProgressMath.blockKicker(source: .coach, met: false, daysLeft: 3,
                                               weekNumber: nil, weekCount: nil),
            "THIS WEEK · COACH'S GOAL")
    }

    func testAMetWeekStillSaysMet() {
        XCTAssertEqual(
            WeeklyGoalProgressMath.blockKicker(source: .coach, met: true, daysLeft: 2,
                                               weekNumber: 3, weekCount: 8),
            "GOAL MET · 2 DAYS LEFT")
    }
```

2. Push; fails.
3. Implement both halves.
4. Push; green. **`app-home-v3-08a-targets-above-calendar` must be unchanged** — those frames build their
   `WeeklyGoalProgress` from a literal fixture and never call this function (global constraint 8).
5. Commit: `feat(goal): the strip's block kicker — WEEK 3 OF 8` + the trailer.

**Proves the stream:** Backend workflow green (2 pgTAP files, one new and one extended) + `GymSyncTests` green
(5 new test files — `LadderRuleTests`, `LadderReadoutTests`, `LadderMathTests`,
`BlockGoalMetricMathTests`, `BlockGoalLiveRepositoryTests` — plus the extended `WeeklyGoalProgressTests`).

---
# STREAM B — the generator

Worktree `wt-goal-gen`, branch `feat/block-goal-generator`. Zero SwiftUI. 6 tasks.

The generator is **pure and deterministic** and its own header says so (`ProgramGenerator.swift:5-9`: "same
inputs + same catalog = the same program, byte for byte"). Every task here keeps that property: the goal
enters as an `Inputs` field, and nothing in this stream fetches.

### B1 — `ProgramGenerator.Inputs.goal`, the focus band and the focus exercise — **L**

**Files:** `GymSyncApp/GymSync/Models/ProgramGenerator.swift`,
`GymSyncApp/GymSync/Models/TrainingProfile.swift`.

Spec §5.3: *"`ProgramGenerator.Inputs` gains `goal: BlockGoal`, which sets the focus band and the focus
exercise where the goal names one, the block length from the date, and the conditioning / mobility placement
for the ramp metrics."*

**The field** — appended to `Inputs` with a trailing default, so every existing construction site compiles
(the same discipline every field on this struct already follows):

```swift
        /// The block's goal (spec §5.3). THE BLOCK EXISTS TO SERVE IT.
        ///
        /// A DRAFT, not a `BlockGoal`: the goal is composed at the door and the
        /// enrollment does not exist until `ProgramBuilder` writes it, so the
        /// only shape available at generation time is the one without an
        /// enrollment id (`BlockGoalDraft`'s own doc comment).
        ///
        /// Optional here and REQUIRED at `ProgramBuilder.build` (task B4). The
        /// generator is a pure function with golden tests that predate goals
        /// and must keep passing byte for byte; the DOOR is where "no block
        /// without a goal" is enforced, because the door is the only way a
        /// block gets built.
        var goal: BlockGoalDraft? = nil
```

**What the goal moves**, and nothing else (three levers, each named and each tested):

1. **The focus band.** `GoalPreset` → `GeneratorScience.Focus`, applied **before**
   `GeneratorScience.band(for:)` at `generate`'s first line (:314-317), so slots, selection and prescription
   all ride the goal's focus rather than the profile's `blockGoal`:

   | preset | focus |
   |---|---|
   | `strength`, `repStrength` | `.strength` |
   | `muscle`, `maintenance` | `.hypertrophy` |
   | `endurance`, `conditioning`, `benchmark` | `.conditioning` |
   | `bodyComposition` | `.weightLoss` |
   | `volume` | `.hypertrophy` |
   | `consistency`, `recovery` | *no override* — the profile's own focus stands |

   `consistency` and `recovery` deliberately do not move the band: showing up more often is not a training
   emphasis, and a recovery block's shape is the cardio/mobility placement (B3), not a rep range. Written as a
   pure `GoalGeneratorMapping.focus(for:) -> GeneratorScience.Focus?` so the `nil` is a value rather than an
   omission.

2. **The focus exercise.** A `liftOneRepMax` or `liftRepsAtLoad` goal names a lift; that lift is inserted into
   `inputs.focusExerciseIDs`, which **wins its main pattern slot outright** before scoring
   (`ProgramGenerator.swift:80-87`, `select` at :1304). `formUnion`, never assignment — the consult's own
   focus lifts and `RuleIntent.swap`'s starred lift are already there, and an assignment would erase them
   (the exact defect `ProgramBuilder.swift:125-127` records).

3. **The muscle group.** A `weeklyMuscleSets` goal with one group sets `inputs.focusMuscles` to that group;
   **Maintenance sets it to `nil`**, which is already the generator's own encoding of "all muscle groups, the
   owner's *hit all and don't think about it again*" (`ProgramGenerator.swift:23-25`) — and is exactly owner
   decision 9. Maintenance also seeds `inputs.volumeTargets` from the goal's `muscleTargets`, so
   `balanceWeeklyVolume` balances toward the recommended numbers rather than the band.

**`TrainingProfile.generatorInputs`** gains one parameter, `goal: BlockGoalDraft? = nil`, applied **last** —
after every profile-derived field and after the standing-rule loop — so the goal is the strongest voice in the
room, which is the whole design.

**Interfaces** — *consumes:* `BlockGoalDraft`, `GoalPreset`, `GoalMetric`, `GeneratorScience.Focus`.
*Produces:* `ProgramGenerator.Inputs.goal`, `GoalGeneratorMapping.focus(for:)`,
`TrainingProfile.generatorInputs(…, goal:)`.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/GoalGeneratorInputTests.swift`:

```swift
import XCTest
@testable import GymSync

final class GoalGeneratorInputTests: XCTestCase {

    private func draft(_ preset: GoalPreset, target: GoalTarget = GoalTarget()) -> BlockGoalDraft {
        BlockGoalDraft(metric: preset.metric, target: target, byDate: nil, preset: preset)
    }

    func testEachPresetChoosesItsBandAndTwoDeliberatelyDoNot() {
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.strength)), .strength)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.repStrength)), .strength)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.muscle)), .hypertrophy)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.maintenance)), .hypertrophy)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.endurance)), .conditioning)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.benchmark)), .conditioning)
        XCTAssertEqual(GoalGeneratorMapping.focus(for: draft(.bodyComposition)), .weightLoss)
        XCTAssertNil(GoalGeneratorMapping.focus(for: draft(.consistency)),
                     "showing up more often is not a training emphasis")
        XCTAssertNil(GoalGeneratorMapping.focus(for: draft(.recovery)))
    }

    func testAStrengthGoalMakesItsLiftAFocusLiftWithoutErasingTheOthers() {
        let bench = UUID(), squat = UUID()
        var profile = TrainingProfile()
        profile.focusExerciseIDs = [squat]
        let inputs = profile.generatorInputs(
            durationWeeks: 8,
            goal: draft(.strength, target: GoalTarget(exerciseID: bench,
                                                      targetWeightLbs: 225)))
        XCTAssertTrue(inputs.focusExerciseIDs.contains(bench))
        XCTAssertTrue(inputs.focusExerciseIDs.contains(squat),
                      "the consult's own focus lift survives the goal")
        XCTAssertEqual(inputs.focus, .strength)
    }

    func testMaintenanceTargetsEveryMajorGroupAndSeedsTheirNumbers() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 6,
            goal: draft(.maintenance,
                        target: GoalTarget(muscleTargets: ["chest": 12, "back": 14,
                                                           "legs": 16, "arms": 10,
                                                           "shoulders": 10, "core": 8])))
        XCTAssertNil(inputs.focusMuscles,
                     "owner decision 9: Maintenance is every major group, which the "
                     + "generator already spells as nil")
        XCTAssertEqual(inputs.volumeTargets["chest"], 12)
        XCTAssertEqual(inputs.volumeTargets["core"], 8)
    }

    func testAMuscleGoalFocusesTheOneGroup() {
        let inputs = TrainingProfile().generatorInputs(
            durationWeeks: 6,
            goal: draft(.muscle, target: GoalTarget(muscleTargets: ["chest": 16])))
        XCTAssertEqual(inputs.focusMuscles, ["chest"])
    }

    func testNoGoalLeavesEveryInputExactlyAsItWas() {
        let profile = TrainingProfile()
        let withoutGoal = profile.generatorInputs(durationWeeks: 8)
        let withNilGoal = profile.generatorInputs(durationWeeks: 8, goal: nil)
        XCTAssertEqual(withoutGoal.focus, withNilGoal.focus)
        XCTAssertEqual(withoutGoal.focusExerciseIDs, withNilGoal.focusExerciseIDs)
        XCTAssertEqual(withoutGoal.focusMuscles, withNilGoal.focusMuscles)
        XCTAssertEqual(withoutGoal.volumeTargets, withNilGoal.volumeTargets)
    }
}
```

2. Push; fails to compile.
3. Add the `goal` field, `GoalGeneratorMapping` (a new `enum` in `ProgramGenerator.swift`, next to `Inputs`),
   and the `generatorInputs` parameter.
4. Push; `GoalGeneratorInputTests` green **and the generator's existing golden tests unchanged** — that is this
   task's real proof, because a goal-less build must produce the byte-identical program it produced before.
5. Commit: `feat(goal): the generator takes the block's goal — band, focus lift, focus muscles` + the trailer.

### B2 — the block length comes from the milestone date — **S**

**File (new):** `GymSyncApp/GymSync/Models/GoalBlockLength.swift`

```swift
import Foundation

// MARK: - GoalBlockLength
//
// Spec §5.3: the goal sets "the block length from the date". PURE, so the
// answer is a test rather than a clock.
enum GoalBlockLength {

    /// The generator's own limits. Below four weeks a block has no wave to
    /// speak of (`ProgramGenerator.swift:918-919`: flat under 8, deload at the
    /// ¾ mark from 8), and `program_enrollments.weeks` is CHECKed BETWEEN 1
    /// AND 52 (`20260728000009_program_enrollments.sql:42`).
    static let minimumWeeks = 4
    static let maximumWeeks = 52
    /// What a block is when the goal names no date — Maintenance, Recovery and
    /// Consistency are "held for the block" (spec §2.1), and eight weeks is
    /// what `ProgramBuilder.build` has always defaulted to
    /// (`ProgramBuilder.swift:88`).
    static let defaultWeeks = 8

    /// Whole weeks from `now` to `byDate`, clamped. A date inside four weeks
    /// still gets a four-week block: the ladder then says the milestone is out
    /// of reach (task B5), which is honest, where refusing to build is not.
    static func weeks(byDate: Date?, from now: Date = .now,
                      calendar: Calendar = .current) -> Int {
        guard let byDate else { return defaultWeeks }
        let days = calendar.dateComponents([.day],
                                           from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: byDate)).day ?? 0
        let raw = Int((Double(days) / 7.0).rounded(.up))
        return min(maximumWeeks, max(minimumWeeks, raw))
    }
}
```

**TDD steps.** 1. `GymSyncApp/GymSyncTests/GoalBlockLengthTests.swift` — 56 days → 8; 60 days → 9 (rounds up,
because a block that ends before the date is a block that gives up a week); nil → 8; 3 days → 4 (the floor);
500 days → 52 (the ceiling); a date in the past → 4, never negative and never a crash.
2. Push; fails. 3. Implement. 4. Push; green.
5. Commit: `feat(goal): block length from the milestone date` + the trailer.

### B3 — cardio and mobility placement for the ramp metrics — **M**

**File:** `GymSyncApp/GymSync/Models/ProgramGenerator.swift`.

Spec §3.4: *"The block generator receives the rung as an input where it changes the plan (a cardio day placed,
a mobility circuit added), through the existing conditioning / cardio passes."* Spec §5.3 names the same
lever: "the conditioning / mobility placement for the ramp metrics".

**Through the existing passes, not a new one.** `Inputs` already carries `cardioDays`, `cardioMinutes` and
`fillWeekWithRecovery`, and `generate` already has a dedicated-cardio placement and an active-recovery fill
(`ProgramGenerator.swift:836-844`, :904-916). B3 sets those fields from the goal and touches nothing else:

| goal | what it sets |
|---|---|
| `endurance` (`weeklyDistance`) | `cardioDays = max(cardioDays, 2)`; `cardioMinutes` from the weekly distance at a documented 10 min/mi (6 min/km) pace floor, clamped to `20…90` |
| `conditioning` (`sessionsOfTypePerWeek`) | `cardioDays = max(cardioDays, target.sessions ?? 0)` capped at 4 |
| `bodyComposition`, cutting | `cardioDays = max(cardioDays, 2)` — the generator's own weight-loss cardio pass then shapes them |
| `recovery` | `fillWeekWithRecovery = true`, and `cardioDays = max(cardioDays, 2)` at `cardioMinutes = target.lissMinutes / 2` clamped to `20…60` |
| `benchmark` | `cardioDays = max(cardioDays, 1)` |
| everything else | **nothing** |

`max(…)`, never assignment: the athlete's own cardio answer from the consult is already in `Inputs`, and a
goal must not take days away from someone who asked for them.

The 10 min/mi floor is a **stated assumption, not a measurement** — the app has no pace history reader in
phase 1. It is written into the function's doc comment as such, and it is the plan's decision because the spec
does not give a number.

**TDD steps.** 1. Extend `GoalGeneratorInputTests.swift`: an endurance goal of 15 mi/wk over 2 days sets
`cardioDays >= 2` and a `cardioMinutes` inside `20…90`; a recovery goal sets `fillWeekWithRecovery`; a
strength goal changes **neither**; an athlete who asked for 3 cardio days keeps 3 when the goal implies 2.
2. Push; fails. 3. Implement `GoalGeneratorMapping.applyPlacement(_:to:)`. 4. Push; green, generator goldens
unchanged for goal-less inputs.
5. Commit: `feat(goal): ramp goals place cardio and mobility through the existing passes` + the trailer.

### B4 — `ProgramBuilder.build` requires a goal — **L**

**File:** `GymSyncApp/GymSync/Models/ProgramBuilder.swift`.

Spec §5.4: *"`ProgramBuilder.build()` requires a `BlockGoal`."* This is the task that makes "no block without a
goal" true rather than aspirational.

**The signature** — `goal` is **required and non-optional**, placed before the two defaulted parameters:

```swift
    @MainActor
    static func build(profile loaded: TrainingProfile,
                      answers: ConsultAnswers?,
                      catalog all: [Exercise],
                      userID: UUID,
                      goal: BlockGoalDraft,
                      goalWriter: WeeklyGoalCoachWriter = LiveWeeklyGoalRepository(),
                      blockGoalRepository: any BlockGoalRepository = LiveBlockGoalRepository())
        async throws -> Outcome
```

**No default on `goal`.** A defaulted parameter here would let a call site keep compiling while silently
building a goal-less block, which is the entire failure this feature exists to end. The three surviving call
sites (`CoachHomeView`, `ConsultEntryView`, and — after C4 — nothing else) are fixed by Stream C; a stream that
forgot one gets a compile error at integration, which is the point.

**The write order** — this file's header calls the order load-bearing, so the goal joins it as a numbered
step, after the enrollment exists and before the receipts:

```
   1. evidence reads            (unchanged)
   2. generate                  — `inputs.goal = goal`, duration from `GoalBlockLength.weeks(byDate:)`
   3. profile                   (unchanged)
   4. snapshot                  (unchanged)
   5. write the day routines    (unchanged)
   6. delete the superseded     (unchanged)
   7. template row → enroll → plan   — `enroll` now RETURNS the enrollment id
 → 7b. THE GOAL AND ITS LADDER  — new
   8. stamp the fired rules     (unchanged)
   9. this week's weekly goal   (unchanged; it now finds the ladder's row already written)
```

**7b, in full.** `enroll(...)` currently discards its result (`_ = try? await ProgramRepository.enroll`,
:282); it must return `ProgramEnrollment?` so 7b has an `enrollmentID`. Then:

```swift
        // ── 7b. The goal and its ladder ──────────────────────────────
        // A block exists to serve a goal (owner decision 4), so the goal is
        // written in the same act that writes the block — not on the next
        // Home load, and not by a background pass that could fail silently.
        //
        // AFTER the enrollment, because `BlockGoal.enrollmentID` is the block
        // this goal drives and there is no id before step 7. BEFORE the
        // receipts, because step 9's weekly write reads the ladder this
        // writes: run it later and the first week of every new block would
        // carry a detected goal instead of its own rung.
        //
        // BEST-EFFORT, like every write after step 5's deliverable: a failure
        // here costs the ladder, never the block. The athlete then has a block
        // with no goal, which is exactly the state A13's detection fills on the
        // next Home load — the same recovery path a migrated block takes.
        if let enrollment {
            let blockGoal = BlockGoal(draft: goal, userID: userID,
                                      enrollmentID: enrollment.id)
            if await blockGoalRepository.save(blockGoal) {
                await blockGoalRepository.saveDerivedLadder(
                    goal: blockGoal, program: program, catalog: all,
                    startedOn: enrollment.startedOn, unit: unit)
                await blockGoalRepository.materialiseRung(
                    goalID: blockGoal.id, weekStart: WeekMath.weekStartString())
            }
        }
```

`saveDerivedLadder` is the one new method on `LiveBlockGoalRepository` this task needs (Stream A owns its
body; B declares the requirement in the protocol extension and Stream A implements it — **coordinate: this
method belongs on the protocol, so it lands in B4 as a protocol requirement with a default that returns
`nil`, and A11's live type overrides it**). It calls `LadderReadout` for the three prescribed metrics and
`LadderRules.rule(for:)` for the eight ramped ones, using `LadderReadout.constraints(program:unit:)`, and
writes `enrollment.weeks` rungs whose `weekStartString` walks forward from
`WeekMath.weekStartString(enrollment.startedOn)`.

**Interfaces** — *consumes:* `BlockGoalDraft`, `BlockGoalRepository`, `GoalBlockLength`, `LadderReadout`,
`LadderRules`, `WeekMath`. *Produces:* the new `build` signature, `enroll(...) -> ProgramEnrollment?`,
`BlockGoalRepository.saveDerivedLadder(goal:program:catalog:startedOn:unit:)`.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/ProgramBuilderGoalTests.swift`. The build itself is `@MainActor`
   and does eleven network reads, so it is **not** unit-tested end to end; what is tested is the pure seam:

```swift
import XCTest
@testable import GymSync

final class ProgramBuilderGoalTests: XCTestCase {

    /// Records what it was asked to write, and writes nothing.
    private actor Recorder: BlockGoalRepository {
        var saved: [BlockGoal] = []
        var ladders: [UUID] = []
        var materialised: [UUID] = []
        func activeGoal() async -> BlockGoal? { nil }
        func ladder(goalID: UUID) async -> Ladder? { nil }
        func page(goalID: UUID) async -> LadderPageModel? { nil }
        func save(_ goal: BlockGoal) async -> Bool { saved.append(goal); return true }
        func reLadder(goalID: UUID) async -> Ladder? { nil }
        func materialiseRung(goalID: UUID, weekStart: String) async -> WeeklyGoal? {
            materialised.append(goalID); return nil
        }
    }

    func testTheDurationComesFromTheMilestoneDate() {
        let now = Date(timeIntervalSince1970: 1_788_696_000)
        let byDate = now.addingTimeInterval(56 * 86_400)
        XCTAssertEqual(GoalBlockLength.weeks(byDate: byDate, from: now), 8)
        XCTAssertEqual(GoalBlockLength.weeks(byDate: nil, from: now), 8)
    }

    func testTheLadderWalksOneWeekPerRungFromTheBlockStart() {
        let start = Date(timeIntervalSince1970: 1_788_696_000)   // a Sunday-week start
        let weeks = LadderMath.weekStartStrings(from: start, count: 8)
        XCTAssertEqual(weeks.count, 8)
        XCTAssertEqual(Set(weeks).count, 8, "no two rungs describe the same week")
        XCTAssertEqual(weeks.first, WeekMath.weekStartString(start))
    }
}
```

> `LadderMath.weekStartStrings(from:count:)` is a two-line pure helper this task adds to `LadderMath` (A9's
> file) — **coordinate with Stream A**: it lands in whichever branch reaches it first and the other rebases.
> It is the only symbol the two streams both write.

2. Push; fails to compile — and **so does every existing call site of `build`**, which is the designed
   failure.
3. Change the signature, thread `inputs.goal`, make `enroll` return, add step 7b, add the protocol
   requirement + default.
4. Fix the two in-tree call sites minimally so the target compiles: `CoachHomeView.buildFromConsult` and
   `ConsultEntryView.finish` each gain a `goal:` argument. **They pass a goal they are handed**, not one they
   invent — Stream C gives both a real one; until C lands, B passes a `BlockGoalDraft` derived by
   `LadderMath.detectedGoal(...)` (A13) so the tree is never in a state that builds an unconsidered block.
5. Push; green.
6. Commit: `feat(goal): no block without a goal — build(goal:) writes the goal and its ladder` + the trailer.

### B5 — "cannot reach by the date", computed and said — **M**

**File:** `GymSyncApp/GymSync/Models/GoalBlockLength.swift` (extend).

Spec §3.2, the copy verbatim: *"225 by Oct 18 needs more than this block can safely give; Nov 15 is the date
I can build to"* — and: **"The ladder never lies about the gap."**

```swift
extension GoalBlockLength {

    /// Can the block's own prescribed loading reach `target` by `byDate`?
    ///
    /// Answered from the LADDER, not from a second model of progress: the last
    /// rung is what the block prescribes for the final week, and if that falls
    /// short of the milestone then the block falls short of the milestone.
    /// Anything else would be a third opinion about the same eight weeks.
    struct Reach: Equatable, Sendable {
        let reaches: Bool
        /// What the block DOES get to — 218, in the spec's example.
        let projected: GoalTarget
        /// The date the block COULD build to, when it cannot make the one
        /// asked for. nil when it can.
        let achievableDate: Date?
    }

    static func reach(metric: GoalMetric, rungs: [GoalTarget], milestone: GoalTarget,
                      byDate: Date?, weeklyGain: Double?, from now: Date = .now,
                      calendar: Calendar = .current) -> Reach {
        guard let last = rungs.last else {
            return Reach(reaches: false, projected: milestone, achievableDate: nil)
        }
        if LadderMath.reached(metric: metric, measured: last, target: milestone) {
            return Reach(reaches: true, projected: last, achievableDate: nil)
        }
        // The date the block COULD build to: how many more weeks of the same
        // weekly gain the remaining distance needs. nil `weeklyGain` (a metric
        // with no linear gain, or a ladder that is flat) means the honest
        // answer is "not on this ladder", with no invented date.
        var achievable: Date?
        if let weeklyGain, weeklyGain > 0,
           let short = shortfall(metric: metric, last: last, milestone: milestone),
           short > 0 {
            let extraWeeks = Int((short / weeklyGain).rounded(.up))
            let endOfBlock = calendar.date(byAdding: .day,
                                           value: rungs.count * 7, to: now) ?? now
            achievable = calendar.date(byAdding: .day, value: extraWeeks * 7,
                                       to: byDate ?? endOfBlock)
        }
        return Reach(reaches: false, projected: last, achievableDate: achievable)
    }

    /// Coach's sentence at the door, spec §3.2 verbatim in shape:
    /// "225 by Oct 18 needs more than this block can safely give; Nov 15 is
    /// the date I can build to."
    ///
    /// Without an achievable date the sentence stops after the first clause
    /// rather than inventing a second — the design's "never lies about the
    /// gap" cuts both ways.
    static func reachSentence(milestoneText: String, byDate: Date?, reach: Reach,
                              calendar: Calendar = .current) -> String? {
        guard !reach.reaches else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.dateFormat = "MMM d"
        let asked = byDate.map { " by \(formatter.string(from: $0))" } ?? ""
        let head = "\(milestoneText)\(asked) needs more than this block can safely give"
        guard let achievable = reach.achievableDate else { return head + "." }
        return head + "; \(formatter.string(from: achievable)) is the date I can build to."
    }
}
```

`shortfall(metric:last:milestone:)` is a private per-metric subtraction (pounds for a lift, reps for rep
strength, miles for distance, seconds for a benchmark, pounds for body weight) returning nil for the metrics
where "distance to the milestone" is not a single number (`weeklyMuscleSets`).

**TDD steps.** 1. In `GoalBlockLengthTests.swift`: a ladder whose last rung is 218 against a 225 milestone is
`reaches == false` with `projected == 218`; the sentence is exactly
`"Bench 225 by Oct 18 needs more than this block can safely give; Nov 15 is the date I can build to."` for a
5 lb/week gain and an Oct 18 date; a reaching ladder returns nil for the sentence; a flat ladder with no
`weeklyGain` produces the one-clause sentence and **no invented date**.
2. Push; fails. 3. Implement. 4. Push; green.
5. Commit: `feat(goal): the reach computation and Coach's sentence about the gap` + the trailer.

### B6 — `WeekBooker` is unchanged, and a test says so — **S**

**File (new):** `GymSyncApp/GymSyncTests/WeekBookerUnchangedTests.swift`.

The task brief and the spec both say `WeekBooker` is unchanged. It is not enough to leave it alone: it
already calls `writeDetectedGoal(weekStart:)` after booking (`WeekBooker.swift:120-121`), and after A10 a
block week's row is written by the **ladder**, not by detection. The two must not fight.

They do not, and this task proves it: `WeeklyGoalWriteRule.shouldOverwrite` returns **true** for a
`source == .coach` row, so a booking after a materialisation would overwrite the rung's row with a detected
one. The fix is **not** in `WeekBooker` — it is one line in `LiveWeeklyGoalRepository.detect`: a week whose
existing row carries `params.goalID` is a **ladder week**, and detection returns that row unchanged rather
than deriving over it.

```swift
    /// A LADDER WEEK IS NOT DETECTION'S TO FILL.
    ///
    /// `WeekBooker.book` calls `writeDetectedGoal` after every booking, and
    /// `WeeklyGoalWriteRule.shouldOverwrite` says yes to a `coach` row — which
    /// is right for a row Coach's own detector wrote and wrong for a row the
    /// block's LADDER materialised (task A10, also `source = coach`). Booking a
    /// week of an active block would otherwise replace week 3's prescribed rung
    /// with a freshly detected goal, and the strip and the ladder page would
    /// then disagree about the same seven days.
    ///
    /// One question, asked here rather than in `WeekBooker`, because
    /// `WeekBooker` has no business knowing what a ladder is.
    static func isLadderWeek(_ existing: WeeklyGoal?) -> Bool {
        existing?.params.goalID != nil
    }
```

consulted at the top of `writeDetected(weekStart:existing:)`:
`guard !WeeklyGoalWriteRule.isLadderWeek(existing) else { return existing }`.

**TDD steps.**

1. Failing test:

```swift
import XCTest
@testable import GymSync

/// `WeekBooker` is unchanged by goal-first programming — and the seam that
/// makes that safe is `WeeklyGoalWriteRule.isLadderWeek`.
final class WeekBookerUnchangedTests: XCTestCase {

    private func row(goalID: UUID?) -> WeeklyGoal {
        WeeklyGoal(userID: UUID(), weekStartString: "2099-01-04", kind: .muscleSets,
                   params: WeeklyGoalParams(muscleTargets: ["chest": 12], goalID: goalID),
                   source: .coach, setAt: Date(timeIntervalSince1970: 0))
    }

    func testALadderWeekIsNotDetectionsToFill() {
        XCTAssertTrue(WeeklyGoalWriteRule.isLadderWeek(row(goalID: UUID())))
        XCTAssertFalse(WeeklyGoalWriteRule.isLadderWeek(row(goalID: nil)))
        XCTAssertFalse(WeeklyGoalWriteRule.isLadderWeek(nil),
                       "an empty week is detection's, exactly as before")
    }

    func testTheShippedOverwriteRuleIsUntouched() {
        let coach = row(goalID: nil)
        var user = coach; user.source = .user
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: nil, detected: coach))
        XCTAssertTrue(WeeklyGoalWriteRule.shouldOverwrite(existing: coach, detected: coach))
        XCTAssertFalse(WeeklyGoalWriteRule.shouldOverwrite(existing: user, detected: coach))
    }

    func testBookingInjectsANoOpWriterWithoutTouchingTheNetwork() async {
        // `WeekBooker.book`'s `goalWriter` parameter exists precisely so this
        // is possible (`WeekBooker.swift:113-115`). Nothing about it changes.
        let writer = NoOpWeeklyGoalCoachWriter()
        let result = await writer.writeDetectedGoal(weekStart: "2099-01-04")
        XCTAssertNil(result)
    }
}
```

2. Push; fails.
3. Add `isLadderWeek` and its one call site. **`WeekBooker.swift` itself is not edited** — verify with
   `git diff --stat` in the commit body.
4. Push; green.
5. Commit: `fix(goal): a ladder week is not detection's to overwrite; WeekBooker unchanged` + the trailer.

**Proves the stream:** `GymSyncTests` green (3 new test files) and the generator's existing golden tests
byte-identical for goal-less inputs.

---

# STREAM C — the door

Worktree `wt-goal-door`, branch `feat/block-goal-door`. 5 tasks. Owns 4 of the 8 new catalog ids.

**"Set a goal → Coach builds your block."** Building a block always begins with the goal; there is no other
entry (spec §5).

### C1 — the goal screen — **L**

**File (new):** `GymSyncApp/GymSync/Features/Coach/GoalScreenView.swift`

```swift
struct GoalScreenView: View {
    /// The block that will be built, once a milestone is chosen.
    var onChosen: (BlockGoalDraft) -> Void
    /// Coach's suggestion, seeded from the last block (spec §7). nil on a
    /// first block, which is the normal case in phase 1.
    var suggested: GoalPreset? = nil
}
```

**Top to bottom**, per spec §5.1 and the design language:

1. **Title** — `Your goal for this block`, `GSFont.heading(28)`, `theme.text`. Sentence case (rule 9).
2. **A grid of ten raised cards**, two columns, `GoalPreset.tiles` in order. Each card: the preset's name in
   caps at 13 pt with 0.6 tracking, one line of body copy at 11 pt in `neutral500`, and the metric's SF
   Symbol in `theme.accent` at the top right — the `doorLabel` recipe `CoachHomeView.swift:174-209` already
   established for this screen family, at tile scale. `.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd)`
   (rule 1: a thing you press sinks). Glyphs, **SF Symbols only** (rule 2):

   | preset | glyph | line |
   |---|---|---|
   | Strength | `figure.strengthtraining.traditional` | `Add weight to a lift by a date.` |
   | Muscle | `figure.arms.open` | `More weekly sets for a muscle group.` |
   | Endurance | `figure.run` | `More distance each week.` |
   | Consistency | `calendar` | `Train more days a week, and hold it.` |
   | Conditioning | `bolt.heart` | `More sessions of one kind each week.` |
   | Maintenance | `equal.circle` | `Hold the recommended volumes.` |
   | Recovery | `figure.cooldown` | `Easy cardio and stretching, for a while.` |
   | Body composition | `scalemass` | `A body weight, at a safe rate.` |
   | Volume | `chart.bar.fill` | `Move a total this block.` |
   | Benchmark | `stopwatch` | `A named workout, faster.` |

   Coach's suggestion (when `suggested` is non-nil) wears a small accent kicker `COACH SUGGESTS` above its
   name — accent's "current item" job (rule 2), and the **only** accent on this screen.
3. **The Pro door**, below the grid, full width: `Talk it through with Coach`, glyph
   `bubble.left.and.text.bubble.right`, with the **`PRO` capsule** exactly as
   `CoachOnboardingViews.swift:60-68` draws it (9 pt bold, 0.8 tracking, accent stroke, `Capsule()`).

   **Phase-1 behaviour, decided here:** the door is **rendered and disabled**, with the footer
   `PRO · ARRIVING WITH THE WATCH METRICS` and the body line
   *`Coach finds the goal and the ladder with you. Pick a preset below and I'll build to it.`*
   It is disabled because the feature is **not built yet** (spec §10 puts the Coach-guided consult in phase
   2), *not* because of entitlement: `Entitlements.hasPro` is `true` today
   (`Models/CoachObservations.swift:11-13` — "every gate in the app asks HERE and nowhere else"), and that is
   the gate phase 2 consults. Naming the gate now and disabling for a stated reason is the honest shape;
   silently routing to a screen that cannot bind a goal is not.
4. **No accent primary.** This is a picker, and the one primary lives on the milestone card (rule 4).

**Interfaces** — *consumes:* `GoalPreset`, `Entitlements.hasPro`. *Produces:* `GoalScreenView`, and the
`onChosen` callback carrying a `BlockGoalDraft`.

**TDD steps.** SwiftUI bodies are not unit-testable in this target (the exemplar's B7 says the same); the
**capture is the proof** (C5, `goal-screen`). What *is* tested is the pure copy table:

1. Failing test — `GymSyncApp/GymSyncTests/GoalScreenCopyTests.swift`: every `GoalPreset.tiles` case has a
   non-empty glyph and a non-empty line; no line ends without a full stop; `GoalPreset.tiles.count == 10`;
   no two presets share a glyph (a grid where two tiles wear the same symbol is a grid nobody can scan).
2. Push; fails.
3. Add `GoalScreenView.swift` with `static let copy: [GoalPreset: (glyph: String, line: String)]` holding the
   table above, so the test reads the shipped values rather than a copy of them.
4. Push; green.
5. Commit: `feat(goal): the goal screen — ten presets and the Pro door` + the trailer.

### C2 — the milestone cards — **L**

**File (new):** `GymSyncApp/GymSync/Features/Coach/GoalMilestoneView.swift`

Spec §5.2: *one card per preset with the levers it needs and nothing else* (design rule 4: questions above the
fold). Coach's line under the levers states current state and what the ladder would look like.

```swift
struct GoalMilestoneView: View {
    let preset: GoalPreset
    /// What the athlete's log says right now, for the seeds and for Coach's
    /// line. Passed in, never fetched here.
    let current: GoalTarget
    /// The block's focus lifts first, then the catalog — the same ordering
    /// `WeeklyGoalEditorSheet.liftPicker` uses.
    let lifts: [WeeklyGoalEditorSheet.LiftOption]
    let routines: [Routine]
    /// Fixture clock for the catalog frames; `.now` in the app.
    var today: Date = .now
    var unitOverride: WeightUnit? = nil
    var onBuild: (BlockGoalDraft) -> Void
}
```

**Levers, per preset** — spec §5.2 verbatim where it names them:

| preset | levers |
|---|---|
| Strength | a **segmented switch** `A MAX / REPS AT A LOAD` (this is where `repStrength` lives); the lift (picker, focus lifts first); the target load (stepper in the athlete's unit, seeded from e1RM + a realistic gain); the date (picker, seeded from the block length). Under `REPS AT A LOAD`: the lift, the load, and a rep stepper. |
| Muscle | the group (six chips) and the weekly sets (stepper) |
| Endurance | the activity (`run/bike/row/walk`), the weekly distance (stepper), the date |
| Consistency | days per week (stepper 1–7) |
| Conditioning | the type (`hiit/mobility/cardio/class`) and the count |
| Maintenance | **the block length only** (a weeks stepper). The targets are the recommended numbers for every major group — read, shown, not edited |
| Recovery | **the block length only**, plus the two companion steppers (stretches a week, LISS minutes a week) |
| Body composition | a segmented `A WEIGHT / A RATE`; a weight stepper in the athlete's unit, or a rate stepper in %/wk; the date |
| Volume | a total stepper (2,500 lb steps) and the date |
| Benchmark | the routine (picker) and a `mm:ss` stepper; the date |

**Coach's line**, under the levers, `theme.neutral700`, 13 pt body, first person (rule 7). Spec §5.2 gives it
verbatim for Strength: **`You're at 205 now; that's about 6 weeks of work`** — built by
`GoalMilestoneCopy.coachLine(preset:current:draft:weeks:unit:)`, a pure function, so it is a test and not a
view. When `GoalBlockLength.reach` says the block cannot make the date, this line is **replaced** by B5's
sentence (spec §3.2) and the primary still builds — the athlete picks: move the date, lower the target, or
keep both. The ladder never lies about the gap.

**The primary** — `BUILD MY BLOCK`, accent, full width, the screen's one primary (rule 4). Disabled with a
stated reason when the card is incomplete (the `incompleteReason` idiom
`WeeklyGoalEditorSheet.swift:711-724` already ships).

**Interfaces** — *consumes:* `GoalPreset`, `GoalTarget`, `BlockGoalDraft`, `GoalBlockLength`,
`WeeklyGoalEditorSheet.LiftOption`, `Units`, `ThemeStore.shared.weightUnit`.
*Produces:* `GoalMilestoneView`, `GoalMilestoneCopy.coachLine(...)`, `GoalMilestoneCopy.draft(...)`.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/GoalMilestoneCopyTests.swift`:

```swift
import XCTest
@testable import GymSync

final class GoalMilestoneCopyTests: XCTestCase {

    func testTheStrengthLineIsTheSpecsOwn() {
        let line = GoalMilestoneCopy.coachLine(
            preset: .strength,
            current: GoalTarget(targetWeightLbs: 205),
            draft: BlockGoalDraft(metric: .liftOneRepMax,
                                  target: GoalTarget(targetWeightLbs: 225),
                                  byDate: nil, preset: .strength),
            weeks: 6, unit: .lbs)
        XCTAssertEqual(line, "You're at 205 now; that's about 6 weeks of work.")
    }

    func testEveryPresetProducesADraftItsMetricCanRead() {
        for preset in GoalPreset.allCases {
            let draft = GoalMilestoneCopy.draft(preset: preset,
                                                current: GoalTarget(),
                                                today: Date(timeIntervalSince1970: 0),
                                                unit: .lbs)
            XCTAssertEqual(draft.metric, preset.metric, "\(preset.rawValue)")
            XCTAssertEqual(draft.preset, preset)
            XCTAssertEqual(draft.source, .user, "the door is the athlete choosing")
            if preset.asksForDate {
                XCTAssertNotNil(draft.byDate, "\(preset.rawValue) is seeded with a date")
            } else {
                XCTAssertNil(draft.byDate,
                             "\(preset.rawValue) is held for the block; it has no deadline")
            }
        }
    }

    func testMaintenanceSeedsEveryMajorGroup() {
        let draft = GoalMilestoneCopy.draft(preset: .maintenance,
                                            current: GoalTarget(),
                                            today: Date(timeIntervalSince1970: 0),
                                            unit: .lbs)
        XCTAssertEqual(Set(draft.target.muscleTargets?.keys ?? [:].keys),
                       Set(MuscleGroup.allCases.map(\.rawValue)),
                       "owner decision 9: every major group")
    }

    func testAnUnreachableMilestoneReplacesTheLineWithTheGap() {
        let reach = GoalBlockLength.Reach(reaches: false,
                                          projected: GoalTarget(targetWeightLbs: 218),
                                          achievableDate: Date(timeIntervalSince1970: 1_795_000_000))
        let line = GoalMilestoneCopy.coachLine(
            preset: .strength, current: GoalTarget(targetWeightLbs: 205),
            draft: BlockGoalDraft(metric: .liftOneRepMax,
                                  target: GoalTarget(targetWeightLbs: 225),
                                  byDate: Date(timeIntervalSince1970: 1_792_411_200),
                                  preset: .strength),
            weeks: 6, unit: .lbs, reach: reach)
        XCTAssertTrue(line.contains("more than this block can safely give"),
                      "the ladder never lies about the gap")
    }
}
```

2. Push; fails.
3. Implement `GoalMilestoneCopy` (pure) and then `GoalMilestoneView` (the levers).
4. Push; green.
5. Commit: `feat(goal): the milestone cards — one lever set per preset, and Coach's line` + the trailer.

### C3 — `BUILD MY BLOCK`, landing on the ladder — **M**

**Files:** `GymSyncApp/GymSync/Features/Coach/GoalMilestoneView.swift`,
`GymSyncApp/GymSync/Features/Coach/ConsultEntryView.swift`.

Spec §5.3: the primary runs `ProgramBuilder.build()` with the goal as an input; *"The consult's 'Reading your
rules, picking the lifts, setting the week' copy stays. Landing is the ladder page (§6), not the routine
list."*

- `ConsultEntryView` gains `let goal: BlockGoalDraft` and passes it to `ProgramBuilder.build(…, goal: goal)`.
  Its `onBuilt` closure gains the goal id it just wrote, so hosts can push the ladder page:
  `var onBuilt: (UUID?) -> Void`.
- The consult's own `buildingCard` (`CoachConsultView.swift:393-402`) is untouched — the copy stays, verbatim.
- **Landing.** Every host's `onBuilt` now pushes `LadderPageView` (Stream D) rather than
  `ProgramScheduleView`. The ladder page's own body carries a `SEE THE BLOCK ›` row to
  `ProgramScheduleView`, so nothing is lost — the schedule is one tap from the ladder rather than the landing.
  **Until D1 lands**, `onBuilt` pushes `ProgramScheduleView` exactly as today; **I1 swaps the destination**,
  one line per host.

**TDD steps.**

1. Failing test — append to `GymSyncApp/GymSyncTests/GoalMilestoneCopyTests.swift`. There is no new pure
   logic in the threading itself, so what is tested is the thing threading can silently get wrong: the draft
   the primary hands over must be the one the levers built, not the seed:

```swift
    func testThePrimaryHandsOverTheEditedDraftAndNotTheSeed() {
        let bench = UUID()
        let seeded = GoalMilestoneCopy.draft(preset: .strength,
                                             current: GoalTarget(exerciseID: bench,
                                                                 targetWeightLbs: 205),
                                             today: Date(timeIntervalSince1970: 0),
                                             unit: .lbs)
        let edited = GoalMilestoneCopy.applying(seeded,
                                                exerciseID: bench,
                                                targetWeightLbs: 245,
                                                byDate: Date(timeIntervalSince1970: 1_795_000_000))
        XCTAssertEqual(edited.target.targetWeightLbs, 245)
        XCTAssertEqual(edited.target.exerciseID, bench)
        XCTAssertNotEqual(edited.byDate, seeded.byDate)
        XCTAssertEqual(edited.metric, seeded.metric,
                       "the levers change the milestone, never the metric")
        XCTAssertEqual(edited.preset, .strength)
    }
```

2. Push; fails to compile.
3. Add `GoalMilestoneCopy.applying(_:exerciseID:targetWeightLbs:byDate:…)`; thread `goal:` through
   `ConsultEntryView` and widen `onBuilt` to `(UUID?) -> Void`.
4. Push; green.
5. Commit: `feat(goal): BUILD MY BLOCK carries the goal into the builder` + the trailer.

### C4 — the door is the one way in; the wizard is retired — **M**

**Files:** `CoachHomeView.swift`, `ProgramLedgerView.swift`, `BlockCalendarView.swift`,
`CoachOfferFlow.swift`; **delete** `CoachWizardView.swift`.

**The finding, stated because it is the decision spec §11.3 defers to the plan.** Grep at `origin/master`:

- `CoachWizardView` is referenced in exactly one place outside its own file — `CoachHomeView.swift:116`,
  inside `case .wizard:` of `navigationDestination(item: $route)`.
- `route = .wizard` **appears nowhere in the repository**. The case is unreachable.
- `CoachBuildLanding` (`CoachWizardView.swift:31`) has no user outside that file.
- The file contains a **second program-writing path**: `create(_:)` at :1748 writes `Routine` rows directly
  and :790 enrolls, entirely bypassing `ProgramBuilder.build`. Leaving it would leave a door that can build a
  block with no goal — the exact thing spec §5.4 forbids — reachable the moment anyone sets that route.

**Decision: retire.** Delete the file, the `case .wizard` in `CoachHomeView.Route`, its `navigationDestination`
arm, and `CoachBuildLanding`. `HealthGateTests.swift:9,26` and `RuleLeverTests.swift:14` mention the type in
**comments only** — update the comments to name `ProgramBuilder`/`ConsultEntryView` instead; do not delete the
tests, which test `healthGateRequired`'s logic and the rule levers, both of which survive.

**Then: every build door routes through the goal screen.** Four hosts, one shape each:

| host | today | after |
|---|---|---|
| `CoachHomeView.consultDoor` | `route = .consult` → `CoachConsultView` → `buildFromConsult` | `route = .goal` → `GoalScreenView` → `GoalMilestoneView` → `ConsultEntryView(goal:)` |
| `ProgramLedgerView.buildDoor` (:162) | `ConsultEntryView(onBuilt:)` | `GoalScreenView` first |
| `BlockCalendarView` (:304) | `ConsultEntryView(onBuilt:)` | `GoalScreenView` first |
| `CoachOfferFlow` (:22) | `ConsultEntryView(onBuilt:)` | `GoalScreenView` first |

The four are collapsed into **one** reusable destination, `GoalFirstBuildFlow`, so there is one build path and
nothing for four hosts to disagree about — the reason `ConsultEntryView`'s own header (:9-14) gives for
existing at all:

```swift
/// The ONE way into a build, now with the goal in front of it (spec §5).
///
/// Four screens open a build (Coach home, the ledger, the block calendar, the
/// onboarding offer). Each opens THIS, which walks
/// goal screen → milestone card → consult → builder → the ladder page — so
/// there is exactly one build path, which is the same reason
/// `ConsultEntryView` was collapsed into one in the first place.
struct GoalFirstBuildFlow: View {
    var onBuilt: (UUID?) -> Void
}
```

`CoachHomeView`'s `consultDoor` copy is **unchanged** — `BUILD MY PROGRAM`, `A conversation with Coach, then
your block — built, and ready to put on the calendar.` It is still true: the goal screen is the first question
of that conversation.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/BuildDoorTests.swift` is not possible (SwiftUI navigation).
   The proof is a **grep assertion in the commit body**, run before and after:
   `git grep -n "ConsultEntryView(" -- 'GymSyncApp/**/*.swift'` must return exactly **one** hit after this task
   (inside `GoalFirstBuildFlow`), and `git grep -rn "CoachWizardView"` must return zero.
2. Delete `CoachWizardView.swift`; remove the route case, its arm, and `CoachBuildLanding`.
3. Add `GoalFirstBuildFlow`; re-point the four hosts.
4. Update the two test comments.
5. Push; the target compiles and `GymSyncTests` is green (nothing tested the wizard).
6. Commit: `refactor(goal): the goal screen is the one door; the legacy wizard is retired` + the trailer.
   Body carries both grep results and the line count deleted (1,903).

### C5 — four catalog ids — **M**

**Files:** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`, and a new
`Features/Coach/GoalFixtures.swift`.

Four ids, one commit, all four contract parts (global constraint 3):

| id | frame | renders |
|---|---|---|
| `goal-screen` | 93 | `GoalScreenView(onChosen: { _ in }, suggested: .strength)` |
| `goal-milestone-strength` | 94 | `GoalMilestoneView(preset: .strength, …)` seeded at 205 → 225 by Oct 18 |
| `goal-milestone-body-composition` | 95 | `GoalMilestoneView(preset: .bodyComposition, …)` at 190 → 178 |
| `goal-milestone-recovery` | 96 | `GoalMilestoneView(preset: .recovery, …)`, six weeks, no date |

**Hermetic** (global constraint 7): `GoalFixtures` holds integers, strings and two fixed epoch seconds;
`today` is `StubBlockGoalRepository.fixtureCreatedAt`; `unitOverride: .lbs` so the frame reads `lb` whatever
the capturing simulator's account is set to; `onChosen`/`onBuild` are `{ _ in }`; `lifts` and `routines` are
fixture arrays, never a repository. Wrap each in a `NavigationStack` (the pages set `.navigationTitle`, which
is a no-op without one — the reason `content_calendarScheduling` is wrapped).

**Do not bump `FLOOR`** — I4 does it once.

**TDD steps.** 1. Add the four cases + builders + ids + capture methods + frame-map entries in one commit.
2. Push. 3. `CatalogScreenTests` green (the count guard is the test), four new `app-goal-*.png` in the
artifact. 4. Commit: `feat(goal): four catalog ids — the goal screen and three milestone cards` + the trailer.

**Proves the stream:** `app-goal-screen`, `app-goal-milestone-strength`,
`app-goal-milestone-body-composition`, `app-goal-milestone-recovery` in the CI artifact, and the two greps in
C4's body.

---
# STREAM D — the ladder page and Home

Worktree `wt-goal-ui`, branch `feat/block-goal-ladder-ui`. 7 tasks. Owns 4 of the 8 new catalog ids.

Everything here builds against `StubBlockGoalRepository` (Task 0.4). D never fetches.

### D1 — the ladder page — **L**

**File (new):** `GymSyncApp/GymSync/Features/Coach/LadderPageView.swift`

Spec §6, top to bottom, in order:

```swift
struct LadderPageView: View {
    let goalID: UUID
    var repository: any BlockGoalRepository = StubBlockGoalRepository()
    /// Rendered directly when present — the catalog's hermetic path, the same
    /// `world` seam `CalendarSchedulingView` grew for the identical reason.
    var world: LadderPageModel? = nil
    var onEditMilestone: () -> Void = {}
    var onEditRung: () -> Void = {}
}
```

| # | element | detail |
|---|---|---|
| 1 | **the milestone as the headline** | `page.headline` — `Bench 225 by Oct 18` — `GSFont.heading(26)`, `theme.text`, the largest thing on the page (rule 3) |
| 2 | **the date** | `page.dateLine`, 12 pt, `neutral500`; absent entirely when empty (a held-for-the-block goal has no date, and a blank line is not a state) |
| 3 | **Coach's one line on standing** | `page.coachLine`, 13 pt body, `theme.neutral700`, tappable → a seeded Coach thread (rule 7). Accent **only** when `!page.reachesMilestone` — that is an invitation to act, which is one of accent's jobs (rule 2) |
| 4 | **the ladder** | one row per week inside **one** raised card (rule 1: one raised object per idea, rows inside it flat) |
| 5 | **the levers** | edit the milestone · edit the date · edit this week's rung · `LET COACH RE-LADDER` (raised) |
| 6 | **the save** | the one accent primary on the page (rule 4) |
| 7 | `SEE THE BLOCK ›` | a quiet row to `ProgramScheduleView`, so the schedule is one tap from the landing (C3) |

**A row** — week number and the target in words on the left, the implication under it, the status on the
right:

| status | rendering |
|---|---|
| `met` | fraction and the week number in `Color.gsSuccess` — the one green, in its "done" job (rule 2) |
| `missed` | `theme.neutral500`, muted — a missed week is a fact, not an error, and red is errors only |
| `current` | a 1.5 pt `theme.accent` ring around the row — accent's "current item in a pager" job |
| `ahead` | default text |
| `overridden` | `theme.neutral500` with the kicker `YOURS` |
| any, `isDeload` | the kicker `DELOAD` beside the week number — spec §3.2: the ladder shows the deload as what it is |

`row.note` renders as a third line in `neutral500` when present — the generator's own decision-log line,
pulled through `Program.notes` (A12), *"so the ladder says why a week is what it is"* (spec §6).

**No gold anywhere on this page.** Gold has exactly two jobs and neither is here (rule 2).

**Interfaces** — *consumes:* `BlockGoalRepository`, `LadderPageModel`, `LadderRow`, `RungStatus`,
`Color.gsSuccess`, `GSMetrics`. *Produces:* `LadderPageView`.

**TDD steps.** The body is not unit-testable; the captures are the proof (D7). What is testable is the
status→style mapping, and it is extracted for exactly that reason:

1. Failing test — `GymSyncApp/GymSyncTests/LadderRowStyleTests.swift`: `LadderPageView.style(for:)` returns
   green for `.met`, muted for `.missed` and `.overridden`, a ringed style for `.current`, default for
   `.ahead`; `LadderPageView.kicker(for:isDeload:)` returns `"DELOAD"` for a deload row, `"YOURS"` for an
   overridden one, `""` otherwise; **red appears in no branch** (assert the returned colour is never
   `Color.red`).
2. Push; fails.
3. Implement.
4. Push; green.
5. Commit: `feat(goal): the ladder page — the milestone, the standing, and one row per week` + the trailer.

### D2 — the strip's block kicker and its destination — **M**

**File:** `GymSyncApp/GymSync/Features/Home/HomeView.swift`.

Two changes, both in `goalStripSection` (:737-752) and `fetchWeeklyGoal` (:1630-1655):

1. **The kicker.** `fetchWeeklyGoal` already returns a `(goal, progress, proposal)` tuple; it gains a fourth
   member, `blockGoalID: UUID?`, read from `goal.params.goalID`. Nothing in `HomeView` computes the kicker —
   `LiveWeeklyGoalRepository.progress(for:)` does (A14), and `HomeView` renders `progress.kicker` exactly as
   it does today. **This task changes no arithmetic on Home**, which is the agreement law
   (`HomeView.swift:744-747`) held.
2. **The destination.** The strip's tap opens the **ladder page** when the row belongs to a ladder, and the
   shipped `WeeklyGoalEditorSheet` when it does not:

```swift
    /// I1: a row that belongs to a ladder opens the LADDER PAGE (spec §6:
    /// "Tap the strip → the Ladder page"); a standalone weekly goal opens the
    /// editor exactly as it does today. Both are one tap from the strip, and
    /// which one you get is a fact about the row, not a mode.
    ///
    /// The editor is still reachable from the ladder page — "edit this week's
    /// rung" is one of its levers (task D3) — so nothing that could be edited
    /// before became unreachable.
    private var goalStripSection: some View {
        Group {
            if goalLoaded {
                HomeWeeklyGoalStrip(kind: weeklyGoal?.kind, progress: goalProgress) {
                    guard appState.currentProfile?.id != nil else { return }
                    if let blockGoalID {
                        pushedLadderGoalID = blockGoalID
                    } else {
                        goalEditorWeeklySessionGoal = profile?.weeklySessionGoal ?? 3
                        showGoalEditor = true
                    }
                }
            } else {
                goalStripSkeleton
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }
```

with `.navigationDestination(item: $pushedLadderGoalID) { LadderPageView(goalID: $0) }` on the page root —
**not** a `PendingRoute` case, for the reason `HomeView.swift`'s B3 note gives: that enum is for push
deep-links (`App/AppState.swift:70-75`) and this is not one.

**Do not touch** the 20-minute check-in window, the 30-minute cutoff, `tabRefreshTTL`, the
`TimelineView(.periodic(by: 30))` cadence, or the 2.4 s gold shimmer.

**TDD steps.** 1. Extend `GymSyncApp/GymSyncTests/HomeCompositionTests.swift`: a `WeeklyGoal` whose
`params.goalID` is set resolves to the ladder destination and one without it to the editor — extracted as
`HomeView.goalStripDestination(for:) -> GoalStripDestination` so it is a value, not a closure.
2. Push; fails. 3. Implement. 4. Push; green, and **`app-tab-home` still renders a goal strip** (the CI
account's seeded row has no `goal_id` until I2 gives it one, so it opens the editor — which is correct).
5. Commit: `feat(goal): the strip carries the block and opens the ladder` + the trailer.

### D3 — the editor, scoped to a rung — **M**

**File:** `GymSyncApp/GymSync/Features/Home/WeeklyGoalEditorSheet.swift`.

Spec §4: *"An athlete's edit of this week's row is an override of the rung: the row becomes `source = user`,
the ladder marks the rung `overridden`, re-laddering starts from actuals as before, and Coach's propose-only
rule protects the override."*

**Almost nothing changes**, and that is the design working: the editor already writes `source = .user`
through `WeeklyGoalRepository.save` (`WeeklyGoalLiveRepository.swift:122-129`), and
`WeeklyGoalWriteRule.shouldOverwrite` already refuses to let Coach write over a `user` row. Two additions:

1. **A rung header.** A new optional input `var rung: RungContext? = nil` carrying
   `(weekNumber: Int, weekCount: Int, milestone: String)`. When present, the header's second line reads —
   verbatim, replacing the standing copy line for this case only:

   > `Week 3 of 8 of "Bench 225 by Oct 18". Change this week and Coach ladders from where you actually are.`

   The shipped line (`Coach set this from your block. Change it here; Coach follows your lead for the rest of
   the week.`) stays for a standalone goal — it is `WeeklyGoalEditorSheet.swift:265-268`, untouched.
2. **`goalID` survives the save.** `params()` (:881) currently builds a fresh `WeeklyGoalParams` per kind, so
   an edit would **drop `params.goalID`** and orphan the row from its ladder. One line at the end of
   `params()`: `params.goalID = goal?.params.goalID`. Without it the ladder loses the week it was overridden
   in — the single most likely defect in this stream, and the reason it has its own test.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/WeeklyGoalEditorParamsTests.swift` (new; the existing editor has
   no test file):

```swift
import XCTest
@testable import GymSync

/// The editor's params builder, at the one seam goal-first programming
/// touches: an override must stay attached to the rung it overrides.
final class WeeklyGoalEditorParamsTests: XCTestCase {

    func testAnOverrideKeepsTheRowAttachedToItsLadder() {
        let goalID = UUID()
        let existing = WeeklyGoal(
            userID: UUID(), weekStartString: "2099-01-04", kind: .muscleSets,
            params: WeeklyGoalParams(muscleTargets: ["chest": 12], goalID: goalID),
            source: .coach, setAt: Date(timeIntervalSince1970: 0))

        let edited = WeeklyGoalEditorSheet.params(
            kind: .muscleSets,
            muscleTargets: [.chest: 16, .back: 12],
            existing: existing)

        XCTAssertEqual(edited.goalID, goalID,
                       "an edit is an OVERRIDE of the rung, not a divorce from it")
        XCTAssertEqual(edited.muscleTargets?["chest"], 16)
        XCTAssertNil(edited.targetSource,
                     "the athlete typed these; they did not come from the block")
    }

    func testAStandaloneGoalStillCarriesNoLadder() {
        let edited = WeeklyGoalEditorSheet.params(
            kind: .days, muscleTargets: [:], existing: nil)
        XCTAssertNil(edited.goalID)
    }
}
```

> This requires lifting `params()` out of the view as a `static func` taking its inputs — do that, and have
> the instance method call it. A view-private closure over `@State` cannot be tested, and this is the one
> piece of the editor that must not silently lose data.

2. Push; fails.
3. Lift `params()`, add the `goalID` carry-through, add the `RungContext` header branch.
4. Push; green, and `app-home-goal-editor` / `app-home-goal-editor-lift` **unchanged** — those fixtures pass
   no `rung`, so the standing copy line still renders.
5. Commit: `feat(goal): editing this week is an override of the rung` + the trailer.

### D4 — the ladder card on the schedule page — **M**

**Files:** `GymSyncApp/GymSync/Features/Coach/LadderCard.swift` (new),
`GymSyncApp/GymSync/Features/Coach/ProgramScheduleView.swift`.

Spec §6: *"The block's schedule page (`ProgramScheduleView`) gains the ladder card at the top, above 'Why this
block', and keeps everything else."*

`LadderCard(page:onOpen:)` — a raised card (rule 1) carrying the headline, Coach's standing line, the
**current rung** and the two either side of it, and a `SEE THE LADDER ›` footer to `LadderPageView`. Three
rows, not eight: the schedule page is about the block's days and the card is a door, not a second ladder.

Placement in `ProgramScheduleView.body` (:67-97), in the `enrollment != nil && !weeks.isEmpty` branch —
**above `arcCard`**, because the goal is what the block is for and the arc is how it gets there:

```swift
                    BlockCalendarView(...)
                    ladderCard                 // NEW — above the arc and the reasoning
                    arcCard
                    routinesCard
                    reasoningCard
```

`ladderCard` is `@ViewBuilder` and renders **nothing at all** when the block has no goal (a migrated block
before A13's detection lands, or a failed 7b write). No empty state, no reserved gap — the same posture
`crewPulseSection` takes on Home (`HomeView.swift:670-682`).

**Do not touch** `reasoningCard` (:416), `provenanceCard` (:467) or `changesCard` (:517). The four
type-checker-timeout precedents in this codebase (context map §"Deepest nested generic view chains") say a
`ScrollView > VStack` gaining one child is safe and a `body` gaining modifiers is not; this adds one child.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/LadderCardTests.swift`. The windowing is pure and is the only
   thing here that can be wrong in a way a capture would not show:

```swift
import XCTest
@testable import GymSync

final class LadderCardTests: XCTestCase {

    private func rows(_ count: Int, currentAt: Int) -> [LadderRow] {
        (0..<count).map { index in
            .init(weekNumber: index + 1, weekStartString: "2026-09-06",
                  targetText: "3 × 5 at \(190 + index * 5)", implication: nil,
                  status: index == currentAt ? .current
                        : (index < currentAt ? .met : .ahead),
                  isDeload: false, note: nil)
        }
    }

    func testTheWindowIsTheCurrentRungAndTheOneEitherSide() {
        let window = LadderCard.window(rows(8, currentAt: 3))
        XCTAssertEqual(window.map(\.weekNumber), [3, 4, 5])
    }

    func testTheWindowClampsAtBothEnds() {
        XCTAssertEqual(LadderCard.window(rows(8, currentAt: 0)).map(\.weekNumber),
                       [1, 2, 3])
        XCTAssertEqual(LadderCard.window(rows(8, currentAt: 7)).map(\.weekNumber),
                       [6, 7, 8])
    }

    func testAOneWeekLadderRendersOneRowAndDoesNotCrash() {
        XCTAssertEqual(LadderCard.window(rows(1, currentAt: 0)).count, 1)
        XCTAssertTrue(LadderCard.window([]).isEmpty)
    }

    func testALadderWithNoCurrentRungWindowsFromTheStart() {
        // Every rung ahead — a block booked but not yet begun.
        let allAhead = rows(8, currentAt: 0).map { row in
            LadderRow(weekNumber: row.weekNumber, weekStartString: row.weekStartString,
                      targetText: row.targetText, implication: row.implication,
                      status: .ahead, isDeload: row.isDeload, note: row.note)
        }
        XCTAssertEqual(LadderCard.window(allAhead).map(\.weekNumber), [1, 2, 3])
    }
}
```

2. Push; fails to compile.
3. Implement `LadderCard.window(_:)` and the card, then insert `ladderCard` above `arcCard`.
4. Push; green.
5. Commit: `feat(goal): the ladder card tops the block's schedule page` + the trailer.

### D5 — the ledger's goal row — **S**

**File:** `GymSyncApp/GymSync/Features/Coach/ProgramLedgerView.swift`.

Spec §6: *"The ledger records the goal's outcome with each finished block: met, missed, or partial, with the
milestone and the final measured value."*

`pastRow(_:)` (:190) gains a **second line under the status line**: the block's milestone, and its outcome
when one is recorded.

```swift
    /// The goal this block was for, and how it came out.
    ///
    /// PHASE 1 RENDERS, PHASE 3 WRITES. `block_goals.outcome` is only ever set
    /// by the block-end check (spec §7, phase 3), so today this line is the
    /// milestone alone for every row — which is already the thing the ledger
    /// was missing: a finished block that does not say what it was FOR is a
    /// row nobody can read.
    ///
    /// Absent entirely for a block with no goal (every block built before this
    /// feature). No placeholder, no "no goal set" — the ledger is a record, and
    /// a record does not editorialise about its own gaps.
    static func goalLine(_ goal: BlockGoal?, liftName: String, unit: WeightUnit,
                         calendar: Calendar = .current) -> String?
```

Rendering: 11 pt body in `neutral500`; when `goal.outcome` is present, the outcome word leads in
`Color.gsSuccess` for `.met` and `neutral500` for `.missed`/`.partial` — **green means done, and nothing here
is red** (rule 2), because a missed block is a fact.

The goals are fetched alongside the enrollments in `load()` (:258) — one `.in("enrollment_id", …)` read for
every row on screen, not one per row.

**TDD steps.**

1. Failing test — `GymSyncApp/GymSyncTests/LedgerGoalLineTests.swift`:

```swift
import XCTest
@testable import GymSync

final class LedgerGoalLineTests: XCTestCase {

    private func goal(_ outcome: GoalOutcome?) -> BlockGoal {
        BlockGoal(id: UUID(), userID: UUID(), enrollmentID: UUID(),
                  metric: .liftOneRepMax,
                  target: GoalTarget(targetWeightLbs: 225),
                  byDate: Date(timeIntervalSince1970: 1_792_411_200),   // 2026-10-18
                  preset: .strength, source: .user, outcome: outcome,
                  outcomeValue: outcome == nil ? nil : GoalTarget(targetWeightLbs: 227),
                  createdAt: Date(timeIntervalSince1970: 0),
                  updatedAt: Date(timeIntervalSince1970: 0))
    }

    func testAFinishedBlockSaysWhatItWasForAndHowItCameOut() {
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(.met), liftName: "Bench", unit: .lbs,
                                       calendar: Calendar(identifier: .gregorian)),
            "MET — BENCH 225 BY OCT 18")
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(.missed), liftName: "Bench", unit: .lbs,
                                       calendar: Calendar(identifier: .gregorian)),
            "MISSED — BENCH 225 BY OCT 18")
    }

    func testAnOutcomelessGoalStillNamesTheMilestone() {
        XCTAssertEqual(
            ProgramLedgerView.goalLine(goal(nil), liftName: "Bench", unit: .lbs,
                                       calendar: Calendar(identifier: .gregorian)),
            "BENCH 225 BY OCT 18",
            "phase 1 renders; phase 3 writes the outcome")
    }

    func testABlockWithNoGoalRendersNothingAtAll() {
        XCTAssertNil(ProgramLedgerView.goalLine(nil, liftName: "", unit: .lbs,
                                                calendar: Calendar(identifier: .gregorian)),
                     "a record does not editorialise about its own gaps")
    }
}
```

> The line is a kicker (caps, `neutral500`, 0.8 tracking — design rule 3), which is why the expected strings
> are upper-cased: it sits directly under `statusLine(_:)`, which is already a kicker
> (`ProgramLedgerView.swift:211-215`), and two adjacent metadata lines in different cases read as two
> different kinds of thing.

2. Push; fails to compile (`goalLine` must be `static` and take its inputs — lift it out of the view).
3. Implement, and fetch the goals alongside the enrollments in `load()`.
4. Push; green.
5. Commit: `feat(goal): the ledger says what each block was for` + the trailer.

### D6 — Coach's line carries ladder proposals — **M**

**File:** `GymSyncApp/GymSync/Features/Home/HomeView.swift`.

Spec §6: *"Coach's line on Home (rung (a) of `coachSentence`) carries ladder proposals: a date move, a target
change, a rung Coach would raise."*

`coachSentence` (:866) already has rung (a) — `if let proposal = goalProposal { return proposal.sentence }`.
This task **widens what can produce that proposal**, without moving the precedence:

```swift
    // (a) now has TWO sources, in this order:
    //     (a1) a LADDER proposal — the re-derived ladder can no longer reach
    //          the milestone by its date, so Coach proposes a new one
    //          (spec §3.5: "Coach proposes a new date (or target) through the
    //          propose channel"). It leads because it is about the BLOCK, and
    //          a block-level gap outranks a week-level difference.
    //     (a2) the shipped weekly proposal (`WeeklyGoalProposalRule`),
    //          unchanged.
    private var coachSentence: String {
        if let ladder = ladderProposal { return ladder }
        if let proposal = goalProposal { return proposal.sentence }
        if let line = todaysRoutineSentence { return line }
        if let line = blockWeekSentence { return line }
        return "Tell me how the week's going and I'll shape the next one."
    }
```

`ladderProposal` is `page.reachesMilestone == false ? page.coachLine : nil`, read from the same
`LadderPageModel` `fetchWeeklyGoal` already has the goal id for — **one extra read, only for an athlete with a
block whose ladder falls short**. The tap target is unchanged: the Coach tile opens `CoachHomeView`
(`HomeView.swift:681-684`), which is where a conversation about the date belongs.

**Nothing is written.** Owner decision 8: Coach proposes date moves and never makes them. The athlete accepts
on the ladder page's own levers (D1).

**TDD steps.**

1. Failing test — append to `GymSyncApp/GymSyncTests/HomeCompositionTests.swift`:

```swift
    func testCoachsLinePutsTheBlocksGapAboveTheWeeksDifference() {
        XCTAssertEqual(
            HomeView.coachSentence(ladderProposal: "This ladder reaches 218 — move the date?",
                                   goalProposal: "Coach suggests 15 mi of running this week.",
                                   todaysRoutine: "Pull A today — take 185 × 8, then we climb.",
                                   blockWeek: "Week 2 of 6. Three days on the books."),
            "This ladder reaches 218 — move the date?",
            "a block-level gap outranks a week-level difference")
    }

    func testTheShippedPrecedenceIsOtherwiseUnchanged() {
        XCTAssertEqual(
            HomeView.coachSentence(ladderProposal: nil,
                                   goalProposal: "Coach suggests 15 mi of running this week.",
                                   todaysRoutine: "Pull A today.", blockWeek: "Week 2 of 6."),
            "Coach suggests 15 mi of running this week.")
        XCTAssertEqual(
            HomeView.coachSentence(ladderProposal: nil, goalProposal: nil,
                                   todaysRoutine: "Pull A today.", blockWeek: "Week 2 of 6."),
            "Pull A today.")
        XCTAssertEqual(
            HomeView.coachSentence(ladderProposal: nil, goalProposal: nil,
                                   todaysRoutine: nil, blockWeek: "Week 2 of 6."),
            "Week 2 of 6.")
        XCTAssertEqual(
            HomeView.coachSentence(ladderProposal: nil, goalProposal: nil,
                                   todaysRoutine: nil, blockWeek: nil),
            "Tell me how the week's going and I'll shape the next one.")
    }

    func testAReachingLadderProposesNothing() {
        let page = StubBlockGoalRepository.fixturePage      // reachesMilestone == true
        XCTAssertNil(HomeView.ladderProposal(from: page),
                     "Coach proposes a date move only when the ladder cannot make the one set")
    }
```

2. Push; fails to compile.
3. Lift `coachSentence` to `static func coachSentence(ladderProposal:goalProposal:todaysRoutine:blockWeek:)
   -> String`, have the computed property call it, and add
   `static func ladderProposal(from: LadderPageModel?) -> String?`.
4. Push; green.
5. Commit: `feat(goal): Coach's line carries the ladder's proposal` + the trailer.

### D7 — four catalog ids — **M**

**Files:** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`,
`Features/Coach/GoalFixtures.swift` (extend C5's file — **coordinate: C creates it, D extends it; resolve in
I1 by concatenating**).

| id | frame | renders |
|---|---|---|
| `ladder-on-track` | 97 | `LadderPageView(goalID:, world: StubBlockGoalRepository.fixturePage)` — `On track`, three met, one current |
| `ladder-behind` | 98 | the same ladder with `reachesMilestone: false` and `coachLine: "This ladder reaches 218 — move the date?"` (spec §6 verbatim), one `missed` rung and one `overridden` |
| `ladder-met` | 99 | every rung `met`, `coachLine: "Met — you hit 225 on October 11."` |
| `home-goal-strip-block` | 100 | `WeeklyGoalStripFrame(kind: .muscleSets, progress: …)` with the block kicker `WEEK 3 OF 8 · COACH'S GOAL` — reusing `WeeklyGoalFixtures.muscleSets`' four chips exactly, so this frame and the shipped `home-goal-strip-muscle-sets` differ **only** in the kicker, which is the whole change |

**Hermetic:** `world:` is passed so `LadderPageView` never touches a repository; every date is a fixture
string already baked into `LadderPageModel`; `onEditMilestone`/`onEditRung` are `{}`.
Wrap the three ladder ids in a `NavigationStack`.

**Do not bump `FLOOR`.**

**TDD steps.** 1. Add the four cases + builders + ids + capture methods + frame-map entries, one commit.
2. Push. 3. `CatalogScreenTests` green; four new PNGs. 4. Commit:
`feat(goal): four catalog ids — the ladder page in three states and the block strip` + the trailer.

**Proves the stream:** `app-ladder-on-track`, `app-ladder-behind`, `app-ladder-met`,
`app-home-goal-strip-block` in the artifact, plus `app-home-goal-editor*` and
`app-home-v3-08a-targets-above-calendar` **unchanged**.

---

# INTEGRATION

Branch `feat/goal-first-release`. Runs after all four streams are pushed. 6 tasks.

### I1 — merge the streams and swap the stubs — **M**

**Merge order — A, then B, then C, then D.** Rationale: A is pure additions plus two migrations and touches no
view; B changes `ProgramBuilder.build`'s signature, which every later stream must compile against; C rewires
the four build doors and deletes the wizard (a large, mostly-deletion diff that must not race D's edits to
`ProgramLedgerView`); D is last so Home and the ladder page integrate against everything real.

**Conflicts to expect, all append-only** — resolve by concatenating in frame order, never renumbering:
`CatalogHostView.swift`'s enum and switch (C: 4, D: 4), `CatalogScreenTests.swift`'s `ids`,
`ScreenshotTests.swift`'s method list, `frame-map.json`, `Features/Coach/GoalFixtures.swift`.
One genuine two-stream file: `ProgramLedgerView.swift` (C4 rewires `buildDoor`, D5 adds `goalLine` to
`pastRow`) — different functions; take both.
One genuine two-stream symbol: `LadderMath.weekStartStrings(from:count:)` (A9's file, B4's need) — keep one.

**Then the swaps, one commit:**

- default `BlockGoalRepository` binding: `StubBlockGoalRepository` → `LiveBlockGoalRepository` at
  `ProgramBuilder.build`'s parameter default, `LadderPageView.repository`, and `HomeView`'s init. The stub
  **stays in the codebase** — the catalog captures use it.
- Home's strip destination: the ladder branch goes live (D2 already wrote it; verify `LadderPageView` is the
  destination and not `ProgramScheduleView`).
- `ConsultEntryView`'s `onBuilt` hosts push `LadderPageView` rather than `ProgramScheduleView` (C3's deferred
  line, four hosts, now one — `GoalFirstBuildFlow`).
- `LiveWeeklyGoalRepository.progress(for:)` uses `blockKicker` (A14 already wrote it; verify the call is
  reached, i.e. `params.goalID` is non-nil on a materialised row — I2's seed is what proves it end to end).

### I2 — the CI account gets a block, a goal and a ladder — **M**

**File:** `scripts/seed_qa_fixtures.js`.

Follow the file's own idempotence idiom (:26-36 and the `weekly_goals` block at :989-1000): compute at run
time, upsert on the natural key, scope everything to `me.id`, and say in the comment that the row is
genuinely live in the shared project and inert for real users because of RLS.

The seed adds, in this order:

1. a `program_enrollments` row for `me` when none is active — `template_slug` `'coach-qa-fixture'`,
   `started_on` = the current week's Sunday, `weeks` 8, `focus` `{"exercise_ids":["<bench id>"]}`,
   `baseline` `{"<bench id>": 205}`;
2. a `block_goals` row for that enrollment — `metric` `'lift_one_rep_max'`, `preset` `'strength'`,
   `source` `'coach'`, `target` `{"exerciseID":"<bench id>","targetWeightLbs":225}`, `by_date` = the
   enrollment start + 56 days. **Upserted on `enrollment_id`**, which is the table's own unique key, rather
   than delete-then-insert: the goal is real history the script must not churn;
3. eight `block_goal_rungs`, week 0..7, `week_start` walking forward one week at a time from the enrollment
   start, targets `{"targetWeightLbs": 190 … 225}` with week 5 at 175, statuses
   `met, met, current, ahead, ahead, ahead, ahead, ahead`;
4. the **existing** `weekly_goals` upsert gains `goal_id` and `rung_index: 2`, and its `params` gains
   `"goalID": "<the goal id>"` — so `app-tab-home` renders the block kicker `WEEK 3 OF 8 · COACH'S GOAL`
   rather than `THIS WEEK · COACH'S GOAL`. **This is the end-to-end proof that A14, A10 and D2 agree.**

The week walk uses the file's own `currentWeekStartSunday()` (:97-101) and its stated skew caveat; do not
write a second week rule.

Commit: `test(goal): the CI account gets a block, a goal and a ladder` + the trailer.

### I3 — the frozen-frame canary — **S**

Before touching `FLOOR`, pull the artifact from I1's run and diff these three against the run that produced
them on `origin/master`:

- `app-home-v3-08a-targets-above-calendar` — **must be byte-identical** (global constraint 8);
- `app-home-v3-08b-targets-above-join` — **must be byte-identical**;
- `app-home-goal-strip-muscle-sets` — must be identical, and is the tighter canary: it renders the *production*
  strip through `HomeWeeklyGoalStrip`, which Task 0.3 and D2 both edited.

`node scripts/parity_diff.js` against the two artifacts if you have both; otherwise a two-up by eye. **A
non-zero diff on any of the three is a defect in 0.3 or D2, not an acceptable change** — find it. The most
likely cause is the four new `switch` arms perturbing the `@ViewBuilder`'s layout of the existing five.

Commit only if a fix was needed: `fix(goal): restore the frozen Home frames` + the trailer.

### I4 — `FLOOR`, frame-map and accepted deviations — **S**

- `.github/workflows/ios.yml:349` — `FLOOR=98` → `FLOOR=106`. One edit, this task only. Update the comment
  above it the way I3 of the Home v3 plan did: *"goal-first phase 1: 98 → 106; eight ids, one capture each."*
- `docs/design/frame-map.json` — verify all eight entries present, frames 93–100, no duplicates, no
  renumbering of 71–92.
- `docs/design/accepted-deviations.json` — add entries for the eight ids. None of them has an authoritative
  canvas frame (there was no proof round for goal-first programming; the spec is the authority), which is the
  same posture the `home-v3-*` and `calendar-scheduling` entries already take. One entry per id, each naming
  the spec section it renders.

Commit: `chore(goal): FLOOR 98 -> 106, frames 93-100, accepted deviations` + the trailer.

### I5 — end-to-end CI — **M**

Push and read the run.

**iOS workflow**
- build green;
- `GymSyncTests` green — **16 new test files**: `BlockGoalModelTests`, `LadderRuleTests`,
  `LadderReadoutTests`, `LadderMathTests`, `BlockGoalMetricMathTests`, `BlockGoalLiveRepositoryTests`,
  `GoalBlockLengthTests`, `GoalGeneratorInputTests`, `ProgramBuilderGoalTests`, `WeekBookerUnchangedTests`,
  `GoalScreenCopyTests`, `GoalMilestoneCopyTests`, `LadderRowStyleTests`, `WeeklyGoalEditorParamsTests`,
  `LadderCardTests`, `LedgerGoalLineTests` — plus the extended `WeeklyGoalModelTests`,
  `WeeklyGoalProgressTests` and `HomeCompositionTests`;
- the screenshot job exports **≥ 106** app captures and "Verify capture count" passes.

**Backend workflow**
- pgTAP green for `block_goals_test.sql` (new, 20 assertions) and `weekly_goals_test.sql` (extended, 28) —
  which requires A1 and A2's migrations to be **applied to the project first** (the Stream A gate).

**Then read the artifact, by eye, in this order:**

1. `app-tab-home` — the strip's kicker reads `WEEK 3 OF 8 · COACH'S GOAL` from I2's seed;
2. `app-goal-screen` — ten tiles, one Coach-suggested kicker, the Pro door disabled with its badge;
3. `app-goal-milestone-strength` / `-body-composition` / `-recovery` — one primary each, questions above the
   fold, Coach's line under the levers;
4. `app-ladder-on-track` / `-behind` / `-met` — the headline is the largest thing; the deload row says DELOAD;
   `-behind` shows the gap sentence and no red;
5. `app-home-goal-strip-block` — identical to `app-home-goal-strip-muscle-sets` except the kicker;
6. `app-home-goal-editor` / `-editor-lift` — **unchanged**;
7. `app-home-v3-08a-targets-above-calendar` — **unchanged**. The last one is the canary; if it moved, I3 was
   not done.

Fix-forward any red; each fix is its own commit on the integration branch.

### I6 — one release PR, with proof cards — **M**

`feat/goal-first-release` → `master`. The body carries:

1. **What shipped**, in the spec's own vocabulary: the goal, the ladder, the block.
2. **The retirement ledger** — `CoachWizardView` (1,903 lines) deleted, with C4's two grep results.
3. **The eight new catalog ids** and the FLOOR change, as the table from this plan.
4. **The two migrations**, and how and when they were applied to `chjkkwqwdlmaxacwglzm`.
5. **The deliberate deviations**, each with its reason:
   - **ten tiles, eleven presets** — Rep strength is the Strength card's second lever, per spec §2.3, not an
     eleventh tile (the task brief said "eleven preset cards"; the spec is the authority and the plan follows
     it);
   - **three milestone captures, not eleven** — the three shapes, per this plan's "New catalog ids" note;
   - **the Pro door ships disabled** — the feature is phase 2, the gate is `Entitlements.hasPro`, and the
     door says so rather than routing nowhere;
   - **the 10 min/mi pace floor** in B3 — a stated assumption, not a measurement;
   - **`RateOfChangeLadderRule`'s clamp** and **`DescendingLadderRule`'s linear descent** — the two places the
     spec gave a range and the plan chose;
   - **`WeeklyGoalWriteRule.isLadderWeek`** — one new rule so `WeekBooker` could stay untouched.
6. **Proof cards**, one per stream, each a CI run URL plus the specific evidence:
   - **A** — Backend green (two pgTAP files), `GymSyncTests` green (6 files);
   - **B** — the generator's golden tests byte-identical for goal-less inputs;
   - **C** — the four `app-goal-*` captures, and the two greps;
   - **D** — the four new captures **and** the three frozen frames unchanged.
7. The trailer per constraint 2, plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.

---

## What this plan does not decide

1. **Which volume accounting Maintenance holds.** Spec §11.1 leaves it open and this plan inherits it: A13
   reads `volume_targets` when the titration has rows and the block's own prescribed sets otherwise, and
   `params.targetSource` records which. Reconciling `ProgramGenerator.weeklyMuscleSets` (per-muscle-string,
   uncapped) with `MuscleGroup.credit` (six groups, capped) is still frozen by global constraint 12 and still
   belongs to a follow-up round.
2. **How LISS is detected without Health.** A6 counts a cardio-**only** app session and Health's own
   walk/bike/row/elliptical/stairs minutes. It cannot tell an easy ride from intervals — that needs the
   watch's heart-rate samples, which is phase 2's `zone2MinutesPerWeek`. Spec §11.2's open item, unchanged.
3. **Whether an athlete may run a block with no goal at all.** `ProgramBuilder.build` requires one and A13
   detects one for every migrated block, so the answer today is no. Whether a "just give me a program" escape
   hatch should exist is a product question nobody has asked.
4. **Block end.** Spec §7 — the outcome check, the recap, the seeded next goal — is phase 3. Phase 1 renders
   `block_goals.outcome` where it exists (D5) and never writes it.
5. **The Coach-guided goal.** Phase 2. C1 ships the door disabled and names `Entitlements.hasPro` as the gate;
   nothing about the free path degrades.
6. **Re-laddering's trigger — RULED (controller, 2026-09-07), not open.** The "first Home load of the week"
   hook already exists: `HomeView.fetchWeeklyGoal` calls `WeeklyGoalRepository.detectIfMissing(weekStart:)`
   whenever the current week has no `weekly_goals` row (the final-review F1 seam on master). A10 therefore
   wires it: when `detectIfMissing` runs for a user with an active `BlockGoal`, it calls `reLadder` from
   actuals and then `materialiseRung` for the current week, and returns that row — so a new week re-ladders
   itself on its first Home load, exactly as spec §3.5 says. `LET COACH RE-LADDER` on the ladder page stays as
   the manual trigger. A10 adds the test: a user with an active goal, a `weekly_goals` row for last week only,
   and a changed actual → `detectIfMissing(thisWeek)` returns a `source = coach` row whose rung differs from
   last week's projection, and `block_goal_rungs` for the remaining weeks are rewritten while `met`/`missed`/
   `overridden` rungs are untouched.
6b. **Recovery's two-metric read — RULED (controller, 2026-09-07).** The primary metric (stretching count,
   from `set_logs`) wins the strip's fraction and right-hand read; the LISS companion renders as its own chip,
   and when Health is not connected that chip reads `CONNECT HEALTH` rather than `0 min` — the shipped rule
   applies per chip, never to the whole strip. 0.3's `recovery` arm carries this branch and a test (Health
   unavailable → LISS chip text is `CONNECT HEALTH`, stretching fraction unchanged).
7. **Push notifications** for a milestone met, a rung missed, or a date proposal. Not designed, not built.
8. **A second concurrent goal.** Explicitly out — one primary goal per block is owner decision 2
   (spec §11.5).
9. **What happens to a ladder when the athlete rebuilds mid-block.** `ProgramBuilder` retires the old
   enrollment (`ProgramBuilder.swift:252-256`) and `block_goals.enrollment_id` cascades, so the old goal and
   its rungs are deleted with it. Whether a finished-early block's ladder should survive into the ledger is
   phase 3's question, alongside the outcome it would carry.
10. **The `sessionsOfType` vocabulary still has no schema.** `WeeklyGoalProgressMath.sessionCounts` infers the
    type from exercise categories and routine names; a `benchmarkTime` goal now leans on the same inference to
    know which sessions were runs of the named routine — except that one has a real `routineID`, which is
    strictly better. A `session_type` column remains the honest fix and remains out of scope.

## New catalog ids and the FLOOR

| id | frame | title | stream | proves |
|---|---|---|---|---|
| `goal-screen` | 93 | Goal screen — the presets and the Pro door | C | spec §5.1: ten preset cards, the Pro door badged |
| `goal-milestone-strength` | 94 | Milestone card — strength | C | spec §5.2: the lift, the load, the date, Coach's line; the max/reps switch |
| `goal-milestone-body-composition` | 95 | Milestone card — body composition | C | spec §2.3: a target weight **or** a rate |
| `goal-milestone-recovery` | 96 | Milestone card — recovery | C | spec §2.3: two metrics, no date |
| `ladder-on-track` | 97 | Ladder page — on track | D | spec §6: headline, `On track`, met/current/ahead, DELOAD |
| `ladder-behind` | 98 | Ladder page — behind, with a proposal | D | spec §3.5 and §6: `This ladder reaches 218 — move the date?`, a missed rung, an overridden one |
| `ladder-met` | 99 | Ladder page — milestone met | D | spec §7's outcome, rendered before phase 3 writes it |
| `home-goal-strip-block` | 100 | Weekly goal strip — the block kicker | D | spec §6: `WEEK 3 OF 8 · COACH'S GOAL` |

**`FLOOR` 98 → 106**, in integration task **I4**, once, for all eight.

---

## Self-review (run by the planner, 2026-09-07)

**1. Spec coverage — every §2–§9 phase-1 requirement maps to a task.**

| spec | requirement | task |
|---|---|---|
| §2.1 | `BlockGoal` — metric, target, date, preset, source | 0.1 |
| §2.1 | `source` follows the shipped rule; Coach proposes, never overwrites | A11 (`save` stamps `.user`), B6, D6 |
| §2.2 | the registry: 5 shipped readers reused, 4 new, Recovery's 2 new | A5, A6 (shipped five explicitly not duplicated) |
| §2.2 | a metric that cannot be read renders `CONNECT HEALTH`, never `0` | A6 + the shipped `connectHealthRead` path |
| §2.3 | eleven presets, all free, all from launch | 0.1 (`GoalPreset`), C1 (ten tiles), C2 (the Strength card's second lever) |
| §2.3 | Maintenance = every major group | B1 (`focusMuscles = nil`), C2 (seeds all six) |
| §2.3 | Recovery = two metrics, one goal | 0.1, A6, A10 (one `recovery` row carries both) |
| §2.4 | Coach-guided goals (pro) | **phase 2** — C1 ships the door, badged and disabled, and names the gate |
| §3.1 | `LadderRung`, `Ladder`; the ladder is a read-out | 0.2, A8 |
| §3.2 | strength rung = prescribed loading; deload is a rung; the gap is never hidden | A8, B5, D1 |
| §3.3 | muscle/maintenance rungs = the week's planned effective sets | A8 |
| §3.4 | ramp rules, pure, with tests | A7 |
| §3.4 | the rung reaches the generator where it changes the plan | B3 |
| §3.5 | adaptive re-laddering from actuals; rewrite ahead/current only | A9 |
| §3.5 | Coach proposes a new date; the ladder shows the gap | B5, A12, D6 |
| §4 | the weekly goal is the materialised rung; the §4 mapping table | A10 |
| §4 | four new kinds, seven new params, `goal_id`/`rung_index` | 0.3, A2 |
| §4 | an edit is an override of the rung | D3 |
| §5.1 | the goal screen: preset grid + the Pro door | C1 |
| §5.2 | one milestone card per preset; Coach's line | C2 |
| §5.3 | `BUILD MY BLOCK`; the goal as a generator input; landing on the ladder | B1, B2, B3, C3 |
| §5.4 | no block without a goal; the wizard decided; migrated blocks | B4, C4, A13 |
| §6 | Home strip's block kicker; tap → the ladder page | A14, D2 |
| §6 | the ladder page | D1 |
| §6 | `ProgramScheduleView`'s ladder card | D4 |
| §6 | `ProgramLedgerView`'s outcome row | D5 |
| §6 | `coachSentence` rung (a) | D6 |
| §7 | block end | **phase 3** — D5 renders the outcome column phase 3 fills |
| §8 | the two tables, RLS, triggers, pgTAP | A1, A2, A3, A4 |
| §9 | pro gating; nothing about the free path degrades | C1 (`Entitlements.hasPro`) |

**Gaps I could not close, and they are named rather than papered over:**

- **§3.5's automatic weekly re-ladder has no trigger.** "When the new week starts (or on the first Home load
  of the week)" needs a first-refresh-of-a-new-week hook that Home does not have; `HomeView.refresh()` runs on
  every tab entry past a 60 s TTL and has no notion of a week boundary. This plan builds the re-ladder and
  gives it two manual triggers (the page's button, and materialisation). Item 6 of "What this plan does not
  decide".
- **§2.2's `CONNECT HEALTH` rule for the two new Health-backed reads.** The shipped rule is honoured for
  `distance` and `sessionsOfType` through `weeklyGoalHealthNeedsConnecting()`. A `recovery` goal's LISS half
  reads Health too — A6 returns 0 when Health is unavailable and the `recovery` strip arm (0.3) has no
  `CONNECT HEALTH` branch of its own, because its **primary** metric (the stretching count) comes from
  `set_logs` and is never zero for a reason the athlete cannot see. A recovery week with Health disconnected
  therefore reads `0 LISS min` beside a true stretch count. Flagged; the fix is one branch in 0.3's
  `recovery` arm and it is not in this plan because the spec does not say which half wins the read.

**2. Placeholder scan.** Grepped the finished document for `TBD`, `TODO`, `FIXME`, `XXX`, `add validation`,
`similar to Task`, `same as above`, `<fill`, `and so on`: **zero hits** other than four legitimate uses of the
word "placeholder" (Task 0.5's `HoldLadderRule` stubs, and CI's placeholder secrets). Every task names its
files, its interfaces and its commit. Three deliberate "phase 2 / phase 3" markers exist (§2.4, §7, the
outcome writer) — scope statements the spec itself makes, each listed in "What this plan does not decide".

**Five things the review changed, rather than noted:**

1. **The fixture helpers I first wrote do not exist.** The draft's A5/A6/A8 tests called
   `SetLog.fixture(...)`, `Exercise.fixture(...)`, `WorkoutSession.fixture(...)` and
   `RoutineExercise.fixture(...)`. Grep-verified at `origin/master`: **there is no `.fixture` helper anywhere
   in `GymSyncTests`.** The idiom is private per-file builders on the real memberwise initializers
   (`WeeklyGoalProgressTests.swift:14-37`, `HomeCompositionTests.swift:196-213`). Every test in this plan was
   rewritten onto that idiom, and A5's fixture block now says why — including that `completedReps` is
   **derived** from `reps` + `isFailed` (`SetLog.swift:41-45`), so a fixture must never set it directly.
2. **The invented pgTAP kind is `'steps'`, not `'foo'`** (`weekly_goals_test.sql:105`). A2 and A4 corrected,
   and A4 now also updates that assertion's stale "outside the five" message.
3. **`VolumeTarget` has no default on `reason`** (`RecoveryProbeRepository.swift:150-158`), so all three
   labels are required; **`ProgramEnrollment` is `Decodable`-only** (`:26`), so its fixture goes through JSON.
   Both stated at A13's test.
4. **`LadderMath.page`'s signature was written two ways** (an `Interfaces` block said
   `(goal:ladder:program:catalog:unit:now:)`, the tests said something else). One signature now, given in
   full at A12.
5. **`ProgramLedgerView.goalLine` was declared `private func` and called statically.** Now
   `static func goalLine(_:liftName:unit:calendar:)` in both places.

**3. Type consistency across tasks.** Every cross-task symbol was grepped across the finished document for a
single spelling; `materialiseCurrentRung` / `materializeRung` / `BlockGoalRepo` / `blockGoalRepo` return zero
hits, and the counts below are the grep's:

- `BlockGoalDraft` — introduced 0.1, consumed B1 (`Inputs.goal`), B4 (`build(goal:)`), C2
  (`GoalMilestoneCopy.draft`), C3, A13 (`LadderMath.detectedGoal`). One spelling throughout; `BlockGoal`
  itself never appears where an enrollment id does not yet exist.
- `GoalTarget` — the single target type for the milestone **and** every rung, in 0.1, 0.2, A5–A13, B5. No
  second "rung value" type exists.
- `BlockGoalRepository` — 0.4 declares six methods; A11 implements them; B4 adds `saveDerivedLadder` **as a
  protocol requirement with a default**, so the stub keeps compiling and the live type overrides. Called with
  the same labels in B4, C3, D1, D2.
- `LadderPageModel` — 0.2 declares it (7 fields); A12 builds it through
  `LadderMath.page(goal:ladder:liftName:rungSets:notesByWeek:deloadWeeks:unit:now:calendar:)`; D1, D4, D6 and
  D7 render it. `LadderRow`'s six fields are the same six at every site, including `LadderCardTests`'
  hand-built rows.
- `LadderCard.window(_:)`, `ProgramLedgerView.goalLine(_:liftName:unit:calendar:)`,
  `HomeView.coachSentence(ladderProposal:goalProposal:todaysRoutine:blockWeek:)`,
  `HomeView.ladderProposal(from:)`, `GoalMilestoneCopy.applying(_:exerciseID:targetWeightLbs:byDate:)` — the
  five statics this plan lifts out of views so they can be tested. Each is declared `static` in its task's
  prose and called `static` in its task's test.
- `WeeklyGoalKind` — nine cases after 0.3; A10's mapping, 0.3's nine switches and A2's CHECK list the same
  nine strings (`muscle_sets, distance, sessions_of_type, days, lift, recovery, body_weight, volume,
  benchmark`).
- `WeeklyGoalParams` — sixteen fields after 0.3; A10 writes only fields 0.3 declared; D3 carries `goalID`
  through; A2's COMMENT names the same key.
- `LadderRule` — one instance-method protocol (0.5); A7's five structs and `HoldLadderRule` all match it;
  `LadderRules.rule(for:)` returns `any LadderRule` in 0.5, A7, A9 and B4.
- `LadderMath.weekStartStrings(from:count:)` — the one symbol two streams both need (A9's file, B4's test).
  Named in both, with the coordination note in each.
- `WeeklyGoalProgressMath.blockKicker(source:met:daysLeft:weekNumber:weekCount:)` — A14 declares it, D2 and
  D7 consume its output as a string; the shipped `kicker(source:met:daysLeft:)` is untouched and still called.
