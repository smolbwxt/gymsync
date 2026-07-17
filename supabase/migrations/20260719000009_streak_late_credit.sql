-- ============================================================
-- Fix-forward for 20260719000006_streaks.sql / 20260719000007_streak_
-- trigger_race_fixes.sql (both already applied to the live DB — applied
-- migrations are append-only in this repo, so this ships as a NEW migration
-- that CREATE OR REPLACEs streak_on_session_state_change() rather than
-- editing either prior file in place). Lineage: 006 (original trigger) ->
-- 007 (FOR UPDATE serialization + broken_by_session_id guard) -> this
-- migration (readiness predicate widened to include 'late').
-- ============================================================
--
-- ── THE USER DECISION (2026-07-16, binding) ─────────────────────────────────
-- The design doc self-conflicts on whether a LATE-but-completed session
-- earns streak credit:
--   • Flow 7's individual rule (docs/superpowers/specs/2026-06-28-gymsync-
--     design.md:843): "reached `state='completed'` with your
--     `check_in_state='ready'` at end" — literally reads as 'ready' ONLY,
--     which would exclude 'late'.
--   • Flow 7's group rule (same file:850): "every invited participant
--     having `check_in_state='ready'`" — same literal 'ready'-only reading.
--   • The §Streaks schema comment (same file:558), sitting directly above
--     the `user_streaks` table definition: "consecutive *planned* sessions
--     ... that were completed WITHOUT A NO_SHOW for you (or everyone, for
--     group streaks)" — this reading only excludes no_show, and by
--     omission would INCLUDE 'late' (a `late` row is present, not absent —
--     the same check_in_at-vs-state-label distinction this migration
--     pipeline already relies on for the abandoned-branch absence check,
--     see 20260719000004_mark_no_shows_absence_fix.sql and 20260719000006's
--     Carol fixture).
-- Same document, two irreconcilable predicates for the same rule — the
-- 'ready'-only reading (843/850) and the 'without a no_show' reading (558)
-- produce different behavior for exactly the 'late' case and agree on
-- everything else (no_show and never-checked-in are excluded under BOTH
-- readings).
--
-- The user resolved this directly, out of band from the design doc, on
-- 2026-07-16: LATE COUNTS. New predicate for streak credit, both at the
-- individual level and at the group all-ready level: `check_in_state IN
-- ('ready', 'late')`. `no_show` and never-checked-in (`'invited'`/
-- `'online'` with no terminal check-in) remain excluded under the new
-- predicate exactly as they were under the old one — this migration does
-- not touch the no_show or abandoned-branch logic at all, only widens what
-- counts as "present" for the completed-branch readiness checks.
--
-- Rationale (user-supplied, recorded verbatim in intent): lateness is
-- already priced by burpees (the late-penalty mechanic introduced in
-- 20260719000003_mark_no_shows.sql / burpee_ledger — showing up late costs
-- you compounding burpees per Flow 6, design doc:815 "burpees compound").
-- Double-punishing the same lateness a second time via the streak — on top
-- of the burpee cost already paid — was never clearly an intended design
-- goal; the schema comment's "without a no_show" phrasing (558) supports
-- reading the streak rule as "showed up at all" rather than "showed up
-- exactly on time," and that is the reading the user chose to ship.
--
-- Consistency: the same widened predicate is applied in BOTH places the old
-- 'ready'-only check appeared — the individual per-participant loop AND the
-- group all-ready check. A late-but-present group member no longer blocks
-- the rest of the group's increment either; the principle (late = present,
-- not absent, for streak purposes) is applied uniformly rather than only
-- fixing the individual case and leaving the group case inconsistent with
-- it.
--
-- ── SCOPE: touches ONLY the two readiness predicates ────────────────────────
-- Everything else in streak_on_session_state_change() is carried forward
-- byte-for-byte from 20260719000007's body:
--   • The Finding 1(a) `FOR UPDATE` lock on session_participants before
--     evaluating readiness (serializes against a concurrent mark_no_shows()
--     tick) — unchanged.
--   • The Finding 1(b) `broken_by_session_id` guard inside streak_bump_user/
--     streak_bump_group (not touched by this migration at all — those two
--     functions are not redefined here since neither of their bodies
--     references 'ready' or the readiness predicate).
--   • The `last_streak_session_id` idempotency guard inside
--     streak_bump_user/streak_bump_group — likewise untouched, same reason.
--   • The `abandoned` branch's absence logic (`check_in_at IS NULL`,
--     including Finding 2's defensive group break) — completely untouched;
--     "late but present at an abandoned session" was already handled
--     correctly (Carol's fixture in 20260719000006 already proves a `late`
--     row with `check_in_at` set does NOT break on abandon) and this
--     migration does not touch that branch at all.
-- The diff against 007's body is exactly two lines:
--   (1) the individual loop's `sp.check_in_state = 'ready'`
--       -> `sp.check_in_state IN ('ready', 'late')`
--   (2) the group all-ready check's `COALESCE(sp.check_in_state, 'invited')
--       <> 'ready'` -> `... NOT IN ('ready', 'late')`
-- ============================================================

CREATE OR REPLACE FUNCTION public.streak_on_session_state_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec         RECORD;
  v_all_ready boolean;
BEGIN
  IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
    RETURN NEW;
  END IF;
  IF NEW.state NOT IN ('completed', 'abandoned') THEN
    RETURN NEW;
  END IF;
  IF NEW.scheduled_for IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.state = 'completed' THEN
    -- Finding 1(a) fix-forward (unchanged from 007): lock this session's
    -- session_participants rows BEFORE evaluating readiness, so this
    -- transaction serializes against a concurrent mark_no_shows() tick
    -- touching the same rows — same pattern as advance_turn's session-row
    -- FOR UPDATE (20260714000001_session_engine_rpcs.sql:151-156, "Lock the
    -- session row to serialize concurrent advances"). This closes the pure
    -- concurrency window; the sequential no_show-then-rejoin case is closed
    -- separately by the broken_by_session_id guard in streak_bump_user/
    -- streak_bump_group (Finding 1(b), 20260719000007 — not modified here).
    PERFORM 1 FROM public.session_participants
      WHERE session_id = NEW.id
      FOR UPDATE;

    -- Individual: every participant whose OWN row is 'ready' OR 'late' at
    -- completion increments, independent of everyone else's state.
    -- Widened per the 2026-07-16 user decision (see header above): late-
    -- but-present now counts the same as on-time-ready — lateness is
    -- already priced via burpees, so it is not double-punished here too.
    -- 'no_show' and never-checked-in ('invited'/'online') remain excluded,
    -- exactly as under the prior 'ready'-only predicate.
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_state IN ('ready', 'late')
    LOOP
      PERFORM public.streak_bump_user(rec.user_id, NEW.id);
    END LOOP;

    -- Group: only if EVERY invited participant (every session_participants
    -- row for this session) is ready OR late — no no_shows and nobody who
    -- never checked in at all anywhere in the roster. Same 2026-07-16
    -- widening applied here as in the individual loop above, for
    -- consistency: a late-but-present group member no longer blocks the
    -- rest of the group's increment either.
    IF NEW.group_id IS NOT NULL THEN
      SELECT NOT EXISTS (
        SELECT 1 FROM public.session_participants sp
        WHERE sp.session_id = NEW.id
          AND COALESCE(sp.check_in_state, 'invited') NOT IN ('ready', 'late')
      ) INTO v_all_ready;

      IF v_all_ready THEN
        PERFORM public.streak_bump_group(NEW.group_id, NEW.id);
      END IF;
    END IF;

  ELSIF NEW.state = 'abandoned' THEN
    -- Untouched by this migration. Breaks every invited participant who
    -- never checked in at all. Absence predicate per the mark_no_shows
    -- Finding-1 lesson (20260719000004_mark_no_shows_absence_fix.sql):
    -- check_in_at IS NULL, never a state-label ('invited'/'online'/'late')
    -- guess — a 'late' row WITH check_in_at set means present, not absent.
    -- This is exactly why 'late' already survived `abandoned` correctly
    -- before this migration (20260719000006's Carol fixture) — only the
    -- `completed` branch's readiness predicates needed widening.
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_at IS NULL
    LOOP
      PERFORM public.streak_break_user(rec.user_id, NEW.id);
    END LOOP;

    -- Finding 2 fix-forward (unchanged from 007): defensive group break,
    -- same absence predicate discipline as the individual loop above.
    -- Unconditional re-apply is a documented no-op (streak_break_group's
    -- own header in 20260719000006), so this is safe even when a no_show
    -- already broke the group for this exact session.
    IF NEW.group_id IS NOT NULL AND EXISTS (
      SELECT 1 FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_at IS NULL
    ) THEN
      PERFORM public.streak_break_group(NEW.group_id, NEW.id);
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

-- No trigger re-creation needed: streak_on_session_completion already
-- dispatches by function name (set in 20260719000006), so CREATE OR REPLACE
-- FUNCTION alone is enough for it to pick up the new body on its very next
-- fire — same reasoning 20260719000007 used for this exact function and
-- 20260719000004 used for mark_no_shows()'s cron job.
