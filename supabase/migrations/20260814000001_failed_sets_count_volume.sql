-- Failure doctrine, volume leg (owner 2026-08-13: "Make the change, lets
-- be consistent"): a failed set logged at n reps completed n−1 of them —
-- real work that moved real weight. Lifetime volume now counts those
-- completed reps. The missed single (n ≤ 1 → 0 completed) still counts
-- nothing, and penalty sets remain excluded.
CREATE OR REPLACE FUNCTION public.increment_lifetime_volume()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_completed integer;
BEGIN
  IF NEW.is_penalty = false
     AND NEW.reps IS NOT NULL
     AND (NEW.weight IS NOT NULL OR NEW.body_weight_lbs IS NOT NULL) THEN
    v_completed := CASE WHEN NEW.is_failed THEN NEW.reps - 1 ELSE NEW.reps END;
    IF v_completed > 0 THEN
      UPDATE public.profiles
        SET lifetime_volume_lifted = lifetime_volume_lifted
          + (v_completed * (COALESCE(NEW.weight, 0) + COALESCE(NEW.body_weight_lbs, 0)))
        WHERE id = NEW.user_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
