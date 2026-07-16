-- ============================================================
-- Phase S Task 4: streak pushes through the existing 3d outbox
-- (milestones + at-risk; break stays SILENT per Flow 7 — no push anywhere
-- in this migration ever fires off a break).
-- ============================================================
-- Design doc citations:
--   Flow 7 notifications              — docs/superpowers/specs/2026-06-28-gymsync-design.md:856-860
--   Tunable defaults (milestone list,
--   at-risk timing)                   — same file:1373-1374
--
-- ── MILESTONE SET: 7/14/30/60/90/180/365, not Flow 7's shorter prose list ──
-- Flow 7's own prose (line 859) says "streak milestone (7, 14, 30, 90, 365)"
-- — five numbers, missing 60 and 180. The Tunable Defaults section (line
-- 1373) is more specific and explicit: "Streak milestones — celebratory
-- pushes at 7, 14, 30, 60, 90, 180, 365 consecutive planned sessions." Seven
-- numbers. Same doc, two inconsistent lists for the same rule. Tunables wins
-- here (per this task's brief, which pins the seven-number list explicitly)
-- because it's the more specific, dedicated "tunable defaults" section that
-- exists precisely to nail down exact numeric knobs the narrative prose
-- summarizes loosely — same category of citation-over-summary judgment this
-- repo's migrations already apply elsewhere (e.g. 20260719000006's
-- scheduled-predicate finding). Recorded here rather than silently picking
-- one list so a future reader isn't left wondering which was used.
--
-- ── HOOK CHOICE: AFTER UPDATE OF current_streak trigger on the streak
--    tables themselves, NOT a change to streak_bump_user/streak_bump_group ──
-- Every existing 3d push enqueuer (20260716000001_push_schema.sql) is a
-- dedicated `AFTER [INSERT|UPDATE OF <col>] ON <table>` trigger that reacts
-- to a column changing on the table itself — zzpush_your_turn fires on
-- `AFTER UPDATE OF current_turn_user_id ON sessions`, zzpush_lateness_chirp
-- on `AFTER UPDATE OF check_in_state ON session_participants`, etc. That
-- shape — react to the data changing, not to which function caused the
-- change — is the established idiom this migration follows: new triggers
-- `AFTER UPDATE OF current_streak ON user_streaks` / `ON group_streaks`,
-- guarded (like every other 3d trigger) with an in-body
-- `NEW.x IS DISTINCT FROM OLD.x` check before doing anything.
-- The alternative the brief posed — editing streak_bump_user/streak_bump_group
-- themselves (another fix-forward CREATE OR REPLACE, joining 20260719000007's
-- own edits to those same two functions) — was rejected: those functions are
-- the already-shipped, already-pgTAP-proven (streaks_test.sql's Quinn/sam
-- idempotency fixtures) computation primitives, and Postgres UPDATE-column
-- triggers fire regardless of which caller performed the UPDATE (a direct
-- SQL UPDATE, a future admin backfill script, anything) — a table-level
-- trigger catches milestone crossings correctly no matter how current_streak
-- changed, whereas logic embedded inside streak_bump_user only catches calls
-- that go through that one function. Zero lines of 006/007 are touched here.
-- ============================================================


-- ── 1. notification_prefs: new 'streak' category ────────────────────────────
-- notification_prefs.category has a CHECK constraint listing exactly the 10
-- designer categories from the 3d push event matrix (design doc §6.3) —
-- streak_milestone/streak_at_risk are new event kinds Flow 7 introduces that
-- the original matrix never listed, so push_event_category() (below) would
-- otherwise map them to NULL, and enqueue_push's own logic
-- (`IF v_category IS NOT NULL AND EXISTS(opt-out row) THEN RETURN`) treats an
-- unmapped category as PERMANENTLY un-opt-outable — a real regression
-- against the design doc's blanket "Per-category opt-outs in You tab" rule
-- (§6.3 intro). One new category, 'streak', covers BOTH raw event names —
-- mirrors the exact precedent already in this file for
-- session_idle_30min/session_idle_60min collapsing onto the single
-- 'session_idle' toggle (push_event_category's own header comment: "no
-- separate 30-min/60-min switch in the UI"). Milestone vs at-risk likewise
-- has no dedicated UI slot and no product reason to split the toggle.
ALTER TABLE public.notification_prefs DROP CONSTRAINT notification_prefs_category_check;
ALTER TABLE public.notification_prefs ADD CONSTRAINT notification_prefs_category_check
  CHECK (category IN (
    'friend_request', 'session_invite', 'session_reminder_15min',
    'session_lobby_open', 'your_turn', 'partner_pr', 'lateness_chirp',
    'session_idle', 'chat_mention', 'leaderboard_passed', 'streak'
  ));

-- push_event_category(): copied forward verbatim from 20260716000001_push_
-- schema.sql plus the two new WHEN branches — same fix-forward convention
-- CREATE OR REPLACE already used throughout this pipeline (e.g. reminder_
-- window_fix.sql's enqueue_scheduled_pushes).
CREATE OR REPLACE FUNCTION public.push_event_category(p_event text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE p_event
    WHEN 'friend_request'         THEN 'friend_request'
    WHEN 'session_invite'         THEN 'session_invite'
    WHEN 'session_reminder_15min' THEN 'session_reminder_15min'
    WHEN 'session_lobby_open'     THEN 'session_lobby_open'
    WHEN 'your_turn'              THEN 'your_turn'
    WHEN 'partner_pr'             THEN 'partner_pr'
    WHEN 'lateness_chirp'         THEN 'lateness_chirp'
    WHEN 'session_idle_30min'     THEN 'session_idle'
    WHEN 'session_idle_60min'     THEN 'session_idle'
    WHEN 'chat_mention'           THEN 'chat_mention'
    WHEN 'leaderboard_passed'     THEN 'leaderboard_passed'
    WHEN 'streak_milestone'       THEN 'streak'
    WHEN 'streak_at_risk'         THEN 'streak'
    ELSE NULL
  END;
$$;


-- ── 2. chat_messages: new 'system_streak' kind (group milestone chat msg) ──
-- Flow 7: "celebratory push + system message in group chat if applicable"
-- (i.e. only for a GROUP streak milestone). Mirrors the system_pr/
-- system_session precedent (author_id NULL = system, per
-- 20260710000003_create_chat.sql's own column comment).
-- Full base list copied forward from 20260715000001_comms_schema.sql's own
-- drop+re-add of this exact constraint (which is where 'audio' was added on
-- top of the original CREATE TABLE list in 20260710000003_create_chat.sql —
-- confirmed against the live pg_constraint definition, not just the
-- original CREATE TABLE text, precisely because this fix-forward idiom
-- means the authoritative list lives in the LATEST drop+re-add, not the
-- table's original migration).
ALTER TABLE public.chat_messages DROP CONSTRAINT chat_messages_kind_check;
ALTER TABLE public.chat_messages ADD CONSTRAINT chat_messages_kind_check
  CHECK (kind IN ('text', 'image', 'audio', 'system_pr', 'system_session',
                  'system_late', 'system_leaderboard', 'system_streak',
                  'soundboard_echo'));


-- ── 3. Milestone enqueue: user_streaks ──────────────────────────────────────
-- Fires only on a genuine change to current_streak (mirrors every other
-- column-trigger's OLD/NEW guard in this pipeline), and only when the NEW
-- value lands exactly on a milestone. streak_bump_user only ever moves
-- current_streak up by exactly 1 per call (and streak_break_user only ever
-- sets it to 0, never a milestone number), so this fires exactly once per
-- streak's lifetime crossing of each threshold — never on 6 or 8, never on
-- a break (0 is not in the milestone set), never twice for the same
-- crossing (current_streak cannot be re-set to the same milestone value
-- without first dropping below it, since it is monotonic between breaks).
CREATE OR REPLACE FUNCTION public.push_streak_milestone_user() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.current_streak IS DISTINCT FROM OLD.current_streak
     AND NEW.current_streak = ANY (ARRAY[7, 14, 30, 60, 90, 180, 365]) THEN
    PERFORM public.enqueue_push(NEW.user_id, 'streak_milestone',
      jsonb_build_object('streak', NEW.current_streak, 'kind', 'user'));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_streak_milestone_user
  AFTER UPDATE OF current_streak ON public.user_streaks
  FOR EACH ROW EXECUTE FUNCTION public.push_streak_milestone_user();


-- ── 4. Milestone enqueue: group_streaks (+ system chat message) ─────────────
-- Pushes every group member (no "exclude the achiever" concept here — unlike
-- partner_pr, a group milestone is a shared achievement, nobody is excluded)
-- and inserts one system_streak chat_messages row, mirroring announce_pr()'s
-- shape (20260710000004_pr_system_messages.sql): author_id NULL, payload
-- carries the structured facts, body carries the human-readable copy.
CREATE OR REPLACE FUNCTION public.push_streak_milestone_group() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.current_streak IS DISTINCT FROM OLD.current_streak
     AND NEW.current_streak = ANY (ARRAY[7, 14, 30, 60, 90, 180, 365]) THEN
    PERFORM public.enqueue_push(gm.user_id, 'streak_milestone',
      jsonb_build_object('streak', NEW.current_streak, 'kind', 'group',
                         'group_id', NEW.group_id))
    FROM public.group_members gm
    WHERE gm.group_id = NEW.group_id;

    INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
    VALUES (NEW.group_id, NULL, 'system_streak',
            '🔥 Crew streak: ' || NEW.current_streak || ' sessions strong!',
            jsonb_build_object('group_id', NEW.group_id, 'streak', NEW.current_streak));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_streak_milestone_group
  AFTER UPDATE OF current_streak ON public.group_streaks
  FOR EACH ROW EXECUTE FUNCTION public.push_streak_milestone_group();


-- ── 5. At-risk cron: 30 min before scheduled_for, not checked in, has a
--       current streak ───────────────────────────────────────────────────────
-- Design doc tunable (line 1374): "Streak-at-risk push timing — 30 minutes
-- before scheduled_for if user hasn't checked in yet." Flow 7 (line 860)
-- narrows the audience further: "you haven't checked in) ... you have a
-- current streak" (a zero-streak user has nothing at risk).
--
-- session_participants gets its own dedupe column (NOT a reuse of sessions.
-- reminded_at) because eligibility here is per-PARTICIPANT — one participant
-- may already be checked in (excluded) while another in the same session
-- still needs the push — unlike the 15-min reminder, which pushes every
-- participant of an eligible session identically and so only needs one
-- session-level flag.
ALTER TABLE public.session_participants
  ADD COLUMN streak_at_risk_notified_at timestamptz;

-- Window: catch-up-safe, exactly the shape 20260716000004_reminder_window_
-- fix.sql fixed the 15-min reminder to use (`scheduled_for - N minutes <=
-- now() AND scheduled_for > now()`, no upper bound) — NOT the original
-- boundary-exact 1-minute-wide window that fix had to walk back, so a
-- delayed/dropped cron tick here can never silently skip a participant
-- forever. streak_at_risk_notified_at IS NULL is the sole idempotency guard,
-- same role reminded_at plays for the 15-min reminder.
--
-- State scope: `state IN ('scheduled', 'lobby_open')`, not just 'scheduled'
-- — same two-state "hasn't started running yet" scope join_session_by_code
-- and live_plumbing's rejoin path already use (20260712000005_join_by_code.
-- sql, 20260714000002_live_plumbing.sql), because a session's lobby can open
-- before scheduled_for elapses, and a participant sitting in an open lobby
-- who still hasn't checked in is exactly as "at risk" as one who hasn't
-- looked at a still-'scheduled' session. Absence predicate is check_in_at
-- IS NULL — the mark_no_shows Finding-1 lesson (20260719000004_mark_no_
-- shows_absence_fix.sql): absence is never a check_in_state label guess.
CREATE OR REPLACE FUNCTION public.enqueue_streak_at_risk_pushes() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec record;
BEGIN
  FOR rec IN
    UPDATE public.session_participants sp
    SET streak_at_risk_notified_at = now()
    FROM public.sessions s, public.user_streaks us
    WHERE sp.session_id = s.id
      AND us.user_id = sp.user_id
      AND s.state IN ('scheduled', 'lobby_open')
      AND s.scheduled_for IS NOT NULL
      AND s.scheduled_for - interval '30 minutes' <= now()
      AND s.scheduled_for > now()
      AND sp.check_in_at IS NULL
      AND us.current_streak > 0
      AND sp.streak_at_risk_notified_at IS NULL
    RETURNING sp.session_id AS session_id, sp.user_id AS user_id, us.current_streak AS current_streak
  LOOP
    PERFORM public.enqueue_push(rec.user_id, 'streak_at_risk',
      jsonb_build_object('session_id', rec.session_id, 'streak', rec.current_streak));
  END LOOP;
END;
$$;

-- Not a client RPC: mirrors enqueue_scheduled_pushes/mark_no_shows/
-- push_drain_dispatch — unrestricted access would let anyone force at-risk
-- pushes ahead of schedule.
REVOKE EXECUTE ON FUNCTION public.enqueue_streak_at_risk_pushes() FROM PUBLIC, anon, authenticated;

-- Same every-minute cadence as push-enqueue/push-drain/mark-no-shows.
-- cron.schedule()'s upsert-by-jobname semantics (verified against this
-- project, documented in 20260716000003_push_cron.sql's header) make
-- re-applying this migration idempotent.
SELECT cron.schedule('streak-at-risk', '* * * * *',
  $$SELECT public.enqueue_streak_at_risk_pushes()$$);
