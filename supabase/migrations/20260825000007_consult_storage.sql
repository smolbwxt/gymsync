-- Consult prerequisites (2026-08-25): the two things the consult learns
-- that TrainingProfile cannot hold.
--
-- Both were built consumer-first, which is why neither had a home:
-- HealthTriage can refuse to program but nothing recorded that it ever
-- asked, and generatorInputs() READS standing rules (advisoryNotes) that
-- nothing could write — those notes are derived fresh from profile state
-- every call, so "pulls before arms, always" had literally nowhere to
-- live.

-- ── Health screening state ────────────────────────────────────────────
-- One row per athlete. `answers` holds the PAR-Q+ general-question ids
-- mapped to booleans; the app's HealthTriage.evaluate is the only thing
-- that interprets them, so the shape stays open rather than one column
-- per question (the instrument gets revised; our schema should not have
-- to).
CREATE TABLE public.health_screenings (
  user_id     uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  answers     jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- NULL means never cleared. Distinct from a stale clearance, which the
  -- client detects by age — PAR-Q+ clearance lapses at 12 months.
  cleared_at  timestamptz,
  -- pregnant | postpartum | NULL. Advisory, never a block (ACOG 804).
  life_stage  text CHECK (life_stage IN ('pregnant', 'postpartum')),
  -- Set when the athlete says a clinician cleared them after a refer-out.
  clinician_cleared boolean NOT NULL DEFAULT false,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.health_screenings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own screening"
  ON public.health_screenings FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- ── Standing rules ────────────────────────────────────────────────────
-- Durable, athlete-authored constraints that outlive a block: "pulls
-- before arms", "keep Saturdays light", "never overhead barbell". They
-- feed BOTH the generator's advisory notes and Coach's instruction rail,
-- which is why they are rows rather than a profile string — Coach needs
-- to cite one, and the athlete needs to retire one.
CREATE TABLE public.training_rules (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  rule       text NOT NULL CHECK (length(btrim(rule)) BETWEEN 1 AND 280),
  -- Where it came from, so Coach knows how freely it may challenge it —
  -- the same doctrine FieldProvenance already encodes for profile fields.
  source     text NOT NULL DEFAULT 'consult'
             CHECK (source IN ('consult', 'chat', 'manual')),
  active     boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX training_rules_user_active
  ON public.training_rules (user_id, active, created_at DESC);

ALTER TABLE public.training_rules ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own rules"
  ON public.training_rules FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.health_screenings_touch()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER health_screenings_touch
  BEFORE UPDATE ON public.health_screenings
  FOR EACH ROW EXECUTE FUNCTION public.health_screenings_touch();
