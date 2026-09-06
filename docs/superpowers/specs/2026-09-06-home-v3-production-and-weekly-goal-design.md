# Home v3 in production, and the weekly goal behind its strip — design

Owner rulings, 2026-09-06 (after seeing variation 08 with the targets strip rendered both ways):
1. The strip sits **above the calendar** (08a).
2. The crew-pulse strip shows **only when a friend is actively working out**; otherwise it is gone and
   everything shifts up.
3. The strip is **"your goal this week", not "muscle-group sets"**. Muscle-group sets is right when the
   goal is strength or hypertrophy. If the goal is something else — miles per week running or biking,
   HIIT sessions per week — the strip shows that instead. Coach detects the goal; the user can edit it
   by tapping the strip, which opens a goal menu with "a bunch of different levers"; Coach can also set
   it himself.

Everything Home is now decided. This document is the design for (A) moving Home v3 into production,
(B) the weekly goal system the strip renders, and (C) the calendar & scheduling page the calendar card
opens. It is the gate for the implementation plan. Design language: `docs/superpowers/specs/2026-09-05-design-language.md`.

## What exists, verified in the repo (so the plan does not invent)

- Home v3 pieces are on master under `Features/Home/V2/` as catalog-only views with fixture inputs
  (PRs #29, #31, #32): `HomeOneButton` (five states), `HomeSoloRow`, `HomeStreakTile`, `HomeCoachTile`,
  `HomeCrewPulseStrip`, `HomeCoachTargetsStrip`, `HomeCalendarCard(showsAppointments:)`,
  `HomeV2JoinCodeCard`, `HomeV2GreetingHeader`. Production `HomeView.swift` (1,881 lines) is untouched.
- **No weekly per-muscle target exists.** Routines carry per-exercise `targetSets`; there is no weekly
  volume target model. A muscle-sets goal must be **derived**: the active block's routines for the week
  → exercises → muscle group → summed target sets; progress = this week's `set_logs` grouped the same way.
- **HealthKit reads only heart rate and nutrition** (`Services/HealthKitBridge.swift:21-25`); it
  exports workouts but reads no `HKWorkout` or distance. Distance goals (running, biking) need a new
  read authorization and a workout/distance query.
- **No "friends who are live" query exists.** Sessions have `state = 'in_progress'` and participants;
  there is no view or RPC that returns a friend's live session. The crew pulse needs one, RLS-safe.
- Coach's knowledge of the goal: the consult persists a training profile (`TrainingProfileRepository`),
  the block generator has a persona lens (barbell-first, explosive, fatigue-averse…), and the orphaned
  wizard's `GoalRankingSection` (ranked goals) has no live call site.

## A. Home v3 in production

Composition, top to bottom (variation 08a, exactly what the owner approved):

1. Greeting header with the `?` help door and the avatar (unchanged).
2. Sync-failure banner when applicable (unchanged).
3. **The one button** (`HomeOneButton`), replacing today's join hero, gold check-in tile, countdown tile
   and empty tile. State resolution reuses what `HomeView` already computes: `todaysSession`,
   `nextActionableSession`, `checkInOpensAt`, `ProgramToday.resolveRoutine`. Every state opens the start
   screen or the lobby; **none starts a workout by itself** (rule 5).
4. **Solo row** — `START SOLO WORKOUT` pill + burpee widget — only when the primary is a crew state.
   (Today's pill and widget, unchanged behaviour.)
5. **Streak tile | Coach tile.** Streak keeps today's data (`UserStreak`, `daysThisWeek`, `effectiveWeeklyGoal`)
   and the `WeeklyGoalSheet` on tap; the number goes gold (rule 2). Coach tile: the word, one sentence
   from the coach (the existing `BlockProgression` / debrief headline path — whichever produces the
   next-session line today), the accent count badge when something waits, tap → Coach.
6. **Crew pulse strip — conditional.** Rendered only when `friendsLive` is non-empty (see B-data). When
   absent, nothing is rendered and the layout shifts up (ruling 2). Copy: `{Name} is lifting now` /
   `{Crew} · {when}` when the live session is a crew session, else `{Name} is lifting now` / `Solo` .
   Tap → that session's lobby if you are a participant, else the crew room.
7. **This week's goal strip** (`HomeCoachTargetsStrip`, renamed `HomeWeeklyGoalStrip`) — see B.
8. **Calendar card as a door**: three months of dots, `{n} UPCOMING`, `+` (opens the schedule sheet),
   chevron; **no appointment rows**; tap anywhere → the calendar & scheduling page (C).
9. Campaigns carousel (unchanged, when active) and join-with-code (unchanged).

Removed from Home: the join hero, the check-in tile in all three states, the "Schedule a session" row
(its job moves to the calendar's `+` and the page), the weekly slot-grid form of the streak tile (the
slot grid survives inside the new tile at tile scale), and the appended upcoming rows. Everything that
lived only on Home (join-by-code, burpee roll-up, campaigns, `?` help, the watch idle push, the replay
banner, the spotlight tour) stays. The tour's four steps are re-pointed at the new elements.

## B. The weekly goal

### Model

`WeeklyGoal` — one per user per ISO week, with a `kind` and per-kind parameters:

| kind | parameters | progress source | strip rendering |
|---|---|---|---|
| `muscleSets` | `[muscleGroup: targetSets]` (up to 6 groups) | this week's `set_logs` → exercise → muscle group | four chips (the four largest targets), meter + fraction; one **next** (furthest behind), **met** in green |
| `distance` | `activity` (run / bike / row / walk), `target` in km or mi | HealthKit workouts of that activity this week (new read) | one meter with the activity glyph, `9.4 / 15 mi`, days remaining |
| `sessionsOfType` | `type` (HIIT, mobility, cardio, class), `count` | completed sessions this week tagged with that type (routine tag or HealthKit workout type) | `n` dots, filled as done, `2 of 3 HIIT` |
| `days` | `count` | distinct training days this week (the streak tile's own number) | the week strip's day chips |
| `lift` | `exercise`, `targetWeight`, `by` (date) | current e1RM from `set_logs` | `205 → 225`, meter from the block's start e1RM, weeks left |

`source ∈ {coach, user}`, `weekStart`, `setAt`. Persisted in a `weekly_goals` table (user_id, week_start,
kind, params jsonb, source, created_at) with RLS "own rows"; Coach writes with `source = coach` from the
same server-side path that books a block's weeks (`WeekBooker` / `ProgramBuilder`), so a block always
arrives with its goal.

### Detection ("detectable by Coach")

When a week starts with no goal row, Coach derives one, in this order:
1. **Active block** → its intent decides the kind: a strength/hypertrophy block → `muscleSets` derived
   from the week's routines (sum of `targetSets` per muscle group); a block with a focus lift and a
   target → `lift`; a conditioning-flavoured block (Hybrid Athlete lens, cardio/HIIT routines) →
   `sessionsOfType` or `distance` when the routines carry distance.
2. **No block, training profile present** → the profile's stated goal (the consult already asks) maps
   to a kind: "get stronger" → `lift` on the focus lift or `muscleSets`; "run/bike more" → `distance`;
   "consistency" → `days` at the profile's weekly goal.
3. **Nothing known** → `days` at `Profile.effectiveWeeklyGoal` (the streak's number) — never empty.

A user-set goal (`source = user`) is never overwritten by detection; Coach may **propose** a change
through the Coach tile's line, and the user accepts in the editor.

### The goal editor (tap the strip)

A sheet, "Your goal this week", in the design language: a segmented row of kinds as chips
(`MUSCLE SETS · MILES · SESSIONS · DAYS · A LIFT`), then the levers for the chosen kind:
- muscle sets: up to six muscle rows with ± steppers (defaults from the block);
- miles: activity picker + target stepper (mi/km follows the unit setting);
- sessions: type picker + count stepper;
- days: count stepper 1–7 (writes the same `weeklyGoal` the streak sheet edits — one source of truth);
- a lift: exercise picker (focus lifts first), target weight, by-date.
Footer: `LET COACH SET IT` (raised) resets `source` to coach and re-derives; `SAVE THIS WEEK'S GOAL`
(accent primary). Copy line under the header: "Coach set this from your block. Change it here; Coach
follows your lead for the rest of the week." Rule 4: one accent button.

### Strip states

- Goal present → the kind's rendering above, kicker `THIS WEEK · {COACH'S | YOUR} GOAL`, right-hand
  read = days or sessions remaining from the same week the streak tile shows (they must agree — the
  fixture law from the catalog work).
- Met → the strip stays, green fraction/meter, kicker `GOAL MET · {n} DAYS LEFT`.
- No goal (only possible before first detection) → `Set a goal for this week ›` as an invitation line
  in accent (rule 3).

## C. The calendar & scheduling page

Opened by tapping anywhere on the calendar card. From the v7 proof:
- Month grid (dots: trained = text, scheduled you = accent ring, crew = crew colour ring, today ring),
  swipe months; the selected week's agenda below: one row per item with time, routine, crew or Solo,
  status pill (IN / COMMIT), chevron → lobby or editor; series rows show ↻ and open the series editor.
- Timeline items beyond sessions: the block's days (`Coach block · week 2 of 6 · Tue Thu Sat · CHANGE
  DAYS ›` → `BlockCalendarView`) and campaign deadlines (`ends Sep 30 · 61%` → campaign detail).
- `SCHEDULE A SESSION` primary → the existing `ScheduleSessionView`. Swipe a row to move or cancel
  (uses the existing edit paths).
- This is the home of "anything on a timeline is editable" (design rule 4). No new data model; it is a
  composition of `TrainingCalendarWidget`'s dot field, `upcoming(limit:)`, series, block and campaign
  repositories.

## Phasing (so Home can ship before the whole goal system exists)

- **Phase 1 — Home v3 layout + calendar page + goal strip in `muscleSets` and `days` kinds.** Both are
  derivable from data the app already has. Coach detection = rules 1 (block) and 3 (days). Editor ships
  with those two kinds. Crew pulse strip **omitted** (needs new data) — the layout already handles its
  absence. This is the first user-facing Home change of the round.
- **Phase 2 — the rest of the goal kinds.** `lift` (e1RM from set_logs, no new data), `sessionsOfType`
  (routine tags), `distance` (new HealthKit workout/distance read + authorization copy). Editor gains
  the kinds; detection gains rule 2 (profile).
- **Phase 3 — crew pulse.** A `friends_live` RPC (friends' sessions in `in_progress`, RLS-safe), the
  strip wired to it, refreshed on Home's existing cadence and on the live-session channel.

## Owner answers (2026-09-06) — binding

1. **Major muscle groups**, and **secondary muscles must be credited correctly**: a set counts fully
   toward the exercise's primary group and partially toward each secondary group (proposal: 0.5 set per
   secondary group, capped so one set never credits more than 1.0 in total across secondaries; the
   plan fixes the exact weights from the exercise catalog's primary/secondary fields). Groups: chest,
   back, shoulders, legs, arms, core; the strip shows the four largest targets.
2. **Metric and imperial**: `distance` follows the app's unit setting (mi with lb, km with kg).
3. **Propose only**: Coach never overwrites a user-set goal; it proposes through the Coach line, and
   the user accepts in the editor.
4. **Build all three phases and ship in one release.** Development is **paired**: the backend/model
   stream (goal table, derivation, friends-live RPC, HealthKit read) and the UI streams (Home wiring,
   goal editor, calendar page) run in parallel worktrees against an interface fixed first, and
   integrate at the end. Nothing user-facing merges until the whole is verified through CI captures.
