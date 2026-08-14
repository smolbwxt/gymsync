-- Set structures (owner 2026-08-13/14): drop sets, supersets, burnouts,
-- and prescribed failure — the prescription-side schema. Shipped ahead of
-- the generator wave (owner: "haven't shipped yet?" — unbatched).
--
-- routine_exercises grows the structure prescription:
--   set_type       'straight' (default) | 'drop' | 'burnout'
--   superset_group exercises sharing a group number alternate as a pair
--   drop_steps / drop_percent  the drop prescription ("drop 2×20%")
--   target_failure the final set is PRESCRIBED to failure — rep target
--                  renders "TO FAILURE", and per the failure doctrine a
--                  prescribed failure is the assignment fulfilled (never
--                  a stall signal)
ALTER TABLE public.routine_exercises
  ADD COLUMN IF NOT EXISTS set_type text NOT NULL DEFAULT 'straight',
  ADD COLUMN IF NOT EXISTS superset_group integer,
  ADD COLUMN IF NOT EXISTS drop_steps integer,
  ADD COLUMN IF NOT EXISTS drop_percent numeric(5,2),
  ADD COLUMN IF NOT EXISTS target_failure boolean NOT NULL DEFAULT false;

-- Drop-set segments (owner decision: NESTED sub-rows, not consecutive
-- set rows): one parent set_logs row per drop set, segments carrying the
-- weight ladder ("225→180→145"). Created now so the logging phase needs
-- no second migration; volume/trigger integration lands with that phase.
CREATE TABLE IF NOT EXISTS public.set_log_segments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_log_id    uuid NOT NULL REFERENCES public.set_logs(id) ON DELETE CASCADE,
  segment_index integer NOT NULL,
  weight        numeric(7,2),
  reps          integer,
  UNIQUE (set_log_id, segment_index)
);

ALTER TABLE public.set_log_segments ENABLE ROW LEVEL SECURITY;

-- Read: wherever the PARENT set log is visible to you. The EXISTS
-- subquery runs under set_logs' own RLS for the caller, so segment
-- visibility exactly inherits set-log visibility (own sets, crew
-- sessions you can see) with zero duplicated policy logic.
CREATE POLICY "segments visible with their set log"
  ON public.set_log_segments FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.set_logs sl WHERE sl.id = set_log_id
  ));

-- Write: only onto your OWN set logs.
CREATE POLICY "segments writable on own set logs"
  ON public.set_log_segments FOR INSERT TO authenticated
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.set_logs sl
    WHERE sl.id = set_log_id AND sl.user_id = auth.uid()
  ));

CREATE POLICY "segments updatable on own set logs"
  ON public.set_log_segments FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.set_logs sl
    WHERE sl.id = set_log_id AND sl.user_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.set_logs sl
    WHERE sl.id = set_log_id AND sl.user_id = auth.uid()
  ));

CREATE POLICY "segments deletable on own set logs"
  ON public.set_log_segments FOR DELETE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.set_logs sl
    WHERE sl.id = set_log_id AND sl.user_id = auth.uid()
  ));
