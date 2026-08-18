# Coach as a Longitudinal Coach — findings + build path

**Owner directive 2026-08-17:** "The coach should do more than coach just 1
week. Coach should build custom programs to your goals, tune it along the
way, schedule your sessions for you, have the entire history of your work
together inform the future."

**Owner's read of the weakness (correct):** "Set and programming progression
is the primary area that we are weak."

This is the handoff record. Everything below was verified against the code,
not assumed.

---

## 1. What we actually ship (verified)

### Within-session: works
`SetProgression.nextWeight` prefills the NEXT SET from the set just
completed. RPE <= 7 steps up ~2.5% (upper) / ~5% (lower), floored to a
loadable increment in the lifter's unit; RPE 8+, no RPE, or a failed set
holds. Deliberately conservative, and good as far as it goes. It has no
memory beyond the current exercise.

### Session-to-session, Coach programs: ABSENT
`ProgramGenerator` computes an 8-week wave — `volumeMultiplier`,
`intensityMultiplier`, deload at the 3/4 mark, strength taper. Those values
appear in exactly two places: where the weeks array is built, and inside
`weekSummaries` (a DISPLAY function). `CoachWizardView.create()` iterates
`program.days` and writes static routines.

**An 8-week Coach program is one week, repeated eight times.** The wave is
metadata on a summary card.

### Session-to-session, bundled programs: works, but walled off
`WorkingWeight.suggest` rung 1 applies `template.weeks[week-1]
.percentOfBaseline x frozen baseline` and reaches the session's suggested
weight. Real progression — but it fires only when ALL of:
- an active `program_enrollments` row exists, AND
- `enrollment.template` resolves from the THREE hardcoded entries in
  `ProgramTemplate.all`, AND
- the exercise is in `focus.exerciseIDs`, AND
- a baseline was frozen at enrollment.

`ProgramRepository.enroll` has exactly ONE caller: the bundled-template
flow in `ProgramViews`. **Coach output never enrolls.** And because
`enrollment.template` resolves against the code list, enrolling someone in
a Coach block today would return nil and silently disable rung 1.

### Dead constants (encoded science, no machinery)
Zero consumers outside their own declaration:
- `GeneratorScience.noviceStallSessions` (2)
- `GeneratorScience.noviceStallDeloadPercent` (10.0)
- `GeneratorScience.advancedAccumulationRIR` / `advancedIntensificationRIR`
- `CatalogExercise.secondaryMuscles` (the fractional-volume gap)

---

## 2. The pattern worth naming

**We keep encoding the science and skipping the machinery that spends it.**

| Science encoded | Machinery missing |
|---|---|
| weekly set bands (12-20) | nothing counts sets per muscle |
| wave multipliers, deload, taper | nothing applies them to prescriptions |
| novice stall thresholds | nothing detects a stall |
| `secondaryMuscles` | nothing counts fractional volume |

Each was written as a VALUE where it needed to be a LOOP. All four are
invisible to output review — a single generated week looks perfectly
reasonable in isolation. Only diffing stated intent against the code finds
them. **Any future audit should check "is this constant read anywhere?" as
a first-class test.**

---

## 3. The target architecture

Coach today is a *generator*. The directive is a *coach*: something with
memory, that adjusts, and that owns the calendar.

### 3a. Bridge the two program systems (unblocks everything)
- `enrollment.template` must resolve DB-backed `program_templates` rows
  (which Coach already writes via the data bridge, 20260814000009) as well
  as the hardcoded three. Today it is code-only.
- Coach's CREATE should enroll the lifter in the block it just generated,
  not just write loose routines.
- Once bridged, `WorkingWeight` rung 1 starts applying Coach's own wave
  automatically — the machinery already exists and is tested.

### 3b. Apply the wave to prescriptions, not just summaries
Generate per-week prescriptions (sets x reps x %1RM per week), or resolve
week-at-read-time from the enrollment's `currentWeek`. Read-time resolution
is preferable: one routine set, week applied on the fly, so a shifted start
date or a repeated week stays correct without rewriting rows.

### 3c. Real progression models (the corpus research feeds this)
- **Double progression** — the schema is ready (`targetRepsLow/High` ship
  today); nothing advances reps toward the top or converts a topped-out
  range into added load. This is the single highest-value missing rule.
- **Stall detection** — consume `noviceStallSessions` /
  `noviceStallDeloadPercent`; a stall must be detectable from `set_logs`
  (missed rep targets N sessions running on the same lift).
- **Volume progression** — add-a-set-per-week within the weekly band, once
  the per-muscle volume accounting layer exists (see the corpus audit).
- **Autoregulation across sessions** — RPE/RIR currently affects only the
  next set; it should inform next WEEK's prescription.

### 3d. Scheduling
Coach should place sessions on the calendar (the trainer arm already books
for clients via `SessionRepository.scheduleForClient`; the same machinery
serves self-scheduling), respecting the recovery ceiling and 48h
same-muscle spacing the generator already reasons about.

### 3e. History informs the future
Block N's outcomes should seed block N+1: achieved e1RMs become the next
baseline (the "re-freeze at block start" rule already pinned by the owner),
lifts that stalled get different treatment, exercises the lifter abandoned
get deprioritized, adherence shapes realistic day counts.

---

## 4. Research feeding this

The educational-fitness corpus (3,228 active transcripts,
`tools/youtube-research/`) has a dedicated **progression pass** — 179 routed
candidates, brief at `scratchpad/yt/brief-progression.md` — extracting
trigger/action rules with structured quantities (`{amount, unit}`),
`applies_to` experience level, and strict `basis` grading.

Scale it to the full 179 and enrich the brief with our CURRENT behavior so
agents diff against reality ("we only prefill the next set and never advance
week to week") rather than describing progression in the abstract. That is
the trick that made the trainer audit sharp.

Consensus must be counted PER CHANNEL — RP alone is 36% of the corpus.

---

## 5. Sequencing

1. Bridge enrollment to DB templates + enroll on Coach CREATE (3a)
2. Apply wave at read-time (3b)
3. Double progression + stall detection, corpus-informed (3c)
4. Per-muscle volume accounting (prerequisite for volume progression)
5. Scheduling (3d)
6. Block-to-block carryover (3e)

Steps 1-2 are mostly wiring and unlock existing tested machinery. Step 3 is
where the research earns its keep.
