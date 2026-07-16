-- ============================================================
-- Fix-forward for 20260719000006_streaks.sql (already applied to the live
-- DB — applied migrations are append-only in this repo, so this ships as a
-- NEW migration that CREATE OR REPLACEs the three affected functions rather
-- than editing 20260719000006 in place).
-- ============================================================
--
-- ── FINDING 1 (Important): completion/no_show race can re-credit a
--    just-broken streak ─────────────────────────────────────────────────────
-- streak_on_session_state_change()'s 'completed' branch evaluates readiness
-- with plain, non-locking SELECTs on session_participants. mark_no_shows()
-- (20260719000003/…004) runs in its own transaction on a per-minute cron and
-- writes check_in_state = 'no_show' to that same table, which fires
-- streak_on_no_show() -> streak_break_user()/streak_break_group().
--
-- Two distinct gaps, both closed here:
--
-- (a) Genuine concurrency: an End-Session completion and a mark_no_shows()
--     tick can be in-flight at the same time. Nothing today forces the
--     completion trigger's readiness read to wait for (or be waited on by) a
--     concurrent no_show UPDATE touching the same session's rows, so the two
--     writers are not serialized against each other at all. Fix: take
--     `SELECT ... FOR UPDATE` on the session's session_participants rows
--     BEFORE evaluating readiness — the same serialization pattern
--     advance_turn already uses to guard against concurrent advances
--     (20260714000001_session_engine_rpcs.sql:151-156, "Lock the session row
--     to serialize concurrent advances"). Here we lock the participant rows
--     instead of the session row, since those are the rows mark_no_shows()
--     writes.
--
-- (b) The sequential case FOR UPDATE cannot fix: Flow 6's own no_show-rejoin
--     path (20260719000003's header: "the EXISTING check-in path already
--     permits a no_show -> ready flip with zero code changes") means a
--     participant can be broken by session X's no_show flip and then
--     legitimately re-check-in ('ready') for that SAME session X before it
--     completes. By the time the completion trigger runs, her row really is
--     'ready' — not a stale read — so no amount of locking stops the
--     readiness loop from picking her up. streak_bump_user's existing guard
--     (`last_streak_session_id <> p_session_id`) does not help either: a
--     break never touches last_streak_session_id, so the guard still passes
--     and the bump would silently re-credit current_streak using the exact
--     session that just broke it (broken_by_session_id = X and
--     last_streak_session_id = X simultaneously, current back at 1 — the
--     "silently re-crediting the no_show'd session" scenario named in the
--     review finding). Fix: streak_bump_user/streak_bump_group both grow a
--     second guard — if broken_by_session_id already equals the session
--     being credited, the bump is skipped. A session that broke a streak can
--     never be the session that revives it. This is the minimal additional
--     guard the review anticipated ("if broken_by = the same session being
--     credited, skip the bump") once (a) alone was checked against the
--     rejoin sequence and found insufficient.
--
-- ── FINDING 2 (Important): group streak's abandoned gap ────────────────────
-- streak_on_session_state_change()'s 'abandoned' branch only ever calls
-- streak_break_user — 20260719000006's own header documents this as
-- deliberate, citing Flow 7's literal asymmetry (individual: no_show OR
-- abandoned-without-checkin; group: no_show only) and arguing it's a
-- no-op distinction today because mark_no_shows()'s ~15-minute default
-- no-show threshold is far shorter than the 6-hour auto-abandon window
-- (20260716000004_reminder_window_fix.sql), so any group session reaching
-- 'abandoned' has already had its absent members (and therefore the group)
-- broken by the no_show flip first.
-- That ordering is real today but nothing enforces it structurally: it's an
-- unvalidated organizer-configurable threshold
-- (late_penalty->>'no_show_after_minutes', introduced in 20260719000003) vs.
-- a fixed constant, and no write path exists yet to change either bound —
-- but "no write path yet" is not the same as "can never regress." If a
-- future change ever pushes the no-show threshold at or past the abandon
-- window, a group session could reach 'abandoned' with an absent member who
-- was NEVER flipped to no_show, and the group streak would never break.
-- Fix: add a defensive streak_break_group call to the 'abandoned' branch,
-- gated on the exact same absence predicate already used for the individual
-- loop (`check_in_at IS NULL` — the mark_no_shows Finding-1 lesson,
-- 20260719000004: absence is check_in_at IS NULL, never a state-label
-- guess). This removes the ordering dependency the 006 header relied on:
-- the group streak now breaks on a bare abandoned transition even if no
-- no_show ever fired first.
-- Idempotency: streak_break_group is already documented as safe to
-- re-apply — 20260719000006's own header on the break primitives: "re-
-- applying the same break twice is a harmless no-op (0 -> 0, same
-- broken_by_session_id written again)". Verified (not just asserted) by the
-- streaks_test.sql "Gap Crew 2" case added alongside this migration: a
-- session whose absent member is flipped to no_show first (existing
-- mechanism) and then reaches 'abandoned' (this new defensive call) ends up
-- in the identical broken state either write produces alone. No additional
-- guard was needed here.
-- ============================================================

-- ── 1. streak_bump_user / streak_bump_group — broken_by_session_id guard ──
CREATE OR REPLACE FUNCTION public.streak_bump_user(p_user_id uuid, p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_current    integer;
  v_longest    integer;
  v_last       uuid;
  v_broken_by  uuid;
BEGIN
  INSERT INTO public.user_streaks (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT current_streak, longest_streak, last_streak_session_id, broken_by_session_id
    INTO v_current, v_longest, v_last, v_broken_by
    FROM public.user_streaks
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF v_last IS NOT DISTINCT FROM p_session_id THEN
    RETURN;  -- already credited for this exact session
  END IF;

  -- Finding 1(b) fix-forward: a session that already broke this streak can
  -- never be the session that re-credits it. Without this guard, a no_show
  -- -> late-rejoin -> completed-ready sequence for the SAME session (Flow 6
  -- explicitly allows the rejoin) would pass the last_streak_session_id
  -- guard above untouched (breaks never write that column) and silently
  -- bump current_streak back up using the very session recorded in
  -- broken_by_session_id.
  IF v_broken_by IS NOT DISTINCT FROM p_session_id THEN
    RETURN;
  END IF;

  v_current := COALESCE(v_current, 0) + 1;
  v_longest := GREATEST(COALESCE(v_longest, 0), v_current);

  UPDATE public.user_streaks
  SET current_streak = v_current,
      longest_streak = v_longest,
      last_streak_session_id = p_session_id
  WHERE user_id = p_user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.streak_bump_group(p_group_id uuid, p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_current    integer;
  v_longest    integer;
  v_last       uuid;
  v_broken_by  uuid;
BEGIN
  INSERT INTO public.group_streaks (group_id) VALUES (p_group_id)
    ON CONFLICT (group_id) DO NOTHING;

  SELECT current_streak, longest_streak, last_streak_session_id, broken_by_session_id
    INTO v_current, v_longest, v_last, v_broken_by
    FROM public.group_streaks
    WHERE group_id = p_group_id
    FOR UPDATE;

  IF v_last IS NOT DISTINCT FROM p_session_id THEN
    RETURN;
  END IF;

  -- Same broken_by_session_id guard as streak_bump_user — see Finding 1(b)
  -- above. Symmetric because the group readiness check races
  -- mark_no_shows() the same way the individual loop does.
  IF v_broken_by IS NOT DISTINCT FROM p_session_id THEN
    RETURN;
  END IF;

  v_current := COALESCE(v_current, 0) + 1;
  v_longest := GREATEST(COALESCE(v_longest, 0), v_current);

  UPDATE public.group_streaks
  SET current_streak = v_current,
      longest_streak = v_longest,
      last_streak_session_id = p_session_id
  WHERE group_id = p_group_id;
END;
$$;

-- No REVOKE re-run needed: CREATE OR REPLACE preserves the existing REVOKE
-- EXECUTE grants set in 20260719000006 (same idiom already used by
-- 20260719000004's mark_no_shows fix-forward).

-- ── 2. streak_on_session_state_change — FOR UPDATE lock + group abandon ───
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
    -- Finding 1(a) fix-forward: lock this session's session_participants
    -- rows BEFORE evaluating readiness, so this transaction serializes
    -- against a concurrent mark_no_shows() tick touching the same rows —
    -- same pattern as advance_turn's session-row FOR UPDATE
    -- (20260714000001_session_engine_rpcs.sql:151-156, "Lock the session
    -- row to serialize concurrent advances"). This closes the pure
    -- concurrency window; the sequential no_show-then-rejoin case is closed
    -- separately by the broken_by_session_id guard in streak_bump_user/
    -- streak_bump_group above (Finding 1(b)).
    PERFORM 1 FROM public.session_participants
      WHERE session_id = NEW.id
      FOR UPDATE;

    -- Individual: every participant whose OWN row is 'ready' at completion
    -- increments, independent of everyone else's state (Flow 7: "reached
    -- state='completed' with YOUR check_in_state='ready' at end").
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_state = 'ready'
    LOOP
      PERFORM public.streak_bump_user(rec.user_id, NEW.id);
    END LOOP;

    -- Group: only if EVERY invited participant (every session_participants
    -- row for this session) is ready — no no_shows anywhere in the roster.
    IF NEW.group_id IS NOT NULL THEN
      SELECT NOT EXISTS (
        SELECT 1 FROM public.session_participants sp
        WHERE sp.session_id = NEW.id
          AND COALESCE(sp.check_in_state, 'invited') <> 'ready'
      ) INTO v_all_ready;

      IF v_all_ready THEN
        PERFORM public.streak_bump_group(NEW.group_id, NEW.id);
      END IF;
    END IF;

  ELSIF NEW.state = 'abandoned' THEN
    -- Breaks every invited participant who never checked in at all.
    -- Absence predicate per the mark_no_shows Finding-1 lesson
    -- (20260719000004_mark_no_shows_absence_fix.sql): check_in_at IS NULL,
    -- never a state-label ('invited'/'online'/'late') guess — a 'late' row
    -- WITH check_in_at set means present, not absent.
    FOR rec IN
      SELECT sp.user_id FROM public.session_participants sp
      WHERE sp.session_id = NEW.id AND sp.check_in_at IS NULL
    LOOP
      PERFORM public.streak_break_user(rec.user_id, NEW.id);
    END LOOP;

    -- Finding 2 fix-forward: defensive group break, no longer relying on
    -- the no_show-fires-first ordering that 20260719000006's header
    -- documented (mark_no_shows()'s ~15min default threshold vs. the 6h
    -- abandon window). Same absence predicate discipline as the individual
    -- loop above — any invited participant who never checked in at all
    -- breaks the group too. Unconditional re-apply is a documented no-op
    -- (see the streak_break_group primitive's own header in
    -- 20260719000006), so this is safe even when a no_show already broke
    -- the group for this exact session.
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

-- No trigger re-creation needed: streak_no_show_break and
-- streak_on_session_completion already dispatch by function name (set in
-- 20260719000006), so CREATE OR REPLACE FUNCTION alone is enough for both
-- triggers to pick up the new bodies on their very next fire — same
-- reasoning 20260719000004 used for mark_no_shows()'s cron job.
