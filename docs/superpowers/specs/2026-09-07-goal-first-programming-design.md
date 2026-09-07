# Goal-first programming — the goal, the ladder, and the block — design

**Status:** approved in conversation 2026-09-07 (owner: "That sounds good to me! Go execute"); this document is
the written form for the owner's review before a plan is written.
**Gate documents:** `docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly-goal-design.md` (the weekly
goal, shipped in PR #35), `docs/superpowers/specs/2026-09-05-design-language.md` (the rules every screen
follows). Context map with file:line references: `.superpowers/sdd/2026-09-07-design-round/context-map.md`;
the round's decisions: `.superpowers/sdd/2026-09-07-design-round/decisions.md`.

## Why

The owner, on build 863: *"when you click build program, it presents you with just a list of routines … it was
supposed to manifest something different … the building block for progress … the flow should ask what are your
goals, and the work tree branches from there."*

What is true today: the Build door (`CoachHomeView` → `CoachConsultView` → `ProgramBuilder.build()` →
`ProgramGenerator.generate`) runs a deep generator — nine-factor exercise selection, prescription by percent of
one-rep max and reps in reserve, weekly volume balancing, four progression layers, and a decision log rendered as
"Why this block". But a block is defined as **one static week of generated routines repeated for the block**,
booked week after week by `WeekBooker`. The athlete sees that week's routines in their routine list and reads the
feature as "pick routines to repeat". Nothing on Home shows the block moving. The original intent — a personal
vehicle of progress, once called a campaign — was never written down; the campaigns that shipped are the
community events.

This design puts a **goal** in front of the generator and a **ladder** behind it, so that every block is the
pursuit of one named milestone, and every week on Home is one rung of that pursuit.

## 1. Vocabulary

| Word | Meaning |
|---|---|
| **Goal** | One measurable thing the athlete is going after in this block: a metric, a target, and (where it has one) a date. One primary goal per block. |
| **Milestone** | The goal's endpoint: the target on the date. ("Bench 225 by Oct 18." "Twelve chest sets a week, held for six weeks.") |
| **Metric** | A quantity the app can measure about the athlete: e1RM of a lift, weekly sets per muscle group, weekly distance, training days, sessions of a type, LISS minutes, stretching exercises. Each metric has a **reader** (where am I now) and a **ladder rule**. |
| **Rung** | The weekly subgoal: this week's step toward the milestone. The Home strip shows the current rung. |
| **Ladder** | The ordered rungs from the athlete's measured current state to the milestone, one per week of the block. |
| **Block** | The multi-week program Coach generates to climb the ladder. The block exists to serve the goal; no block exists without one. |
| **Preset** | A named, ready-made goal over the metric registry (Strength, Muscle, …). Free. |
| **Coach-guided goal** | A goal and ladder found by talking it through with Coach. Pro. |

"Milestone" here is the goal's endpoint. It is distinct from the volume milestone catalog (plates, the Earth ring),
which stays its own thing.

## 2. The goal model

### 2.1 A goal is a metric, a target and a date

```swift
struct BlockGoal: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    let userID: UUID
    let enrollmentID: UUID            // the block this goal drives (program_enrollments.id)
    var metric: GoalMetric            // what is measured (registry, §2.2)
    var target: GoalTarget            // the milestone value, typed per metric
    var byDate: Date?                 // the milestone date; nil = "held for the block" (maintenance, recovery)
    var preset: GoalPreset?           // which preset produced it; nil = Coach-guided or custom
    var source: WeeklyGoalSource      // coach | user — who last set the milestone (reuses the shipped enum)
    let createdAt: Date
    var updatedAt: Date
}
```

`source` follows the shipped rule exactly: Coach may write a `coach` goal freely and may **never** overwrite a
`user` one; when Coach wants to change a user's milestone or date it **proposes** through the existing
`propose(weekStart:)` channel and the Coach line, and the athlete accepts in the editor.

### 2.2 The metric registry

The registry is open — the owner's ruling is that five kinds are too restrictive. Each metric declares a reader
(current state) and a ladder rule (§3). Launch set:

| Metric | Reader (exists today unless marked NEW) | Unit |
|---|---|---|
| `liftOneRepMax(exerciseID)` | `StatMath.estimatedOneRepMax` over `set_logs` (`WeeklyGoalProgressMath.liftProgress`) | lb canonical, shown in the user's unit |
| `weeklyMuscleSets(group)` | `MuscleGroup` rollup over `set_logs` (`muscleSetsProgress`) | sets/week |
| `weeklyDistance(activity)` | HealthKit workouts (`distanceProgress`) | mi or km with the user's unit |
| `trainingDaysPerWeek` | distinct training days (`distinctTrainingDays`) | days/week |
| `sessionsOfTypePerWeek(type)` | inferred session type (`sessionsOfTypeProgress`) | sessions/week |
| `lissMinutesPerWeek` | **NEW** — HealthKit workouts of walking / cycling / rowing / elliptical at low intensity, or app sessions whose routine is cardio-only | minutes/week |
| `stretchingExercisesPerWeek` | **NEW** — count of logged exercises whose catalog category is mobility/stretch, or of completed mobility circuits | count/week |

A metric that cannot be read on this device (Health not connected) renders `CONNECT HEALTH`, never `0`, per the
shipped rule. Body-weight and skill metrics (first pull-up, handstand) are **not** in the launch registry — they
need a weigh-in source and progression ladders the catalog does not carry. The registry is designed so they slot in
as entries, without changing the door.

### 2.3 Presets

Presets are goals over the registry with a default ladder shape. All free.

| Preset | Metric | Milestone the door asks for | Ladder shape |
|---|---|---|---|
| **Strength** | `liftOneRepMax(lift)` | a lift, a target load, a date | read off the block's prescribed loading (§3.2) |
| **Muscle** | `weeklyMuscleSets(group)` | a group and a weekly set count | volume titration's climb (§3.3) |
| **Endurance** | `weeklyDistance(activity)` | an activity, weekly distance or an event distance, a date | +10 % a week, down week every fourth |
| **Consistency** | `trainingDaysPerWeek` | days per week, held for N weeks | +1 day every two weeks until the target holds |
| **Conditioning** | `sessionsOfTypePerWeek(type)` | a type and a weekly count | same ramp as Consistency |
| **Maintenance** | `weeklyMuscleSets(all major groups)` | none — "hold the recommended numbers" | flat at the recommended volumes (`volume_targets`, else the generator's bands) |
| **Recovery** | `lissMinutesPerWeek` + `stretchingExercisesPerWeek` | none — a recovery block of N weeks | flat or gently descending; LISS minutes and a stretching count per week |

Recovery is the one preset with two metrics. It is still **one goal**: the primary metric is
`stretchingExercisesPerWeek` (what the block schedules), LISS minutes is its companion read, shown on the same rung.
Nothing else in the design changes for it.

### 2.4 Coach-guided goals (pro)

The pro path is a conversation: the athlete describes what they want ("I want to be able to do a strict muscle-up
by spring", "I'm coming back from a shoulder thing"), and Coach identifies the goal — which metric, what target,
what date is realistic from the athlete's history — and the ladder to get there, then builds the block. It reuses
the existing consult (`CoachConsultView`, ending on BUILD IT) with the goal as its first and binding output: the
consult cannot end without a `BlockGoal`. A Coach-guided goal may use any metric in the registry and may propose a
milestone the presets would not (a lift the athlete never named, a distance event). It never invents a metric the
registry cannot read; if the wish maps to nothing readable, Coach says so and offers the nearest preset.

## 3. The ladder

### 3.1 Definition

```swift
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
```

The ladder is a **read-out of the generated block projected onto the goal's metric**. It is not a second schedule.
The generator already produces `Program.weeks` (per week: `volumeMultiplier`, `intensityMultiplier`, `isDeload`)
and per-slot prescriptions (`sets`, `repsLow`, `repsHigh`, `percentOfMax`, RIR). The ladder is computed from those,
so the ladder and the plan cannot disagree.

### 3.2 Strength: the rung is the prescribed loading

The owner's ruling: *goals are captured by the %1RM loading the programming prescribes, not an arbitrary cycle.*

For week *k*, the rung is the top working load the block prescribes for the goal lift's main slot:
`baselineE1RM × percentOfMax(slot) × intensityMultiplier(week k)`, expressed as "3 × 5 at 190" and as the e1RM
that set implies. The milestone is met when the athlete's measured e1RM (from logged sets) reaches the target on or
before the date. The block's own deload and taper weeks appear in the ladder as what they are (a lower rung with
the label DELOAD), because they are in the prescription — the ladder does not smooth them away.

If the generator's prescribed loading cannot reach the target by the date (the ramp implied is faster than the
block allows), Coach says so at the door — *"225 by Oct 18 needs more than this block can safely give; Nov 15 is
the date I can build to"* — and the athlete picks: move the date, lower the target, or keep both and accept the
ladder will fall short. The ladder never lies about the gap.

### 3.3 Muscle, Maintenance: the rung is the week's planned effective sets

`Program`'s weekly effective sets per group (`weeklyMuscleSets`, primary 1.0 + secondary 0.5) **are** the rungs,
after `balanceWeeklyVolume`. For Muscle the block climbs toward the target group count with volume titration's
add / hold / cut / deload decisions (`VolumeTitration`, recovery probes); for Maintenance the rungs are flat at the
recommended volumes. The Home strip renders these exactly as it renders `muscleSets` today.

### 3.4 Endurance, Consistency, Conditioning, Recovery: ramp rules

These metrics are not prescribed by the lifting generator, so their ladders come from ramp rules in code:
distance +10 % a week with every fourth week down; days and sessions +1 every two weeks until the target holds;
recovery flat. Each rule is a pure function `(current, target, weeks) -> [target per week]` with tests. The block
generator receives the rung as an input where it changes the plan (a cardio day placed, a mobility circuit added),
through the existing conditioning / cardio passes.

### 3.5 Adaptive re-laddering (owner's option 1)

Each week, when the new week starts (or on the first Home load of the week), Coach re-derives the remaining rungs
from **actuals**: the measured current state, not last week's rung. A missed week does not leave a hole to catch
up; the ladder moves. A beaten week moves it the other way. The **milestone and its date are the athlete's**:
Coach never moves them silently. When the re-derived ladder can no longer reach the milestone by the date, Coach
proposes a new date (or target) through the propose channel; until accepted, the ladder shows the gap honestly
("on this ladder you reach 218 by Oct 18").

For Strength, re-laddering means regenerating the block's remaining weeks' loading from the new e1RM baseline, the
way `BlockProgression` already adjusts loads session to session — the ladder is re-read from the regenerated plan.

## 4. The weekly goal is the current rung

The shipped weekly goal (`weekly_goals`, one row per user per week, `WeeklyGoal{kind, params, source}`) becomes the
**materialised current rung**. Each week the ladder writes that week's row with `source = coach` — a Coach write,
allowed by the shipped rule — and the strip renders it with the readers that already exist.

Mapping from metric to the shipped `WeeklyGoalKind`:

| Metric | `WeeklyGoalKind` | `params` |
|---|---|---|
| `liftOneRepMax` | `lift` | `exerciseID`, `targetWeightLbs` = the rung's e1RM, `byDate` |
| `weeklyMuscleSets` (Muscle, Maintenance) | `muscleSets` | `muscleTargets` = the rung's per-group sets, `targetSource` |
| `weeklyDistance` | `distance` | `activity`, `distanceTarget` = the rung |
| `trainingDaysPerWeek` | `days` | none (the profile's weekly goal is the number, per the shipped rule — the ladder writes the profile's weekly session goal through its existing deferral) |
| `sessionsOfTypePerWeek` | `sessionsOfType` | `sessionType`, `count` |
| `stretchingExercisesPerWeek` (+ LISS) | **`recovery` (NEW kind)** | `count` = stretching exercises, `lissMinutes` (NEW field) |

`WeeklyGoalKind` gains one case (`recovery`) and `WeeklyGoalParams` two fields (`lissMinutes`, `goalID`), all
additive. `weekly_goals` gains `goal_id uuid` and `rung_index int` (nullable, additive) so a row knows the ladder
it belongs to; a row with `goal_id = null` is a standalone weekly goal exactly as today.

An athlete's edit of this week's row (the shipped editor) is an **override of the rung**: the row becomes
`source = user`, the ladder marks the rung `overridden`, re-laddering starts from actuals as before, and Coach's
propose-only rule protects the override. The ladder page (§6) is where the athlete edits the milestone itself.

## 5. The front door

**"Set a goal → Coach builds your block."** Building a block always begins with the goal; there is no other entry.

1. **The goal screen.** Title *Your goal for this block*. The seven presets as a grid of raised cards (name, one
   line, the metric's glyph). Below them one door: *Talk it through with Coach* — the pro path (§2.4), badged. The
   athlete taps a preset.
2. **The milestone.** One card per preset with the levers it needs and nothing else (design rule: questions above
   the fold): Strength — the lift (picker, focus lifts first), the target load (stepper in the user's unit,
   seeded from e1RM + a realistic gain), the date (picker, seeded from the block length); Muscle — the group and
   the weekly sets; Endurance — the activity, the weekly distance or event, the date; Consistency — days per week;
   Conditioning — the type and count; Maintenance and Recovery — the block length only. Coach's line under the
   levers states current state and what the ladder would look like ("You're at 205 now; that's about 6 weeks of
   work").
3. **Build.** The primary reads *BUILD MY BLOCK*. It runs `ProgramBuilder.build()` with the goal as an input:
   `ProgramGenerator.Inputs` gains `goal: BlockGoal`, which sets the focus band and the focus exercise where the
   goal names one, the block length from the date, and the conditioning / mobility placement for the ramp metrics.
   The consult's "Reading your rules, picking the lifts, setting the week" copy stays. Landing is the ladder page
   (§6), not the routine list.
4. **No block without a goal.** `ProgramBuilder.build()` requires a `BlockGoal`; the legacy wizard path
   (`CoachWizardView`) either routes through the goal screen first or is retired (the plan decides; the door is the
   one way in either way). Existing enrollments without a goal get a Coach-detected one on first Home load, derived
   from the enrollment's `focus` and `baseline` the way Home already fills an empty week.

The routine list is unchanged: the block's routines still appear there as "Coach · …" routines, because the
athlete starts sessions from them. They are the block's days, not its identity.

## 6. Where it shows

- **Home, the weekly strip** — unchanged shape; it renders the current rung. The kicker gains the block context:
  `WEEK 3 OF 8 · COACH'S GOAL` (or `YOUR GOAL` after an override). The right-hand read stays the rung's read
  (`1 SESSION LEFT`, `3 DAYS LEFT`, `CONNECT HEALTH`).
- **Tap the strip → the Ladder page** (new). Top: the milestone as the headline ("Bench 225 by Oct 18"), the date,
  Coach's one line on standing ("On track" / "This ladder reaches 218 — move the date?"). Then the ladder: one row
  per week — week number, the rung's target in words, status (met in green, missed muted, current ringed in accent,
  ahead default, DELOAD labelled). Below: the levers the athlete owns — edit the milestone, edit the date, edit this
  week's rung (the shipped editor, scoped to the rung), *LET COACH RE-LADDER* (raised). The one accent primary is
  the save. Explanation lines relevant to the goal are pulled from `Program.notes` (the generator's decision log)
  so the ladder says why a week is what it is.
- **The block's schedule page** (`ProgramScheduleView`) gains the ladder card at the top, above "Why this block",
  and keeps everything else.
- **The ledger** (`ProgramLedgerView`) records the goal's outcome with each finished block: met, missed, or
  partial, with the milestone and the final measured value.
- **Coach's line on Home** (rung (a) of `coachSentence`) carries ladder proposals: a date move, a target change,
  a rung Coach would raise.

## 7. Block end

When the last week closes, the milestone is checked against the metric's reader: **met**, **missed**, or
**partial** (with the measured value). The recap names the outcome, what carried it, and what Coach would set
next. The next block starts at the goal screen again, seeded with Coach's suggestion (a maintenance block after a
strength peak; the next rung of the same lift; a recovery block after a hard one).

## 8. Data

New tables, own-rows RLS in the repo's four-policy shape, `updated_at` triggers per the existing convention:

```sql
create table public.block_goals (
  id            uuid primary key default gen_random_uuid(),
  user_id       uuid not null references public.profiles(id) on delete cascade,
  enrollment_id uuid not null references public.program_enrollments(id) on delete cascade,
  metric        text not null,           -- registry key, e.g. 'lift_one_rep_max'
  target        jsonb not null,          -- typed per metric (camelCase keys, like weekly_goals.params)
  by_date       date,
  preset        text,                    -- 'strength' | 'muscle' | … | null (Coach-guided/custom)
  source        text not null default 'coach' check (source in ('coach','user')),
  outcome       text check (outcome in ('met','missed','partial')),
  outcome_value jsonb,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  unique (enrollment_id)                 -- one primary goal per block
);
create table public.block_goal_rungs (
  goal_id     uuid not null references public.block_goals(id) on delete cascade,
  week_index  int  not null,
  week_start  date not null,
  target      jsonb not null,
  status      text not null default 'ahead' check (status in ('ahead','current','met','missed','overridden')),
  derived_at  timestamptz not null default now(),
  primary key (goal_id, week_index)
);
alter table public.weekly_goals add column goal_id uuid references public.block_goals(id) on delete set null,
                                add column rung_index int;
```

Rungs are persisted (not only computed) so that missed and overridden weeks remain visible after re-laddering, and
so the ledger can show the climb. Re-laddering rewrites only rungs with status `ahead` or `current`.

## 9. Pro gating

Presets and their ladders are free. *Talk it through with Coach* — a Coach-guided goal and ladder — is pro, behind
the app's existing entitlement gate (the plan names the gate). Nothing about the free path degrades: a free athlete
gets a full goal, a full ladder, and Coach's adaptive re-laddering and proposals.

## 10. Phases

- **Phase 1 — the door, the ladder, five presets + Maintenance.** `BlockGoal`, the registry for the five shipped
  metrics, presets Strength / Muscle / Endurance / Consistency / Conditioning / Maintenance, the goal screen, the
  goal as a generator input, the ladder read-out for Strength and Muscle, ramp rules for the other three, the
  ladder page, the strip's block kicker, weekly materialisation into `weekly_goals`, adaptive re-laddering,
  migration of existing enrollments, tables and pgTAP. Ships in one PR with proof cards before merge.
- **Phase 2 — Recovery + Coach-guided goals.** The two NEW readers (LISS minutes, stretching count), the `recovery`
  kind, the pro consult path that binds a `BlockGoal`, and Coach's date/target proposals surfaced on the ladder.
- **Phase 3 — block end.** Outcome check, the recap, the ledger's outcomes, the seeded next goal.

## 11. What this design does not decide

1. The exact set of "major muscle groups" a Maintenance goal holds, and whether `volume_targets` or the generator's
   bands are the recommended numbers when both exist (the Home v3 plan left the two accountings unreconciled; this
   design reads whichever the block was built from and says so on the ladder).
2. How LISS is detected without Health (heart-rate zones need the watch; without it, a cardio-only routine counts).
3. Whether the legacy `CoachWizardView` is retired or routed through the goal screen (the plan decides after
   reading its remaining call sites).
4. The wording of the door and the ladder page beyond what is written here (copy pass at plan time, design rules
   8 and 9).
5. A second concurrent goal (a "side quest"): explicitly out; one primary goal per block is the ruling.

## Owner decisions (2026-09-07) — binding

1. Programming "feels off" because of the front door, not the generator; the block must manifest the pursuit of a
   goal, and the flow starts from "what are your goals".
2. **One primary goal per block.** Goal and program are one object at two time scales; Home's weekly strip is the
   block's slice for this week; standing constraints live in Coach's rules.
3. **A progression system per goal shows the stepping stones to the milestone** — the ladder.
4. **Building a program always assigns a goal**, so the goal-and-ladder pair is what Home tracks.
5. **Five kinds is too restrictive**: the vocabulary is open (Maintenance = hold the recommended muscle-group
   numbers; Recovery = LISS cardio plus a count of stretching exercises or circuits; many more possible).
6. **The strength ladder is the %1RM loading the programming prescribes**, never a cycle imposed on top.
7. **Talking to Coach to identify the right goal and ladder is a pro feature.**
8. **Re-laddering is adaptive (option 1):** Coach re-ladders from actuals weekly; the milestone and its date belong
   to the athlete; Coach proposes date moves and never makes them.
