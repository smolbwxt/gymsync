-- Bodyweight-exercise sets (owner items 6+7, 2026-08-13): logged body
-- weight becomes the load a bodyweight set moves.
--
-- set_logs.body_weight_lbs — the lifter's latest logged body weight in
-- CANONICAL POUNDS, stamped by the client AT LOG TIME for exercises whose
-- equipment is 'bodyweight' (a snapshot, deliberately: last month's
-- pull-ups were done at last month's body weight). NULL for loaded lifts
-- and for lifters who never logged a body weight — volume stays honestly
-- zero rather than guessing.
--
-- The lifetime-volume trigger now counts effective tonnage:
-- reps × (added weight + body weight), and fires when EITHER component
-- exists — pure-bodyweight sets finally count.
ALTER TABLE public.set_logs
  ADD COLUMN IF NOT EXISTS body_weight_lbs numeric(6,2);

CREATE OR REPLACE FUNCTION public.increment_lifetime_volume()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.is_failed = false AND NEW.is_penalty = false
     AND NEW.reps IS NOT NULL
     AND (NEW.weight IS NOT NULL OR NEW.body_weight_lbs IS NOT NULL) THEN
    UPDATE public.profiles
      SET lifetime_volume_lifted = lifetime_volume_lifted
        + (NEW.reps * (COALESCE(NEW.weight, 0) + COALESCE(NEW.body_weight_lbs, 0)))
      WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;
