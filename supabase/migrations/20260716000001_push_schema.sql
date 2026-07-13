-- ============================================================
-- Phase 3d Task 1: Push notification schema
-- Devices, per-category prefs, service-role-only outbox queue,
-- and the row-trigger-driven notification events.
-- ============================================================

-- ── push_devices ────────────────────────────────────────────────────────────
-- Spec §3 (design doc lines 200-205) + owner-only RLS (line 648).
CREATE TABLE public.push_devices (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  apns_token   text UNIQUE NOT NULL,
  last_seen_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX push_devices_user_id_idx ON public.push_devices(user_id);

ALTER TABLE public.push_devices ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner manages own devices"
  ON public.push_devices FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- ── notification_prefs ──────────────────────────────────────────────────────
-- Not in the spec's Data Model — designed here per the designer brief's
-- 10-category opt-out list (2026-07-12-design-request-next-phases.md).
-- Absence of a row = enabled (spec line 1179: "Defaults: all on for v1").
CREATE TABLE public.notification_prefs (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  category   text NOT NULL CHECK (category IN (
               'friend_request', 'session_invite', 'session_reminder_15min',
               'session_lobby_open', 'your_turn', 'partner_pr', 'lateness_chirp',
               'session_idle', 'chat_mention', 'leaderboard_passed'
             )),
  enabled    boolean NOT NULL DEFAULT true,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, category)
);

ALTER TABLE public.notification_prefs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "owner manages own prefs"
  ON public.notification_prefs FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());


-- ── push_queue ───────────────────────────────────────────────────────────────
-- The outbox: push-dispatcher (a later task's Edge Function, running under the
-- service role) drains this. RLS is enabled with ZERO policies on purpose —
-- clients must never read or write the queue directly (no opt-in-only category
-- leakage, no client-side spoofed pushes). Only the service role (which
-- bypasses RLS) and SECURITY DEFINER functions (enqueue_push, below) can
-- touch this table.
CREATE TABLE public.push_queue (
  id         bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  event      text NOT NULL,
  payload    jsonb NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  sent_at    timestamptz,
  attempts   int NOT NULL DEFAULT 0
);
CREATE INDEX push_queue_unsent_idx ON public.push_queue(sent_at) WHERE sent_at IS NULL;

ALTER TABLE public.push_queue ENABLE ROW LEVEL SECURITY;
-- No CREATE POLICY statements here — intentional. See comment above.


-- ── push_event_category: event name -> notification_prefs category ─────────
-- Pure lookup, no table access, so no elevated privilege needed.
--
-- The idle ladder (spec Flow 6, design doc lines 817-829) fires two distinct
-- raw event names — session_idle_30min (organizer only) and
-- session_idle_60min (all participants) — but the designer's 10-category
-- opt-out list (Feature 2) has exactly ONE toggle for both ("Idle session
-- nudges" -> 'session_idle'). There is no separate 30-min/60-min switch in
-- the UI, so both collapse to the same category here. enqueue_push (below)
-- is what actually gates delivery on this category.
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
    ELSE NULL
  END;
$$;


-- ── enqueue_push: the single write path into push_queue ────────────────────
-- SECURITY DEFINER so the event triggers below (which run under whatever
-- role/RLS context fired the originating INSERT/UPDATE) can still write to
-- the policy-less push_queue table. Suppresses delivery only when the
-- recipient has an explicit notification_prefs row with enabled=false for
-- the event's category — absence of a row always means "on" (default-on per
-- spec). Callers are responsible for passing the correct recipient(s); this
-- function does not itself exclude the acting user.
CREATE OR REPLACE FUNCTION public.enqueue_push(p_user uuid, p_event text, p_payload jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_category text;
BEGIN
  v_category := public.push_event_category(p_event);

  IF v_category IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.notification_prefs
    WHERE user_id = p_user AND category = v_category AND enabled = false
  ) THEN
    RETURN;
  END IF;

  INSERT INTO public.push_queue (user_id, event, payload)
  VALUES (p_user, p_event, COALESCE(p_payload, '{}'::jsonb));
END;
$$;


-- ============================================================
-- Event triggers
-- ============================================================
-- All new trigger names are prefixed "zzpush_" so that, on tables with
-- pre-existing AFTER triggers on the same event (currently only
-- public.sessions: session_lifecycle_announce fires on the same
-- INSERT/UPDATE OF state event as zzpush_session_lobby_open), Postgres's
-- alphabetical same-event firing order guarantees ours runs last. The two
-- are independent (one writes chat_messages, the other writes push_queue)
-- so ordering doesn't change correctness today, but this keeps future
-- additions safe without re-auditing fire order.

-- ── friend_request: AFTER INSERT ON friendships (status='pending') ─────────
-- Recipient is friend_id (see 20260710000001_create_friendships.sql: the
-- requester-creates-pending-request policy pins user_id = the requester,
-- friend_id = the recipient).
CREATE OR REPLACE FUNCTION public.push_friend_request() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.status = 'pending' THEN
    PERFORM public.enqueue_push(NEW.friend_id, 'friend_request',
      jsonb_build_object('from_user_id', NEW.user_id));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_friend_request AFTER INSERT ON public.friendships
  FOR EACH ROW EXECUTE FUNCTION public.push_friend_request();


-- ── session_invite: AFTER INSERT ON session_participants ───────────────────
-- Skip the organizer's own participant row (they are the inviter, not an
-- invitee). All other inserted rows (organizer-added invites, late-joiner
-- auto-invites from invite_new_member_to_future_sessions, room-code
-- self-joins) push the invitee.
CREATE OR REPLACE FUNCTION public.push_session_invite() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id   uuid;
  v_organizer_name text;
BEGIN
  SELECT s.organizer_id, p.username INTO v_organizer_id, v_organizer_name
    FROM public.sessions s
    JOIN public.profiles p ON p.id = s.organizer_id
   WHERE s.id = NEW.session_id;

  IF v_organizer_id IS DISTINCT FROM NEW.user_id THEN
    PERFORM public.enqueue_push(NEW.user_id, 'session_invite',
      jsonb_build_object('session_id', NEW.session_id,
                         'organizer_id', v_organizer_id,
                         'organizer_username', v_organizer_name));
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_session_invite AFTER INSERT ON public.session_participants
  FOR EACH ROW EXECUTE FUNCTION public.push_session_invite();


-- ── session_lobby_open: AFTER UPDATE OF state ON sessions ───────────────────
-- Fires only on the transition INTO lobby_open. Recipients are participants
-- who aren't already "present" — check_in_state IN ('online','ready','late')
-- means they got there some other way (e.g. joined by room code before the
-- transition) and don't need to be told the lobby just opened.
CREATE OR REPLACE FUNCTION public.push_session_lobby_open() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.state IS DISTINCT FROM 'lobby_open' OR OLD.state IS NOT DISTINCT FROM 'lobby_open' THEN
    RETURN NEW;
  END IF;

  PERFORM public.enqueue_push(sp.user_id, 'session_lobby_open',
    jsonb_build_object('session_id', NEW.id))
  FROM public.session_participants sp
  WHERE sp.session_id = NEW.id
    AND COALESCE(sp.check_in_state, 'invited') NOT IN ('online', 'ready', 'late');

  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_session_lobby_open
  AFTER UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.push_session_lobby_open();


-- ── your_turn: AFTER UPDATE OF current_turn_user_id ON sessions ─────────────
CREATE OR REPLACE FUNCTION public.push_your_turn() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.current_turn_user_id IS DISTINCT FROM OLD.current_turn_user_id
     AND NEW.current_turn_user_id IS NOT NULL THEN
    PERFORM public.enqueue_push(NEW.current_turn_user_id, 'your_turn',
      jsonb_build_object('session_id', NEW.id));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_your_turn
  AFTER UPDATE OF current_turn_user_id ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.push_your_turn();


-- ── partner_pr: AFTER INSERT ON chat_messages (kind='system_pr') ───────────
-- announce_pr() (20260710000004_pr_system_messages.sql) already fans a
-- system_pr chat_messages row out to every group the lifter belongs to
-- (author_id is always NULL for system rows; the PR-scorer's id lives in
-- payload->>'user_id'). This trigger fires per chat_messages row (i.e. per
-- group) and enqueues a push to every group member except the PR scorer.
CREATE OR REPLACE FUNCTION public.push_partner_pr() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_pr_user_id uuid;
BEGIN
  IF NEW.kind <> 'system_pr' THEN
    RETURN NEW;
  END IF;

  v_pr_user_id := (NEW.payload ->> 'user_id')::uuid;

  PERFORM public.enqueue_push(gm.user_id, 'partner_pr',
    jsonb_build_object('group_id', NEW.group_id, 'message_id', NEW.id,
                       'pr_user_id', v_pr_user_id))
  FROM public.group_members gm
  WHERE gm.group_id = NEW.group_id
    AND gm.user_id IS DISTINCT FROM v_pr_user_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_partner_pr AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.push_partner_pr();


-- ── lateness_chirp: AFTER UPDATE OF check_in_state ON session_participants ──
-- Fires only on the transition INTO 'late'. Recipients are the OTHER
-- participants in the same session.
CREATE OR REPLACE FUNCTION public.push_lateness_chirp() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.check_in_state IS DISTINCT FROM 'late' OR OLD.check_in_state IS NOT DISTINCT FROM 'late' THEN
    RETURN NEW;
  END IF;

  PERFORM public.enqueue_push(sp.user_id, 'lateness_chirp',
    jsonb_build_object('session_id', NEW.session_id, 'late_user_id', NEW.user_id))
  FROM public.session_participants sp
  WHERE sp.session_id = NEW.session_id
    AND sp.user_id <> NEW.user_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_lateness_chirp
  AFTER UPDATE OF check_in_state ON public.session_participants
  FOR EACH ROW EXECUTE FUNCTION public.push_lateness_chirp();


-- ── chat_mention: AFTER INSERT ON chat_messages (kind='text') ──────────────
-- Parses @username tokens out of the message body, matches them
-- case-insensitively against group members' profiles (same lower(username)
-- convention as profiles_username_lower_idx), and pushes each distinct
-- mentioned member except the author. Non-members and unmatched handles are
-- silently ignored (no row, no error).
CREATE OR REPLACE FUNCTION public.push_chat_mention() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_handle text;
BEGIN
  IF NEW.kind <> 'text' OR NEW.body IS NULL THEN
    RETURN NEW;
  END IF;

  FOR v_handle IN
    SELECT DISTINCT lower(m[1])
    FROM regexp_matches(NEW.body, '@([A-Za-z0-9_]+)', 'g') AS m
  LOOP
    PERFORM public.enqueue_push(gm.user_id, 'chat_mention',
      jsonb_build_object('group_id', NEW.group_id, 'message_id', NEW.id,
                         'mentioned_username', v_handle))
    FROM public.group_members gm
    JOIN public.profiles p ON p.id = gm.user_id
    WHERE gm.group_id = NEW.group_id
      AND lower(p.username) = v_handle
      AND gm.user_id IS DISTINCT FROM NEW.author_id;
  END LOOP;

  RETURN NEW;
END;
$$;

CREATE TRIGGER zzpush_chat_mention AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.push_chat_mention();
