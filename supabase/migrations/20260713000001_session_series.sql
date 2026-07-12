CREATE TABLE public.session_series (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  organizer_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  timezone      text NOT NULL,
  until_date    date NOT NULL,
  late_penalty  jsonb NOT NULL DEFAULT '{"exercise":"burpee","per_minute":5}'::jsonb,
  ended_at      timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (until_date <= (created_at + interval '26 weeks')::date)
);

CREATE TABLE public.session_series_days (
  series_id  uuid NOT NULL REFERENCES public.session_series(id) ON DELETE CASCADE,
  weekday    int NOT NULL CHECK (weekday BETWEEN 1 AND 7),  -- 1=Sunday (Swift Calendar)
  time_local time NOT NULL,
  routine_id uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  PRIMARY KEY (series_id, weekday)
);

ALTER TABLE public.sessions
  ADD COLUMN series_id uuid REFERENCES public.session_series(id) ON DELETE SET NULL;
CREATE INDEX sessions_series_idx ON public.sessions(series_id)
  WHERE series_id IS NOT NULL;

ALTER TABLE public.session_series      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_series_days ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.series_group_id(p_series_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT group_id FROM public.session_series WHERE id = p_series_id;
$$;

CREATE OR REPLACE FUNCTION public.is_series_organizer(p_series_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.session_series
                 WHERE id = p_series_id AND organizer_id = p_user_id);
$$;

CREATE POLICY "group members read series"
  ON public.session_series FOR SELECT TO authenticated
  USING (public.is_group_member(session_series.group_id, auth.uid()));
CREATE POLICY "organizer creates series in own group"
  ON public.session_series FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid()
              AND public.is_group_member(session_series.group_id, auth.uid()));
CREATE POLICY "organizer updates series"
  ON public.session_series FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid()) WITH CHECK (organizer_id = auth.uid());
CREATE POLICY "organizer deletes series"
  ON public.session_series FOR DELETE TO authenticated
  USING (organizer_id = auth.uid());

CREATE POLICY "group members read series days"
  ON public.session_series_days FOR SELECT TO authenticated
  USING (public.is_group_member(
           public.series_group_id(session_series_days.series_id), auth.uid()));
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid()));
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid()))
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid()));
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid()));
