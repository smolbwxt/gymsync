-- Hub-hosted equipment (owner 2026-08-14: "the hub should host what
-- equipment is available, and that then should tell the coach what's
-- possible"). Equipment classes a venue offers — editable by the venue
-- creator through the existing creator-edit policy (unverified venues),
-- readable by everyone. The Coach reads the lifter's home-gym hub
-- inventory to preset its equipment dial; the home-gym → join-hub
-- prompt flow rides the next UI pass.
ALTER TABLE public.venues
  ADD COLUMN IF NOT EXISTS equipment text[] NOT NULL
    DEFAULT ARRAY['barbell','dumbbell','machine','cable','bodyweight']::text[];
