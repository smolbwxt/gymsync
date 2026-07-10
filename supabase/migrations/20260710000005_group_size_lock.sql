-- Serialize member inserts per group: without the row lock, two concurrent
-- inserts at 24 members both pass the count check and the group ends at 26.
CREATE OR REPLACE FUNCTION public.enforce_group_size() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM 1 FROM public.groups WHERE id = NEW.group_id FOR UPDATE;
  IF (SELECT count(*) FROM public.group_members WHERE group_id = NEW.group_id) >= 25 THEN
    RAISE EXCEPTION 'group is full (max 25 members)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
