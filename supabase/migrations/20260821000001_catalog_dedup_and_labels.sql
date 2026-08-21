-- Catalog QA (Sonnet swarm 2026-08-21, owner-directed): dedup + label
-- sanity over all 1,305 rows. High-confidence findings only, validated
-- against legal vocabularies; equipment moves outside the 5 filter
-- classes HELD (they would vanish under hub presets until subclass
-- filtering exists). Alias rows are MARKED, never deleted - history,
-- PRs, and substitutions keep resolving; selection pools exclude them.

ALTER TABLE public.exercises ADD COLUMN IF NOT EXISTS alias_of uuid
  REFERENCES public.exercises(id);
CREATE INDEX IF NOT EXISTS exercises_alias_of_idx ON public.exercises(alias_of);

UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'back-extension') WHERE slug = '45-degree-back-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'arnold-press') WHERE slug = 'arnold-dumbbell-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'back-extension') WHERE slug = 'back-extension-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'bent-arm-barbell-pullover') WHERE slug = 'barbell-pullover';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'barbell-step-up') WHERE slug = 'barbell-step-ups';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-barbell-press-behind-neck') WHERE slug = 'behind-neck-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'belt-squat') WHERE slug = 'belt-squat-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'bench-dips') WHERE slug = 'bench-dip';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'chest-supported-rear-delt-raise') WHERE slug = 'bent-over-dumbbell-rear-delt-raise-with-head-on-bench';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'front-cable-raise') WHERE slug = 'cable-front-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-hammer-curls-rope-attachment') WHERE slug = 'cable-hammer-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'one-legged-cable-kickback') WHERE slug = 'cable-kickback';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-seated-lateral-raise') WHERE slug = 'cable-lateral-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-rope-rear-delt-row') WHERE slug = 'cable-rope-rear-delt-rows';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-russian-twists') WHERE slug = 'cable-russian-twist';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-shrug') WHERE slug = 'cable-shrugs';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-cable-wood-chop') WHERE slug = 'cable-woodchop';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-wrist-curl') WHERE slug = 'cable-wrist-curl-station';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'calf-press-on-the-leg-press-machine') WHERE slug = 'calf-press-leg-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'close-grip-standing-barbell-curl') WHERE slug = 'close-grip-barbell-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'close-grip-barbell-bench-press') WHERE slug = 'close-grip-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'close-grip-dumbbell-press') WHERE slug = 'close-grip-db-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'close-grip-front-lat-pulldown') WHERE slug = 'close-grip-lat-pulldown';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'concentration-curl') WHERE slug = 'concentration-curls';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'calf-raise-on-a-dumbbell') WHERE slug = 'db-calf-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-clean') WHERE slug = 'db-clean';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-flyes') WHERE slug = 'db-flye';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-lunges') WHERE slug = 'db-lunge';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'split-squat-with-dumbbells') WHERE slug = 'db-split-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-squat') WHERE slug = 'db-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-step-ups') WHERE slug = 'db-step-up';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'tricep-dumbbell-kickback') WHERE slug = 'db-tricep-kickback';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'decline-barbell-bench-press') WHERE slug = 'decline-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'decline-dumbbell-bench-press') WHERE slug = 'decline-db-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'decline-dumbbell-fly') WHERE slug = 'decline-dumbbell-flyes';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'farmers-carry') WHERE slug = 'farmer-s-walk';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'front-dumbbell-raise') WHERE slug = 'front-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'barbell-guillotine-bench-press') WHERE slug = 'guillotine-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hack-squat') WHERE slug = 'hack-squat-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hammer-curl') WHERE slug = 'hammer-curls';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'handstand-push-ups') WHERE slug = 'handstand-push-up';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'incline-dumbbell-curl') WHERE slug = 'incline-db-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'front-incline-dumbbell-raise') WHERE slug = 'incline-db-front-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'incline-dumbbell-press') WHERE slug = 'incline-db-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-incline-row') WHERE slug = 'incline-db-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'incline-dumbbell-fly') WHERE slug = 'incline-dumbbell-flyes';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'leverage-incline-chest-press') WHERE slug = 'incline-machine-chest-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'iso-lateral-chest-press') WHERE slug = 'iso-lateral-chest-press-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'iso-lateral-high-row') WHERE slug = 'iso-lateral-high-row-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hip-abductor-machine') WHERE slug = 'iso-lateral-hip-abduction';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hip-adductor-machine') WHERE slug = 'iso-lateral-hip-adduction';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'iso-lateral-low-row') WHERE slug = 'iso-lateral-low-row-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'iso-lateral-pulldown') WHERE slug = 'iso-lateral-pulldown-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'freehand-jump-squat') WHERE slug = 'jump-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'landmine-180') WHERE slug = 'landmine-180-s';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'one-arm-long-bar-row') WHERE slug = 'landmine-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'leg-extension') WHERE slug = 'leg-extension-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'leg-extension') WHERE slug = 'leg-extensions';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'lying-dumbbell-tricep-extension') WHERE slug = 'lying-db-tricep-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'lying-leg-curl') WHERE slug = 'lying-leg-curl-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'lying-leg-curl') WHERE slug = 'lying-leg-curls';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'flat-bench-lying-leg-raise') WHERE slug = 'lying-leg-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dip-machine') WHERE slug = 'machine-dip';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'leverage-high-row') WHERE slug = 'machine-high-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'preacher-curl-machine') WHERE slug = 'machine-preacher-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'preacher-curl-machine') WHERE slug = 'machine-preacher-curls';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'machine-shoulder-military-press') WHERE slug = 'machine-shoulder-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'machine-triceps-extension') WHERE slug = 'machine-tricep-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'mountain-climbers') WHERE slug = 'mountain-climber';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'narrow-stance-hack-squats') WHERE slug = 'narrow-stance-hack-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'narrow-stance-squats') WHERE slug = 'narrow-stance-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'bent-over-two-dumbbell-row-with-palms-in') WHERE slug = 'neutral-grip-db-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'oblique-crunches') WHERE slug = 'oblique-crunches-on-the-floor';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-one-arm-tricep-extension') WHERE slug = 'one-arm-cable-tricep-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'one-arm-dumbbell-bench-press') WHERE slug = 'one-arm-db-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'one-arm-dumbbell-row') WHERE slug = 'one-arm-db-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'dumbbell-one-arm-shoulder-press') WHERE slug = 'one-arm-db-shoulder-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-rope-overhead-triceps-extension') WHERE slug = 'overhead-rope-tricep-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'pendulum-squat') WHERE slug = 'pendulum-squat-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-pull-through') WHERE slug = 'pull-through';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'reverse-grip-bent-over-rows') WHERE slug = 'reverse-grip-bent-over-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'reverse-grip-triceps-pushdown') WHERE slug = 'reverse-grip-tricep-pushdown';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'reverse-hyperextension-machine') WHERE slug = 'reverse-hyperextension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'rocking-standing-calf-raise') WHERE slug = 'rocking-calf-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'back-extension') WHERE slug = 'roman-chair-back-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'triceps-pushdown-rope-attachment') WHERE slug = 'rope-tricep-pushdown';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-row') WHERE slug = 'seated-cable-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'cable-row') WHERE slug = 'seated-cable-rows';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'seated-calf-raise') WHERE slug = 'seated-calf-raise-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'seated-dumbbell-curl') WHERE slug = 'seated-db-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'seated-dumbbell-press') WHERE slug = 'seated-db-shoulder-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'seated-leg-curl') WHERE slug = 'seated-leg-curl-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'seated-one-arm-cable-row') WHERE slug = 'seated-one-arm-cable-pulley-rows';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'single-leg-leg-extension') WHERE slug = 'single-leg-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'single-leg-press') WHERE slug = 'single-leg-leg-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'ez-bar-skullcrusher') WHERE slug = 'skull-crusher';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'smith-machine-overhead-shoulder-press') WHERE slug = 'smith-machine-overhead-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'smith-machine-reverse-calf-raises') WHERE slug = 'smith-machine-reverse-calf-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'smith-machine-bent-over-row') WHERE slug = 'smith-machine-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'smith-single-leg-split-squat') WHERE slug = 'smith-machine-split-squat';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'smith-machine-stiff-legged-deadlift') WHERE slug = 'smith-machine-stiff-leg-deadlift';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-biceps-cable-curl') WHERE slug = 'standing-cable-curl';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-calf-raise') WHERE slug = 'standing-calf-raise-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-calf-raise') WHERE slug = 'standing-calf-raises';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-dumbbell-calf-raise') WHERE slug = 'standing-db-calf-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-dumbbell-triceps-extension') WHERE slug = 'standing-db-tricep-extension';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'standing-leg-curl') WHERE slug = 'standing-leg-curl-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'step-up-with-knee-raise') WHERE slug = 'step-up-knee-raise';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'stiff-legged-dumbbell-deadlift') WHERE slug = 'stiff-leg-db-deadlift';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'stiff-legged-barbell-deadlift') WHERE slug = 'stiff-leg-deadlift';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 't-bar-row-with-handle') WHERE slug = 't-bar-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hip-abductor-machine') WHERE slug = 'thigh-abductor';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'hip-adductor-machine') WHERE slug = 'thigh-adductor';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'tibialis-raise-machine') WHERE slug = 'tibia-raise-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'triceps-pushdown') WHERE slug = 'tricep-pushdown';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'triceps-pushdown-v-bar-attachment') WHERE slug = 'tricep-pushdown-v-bar-attachment';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'underhand-cable-pulldowns') WHERE slug = 'underhand-lat-pulldown';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'upright-barbell-row') WHERE slug = 'upright-row';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'v-bar-pullup') WHERE slug = 'v-bar-pull-up';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'v-squat') WHERE slug = 'v-squat-machine';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'weighted-pull-up') WHERE slug = 'weighted-pull-ups';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'wide-grip-barbell-bench-press') WHERE slug = 'wide-grip-bench-press';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'wide-grip-rear-pull-up') WHERE slug = 'wide-grip-pull-up';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'push-up-wide') WHERE slug = 'wide-push-up';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'wide-stance-stiff-leg-deadlift') WHERE slug = 'wide-stance-stiff-legs';
UPDATE public.exercises SET alias_of = (SELECT id FROM public.exercises WHERE slug = 'zercher-squats') WHERE slug = 'zercher-squat';

UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'assisted-dip-machine';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'bench-dips';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'bench-press-powerlifting';  -- Bench press is the textbook horizontal push movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'bench-press-with-chains';  -- Chain-loaded bench press is still a horizontal push.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'board-press';  -- Board press is a partial-ROM bench press; horizontal push.
UPDATE public.exercises SET primary_muscle = 'hamstrings' WHERE slug = 'cable-deadlifts';  -- Hip-hinge pattern is posterior-chain (hamstrings/glutes) dom
UPDATE public.exercises SET primary_muscle = 'hamstrings' WHERE slug = 'car-deadlift';  -- Hip-hinge deadlift is hamstring/glute driven; quads is secon
UPDATE public.exercises SET primary_muscle = 'lower_back' WHERE slug = 'chair-lower-back-stretch';  -- Name explicitly says 'Lower Back Stretch'; labeling it lats 
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'close-grip-barbell-bench-press';  -- Close-grip bench press is a horizontal pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'close-grip-dumbbell-press';  -- Dumbbell close-grip press is a horizontal pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'close-grip-ez-bar-press';  -- EZ-bar close-grip press is a horizontal pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'close-grip-push-up-off-of-a-dumbbell';  -- Push-up variants are horizontal pushing movements.
UPDATE public.exercises SET primary_muscle = 'glutes' WHERE slug = 'crossover-reverse-lunge';  -- It's a lunge pattern; lower_back isn't even in its own secon
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'diamond-push-up';  -- Push-up variants are horizontal pushing movements.
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'dip-machine';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'dips-triceps-version';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'dumbbell-floor-press';  -- Floor press is a horizontal pressing movement like bench pre
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'floor-press';  -- Floor press is a horizontal pressing movement like bench pre
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'floor-press-with-chains';  -- Chain-loaded floor press is still a horizontal push.
UPDATE public.exercises SET movement_pattern = 'other' WHERE slug = 'front-cone-hops-or-hurdle-hops';  -- This is a plyometric hop/jump drill (explosive=true), not a 
UPDATE public.exercises SET movement_pattern = 'isolation' WHERE slug = 'high-cable-curls';  -- Cable bicep curl variant is isolation, not 'other'.
UPDATE public.exercises SET movement_pattern = 'pull_horizontal' WHERE slug = 'incline-bench-pull';  -- Prone incline barbell row is a compound horizontal pull, not
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'incline-push-up-close-grip';  -- Push-up variants are horizontal pushing movements.
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'iso-lateral-rear-delt-fly';  -- Named rear delt fly; prime mover is rear delts, not generic 
UPDATE public.exercises SET movement_pattern = 'hinge' WHERE slug = 'kettlebell-swing';  -- Kettlebell swing is the textbook hip-hinge drill, not an unc
UPDATE public.exercises SET primary_muscle = 'hamstrings' WHERE slug = 'leverage-deadlift';  -- Machine deadlift is still a hip hinge; hamstrings/glutes are
UPDATE public.exercises SET primary_muscle = 'neck' WHERE slug = 'looking-at-ceiling';  -- Name describes a cervical extension movement; unrelated to q
UPDATE public.exercises SET movement_pattern = 'pull_vertical' WHERE slug = 'mixed-grip-chin';  -- A chin-up variant is a vertical pulling movement, not 'other
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'one-arm-floor-press';  -- Floor press is a horizontal pressing movement, single-arm or
UPDATE public.exercises SET movement_pattern = 'hinge' WHERE slug = 'one-arm-kettlebell-swings';  -- Same ballistic hip-hinge mechanics as the two-hand swing.
UPDATE public.exercises SET primary_muscle = 'hamstrings' WHERE slug = 'one-arm-side-deadlift';  -- Asymmetric hip-hinge deadlift; hamstrings/glutes primary, qu
UPDATE public.exercises SET primary_muscle = 'lower_back' WHERE slug = 'one-half-locust';  -- Locust is a prone back-extension yoga pose; trains spinal er
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'parallel-bar-dip';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'pin-presses';  -- Pin press is a bench-press variant; horizontal pressing move
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'push-ups-close-triceps-position';  -- Push-up variants are horizontal pushing movements.
UPDATE public.exercises SET movement_pattern = 'hinge' WHERE slug = 'rack-pull-with-bands';  -- Same partial-deadlift pattern as rack-pulls, which should al
UPDATE public.exercises SET movement_pattern = 'hinge' WHERE slug = 'rack-pulls';  -- Rack pulls are a partial-ROM deadlift; sibling deadlift vari
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'rear-delt-machine';  -- Name explicitly says rear delt; catalog uses rear_delts else
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'rear-delt-row-machine';  -- Named rear delt row; prime mover is rear delts, not generic 
UPDATE public.exercises SET primary_muscle = 'glutes' WHERE slug = 'rear-leg-raises';  -- Rear leg raise is a hip-extension glute exercise, not a quad
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'reverse-flyes';  -- Reverse fly is a rear-delt isolation move, same as catalog's
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'reverse-flyes-with-external-rotation';  -- Reverse fly variant; prime mover is rear delts, not generic 
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'reverse-machine-flyes';  -- Reverse fly (matches reverse-pec-deck) is rear-delt work, no
UPDATE public.exercises SET primary_muscle = 'hamstrings' WHERE slug = 'rickshaw-deadlift';  -- Hip-hinge pull (no knee in joint_stress); hamstrings/glutes 
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'ring-dips';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'isolation' WHERE slug = 'seated-bent-over-rear-delt-raise';  -- Bent-over raise is single-joint isolation, not a vertical pr
UPDATE public.exercises SET primary_muscle = 'rear_delts' WHERE slug = 'seated-bent-over-rear-delt-raise';  -- Named rear delt raise; same movement type labeled rear_delts
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'seated-dip-machine';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET primary_muscle = 'abductors' WHERE slug = 'side-leg-raises';  -- Lying side leg raise lifts leg away from body - trains abduc
UPDATE public.exercises SET equipment = 'machine' WHERE slug = 'smith-incline-shoulder-raise';  -- Named a Smith exercise; other Smith-named rows correctly use
UPDATE public.exercises SET movement_pattern = 'push_horizontal' WHERE slug = 'smith-machine-close-grip-bench-press';  -- Guided bench press is still a horizontal pressing movement.
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'vertical-dip-machine';  -- Name literally says 'Vertical'; dips are a vertical pressing
UPDATE public.exercises SET spinal_load = 1 WHERE slug = 'weighted-ball-hyperextension';  -- Ball-loaded back extension isn't heavy-axial like squats/dea
UPDATE public.exercises SET movement_pattern = 'push_vertical' WHERE slug = 'weighted-bench-dip';  -- Dips are a vertical pressing movement.
UPDATE public.exercises SET movement_pattern = 'hinge' WHERE slug = 'wide-stance-stiff-leg-deadlift';  -- Same stiff-leg deadlift movement; sibling deadlift rows are 
UPDATE public.exercises SET primary_muscle = 'quads' WHERE slug = 'wind-sprints';  -- Sprinting is leg/cardio-driven; core is not the primary trai
