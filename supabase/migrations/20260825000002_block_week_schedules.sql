-- Per-week block schedules (owner 2026-08-25: "each week can carry its
-- own schedule"). Until now a block's rhythm lived in ONE SessionSeries
-- — a single recurring weekday pattern for the whole block — so a week
-- that needed different days had nowhere to be stored. The week sheet
-- deliberately shipped read-only rather than fake an editor that would
-- silently drop its edits; this table is what makes it real.
--
-- Shape: an OVERRIDE per (enrollment, week). A week with no row inherits
-- the block's default pattern, so an eight-week block that never varies
-- stores nothing at all and behaves exactly as before.
--
-- weekdays uses Calendar's own convention (1 = Sunday … 7 = Saturday),
-- matching `Calendar.component(.weekday:)` on the client. Storing ISO
-- days here would mean a silent ±1 every time the client reads it back.

CREATE TABLE public.block_week_schedules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  enrollment_id uuid NOT NULL REFERENCES public.program_enrollments(id) ON DELETE CASCADE,
  week_number   integer NOT NULL CHECK (week_number BETWEEN 1 AND 52),
  weekdays      smallint[] NOT NULL DEFAULT '{}',
  hour          smallint NOT NULL DEFAULT 18 CHECK (hour BETWEEN 0 AND 23),
  minute        smallint NOT NULL DEFAULT 0 CHECK (minute BETWEEN 0 AND 59),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT block_week_schedules_weekdays_valid
    CHECK (weekdays <@ ARRAY[1,2,3,4,5,6,7]::smallint[]),
  CONSTRAINT block_week_schedules_one_per_week
    UNIQUE (enrollment_id, week_number)
);

CREATE INDEX block_week_schedules_enrollment
  ON public.block_week_schedules (enrollment_id, week_number);

ALTER TABLE public.block_week_schedules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "own week schedules"
  ON public.block_week_schedules FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- updated_at maintenance: the sheet upserts the same row repeatedly as
-- the athlete toggles days, and recency is what the calendar sorts by.
CREATE OR REPLACE FUNCTION public.block_week_schedules_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER block_week_schedules_touch
  BEFORE UPDATE ON public.block_week_schedules
  FOR EACH ROW EXECUTE FUNCTION public.block_week_schedules_touch();
