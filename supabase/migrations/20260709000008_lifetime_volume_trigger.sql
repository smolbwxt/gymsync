CREATE OR REPLACE FUNCTION public.increment_lifetime_volume()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.is_failed = false AND NEW.is_penalty = false
     AND NEW.reps IS NOT NULL AND NEW.weight IS NOT NULL THEN
    UPDATE public.profiles
      SET lifetime_volume_lifted = lifetime_volume_lifted + (NEW.reps * NEW.weight)
      WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_logs_increment_volume
  AFTER INSERT ON public.set_logs
  FOR EACH ROW EXECUTE FUNCTION public.increment_lifetime_volume();
