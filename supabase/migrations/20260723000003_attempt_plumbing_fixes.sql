-- ============================================================
-- Phase L Task 2 fix-forward: 3 review findings against attempt
-- plumbing (start_attempt RPC, leaderboard_rank_and_passed,
-- leaderboard_social_effects_on_completion — all live in
-- 20260723000002_attempt_plumbing.sql, APPLIED LIVE and therefore
-- immutable). This migration CREATE-OR-REPLACEs the three affected
-- functions in place; no schema (table/column) changes.
-- Review report: .superpowers/sdd/task-2-report.md's fix section.
-- ============================================================

-- ============================================================
-- ── FINDING 1 (Critical) — routine/session binding never checked ───────────
-- ============================================================
-- start_attempt gated participation (is_session_participant) and the
-- ATTEMPTED routine's own visibility ('public'), but never checked that
-- p_session_id is actually the session that RAN p_routine_id. sessions.
-- routine_id (20260709000006_create_sessions.sql:3) is set at session-
-- creation time and carries "which routine this session is running" for
-- ANY session (Attempt Solo/Attempt with Friends included — Flow 4). Without
-- this gate, a participant could pair any throwaway session (e.g. one
-- running a totally unrelated, or even instantly-abandoned, routine) with
-- any OTHER public routine's id and fabricate an attempt — an arbitrarily
-- fast "completion" that was never actually run against that routine's
-- exercises, poisoning that routine's leaderboard.
--
-- Fix: after the participant gate and before the visibility gate, require
-- sessions.routine_id (the session's ACTUAL routine) to equal p_routine_id
-- (the ATTEMPTED routine). IS DISTINCT FROM (not <>) so a session with no
-- routine_id at all (NULL — e.g. an ordinary non-public-workout session)
-- is correctly treated as "does not match" rather than silently passing a
-- NULL-comparison.
CREATE OR REPLACE FUNCTION public.start_attempt(p_routine_id uuid, p_session_id uuid, p_opt_in boolean)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_visibility          text;
  v_session_routine_id  uuid;
  v_id                  uuid;
BEGIN
  IF NOT public.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'must be a participant of the session to start an attempt' USING ERRCODE = 'P0001';
  END IF;

  -- FINDING 1 fix: an attempt is only valid for the routine the session was
  -- actually running — the session's own routine_id must match the routine
  -- being attempted. Rejects any (unrelated-session, public-routine) pairing
  -- before it can ever reach the visibility gate below.
  SELECT routine_id INTO v_session_routine_id FROM public.sessions WHERE id = p_session_id;
  IF v_session_routine_id IS DISTINCT FROM p_routine_id THEN
    RAISE EXCEPTION 'session must be running the attempted routine' USING ERRCODE = 'P0001';
  END IF;

  SELECT visibility INTO v_visibility FROM public.routines WHERE id = p_routine_id;
  IF v_visibility IS DISTINCT FROM 'public' THEN
    RAISE EXCEPTION 'routine must be public to attempt from Discover' USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.workout_attempts
    (routine_id, user_id, session_id, is_opt_in_leaderboard, started_at, is_complete)
  VALUES
    (p_routine_id, auth.uid(), p_session_id, COALESCE(p_opt_in, false), now(), false)
  ON CONFLICT (session_id, user_id) DO NOTHING
  RETURNING id INTO v_id;

  IF v_id IS NULL THEN
    SELECT id INTO v_id FROM public.workout_attempts
      WHERE session_id = p_session_id AND user_id = auth.uid();
  END IF;

  RETURN v_id;
END;
$$;
-- CREATE OR REPLACE preserves the function's existing ACL (same name + arg
-- types as the live definition) — the REVOKE/anon-lockout + GRANT TO
-- authenticated already applied in 20260723000002 stand untouched; no need
-- to reissue them here.


-- ============================================================
-- ── FINDING 2 (Important) — displacement misattribution in same-session
--    multi-completion ──────────────────────────────────────────────────────
-- ============================================================
-- The rank+1-post-insertion heuristic reads whoever now sits at (this
-- attempt's rank + 1) as "the person this attempt displaced." That is only
-- true when the neighbor was ALREADY THERE before this attempt landed. When
-- 2+ opted-in attempts in the SAME session complete together (the "Attempt
-- with Friends" core flow — leaderboard_recompute_on_session_completion's
-- own FOR loop, 20260723000001:264, upserts EVERY attempt tied to that
-- session's completion in one trigger firing, before leaderboard_social_
-- effects_on_completion's own FOR loop runs, by construction of the
-- zz-alphabetical-ordering trick documented in 20260723000002), a
-- same-batch neighbor is NOT "already there" — it is a sibling new entrant.
-- The old heuristic pushed each new entrant a spurious "someone passed you"
-- about the other, and left a pre-existing displaced user's notification
-- dependent on iteration order.
--
-- Fix — considered and rejected a computed_at/now() timing predicate first
-- (a same-batch sibling's leaderboard_entries.computed_at IS stamped via a
-- single now() call per the recompute trigger's loop, so in an ordinary
-- one-statement-per-transaction production request every batch-mate really
-- does share one instant): it does not actually encode "same batch," it
-- encodes "same transaction" — proven wrong by the very pgTAP suite this
-- migration extends, which wraps the ENTIRE test file (dana's completion,
-- gabe's, erin's, AND this batch's) in one outer transaction, so now()
-- would be identical across scenarios that are NOT the same batch at all.
--
-- The predicate that actually matches the mechanism: "the same batch" IS,
-- by construction, exactly "the set of workout_attempts rows sharing the
-- CURRENTLY-COMPLETING session_id" — that is the literal WHERE clause the
-- recompute trigger's FOR loop uses to decide what it upserts in one
-- firing (WHERE session_id = NEW.id). Two leaderboard_entries rows are
-- same-batch siblings if and only if their underlying attempts share a
-- session_id; comparing session_id is a pure structural fact, immune to
-- transaction/statement/clock granularity of whatever session or test
-- harness is driving it. A neighbor at rank+1 is only surfaced as "passed"
-- when its attempt's session_id differs from THIS attempt's own
-- session_id; a same-session sibling collapses to NULL.
--
-- Resulting semantics (accepted, documented): with N new same-batch
-- entrants landing above one pre-existing user, NONE of the new entrants
-- push each other, and the pre-existing user gets notified about exactly
-- ONE passer — whoever ends up DIRECTLY above them in the final post-batch
-- ordering (one notification per displaced pre-existing user, not one per
-- passer). A pre-existing user displaced by multiple batch-mates only ever
-- hears about the nearest one, which is the same "your immediate neighbor
-- changed" framing the push copy already implies.
--
-- (Finding 3's self-pass scenario is NOT conflated here: a user's own
-- earlier attempt on a different session_id is a genuinely different,
-- already-completed session — this predicate correctly does NOT exclude
-- it; the acting-user guard below is the deliberately separate fix for
-- that case.)
CREATE OR REPLACE FUNCTION public.leaderboard_rank_and_passed(p_attempt_id uuid)
RETURNS TABLE(rnk integer, passed_user_id uuid)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public AS $$
DECLARE
  v_routine_id   uuid;
  v_default_sort text;
  v_top_set_ex   uuid;
BEGIN
  SELECT le.routine_id INTO v_routine_id
    FROM public.leaderboard_entries le WHERE le.attempt_id = p_attempt_id;

  IF v_routine_id IS NULL THEN
    RETURN;
  END IF;

  SELECT r.default_sort, r.scoring_top_set_exercise_id
    INTO v_default_sort, v_top_set_ex
    FROM public.routines r WHERE r.id = v_routine_id;

  IF v_default_sort IS NULL OR v_default_sort = 'recent'
     OR (v_default_sort = 'top_set' AND v_top_set_ex IS NULL) THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH ranked AS (
    SELECT le.attempt_id AS a_id, le.user_id AS u_id, wa.session_id AS sess_id,
           (ROW_NUMBER() OVER (ORDER BY
             CASE WHEN v_default_sort = 'time'   THEN le.time_seconds  END ASC  NULLS LAST,
             CASE WHEN v_default_sort = 'volume' THEN le.total_volume END DESC NULLS LAST,
             CASE WHEN v_default_sort = 'top_set'
                  THEN (le.top_sets ->> v_top_set_ex::text)::numeric END DESC NULLS LAST,
             le.computed_at ASC, le.attempt_id ASC
           ))::integer AS rn
      FROM public.leaderboard_entries le
      JOIN public.workout_attempts wa ON wa.id = le.attempt_id
     WHERE le.routine_id = v_routine_id
       AND le.is_complete = true
       AND wa.is_opt_in_leaderboard = true
  )
  -- FINDING 2 fix: below.u_id is only surfaced as "passed" when its attempt
  -- belongs to a DIFFERENT session than THIS attempt's own session — a
  -- same-session (same-batch) sibling collapses to NULL.
  SELECT me.rn,
         CASE WHEN below.sess_id IS DISTINCT FROM me.sess_id THEN below.u_id ELSE NULL END AS passed_user_id
    FROM ranked me
    LEFT JOIN ranked below ON below.rn = me.rn + 1
   WHERE me.a_id = p_attempt_id;
END;
$$;
-- REVOKE stands from 20260723000002 (internal-only, never a client RPC) —
-- unchanged signature, ACL preserved by CREATE OR REPLACE.


-- ============================================================
-- ── FINDING 3 (Important) — self-passing push ───────────────────────────────
-- ============================================================
-- A user who runs the SAME routine more than once (distinct sessions,
-- distinct workout_attempts/leaderboard_entries rows — nothing dedupes
-- across a user's own attempts) can legitimately land directly above their
-- OWN older entry. That older entry belongs to a genuinely DIFFERENT,
-- already-completed session_id (same as any other user's pre-existing
-- entry), so FINDING 2's same-session batch fix does not — and should not —
-- filter it out at the ranking layer: leaderboard_rank_and_passed correctly
-- reports the old entry as "passed." What must not happen is turning that
-- into a push notifying the user that they passed themselves.
--
-- Fix: exclude the acting user (rec.user_id — the attempt that just
-- completed) from the push recipient, mirroring the acting-user exclusion
-- every other push trigger in this codebase already has — see
-- push_partner_pr's own `gm.user_id IS DISTINCT FROM v_pr_user_id`
-- (20260716000001_push_schema.sql:257) and push_lateness_chirp's
-- `sp.user_id <> NEW.user_id` (same file:281). Same idiom, applied here as
-- `v_passed_user <> rec.user_id`.
CREATE OR REPLACE FUNCTION public.leaderboard_social_effects_on_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec            RECORD;
  v_username     text;
  v_routine_name text;
  v_time_str     text;
  v_rank         integer;
  v_passed_user  uuid;
  v_body         text;
BEGIN
  IF NEW.state IS NOT DISTINCT FROM OLD.state OR NEW.state <> 'completed' THEN
    RETURN NEW;
  END IF;

  FOR rec IN
    SELECT wa.id AS attempt_id, wa.user_id, wa.routine_id, le.time_seconds
      FROM public.workout_attempts wa
      JOIN public.leaderboard_entries le ON le.attempt_id = wa.id
     WHERE wa.session_id = NEW.id AND wa.is_opt_in_leaderboard = true
  LOOP
    SELECT rnk, passed_user_id INTO v_rank, v_passed_user
      FROM public.leaderboard_rank_and_passed(rec.attempt_id);

    IF NEW.group_id IS NOT NULL THEN
      SELECT p.username INTO v_username FROM public.profiles p WHERE p.id = rec.user_id;
      SELECT r.name INTO v_routine_name FROM public.routines r WHERE r.id = rec.routine_id;

      v_time_str := CASE WHEN rec.time_seconds IS NOT NULL THEN
        (rec.time_seconds / 60)::text || ':' || LPAD((rec.time_seconds % 60)::text, 2, '0')
        ELSE NULL END;

      v_body := COALESCE(v_username, 'Someone') || ' attempted ' || COALESCE(v_routine_name, 'a workout')
                || CASE WHEN v_time_str IS NOT NULL THEN ' — finished in ' || v_time_str ELSE '' END
                || CASE WHEN v_rank IS NOT NULL THEN ' (#' || v_rank || ' globally)' ELSE '' END;

      INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
      VALUES (NEW.group_id, NULL, 'system_leaderboard', v_body,
              jsonb_build_object('session_id', NEW.id, 'attempt_id', rec.attempt_id,
                                 'routine_id', rec.routine_id, 'routine_name', v_routine_name,
                                 'user_id', rec.user_id, 'time_seconds', rec.time_seconds,
                                 'rank', v_rank));
    END IF;

    -- FINDING 3 fix: never push a user about passing themselves (their own
    -- older entry on the same routine).
    IF v_passed_user IS NOT NULL AND v_passed_user <> rec.user_id THEN
      PERFORM public.enqueue_push(v_passed_user, 'leaderboard_passed',
        jsonb_build_object('routine_id', rec.routine_id, 'attempt_id', rec.attempt_id,
                           'passing_user_id', rec.user_id, 'new_rank', v_rank));
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
-- Trigger binding (zzleaderboard_social_effects_on_completion AFTER UPDATE
-- OF state ON sessions) is unchanged — CREATE OR REPLACE on the function
-- body alone is picked up by the existing trigger with no DROP/CREATE
-- TRIGGER needed.
