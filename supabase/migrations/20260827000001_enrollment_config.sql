-- The frozen build-time snapshot the ledger's provenance view reads.
--
-- Owner 2026-08-27: the current program's page should offer "the five
-- doors and options that led to the creation of the program" - behind a
-- button, because "it isn't necessarily something that a user is going
-- to want to look at every single time".
--
-- Nothing froze this before: TrainingProfile is ONE live row overwritten
-- by every consult and every build, and the wizard's Inputs died with
-- the screen. So the options that built block N were unknowable the
-- moment block N+1 was tuned. The enrollment is the natural home - it is
-- already the frozen record of the block (slug, focus, baseline,
-- started_on) and history rows accumulate by design.
--
-- jsonb text map rather than columns: the digest's shape follows the
-- wizard's dials, and a new dial must not need a migration. Nullable -
-- every existing enrollment predates the snapshot, and the ledger says
-- so honestly rather than inventing a past.
ALTER TABLE public.program_enrollments
  ADD COLUMN IF NOT EXISTS config jsonb;
