-- Rogue Echo Bike -> the Fan Bike row (inserted AFTER the 004 seed ran;
-- the strategist's cross-brand mapping resolves now).
UPDATE public.brand_machines
   SET exercise_id = (SELECT id FROM public.exercises WHERE slug = 'fan-bike-air-bike-cardio' LIMIT 1)
 WHERE brand = 'Rogue Fitness' AND machine = 'Echo Bike' AND exercise_id IS NULL;
