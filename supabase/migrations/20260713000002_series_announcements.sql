CREATE OR REPLACE FUNCTION public.announce_session_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_username text;
  v_routine  text;
  v_body     text;
BEGIN
  IF NEW.group_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'INSERT' AND NEW.series_id IS NOT NULL THEN
    RETURN NEW;  -- series occurrences announce once via finalize_series
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_username FROM public.profiles WHERE id = NEW.organizer_id;
  SELECT name INTO v_routine FROM public.routines WHERE id = NEW.routine_id;

  v_body := CASE
    WHEN TG_OP = 'INSERT' AND NEW.state = 'scheduled' THEN
      '📅 ' || COALESCE(v_routine, 'Workout') || ' scheduled for '
           || to_char(NEW.scheduled_for AT TIME ZONE 'UTC', 'Dy Mon DD, HH24:MI')
           || ' UTC by ' || v_username
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'in_progress' THEN
      '🏁 ' || COALESCE(v_routine, 'Session') || ' started'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'completed' THEN
      '✅ ' || COALESCE(v_routine, 'Session') || ' complete'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'abandoned' THEN
      '🌫️ ' || COALESCE(v_routine, 'Session') || ' abandoned'
    ELSE NULL
  END;

  IF v_body IS NOT NULL THEN
    INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
    VALUES (NEW.group_id, NULL, 'system_session', v_body,
            jsonb_build_object('session_id', NEW.id, 'state', NEW.state,
                               'scheduled_for', NEW.scheduled_for));
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.finalize_series(p_series_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_series public.session_series%ROWTYPE;
  v_days   text;
BEGIN
  SELECT * INTO v_series FROM public.session_series
    WHERE id = p_series_id AND organizer_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'only the series organizer may finalize';
  END IF;
  SELECT string_agg(
           CASE weekday WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon' WHEN 3 THEN 'Tue'
                        WHEN 4 THEN 'Wed' WHEN 5 THEN 'Thu' WHEN 6 THEN 'Fri'
                        ELSE 'Sat' END, '/' ORDER BY weekday)
    INTO v_days
    FROM public.session_series_days WHERE series_id = p_series_id;
  INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
  VALUES (v_series.group_id, NULL, 'system_session',
          '🔁 Sessions scheduled ' || COALESCE(v_days, '?')
            || ' until ' || to_char(v_series.until_date, 'Mon DD'),
          jsonb_build_object('series_id', p_series_id,
                             'until_date', v_series.until_date));
END;
$$;

CREATE POLICY "organizer deletes own scheduled sessions"
  ON public.sessions FOR DELETE TO authenticated
  USING (organizer_id = auth.uid() AND state = 'scheduled');

-- Rider: departed organizers must not retain mutate rights (read is already member-gated)
DROP POLICY "organizer updates series" ON public.session_series;
CREATE POLICY "organizer updates series"
  ON public.session_series FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid()
         AND public.is_group_member(session_series.group_id, auth.uid()))
  WITH CHECK (organizer_id = auth.uid()
              AND public.is_group_member(session_series.group_id, auth.uid()));
DROP POLICY "organizer deletes series" ON public.session_series;
CREATE POLICY "organizer deletes series"
  ON public.session_series FOR DELETE TO authenticated
  USING (organizer_id = auth.uid()
         AND public.is_group_member(session_series.group_id, auth.uid()));
DROP POLICY "organizer writes series days" ON public.session_series_days;
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND public.is_group_member(
                    public.series_group_id(session_series_days.series_id), auth.uid()));
DROP POLICY "organizer updates series days" ON public.session_series_days;
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND public.is_group_member(
               public.series_group_id(session_series_days.series_id), auth.uid()))
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid())
              AND public.is_group_member(
                    public.series_group_id(session_series_days.series_id), auth.uid()));
DROP POLICY "organizer deletes series days" ON public.session_series_days;
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid())
         AND public.is_group_member(
               public.series_group_id(session_series_days.series_id), auth.uid()));
