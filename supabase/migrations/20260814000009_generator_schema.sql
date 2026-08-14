-- The generator schema wave (owner 2026-08-14: "build the Coach, the
-- Plan, creator programs, all the way down") — the keystone migration
-- every remaining arm hangs off.

-- ── 1. Rep ranges: the load-bearing primitive ────────────────────────
-- Double progression is undefined on a single number. Legacy target_reps
-- (text) stays for display back-compat; new writes fill all three.
ALTER TABLE public.routine_exercises
  ADD COLUMN IF NOT EXISTS target_reps_low integer,
  ADD COLUMN IF NOT EXISTS target_reps_high integer,
  ADD COLUMN IF NOT EXISTS cardio_zone integer,
  ADD COLUMN IF NOT EXISTS cardio_minutes integer;

-- ── 2. Profiles: the "about you" demographics ────────────────────────
-- birth_year retires the HR-max 190 placeholder (220 − age); sex feeds
-- the generator's PHYSIOLOGY deltas (fatigue resistance, reps-at-%1RM,
-- rest) — never exercise-selection stereotypes. All optional, skippable.
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS birth_year integer,
  ADD COLUMN IF NOT EXISTS height_in numeric(4,1),
  ADD COLUMN IF NOT EXISTS sex text;

-- ── 3. Program templates as DATA ─────────────────────────────────────
-- kind: overlay (prescriptions on YOUR routines) | takeover (ships its
-- own week). Metadata is globally readable (the store page); premium
-- WEEKS live in the child table behind the purchase gate.
CREATE TABLE public.program_templates (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  slug                text UNIQUE NOT NULL,
  name                text NOT NULL,
  summary             text NOT NULL DEFAULT '',
  kind                text NOT NULL DEFAULT 'takeover',   -- overlay | takeover
  focus_kind          text,                               -- strength|hypertrophy|weight_loss|conditioning
  sessions_per_week   integer NOT NULL DEFAULT 3,
  duration_weeks      integer NOT NULL DEFAULT 8,
  creator_id          uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  is_premium          boolean NOT NULL DEFAULT false,
  price_tier          text,
  storekit_product_id text,
  owner_id            uuid REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.program_template_weeks (
  template_id uuid PRIMARY KEY REFERENCES public.program_templates(id) ON DELETE CASCADE,
  weeks       jsonb NOT NULL DEFAULT '[]'
);

CREATE TABLE public.program_purchases (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  template_id    uuid NOT NULL REFERENCES public.program_templates(id) ON DELETE CASCADE,
  transaction_id text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, template_id)
);

ALTER TABLE public.program_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_template_weeks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.program_purchases ENABLE ROW LEVEL SECURITY;

-- Template METADATA: global read (store pages need premium titles too);
-- users own their generated templates; creator uploads are curated
-- server-side for now (invite-only rail — no self-serve INSERT policy
-- for creator rows).
CREATE POLICY "templates globally readable"
  ON public.program_templates FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "user manages own generated templates"
  ON public.program_templates FOR ALL TO authenticated
  USING (owner_id = auth.uid())
  WITH CHECK (owner_id = auth.uid() AND is_premium = false AND creator_id IS NULL);

-- WEEKS: the paywall line. Free templates open; premium requires a
-- purchase row (or ownership — your own generated weeks are yours).
CREATE POLICY "weeks readable when entitled"
  ON public.program_template_weeks FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.program_templates t
    WHERE t.id = template_id
      AND (t.is_premium = false
           OR t.owner_id = auth.uid()
           OR EXISTS (SELECT 1 FROM public.program_purchases p
                      WHERE p.template_id = t.id AND p.user_id = auth.uid()))
  ));

CREATE POLICY "user writes own template weeks"
  ON public.program_template_weeks FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.program_templates t
                 WHERE t.id = template_id AND t.owner_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.program_templates t
                      WHERE t.id = template_id AND t.owner_id = auth.uid()));

-- Purchases: readable by the buyer; INSERT rides the verify-entitlement
-- edge function (service role) — the M1 trust model, one writer.
CREATE POLICY "buyer reads own purchases"
  ON public.program_purchases FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- ── 4. The Plan: the macrocycle queue ────────────────────────────────
CREATE TABLE public.training_plan_entries (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  template_id uuid NOT NULL REFERENCES public.program_templates(id) ON DELETE CASCADE,
  position    integer NOT NULL,
  starts_on   date,
  status      text NOT NULL DEFAULT 'queued',   -- queued | active | complete
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.training_plan_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "user manages own plan"
  ON public.training_plan_entries FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Trainers with calendar scope manage the client's plan (T4 hook).
CREATE POLICY "trainer manages client plan"
  ON public.training_plan_entries FOR ALL TO authenticated
  USING (private.trainer_scope(user_id, auth.uid(), 'calendar'))
  WITH CHECK (private.trainer_scope(user_id, auth.uid(), 'calendar'));

-- ── 5. Movement-pattern classification (selection rule engine) ───────
-- Deterministic, name+muscle derived; 'other' is an honest fallback the
-- generator treats as accessory-only.
ALTER TABLE public.exercises
  ADD COLUMN IF NOT EXISTS movement_pattern text;

UPDATE public.exercises SET movement_pattern = CASE
  WHEN name ILIKE '%squat%' OR name ILIKE '%leg press%' THEN 'squat'
  WHEN name ILIKE '%deadlift%' OR name ILIKE '%hip thrust%' OR name ILIKE '%rdl%'
       OR name ILIKE '%good morning%' OR name ILIKE '%hip hinge%'
       OR name ILIKE '%glute bridge%' OR name ILIKE '%pull through%'
       OR name ILIKE '%back extension%' OR name ILIKE '%reverse hyper%' THEN 'hinge'
  WHEN name ILIKE '%lunge%' OR name ILIKE '%split squat%' OR name ILIKE '%step%up%' THEN 'lunge'
  WHEN (name ILIKE '%press%' OR name ILIKE '%push%up%' OR name ILIKE '%dip%' OR name ILIKE '%fly%')
       AND primary_muscle = 'chest' THEN 'push_horizontal'
  WHEN (name ILIKE '%press%' OR name ILIKE '%raise%' AND primary_muscle = 'shoulders')
       AND primary_muscle = 'shoulders' THEN 'push_vertical'
  WHEN name ILIKE '%row%' AND primary_muscle IN ('back','lats','traps') THEN 'pull_horizontal'
  WHEN (name ILIKE '%pulldown%' OR name ILIKE '%pull%up%' OR name ILIKE '%chin%up%'
        OR name ILIKE '%pullover%') THEN 'pull_vertical'
  ELSE NULL END
WHERE movement_pattern IS NULL;

UPDATE public.exercises
  SET movement_pattern = CASE
    WHEN category = 'isolation' THEN 'isolation'
    ELSE 'other' END
WHERE movement_pattern IS NULL;
