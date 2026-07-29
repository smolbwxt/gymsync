# Logging, Cardio & Group Runs — research + design direction

**Date:** 2026-07-29
**Method:** 12 parallel research angles (web + codebase) → 196 findings → 18
design-driving claims adversarially re-verified → 4 design lenses. 34 agents,
0 errors.

> **Verification result — read this first.** Of 18 claims checked:
> **1 confirmed, 15 partly, 2 refuted, 0 unverifiable.** Almost nothing in this
> category's received wisdom survives contact with primary sources intact. The
> details below are written *after* that filter.

---

## 0. What the verification pass killed

Do not build on these — they failed:

| Claim | Verdict |
|---|---|
| "Too many taps is the #1 reason lifters abandon a tracker; 2–3 taps is the accepted ceiling" | **Contradicted.** The JMIR 2024 scoping review ranks abandonment causes and tap-count isn't the leader. The "2–3 tap ceiling" traces to a single vendor blog with no methodology. Treat tap reduction as a sound heuristic, **not** a citable fact. |
| "Strong is a three-tap set" | **Refuted.** The source counted app-open + start-workout + log-set, and the same review calls Strong the *fastest* logger with pre-loaded weights. |
| "AMRAP only counts if reps feed progression — Boostcamp is the reference implementation" | **REFUTED.** Boostcamp's own program docs show a fixed, manually-entered TM increment. The claim was assembled from Boostcamp's own SEO page ranking Boostcamp #1. |
| "The set-row grammar does NOT transfer to cardio" | **REFUTED — and this one matters most for us.** Fitbod, Hevy, Strong, Runna and Apple's own custom-workout builder all use retrospective-confirm for cardio. The defensible narrow version: *don't force **unstructured** cardio into a set table.* |
| "Strong publicly concedes its Watch sync is broken" | **Partly** — that concession is from **2021**; a rebuilt watchOS app shipped by early 2026 (with Live Sync fixes still landing July 2026). Past tense, not a live confession. |

**Two methodological warnings that apply to all competitor research here:**
1. **Reddit is not crawlable** by these tools. Any "we analysed 200+ Reddit
   threads" source is unauditable in principle — treat as unverified.
2. **Search results are contaminated by vendor SEO.** Several "independent
   comparison" pages (Boostcamp's `/best/*`, `findyouredge.app`) rank their own
   product #1 without disclosure. Two claims here were built entirely from such
   pages before verification caught it.

**The one fully CONFIRMED claim:** Hevy's Apple Health sync gap never
backfills — workouts logged while sync was misconfigured are permanently
missing. Verified via Zendesk's public API against Hevy's own article text.

---

## 1. What actually makes logging fast (the survivors)

- **"One-tap logging" is prefill + a single confirm that also starts the rest
  timer.** Confirmed from four vendors' own documentation. The competitive
  difference is **how often the prefilled value is already correct** — not the
  confirm gesture. *This is the load-bearing insight of the whole report.*
- **Two prefill sources, both used:** last-session actuals *and* program
  prescription. Hevy's real model is subtler than "look up last session" — it
  persists a mutable routine object overwritten post-workout, with a user
  opt-out. That's the better model to copy.
- **PREVIOUS is a separate, coexisting element** from the prefill — visible
  next to the input, not replaced by it.
- **Set types live on the set-number cell** (tap → Normal/Warmup/Drop/Failure).
  Zero *persistent* chrome; it opens a transient menu. Survives the Watch port.
- **Rest timer: auto-start on completion, rendered inline.** But a manual start
  affordance and per-exercise disable are part of the pattern, not violations —
  Strong ships a manual timer, Fitbod requires a per-exercise toggle.
- **Swipe-to-delete is common but not universal**, and no mainstream app uses
  swipe as the *primary* logging gesture. Reserve swipe for destructive actions.

### Bugs this research found in OUR code (all verified, all now fixed)
1. `RoutineBuilderView` seeded `targetReps: "8-12"`; `Int("8-12")` is nil; Save
   was gated on that → **the app's own default routine opened with a dead Save
   button.**
2. `incrementInt` did `(Int(s) ?? 0) + 1` → tapping **+** on that prefill wiped
   it to `1`.
3. `prefillLogInputs()` set `logWeight = ""` → **group turns always opened with
   a blank weight.**
4. `WatchConnectivityBridge.handleLogSet` hardcodes `setIndex: 1` (documented
   as "not turn-tracked", but it collides every wrist-logged set at index 1 —
   must be fixed before the wrist becomes a real logging surface).

---

## 2. Cardio — the data model is the decision

**Organising principle:** a cardio effort is still a **row** (so it inherits the
offline queue, RLS, client-UUID idempotent PK, edit/delete for free) — but rows
need a **block** above them for structure, and a shared **effort currency**
beside them so cardio counts without corrupting `lifetime_volume_lifted`.

**Effort rows (M).** `set_logs += kind ∈ {weight_reps, reps_only, duration,
distance_duration}`, `duration_seconds`, `distance_meters`;
`exercises += measurement_kind`; `user_settings += distance_unit`. Canonical
**meters and seconds**, converted at exactly two edges — the same doctrine as
the pounds sweep. **Pace is never stored**, always derived. One steady run = one
row; 6×400m = six rows with set_index 1–6. `LogSetSheet` keeps the same shell and
swaps its stepper cells on `measurementKind`; RPE stays identical across all
kinds — *RPE is the field that makes lifting and cardio one language.*

**Blocks (L).** `Session → Block[] → Row[]`, with a real interval clock
persisted on every phase transition. Today the app's **only** timing primitive
is `@State restEndAt: Date?` — one deadline, one notification. Intervals, EMOM,
AMRAP and circuits aren't a UI gap, they're a **missing state machine**. Blocks
also map 1:1 onto `HKWorkoutActivity`, so hybrid sessions export losslessly.

**Two cardio screens, sequenced (S then L).** **Indoor first** — treadmill/bike/
rower — a stepper card, zero new entitlements, distance labelled "estimated",
optional Bluetooth FTMS (service `0x1826`, same plumbing as our chest strap).
**Outdoor GPS later** — needs background location, battery review, App Review
risk. Auto-pause must key on **CoreMotion jerk, not GPS speed** (Strava measured
GPS lag inflating a true 7:00/mi to a displayed 7:15–7:25).

**Effort Points (M).** Store both `effort_hr` (time-in-zone or Banister TRIMP)
and `effort_srpe` (minutes × RPE, Foster's protocol, r = 0.75–0.90 vs HR-TRIMP),
plus an `effort_source` label. Zones get **three-tier provenance** shown in the
UI: *estimated* (220−age) → *from your data* (observed 99th percentile) →
*measured* (LTHR field test). Never ship 220−age silently.

**Progression engine (M) — every rule earns its place:**
- ✅ **Completion-gated, never calendar-gated.** C25K's own data: 64.5% dropout,
  27.3% completion, dropouts naming week 5 — where running goes 5→8→20 min in
  seven days. Cap the longest continuous segment at **+50% week-over-week**.
- ✅ **One volume guardrail:** prescribed longest effort ≤ **1.10×** the trailing
  30-day longest. One SQL window function.
- ✅ **Prescribe by named relative effort**, not absolute pace — maps onto the
  RPE bar we already ship and sidesteps treadmill-vs-outdoor pace mismatch.
- ❌ **The 10% rule** — the GRONORUN RCT (532 novice runners) found *no* injury
  difference vs a 24% ramp. Marketing it is a falsifiable claim with a
  published null result behind it.
- ❌ **Any ACWR risk score or red badge.** The 2025 meta-analysis puts the
  0.8–1.3 "sweet spot" at a 95% CI of **14–94%** — uninformative.
- ❌ **"80/20 polarized" branding** — at 1–3 sessions/week the math is
  meaningless (2 easy + 1 hard *is* 67/33).
- 🏆 **Co-prescribed strength is the strongest available claim and it is
  uniquely ours:** Lauersen, BJSM 2018 — strength training roughly halves
  overuse injuries (pooled RR ≈ 0.34). Runna, NRC and Strava can *recommend*
  lifting; **only GymSync can verify it happened from logged sets.**

---

## 3. Group runs — yes, a different UI (and why)

**The structural answer:** group lifting is *turn-taking* (`advance_turn()`
walks `turn_order` one lifter at a time; `currentExerciseForSheet` hard-returns
`routineExercises.first`). A run is the **structural inverse** — everyone moving
simultaneously, continuously. Reskinning rotation would be the most expensive
wrong turn available.

**But ~80% of the group stack is modality-agnostic** — scheduling, check-in
states, `mark_no_shows`, the burpee ledger, streaks, LiveKit, chat, kudos,
recap, Pump Check all read neither reps nor weight. So: **one flag**
(`sessions.modality ∈ {lift, run}`) routes to a `GroupRunLiveView` sibling and
everything around the live screen is reused.

**The Spread Strip** replaces the spotlight card: every participant as a dot on
a **normalized axis — % of their own target**, not raw distance, so a 5:00/km
and an 8:00/km runner sit level. Rides an ephemeral broadcast channel
(`session:{id}:run`, 10s cadence) cloned from `HeartRateBroadcastService` —
nothing persisted per tick. *Indoor/same-place uses real distance instead,
because people can see each other and normalizing would read as a lie.*

**The Anchor + Elastic Fence — nobody can be rendered last.** An assignable,
rotating **Anchor** (parkrun's tail walker) whose finish defines completion.
A cohesion band measured **from the anchor, never from the front**. Drift ahead
→ a gentle regroup card. Drift **behind → no card at all, ever**; only the
anchor sees it and only the anchor can call a regroup. The drop rule punishes
**stopping, not slowness** — and a dropped runner stays on the strip greyed with
"last seen", never removed. Evidence: SEM study (n=343) found downward social
comparison significantly *reduces* social presence (β = −0.261) with no
motivational upside — a screen that says "you're beating Sam" actively harms
what we sell.

**Why not rubber-banding (Zwift's answer):** it works socially but corrupts
every downstream number — a 300W rider tethered to a 75W rider climbed Alpe du
Zwift *faster* than two free-riding 300W riders. Outdoors you can't fake
physics, so equalize in the **display/scoring** layer and leave each runner's
real pace truthful in their own record.

**Earbud-first (L).** PTT is the wrong gesture running (needs a hand) → VOX with
auto-mute above a hard-effort HR threshold; splits/regroups/kudos as TTS + a
documented haptic vocabulary. **Honest cost:** `AudioSessionManager` is
`.ambient` and `project.yml` declares **no** `UIBackgroundModes` — audible cues
with a locked phone need `.playback` + background audio, which changes soundboard
behaviour in lifting sessions and adds App Review surface. **Ship v1 with
haptic-only boundaries.**

**Ship indoor/same-place first (S).** Adjacent treadmills, no GPS, no new
entitlements — and it composes with the live group session we already have.
Unlocks a "**Wall**" view (one phone propped on a rack showing the strip at
3-metre legibility) that is impossible for Strava.

---

## 4. Where the lightning is

The differentiation lens was blunt: **GymSync's one durable asset is not fast
logging — it's the explicit, scheduled, friends-only live group session.** No
competitor has an analogue. Strava's "group activity" is a post-hoc GPS
heuristic (nearby >50% of the time); Racefully (closest live group-run product)
has *no voice* and hasn't shipped since 2026-02-28; Zwift is trainer-locked;
Peloton has a leaderboard, not a session.

**Explicitly rejected as parity or trivially copyable:** rest-timer Live
Activity (Hevy ships it), standalone Watch logging (4 apps ship it), GPS
recording with maps/routes (Strava owns it), time-in-zone charts (free from
HealthKit in iOS 27), a cardio leaderboard (the gamification literature names
leaderboards the most harmful element), voice logging, auto rep detection
(benchmarks *worse* than manual: 75–83%, blind to load), and "one app for
lifting + cardio" (Strava is converging from the other side).

**The three that compound:**
1. **The Anchor Run** — group cardio as effort-spread, reusing the whole session
   envelope. Co-located first.
2. **Crew Load** — one effort currency across both modalities *plus* the group's
   shared calendar. Whoop's Strain is provably wrong for lifting (HR-derived);
   we have structured lifting ground truth *because* logging is our first
   pillar. And nobody else holds a shared calendar of scheduled group sessions
   with a social surface to renegotiate them.
3. **The Rotation Clock** — the phone becomes the shared social surface, the
   wrist/Lock Screen becomes the personal log. A Live Activity carrying *whose
   turn it is* is uncopyable, because no competitor has turn-taking.

**One cross-cutting blocker, found in code:** when `logSet` throws `.network` in
a group session, the client skips `advanceTurn` and **replay never retries it** —
one dead signal freezes everyone's rotation. Every proposal above makes that
more likely (outdoors, phone in pocket). **Fix graceful rotation degradation
first**, or the differentiated feature is the fragile one.

---

## Sequencing recommendation

1. **Now (done):** the four logging defects above.
2. **Next (S/M):** graceful rotation degradation; prefill-as-product (structured
   targets + PREVIOUS column + zero-touch-confirm metric); indoor cardio rows.
3. **Then (M/L):** blocks + interval clock; Effort Points; the Anchor Run
   co-located.
4. **Later (L/XL):** outdoor GPS; earbud audio; Live Activity rotation card.
