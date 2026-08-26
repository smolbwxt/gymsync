-- Standing rules gain a STRUCTURED READING, so the generator can act on
-- one instead of only quoting it back.
--
-- Owner 2026-08-26: "Much like unanswered research, we should have
-- unfulfilled request log that we then accumulate parts and upgrade the
-- generator to account for in the future."
--
-- The shape deliberately mirrors corpus_misses, which does the same job
-- for questions Coach could not answer: the athlete's ask is recorded
-- verbatim, a dev-facing queue accumulates what keeps being asked for,
-- and when the capability lands the athlete is told it came back.
--
-- WHAT IS NOT STORED HERE, and this is the whole design decision:
-- there is no `buildable` or `status` column saying whether Coach can
-- honour the rule. That is not a fact about the rule - it is a fact
-- about the generator, and it changes every time a lever ships. Storing
-- it would freeze each rule at the capability level of whatever app
-- version recorded it, and a new lever would need a backfill to reach
-- rules typed before it existed.
--
-- So we store the INTENT (what the athlete meant) and derive buildability
-- at read time from the levers this build actually has (RuleIntent in
-- Swift). Ship a lever, and every rule ever recorded with that intent
-- becomes live at once, including ones typed months earlier.

ALTER TABLE public.training_rules
  -- What the athlete meant, as classified by the on-device model and
  -- CONFIRMED by the athlete. 'unknown' is the honest default and the
  -- most important value in the column: it is the demand signal for
  -- which levers to build next.
  ADD COLUMN IF NOT EXISTS intent text NOT NULL DEFAULT 'unknown',
  -- Structured parameters for the intent, e.g.
  --   {"exercise_id": "...", "exercise_name": "Push-Up"}
  -- jsonb rather than columns because each intent needs different slots,
  -- and a new intent should not need a migration.
  ADD COLUMN IF NOT EXISTS slots jsonb,
  -- When a generated block last ACTED on this rule. NULL means the rule
  -- is still waiting - either because no lever exists yet, or because
  -- one now does and the athlete has not rebuilt since.
  --
  -- This is what lets the athlete be told "Coach can do this now",
  -- exactly as corpus_misses.status='researched' powers "the research
  -- came back".
  ADD COLUMN IF NOT EXISTS applied_at timestamptz,
  -- Did the athlete AGREE with how Coach read their rule?
  --
  -- Unlike buildability, this IS a fact about the rule and belongs in the
  -- row. A misread rule is worse than an unread one: it silently changes
  -- training the athlete never asked to change. So a lever fires only for
  -- a reading they confirmed, and an unconfirmed rule behaves exactly
  -- like an unbuildable one until they say yes.
  ADD COLUMN IF NOT EXISTS confirmed boolean NOT NULL DEFAULT false;

-- The dev-facing demand signal: what athletes keep asking for that no
-- lever covers. Reads via service role, same as the corpus_misses queue.
CREATE INDEX IF NOT EXISTS training_rules_unbuilt
  ON public.training_rules (intent, created_at DESC)
  WHERE active AND applied_at IS NULL;
