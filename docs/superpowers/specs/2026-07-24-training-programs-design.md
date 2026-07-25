# Training Programs ("self-assigned personal trainer") — Design

**Date:** 2026-07-24
**Origin:** User feature request (2026-07-24 feedback round): "People like to
temporarily cycle focus on certain muscle groups, certain lifting styles like
strength focused, hypertrophy focused. A feature here would be something like
'the march to one rep max', or 'Leg focused strength gain'. Depending on the
campaign, this becomes a 6-12 week, maybe longer, schedule interruption for
the muscle group focus, or a suggested rep or weight goals for the other
campaigns. This feels like a self assigned personal trainer type addition."
Direction approved by user: "Go with your suggestions on the campaign."

## What this is

A **program** is a self-assigned, multi-week training focus with concrete
weekly rep/weight targets personalized from the user's own PR history. It is
NOT the existing Phase C campaign (team-curated seasonal *community* events
with join/leaderboard/community bar — `20260728000001_campaigns_schema.sql`).
Programs and community campaigns share the Library ▸ Campaigns surface but are
separate systems: campaigns are something the team runs for everyone;
programs are something one user runs for themself.

## Approved shape (three phases)

1. **Phase P1 — personal program templates** (this spec's implementable core):
   app-shipped templates, enroll with a baseline, see personalized weekly
   targets, track progress. No schedule mutation.
2. **Phase P2 — schedule integration**: "plan my week" generates scheduled
   solo sessions from the active program week (user previews + confirms).
3. **Phase P3 — community programs**: user-authored templates published to
   Discover with stars. Sketched only; not designed here.

**v1 progression principle (locked):** simple and transparent. Every target
the app suggests must show its math ("82.5% of your 225 lb est 1RM → 185 lb").
No hidden autoregulation, no automatic deload triggers, no stall detection —
templates may *contain* a deload week, and the user can repeat a week
manually, but the app never silently changes the plan. The domain depth
(RPE, fatigue management) is real; v1 stays honest by being a calculator,
not a coach that pretends to watch you.

---

## Phase P1 design

### Templates: bundled in-app, not in the database

Templates are code-defined Swift values (`ProgramTemplate`), not DB rows.
Rationale: a template is logic + copy that must stay in lockstep with the
client that renders it (percent schemes, week math, focus-picker rules).
Bundling removes curation infra, versioning/sync questions, and an RLS
surface — the same trust boundary as the bundled exercise catalog's display
logic. Phase P3 revisits this when user-authored templates need server
storage.

**v1 template list (3):**

| slug | name | length | focus | scheme summary |
|---|---|---|---|---|
| `march-to-1rm` | March to One-Rep Max | 8 wk | 1 barbell lift (user picks) | Linear peak: 5s → 3s → doubles/singles, %TM 70→95, week 5 deload (60%), week 8 test week |
| `leg-strength-block` | Leg-Focused Strength | 6 wk | squat-pattern lift + accessory hinge | 2 lower sessions/wk, 5×5 at 75→85%, week 4 deload |
| `hypertrophy-block` | Hypertrophy Block | 8 wk | 1 muscle-group emphasis (user picks) | 8–12 rep sets, volume ramps by set count not %1RM, week 5 deload |

Exact per-week tables live in the implementation plan; the shape they must
fit is:

```swift
struct ProgramTemplate {           // bundled, Identifiable by slug
    let slug: String
    let name: String
    let summary: String            // card copy
    let weeks: [ProgramWeek]
    let focusRule: FocusRule       // .singleBarbellLift | .liftPlusAccessory | .muscleGroup
    let sessionsPerWeek: Int
}
struct ProgramWeek {
    let percentOfBaseline: Double? // nil for volume-driven (hypertrophy) weeks
    let sets: Int
    let reps: Int
    let isDeload: Bool
    let note: String?              // "Test week: work to a heavy single"
}
```

### Baseline: est 1RM from real history, never a guess

At enrollment the app derives a **training max** per focus lift:

- Primary source: the user's best qualifying set on that exercise
  (`SessionRepository.exerciseHistory` exclusions) run through
  `StatMath.estimatedOneRepMax` (Epley, `StatMath.swift:114`).
- If no history exists for the chosen lift: the user enters one recent
  "weight × reps" set and the app applies Epley to it. The enrollment sheet
  never invents a number (same "no PR → no estimate" doctrine as
  `StatMath.projectedWeight`, `StatMath.swift:123`).
- The baseline is **frozen at enrollment** (stored on the enrollment row).
  Weekly targets are `percentOfBaseline × baseline`, rounded to 5 lb via the
  existing inverse-Epley rounding idiom. Freezing keeps every week's math
  auditable; a mid-program PR does not silently rewrite the plan. The user
  can re-baseline explicitly from the program card (recorded as a new
  baseline value — still one tap, still transparent).

### Server state: one table

```sql
program_enrollments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  template_slug  text NOT NULL,
  focus          jsonb NOT NULL,      -- {"exercise_ids":[...], "muscle_group": "..."} per FocusRule
  baseline       jsonb NOT NULL,      -- {"<exercise_id>": 225.0, ...} est-1RM lbs at enrollment
  started_on     date NOT NULL,
  weeks          integer NOT NULL CHECK (weeks BETWEEN 1 AND 52),
  ended_at       timestamptz,         -- set on completion OR abandonment
  ended_reason   text,                -- 'completed' | 'abandoned' (null while active)
  created_at     timestamptz NOT NULL DEFAULT now()
)
-- one active program at a time:
CREATE UNIQUE INDEX one_active_program_per_user
  ON program_enrollments(user_id) WHERE ended_at IS NULL;
```

- RLS: owner-only for SELECT/INSERT/UPDATE/DELETE (`user_id = auth.uid()`),
  the `soundboard_favorites` idiom. No curator/admin surface, no cross-user
  reads in P1 (P3 will need them; not before).
- `weeks` is copied from the template at enrollment so old enrollments stay
  interpretable if a bundled template changes length later.
- Current week is **derived**: `floor(days(today − started_on) / 7) + 1`,
  clamped to `weeks`. No stored cursor to drift. "Repeat a week" (manual
  deload) = the user shifts `started_on` forward 7 days via the program
  card — a plain owner UPDATE, and the math stays honest.
- Progress is **derived from existing set logs** (sessions completed this
  week vs `sessionsPerWeek`, est-1RM trend on focus lifts) — no triggers, no
  counters, nothing the client could double-count. The Phase C progress
  trigger stays campaigns-only.

### UI

All inside the existing **Library ▸ Campaigns** sub-tab (no fifth segment —
the 4-pill control is already at minimum type size):

- **"Your program" section (top, when enrolled):** card with program name,
  "Week 3 of 8", this week's prescription ("3×5 @ 82.5% → 185 lb"), a
  sessions-this-week progress indicator (`StatMath.workoutsThisWeek`
  filtered per week bucketing), and the deload/test-week note when the
  template sets one. Tapping opens the program detail.
- **Program detail (enrolled):** full week-by-week table with the user's
  actual weights filled into every row (the whole plan visible up front —
  transparency doctrine), re-baseline action, repeat-week action, abandon
  action (confirmation; sets `ended_at`/`ended_reason`).
- **Template gallery ("Start a program"):** template cards below the Your
  program section (or as the section's replacement when not enrolled),
  above the existing community-campaigns sections. Card → template detail:
  summary, the scheme table in % form, focus picker (seeded from the lifts
  the user has PR history on), baseline confirmation, Start.
- **Home:** the existing "Campaigns you might like" shelf is untouched. When
  a program is active, a compact "Week 3 of 8 · 1 of 3 sessions done" line
  is added to the Home campaigns section card. (Option, cheap; cut first if
  the section crowds.)
- Completion: when the derived week passes `weeks`, the card flips to a
  summary state (baseline vs current est 1RM on focus lifts) with a
  "Finish" action that stamps `ended_at`/`ended_reason='completed'`. No
  server-side completion machinery.

### Testing

- **pgTAP** (`program_enrollments_test.sql`): owner CRUD lives; cross-user
  read/write 42501; second concurrent active enrollment rejected by the
  partial unique index; ended enrollment allows a new active one.
- **Swift pure-math tests** (`ProgramMathTests`, no network — the
  `StatMath`/`BurpeeLedgerMath` pattern): week derivation (start, mid,
  clamp at end, repeat-week shift), target computation (percent × baseline
  → 5 lb rounding, nil-percent weeks), baseline derivation from a PR set,
  template integrity (every bundled template: weeks count matches length,
  percents in sane range, exactly the declared deload weeks).
- **Screenshot catalog**: `catalog` entries for program card (enrolled),
  template gallery, template detail — the established `UITEST_CATALOG`
  debug-screen route.

### Non-goals for P1 (explicit)

- No schedule mutation (P2), no user-authored or shared templates (P3).
- No autoregulation, stall detection, or automatic deloads — ever, without a
  separate design round.
- No coupling to community campaigns' tables, triggers, or leaderboards.
- No kg/lb unit work beyond what target display already needs (5 lb rounding
  assumes lbs; unit-aware rounding is a follow-up noted for the plan).

---

## Phase P2 sketch — schedule integration (next design round)

"Plan my week" on the program card proposes N scheduled solo sessions
(existing scheduling infra + check-in flow) pre-filled from the week's
prescription, as a routine snapshot per session. User previews, adjusts
days, confirms. Program sessions coexist with group sessions — an
"interruption" is additive, never destructive to existing schedule rows.
Open questions deferred to that round: collision handling with group
sessions, editing a generated session, what "done" means for a partially
completed prescription.

## Phase P3 sketch — community programs

User-authored templates, published to Discover, starred (reuse
`routine_stars`' shape), possibly "run as a group" bridging back into the
community-campaign machinery. Requires templates-in-DB, moderation surface,
and versioning — all deliberately out of scope until P1 proves usage.
