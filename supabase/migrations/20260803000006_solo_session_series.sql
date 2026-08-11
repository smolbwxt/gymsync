-- Recurring solo workouts (owner request 2026-08-02: "yes I want recurring
-- solo workouts").
--
-- `session_series` was built group-first: `group_id NOT NULL`, every RLS
-- policy routed through `is_group_member`, and `finalize_series` always
-- announced the schedule into the group's chat. A lifter who trains alone
-- could schedule ONE session (20260803000005) but never a standing
-- commitment — "legs every Tuesday" required inventing a group.
--
-- This makes the group OPTIONAL. A solo series is one whose `group_id IS
-- NULL`; it belongs to its organizer and nobody else, which is exactly what
-- the policies below encode. Group series are untouched: every predicate
-- keeps its existing group branch, and solo access is added beside it rather
-- than replacing it.

-- 1 ── The column itself.
ALTER TABLE public.session_series ALTER COLUMN group_id DROP NOT NULL;

-- 2 ── session_series policies.
--
-- Read: a solo series is visible to its organizer alone. Write: you may only
-- create a series in a group you belong to, OR a solo one for yourself —
-- `group_id IS NULL` can never be used to smuggle access to someone else's
-- schedule because `organizer_id = auth.uid()` is conjoined in every branch.
DROP POLICY IF EXISTS "group members read series" ON public.session_series;
DROP POLICY IF EXISTS "group members read series" ON public.session_series;
CREATE POLICY "group members read series"
  ON public.session_series FOR SELECT TO authenticated
  USING (
    (group_id IS NULL AND organizer_id = auth.uid())
    OR private.is_group_member(group_id, auth.uid())
  );

DROP POLICY IF EXISTS "organizer creates series in own group" ON public.session_series;
DROP POLICY IF EXISTS "organizer creates series in own group" ON public.session_series;
CREATE POLICY "organizer creates series in own group"
  ON public.session_series FOR INSERT TO authenticated
  WITH CHECK (
    organizer_id = auth.uid()
    AND (group_id IS NULL OR private.is_group_member(group_id, auth.uid()))
  );

DROP POLICY IF EXISTS "organizer updates series" ON public.session_series;
DROP POLICY IF EXISTS "organizer updates series" ON public.session_series;
CREATE POLICY "organizer updates series"
  ON public.session_series FOR UPDATE TO authenticated
  USING (
    organizer_id = auth.uid()
    AND (group_id IS NULL OR private.is_group_member(group_id, auth.uid()))
  )
  WITH CHECK (
    organizer_id = auth.uid()
    AND (group_id IS NULL OR private.is_group_member(group_id, auth.uid()))
  );

DROP POLICY IF EXISTS "organizer deletes series" ON public.session_series;
DROP POLICY IF EXISTS "organizer deletes series" ON public.session_series;
CREATE POLICY "organizer deletes series"
  ON public.session_series FOR DELETE TO authenticated
  USING (
    organizer_id = auth.uid()
    AND (group_id IS NULL OR private.is_group_member(group_id, auth.uid()))
  );

-- 3 ── session_series_days policies.
--
-- `series_group_id()` returns NULL for a solo series, and
-- `is_group_member(NULL, …)` is not a truth value anyone should rely on —
-- so each policy now asks the ownership question explicitly first.
DROP POLICY IF EXISTS "group members read series days" ON public.session_series_days;
DROP POLICY IF EXISTS "group members read series days" ON public.session_series_days;
CREATE POLICY "group members read series days"
  ON public.session_series_days FOR SELECT TO authenticated
  USING (
    (private.series_group_id(series_id) IS NULL
     AND private.is_series_organizer(series_id, auth.uid()))
    OR private.is_group_member(private.series_group_id(series_id), auth.uid())
  );

DROP POLICY IF EXISTS "organizer writes series days" ON public.session_series_days;
DROP POLICY IF EXISTS "organizer writes series days" ON public.session_series_days;
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (
    private.is_series_organizer(series_id, auth.uid())
    AND (private.series_group_id(series_id) IS NULL
         OR private.is_group_member(private.series_group_id(series_id), auth.uid()))
  );

DROP POLICY IF EXISTS "organizer updates series days" ON public.session_series_days;
DROP POLICY IF EXISTS "organizer updates series days" ON public.session_series_days;
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (
    private.is_series_organizer(series_id, auth.uid())
    AND (private.series_group_id(series_id) IS NULL
         OR private.is_group_member(private.series_group_id(series_id), auth.uid()))
  )
  WITH CHECK (
    private.is_series_organizer(series_id, auth.uid())
    AND (private.series_group_id(series_id) IS NULL
         OR private.is_group_member(private.series_group_id(series_id), auth.uid()))
  );

DROP POLICY IF EXISTS "organizer deletes series days" ON public.session_series_days;
DROP POLICY IF EXISTS "organizer deletes series days" ON public.session_series_days;
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (
    private.is_series_organizer(series_id, auth.uid())
    AND (private.series_group_id(series_id) IS NULL
         OR private.is_group_member(private.series_group_id(series_id), auth.uid()))
  );

-- 4 ── finalize_series must not announce into a group that isn't there.
--
-- It unconditionally inserted a 🔁 summary into `chat_messages` using the
-- series' group_id; for a solo series that is NULL, which would either
-- violate the column's NOT NULL or mint an unreachable message. A solo
-- series simply has no room to announce into, so it finalizes silently.
-- Everything else about the function is preserved verbatim, including the
-- organizer-only guard.
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

  -- Solo series: nothing to announce, and nowhere to announce it.
  IF v_series.group_id IS NULL THEN
    RETURN;
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
