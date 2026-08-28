# Prescription audit — corpus alignment for release (2026-08-28)

Owner directive: "make sure hypertrophy actually means hypertrophy in the
generator. While you're at it, an audit to make sure that what we are
prescribing aligns with the corpus and is polished for release."

Method: two independent inventories — every prescription constant/rule in
the shipping code (file:line receipts) vs. an evidence pack from
`generator-evidence.json`, `volume-landmarks.md`,
`2026-08-26-overnight-decisions.md`, the 162-program trainer audit
report, and 10 read-only `corpus_findings` queries — then diffed by hand.
No performance numbers are claimed anywhere in this audit; every verdict
cites its two sides.

## Verdicts — the core hypertrophy prescription is ALIGNED

| We prescribe | Corpus says | Verdict |
|---|---|---|
| Weekly sets 12–20 (`GS band .hypertrophy`) | The "moderate" 12–20 bin significantly beat <12 for every muscle; >20 marginal (FHP/HoH 2022 meta, strong) | ✅ exactly the evidence bin |
| Main reps 6–12, accessories 8–20 | 30–80% 1RM / ~5–35 reps equivalent near failure (strong); primaries lower than accessories (moderate) | ✅ |
| Main rest 120s, accessory 90s | Mains 2–4 min, accessories ~1.5 min (strength-accessories.md); rest is a volume moderator, no strong standalone number | ✅ |
| %1RM anchors 60→16 … 90→4, anchored at range top | Brzycki/Epley midpoint table (moderate); range-top anchoring was the trainer audit's own fix | ✅ |
| ≥2×/muscle/week split law | 2+ beats 1 volume-equated; ~nothing from 3+ (strong) | ✅ |
| Experience ceilings 67.5/87.5/92.5 | Trainer-audit shipped fix (novices at 90% was the top critical) | ✅ |
| Deload wk ¾, vol ×0.5, intensity ×0.95 | Evidence band: vol −40–60%, intensity 0–10% cut | ✅ (comment lied — fixed below) |
| Titration 12–25/muscle, no per-session cap; 25-set/day session cap | Overnight decision (per-session caps discredited; <12 weekly is the only proven harm) + owner's 25/day policy | ✅ by decision |

## What was NOT aligned — fixed this round

1. **Focus was copy, not volume** (the owner's finding). `focusMuscles`
   was one selection sort key; "I'll give them the volume" ran no volume.
   Now: focus muscles are floored at the band top in
   `balanceWeeklyVolume.bounds`, every other muscle holds the band floor
   — the corpus specialization spec (+20–40% focus, others cut/held;
   never below the <12 harm line). Cap: three areas, enforced in the UI
   (the old `prefix(2)` silently dropped a third pick *alphabetically*).
   Precedence: band → focus tilt → titration target → athlete cap/floor.
2. **Weight-loss cardio did not exist.** Owner design 2026-08-13 (LISS
   buy-in/buy-out) was never built — a WL block with cardioDays=0
   shipped zero cardio. Now: every WL lifting day buys out in zone-2
   (30 min new / 15 min otherwise), with an honest note.
3. **`EffortAppetite.toFailure` did nothing visible.** RIR is computed
   and dies at the persistence boundary (P5.1 CONFIRMED: `rirLow/High`
   have exactly 3 references — two declarations, one assignment;
   `RoutineExercise` has no column). Now `.toFailure` sets
   `targetFailure` on plain accessories (the flag the live session
   already renders); mains never. Full RIR persistence = v0.x (needs a
   migration + session UI).
4. **Beginner band 6–10 → 8–12.** volume-landmarks pins novice 9–12,
   ~10 = beginner MEV; the old midpoint (8) sat on the floor of
   effectiveness. Also: titration targets are now clamped to the band
   ceiling so the search's own 12-floor can't drag a novice past their
   band.
5. **Female rep-top bonus escaped the exercise rep-window clamp** (could
   exceed labeled repMax by 1). Re-clamped after the bonus.
6. **`reroll` dropped `bandOverride`** — a power_rfd athlete rerolled
   into a strength-band prescription. Fixed.
7. **Coverage dose silently abandoned orphans past the third** — now
   named in the "tight week" note.
8. Truth-in-comments: deload comment said "intensity held" while shipping
   0.95; `maxConsecutiveHardDays` renamed `maxHardDaysPerWeek` (no
   day-of-week binding exists — "consecutive" was unrepresentable); the
   48h note now interpolates `sameMuscleSpacingHours`; the 25-set day cap
   is a named constant (`GS.dayCapSets`) instead of a bare literal one
   keystroke from VolumeTitration's unrelated weekly 25; the dead
   `advancedAccumulationRIR`/`advancedIntensificationRIR` constants
   (zero readers) are deleted.

## Known gaps, deliberately deferred (v0.x)

- **RIR persistence + mesocycle RIR trajectory** (corpus: RIR 3–4 →
  0–1 across the block, never rising). Needs a routine_exercises
  migration and session rendering. Until then `.reserved` vs `.standard`
  differ only in dead numbers — the appetite's honest surface today is
  the failure flag.
- **Cardio auto-periodization** (minutes/intervals riding the week
  wave) — note-only today, unchanged.
- **Specialization duration**: corpus says focus blocks are temporary
  (~4–12 weeks then cut back). Our focus tilt runs the block's length —
  fine at 8 weeks, worth a rule when blocks stretch.
- **Sport-prep parameter sets, fatigue-cost-aware trimming,
  audit-driven score corrections** — carried from the 2026-08-16 deferred
  list, unchanged.
- **"12 unincorporated corpus lessons" (P6.3): the list does not exist
  on disk.** It died with the audit session's scratchpad. The nearest
  on-disk proxies are the deferred list above and the "not yet built"
  sections of volume-landmarks / sport-prep-parameters. P6.3 should be
  re-pointed at those rather than at a phantom list.

## Provenance

Code inventory and evidence pack were produced by two independent
read-only agents 2026-08-28 and diffed by hand; receipts in the session
transcript. Shipped state: this commit, on `ui/visual-language-redesign`.
