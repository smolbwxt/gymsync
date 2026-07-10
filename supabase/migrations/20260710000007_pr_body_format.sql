-- Fix trailing-dot bug in PR announcement body: 'FM999999.99' renders '100.' for whole numbers.
-- Strip the trailing dot with TRAILING '.' FROM to_char(...).
CREATE OR REPLACE FUNCTION public.announce_pr() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_username text;
  v_exercise text;
BEGIN
  IF NEW.is_failed OR NEW.is_penalty OR NEW.weight IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.set_logs
    WHERE user_id = NEW.user_id AND exercise_id = NEW.exercise_id
      AND is_failed = false AND is_penalty = false
      AND id <> NEW.id AND weight >= NEW.weight
  ) THEN
    RETURN NEW;  -- not a PR
  END IF;

  SELECT username INTO v_username FROM public.profiles  WHERE id = NEW.user_id;
  SELECT name     INTO v_exercise FROM public.exercises WHERE id = NEW.exercise_id;

  INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
  SELECT gm.group_id, NULL, 'system_pr',
         '🔥 ' || v_username || ' hit a PR on ' || v_exercise || ': '
              || trim(TRAILING '.' FROM to_char(NEW.weight, 'FM999999.99')) || ' lbs',
         jsonb_build_object('user_id', NEW.user_id, 'exercise_id', NEW.exercise_id,
                            'weight', NEW.weight, 'set_log_id', NEW.id)
  FROM public.group_members gm
  WHERE gm.user_id = NEW.user_id;

  RETURN NEW;
END;
$$;
