# Sport-prep parameters — football / baseball / wrestling

Synthesis of the 2026-08-21 sport deep-read: 218 findings from 36
transcripts (12 per sport), read against `tools/youtube-research/
brief-sport.md` by a nine-agent swarm. Channel authority per sport:
Garage Strength + Overtime Athletes (football), Driveline + Tread
Athletics (baseball), Daru Strong + Garage Strength (wrestling).
Raw findings: `tools/youtube-research/passes/sport-*/f-*.json`.
A few football claims leaked into baseball batches via a shared-channel
video; they are counted under football here.

The point of this document: parameters the GENERATOR can consume for
the `sport_prep` goal and the `inSeason` flag — not general sports
science. Each sport section ends with its generator derivations.

---

## Football

**Season structure.** The off-season is short (~5-6 months) and splits
in two: an early higher-volume strength/hypertrophy block (early work
at 7-17 reps; squat twice weekly — one 5x7 volume day, one speed day;
Olympic-lift TECHNIQUE emphasized in weeks 4-12 at light load before
adding weight), then a pre-camp block at lower volume and higher
intensity where plyometrics and speed peak. After the season: 2-3
weeks easy before ramping again.

**In-season.** 2-3 short sessions (40-45 min, 3-4 exercises, big
transferable lifts), flexed by opponent difficulty — more/harder
against weak opponents, lighter before tough ones (5x5 weeks vs 5x2
weeks). Cluster sets (near-max singles/doubles, ~30s intra-rest) over
straight sets. Sprint-mechanics work INVERTS the usual pattern: 2-3x
weekly in-season, ~1x off-season. Light pump work rides along for
engagement + joint prophylaxis.

**Selection.** Absolute strength is the universal foundation (back +
front squat, bench variants, cleans); the single-leg squat is the one
exercise named top-tier for EVERY position (hip mobility + unilateral
trunk control for cutting/blocking; an in-house 315 lb single-leg
squat ↔ 30" vertical correlation is their justification). Explosive
work = Olympic variations nearly daily off-season + contrast training
(heavy squat paired with jumps, 2-3 min between) + plyo ≥2x weekly.
Benchmarks scale by position (linemen clean 1.0-1.25x BW; skill
positions lighter but faster; HS explosiveness bar ≈ 8 ft broad /
26-28" vertical; retest every 12-18 weeks).

**Generator derivations (football):**
- Off-season: explosive budget UP (2/day is defensible), squat
  patterns + Olympic-flavored pulls preferred, hypertrophy rep
  windows early block, intensity ramp late block.
- In-season: session cap ~45 min, 3-4 exercises, mains only, low-rep
  cluster-style prescriptions, NO volume accessories; deload-by-
  schedule is normal, not a warning sign.
- Unilateral quad pattern (split squat / single-leg squat) should
  rank up for sport_prep football regardless of focus.
- Conditioning: none added beyond sprint work — practices carry it.

## Baseball

**The priority inversion.** Baseball S&C is arm-first: shoulder/elbow
health outranks everything (a 5,700-athlete survey weighting cited as
44% shoulder/elbow, 31% hips/groin, 25% trunk). Arm care is its own
subsystem, NOT generic lifting: posterior-cuff external rotation
progressing to ~10% BW x 10 reps, external/internal rotation strength
ratio held near 0.85-1.05, scapular stabilizers (serratus, low trap)
trained in throwing-specific positions, forearm/FCU isometrics for
UCL protection. Velocity work never runs without parallel arm
strength (torque rises with every mph).

**Selection.** In the weight room: GENERAL athleticism via compounds
(squat, deadlift, bench) + sprint/plyo — explicitly NO sport-mimicry
lifts. Slow-eccentric DB external rotation is the one accessory
called out as near-universal (players are weakest there). Single-leg
progressions matter (goblet → barbell). Catchers get less deep-squat
volume (the position already loads it); heavy benching (275-300 lb)
is defended as harmless to throwing.

**Season structure.** Off-season throwing runs on-ramp → ~6-week
velocity phase → competition phase. In-season lifting is maintenance
at MINIMUM effective dose and must not produce soreness; speed/power
detrain fastest so the little work done preserves THOSE. Starters
schedule proactively around the rotation (heaviest lift right after a
start; brief power touch 2-3 days before the next); relievers and
position players schedule reactively. Volume reduction scales with
training age (veterans cut most).

**Power.** Acceleration-dominant (90 ft between bases): drive-phase
work, cleans 2-3x weekly, lateral/rotational power (banded side
jumps, cossack progressions, rotational trunk work). Velocity itself
lives at the fast end of the force-velocity curve — past a moderate
strength threshold, heavy lifting gives diminishing velocity returns.

**Generator derivations (baseball):**
- sport_prep baseball: shoulder-caution posture BY DEFAULT — no
  behind-neck pressing, prefer neutral-grip/landmine pressing angles;
  external-rotation accessory slotted like core (a standing dose).
- In-season: lowest-volume maintenance of the three sports; no
  soreness = accessory sets minimal, mains submaximal, power touch
  preserved.
- Rotational/lateral power patterns rank up; pure top-speed
  conditioning ranks down (game supplies it).
- Catchers (position data unavailable to the generator today): note
  only.

## Wrestling

**The four pillars.** Explosiveness/reaction, strength (RELATIVE for
light classes, ABSOLUTE for heavy — ~500 lb squat named as the
heavyweight bar), GRIP (its own pillar: fat-grip pulls 5-6x12-17,
false-grip weighted pull-ups, sled curls for underhooks; pull-up
benchmarks 25-30 reps under ~185, 10-15 for heavyweights), and
strength-endurance (high-rep supersets at 30s rest to reach
minutes-4-6 match fatigue).

**Selection.** Unilateral-first is the law — stance, penetration
step, and shot finishes are one-sided (split squats front-racked,
goblet lunges weaker-leg-first, pistols, unilateral jumps and stair
bounds). Sled work is the signature modality (low pushes for level
change, heavy pulls for back-leg drive, harness crawls light-for-
speed / heavy-for-fatigue-rehearsal). Lats/back and grip outrank
pressing; a condensed conjugate shape (max-effort + dynamic-effort
paired in one session) fits recovery better than a 4-day split.
Optional third day: joint bulletproofing (neck, shoulders, low back,
knees) at high reps.

**Season structure.** In-season KEEPS the big lifts in 40-45 min
sessions rather than cutting them; the field's named mistake is
tapering too early and peaking before the postseason. Lifting
frequency scales inversely with mat time (hobbyists 3-4, elite
in-camp 2). Implement loads lighten in-season (25 lb med-ball →
12-15 lb) to shift the same drills toward speed.

**Conditioning splits by weight class.** Lightweights: interval work
in scramble-length bouts (15-30s). Heavyweights: cyclical low-impact
(bike/rower/sled/swim) — running and hill sprints are discouraged at
240+ lb bodyweights (impact injury risk).

**Weight management.** Depleting cuts are rejected; keep protein
(~1g/lb) and creatine through the season.

**Generator derivations (wrestling):**
- Unilateral variants rank ABOVE bilateral for sport_prep wrestling
  (the inverse of the default ladder).
- Grip/lat emphasis: pulling accessories rank up; a grip-flavored
  accessory is a standing dose like baseball's cuff work.
- In-season: sessions stay 40-45 min WITH mains (unlike baseball's
  minimum dose); intensity holds, volume trims; never zero out
  explosive work.
- Conditioning style keys off bodyweight when known (body context
  fields, 2026-08-21): heavier athletes → low-impact cyclical, which
  composes with the existing impactCaution demotion.

---

## Cross-sport consensus (the generator's shared sport_prep spine)

1. **In-season = short, intense, low-volume, mains-first.** All three
   sports converge on 40-45 min, 2-3x weekly, big lifts kept, volume
   (not intensity) as the release valve, flexed by schedule/opponent.
2. **Explosive work is a first-class citizen off-season** and the
   LAST thing zeroed in-season (it detrains fastest).
3. **The sport supplies conditioning.** Added conditioning is the
   exception (wrestling by weight class), not the rule.
4. **Sport-specific prophylaxis is a standing dose**: arm care
   (baseball), joint bulletproofing/neck (wrestling), position-
   specific pump work (football).
5. **No weight-room mimicry** (baseball says it outright; football
   and wrestling train positions via loading patterns, not sport
   charades) — the generator should bias PATTERNS, never invent
   sporty exercises.

## Follow-up code pass (not yet built)

Wire per-sport parameter sets into `GeneratorScience`/`ProgramGenerator`
keyed off a `sportPrepSport` profile field: selection tilts (unilateral
rank-up for wrestling, rotational/lateral for baseball), standing
prophylaxis slots (cuff / grip), in-season prescription caps per sport,
and conditioning style by weight class riding the body-context fields.
Each knob lands with a no-dead-knobs test, same as every profile field.
