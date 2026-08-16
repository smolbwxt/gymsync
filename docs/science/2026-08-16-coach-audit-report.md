# Coach Generator Audit — Grid × Trainer Swarm (2026-08-16)

**Method.** The REAL `ProgramGenerator.generate()` (never a
reimplementation) ran the full structural input grid — 162 programs
across focus × days × experience, no-barbell gyms, session caps,
cardio-heavy variants, fill-week, and seed rotation — against a frozen
production catalog, via CI. 30 independent Sonnet-max reviewers in a
science-first personal-trainer persona reviewed every program against
`generator-evidence.json`, returning what/why/severity plus an
`encodableRule` wherever the fix was deterministic. In parallel, 22
reviewers authored the 11-label catalog taxonomy for all 1,305
exercises (owner-approved; migration 20260816000002; 606 contentious
rationales in `catalog-label-rationales.json`).

**Verdict on the pre-audit generator.** 162/162 programs reviewed:
ratings 1★×6 · 2★×68 · 3★×62 · 4★×25 · 5★×1; 75 critical, 266
important, 51 minor issues; 382 encodable rules (highly convergent —
independent reviewers kept finding the same defects).

## Findings → shipped rules (all tested)

1. **Novice intensity (most-repeated CRITICAL).** New lifters were
   opened at 90% 1RM with no established max. → Experience-scaled
   intensity ceilings (new 72.5 / intermediate 87.5 / advanced 92.5).
2. **%-vs-reps contradiction (systemic).** 90% printed beside a 6-rep
   target our own reps-at-percent table says 90% cannot support. →
   Anchor = `percentFor(range top)`, under the ceiling.
3. **Axial stacking (CRITICAL).** Squat + deadlift both at the top
   anchor in one session. → Only one heavy-spinal-load (label) main
   keeps the session's top anchor; later ones drop ~10%.
4. **No weekly undulation.** The same lift at its top anchor every
   session. → Heavy/light wave: a lift keeps its top anchor ≤2×/week;
   further exposures drop ~10%.
5. **Conditioning goal failure.** `cardioDays=0` shipped ZERO zone
   work. → Every conditioning lifting day ends in a zone-4 interval
   finisher.
6. **Rep windows.** 15-rep deadlifts / 3-rep lateral raises were
   prescribable. → Label rep windows clamp the focus band per exercise.
7. **Unilateral derate.** Dumbbell fallbacks (split squats) inherited
   bilateral near-max anchors. → Unilateral (label) mains cap at 80%.
8. **Score-first selection.** Alphabetical rank and the equipment
   ladder decided picks. → `focus_scores` lead; complexity GATES by
   experience (soft — never a hole; complex+effective rises for
   advanced, the owner's law); lengthened-bias preferred for
   hypertrophy accessories; ladder demoted to tiebreak; unstable-
   surface work floored at complexity 4.
9. **Low-frequency volume floor.** 1–2-day weeks undershot the weekly
   set floor. → Mains +1 set with the anchor capped at 82.5 (density
   over ceiling), noted honestly.
10. **48h note.** Fired only at ≥3 full-body days (off-by-one) and
    promised arithmetically impossible spacing at high frequency. →
    Fires at ≥2; wording asks for the possible.
11. **Cardio periodization.** Flat zone work for 8 weeks while lifting
    waves and deloads. → Coaching note (progress every 2 weeks, halve
    on deload); full auto-periodization deferred.

## Deferred (tracked)

- Fatigue-cost-aware session-cap trimming (labels ready; consumer TBD).
- Joint-stress filters ("work around my knee") — trainer-arm feature.
- Sex-delta variants in the grid harness (unit tests cover the deltas;
  the corpus didn't exercise them — add sex to the grid).
- Cardio auto-periodization (minutes/intervals riding the week wave).
- Audit-driven per-exercise focus-score corrections (targeted label
  updates as field feedback accumulates).

**Artifacts.** Corpus + reviews + labels: session scratchpad
`audit/`; permanent grid harness: `GeneratorGridDumpTests.swift`
(GRIDJSON in every CI run). Swarm ops lesson: serialize swarms, waves
of 4, small batches, file-based outputs — bursts die on rate limits
and 64k output caps.
