# Lifting Quality: Units, Bar Loader, Warm-up Ramp

**Date:** 2026-07-26
**Origin:** User request after a gap review: "Let's have a toggle for kg and lbs. I like
your warmup and inventory suggestions, let's work it." Plus exercise media via YouTube
(separate phase, see the end).

---

## Phase U — Units (kg / lbs)

### The one decision that matters: store canonical, convert at the edges

Every weight in the database stays in **pounds**. The unit setting is a *display and
entry* concern only. No migration of `set_logs.weight`, `personal_records`,
`body_weight_logs`, or program baselines — and therefore no risk of a half-converted
dataset, which is the failure mode that makes unit features dangerous.

Conversion happens in exactly two places: formatting a stored value for display, and
parsing a typed value on entry. `1 kg = 2.2046226218 lb`.

### Storage

`user_settings.unit_system text NOT NULL DEFAULT 'lbs' CHECK (unit_system IN ('lbs','kg'))`

`UserSettings.unitSystem` is added **last with a default** — the memberwise-init trap
that file documents twice already (`shareHeartRate`, then `accent`). It must also be
merged in `ThemeStore.mergeExternalSettingsWrite`, or a concurrent write from another
device silently reverts it.

### Rounding

Displayed weights round to the increment that unit can actually load: **2.5 lb** or
**1.25 kg** (the smallest common plate pair, doubled). A converted 225 lb shows as
102.5 kg, not 102.0583. Body weight rounds to 0.1 in both units.

---

## Phase B — Bar loader + inventory

### What exists

`PlateMath` already computes a per-side stack, rounds down to what's loadable, and
treats the empty bar as the floor. It is surfaced as **text chips inside a collapsed
disclosure in the log-set sheet**, ungated by equipment.

### What changes

1. **A visual loader.** A drawn bar with proportional plates per side, plus the numeric
   stack beneath it. Rendered where it's useful: on the **live workout screen** under the
   exercise header, not buried in the post-set sheet.
2. **Gated to barbell lifts.** `exercise.equipment == "barbell"`. A plate stack on a
   dumbbell curl is noise, and its presence there is a bug today.
3. **Configurable bar.** `user_settings.bar_weight_lbs numeric DEFAULT 45` — covers the
   35 lb women's bar, the 15 kg (33 lb) trainer, and a 55 lb safety-squat bar. Presented
   in the user's unit.
4. **Configurable plate inventory.** `user_settings.plate_inventory jsonb` — the
   denominations this gym actually has, defaulting to the standard set per unit. A loader
   that confidently draws 2.5s a gym doesn't own is worse than no loader.

Unreachable targets already degrade correctly (nearest loadable at-or-below, with the
delta exposed); the visual must show that honestly rather than drawing a perfect stack.

---

## Phase W — Warm-up ramp

The biggest hole in the lifting flow: the app prescribes 3×5 @ 225 and expects the lifter
to walk up and do it.

`WarmupMath.ramp(workingWeight:barWeight:unit:)` produces a small, conventional ladder —
derived percentages, rounded to loadable increments, always starting at the empty bar:

| Step | Load | Reps |
|---|---|---|
| 1 | empty bar | 5 |
| 2 | ~55% | 5 |
| 3 | ~70% | 3 |
| 4 | ~85% | 2 |
| 5 | ~95% | 1 |

Rules that keep it honest:
- Steps at or above the working weight are dropped (a light working set needs fewer
  rungs — 95 lb doesn't get a five-step ramp).
- Duplicate loads after rounding collapse to one.
- Every step carries its own plate stack, so the ramp and the loader are the same
  feature seen twice.
- Warm-ups are **not logged as sets**. They don't count toward volume, PRs, or program
  progress — logging them would corrupt every downstream number. They're a checklist.

Surfaced on the live workout screen for barbell exercises, collapsed once the first
working set is logged.

---

## Phase M — Exercise media (YouTube)

Separate, smaller, and content-gated.

- `exercises.demo_youtube_id text` — the **video ID**, not a URL.
- Rendered through a `youtube-nocookie.com` iframe in a `WKWebView` on the exercise
  **detail** screen. The official embedded player only: extracting the stream into
  `AVPlayer` violates YouTube's Terms and is a known App Store removal cause.
- Explicit unavailable state — deleted, private, region-blocked and embedding-disabled
  videos all fail silently otherwise, and at a few hundred exercises some always will.
- Not shown inline during a live set: ads are unskippable by terms, and gym signal is
  unreliable. Offline-proof in-session loops are a later, separate idea.
- Populating IDs is a **content task**; the schema makes each one a one-line change.

---

## Testing

- pgTAP: unit_system CHECK rejects a bad value; bar weight and inventory are owner-only.
- `UnitsTests`: round-trip lbs→kg→lbs within tolerance; display rounding to 2.5 lb /
  1.25 kg; parse accepts both comma and period decimals.
- `PlateMathTests` (extend): kg denominations; a custom inventory missing 2.5s rounds
  down correctly; a target below bar weight returns the bar.
- `WarmupMathTests`: ladder for 225 lb and 100 kg; steps above working weight dropped;
  duplicates collapsed; light working weight yields a short ramp; every step loadable.
- Catalog: `bar-loader` and `warmup-ramp` captures.

## Non-goals

Converting stored data; per-exercise bar overrides; micro-plates below 1.25 kg / 2.5 lb;
logging warm-ups as real sets; in-session video.
