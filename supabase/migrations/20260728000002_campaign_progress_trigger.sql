-- ============================================================
-- Phase C / Task 1 (Part 2 of 2): progress-accrual trigger + completion
-- chat message + chat_messages.kind CHECK extension.
-- ============================================================
-- Design doc citations:
--   Flow 8, Progress accrual (spec :873-875):
--     "A trigger on sessions.state -> completed checks: (a) is the
--      completed session's routine in any active campaign's
--      curated_routine_ids, and (b) is the user a participant of that
--      campaign? If yes, campaign_progress for that (campaign, user) pair
--      increments the relevant counters."
--     "Volume and workouts-completed metrics are re-derived from set_logs
--      when relevant."
--   Flow 8, Completion (spec :882-884):
--     "When individual_target is met, user gets a completion badge and a
--      chat system message ('🌊 Tommy just completed Spring Break Prep —
--      12/12 sessions!'). Campaign ends at ends_at; leaderboard is frozen;
--      final community total is displayed as historical fact."
--
-- ── THE RECOMPUTE-HOOK FINDING (cite everything -- same audit, reused) ─────
-- Every write path that can ever set sessions.state = 'completed' was
-- already exhaustively audited by 20260719000006_streaks.sql's own header
-- and reconfirmed by 20260723000001_public_workout_repository.sql's own
-- header ("IDENTICAL to the hook 20260719000006_streaks.sql already
-- uses"): exactly two call sites in the whole app --
-- SessionRepository.complete(sessionID:) (client "End Session", both solo
-- and group) and idle_rpcs.sql's wrap-up/auto-abandon path
-- (20260716000006_idle_rpcs.sql:36-39). Both funnel through one choke
-- point, a plain UPDATE of sessions.state (+ completed_at, same
-- statement). Reusing `AFTER UPDATE OF state ON public.sessions` with the
-- same OLD/NEW state-diff guard both precedents already use (rather than
-- inventing a third hook shape) is the honest, precedented choice -- not a
-- new finding, a third confirmation of the same one.
--
-- ── RACE-GUARD LESSON REUSED (cite: 20260719000007) ─────────────────────
-- streak_trigger_race_fixes.sql's Finding 1(a) established that a
-- session's completion-branch readiness read must take
-- `SELECT ... FOR UPDATE` on that session's session_participants rows
-- BEFORE evaluating check_in_state, to serialize against a concurrent
-- mark_no_shows() tick touching the same rows. Reused verbatim below,
-- guarding the SAME session_participants rows the campaign trigger also
-- reads for readiness -- re-acquiring a row lock the streak trigger (which
-- fires in the same transaction, same AFTER-trigger fan-out) may have
-- already taken is a no-op, not a deadlock (same transaction, same lock
-- requester). Finding 1(b)'s `broken_by_session_id` guard does NOT apply
-- here -- campaigns have no "break" concept, so there is no re-credit path
-- to guard against; the state-diff guard alone is sufficient, same
-- argument leaderboard_recompute_on_session_completion's own header makes
-- ("fires exactly once per session in practice", :253-258) given the
-- one-directional completed state machine both audits confirm.
--
-- ── ADJUDICATION: readiness predicate reused from the streak's individual
--    rule, not invented fresh ───────────────────────────────────────────
-- Flow 8 says only "the user" completed a session, without naming a
-- check_in_state qualifier. The honest, non-inventive reading borrows the
-- established "did this participant actually finish the workout" predicate
-- already defined for this exact event by streak_on_session_state_change's
-- individual branch (`check_in_state = 'ready'`,
-- 20260719000007_streak_trigger_race_fixes.sql:210-213) rather than
-- crediting every invited participant regardless of attendance. A no-show
-- participant on an otherwise-completed session did not complete a workout
-- and should not accrue campaign progress either. Confirmed this does not
-- exclude solo Quick Workouts: SessionRepository.startSolo always inserts
-- its sole session_participants row with check_in_state:'ready' at
-- creation time (SessionRepository.swift:46-53), so every solo session
-- remains eligible.
--
-- Unlike the streak trigger, this one is NOT scoped to
-- `scheduled_for IS NOT NULL` -- that gate exists for streaks specifically
-- because Flow 7 requires "pre-planned via the schedule flow"
-- (20260719000006's own header). Flow 8 states no such requirement --
-- "is the completed session's routine in any active campaign's
-- curated_routine_ids" makes no mention of how the session was created, so
-- an ad-hoc Quick Workout against a curated routine counts exactly the
-- same as a scheduled one.
--
-- ── "Active campaign" / date-window predicate ───────────────────────────
-- Task brief: "Progress increments per the campaign's goal type within its
-- date window." Bound on NEW.completed_at (the session's actual
-- completion timestamp) BETWEEN campaigns.starts_at AND ends_at -- not
-- now() -- so a session that finishes inside the campaign's window counts
-- even if this trigger's own execution were ever delayed relative to it
-- (it isn't, in practice: this is a synchronous AFTER trigger in the same
-- transaction as the UPDATE), and, symmetrically, so a late duration-edit
-- (session_duration_edits, which never touches `state` and therefore never
-- re-fires this trigger) cannot retroactively pull a session into or out
-- of a window it already resolved at the one moment this trigger runs.
-- `is_draft` is deliberately NOT part of this predicate -- draft-ness is a
-- pure RLS-visibility concern (Part 1's Adjudication 3); Task 3's seeded
-- test campaign must accrue progress from a fixture completion exactly
-- like a real one (that IS Phase C's acceptance bar per the phase spec's
-- own "Acceptance" section), and gating accrual on is_draft would break
-- that live proof for no product reason.
--
-- ── sessions_completed vs workouts_completed: deliberately redundant in v1
-- Both counters increment together for every qualifying session -- Flow
-- 8's own trigger description gates BOTH on the same (a) AND (b) condition
-- ("If yes, campaign_progress... increments the relevant counterS", plural,
-- gated as one unit). This looks redundant today, but the schema comment
-- on individual_target (spec :592, "{"sessions":12} or
-- {"workouts_completed":4}") shows why both names exist: a campaign's
-- individual_target picks ONE OR THE OTHER key, and the trigger doesn't
-- know in advance which key a given campaign uses, so it keeps both
-- counters in lockstep rather than guessing which one "really" matters --
-- no invented distinction between "any completed session" and "a curated
-- one" that Flow 8's text does not draw.
--
-- ── volume_lifted: incremented (cumulative), not recomputed absolute ────
-- Unlike leaderboard_entries.total_volume (a per-ATTEMPT absolute
-- recompute, because an attempt is a single event), campaign_progress.
-- volume_lifted is a cumulative campaign-lifetime total across
-- potentially many qualifying sessions -- so this trigger ADDS each
-- qualifying session's own volume (same `reps * weight`, excluding
-- is_penalty/is_failed formula as increment_lifetime_volume
-- (20260709000008_lifetime_volume_trigger.sql:4), leaderboard_
-- attempt_volume, and group_stats) onto the running total, rather than
-- overwriting it. "Re-derived from set_logs when relevant" (spec :875)
-- describes HOW each session's contribution is computed (from set_logs,
-- not from some other running counter), not that the campaign total
-- itself is a full recompute each time.
--
-- ── Completion badge: no DB table ─────────────────────────────────────
-- Flow 8's "completion badge" has no corresponding table anywhere in the
-- schema section (:581-614 lists only campaigns/campaign_participants/
-- campaign_progress) and no badges table exists anywhere else in this
-- repo. Same posture as streak milestones (7/14/30/... thresholds,
-- 20260719000008_streak_pushes.sql) which are also purely derived from
-- already-stored counters with no separate "badges" table -- the badge is
-- a client-derived display state (campaign_progress vs. campaigns.
-- individual_target), not a Task 1 backend concern. Flagged for Task 2 (UI).
--
-- ── Push notification: NONE named, therefore none built ─────────────────
-- Master spec §6.3's push table (:1165-1177) is the exhaustive, named list
-- of push events wired through push-dispatcher -- no campaign-related row
-- exists in it (contrast `leaderboard_passed`, `streak_milestone`, both of
-- which DO have rows, per 20260723000002's own header:24-27, "reserved in
-- 3d"). Flow 8's Completion section (:882-884) names only "a completion
-- badge and a chat system message" -- no push. Per the brief's own
-- instruction ("If Flow 8 names neither, say so and build neither"): no
-- payloads.ts case, no enqueue_push call, no deno test are added here.
-- ============================================================

-- ── 1. chat_messages.kind — extend with 'system_campaign' ───────────────
-- "Grown table" doctrine (handoff §3.2, "NOT VALID/VALIDATE for
-- grown-table CHECKs") applied for the first time in this repo: every
-- prior kind-CHECK extension (20260715000001, 20260719000008) used a bare
-- DROP CONSTRAINT + ADD CONSTRAINT, which validates the new CHECK against
-- every existing row while holding ACCESS EXCLUSIVE for the full scan.
-- chat_messages now carries eleven shipped phases of real chat/PR/
-- streak/leaderboard/soundboard traffic (20260710000003 through
-- 20260726000004) -- large enough that the doctrine's fix-forward
-- pointer names it explicitly (2026-07-18-discover-leaderboards.md:14,
-- "the S-phase lock doctrine — chat_messages is the growing table").
-- Sequence: ADD the new, wider CHECK as NOT VALID (fast, metadata-only,
-- brief ACCESS EXCLUSIVE, but does not scan) under a temporary name so it
-- coexists with the old one for a moment (harmless double-checking, both
-- accept every existing row); VALIDATE it (SHARE UPDATE EXCLUSIVE, scans
-- without blocking concurrent reads/writes); THEN drop the old constraint;
-- THEN rename the new one back to the canonical name
-- `chat_messages_kind_check` so a future reader doing exactly what THIS
-- migration's own citation practice does (grep the latest drop/add for the
-- authoritative list) finds it under the expected name.
--
-- Full base list copied forward from the current authoritative constraint
-- text (20260719000008_streak_pushes.sql:112-114, itself copied forward
-- from 20260715000001), plus 'system_campaign'.
ALTER TABLE public.chat_messages
  ADD CONSTRAINT chat_messages_kind_check_v2
  CHECK (kind IN ('text', 'image', 'audio', 'system_pr', 'system_session',
                  'system_late', 'system_leaderboard', 'system_streak',
                  'system_campaign', 'soundboard_echo'))
  NOT VALID;

ALTER TABLE public.chat_messages VALIDATE CONSTRAINT chat_messages_kind_check_v2;

ALTER TABLE public.chat_messages DROP CONSTRAINT chat_messages_kind_check;
ALTER TABLE public.chat_messages RENAME CONSTRAINT chat_messages_kind_check_v2 TO chat_messages_kind_check;

-- The INSERT-policy kind allow-lists (20260726000004_chat_messages_
-- insert_is_session_participant_fixup.sql:53, and its own predecessors)
-- restrict which kinds a CLIENT may author directly
-- ('text','image','audio','soundboard_echo') -- 'system_campaign' is
-- authored exclusively by the SECURITY DEFINER trigger below (author_id
-- NULL), same posture as 'system_pr'/'system_streak'/'system_leaderboard'
-- today, none of which appear in that client allow-list either. No policy
-- change needed here.

-- ============================================================
-- ── 2. Progress accrual + completion message trigger ────────────────────
-- ============================================================
CREATE OR REPLACE FUNCTION public.campaign_progress_on_session_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec              RECORD;
  v_session_volume numeric(12,2);
  v_old_sessions   integer;
  v_old_workouts   integer;
  v_old_volume     numeric(12,2);
  v_new_sessions   integer;
  v_new_workouts   integer;
  v_new_volume     numeric(12,2);
  v_target_n       integer;
  v_old_count      integer;
  v_new_count      integer;
  v_unit_label     text;
  v_username       text;
BEGIN
  -- Same OLD/NEW state-diff guard shape as streak_on_session_state_change
  -- and leaderboard_recompute_on_session_completion: a same-value refire,
  -- or any transition that isn't INTO 'completed' (including 'abandoned'
  -- -- Flow 8 names no abandoned-session behavior at all), is a no-op.
  IF NEW.state IS NOT DISTINCT FROM OLD.state OR NEW.state <> 'completed' THEN
    RETURN NEW;
  END IF;

  -- Cheap early-out: a session with no routine can never match any
  -- campaign's curated_routine_ids.
  IF NEW.routine_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Cheap early-out: skip the participant lock entirely unless at least
  -- one campaign's window+routine could possibly match this session.
  -- Campaigns table is small by product design ("1-2 active seasonal
  -- campaigns at a time", spec :1375), so this is a trivial scan.
  IF NOT EXISTS (
    SELECT 1 FROM public.campaigns c
    WHERE NEW.routine_id = ANY(c.curated_routine_ids)
      AND NEW.completed_at BETWEEN c.starts_at AND c.ends_at
  ) THEN
    RETURN NEW;
  END IF;

  -- Race guard reused from streak_trigger_race_fixes.sql Finding 1(a):
  -- lock this session's session_participants rows before evaluating
  -- readiness, serializing against a concurrent mark_no_shows() tick.
  PERFORM 1 FROM public.session_participants
    WHERE session_id = NEW.id
    FOR UPDATE;

  FOR rec IN
    SELECT c.id AS campaign_id, c.name AS campaign_name, c.individual_target,
           sp.user_id
    FROM public.campaigns c
    JOIN public.campaign_participants cpart ON cpart.campaign_id = c.id
    JOIN public.session_participants sp
      ON sp.session_id = NEW.id
     AND sp.user_id = cpart.user_id
     AND sp.check_in_state = 'ready'
    WHERE NEW.routine_id = ANY(c.curated_routine_ids)
      AND NEW.completed_at BETWEEN c.starts_at AND c.ends_at
  LOOP
    -- This session's volume contribution, same exclusions as
    -- increment_lifetime_volume/leaderboard_attempt_volume/group_stats:
    -- reps * weight, excluding is_penalty and is_failed rows.
    SELECT COALESCE(SUM(sl.reps * sl.weight), 0)
      INTO v_session_volume
      FROM public.set_logs sl
      WHERE sl.session_id = NEW.id AND sl.user_id = rec.user_id
        AND sl.is_failed = false AND sl.is_penalty = false
        AND sl.reps IS NOT NULL AND sl.weight IS NOT NULL;

    -- streak_bump_user idiom: INSERT...ON CONFLICT DO NOTHING to
    -- guarantee the row exists, then SELECT...FOR UPDATE to lock it and
    -- read the pre-write counts (needed for the completion-crossing check
    -- below), then a plain UPDATE with the computed new values. This
    -- avoids the INSERT-vs-UPDATE trigger-fan-out gap a naive
    -- `INSERT ... ON CONFLICT DO UPDATE` would have if the completion
    -- check instead lived in a separate `AFTER UPDATE ON campaign_progress`
    -- trigger (a brand-new participant's first-ever qualifying session
    -- would take the INSERT path and never fire such a trigger at all).
    INSERT INTO public.campaign_progress (campaign_id, user_id)
      VALUES (rec.campaign_id, rec.user_id)
      ON CONFLICT (campaign_id, user_id) DO NOTHING;

    SELECT sessions_completed, workouts_completed, volume_lifted
      INTO v_old_sessions, v_old_workouts, v_old_volume
      FROM public.campaign_progress
      WHERE campaign_id = rec.campaign_id AND user_id = rec.user_id
      FOR UPDATE;

    v_new_sessions := v_old_sessions + 1;
    v_new_workouts := v_old_workouts + 1;
    v_new_volume   := v_old_volume + v_session_volume;

    UPDATE public.campaign_progress
      SET sessions_completed = v_new_sessions,
          workouts_completed = v_new_workouts,
          volume_lifted      = v_new_volume,
          updated_at         = now()
      WHERE campaign_id = rec.campaign_id AND user_id = rec.user_id;

    -- ── Completion check: individual_target crossing, fires once ──────
    -- Picks whichever key the campaign's individual_target actually uses
    -- (spec :592, "{"sessions":12} or {"workouts_completed":4}") -- NULL
    -- individual_target or an unrecognized key is a silent no-op (no
    -- completion message), not an error.
    v_target_n := NULL;
    IF rec.individual_target ? 'sessions' THEN
      v_target_n  := (rec.individual_target->>'sessions')::integer;
      v_old_count := v_old_sessions;
      v_new_count := v_new_sessions;
      v_unit_label := 'sessions';
    ELSIF rec.individual_target ? 'workouts_completed' THEN
      v_target_n  := (rec.individual_target->>'workouts_completed')::integer;
      v_old_count := v_old_workouts;
      v_new_count := v_new_workouts;
      v_unit_label := 'workouts';
    END IF;

    -- Crossing, not "landing exactly": both counters move by exactly +1
    -- per qualifying session (never re-set, never decremented -- there is
    -- no break/undo concept for campaigns), so old < target <= new can
    -- only ever be true on the ONE session that first reaches the target,
    -- same "fires exactly once" argument push_streak_milestone_user/group
    -- make for their own ANY-membership check
    -- (20260719000008_streak_pushes.sql:118-126).
    IF v_target_n IS NOT NULL AND v_old_count < v_target_n AND v_new_count >= v_target_n THEN
      SELECT username INTO v_username FROM public.profiles WHERE id = rec.user_id;

      -- Fan out to every group the achiever belongs to -- same shape as
      -- announce_pr() (20260710000007_pr_body_format.sql:24-31) and
      -- push_streak_milestone_group's chat insert
      -- (20260719000008_streak_pushes.sql:161-164): author_id NULL =
      -- system, payload carries structured facts, body carries the
      -- human-readable copy. A groupless user (zero group_members rows)
      -- silently produces zero message rows, same as announce_pr's own
      -- documented behavior for a groupless lifter -- not a new gap.
      INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
      SELECT gm.group_id, NULL, 'system_campaign',
             '🌊 ' || v_username || ' just completed ' || rec.campaign_name
                  || ' — ' || v_new_count || '/' || v_target_n || ' ' || v_unit_label || '!',
             jsonb_build_object('user_id', rec.user_id, 'campaign_id', rec.campaign_id,
                                'target', v_target_n, 'value', v_new_count)
      FROM public.group_members gm
      WHERE gm.user_id = rec.user_id;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS campaign_progress_on_completion ON public.sessions;
CREATE TRIGGER campaign_progress_on_completion
  AFTER UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.campaign_progress_on_session_completion();
