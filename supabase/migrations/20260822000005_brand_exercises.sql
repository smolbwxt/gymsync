-- 20260822000005_brand_exercises.sql
--
-- The 9 brand-signature machines the strategist judged genuinely NEW
-- (everything else mapped onto existing rows). Full pipeline per row:
-- corpus-grounded label vectors, WebSearch-verified YouTube demo,
-- lifter-facing description, brand stamp, brand_machines link.
ALTER TABLE public.exercises ADD COLUMN IF NOT EXISTS description text;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Arc Trainer', 'arc-trainer', 'cardio',
   'quads', ARRAY['glutes','hamstrings','calves']::text[], 'machine',
   'Cybex', '{"strength": 0, "hypertrophy": 1, "weight_loss": 8, "conditioning": 9}'::jsonb, 1, 2,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','hip']::text[], false, 'CSZ3zMOqitM',
   'A Cybex cardio machine that moves your feet through a natural, non-linear arc instead of a fixed elliptical or stepping path. Adjustable stride depth and resistance let you dial in quad- and glute-dominant leg drive with far less joint pounding than a treadmill. Cue: sit back slightly and drive through the whole foot, not just the toes.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Adaptive Motion Trainer (AMT)', 'adaptive-motion-trainer-amt', 'cardio',
   'quads', ARRAY['glutes','hamstrings','calves']::text[], 'machine',
   'Precor', '{"strength": 0, "hypertrophy": 1, "weight_loss": 8, "conditioning": 9}'::jsonb, 2, 2,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','hip','ankle']::text[], false, '6FUFUXh8OKA',
   'Precor''s AMT uses an open, unfixed foot path instead of a locked pedal track, so it can blend elliptical striding, stair climbing, and light running motion in one session. That open stride demands a bit more coordination than a standard elliptical but stays low-impact on the knees and hips. Cue: let your feet find their own path rather than fighting the machine''s flow.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Krankcycle (Arm Ergometer)', 'krankcycle-arm-ergometer', 'cardio',
   'shoulders', ARRAY['triceps','biceps','core']::text[], 'machine',
   'Matrix Fitness', '{"strength": 1, "hypertrophy": 1, "weight_loss": 7, "conditioning": 9}'::jsonb, 2, 2,
   0, NULL, NULL,
   false, false,
   'none', false,
   ARRAY['shoulder','elbow']::text[], false, 'mBpoaeNhO44',
   'A seated arm-crank ergometer that delivers real cardio conditioning through the shoulders and arms instead of the legs, making it a go-to for lower-body injury rehab, upper-body finishers, or sprint intervals. Resistance and crank direction (forward or reverse) can be adjusted to shift emphasis between the push and pull phase. Cue: drive the crank through the full circle rather than just the push, so both shoulders share the work evenly.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Kinesis Cable Station', 'kinesis-cable-station', 'compound',
   'core', ARRAY['shoulders','back','chest']::text[], 'cable',
   'Technogym', '{"strength": 3, "hypertrophy": 4, "weight_loss": 5, "conditioning": 6}'::jsonb, 3, 3,
   1, 8, 15,
   false, true,
   'none', false,
   ARRAY['shoulder','elbow','lower_back']::text[], false, 'T93pnlk8KR8',
   'Technogym''s Kinesis station pairs two independently loaded, multi-directional pulley arms, so each side can press, pull, or rotate through its own natural path instead of a single fixed track. It''s built for functional, core-integrated work such as chops, lifts, presses, and rotational patterns rather than straight-line isolation moves. Cue: initiate each rep from the core and let the arms follow, not the other way around.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('SkiErg', 'skierg', 'cardio',
   'lats', ARRAY['triceps','core','shoulders']::text[], 'machine',
   'Concept2', '{"strength": 1, "hypertrophy": 2, "weight_loss": 8, "conditioning": 9}'::jsonb, 2, 3,
   1, NULL, NULL,
   true, false,
   'low', false,
   ARRAY['lower_back','shoulder']::text[], false, 'B0lIgT5PHc8',
   'Concept2''s SkiErg mimics the double-pole motion of cross-country skiing, pulling two cords from an overhead reach down past the hips using a hip hinge and lat-driven pull. It''s a full-body conditioning tool that loads the lats and triceps in a long, stretched position on every rep, unlike leg-only cardio machines. Cue: reach tall for the catch and start the pull from the hips, not the arms.', 'pull_vertical')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Jacobs Ladder', 'jacobs-ladder', 'cardio',
   'quads', ARRAY['glutes','hamstrings','calves','lats','core','forearms']::text[], 'machine',
   'Jacobs Ladder', '{"strength": 1, "hypertrophy": 2, "weight_loss": 8, "conditioning": 10}'::jsonb, 2, 4,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','hip','shoulder']::text[], false, 'yO4KJB2R0XI',
   'Jacobs Ladder is a self-paced, endless-ladder climbing machine — there''s no belt or motor, so the rungs only move as fast as you climb. It''s a leg- and grip-endurance conditioning tool that scales entirely to effort, making it hard to fake through. Keep your hips low and drive through the whole foot on each rung instead of tip-toeing up on your calves.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('VersaClimber', 'versaclimber', 'cardio',
   'quads', ARRAY['glutes','hamstrings','calves','lats','shoulders','forearms']::text[], 'machine',
   'VersaClimber', '{"strength": 2, "hypertrophy": 2, "weight_loss": 8, "conditioning": 10}'::jsonb, 3, 4,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','hip','shoulder','wrist']::text[], false, 'n8YVmOmTZn8',
   'The VersaClimber is a vertical climbing machine with independent foot pedals and hand poles that move in opposition, like climbing a steep ladder. Because the arms and legs share the work, it delivers very high-output conditioning with zero impact, and resistance can be biased toward legs, arms, or both. Stay upright and drive the push through the hips and legs rather than just pedaling with the knees.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Lateral Elliptical (Side-to-Side Trainer)', 'lateral-elliptical-side-to-side-trainer', 'cardio',
   'glutes', ARRAY['quads','hamstrings','calves','adductors']::text[], 'machine',
   'Octane Fitness', '{"strength": 1, "hypertrophy": 2, "weight_loss": 7, "conditioning": 8}'::jsonb, 2, 3,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','hip','ankle']::text[], false, 'BlgPgJGZsy8',
   'The Lateral X swaps the standard front-to-back elliptical stride for a side-to-side, skating-style motion, which shifts the emphasis onto the glutes (especially glute medius) and inner/outer thigh instead of just quads and hamstrings. It''s a low-impact way to add frontal-plane conditioning that most cardio machines skip entirely. Push out through the whole foot on each lateral stride rather than just shifting your weight side to side.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.exercises
  (name, slug, category, primary_muscle, secondary_muscles, equipment,
   brand, focus_scores, complexity, fatigue_cost, spinal_load, rep_min,
   rep_max, lengthened_bias, unilateral, impact, leg_interference,
   joint_stress, explosive, demo_youtube_id, description, movement_pattern)
VALUES
  ('Fan Bike (Air Bike Cardio)', 'fan-bike-air-bike-cardio', 'cardio',
   'quads', ARRAY['hamstrings','glutes','calves','chest','shoulders','triceps']::text[], 'machine',
   'Assault Fitness', '{"strength": 2, "hypertrophy": 2, "weight_loss": 8, "conditioning": 10}'::jsonb, 1, 4,
   0, NULL, NULL,
   false, false,
   'low', false,
   ARRAY['knee','shoulder','elbow']::text[], false, 'jinMaYRpOTQ',
   'The fan bike pairs pedaling legs with pumping handles, and its air-resistance fan means the harder you push, the harder it pushes back — there''s no way to coast. It''s a staple full-body conditioning tool for intervals and finishers precisely because effort can''t be faked. Drive the handles down and back with the legs, not just the arms, or the legs end up doing all the work.', 'other')
ON CONFLICT (slug) DO NOTHING;

INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Cybex', 'Arc Trainer',
        (SELECT id FROM public.exercises WHERE slug = 'arc-trainer' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Precor', 'Adaptive Motion Trainer (AMT)',
        (SELECT id FROM public.exercises WHERE slug = 'adaptive-motion-trainer-amt' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Matrix Fitness', 'Krankcycle (Arm Ergometer)',
        (SELECT id FROM public.exercises WHERE slug = 'krankcycle-arm-ergometer' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Technogym', 'Kinesis Cable Station',
        (SELECT id FROM public.exercises WHERE slug = 'kinesis-cable-station' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Concept2', 'SkiErg',
        (SELECT id FROM public.exercises WHERE slug = 'skierg' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Jacobs Ladder', 'Jacobs Ladder',
        (SELECT id FROM public.exercises WHERE slug = 'jacobs-ladder' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('VersaClimber', 'VersaClimber',
        (SELECT id FROM public.exercises WHERE slug = 'versaclimber' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Octane Fitness', 'Lateral Elliptical (Side-to-Side Trainer)',
        (SELECT id FROM public.exercises WHERE slug = 'lateral-elliptical-side-to-side-trainer' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
INSERT INTO public.brand_machines (brand, machine, exercise_id)
VALUES ('Assault Fitness', 'Fan Bike (Air Bike Cardio)',
        (SELECT id FROM public.exercises WHERE slug = 'fan-bike-air-bike-cardio' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
