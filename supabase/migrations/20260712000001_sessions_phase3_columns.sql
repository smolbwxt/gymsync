ALTER TABLE public.sessions
  ADD COLUMN group_id                uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  ADD COLUMN room_code               text UNIQUE,
  ADD COLUMN current_turn_user_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN current_turn_started_at timestamptz,
  ADD COLUMN late_penalty            jsonb NOT NULL DEFAULT '{"exercise":"burpee","per_minute":5}'::jsonb,
  ADD COLUMN edited_by               uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.session_participants
  ADD COLUMN check_in_at     timestamptz,
  ADD COLUMN check_in_method text CHECK (check_in_method IN ('geofence','traveling_override')),
  ADD COLUMN late_minutes    integer NOT NULL DEFAULT 0,
  ADD COLUMN burpees_owed    integer NOT NULL DEFAULT 0;

CREATE INDEX sessions_group_scheduled_idx
  ON public.sessions(group_id, scheduled_for DESC) WHERE group_id IS NOT NULL;
CREATE INDEX sessions_scheduled_state_idx
  ON public.sessions(scheduled_for) WHERE state = 'scheduled';

-- Check-in is self-service: participants update their OWN row.
-- (Phase 1 policy only allowed the organizer to update participant rows.)
CREATE POLICY "participant updates own check-in"
  ON public.session_participants FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Lateness evaluation runs as the organizer at Start.
CREATE OR REPLACE FUNCTION public.evaluate_lateness(p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scheduled timestamptz;
  v_per_minute integer;
BEGIN
  SELECT scheduled_for, COALESCE((late_penalty->>'per_minute')::int, 5)
    INTO v_scheduled, v_per_minute
    FROM public.sessions
    WHERE id = p_session_id AND organizer_id = auth.uid();
  IF v_scheduled IS NULL THEN
    RAISE EXCEPTION 'only the session organizer may evaluate lateness';
  END IF;

  UPDATE public.session_participants sp
  SET late_minutes = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int,
      burpees_owed = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int * v_per_minute,
      check_in_state = CASE
        WHEN sp.check_in_at IS NOT NULL AND sp.check_in_at > v_scheduled THEN 'late'
        ELSE sp.check_in_state END
  WHERE sp.session_id = p_session_id
    AND (sp.check_in_at IS NULL OR sp.check_in_at > v_scheduled);
END;
$$;
