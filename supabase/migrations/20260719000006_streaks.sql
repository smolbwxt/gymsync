-- ============================================================
-- Phase S Task 3: user_streaks + group_streaks tables, lifecycle triggers
-- ============================================================
-- Design doc citations:
--   Schema (verbatim column set)  — docs/superpowers/specs/2026-06-28-gymsync-design.md:553-579
--   RLS narrative                 — same file:667-668
--   Flow 7 (all rules)            — same file:838-860
--
-- ── THE SCHEDULED-PREDICATE FINDING (cite everything) ───────────────────────
-- Flow 7's counting rule requires the session to have been `state='scheduled'`
-- at some point ("pre-planned via the schedule flow"). There is no state-
-- history table, so the honest, checkable-today predicate has to be a
-- column condition. Audit of every INSERT path into `public.sessions`
-- (grepped the whole Swift client + every migration for
-- `INSERT INTO public.sessions` / `.from("sessions").insert(...)` — exactly
-- two client call sites exist, no server-side RPC ever inserts a session):
--   • SessionRepository.startSolo(routineID:) (SessionRepository.swift:21-57)
--     — solo Quick Workout. Builds the row with `scheduledFor: nil` (line 36)
--     and `state: "in_progress"` (line 30). NEVER goes through 'scheduled'.
--   • SessionRepository.schedule(groupID:inviteeIDs:routineID:scheduledFor:
--     generateRoomCode:) (SessionRepository.swift:144-196) — the ONLY path
--     that ever sets `state: "scheduled"` (line 159), and it always supplies
--     a required (non-optional) `scheduledFor: Date` (line 148, formatted at
--     line 160). Used for BOTH solo-scheduled and group-scheduled sessions
--     (distinguished by whether `groupID` is nil), and by session-series
--     occurrence generation (20260713000001_session_series.sql), which also
--     always carries a concrete `scheduled_for`.
--   • `reschedule` (SessionRepository.swift:345-355) only UPDATEs
--     `scheduled_for` on a session that already has one (from `schedule()`);
--     no code path ever nulls it back out after the fact.
-- Conclusion: `scheduled_for IS NOT NULL` is 1:1 with "was scheduled at any
-- point" for every session that exists in this system today — startSolo()
-- is the only NULL-producing path and it never transitions through
-- 'scheduled'. This is the same predicate `mark_no_shows()` already relies
-- on (20260719000003_mark_no_shows.sql: `s.scheduled_for IS NOT NULL`) to
-- exclude ad-hoc sessions from the no-show sweep — reused here for the same
-- reason, not reinvented.
--
-- ── THE BREAK-MOMENT EQUIVALENCE (cite everything) ──────────────────────────
-- Flow 7: "the next scheduled session in your calendar reaches its
-- scheduled_for time and you were no_show" reads like it wants a *calendar
-- successor* check. It doesn't need one: `mark_no_shows()` is the ONLY
-- producer of `check_in_state = 'no_show'` in the whole codebase (confirmed
-- in 20260719000003's own header — "no code path has ever set ... no_show").
-- It fires every minute (cron) and flips a participant to no_show the
-- instant their session's `scheduled_for + no_show_after_minutes` elapses
-- (default 15 min) while they still have `check_in_at IS NULL`. Because that
-- flip happens in near-real-time relative to when the session was actually
-- due, "the next scheduled session reaches scheduled_for and you're
-- no_show" and "session_participants.check_in_state flips to no_show" are
-- the SAME moment in practice — there is no window in which a later
-- scheduled session could complete first and reorder the sequence. Firing
-- the break off the no_show UPDATE (per the design doc's own "Update
-- timing" paragraph, line ~858: trigger fires "on session_participants.
-- check_in_state flips to no_show") is therefore not an approximation of the
-- calendar rule, it IS the calendar rule's realization in this schema.
-- Corollary for `abandoned`: mark_no_shows() also sweeps 'in_progress'
-- sessions (not just 'lobby_open'), and its default 15-minute threshold is
-- far shorter than the 6-hour auto-abandon window
-- (20260716000004_reminder_window_fix.sql) — so by the time any session
-- reaches `state='abandoned'`, every never-checked-in participant has
-- already been flipped to no_show and already had their streak broken by
-- that trigger. The `abandoned` branch below still independently re-checks
-- `check_in_at IS NULL` per-participant (defense in depth for the case where
-- an organizer sets an unusually large `no_show_after_minutes` and abandon
-- fires first) — it's belt-and-braces, not the primary mechanism.
--
-- ── INDIVIDUAL vs GROUP BREAK RULE — a deliberate asymmetry ─────────────────
-- The Individual rule (line 845) lists TWO break conditions: no_show OR
-- abandoned-without-checkin. The Group rule (~line 852) lists only ONE:
-- "Breaks when any group session ends with a no_show." No abandoned clause
-- for groups. This migration honors that literal asymmetry: the `abandoned`
-- branch below only calls streak_break_user (never streak_break_group). Per
-- the break-moment equivalence above, this is a no-op distinction in
-- practice anyway (the group streak would already be broken by the earlier
-- no_show flip in the overwhelmingly common case), so no behavior gap opens
-- up — it just means we don't invent a rule the spec doesn't state.
--
-- ── RLS RECURSION HELPER (established precedent) ────────────────────────────
-- `is_friend()` follows the exact SECURITY DEFINER STABLE shape of
-- is_group_member/is_session_participant (20260709000006_create_sessions.
-- sql:32-39, 20260710000002_create_groups.sql:25-30). No `is_friend` helper
-- existed before this migration — the design doc's own set_logs RLS
-- narrative (line ~627) describes a "friends can read" rule that was never
-- actually implemented in 20260709000007_create_set_logs.sql, so there is
-- no prior friend-read policy to copy; this is the first one, built to the
-- same idiom.
--
-- ── TRIGGER-ONLY WRITES (established precedent) ─────────────────────────────
-- Both tables get RLS enabled with a SELECT-only policy each — no INSERT/
-- UPDATE/DELETE policy for `authenticated` exists at all, so those commands
-- are rejected outright (42501) for any client role. The four small
-- streak_bump_*/streak_break_* helper functions and the two AFTER-trigger
-- functions are all `SECURITY DEFINER`, owned by the migration role
-- (postgres), which — same as `increment_lifetime_volume` writing to
-- `profiles` (20260709000008_lifetime_volume_trigger.sql) despite profiles'
-- own restrictive RLS — is exempt from its own tables' RLS as table owner.
-- The four helper functions are additionally REVOKEd from
-- PUBLIC/anon/authenticated (mirrors mark_no_shows()'s "not a client RPC"
-- REVOKE, 20260719000003_mark_no_shows.sql) so a client can't bypass the
-- table RLS by calling the helper directly instead of writing the table.
-- ============================================================

-- ── 1. Tables (verbatim per design doc) ─────────────────────────────────────
CREATE TABLE public.user_streaks (
  user_id                 uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  current_streak          integer DEFAULT 0,
  longest_streak          integer DEFAULT 0,
  last_streak_session_id  uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  broken_at               timestamptz,
  broken_by_session_id    uuid REFERENCES public.sessions(id) ON DELETE SET NULL
);

CREATE TABLE public.group_streaks (
  group_id                uuid PRIMARY KEY REFERENCES public.groups(id) ON DELETE CASCADE,
  current_streak          integer DEFAULT 0,
  longest_streak          integer DEFAULT 0,
  last_streak_session_id  uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  broken_at               timestamptz,
  broken_by_session_id    uuid REFERENCES public.sessions(id) ON DELETE SET NULL
);

ALTER TABLE public.user_streaks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_streaks ENABLE ROW LEVEL SECURITY;

-- ── 2. RLS helper: friendship (accepted, either direction) ──────────────────
CREATE OR REPLACE FUNCTION public.is_friend(p_user_id uuid, p_viewer_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.friendships
    WHERE status = 'accepted'
      AND ((user_id = p_user_id AND friend_id = p_viewer_id)
        OR (user_id = p_viewer_id AND friend_id = p_user_id))
  );
$$;

-- ── 3. RLS policies — SELECT only; no write policy on either table ─────────
CREATE POLICY "owner and friends can read user streaks"
  ON public.user_streaks FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR public.is_friend(user_streaks.user_id, auth.uid())
  );

CREATE POLICY "members can read group streaks"
  ON public.group_streaks FOR SELECT TO authenticated
  USING (public.is_group_member(group_streaks.group_id, auth.uid()));

-- ── 4. Increment/break primitives (shared by both trigger functions) ───────
-- Idempotency guard lives here (not just in the trigger's state-diff check):
-- if `last_streak_session_id` already equals the session being credited,
-- the bump is skipped. This survives not just a same-state UPDATE refire
-- (already caught by `NEW.state IS NOT DISTINCT FROM OLD.state` in the
-- trigger below) but also a hypothetical state-bounce
-- (completed -> in_progress -> completed) that would defeat a pure
-- state-diff guard.
CREATE OR REPLACE FUNCTION public.streak_bump_user(p_user_id uuid, p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_current integer;
  v_longest integer;
  v_last    uuid;
BEGIN
  INSERT INTO public.user_streaks (user_id) VALUES (p_user_id)
    ON CONFLICT (user_id) DO NOTHING;

  SELECT current_streak, longest_streak, last_streak_session_id
    INTO v_current, v_longest, v_last
    FROM public.user_streaks
    WHERE user_id = p_user_id
    FOR UPDATE;

  IF v_last IS NOT DISTINCT FROM p_session_id THEN
    RETURN;  -- already credited for this exact session
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
  v_current integer;
  v_longest integer;
  v_last    uuid;
BEGIN
  INSERT INTO public.group_streaks (group_id) VALUES (p_group_id)
    ON CONFLICT (group_id) DO NOTHING;

  SELECT current_streak, longest_streak, last_streak_session_id
    INTO v_current, v_longest, v_last
    FROM public.group_streaks
    WHERE group_id = p_group_id
    FOR UPDATE;

  IF v_last IS NOT DISTINCT FROM p_session_id THEN
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

-- Break: zero current_streak, stamp broken_at/broken_by_session_id.
-- longest_streak is deliberately untouched — the watermark must survive a
-- break (pgTAP matrix item). Unconditional (no idempotency guard needed):
-- re-applying the same break twice is a harmless no-op (0 -> 0, same
-- broken_by_session_id written again).
CREATE OR REPLACE FUNCTION public.streak_break_user(p_user_id uuid, p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.user_streaks (user_id, current_streak, broken_at, broken_by_session_id)
  VALUES (p_user_id, 0, now(), p_session_id)
  ON CONFLICT (user_id) DO UPDATE
    SET current_streak = 0,
        broken_at = now(),
        broken_by_session_id = p_session_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.streak_break_group(p_group_id uuid, p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.group_streaks (group_id, current_streak, broken_at, broken_by_session_id)
  VALUES (p_group_id, 0, now(), p_session_id)
  ON CONFLICT (group_id) DO UPDATE
    SET current_streak = 0,
        broken_at = now(),
        broken_by_session_id = p_session_id;
END;
$$;

-- Internal plumbing only, called exclusively from the trigger functions
-- below (which run as the SECURITY DEFINER owner already, so the REVOKE
-- does not block their PERFORM calls) — never a client RPC.
REVOKE EXECUTE ON FUNCTION public.streak_bump_user(uuid, uuid)   FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.streak_bump_group(uuid, uuid)  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.streak_break_user(uuid, uuid)  FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.streak_break_group(uuid, uuid) FROM PUBLIC, anon, authenticated;

-- ── 5. Trigger: session_participants.check_in_state -> no_show ─────────────
-- Breaks the individual (always) and the group streak (if this is a group
-- session) at the moment of the no_show flip — see the break-moment
-- equivalence note above for why this IS the "next scheduled session
-- reaches scheduled_for" rule, not an approximation of it.
CREATE OR REPLACE FUNCTION public.streak_on_no_show()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_group_id       uuid;
  v_scheduled_for  timestamptz;
BEGIN
  -- Only a genuine transition INTO no_show recomputes anything.
  IF NEW.check_in_state IS DISTINCT FROM 'no_show'
     OR OLD.check_in_state IS NOT DISTINCT FROM 'no_show' THEN
    RETURN NEW;
  END IF;

  SELECT s.group_id, s.scheduled_for INTO v_group_id, v_scheduled_for
    FROM public.sessions s WHERE s.id = NEW.session_id;

  -- Defensive: mark_no_shows() itself only ever operates on
  -- `scheduled_for IS NOT NULL` sessions, so this should be unreachable in
  -- practice, but Flow 7 is explicit that ad-hoc lifts never touch the
  -- streak either way.
  IF v_scheduled_for IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM public.streak_break_user(NEW.user_id, NEW.session_id);

  IF v_group_id IS NOT NULL THEN
    PERFORM public.streak_break_group(v_group_id, NEW.session_id);
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS streak_no_show_break ON public.session_participants;
CREATE TRIGGER streak_no_show_break
  AFTER UPDATE OF check_in_state ON public.session_participants
  FOR EACH ROW EXECUTE FUNCTION public.streak_on_no_show();

-- ── 6. Trigger: sessions.state -> completed / abandoned ─────────────────────
CREATE OR REPLACE FUNCTION public.streak_on_session_state_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec         RECORD;
  v_all_ready boolean;
BEGIN
  -- State-diff guard: same-state refires (e.g. an UPDATE that only touches
  -- completed_at on an already-'completed' row) never recompute anything.
  IF NEW.state IS NOT DISTINCT FROM OLD.state THEN
    RETURN NEW;
  END IF;
  IF NEW.state NOT IN ('completed', 'abandoned') THEN
    RETURN NEW;
  END IF;
  -- Ad-hoc / unscheduled sessions (Quick Workout) never touch anyone's
  -- streak — see the scheduled-predicate finding above.
  IF NEW.scheduled_for IS NULL THEN
    RETURN NEW;
  END IF;

  IF NEW.state = 'completed' THEN
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
    -- No group-streak break here by design — see the "deliberate asymmetry"
    -- note above (Flow 7's group rule only names no_show).
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS streak_on_session_completion ON public.sessions;
CREATE TRIGGER streak_on_session_completion
  AFTER UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.streak_on_session_state_change();
