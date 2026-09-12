-- 20260912000002_workout_posts_is_late_trigger.sql
--
-- Spec: docs/superpowers/specs/2026-09-11-social-cards-design.md §2, §6.
-- Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, review fix 6.
--
-- `is_late` MOVES TO THE SERVER'S CLOCK.
--
-- Migration 20260912000001 kept spec §6's "is_late stays for old rows and is
-- derived for new ones" and put the derivation in the CLIENT
-- (`PostLateness.isLate`, plan task S2.0). That was half right and half
-- inconsistent: the client derived the boolean from the DEVICE clock, while
-- the tag the card prints beside it — "posted 47 min after" — is computed
-- from `created_at`, which is the SERVER's `now()`. Two clocks, one fact. A
-- device an hour fast wrote `is_late = true` onto a post whose own timestamps
-- said it was prompt, and nothing in the row disagreed with itself loudly
-- enough to be noticed.
--
-- So the derivation happens here, at INSERT, against the same clock that
-- stamps `created_at`.
--
-- STILL NOT A GENERATED COLUMN, for the reason 20260912000001 gives: turning
-- a populated boolean into a generated one means dropping it, which would
-- erase what every row written before 2026-09 says about itself. A BEFORE
-- INSERT trigger changes new rows only and touches no existing one.
--
-- THE NULL BRANCH IS THE CONTRACT, not an oversight. A row with no
-- `completed_at` keeps whatever the client sent, because there is nothing to
-- measure from and the composer's capture-time flag is the only honest signal
-- an old caller has. Guessing `false` there would quietly un-late a genuinely
-- late post.
--
-- SIXTY SECONDS IS SPELLED TWICE, in two languages: here, and as
-- `PostLateness.windowSeconds` in Swift (which the composer's countdown and
-- the card's tag both read). There is no way to share one literal across the
-- wire; if this window ever moves, both move together.
--
-- Idempotent (OR REPLACE + DROP IF EXISTS), the house style
-- (20260717000004_curator_guard_trigger.sql:18-21).

CREATE OR REPLACE FUNCTION public.workout_posts_derive_is_late()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.completed_at IS NOT NULL THEN
    NEW.is_late := (now() - NEW.completed_at) > interval '60 seconds';
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.workout_posts_derive_is_late() IS
  'Spec 2: is_late is elapsed time from the session''s completion to the post, measured on the SERVER''s clock so it agrees with created_at and with the "posted 47 min after" tag the card renders. Rows with no completed_at keep the client''s capture-time flag - there is nothing to measure from, and guessing false would un-late a genuinely late post.';

DROP TRIGGER IF EXISTS workout_posts_derive_is_late ON public.workout_posts;
CREATE TRIGGER workout_posts_derive_is_late
  BEFORE INSERT ON public.workout_posts
  FOR EACH ROW EXECUTE FUNCTION public.workout_posts_derive_is_late();

COMMENT ON COLUMN public.workout_posts.is_late IS
  'Whether the post came more than 60 s after the session ended. DERIVED BY THE SERVER at INSERT (workout_posts_derive_is_late) whenever completed_at is present, so it agrees with created_at rather than with the posting device''s clock. When completed_at is NULL the client''s capture-time flag is kept. Rows written before 2026-09 carry the old client-side boolean and are not rewritten.';
