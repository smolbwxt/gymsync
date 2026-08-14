-- Trainer arm T2 (owner 2026-08-14: "read AND write — everything that
-- dictates how a client works out"): prescription authority + scope-gated
-- reads + trainer notes (T5). The consent architecture:
--   WRITE (prescriptions) = inherent in the active coaching relationship,
--     but confined to the PRESCRIBED namespace — a trainer can never
--     touch a routine the client authored (prescribed_by is the fence).
--   READ (personal data) = the client's granular scope grants.
-- Ending the relationship kills all of it at the database, instantly.

ALTER TABLE public.routines
  ADD COLUMN IF NOT EXISTS prescribed_by uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

-- Helpers (private-schema idiom, RLS-quals-only; SECURITY DEFINER so the
-- trainer_clients lookup doesn't recurse through its own policies).
CREATE OR REPLACE FUNCTION private.is_trainer_of(p_client uuid, p_trainer uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trainer_clients tc
    WHERE tc.trainer_id = p_trainer AND tc.client_id = p_client
      AND tc.status = 'active'
  );
$$;

CREATE OR REPLACE FUNCTION private.trainer_scope(p_client uuid, p_trainer uuid, p_scope text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.trainer_clients tc
    WHERE tc.trainer_id = p_trainer AND tc.client_id = p_client
      AND tc.status = 'active'
      AND COALESCE((tc.scopes->>p_scope)::boolean, false)
  );
$$;

-- ── Routines: the prescription namespace ─────────────────────────────
CREATE POLICY "trainer reads client routines"
  ON public.routines FOR SELECT TO authenticated
  USING (private.is_trainer_of(owner_id, auth.uid()));

CREATE POLICY "trainer prescribes routines"
  ON public.routines FOR INSERT TO authenticated
  WITH CHECK (prescribed_by = auth.uid()
              AND private.is_trainer_of(owner_id, auth.uid()));

CREATE POLICY "trainer updates own prescriptions"
  ON public.routines FOR UPDATE TO authenticated
  USING (prescribed_by = auth.uid() AND private.is_trainer_of(owner_id, auth.uid()))
  WITH CHECK (prescribed_by = auth.uid());

CREATE POLICY "trainer deletes own prescriptions"
  ON public.routines FOR DELETE TO authenticated
  USING (prescribed_by = auth.uid() AND private.is_trainer_of(owner_id, auth.uid()));

-- routine_exercises mirror through the parent routine.
CREATE POLICY "trainer reads client routine exercises"
  ON public.routine_exercises FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_id AND private.is_trainer_of(r.owner_id, auth.uid())
  ));

CREATE POLICY "trainer writes prescription exercises"
  ON public.routine_exercises FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_id AND r.prescribed_by = auth.uid()
      AND private.is_trainer_of(r.owner_id, auth.uid())
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_id AND r.prescribed_by = auth.uid()
      AND private.is_trainer_of(r.owner_id, auth.uid())
  ));

-- ── Scope-gated reads ────────────────────────────────────────────────
CREATE POLICY "trainer reads client history"
  ON public.set_logs FOR SELECT TO authenticated
  USING (private.trainer_scope(user_id, auth.uid(), 'history'));

CREATE POLICY "trainer reads client records"
  ON public.personal_records FOR SELECT TO authenticated
  USING (private.trainer_scope(user_id, auth.uid(), 'stats'));

CREATE POLICY "trainer reads client body weight"
  ON public.body_weight_logs FOR SELECT TO authenticated
  USING (private.trainer_scope(user_id, auth.uid(), 'body_weight'));

CREATE POLICY "trainer reads client calendar"
  ON public.sessions FOR SELECT TO authenticated
  USING (private.trainer_scope(organizer_id, auth.uid(), 'calendar'));

-- Schedule WRITE authority (server-ready now; the booking UI rides the
-- week-series pass): a trainer may create scheduled sessions ON the
-- client's calendar — organizer stays the CLIENT so every downstream
-- surface treats it as the client's own booked lift.
CREATE POLICY "trainer books for client"
  ON public.sessions FOR INSERT TO authenticated
  WITH CHECK (private.trainer_scope(organizer_id, auth.uid(), 'calendar')
              AND state = 'scheduled');

-- ── T5: trainer notes — private to the trainer, never client-visible ──
CREATE TABLE public.trainer_notes (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  client_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body       text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.trainer_notes ENABLE ROW LEVEL SECURITY;

-- Reads/deletes survive an ended relationship (a trainer's own notebook
-- doesn't vanish when a client leaves); NEW notes need an active client.
CREATE POLICY "trainer owns own notes"
  ON public.trainer_notes FOR SELECT TO authenticated
  USING (trainer_id = auth.uid());

CREATE POLICY "trainer writes notes on active clients"
  ON public.trainer_notes FOR INSERT TO authenticated
  WITH CHECK (trainer_id = auth.uid()
              AND private.is_trainer_of(client_id, auth.uid()));

CREATE POLICY "trainer deletes own notes"
  ON public.trainer_notes FOR DELETE TO authenticated
  USING (trainer_id = auth.uid());
