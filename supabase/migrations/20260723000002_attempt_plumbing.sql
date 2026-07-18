-- ============================================================
-- Phase L Task 2: Attempt plumbing — start_attempt RPC, completion
-- system message, leaderboard_passed displacement push.
-- ============================================================
-- Design doc citations:
--   Flow 4 (attempt lifecycle + system message copy) — docs/superpowers/
--     specs/2026-06-28-gymsync-design.md:790-797
--   Push table (leaderboard_passed row)              — same file:1176
--   Phase L design §2 (attempt flow)                  — docs/superpowers/
--     specs/2026-07-18-discover-leaderboards-design.md:13-15
--   Task 1 report (schema/RLS this migration builds on) — .superpowers/
--     sdd/task-1-report.md
--
-- ── FINDING 1: system_leaderboard kind + leaderboard_passed category are
--    ALREADY reserved — no CHECK-constraint extension needed here ──────────
-- The brief's checklist says "verify current chat kinds CHECK; extend w/
-- NOT VALID+VALIDATE doctrine if missing." Verified both, and both are
-- already present, planted well before this feature existed:
--   - chat_messages.kind: 'system_leaderboard' has been in the CHECK since
--     the table's ORIGINAL CREATE TABLE (20260710000003_create_chat.sql:8),
--     carried forward verbatim through every subsequent drop+re-add
--     (20260715000001_comms_schema.sql:31, 20260719000008_streak_pushes.
--     sql:113 — the latter is the current authoritative constraint text).
--   - notification_prefs.category / push_event_category('leaderboard_passed'):
--     both present since push_queue's own creation (20260716000001_push_
--     schema.sql:34,94) — Phase L design doc's own words confirm this was
--     deliberate: "pushes (`leaderboard_passed`, reserved in 3d)" (design.md:3).
-- So there is nothing to ALTER on chat_messages or notification_prefs, and
-- therefore no NOT VALID+VALIDATE step in this migration — that doctrine
-- only applies when a CHECK constraint is actually being widened, which
-- isn't the case here. Recorded so a future reader doesn't go looking for
-- a DROP/ADD CONSTRAINT that was never needed.
--
-- ── FINDING 2: start_attempt as an explicit client RPC (not an implicit
--    hook on session creation) ──────────────────────────────────────────────
-- The brief poses the choice explicitly. Session creation (`sessions`
-- INSERT, 20260709000006_create_sessions.sql:57-59) has no concept of
-- "which routine, opted in or not, for public-workout purposes" — routine_id
-- on sessions is set at schedule time for ANY routine (private included),
-- and Attempt Solo/Attempt with Friends (Flow 4) are explicitly separate
-- CTAs from ordinary session creation. An explicit `start_attempt(p_routine,
-- p_session, p_opt_in)` RPC — same calling convention the client already
-- uses everywhere else for a privileged write
-- (`.rpc("start_session", params: [...])`, GymSyncApp/GymSync/Models/
-- SessionRepository.swift:367; `.rpc("register_push_device", ...)`,
-- PushDeviceRepository.swift:54) — keeps the opt-in choice explicit at the
-- moment Flow 4 actually asks for it ("Show me on leaderboard" toggle,
-- design.md:794) and is directly testable in isolation, rather than
-- threading a routine-visibility check into the general session-creation
-- path that every OTHER session (not just public-workout attempts) also
-- goes through.
-- ============================================================


-- ============================================================
-- ── 1. start_attempt(p_routine_id, p_session_id, p_opt_in) ─────────────────
-- ============================================================
-- Gate: caller must be a participant of p_session_id (is_session_participant,
-- 20260709000006_create_sessions.sql:32 — same helper every other session-
-- scoped RPC in this repo uses, e.g. idle_rpcs.sql:23,57) AND p_routine_id
-- must be visibility='public' (Task 1's own header explicitly deferred this
-- exact check to "Task 2's attempt-start RPC," 20260723000001_public_
-- workout_repository.sql:65-67).
--
-- Idempotent-ish: workout_attempts_session_user_idx (Task 1, a UNIQUE index
-- on (session_id, user_id)) is the idempotency key — ON CONFLICT DO NOTHING,
-- then a plain SELECT for the pre-existing row's id. A repeat call (double-
-- tap, retry after a dropped response) returns the SAME attempt id rather
-- than erroring or creating a second row; it deliberately does NOT update
-- is_opt_in_leaderboard on a repeat call — the opt-in choice is pinned at
-- first start, matching Flow 4's "opt-in per attempt" framing (a toggle a
-- user sets once when launching the attempt, not a value that should
-- silently flip underneath an in-progress attempt from a stray retry).
CREATE OR REPLACE FUNCTION public.start_attempt(p_routine_id uuid, p_session_id uuid, p_opt_in boolean)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_visibility text;
  v_id         uuid;
BEGIN
  IF NOT public.is_session_participant(p_session_id, auth.uid()) THEN
    RAISE EXCEPTION 'must be a participant of the session to start an attempt' USING ERRCODE = 'P0001';
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

-- Client-callable — self-scoped by is_session_participant + auth.uid() above
-- (params are entity ids, gated in-body, never trusted directly — same shape
-- as group_burpee_ledger/register_push_device). Newly created functions get
-- PUBLIC EXECUTE by default, which anon inherits, so REVOKE FROM PUBLIC, anon
-- and GRANT back explicitly TO authenticated (the burpee-ledger pattern,
-- 20260717000002_burpee_ledger_rpc.sql:62-68) — do NOT include authenticated
-- in the REVOKE.
REVOKE EXECUTE ON FUNCTION public.start_attempt(uuid, uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_attempt(uuid, uuid, boolean) TO authenticated;


-- ============================================================
-- ── 2. leaderboard_rank_and_passed: rank + the single directly-passed user ──
-- ============================================================
-- Internal plumbing only (same idiom as leaderboard_attempt_volume,
-- 20260723000001:243) — never a client RPC.
--
-- Rank metric = the routine's own default_sort (Phase L design §1: "sortable
-- ... per default_sort" — the SAME field, not an independent choice for this
-- function): 'time' -> time_seconds ASC NULLS LAST, 'volume' -> total_volume
-- DESC NULLS LAST, 'top_set' -> the routine's scoring_top_set_exercise_id's
-- entry in top_sets DESC NULLS LAST. 'recent' and an unset default_sort both
-- return NULL (no rank) — 'recent' is a chronological ordering, not a scored
-- position, so "displaced a rank" has no meaning for it; an unset
-- default_sort means the curator never picked a scoring metric.
--
-- "The directly passed user" (push table, design.md:1176: "A leaderboard
-- entry knocks you down a rank" -> "The passed user") is derived, not
-- separately tracked: whoever sits at position (this attempt's rank + 1) in
-- the SAME final ordering, AFTER this attempt's row is included, is by
-- construction the person who held that rank immediately before this
-- attempt was inserted (inserting one new ranked element shifts everyone at
-- or below the insertion point down by exactly one position; it cannot
-- reorder anyone else relative to each other). That single row IS the
-- single recipient — no separate before/after snapshot query needed.
--
-- Only opt-in + complete entries enter the window (JOIN to workout_attempts,
-- same shape as the RLS policy's own join in 20260723000001 — leaderboard_
-- entries deliberately has no denormalized opt-in column, see that
-- migration's §3 comment) — an opted-out attempt can neither hold a rank nor
-- ever appear as anyone's "passed" neighbor, which is also what keeps it
-- from leaking a rank via this function even indirectly.
--
-- Tiebreak (computed_at ASC, attempt_id ASC): two entries share the same
-- transaction's now() when a group session completes several attempts at
-- once (Postgres's now() is stable per-transaction), so computed_at alone
-- cannot break same-session ties — attempt_id is the final deterministic
-- tiebreaker. Recorded honestly: in the rare case of an exact metric tie
-- between two attempts completing in the SAME session batch, the "passed"
-- neighbor for one of them may be the other brand-new attempt rather than a
-- pre-existing entry — a real edge case, not fixed further here (true ties
-- on continuous decimal metrics are vanishingly rare, and the spec's own
-- worked example, "#187 globally", is precisely the common case this
-- function targets: one new attempt displacing a PRE-EXISTING entry).
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
    SELECT le.attempt_id AS a_id, le.user_id AS u_id,
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
  SELECT me.rn, below.u_id
    FROM ranked me
    LEFT JOIN ranked below ON below.rn = me.rn + 1
   WHERE me.a_id = p_attempt_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.leaderboard_rank_and_passed(uuid) FROM PUBLIC, anon, authenticated;


-- ============================================================
-- ── 3. Completion social effects: system message + leaderboard_passed ──────
-- ============================================================
-- A SEPARATE trigger function on the SAME `AFTER UPDATE OF state ON
-- sessions` event Task 1's leaderboard_recompute_on_session_completion
-- already uses — not an edit to that function's body. This mirrors the
-- repo's established one-trigger-per-concern shape (leaderboard_recompute /
-- leaderboard_lock_on_duration_edit / leaderboard_refresh_on_set_log_change
-- are already three independent trigger functions in Task 1 for three
-- independent concerns), keeps Task 1's already-pgTAP-proven function
-- byte-for-byte untouched (zero regression risk to its 22 green assertions),
-- and — critically — MUST run strictly after the recompute trigger has
-- upserted every attempt in this session's leaderboard_entries, or a rank
-- computed here would see a partially-updated cohort. Postgres fires
-- same-event AFTER triggers in NAME-alphabetical order (the exact mechanism
-- push_schema.sql already documents and relies on for its own zzpush_*
-- triggers, 20260716000001_push_schema.sql:131-138): naming this trigger
-- `zzleaderboard_social_effects_on_completion` sorts it after
-- `leaderboard_recompute_on_completion` ('z' > 'l'), guaranteeing every
-- attempt tied to this session already has its final leaderboard_entries row
-- by the time this function runs.
--
-- Solo vs group message (design.md:794 "lands in the user's group chat";
-- Phase L design §2's own pinned ambiguity note, design.md:14): a session's
-- group_id is NULL for a solo attempt (sessions.group_id is nullable,
-- 20260712000001_sessions_phase3_columns.sql:2) — there is no group thread
-- for a solo attempt to land a message in, so this function skips the chat
-- insert entirely rather than inventing a DM-style channel the schema
-- doesn't have. Recorded as an honest read per the brief's pinned decision,
-- not a bug.
--
-- Opt-out attempts never reach either effect: the driving SELECT below is
-- scoped to `wa.is_opt_in_leaderboard = true`, so an opted-out attempt is
-- filtered out before rank, message, or push are ever considered — no
-- partial leak of its rank or existence to anyone.
--
-- chat_messages column shape (group_id, author_id, kind, body, payload) with
-- author_id = NULL for "system" matches every other system-message insert in
-- this codebase verbatim (announce_pr, announce_session_lifecycle,
-- push_streak_milestone_group — none of them populate chat_messages.session_id
-- as a column either, always folding session context into payload instead;
-- followed here for the same reason).
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

    IF v_passed_user IS NOT NULL THEN
      PERFORM public.enqueue_push(v_passed_user, 'leaderboard_passed',
        jsonb_build_object('routine_id', rec.routine_id, 'attempt_id', rec.attempt_id,
                           'passing_user_id', rec.user_id, 'new_rank', v_rank));
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zzleaderboard_social_effects_on_completion ON public.sessions;
CREATE TRIGGER zzleaderboard_social_effects_on_completion
  AFTER UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.leaderboard_social_effects_on_completion();
