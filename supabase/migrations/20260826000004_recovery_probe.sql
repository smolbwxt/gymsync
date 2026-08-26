-- Recovery probe (owner 2026-08-26): "we should have a probe after every
-- session talking about recovery from the previous routine and track it
-- until recovered."
--
-- WHY DURATION AND NOT SORENESS. A one-shot "are you sore?" measures
-- presence. What decides whether a dose exceeded someone's recovery
-- capacity is DURATION: whether they came back for the next session for
-- that muscle still carrying the last one. So a probe opens after a
-- session, stays open, and is re-asked until the athlete says recovered.
-- The answer we actually want is the number of days that took.
--
-- That number is the leading indicator for the volume search. Recovered
-- well before the next session for that muscle means there is room to add;
-- still carrying it when the next session arrives means the dose is at or
-- past capacity.
--
-- Per MUSCLE, not per session, because that is the granularity the
-- corpus's own rule works at: "distinct performance decline across two
-- consecutive sessions FOR A MUSCLE GROUP signals it has hit maximum
-- recoverable volume; response is to cut THAT MUSCLE GROUP's volume."
CREATE TABLE public.recovery_probes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  -- The session whose work this probe is asking about.
  session_id   uuid REFERENCES public.sessions(id) ON DELETE CASCADE,
  -- Lowercased primary muscle, matching GeneratorScience.majorMuscles so an
  -- answer always lands on something the generator can act on.
  muscle       text NOT NULL,
  -- When the work being recovered FROM was done. The clock starts here,
  -- not when we first ask.
  trained_at   timestamptz NOT NULL,
  -- NULL while still recovering. Set once the athlete says they are back.
  recovered_at timestamptz,
  -- The athlete's own last answer: fresh | tender | sore | wrecked.
  -- Kept even after recovery, because "it took 3 days and it was WRECKED"
  -- and "it took 3 days and it was tender" are different doses.
  last_state   text CHECK (last_state IN ('fresh', 'tender', 'sore', 'wrecked')),
  asked_count  integer NOT NULL DEFAULT 0,
  last_asked_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- The hot query: "what is still open for this athlete?"
CREATE INDEX recovery_probes_open
  ON public.recovery_probes (user_id, recovered_at, muscle)
  WHERE recovered_at IS NULL;

-- And the titration read: recent closed probes for one muscle.
CREATE INDEX recovery_probes_history
  ON public.recovery_probes (user_id, muscle, trained_at DESC);

ALTER TABLE public.recovery_probes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own recovery probes"
  ON public.recovery_probes FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Per-muscle volume the titration has settled on.
--
-- Separate from training_profiles because it is DERIVED and per muscle,
-- and because it changes on a different clock than anything the athlete
-- typed. The profile holds what they asked for; this holds what their body
-- answered.
CREATE TABLE public.volume_targets (
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  muscle       text NOT NULL,
  weekly_sets  integer NOT NULL CHECK (weekly_sets BETWEEN 1 AND 60),
  -- Why it last moved, in the athlete's language, so Coach can cite it.
  reason       text,
  updated_at   timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, muscle)
);

ALTER TABLE public.volume_targets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "own volume targets"
  ON public.volume_targets FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
