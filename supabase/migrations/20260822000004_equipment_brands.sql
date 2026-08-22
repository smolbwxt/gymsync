-- 20260822000004_equipment_brands.sql
--
-- Hub equipment brands, data layer (spec 2026-08-22 §4; owner: "the
-- hub is the source of truth"). Three pieces:
--   1. exercises.brand - set ONLY on brand-specific rows (the new
--      machines the brand pass adds); generic rows stay brand-less so
--      unchecking Hammer Strength never removes a generic lat pulldown.
--   2. brand_machines - the reference map the hub UI renders: each
--      brand's signature machines and the catalog exercise each one IS
--      (76 strategist-validated mappings seeded below).
--   3. Venue exclusions - brand-level and per-exercise ticks,
--      crowdsourced: any member of the hub (venue_users) may edit the
--      collective picture; the hub is the source of truth.
ALTER TABLE public.exercises ADD COLUMN IF NOT EXISTS brand text;

CREATE TABLE public.brand_machines (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  brand       text NOT NULL,
  machine     text NOT NULL,
  exercise_id uuid REFERENCES public.exercises(id) ON DELETE CASCADE,
  UNIQUE (brand, machine)
);
CREATE INDEX brand_machines_brand_idx ON public.brand_machines (brand);

ALTER TABLE public.brand_machines ENABLE ROW LEVEL SECURITY;
CREATE POLICY "brand machines are globally readable"
  ON public.brand_machines FOR SELECT TO authenticated USING (true);

CREATE TABLE public.venue_brand_exclusions (
  venue_id uuid NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  brand    text NOT NULL,
  added_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  PRIMARY KEY (venue_id, brand)
);
CREATE TABLE public.venue_equipment_exclusions (
  venue_id    uuid NOT NULL REFERENCES public.venues(id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES public.exercises(id) ON DELETE CASCADE,
  added_by    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  PRIMARY KEY (venue_id, exercise_id)
);

ALTER TABLE public.venue_brand_exclusions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.venue_equipment_exclusions ENABLE ROW LEVEL SECURITY;

-- Readable to anyone (the picture is public); editable by the hub's
-- OWN members - the crowdsourcing consent boundary.
CREATE POLICY "exclusions readable" ON public.venue_brand_exclusions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "members edit brand exclusions" ON public.venue_brand_exclusions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.venue_users vu
                 WHERE vu.venue_id = venue_brand_exclusions.venue_id
                   AND vu.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.venue_users vu
                      WHERE vu.venue_id = venue_brand_exclusions.venue_id
                        AND vu.user_id = auth.uid()));
CREATE POLICY "equipment exclusions readable" ON public.venue_equipment_exclusions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "members edit equipment exclusions" ON public.venue_equipment_exclusions
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.venue_users vu
                 WHERE vu.venue_id = venue_equipment_exclusions.venue_id
                   AND vu.user_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.venue_users vu
                      WHERE vu.venue_id = venue_equipment_exclusions.venue_id
                        AND vu.user_id = auth.uid()));

INSERT INTO public.brand_machines (brand, machine, exercise_id) VALUES
  ('Hammer Strength', 'Iso-Lateral Row', (SELECT id FROM public.exercises WHERE name = 'Iso-Lateral Row' LIMIT 1)),
  ('Hammer Strength', 'Iso-Lateral Chest Press', (SELECT id FROM public.exercises WHERE name = 'Iso-Lateral Chest Press' LIMIT 1)),
  ('Hammer Strength', 'Iso-Lateral Shoulder Press', (SELECT id FROM public.exercises WHERE name = 'Iso-Lateral Shoulder Press' LIMIT 1)),
  ('Hammer Strength', 'Iso-Lateral Leg Press', (SELECT id FROM public.exercises WHERE name = 'Iso-Lateral Leg Press' LIMIT 1)),
  ('Hammer Strength', 'HD Belt Squat', (SELECT id FROM public.exercises WHERE name = 'Belt Squat' LIMIT 1)),
  ('Hammer Strength', 'Ground Base Row', (SELECT id FROM public.exercises WHERE name = 'Ground Base Row' LIMIT 1)),
  ('Hammer Strength', 'Iso-Lateral Glute Drive', (SELECT id FROM public.exercises WHERE name = 'Iso-Lateral Glute Drive' LIMIT 1)),
  ('Life Fitness', 'Signature Series Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Life Fitness', 'Signature Series Chest Press', (SELECT id FROM public.exercises WHERE name = 'Machine Bench Press' LIMIT 1)),
  ('Life Fitness', 'Treadmill', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Life Fitness', 'Elliptical Cross-Trainer', (SELECT id FROM public.exercises WHERE name = 'Elliptical Trainer' LIMIT 1)),
  ('Life Fitness', 'Signature Series Lat Pulldown', (SELECT id FROM public.exercises WHERE name = 'Lat Pulldown' LIMIT 1)),
  ('Life Fitness', 'Signature Series Leg Extension', (SELECT id FROM public.exercises WHERE name = 'Leg Extension' LIMIT 1)),
  ('Life Fitness', 'Signature Series Leg Curl', (SELECT id FROM public.exercises WHERE name = 'Leg Curl' LIMIT 1)),
  ('Nautilus', 'Nautilus Pullover', (SELECT id FROM public.exercises WHERE name = 'Pullover Machine' LIMIT 1)),
  ('Nautilus', 'Nautilus Leg Extension', (SELECT id FROM public.exercises WHERE name = 'Leg Extension' LIMIT 1)),
  ('Nautilus', 'Nautilus Leg Curl', (SELECT id FROM public.exercises WHERE name = 'Prone Leg Curl' LIMIT 1)),
  ('Nautilus', 'Nautilus Compound Row', (SELECT id FROM public.exercises WHERE name = 'Seated Row Machine' LIMIT 1)),
  ('Nautilus', 'Nautilus 4-Way Neck', (SELECT id FROM public.exercises WHERE name = '4-Way Neck Machine' LIMIT 1)),
  ('Nautilus', 'Nautilus Pec Deck / Arm Cross', (SELECT id FROM public.exercises WHERE name = 'Pec Deck' LIMIT 1)),
  ('Cybex', 'Eagle NX Leg Press', (SELECT id FROM public.exercises WHERE name = '45-Degree Leg Press' LIMIT 1)),
  ('Cybex', 'VR3 Chest Press', (SELECT id FROM public.exercises WHERE name = 'Seated Chest Press Machine' LIMIT 1)),
  ('Cybex', 'Multi-Hip Machine', (SELECT id FROM public.exercises WHERE name = 'Multi-Hip Machine (Extension Setting)' LIMIT 1)),
  ('Cybex', 'Bravo Functional Trainer', (SELECT id FROM public.exercises WHERE name = 'Cable Crossover' LIMIT 1)),
  ('Precor', 'EFX Elliptical', (SELECT id FROM public.exercises WHERE name = 'Elliptical Trainer' LIMIT 1)),
  ('Precor', 'Treadmill', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Precor', 'Icarian Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Precor', 'Recumbent Bike', (SELECT id FROM public.exercises WHERE name = 'Recumbent Bike' LIMIT 1)),
  ('Matrix Fitness', 'Treadmill', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Matrix Fitness', 'Ascent Trainer', (SELECT id FROM public.exercises WHERE name = 'Elliptical Trainer' LIMIT 1)),
  ('Matrix Fitness', 'Ultra Series Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Technogym', 'Skillrun', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Technogym', 'Selection Pro Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Technogym', 'Recline Bike', (SELECT id FROM public.exercises WHERE name = 'Recumbent Bike' LIMIT 1)),
  ('Rogue Fitness', 'Echo Bike', (SELECT id FROM public.exercises WHERE name = 'Fan Bike (Air Bike Cardio)' LIMIT 1)),
  ('Rogue Fitness', 'Dog Sled / Prowler', (SELECT id FROM public.exercises WHERE name = 'Sled Push' LIMIT 1)),
  ('Rogue Fitness', 'Landmine', (SELECT id FROM public.exercises WHERE name = 'Landmine Press' LIMIT 1)),
  ('Concept2', 'RowErg', (SELECT id FROM public.exercises WHERE name = 'Rowing, Stationary' LIMIT 1)),
  ('Concept2', 'BikeErg', (SELECT id FROM public.exercises WHERE name = 'Bicycling, Stationary' LIMIT 1)),
  ('Keiser', 'M3i Indoor Cycle', (SELECT id FROM public.exercises WHERE name = 'Bicycling, Stationary' LIMIT 1)),
  ('Keiser', 'Air300 Squat', (SELECT id FROM public.exercises WHERE name = 'Smith Machine Squat' LIMIT 1)),
  ('Keiser', 'Functional Trainer', (SELECT id FROM public.exercises WHERE name = 'Cable Crossover' LIMIT 1)),
  ('Keiser', 'A420 Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Free Motion', 'Dual Cable Cross', (SELECT id FROM public.exercises WHERE name = 'Cable Crossover' LIMIT 1)),
  ('Free Motion', 'EXT Incline Press Station', (SELECT id FROM public.exercises WHERE name = 'Incline Cable Chest Press' LIMIT 1)),
  ('Hoist Fitness', 'ROC-IT Functional Trainer', (SELECT id FROM public.exercises WHERE name = 'Cable Crossover' LIMIT 1)),
  ('Hoist Fitness', 'Motion Cage Dip Station', (SELECT id FROM public.exercises WHERE name = 'Parallel Bar Dip' LIMIT 1)),
  ('Woodway', 'Curve (self-powered treadmill)', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('StairMaster', 'StepMill', (SELECT id FROM public.exercises WHERE name = 'Stairmaster' LIMIT 1)),
  ('TRX', 'Suspension Trainer Row', (SELECT id FROM public.exercises WHERE name = 'Suspended Row' LIMIT 1)),
  ('TRX', 'Suspension Trainer Push-Up', (SELECT id FROM public.exercises WHERE name = 'Suspended Push-Up' LIMIT 1)),
  ('TRX', 'Suspension Trainer Split Squat', (SELECT id FROM public.exercises WHERE name = 'Suspended Split Squat' LIMIT 1)),
  ('Sorinex', 'Reverse Hyper', (SELECT id FROM public.exercises WHERE name = 'Reverse Hyperextension Machine' LIMIT 1)),
  ('Sorinex', 'Belt Squat', (SELECT id FROM public.exercises WHERE name = 'Belt Squat' LIMIT 1)),
  ('EliteFTS', 'Reverse Hyper', (SELECT id FROM public.exercises WHERE name = 'Reverse Hyperextension Machine' LIMIT 1)),
  ('EliteFTS', 'Prowler Sled', (SELECT id FROM public.exercises WHERE name = 'Sled Push' LIMIT 1)),
  ('Watson Gym Equipment', 'Belt Squat', (SELECT id FROM public.exercises WHERE name = 'Belt Squat' LIMIT 1)),
  ('Watson Gym Equipment', 'GHD', (SELECT id FROM public.exercises WHERE name = 'Glute-Ham Developer' LIMIT 1)),
  ('Arsenal Strength', 'Bison Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Arsenal Strength', 'Freedom Squat', (SELECT id FROM public.exercises WHERE name = 'Barbell Squat' LIMIT 1)),
  ('Panatta', 'Multipower', (SELECT id FROM public.exercises WHERE name = 'Smith Machine' LIMIT 1)),
  ('Panatta', 'Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Gym80', 'Sygnum Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Gym80', 'Sygnum Chest Press', (SELECT id FROM public.exercises WHERE name = 'Machine Bench Press' LIMIT 1)),
  ('MedX', 'Lumbar Extension Machine', (SELECT id FROM public.exercises WHERE name = 'Back Extension' LIMIT 1)),
  ('MedX', 'Cervical Extension Machine', (SELECT id FROM public.exercises WHERE name = 'Neck Extension Machine' LIMIT 1)),
  ('Octane Fitness', 'Zero Runner', (SELECT id FROM public.exercises WHERE name = 'Elliptical Trainer' LIMIT 1)),
  ('NordicTrack', 'Incline Trainer', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('NordicTrack', 'Recumbent Bike', (SELECT id FROM public.exercises WHERE name = 'Recumbent Bike' LIMIT 1)),
  ('Peloton', 'Bike', (SELECT id FROM public.exercises WHERE name = 'Bicycling, Stationary' LIMIT 1)),
  ('Peloton', 'Tread', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Body-Solid', 'Powerline Functional Trainer', (SELECT id FROM public.exercises WHERE name = 'Cable Crossover' LIMIT 1)),
  ('Body-Solid', 'GLPH Leg Press', (SELECT id FROM public.exercises WHERE name = 'Leg Press' LIMIT 1)),
  ('Torque Fitness', 'Tank M2', (SELECT id FROM public.exercises WHERE name = 'Sled Push' LIMIT 1)),
  ('Assault Fitness', 'AirRunner', (SELECT id FROM public.exercises WHERE name = 'Running, Treadmill' LIMIT 1)),
  ('Schwinn', 'AC Performance Plus Bike', (SELECT id FROM public.exercises WHERE name = 'Bicycling, Stationary' LIMIT 1))
ON CONFLICT (brand, machine) DO NOTHING;
