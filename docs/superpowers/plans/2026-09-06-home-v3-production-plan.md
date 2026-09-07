# Home v3 in production, the weekly goal system, and the calendar & scheduling page — implementation plan

Gate: `docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly-goal-design.md` (approved, with the
binding **Owner answers** section at its end). Design language:
`docs/superpowers/specs/2026-09-05-design-language.md`. Home element inventory:
`.superpowers/sdd/2026-09-04-investigations/screen-inventory-2.md` §1.

## Why

Home v3 has been judged and picked (variation **08a**, owner 2026-09-06) but it exists only as
catalog frames rendered from fixtures. Production `HomeView.swift` is still the 2026-07 declutter layout.
This plan moves 08a into production, builds the weekly-goal system its strip renders, and builds the
calendar & scheduling page the calendar card opens — as one release, per owner ruling 4.

The owner also ruled (4) that development is **paired**: a backend/model stream and three UI streams run
in parallel worktrees against an interface fixed first, and integrate at the end. That shape is the
plan's spine: **Task 0 is the interface**, then four independent streams, then integration.

---

## Base branch — read this first

**Every stream forks from `origin/master` (`ac3aa26` or later).** Master already carries everything this
plan builds on: the 23 Home V2/V3 pieces under `Features/Home/V2/` (PRs #29, #31, #32), the design doc
with the owner's binding answers (PRs #33, #34), the catalog contract at 71 ids / `FLOOR` 87, and the
screenshot pipeline fix. Production `HomeView.swift` and `TrainingCalendarWidget.swift` are untouched
on master.

> Correction (controller, 2026-09-06): the first draft of this section claimed the V2 pieces were not on
> master and told every stream to fork from `docs/home-goal-design @ 859ae88`. That came from a stale
> LOCAL `master` ref (`028602c`) in the main checkout; `origin/master` was ahead by every merge of the
> week. The ref has been fast-forwarded. Always verify against `origin/master`, never the local ref.

Task 0 lands on `feat/home-v3-release` forked from `origin/master`; the four streams fork from the tip
of Task 0.5; integration merges the streams back into `feat/home-v3-release`, which becomes the single
release PR.

## Binding global constraints

These apply to **every** task in this plan. A task that breaks one says so in its commit body and why.

1. **Swift compiles only in CI.** There is no macOS toolchain on this machine. You cannot run
   `xcodebuild`, `swift build`, or a simulator locally. Read the code you are changing, reason about
   the types, and push. CI (`.github/workflows/ios.yml`) is the compiler.
2. **One commit per task.** A task is the unit of review. Do not batch two tasks into one commit, and
   do not split one task across two commits unless CI forced a fix-up.
3. **The catalog four-part contract.** Any new `CatalogScreen` id must land in all four places in the
   *same commit*, plus the count guard:
   - the `case` in `App/CatalogHostView.swift` (`enum CatalogScreen`, :16-71) **and** its builder arm in
     the same file's `switch`;
   - the id string in `GymSyncTests/CatalogScreenTests.swift`'s `ids` array — the test asserts
     `CatalogScreen.allCases.count == ids.count`, so a case added without a list entry fails the build;
   - a `func testCatalog…() { captureCatalog("<id>") }` in `GymSyncUITests/ScreenshotTests.swift`
     (helper at :334);
   - an entry in `docs/design/frame-map.json` (`{"frame": <n>, "title": "<title>"}`; frames 71–82 are
     taken by home-v3-01…10 + 08a/08b, so **new ids start at frame 83**);
   - and the fifth touch: bump `FLOOR` in `.github/workflows/ios.yml:336` by the number of ids added.
     It is **87** today.
4. **Attribution trailer** on every commit:
   ```
   Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
   Claude-Session: https://claude.ai/code/session_01SMNTPsgf3mtFSr4awky8ni
   ```
   Use `git commit -F <file>` or a quoted heredoc — a `-m` message containing backticked identifiers has
   silently deleted words in this repo before.
5. **No product-timing constant changes.** Named explicitly, do not touch any of these:
   - the 20-minute check-in window (`HomeView.checkInOpensAt`, :616) and its server twin
     `20260715000003_checkin_window.sql`;
   - the 30-minute missed-session cutoff (`HomeView.todaysSession` :341, `nextActionableSession` :603);
   - `HomeView.tabRefreshTTL = 60` (:35);
   - the `TimelineView(.periodic(by: 30))` countdown cadence and the 2.4 s gold shimmer;
   - `ScreenshotTests.catalogRenderBudget` and `settle()`'s 0.3 s.
6. **Nothing user-facing merges until the whole ships together** (owner ruling 4). Stream branches merge
   into the integration branch `feat/home-v3-release`, never into `master` on their own. `master` sees
   exactly one PR, at the end.
7. **Every UI task names the CI capture that proves it.** For production Home that is **`app-tab-home`**
   (the signed-in walk, `ScreenshotTests` :247). For everything else it is a new catalog id from the
   table in "New catalog ids" below. A UI task whose only evidence is "it should look right" is not done.
8. **Do not change `ProgramGenerator.weeklyMuscleSets`** (`ProgramGenerator.swift:1871-1887`) or
   `VolumeAccountingTests`. See "What this plan does not decide" #1.

---

## New catalog ids (10) and the FLOOR

| id | frame | title | owner |
|---|---|---|---|
| `home-goal-strip-muscle-sets` | 83 | Weekly goal strip — muscle sets | Stream C |
| `home-goal-strip-distance` | 84 | Weekly goal strip — distance | Stream C |
| `home-goal-strip-sessions` | 85 | Weekly goal strip — sessions of a type | Stream C |
| `home-goal-strip-days` | 86 | Weekly goal strip — days | Stream C |
| `home-goal-strip-lift` | 87 | Weekly goal strip — a lift | Stream C |
| `home-goal-strip-met` | 88 | Weekly goal strip — goal met | Stream C |
| `home-goal-strip-empty` | 89 | Weekly goal strip — no goal yet | Stream C |
| `home-goal-editor` | 90 | Weekly goal editor — muscle sets | Stream C |
| `home-goal-editor-lift` | 91 | Weekly goal editor — a lift | Stream C |
| `calendar-scheduling` | 92 | Calendar & scheduling page | Stream D |

`FLOOR` **87 → 97**, bumped once, in integration task **I3** — not piecemeal by each stream, because
a stream branch that bumps FLOOR before its ids exist on the integration branch turns CI red for
everyone else.

---

## Dependency graph

```
                      ┌─────────────────────────────────────────┐
   master ── merge ──► │  Task 0 — THE INTERFACE (0.1 … 0.5)     │  branch: feat/home-v3-release
   docs/home-goal-     │  5 commits, sequential, one worktree    │
   master (ac3aa26)    └──────────────────┬──────────────────────┘
                                          │  everything below forks from the tip of Task 0.5
              ┌───────────────┬───────────┴───────────┬────────────────┐
              ▼               ▼                       ▼                ▼
      ┌───────────────┐ ┌───────────────┐   ┌──────────────────┐ ┌──────────────┐
      │ STREAM A      │ │ STREAM B      │   │ STREAM C         │ │ STREAM D     │
      │ data+backend  │ │ Home prod.    │   │ goal editor +    │ │ calendar &   │
      │ A1 … A12      │ │ B1 … B7       │   │ strip kinds      │ │ scheduling   │
      │               │ │               │   │ C1 … C4          │ │ D1 … D5      │
      │ worktree      │ │ worktree      │   │ worktree         │ │ worktree     │
      │ wt-goal-data  │ │ wt-home-v3    │   │ wt-goal-ui       │ │ wt-calendar  │
      └───────┬───────┘ └───────┬───────┘   └────────┬─────────┘ └──────┬───────┘
              └─────────────────┴────────────────────┴──────────────────┘
                                          ▼
                      ┌─────────────────────────────────────────┐
                      │  INTEGRATION  I1 … I5  (feat/home-v3-   │
                      │  release), then ONE PR to master        │
                      └─────────────────────────────────────────┘
```

**Cross-stream edges — the only ones that exist:**

| Edge | Why it is not a blocker |
|---|---|
| B needs the goal strip view | Task **0.3** ships `HomeWeeklyGoalStrip` as a working shell that renders `muscleSets` (today's chips) and the empty invitation. B composes against that shell and never edits it. C replaces its body. |
| B needs the calendar page to push | Task **0.4** ships `CalendarSchedulingView` as a scaffold (nav title, `SCHEDULE A SESSION`, empty agenda). B pushes it. D fills it in and never changes its type name or init. |
| B and C need real goal data | Task **0.2** ships `WeeklyGoalRepository` as a protocol with `StubWeeklyGoalRepository` (deterministic fixture goals). B and C wire to the protocol. A ships `LiveWeeklyGoalRepository`. **I1** swaps the default binding. |
| B needs friends-live | Task **0.5** ships `FriendsLiveRepository` protocol + a stub that returns `[]` (so the strip is absent, which is the shipping default until A9 lands). |
| C needs the exercise picker for the `lift` kind | Existing: `RoutinePickerSheet`-style catalog load via `ExerciseRepository.fetchAll()` (`Models/Exercise.swift:107`). No new dependency. |
| D needs the block/campaign rows | Existing repositories only: `ProgramRepository` (`Models/ProgramEnrollment.swift:82`), `CampaignRepository`, `SeriesRepository`, `SessionRepository.upcoming()` (`Models/SessionRepository.swift:443`). No new dependency. |

Streams A, B, C, D touch **disjoint file sets** except for three shared files, each owned by exactly one
stream: `CatalogHostView.swift` + `CatalogScreenTests.swift` + `ScreenshotTests.swift` are touched by
**C** (7 ids) and **D** (1 id) — resolve those two merges in **I1** by concatenating; they are
append-only lists.

---

# Task 0 — THE INTERFACE

Branch `feat/home-v3-release`, forked from `origin/master` (`ac3aa26` or later). Five commits.
**Nothing forks until 0.5 is pushed.** Size: **M** total.

### 0.1 — `MuscleGroup`, the rollup, and the secondary-credit rule — **S**

**File (new):** `GymSyncApp/GymSync/Models/MuscleGroup.swift`

The catalog's muscle vocabulary is 21 distinct lowercase strings, verified by extracting the
`primary_muscle` and `secondary_muscles` columns from every `INSERT INTO public.exercises` across
`supabase/migrations/` (1,117 rows: `20260709000003_seed_exercises.sql` 30,
`20260813000001_import_free_exercise_db.sql` 861, `20260814000006_machine_catalog.sql` 170,
`20260814000007_hammer_strength_catalog.sql` 47, `20260822000005_brand_exercises.sql` 9):

> `abductors adductors back biceps calves chest core forearms front_delts glutes hamstrings
> hip_flexors lats lower_back neck quads rear_delts shoulders traps triceps upper_chest`

plus `obliques`, which appears only in the runtime-seeded packs
(`scripts/data/exercise_expansion_2026_08.json`, `scripts/exercise_packs/expansion_v1.json`, applied by
`scripts/seed_exercise_expansion.js`).

Write exactly this rollup — the owner's six groups (answer 1), lowercased match, nothing else:

```swift
enum MuscleGroup: String, CaseIterable, Sendable {
    case chest, back, shoulders, legs, arms, core
}
```

| group | muscle strings |
|---|---|
| `chest` | `chest`, `upper_chest` |
| `back` | `back`, `lats`, `lower_back`, `traps` |
| `shoulders` | `shoulders`, `front_delts`, `rear_delts` |
| `legs` | `quads`, `hamstrings`, `glutes`, `calves`, `adductors`, `abductors`, `hip_flexors` |
| `arms` | `biceps`, `triceps`, `forearms` |
| `core` | `core`, `obliques` |
| *(none)* | `neck` — credits nothing, from either slot |

**The credit rule** (owner answer 1: "full credit primary, partial credit secondary, capped").
`static func credit(primary: String, secondaries: [String]) -> [MuscleGroup: Double]`:

1. `p = group(primary.lowercased())`. If non-nil, `result[p] = 1.0`.
2. `S = Set(secondaries.compactMap { group($0.lowercased()) }).subtracting([p])` — roll up to groups
   **first**, then de-duplicate, then drop the primary's own group. (Back Squat's
   `['glutes','hamstrings','core']` → `{legs, core}` → minus `legs` → `{core}`.)
3. Each group in `S` gets `min(0.5, 1.0 / Double(S.count))`. **The total secondary credit for one set
   never exceeds 1.0** — that is the owner's cap, expressed as a per-group weight rather than a
   post-hoc clamp so the split is deterministic and order-independent.
   `|S|=1 → 0.5` · `|S|=2 → 0.5, 0.5` · `|S|=3 → 0.333…×3` · `|S|=4 → 0.25×4`.
4. An unmapped string on either side contributes nothing and is not an error.

**Tests (new):** `GymSyncApp/GymSyncTests/MuscleGroupRollupTests.swift` — at minimum:
Bench Press (`chest`, `['triceps','front_delts']`) → `chest 1.0, arms 0.5, shoulders 0.5`;
Back Squat (`quads`, `['glutes','hamstrings','core']`) → `legs 1.0, core 0.5`;
Alternating Renegade Row (`back`, `['core','biceps','chest','lats','triceps']` — a real catalog row,
5 secondaries → 3 groups after rollup+dedup) → `back 1.0, core 0.333…, arms 0.333…, chest 0.333…`;
`neck` primary → empty; every one of the 22 strings maps to the table above or to nil;
and a property test that Σ(secondary credit) ≤ 1.0 for every catalog row.

**Proves it:** `MuscleGroupRollupTests` green in CI.

### 0.2 — `WeeklyGoal`, its kinds, and the repository surface — **M**

**File (new):** `GymSyncApp/GymSync/Models/WeeklyGoal.swift`

```swift
enum WeeklyGoalKind: String, Codable, CaseIterable, Sendable {
    case muscleSets = "muscle_sets"
    case distance
    case sessionsOfType = "sessions_of_type"
    case days
    case lift
}

enum WeeklyGoalSource: String, Codable, Sendable { case coach, user }

/// Per-kind parameters. ONE payload type with per-kind optional fields, not
/// five types: the column is a single `params jsonb` and a Codable enum with
/// associated values would put the discriminator in two places.
struct WeeklyGoalParams: Codable, Equatable, Sendable {
    var muscleTargets: [String: Int]? = nil      // MuscleGroup.rawValue -> target sets, ≤ 6 keys
    var activity: String? = nil                  // run | bike | row | walk
    var distanceTarget: Double? = nil            // in the user's unit (mi with lbs, km with kg)
    var sessionType: String? = nil               // hiit | mobility | cardio | class
    var count: Int? = nil                        // sessionsOfType count, or days count
    var exerciseID: UUID? = nil
    var targetWeightLbs: Decimal? = nil          // CANONICAL POUNDS, per Models/Units.swift
    var byDate: Date? = nil
}

struct WeeklyGoal: Identifiable, Equatable, Sendable {
    var id: String { "\(userID.uuidString)-\(weekStartString)" }
    let userID: UUID
    /// Raw DATE string from PostgREST ("yyyy-MM-dd"). DATE columns must not go
    /// through the SDK's timestamp decoder — the `SessionSeries` idiom,
    /// documented at `Models/ProgramEnrollment.swift:36-38`.
    let weekStartString: String
    var kind: WeeklyGoalKind
    var params: WeeklyGoalParams
    var source: WeeklyGoalSource
    let setAt: Date
}
```

**The week must be the device calendar's week, not ISO-8601.** `HomeView.daysThisWeek` (:950) uses
`Calendar.current.isDate(_:equalTo:.now, toGranularity: .weekOfYear)`, which honours the user's
`firstWeekday`. The design says "ISO week"; **deviate deliberately** and record it, because the design's
own strip law says the strip's right-hand read and the streak tile "must agree", and two different week
definitions on one page break that. Ship a single helper used by both:

```swift
enum WeekMath {
    static func startOfWeek(_ date: Date = .now, calendar: Calendar = .current) -> Date
    static func weekStartString(_ date: Date = .now, calendar: Calendar = .current) -> String  // yyyy-MM-dd, POSIX locale, device tz
    static func daysRemaining(in week: Date, from now: Date = .now, calendar: Calendar = .current) -> Int
}
```

**The repository surface** (same file, or `WeeklyGoalRepository.swift` — your call, one commit either way):

```swift
protocol WeeklyGoalRepository: Sendable {
    func goal(weekStart: String) async -> WeeklyGoal?
    func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress
    @discardableResult func save(_ goal: WeeklyGoal) async -> Bool   // source = .user
    func clearToCoach(weekStart: String) async -> WeeklyGoal?        // LET COACH SET IT: delete + re-derive
}

/// What the strip renders. Kind-agnostic on purpose: the strip switches on
/// `kind`, but the numbers are already resolved so no view does arithmetic.
struct WeeklyGoalProgress: Equatable, Sendable {
    struct Chip: Equatable, Sendable {
        let name: String        // e.g. "CHEST" — caller owns the caps
        let done: Double        // unrounded; the chip shows `Int(done.rounded())`
        let target: Double
        let isNext: Bool        // exactly one true, or none when all met
    }
    var chips: [Chip] = []              // muscleSets: up to 4 (the four LARGEST targets)
    var value: Double = 0               // distance / lift current / sessions done / days done
    var target: Double = 0
    var unitLabel: String = ""          // "mi" | "km" | "" — from ThemeStore.shared.weightUnit
    var met: Bool = false
    var rightHandRead: String = ""      // "1 SESSION LEFT" / "3 DAYS LEFT" — SAME week as the streak tile
    var kicker: String = ""             // "THIS WEEK · COACH'S GOAL" | "THIS WEEK · YOUR GOAL" | "GOAL MET · {n} DAYS LEFT"
}
```

**Also in this commit:** `StubWeeklyGoalRepository` — deterministic, no network, returns the design's
own fixture numbers (`HomeV2Fixtures.coachTargets`: CHEST 8/12, BACK 10/12, LEGS 6/12 next, ARMS 8/8,
`rightHandRead = "1 SESSION LEFT"`). It is what B and C build against and what the catalog captures use.

**Tests (new):** `GymSyncApp/GymSyncTests/WeeklyGoalModelTests.swift` — `WeeklyGoalParams` Codable
round-trips for all five kinds through JSON with only that kind's keys present and the rest absent (not
`null`); `WeekMath.weekStartString` is stable across a DST boundary; `WeekMath`'s week and
`HomeView`-style `isDate(…toGranularity: .weekOfYear)` classify the same set of dates identically for a
year of dates under `firstWeekday` 1 and 2.

### 0.3 — `HomeWeeklyGoalStrip` (rename + shell) — **S**

**File:** `git mv GymSyncApp/GymSync/Features/Home/V2/HomeCoachTargetsStrip.swift
GymSyncApp/GymSync/Features/Home/V2/HomeWeeklyGoalStrip.swift`, rename the type
`HomeCoachTargetsStrip` → `HomeWeeklyGoalStrip` (design §A item 7 names the rename).

New init, replacing `targets:`/`sessionsLeft:`:

```swift
struct HomeWeeklyGoalStrip: View {
    let kind: WeeklyGoalKind?          // nil = no goal yet → the invitation line
    let progress: WeeklyGoalProgress
    var action: () -> Void = {}
}
```

Body in this commit renders **two** cases only, so B can compose immediately:
- `kind == .muscleSets` → today's four-chip row, unchanged pixel-for-pixel, fed from
  `progress.chips` and `progress.kicker` / `progress.rightHandRead` instead of the old two params;
- `kind == nil` → the design's invitation, verbatim: **`Set a goal for this week ›`**, in
  `theme.accent` (design language rule 2: an invitation line is one of accent's jobs), single line,
  `surface` fill, 14 pt radius, same 12 pt padding as the chip row.
- every other kind → `EmptyView()` with a `// Stream C fills this in (task C2).` marker.

Update the call sites in `HomeV3Variations.swift` (`HomeV3TargetsAboveCalendarView` :443-445 and
`HomeV3TargetsAboveJoinView` :483-485) to build a `WeeklyGoalProgress` from `HomeV2Fixtures.coachTargets`
so the 08a/08b catalog frames render **byte-identically to what the owner approved**. That identity is
this task's proof.

**Proves it:** CI artifact — `app-home-v3-08a-targets-above-calendar.png` unchanged from the
run that produced the approved frame. Run `node scripts/parity_diff.js` locally against the two
artifacts if you have them; otherwise eyeball the two-up.

### 0.4 — `CalendarSchedulingView` scaffold — **S**

**File (new):** `GymSyncApp/GymSync/Features/Calendar/CalendarSchedulingView.swift`

```swift
struct CalendarSchedulingView: View {
    /// The sessions the caller already fetched, so the page paints instantly
    /// from Home's `refresh()` results and re-fetches in the background.
    let completedSessions: [WorkoutSession]
    let upcomingSessions: [WorkoutSession]
    let groups: [GymGroup]
}
```

This commit ships: nav title `Calendar`, month subtitle line, the `+` circle in the trailing toolbar
slot, and one primary `SCHEDULE A SESSION` button (accent — the page's single primary, design rule 4)
that presents `ScheduleSessionView(onScheduled:)` (`Features/Sessions/ScheduleSessionView.swift:21-28`).
Everything else is a `// Stream D` marker. **Do not** add a catalog id here — D owns
`calendar-scheduling`.

### 0.5 — `FriendsLive` result type + repository — **S**

**File (new):** `GymSyncApp/GymSync/Models/FriendsLive.swift`

```swift
struct FriendLive: Identifiable, Equatable, Sendable {
    let id: UUID              // friend's profile id
    let initials: String      // two letters, the HomeCrewPulseStrip idiom
    let displayName: String
    let sessionID: UUID
    let groupID: UUID?
    let groupName: String?
    let startedAt: Date?
}

protocol FriendsLiveRepository: Sendable { func live() async -> [FriendLive] }
struct EmptyFriendsLiveRepository: FriendsLiveRepository { func live() async -> [FriendLive] { [] } }
```

The default binding stays `EmptyFriendsLiveRepository` until **A9**. That is deliberate: owner ruling 2
says the crew-pulse strip is absent unless a friend is actually lifting, and an empty repository is
exactly that state — so Home is correct at every point in the build, not just at the end.

**Push `feat/home-v3-release` here. The four streams fork from this commit.**

---

# STREAM A — data & backend

Worktree `wt-goal-data`, branch `feat/weekly-goal-data`. Zero SwiftUI. 12 tasks.

> **Migration gate, read once.** `.github/workflows/backend.yml:16-26` runs `scripts/run_pgtap.js`
> against the **live** `SUPABASE_DB_URL` secret. There is no `supabase db push` anywhere in CI — grepped.
> So a pgTAP test for a table that has not been applied to the shared project **will fail**. Migrations
> in this stream must be applied to the project (`chjkkwqwdlmaxacwglzm`) by the operator, or via the
> Supabase MCP `apply_migration`, before the matching pgTAP task's CI run. Say so in the commit body.

### A1 — `weekly_goals` table + RLS — **S**

**File (new):** `supabase/migrations/20260906000001_weekly_goals.sql`
(naming: `2026MMDD00000N_<slug>.sql`; latest existing is `20260828000001_profiles_onboarded_at.sql`).

```sql
CREATE TABLE public.weekly_goals (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  week_start date NOT NULL,
  kind       text NOT NULL CHECK (kind IN ('muscle_sets','distance','sessions_of_type','days','lift')),
  params     jsonb NOT NULL DEFAULT '{}'::jsonb,
  source     text NOT NULL DEFAULT 'coach' CHECK (source IN ('coach','user')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_start)
);
ALTER TABLE public.weekly_goals ENABLE ROW LEVEL SECURITY;
```
Four policies, all `USING (user_id = auth.uid())` / `WITH CHECK (user_id = auth.uid())`, for
SELECT / INSERT / UPDATE / DELETE to `authenticated`. Follow the shape of
`20260710000001_create_friendships.sql`'s policy block (named policies, `TO authenticated`).

The header comment states the owner ruling this table encodes ("propose only": Coach may write a row
whose `source = 'coach'`, and **may not** overwrite one whose `source = 'user'` — enforced in A11 on the
write path, not in a trigger, because Coach writes as the user's own JWT).

### A2 — pgTAP for `weekly_goals` — **S**

**File (new):** `supabase/tests/weekly_goals_test.sql`. Follow `supabase/tests/user_settings_test.sql`
exactly: `BEGIN; CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions; SELECT plan(n);`, two
fixture `auth.users` + `profiles`, `SET LOCAL role authenticated` + `SET LOCAL request.jwt.claim.sub`.

Assertions: owner inserts own row; defaults `source='coach'`, `params='{}'`; the PK rejects a second row
for the same `(user_id, week_start)`; each of the five `kind` values is accepted and a sixth is rejected;
a `source` outside `{coach,user}` is rejected; **an outsider sees zero rows** and **cannot insert a row
for another user_id** (the two RLS denials). `ROLLBACK;`.

**Proves it:** `node scripts/run_pgtap.js supabase/tests/weekly_goals_test.sql` green in the Backend
workflow.

### A3 — the muscle-sets tally from `set_logs` — **M**

**File (new):** `GymSyncApp/GymSync/Models/WeeklyGoalProgressMath.swift`

A **pure** function, no network:

```swift
static func muscleSetCredit(logs: [SetLog], catalog: [UUID: Exercise]) -> [MuscleGroup: Double]
```

Count a set when `!log.isPenalty` and `log.completedReps != nil` (`Models/SetLog.swift:40` — a failed
single proves nothing was lifted and must not credit volume). For each counted log, add
`MuscleGroup.credit(primary:secondaries:)` (task 0.1) for its exercise. Unknown `exerciseID` → skipped.

**Tests (new):** `GymSyncApp/GymSyncTests/WeeklyGoalProgressTests.swift` — a failed single credits
nothing; a failed triple credits fully (it completed 2 reps); a penalty set credits nothing; two sets of
one exercise credit 2× the per-set map.

### A4 — `muscleSets` and `days` progress — **M**

Same file. `WeeklyGoalProgressMath.progress(goal:logs:catalog:sessions:now:calendar:)`:

- **`muscleSets`**: chips = the **four largest `params.muscleTargets` values** (design's table), ties
  broken by `MuscleGroup.allCases` order so the strip never reshuffles between refreshes. `isNext` = the
  single group with the largest `target - done` deficit among the *rendered four*, none when all met.
  `met` = every rendered chip met. Chip `name` = the group's `rawValue.uppercased()`.
- **`days`**: `value` = distinct training days this week — reuse `HomeView.daysThisWeek`'s exact rule
  (`session.completedAt` non-nil, `Calendar.current.startOfDay`, `Set(...).count`) by **lifting that
  computation into this file** and having `HomeView` call it in **B1**. Do not leave two copies.
  `target` = `Profile.effectiveWeeklyGoal` (`Models/Profile.swift:21-30`) — the anti-goalpost effective
  value, not the standing one.
- `rightHandRead` for both = `WeekMath.daysRemaining(...)` rendered as
  `"{n} DAYS LEFT"` (`"1 DAY LEFT"` singular), and the kicker per the design:
  `THIS WEEK · COACH'S GOAL` / `THIS WEEK · YOUR GOAL`, or when met, `GOAL MET · {n} DAYS LEFT`.

**Tests:** extend `WeeklyGoalProgressTests` — `isNext` picks the largest deficit not the smallest
fraction; a group at 0/0 target draws an empty meter and is never `isNext`; the `days` kind's number
equals what `HomeView.daysThisWeek` produced for the same fixture sessions (this is the agreement law).

### A5 — `lift` progress via e1RM — **S**

Same file. Current e1RM = `max` over this **block**'s logs for `params.exerciseID` of
`StatMath.estimatedOneRepMax(weight:reps:)` (`Models/StatMath.swift:125`) using `log.completedReps`, not
raw `reps`. Use the **plain** variant, not the RPE-aware one at :141 — its own doc comment reserves the
RPE variant for suggestion paths, and a goal readout is a record of what you did.

Meter fill = `(current − blockStart) / (target − blockStart)`, clamped 0…1, where `blockStart` is
`ProgramEnrollment.baselineValue(for:)` (`Models/ProgramEnrollment.swift:74`) when the active enrollment
carries one, else the earliest e1RM inside the block window. `unitLabel` = `ThemeStore.shared.weightUnit.label`;
convert with `Units.fromPounds(_:to:)` — stored weights are always pounds (`Models/Units.swift:7-12`).
Right-hand read = weeks left to `params.byDate`.

**Tests:** a lift with no logs renders 0 progress and does **not** crash; `blockStart == target` does
not divide by zero.

### A6 — `sessionsOfType` progress — **M**

Completed sessions this week whose routine carries the type tag. There is **no session-type column
today** — the honest source is the routine's name/`Coach · ` prefix plus the exercise categories
(`Exercise.category ∈ {compound, isolation, cardio, mobility}`, from
`20260813000001_import_free_exercise_db.sql`'s mapping comment). Implement it as:
a session counts toward `params.sessionType` when its routine's exercises are ≥ 50 % of that category
(`cardio` → `cardio`, `mobility` → `mobility`), or — for `hiit` and `class`, which have no category —
when the routine name contains the word case-insensitively. Put that rule in one documented function
with its limitation stated in the doc comment. Where an Apple Health workout of the matching type exists
for the day (A7 lands the query), prefer it.

**Tests:** the category threshold; the name fallback; a session counted once even with two matching
signals.

### A7 — HealthKit distance read + authorization copy — **M**

**Files:**
- `GymSyncApp/GymSync/Services/HealthKitBridge.swift:8-27` — extend `requestPermission()`'s `read:` set
  with `HKObjectType.workoutType()`, `HKQuantityType(.distanceWalkingRunning)`,
  `HKQuantityType(.distanceCycling)`. Today it reads **only** HR + four dietary types and shares
  `workoutType` (verified, :21-25). Add a `distances(activity:from:to:)` and a
  `workouts(from:to:)` `HKSampleQuery` wrapper, both returning `[]` when
  `HKHealthStore.isHealthDataAvailable()` is false.
- `GymSyncApp/project.yml:169` — `NSHealthShareUsageDescription` currently reads *"Gym Sync writes your
  completed workouts to Apple Health so they appear in your Activity ring."* That is a **write** sentence
  on the **read** key and has already been wrong since the 2026-07-27 HR read. Replace it with the read
  it now describes, verbatim:

  > `Gym Sync reads your workouts, distance and heart rate from Apple Health so your weekly goal counts the miles and sessions you log with other apps and watches.`

  Leave `NSHealthUpdateUsageDescription` (:170) and the **watch target's** two strings (:256, :268)
  untouched — the watch's read is a different, narrower purpose and its comment at :257-259 records why
  its key exists at all.
- `WeeklyGoalProgressMath` — `distance` progress: sum matching workouts' `totalDistance` this week,
  convert with `HKUnit.mile()` when `ThemeStore.shared.weightUnit == .lbs` and `HKUnit.meterUnit(with: .kilo)`
  when `.kg` (owner answer 2: mi with lb, km with kg). `unitLabel` = `"mi"` / `"km"`.

**Tests:** unit conversion both ways; the empty/denied path returns 0 rather than nil.

### A8 — `friends_live` RPC — **M**

**File (new):** `supabase/migrations/20260906000002_friends_live.sql`

```sql
CREATE OR REPLACE FUNCTION public.friends_live()
RETURNS TABLE (user_id uuid, username text, display_name text,
               session_id uuid, group_id uuid, group_name text, started_at timestamptz)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$ … $$;
GRANT EXECUTE ON FUNCTION public.friends_live() TO authenticated;
```

**`SECURITY DEFINER` is not optional.** `20260709000006_create_sessions.sql:31-33` documents why: the
`sessions` and `session_participants` policies reference each other, so any cross-table subquery from a
policy re-enters the other table's RLS and cycles. Follow the existing `is_session_participant` /
`is_session_organizer` precedent in that file.

The body: friends of `auth.uid()` from `public.friendships` where `status = 'accepted'` in **either**
direction (the table is directional with a canonical-pair unique index,
`20260710000001_create_friendships.sql:12-13`); their sessions where `state = 'in_progress'`; joined to
`profiles` and `groups`. **Exclude blocked pairs** — join against the block table introduced by
`20260721000001_moderation_block_report.sql`. `LIMIT 5` (the strip shows one; five is enough headroom for
"and 2 more" later without an unbounded scan).

**File (new):** `supabase/tests/friends_live_test.sql` — three fixture users A/B/C: A↔B accepted, A↔C
pending. B in an `in_progress` session, C in one too. As A: exactly one row, B's. Then block B: zero
rows. `ROLLBACK;`.

### A9 — `LiveFriendsLiveRepository` — **S**

**File:** `GymSyncApp/GymSync/Models/FriendsLive.swift` — add the Supabase implementation calling
`.rpc("friends_live")`. `initials` = the same two-letter derivation
`TrainingCalendarWidget.initials(_:)` (:287) uses; extract it or duplicate with a comment naming the
source. Errors → `[]` (best-effort, matching every other Home fetch).

### A10 — `WeeklyGoalDetector` — **L**

**File (new):** `GymSyncApp/GymSync/Models/WeeklyGoalDetector.swift`

A **pure** function, no network — every input is passed in, so it is fully testable:

```swift
static func detect(enrollment: ProgramEnrollment?,
                   weekRoutines: [Routine],
                   routineExercises: [UUID: [RoutineExercise]],
                   catalog: [UUID: Exercise],
                   trainingProfile: TrainingProfile?,
                   effectiveWeeklyGoal: Int,
                   weekStart: String) -> WeeklyGoal
```

The design's three rules, in order:

1. **Active block.** Strength/hypertrophy intent (`TrainingProfile.dominantGoal ∈ {.hypertrophy,
   .maxStrength}` or `ProgramEnrollment.focus.muscleGroup != nil`) → `muscleSets`, targets = the week's
   routines' `RoutineExercise.targetSets` (`Models/RoutineExercise.swift:8`) summed through
   `MuscleGroup.credit`, keeping the top 6 groups. A block with `focus.exerciseIDs` and a
   `baseline` entry → `lift` on the first focus lift, target = `baseline × 1.05` rounded to the unit's
   `displayIncrement` (`Models/Units.swift:36`), `by` = the enrollment's end.
   Conditioning-flavoured (`dominantGoal ∈ {.conditioning, .fatLoss}`, or ≥ half the week's exercises
   are `category == "cardio"`) → `sessionsOfType(cardio, count: trainingProfile.daysPerWeek)`.
2. **No block, profile present.** `dominantGoal` → kind: `.maxStrength` → `lift` on the profile's focus
   lift if it names one, else `muscleSets`; `.hypertrophy` → `muscleSets`;
   `.conditioning`/`.fatLoss` → `distance(run)` at a profile-scaled target;
   everything else → `days`.
   (`TrainingGoal` cases are at `Models/TrainingProfile.swift:93-102`; `dominantGoal` at :337.)
3. **Nothing known** → `days` at `effectiveWeeklyGoal`. **Never returns nil** — the design's law.

`source` is always `.coach` on a detected goal.

**Tests (new):** `GymSyncApp/GymSyncTests/WeeklyGoalDetectorTests.swift` — one test per branch, plus:
rule 3 with every input nil returns `days` at the passed goal and never crashes; a `muscleSets`
detection never emits more than 6 groups; detection is deterministic (same inputs → equal output, run
twice).

### A11 — Coach writes the goal; propose-only — **M**

**Files:**
- `GymSyncApp/GymSync/Models/WeekBooker.swift:27` (`book(window:weekdays:hour:minute:routines:)`) —
  after the booking loop returns, upsert a detected goal for `WeekMath.weekStartString(window.start)`
  **only when no row exists for that week, or the existing row's `source == .coach`**. A row with
  `source == .user` is left alone. That is the owner's answer 3, enforced at the one write path.
- `GymSyncApp/GymSync/Models/ProgramBuilder.swift:49` (`build(profile:answers:catalog:userID:)`) — same
  upsert at the end of the write order (after step 8, "stamp the rules whose levers actually fired"), so
  a block always arrives with its goal. Do **not** move it earlier: the file's header comment (:19-26)
  says the order of writes is load-bearing.
- A `propose(_:)` path that writes nothing and returns the would-be goal, for the Coach tile's line.

**Tests:** a pure `shouldOverwrite(existing:detected:) -> Bool` helper with the three cases
(no row → true; `coach` row → true; `user` row → false), unit-tested. The repository calls are
best-effort `try?` like every other Coach write.

### A12 — `LiveWeeklyGoalRepository` — **M**

**File:** `GymSyncApp/GymSync/Models/WeeklyGoal.swift` (or its own file) — the Supabase implementation of
the 0.2 protocol: `.from("weekly_goals").select().eq("week_start", …)`; `save` upserts with
`source = 'user'`; `clearToCoach` deletes the row and returns `detect(...)`'s result after re-fetching
its inputs. `week_start` is sent and decoded as a **string**, never a `Date` (`ProgramEnrollment.swift:36-38`).
Progress calls `WeeklyGoalProgressMath` with `SetLogRepository` logs for the week + `ExerciseRepository.fetchAll()`
(paged — `Models/Exercise.swift:107-121`) + `SessionRepository.history`.

**Proves the stream:** Backend workflow green (2 pgTAP files) + `GymSyncTests` green (5 new test files).

---

# STREAM B — Home in production

Worktree `wt-home-v3`, branch `feat/home-v3-production`. 7 tasks. Builds against Task 0's stubs.

### B1 — `HomeView` adopts the 08a composition — **L**

**File:** `GymSyncApp/GymSync/Features/Home/HomeView.swift` — the `body` VStack at **:87-101**.

Replace those 15 lines with 08a's order, sourced verbatim from
`HomeV3TargetsAboveCalendarView` (`Features/Home/V2/HomeV3Variations.swift:425-453`) and the shared
frame `HomeV3Frame` (:60-92):

| # | element | source | spacing |
|---|---|---|---|
| 1 | greeting header | keep `greetingHeader` (:251) — **not** `HomeV2GreetingHeader`; production's has the `?` help door and the avatar tap, which the fixture header does not | — |
| 2 | `replayFailureNotice` (:236) | unchanged | — |
| 3 | `HomeOneButton(state:action:)` | new; state from B1's resolver below | `VStack(spacing: 9)`, `.horizontal 16`, `.bottom 12` |
| 4 | `HomeSoloRow(burpeesOwed:onStartSolo:onOpenLedger:)` — **only when `state.isCrewState`** | replaces `soloSecondaryButton` (:422) + `burpeeOwedWidget` (:488) | inside the same `VStack(spacing: 9)` |
| 5 | `HomeV3TilePair { HomeStreakTile · HomeCoachTile }` | replaces `checkInAndStreakRow` (:587) | `.horizontal 16`, `.bottom 12` |
| 6 | `HomeCrewPulseStrip` — **only when `friendsLive` is non-empty** | new | `.horizontal 16`, `.bottom 10` (the strip gap) |
| 7 | `HomeWeeklyGoalStrip(kind:progress:action:)` | task 0.3 | `.horizontal 16`, `.bottom 12` |
| 8 | `HomeCalendarCard(months:appointments:showsAppointments: false, action:)` | replaces `calendarWidget` (:1091) | `.horizontal 16`, `.bottom 12` |
| 9 | `campaignsSection` when `!activeCampaigns.isEmpty` (:1121) | unchanged | unchanged |
| 10 | `joinWithCodeSection` (:1255) | unchanged | unchanged |

**The one button's state resolver.** A new `private var oneButtonState: HomeOneButtonState`, built from
what `HomeView` already computes — no new fetches, no new timing:

| condition | state |
|---|---|
| `nextActionableSession(now:)` is `state == "in_progress"` and started | `.joinSession(startedAt:)` |
| `checkInAvailable(session, now:)` (:623) and it is a group session | `.checkIn(crew:routine:time:)` — **gold** |
| a next session exists but `now < checkInOpensAt(session)` (:616) | `.checkInOpens(compactCountdown(...))` (:802) |
| `ProgramToday.resolveRoutine` produced a routine (`loadTodaysRoutine()` :1539) | `.startRoutine(name)` |
| otherwise | `.startWorkout` |

Keep it inside the existing `TimelineView(.periodic(by: 30))` that `checkInWidget` (:639) already wraps,
so the countdown text stays live. **Do not change the 20-minute or 30-minute rules** (constraint 5).

**Destinations** — every state opens a screen, none starts a workout (design language rule 5):
`.joinSession`/`.checkIn` → `LobbyView(session:).id(session.id)` (the `.id` is load-bearing —
HomeView.swift:159-163 records the 2026-07-30 field bug where a re-resolved lobby wrote 14 sets into the
next occurrence); `.checkInOpens` on a group session → `appState.pendingRoute = .chat(groupID:)` +
`selectedTab = .social` (:669); `.startRoutine`/`.startWorkout` → `showRoutinePicker = true` with
`routinePickerPreselected` set to today's routine (:430).

**Removed from Home — the ledger.** Every one of these is deleted and this table says where its job
went. Put this table in the commit body.

| removed | HomeView anchor | where its job went |
|---|---|---|
| Join hero (`primaryCTASection`'s `NavigationLink` + `ctaCard`) | :352-420 | `HomeOneButton` `.joinSession` / `.checkIn` states |
| `soloSecondaryButton` | :422 | `HomeSoloRow`'s pill (48 pt face, not 55 — the freed height goes to the 57 pt one button) |
| `burpeeOwedWidget` | :488 | `HomeSoloRow`'s counter; `loadBurpeeDebt()` (:713) is **kept** — it is the only all-groups debt roll-up in the app (inventory §1d) |
| `scheduleWidget` ("Schedule a session") | :519 | the calendar card's `+` and the calendar page's `SCHEDULE A SESSION` |
| `checkInWidget` / `goldCheckInCard` / `countdownBody` / `checkInEmptyBody` | :639, :743, :812, :890 | the one button's five states. `commitControl` (:863) is **kept** — see the note below |
| `weeklyGoalWidget`'s wide form | :961 | `HomeStreakTile` — the slot grid survives at tile scale, wrapping every 5 in rows instead of columns |
| `TrainingCalendarWidget`'s appended upcoming rows | `TrainingCalendarWidget.swift:220-291` | the calendar page's week agenda (Stream D) |
| `streakInviteWidget` | :1050 | **kept** — `streakWidget` (:934) still branches on `hasEverTrained` (:1046); a never-trained user sees the invitation, not a 0-streak tile |

**Kept, because the inventory says they live only on Home (§1d)** — verify each one still renders:
join-with-code; the all-groups burpee roll-up; the campaigns carousel + inline join; the gold
"act now" signal (now the button's `.checkIn` face); the `?` HelpSheet; the spotlight tour (see B2);
the watch idle push (`pushWatchIdleStateIfNoLiveSession()` :1438, still called from `refresh()`);
the replay-failure banner; the training-calendar dot field; `RoutinePickerSheet`'s freestyle start;
the weekly-goal `WeeklyGoalSheet` on the streak tile (:1032, :1811).

**The commit chip.** `commitControl` (:863) rendered inside the countdown card, which is gone. The
inventory calls it "the only glance-level commit status". Keep it: render it as a trailing element on
`HomeOneButton`'s `.checkInOpens` row — **not** as a nested `Button` (:856-862 records why: a Button
inside a Button's label is a gesture-conflict hazard); the whole button already routes to the crew room
where committing lives.

**Also in this commit:** move `daysThisWeek` (:950) into `WeeklyGoalProgressMath` (A4's requirement) and
call it here, so the streak tile and the goal strip cannot drift.

**Proves it:** `app-tab-home` in the CI artifact shows the 08a order with the crew pulse **absent**
(the stub returns `[]`), the goal strip rendering the stub's four chips, and the calendar card with the
chevron and no appointment rows.

### B2 — re-point the spotlight tour — **S**

**Files:** `GymSyncApp/GymSync/Services/GuidanceTips.swift:99-112`, `HomeView.swift:92/94/96/456`.

`tour.home.schedule`'s target (`scheduleWidget`) no longer exists. Bump the tour id
**`tour.home.v1` → `tour.home.v2`** — the id gates "seen once", so a changed step list under the old id
would leave every existing user on the old walk. New four steps:

| anchor key | title | message (verbatim) |
|---|---|---|
| `GuidanceTip.home.rawValue` → on `HomeOneButton` | `Start here` | *unchanged*: "Start a workout any time — run one of your routines or go freeform." |
| `tour.home.goal` (new) → on `HomeWeeklyGoalStrip` | `Your goal this week` | "Coach sets a goal each week — muscle sets, miles, sessions or days. Tap the strip to change it." |
| `tour.home.calendar` → on `HomeCalendarCard` | `Your training calendar` | "Everything on the books lands here — tap it to open the calendar, where you schedule and move sessions." |
| `tour.home.streak` → on the tile pair | `Defend the streak` | *unchanged*: "Train each week and the streak grows. Check in when you arrive so your gym time counts." |

Delete the `tour.home.schedule` step and its `.gsSpotlightTarget(key:)` at :94.

**Proves it:** the `guidance-spotlight` catalog capture still renders (it is a different screen, but it
must not regress), and `CatalogScreenTests` is untouched.

### B3 — the Coach tile, wired — **M**

**File:** `HomeView.swift`.

`HomeCoachTile(sentence:waiting:action:)`. Three things this task decides, because **no existing
"Home coach sentence" path was found** (grepped: `BlockProgression` (`Models/BlockProgression.swift:40`)
is per-lift and returns `Decision`/`CoachNote`, not a Home line; `CoachHomeView` builds its own):

1. **The sentence**, first precedence that produces text:
   (a) the goal repository's `propose(_:)` line when Coach wants to change a `source = user` goal
   ("Your week looks like miles, not sets — want me to switch it?"), (b) today's routine from
   `ProgramToday.resolveRoutine` as a first-person line ("Pull A today — take 185 × 8, then we climb"),
   (c) the block's week ("Week 2 of 6. Three days on the books."), (d) a static invitation
   ("Tell me how the week's going and I'll shape the next one."). First person, one sentence
   (design rule 7).
2. **The badge** (`waiting:`): unread coach-thread messages. If no unread count exists on
   `coach_chat_threads` (`20260824000005_coach_chat_threads.sql`), pass `nil` — **do not invent a
   number**. A badge that is always `1` is worse than no badge (design rule 4: badges point, they do
   not shout).
3. **The route.** Coach is reachable today only from the You tab's `showCoach` push
   (`Features/You/YouTabView.swift:124-131`). Home is inside a `NavigationStack`, so add a local
   `.navigationDestination(isPresented: $showCoach) { CoachHomeView() }` on Home. **Do not** add a
   `PendingRoute` case — that enum is for push deep-links (`App/AppState.swift:70-75`) and this is not one.

### B4 — the crew pulse, conditional — **S**

**File:** `HomeView.swift`. `@State private var friendsLive: [FriendLive] = []`, fetched inside
`refresh()`'s **single parallel batch** (:1320-1327 — add a ninth `async let`, assign in the single
commit block at :1345, per the perf note at :1330-1337 that says interleaved awaits made the screen
visibly assemble). Render `HomeCrewPulseStrip` only when non-empty; when empty **render nothing at all**
and let the layout shift up (owner ruling 2).

Copy, verbatim from the design: headline `{Name} is lifting now`; detail `{Crew} · {when}` for a crew
session, `Solo` otherwise. Tap → that session's lobby when `session_participants` includes you, else the
crew room (`pendingRoute = .chat(groupID:)` + `.social`).

### B5 — the calendar card as a door — **S**

**File:** `HomeView.swift`. `HomeCalendarCard(months:appointments:showsAppointments: false, action:)`.

`months` and `appointments` are built from `historySessions` / `upcomingSessions` / `groups` — the same
three arrays `TrainingCalendarWidget` takes today (:1092-1099). Extract the `Month`/`Appointment`
construction into a small `HomeCalendarCardModel` so the mapping is testable and Stream D can reuse it.
`action:` pushes `CalendarSchedulingView(completedSessions:upcomingSessions:groups:)` (task 0.4).

`TrainingCalendarWidget` has **exactly one call site** (HomeView.swift:1092, grep-verified) — it is not
deleted here; Stream D task D1 takes ownership of its dot field.

### B6 — the goal strip, wired — **M**

**File:** `HomeView.swift`. `@State private var weeklyGoal: WeeklyGoal?`,
`@State private var goalProgress: WeeklyGoalProgress = .init()`,
`@State private var goalLoaded = false`. Fetched in the same single batch as B4.

Three states, per the design:
- **loading** (`!goalLoaded`) — render the strip's chrome with the kicker and a skeleton meter row, not
  an empty gap: the layout must not jump when the fetch lands. (Home has no skeleton anywhere today,
  §1c — this is the first, and it is scoped to this one strip.)
- **goal present** → `HomeWeeklyGoalStrip(kind: goal.kind, progress: goalProgress)`.
- **no goal** → `HomeWeeklyGoalStrip(kind: nil, progress: .init())` — the invitation line.

Tap → the goal editor sheet (Stream C's `WeeklyGoalEditorSheet`); until C lands, tap opens the existing
`WeeklyGoalSheet` (:1811) so the strip is never inert. Swap the destination in **I1**.

**The agreement law.** `goalProgress.rightHandRead` and `HomeStreakTile`'s `daysDone/goal` describe the
same week. A4 guarantees the numbers; this task must not re-derive either of them locally.

### B7 — Home's own test + capture ledger — **S**

**File (new):** `GymSyncApp/GymSyncTests/HomeCompositionTests.swift` — pure tests of the extracted
helpers only (`oneButtonState` resolution given fixture sessions and clocks;
`HomeCalendarCardModel`'s month/appointment mapping). SwiftUI bodies are not unit-testable here; the
capture is the visual proof.

**Proves the stream:** `app-tab-home` renders the 08a order. Attach it to the stream's merge commit body
as the evidence line (the artifact URL from the CI run).

---

# STREAM C — the goal editor and the strip's five kinds

Worktree `wt-goal-ui`, branch `feat/weekly-goal-ui`. 4 tasks. Owns 9 of the 10 new catalog ids.

### C1 — the strip's kind switch — **M**

**File:** `GymSyncApp/GymSync/Features/Home/V2/HomeWeeklyGoalStrip.swift` (renamed in 0.3).

Turn the body into a `switch kind`. Everything below keeps the file's existing chrome unchanged: a
strip, not a card (`theme.surface`, `HomeV2Metrics.stripRadius` = 14, no extrusion — design rule 1); the
kicker row with `progress.kicker` on the left, `progress.rightHandRead` on the right, chevron at the
trailing edge; `Color.gsHex(0x2FA45C)` as the one green, in its "done" job.

### C2 — the five renderings + met + empty — **L**

Same file. Design §B's table, exactly:

| kind | rendering |
|---|---|
| `muscleSets` | four equal chips (the four largest targets) — group name kicker, 4 pt meter, `done/target` under it. **met** → fraction and meter fill green, name unchanged. **next** → 1.5 pt accent ring on the chip. Already built; keep pixel-identical. |
| `distance` | one full-width meter with the activity's SF Symbol (`figure.run` / `figure.outdoor.cycle` / `figure.rower` / `figure.walk` — SF Symbols only, no emoji, rule 2), the value `9.4 / 15 mi` in tabular figures, days remaining on the right |
| `sessionsOfType` | `params.count` dots in a row, filled as done (filled = `theme.text`, or green when met; empty = `theme.neutral300`), label `2 of 3 HIIT` |
| `days` | the week's seven day chips — reuse `HomeWeekStrip.Day` and its `.done`/`.today`/`.empty` states (`Features/Home/V2/HomeWeekStrip.swift`), so Home's two week readouts are literally the same view |
| `lift` | `205 → 225` with the arrow, a meter from the block's start e1RM, `weeks left` on the right. Weight rendered via `ThemeStore.shared.weightUnit` + `Units.fromPounds` — never a raw stored pound value |

**Metric/imperial (owner answer 2):** `distance` follows the unit setting — **mi with lbs, km with kg**.
`lift` follows it too. Read it once per body from `ThemeStore.shared.weightUnit`
(`DesignSystem/ThemeStore.swift:88`); never hard-code `"lb"` or `"mi"`.

**Copy that is fixed:** kicker `THIS WEEK · COACH'S GOAL` / `THIS WEEK · YOUR GOAL`; met kicker
`GOAL MET · {n} DAYS LEFT`; empty line `Set a goal for this week ›`.

**Colour discipline:** green only on met fractions/meters; accent only on the `next` ring and the empty
invitation line; **no gold anywhere on this strip** — gold has exactly two jobs and neither is here.

### C3 — the goal editor sheet — **L**

**File (new):** `GymSyncApp/GymSync/Features/Home/WeeklyGoalEditorSheet.swift`

Header **`Your goal this week`**. Copy line under it, verbatim from the design:

> Coach set this from your block. Change it here; Coach follows your lead for the rest of the week.

Then a segmented row of kinds as **chips** — `MUSCLE SETS · MILES · SESSIONS · DAYS · A LIFT` — flat,
not extruded (rule 1: chips are furniture), 999 radius, the selected one in `theme.text` on
`theme.neutral300`. Then the chosen kind's levers:

| kind | levers |
|---|---|
| muscle sets | up to six rows (`MuscleGroup.allCases`), each `± ` steppers; defaults seeded from the block's detection |
| miles | activity picker (run / bike / row / walk) + target stepper, unit follows `weightUnit` |
| sessions | type picker (HIIT / mobility / cardio / class) + count stepper |
| days | count stepper 1–7 — **writes the same `weeklySessionGoal`** the streak sheet edits (`ProfileRepository.updateWeeklySessionGoal`, HomeView.swift:1868). One source of truth: the `days` kind and the streak goal are the same number, and the anti-goalpost rule (an edit lands next week) still applies |
| a lift | exercise picker (the block's focus lifts first, then `ExerciseRepository.fetchAll()`), target weight stepper in the user's unit, by-date |

Footer, two buttons: **`LET COACH SET IT`** (raised face — `.gs3DCardStyle`) which calls
`clearToCoach(weekStart:)`, and **`SAVE THIS WEEK'S GOAL`** (accent). **Exactly one accent button on the
sheet** (design rule 4) — `LET COACH SET IT` is raised, never accent.

Presented as a sheet from the strip's tap. Detent: `.large` (five kinds × six rows does not fit
`.medium`).

### C4 — nine catalog ids — **M**

**Files:** `App/CatalogHostView.swift`, `GymSyncTests/CatalogScreenTests.swift`,
`GymSyncUITests/ScreenshotTests.swift`, `docs/design/frame-map.json`, plus a fixture file
`Features/Home/V2/WeeklyGoalFixtures.swift`.

Nine ids: `home-goal-strip-muscle-sets` (frame 83), `-distance` (84), `-sessions` (85), `-days` (86),
`-lift` (87), `-met` (88), `-empty` (89), `home-goal-editor` (90), `home-goal-editor-lift` (91).

Fixtures are hermetic — integers and strings, no `Date.now`, no repository (the reason
`HomeV2Fixtures.swift:1-10` gives). `-muscle-sets` reuses `HomeV2Fixtures.coachTargets` exactly, so the
new capture and the approved 08a frame agree. `-met` is the same four groups at target.
`-lift` fixture is `205 → 225`, `by` 6 weeks out. `-distance` is `9.4 / 15 mi`.

Each strip id renders the strip **on the page ground with the greeting header above it**, matching how
the home-v3 frames present a strip — a strip floating alone on a blank screen is not a reviewable frame.

**Do not bump `FLOOR`** — I3 does it once.

**Proves the stream:** nine new `app-home-goal-*.png` in the CI artifact.

---

# STREAM D — the calendar & scheduling page

Worktree `wt-calendar`, branch `feat/calendar-scheduling-page`. 5 tasks. Structure from the v7 proof
(`04-calendar-scheduling-new-page.png`) and design §C.

### D1 — extract the month dot field — **M**

**Files:** `GymSyncApp/GymSync/Features/Home/TrainingCalendarWidget.swift:71-217` →
new `GymSyncApp/GymSync/Features/Calendar/TrainingMonthField.swift`.

The dot field exists in **two implementations** today: the production one
(`monthGroupedField` :139, `monthGrid` :168, `dot` :197 — all `private`) and a fixture-driven copy in
`Features/Home/V2/HomeCalendarCard.swift:155-215`, whose own doc comment (:14-26) says it was rebuilt
"on the same constants" only because the production field is `private` and that build could not edit it.
That constraint is gone. Extract **one** view:

```swift
struct TrainingMonthField: View {
    struct Month: Identifiable { … }   // the HomeCalendarCard.Month shape
    let months: [Month]
    var fieldWidth: CGFloat = 326
}
```

Constants live here once: 12 pt gutters, a 21-column unit `(width - 2*gutter)/21`, `unit * 0.42` row
spacing, dots at `unit * 0.68` (trained/planned) and `unit * 0.52` (otherwise), today haloed at
`unit * 0.95`. Dot semantics unchanged: trained = `theme.text`, scheduled = accent, past untrained =
`neutral400`, future = `neutral300`, today = accent halo (inventory §1a row 17).

Rewire **both** callers: `TrainingCalendarWidget` and `HomeCalendarCard`. Neither's rendering may
change — that is this task's whole risk, and its proof.

**Proves it:** `app-home-v3-08a-targets-above-calendar` and `app-tab-home` unchanged from the previous
run. If the diff is non-zero, the extraction moved a constant — find it, do not accept it.

### D2 — the page — **L**

**File:** `GymSyncApp/GymSync/Features/Calendar/CalendarSchedulingView.swift` (scaffolded in 0.4).

Top to bottom, from the v7 proof:

1. **Header** — back chevron, title `Calendar`, subtitle `{Month} {Year}` (the selected month), and the
   `+` circle in the trailing slot → `ScheduleSessionView`.
2. **Month card** — a single month at day-number scale (not the three-month dot field: the proof shows
   numbered days in rounded cells). Selected week's days boxed; ring semantics: **trained = filled/text
   cell**, **scheduled-you = accent ring**, **crew = that crew's `GSGroupColor` ring**, **today = a
   distinct ring**. A legend line under the grid naming the three: `Trained · You · Crew`. Swipe left/right
   to change month (`DragGesture`, or a `TabView(.page)` of months — either, one commit).
3. **`THIS WEEK`** section header with the hint `SWIPE A ROW TO MOVE OR CANCEL` on the right.
4. The selected week's **agenda** (task D3).
5. **Block row** and **campaign rows** (task D4).
6. **`SCHEDULE A SESSION`** primary in accent — the page's single primary.

Data in: the three arrays the initializer already takes. Data refreshed: `SessionRepository.upcoming()`
and `SessionRepository.history(userID:limit:)` on `.task` and `.refreshable`, best-effort `try?` like
every other screen.

### D3 — the week agenda rows + swipe — **M**

One row per item: day number + weekday on the left (`5` / `FRI`), then `{Routine} · {time}` with the
`↻` glyph when `session.seriesID != nil`, subtitle `{Crew} · {detail}` or `Solo · from your block`, a
status pill on the right — `IN` (green, checked in) or `COMMIT` (accent) — then the chevron.

Row tap → `LobbyView(session:).id(session.id)` (the `.id` rule again). A series row's `↻` and the row
both open the lobby; the **series editor** is reached from the lobby's existing
`SeriesEditorView(seriesID:onSaved:)` (`Features/Sessions/SeriesEditorView.swift:171-173`) —
**do not add a second entry point** unless the swipe actions need one.

Swipe actions use the **existing** edit paths, no new repository methods:
*Move* → `ScheduleSessionView` preloaded with that session; *Cancel* →
`SeriesRepository.cancelOccurrence(sessionID:)` for a series occurrence, `SessionRepository.deleteSession(id:)`
otherwise — exactly the branch `WeekBooker.book` already makes at `Models/WeekBooker.swift:48-59`.

**Rows are flat.** The card they sit in is the raised object; furniture inside it stays flat (rule 1).

### D4 — block and campaign rows — **M**

- **Block row**, copy from the design: `Coach block · week {n} of {m} · Tue Thu Sat` with a trailing
  **`CHANGE DAYS ›`** pill → `BlockCalendarView(enrollment:weeks:)`
  (`Features/Coach/BlockCalendarView.swift:23-25`). `n`/`m` from `ProgramEnrollment.startedOn` and
  `.weeks` (`Models/ProgramEnrollment.swift:38, 66-71`); the weekday list from the block's booked
  sessions. Absent entirely when there is no active enrollment.
- **Campaign rows**: `{Campaign} campaign · ends {date} · you're at {n}%` → `CampaignDetailView(campaign:)`.
  Source: `CampaignRepository.activeAndUpcoming().active` + `myProgress` — the same two calls
  `HomeView.fetchActiveCampaigns` (:1488) and `loadCampaignJoinState` (:1501) already make. One row per
  **joined** active campaign; unjoined discovery stays on Home's carousel (inventory §1d: Home is the
  only discovery surface).

**No new data model** — design §C is explicit. If you find yourself writing a migration in this stream,
stop and re-read the design.

### D5 — the `calendar-scheduling` catalog id — **S**

Four-part contract for `calendar-scheduling`, frame **92**, title `Calendar & scheduling page`. Fixture
world: the v7 proof's own content (Sep 2026; trained 1, 3, 4; you-scheduled 5, 7, 11, 18, 20; crew 6, 9,
13, 16; today 5) and its four agenda rows — `Push A · 5:00 PM · Push Crew · Powerhouse · you're in · IN`,
`Lower B · 9:00 AM ↻ · Legs Crew · repeats weekly`, `Pull A · 10:00 AM · Solo · from your block`,
`Push B · 5:00 PM · Push Crew · commit closes Mon 5 PM · COMMIT` — plus the block row
`Coach block · week 2 of 6 · Tue, Thu, Sat · CHANGE DAYS ›` and
`Fall Volume campaign · ends Sep 30 · you're at 61%`.

Hermetic: fixture integers, no `Date.now`. **Do not bump `FLOOR`.**

**Proves the stream:** `app-calendar-scheduling.png` matches the v7 proof's structure, and D1's two
unchanged captures.

---

# INTEGRATION

Branch `feat/home-v3-release`. Run after all four streams are pushed. 5 tasks.

### I1 — merge the streams and swap the stubs — **M**

Merge order — **A, then D, then C, then B**. Rationale: A is pure additions (no shared file); D touches
`TrainingCalendarWidget` which B also reads, so D lands first and B rebases onto it; C and B both edit
`HomeView`-adjacent files, and B is last so it integrates against everything real.

Conflicts to expect, all append-only: `CatalogHostView.swift`'s enum and switch (C: 9 ids, D: 1),
`CatalogScreenTests.swift`'s `ids` array, `ScreenshotTests.swift`'s test list, `frame-map.json`.
Resolve by concatenating in frame order; do not renumber.

Then the swaps, one commit:
- default `WeeklyGoalRepository` binding: `StubWeeklyGoalRepository` → `LiveWeeklyGoalRepository` (A12).
  The stub stays in the codebase — the catalog captures use it.
- default `FriendsLiveRepository`: `EmptyFriendsLiveRepository` → `LiveFriendsLiveRepository` (A9).
- Home's goal-strip tap destination: `WeeklyGoalSheet` → `WeeklyGoalEditorSheet` (C3). The old
  `WeeklyGoalSheet` (`HomeView.swift:1811`) **stays** — the streak tile still opens it (:1032), and
  the `days` kind writes the same field, which is the point.

### I2 — the CI account gets a real goal — **S**

**File:** `scripts/seed_qa_fixtures.js`.

Add a `weekly_goals` block following the file's own idempotence idiom (:13-20: delete this account's own
prior fixture rows keyed on a stable marker, then re-insert). Insert one row for `ci_test_user_2` at
`WeekMath`'s current week start, `kind = 'muscle_sets'`, `source = 'coach'`, params matching
`HomeV2Fixtures.coachTargets` so **`app-tab-home` renders a real goal rather than the empty invitation**.

Because the week rolls, the seed must compute `week_start` at run time (the workflow's "Seed QA fixture
world" step runs on every screenshot job), and it must upsert on `(user_id, week_start)` rather than
insert — otherwise the second run of a week fails on the PK.

Note in the block's comment, as the file's header demands (:26-36), that this row is genuinely live in
the shared project and is inert for real users (it is scoped to one account by `user_id`, and RLS means
nobody else can read it).

### I3 — `FLOOR`, frame-map, and the parity entries — **S**

- `.github/workflows/ios.yml:336` — `FLOOR=87` → `FLOOR=97`. One edit, this task only.
- `docs/design/frame-map.json` — verify all ten entries present, frames 83–92, no duplicates.
- `docs/design/accepted-deviations.json` — add entries for anything the parity harness will flag as
  having no authoritative canvas frame. At minimum: `calendar-scheduling` (the v7 HTML proof is the
  authority, not a numbered canvas frame — same posture the existing `voice-*` entries take) and
  `tab-home` (extend the existing entry, do not open a second one, per the precedent that entry's own
  text sets).

### I4 — end-to-end CI — **M**

Push and read the run:
- **iOS workflow**: build green; `GymSyncTests` green (7 new test files); screenshot job exports
  **≥ 97** app captures; the "Verify capture count" step passes.
- **Backend workflow**: pgTAP green for `weekly_goals_test.sql` and `friends_live_test.sql` — which
  requires A1 and A8's migrations to be **applied to the project first** (see the Stream A gate).
- Pull the artifact and check, by eye, in this order: `app-tab-home` (the 08a order, a real goal from
  I2's seed, no crew pulse unless a friend happens to be live, no appointment rows on the calendar
  card), `app-calendar-scheduling`, the seven `app-home-goal-strip-*`, the two
  `app-home-goal-editor*`, and finally `app-home-v3-08a-targets-above-calendar` **unchanged** — the last
  one is the regression canary for tasks 0.3 and D1.

Fix-forward any red; each fix is its own commit on the integration branch.

### I5 — one release PR — **M**

`feat/home-v3-release` → `master`. Body carries: the removed-element ledger from B1; the "kept, lives
only on Home" checklist from the inventory §1d with each item ticked; the list of ten new catalog ids
and the FLOOR change; the two migrations and the note about how they were applied; the deliberate
deviations (device-calendar week instead of ISO; the `NSHealthShareUsageDescription` rewrite; the
`tour.home.v2` id bump); and the CI run URL whose artifact is the visual proof. Trailer per constraint 4,
plus `🤖 Generated with [Claude Code](https://claude.com/claude-code)` per PR convention.

---

## What this plan does not decide

1. **Two muscle-set accountings now exist and they can disagree.** `ProgramGenerator.weeklyMuscleSets`
   (`ProgramGenerator.swift:1871-1887`) credits `1.0` primary and `0.5` per secondary **muscle string**,
   **uncapped**, and is what the block generator balances targets against (with tests at
   `GymSyncTests/VolumeAccountingTests.swift:29`). The goal strip's number rolls those strings up to six
   **groups** and caps total secondary credit at 1.0 per set. A target the generator wrote and a
   progress number the strip renders are therefore not the same arithmetic. This plan does **not**
   reconcile them — changing the generator moves block prescriptions, which is a separate decision with
   its own proof burden. Constraint 8 freezes the generator; the divergence is documented in
   `MuscleGroup.swift`'s doc comment and belongs in a follow-up round.
2. **`volume_targets` vs. summed `targetSets`.** A per-muscle weekly target table already exists
   (`VolumeTargetRepository`, `Models/RecoveryProbeRepository.swift:145-190`) — "what the search has
   settled on, per muscle". The design says derive `muscleSets` targets from the week's routines'
   `targetSets`, and A10 follows the design. Whether `volume_targets` should be the source instead (or
   the cross-check) is open.
3. **Coach's badge count.** B3 passes `nil` when no unread count exists. Whether `coach_chat_threads`
   should grow one, and what counts as "waiting", is not decided here.
4. **The `sessionsOfType` type vocabulary has no schema.** A6 infers the type from exercise categories
   and routine names. A real `session_type` column, or a routine tag, is the honest fix and is not in
   this plan.
5. **Realtime for the crew pulse.** Design phase 3 says "refreshed on Home's existing cadence and on the
   live-session channel". This plan wires only the existing cadence (Home's `refresh()`). A Realtime
   subscription is not built.
6. **Goal history.** `weekly_goals` is one row per user per week and nothing reads last week's. Whether
   a met/missed history feeds Coach, the AAR, or a Stats surface is open.
7. **Whether `TrainingCalendarWidget` survives.** After B5, its only call site is gone and only its
   extracted dot field is used. Deleting the rest of it is a `/denoise` follow-up, not this plan.
8. **Push notifications for a goal met or a goal proposal.** Not designed, not built.
9. **The `days` goal's relationship to streak pushes.** `days` writes `weeklySessionGoal`, which
   `streak_pushes` already reads (`supabase/tests/streak_pushes_test.sql`). Whether editing the goal from
   the new editor should re-evaluate a pending push is unexamined.
10. **Whether Home should show a second friend.** `friends_live` returns up to 5; the strip renders one.
    An "and 2 more" affordance is not designed.
