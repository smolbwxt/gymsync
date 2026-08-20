-- Corpus label corrections (owner arc 2026-08; applied 2026-08-20).
--
-- The 1,305-exercise label taxonomy was authored by a swarm reasoning from
-- first principles. The educational-fitness deep read (782 per-exercise
-- judgments, 30 top-routed videos, tools/youtube-research/labeldiff.py)
-- diffed practitioner claims against what we ship, gated on agreement from
-- 2+ INDEPENDENT channels — RP alone is 36% of the corpus, so per-claim
-- counting would let one prolific educator masquerade as consensus.
--
-- 13 corrections qualified. 12 are lengthened_bias false -> true (the
-- swarm under-flagged the stretch-position lifts: deep knee flexion for
-- quads, stretched pecs/lats on presses and pulls); 1 adds elbow to the
-- decline bench's joint-stress list. 48 single-source disagreements were
-- reviewed and deliberately NOT applied.

UPDATE public.exercises SET lengthened_bias = true WHERE name IN (
  'Leg Extension',                        -- 4ch: FHP, HoH, RP, SBS
  'Barbell Squat',                        -- 3ch: Biolayne, FHP, RP
  'Dumbbell Bench Press',                 -- 2ch: RP, SBS
  'Barbell Hack Squat',                   -- 2ch: 3DMJ, HoH
  'Seated Calf Stretch',                  -- 2ch: FHP, HoH
  'Band Skull Crusher',                   -- 2ch: Nippard, RP
  'Bench Press',                          -- 2ch: RP, SBS
  'Barbell Row',                          -- 2ch: FHP, RP
  'Lat Pulldown',                         -- 2ch: Menno, SBS
  'Leg Press',                            -- 2ch: 3DMJ, RP
  'Dumbbell Lying Rear Lateral Raise',    -- 2ch: RP, SBS
  'Leg Curl'                              -- 2ch: 3DMJ, DDS
);

-- 2ch (Menno, SBS): close-to-torso pressing loads the elbow extensors
-- hard; the decline bench listed shoulder only.
UPDATE public.exercises
SET joint_stress = array_append(joint_stress, 'elbow')
WHERE name = 'Decline Barbell Bench Press'
  AND NOT ('elbow' = ANY(joint_stress));
