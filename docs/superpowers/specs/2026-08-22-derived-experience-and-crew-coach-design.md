# Design: derived experience, mid-session builder, @Coach in crews, hub brands

Owner rulings 2026-08-22 ("Sounds great. Let it ride"). Four features,
one spec — each section is self-contained.

## 1. Derived experience (replaces the EXPERIENCE dial)

Experience level is NEVER shown or picked. Five comfort probes in the
GOALS door, spanning the complexity ladder with recognizable lifts:

| Probe | Complexity |
|---|---|
| Goblet squat | 1 |
| Barbell back squat, heavy | 3 |
| Conventional deadlift | 3 |
| Weighted pull-up | 4 |
| Power clean | 5 |

Chips: Comfortable / Not yet. Derivation: the cap is the highest
complexity with a COHERENT PREFIX (comfortable at 4 but not 3 reads
as 3 — bravado doesn't skip rungs). The cap feeds the selection gate
DIRECTLY (finer than three buckets); a register tier derives from it
(cap 1–2 novice, 3 intermediate, 4–5 advanced) for the debrief voice,
rep floors, and calibration anchors. Graduation proposals and drift
probes move the cap over time. Storage: `comfortAnswers` +
`derivedComplexityCap` on the profile payload; legacy profiles keep
their stored trainingAge until they answer.

## 2. Mid-session routine editing (solo v1)

Full builder, session-local: reorder, add, remove, sets/reps — an
overlay that never touches the stored routine mid-flight. At workout
end, a three-way: Discard / Update this routine / Save as new routine.
Groups are OUT of v1: a live edit to a shared routine collides with
the hot-swap unanimity rule; group editing waits for its own consensus
design.

## 3. @Coach in crew chats

- Trigger: a message starting `@Coach` in a crew chat.
- Data boundary: Coach reads the ASKER's own training data (made
  public by the act of asking — consent by venue) plus crew-shared
  data (leaderboards, streaks, session history any member already
  sees). Never another member's personal logbook.
- Gate: ONE Pro member lights @Coach for the whole crew — the only
  non-Pro venue, deliberately (social upsell).
- Runtime: the asker's device runs the on-device model; the reply
  posts as a chat message (kind `coach_reply`, inserted by the asker,
  rendered as Coach). Devices without Apple Intelligence degrade to
  the computed report-card sentences — honest, never silent.

## 4. Hub equipment brands

- The Venue hub is the source of truth for what a gym has.
- UI: brand dropdown; each brand's cataloged machines individually
  tickable; unchecking the brand removes them all.
- Unmanaged hubs: any member who claims the gym contributes to the
  collective picture.
- Prerequisite: a catalog brand-labeling pass (brand-named lines get
  `brand`; generic machines stay brand-less and untouched by brand
  toggles). Selection filters by the athlete's home hub inventory.

## 5. Deep-page preloading

Spike only: instrument first, design after numbers exist.
