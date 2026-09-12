-- 20260912000003_workout_posts_is_late_created_at.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §2, §6.
-- Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, review fix 6.
--
-- FINAL REVIEW FIX ON 20260912000002: STILL THE WRONG CLOCK, ONE STEP CLOSER.
--
-- 20260912000002 moved `is_late` off the CLIENT's clock and onto the
-- SERVER's, comparing `now() - NEW.completed_at`. That fixed the case that
-- migration set out to fix, but `now()` here means "the instant this
-- statement runs" — a THIRD value, distinct from both `completed_at` and
-- `created_at`, that happens to equal `created_at` only when `created_at` is
-- left to its column default. It stops being the same value the moment a
-- caller sets `created_at` explicitly.
--
-- A caller does exactly that: `scripts/seed_qa_fixtures.js`'s pump-check
-- fixture writes `created_at` and `completed_at` both, deliberately, so a
-- re-run pins the card at "posted 47 min after" instead of a gap that grows
-- by however long it has been since the last seed (review fix 11a there,
-- :1146-1150). The client's tag (`PostLateness.tag`) reads that same
-- `created_at` column. `now()` at INSERT time is neither column — it is
-- whatever instant Postgres happens to process the statement at, which for a
-- backdated seed row is not the instant the row claims to represent.
-- 20260912000002's boolean survives this particular fixture's numbers by
-- coincidence (both readings clear the 60 s bar — 47 min the tag's way,
-- ~107 min the old trigger's way), but the trigger and the tag are measuring
-- two different durations, and a fixture with a smaller gap would not be so
-- lucky.
--
-- So the comparison moves one column over: `NEW.created_at` in place of
-- `now()`. This is safe unconditionally, seeded row or not, because Postgres
-- applies COLUMN DEFAULTS before BEFORE-ROW triggers run —
-- `created_at timestamptz NOT NULL DEFAULT now()`
-- (20260731000001_workout_posts.sql:38) has already been substituted into
-- NEW by the time this function sees it, whether the caller supplied a value
-- or fell through to the default. There is no path where NEW.created_at is
-- NULL here, seeded or not.
--
-- Idempotent (OR REPLACE), the house style
-- (20260717000004_curator_guard_trigger.sql:18-21). The trigger and the
-- column comment are 20260912000002's and stay there untouched — CREATE
-- TRIGGER binds to the function by name, so replacing the function's body is
-- enough to change what the existing trigger does. Do not edit
-- 20260912000002 itself; this migration supersedes only the function body.

CREATE OR REPLACE FUNCTION public.workout_posts_derive_is_late()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.completed_at IS NOT NULL THEN
    NEW.is_late := (NEW.created_at - NEW.completed_at) > interval '60 seconds';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.workout_posts_derive_is_late() IS
  'Spec 2: is_late is elapsed time from the session''s completion to the post, measured as created_at − completed_at so it always agrees with the "posted 47 min after" tag the card renders from those same two columns, defaulted or explicit alike. Rows with no completed_at keep the client''s capture-time flag - there is nothing to measure from, and guessing false would un-late a genuinely late post.';
