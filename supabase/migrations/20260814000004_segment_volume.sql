-- Drop-set segment volume (set structures phase B): each drop segment's
-- reps × weight joins lifetime volume. The PARENT set_logs row carries
-- the TOP bell (so PRs, e1RM, and every existing consumer stay correct
-- with zero changes); segments are the drops only — no double count.
-- SECURITY DEFINER mirrors increment_lifetime_volume(): the profiles
-- update must not depend on the inserting user's RLS view.
CREATE OR REPLACE FUNCTION public.increment_lifetime_volume_segment()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.reps IS NOT NULL AND NEW.reps > 0 AND NEW.weight IS NOT NULL THEN
    UPDATE public.profiles
      SET lifetime_volume_lifted = lifetime_volume_lifted + (NEW.reps * NEW.weight)
      WHERE id = (SELECT user_id FROM public.set_logs WHERE id = NEW.set_log_id);
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_segment_volume ON public.set_log_segments;
CREATE TRIGGER trg_segment_volume
  AFTER INSERT ON public.set_log_segments
  FOR EACH ROW EXECUTE FUNCTION public.increment_lifetime_volume_segment();
