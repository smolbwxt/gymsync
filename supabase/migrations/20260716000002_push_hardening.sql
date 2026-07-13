-- ============================================================
-- Phase 3d Task 1: Push hardening — fix-forward round 1
-- 20260716000001_push_schema.sql is already applied; append-only rules mean
-- fixes land here rather than editing that file in place.
-- ============================================================

-- ── FIX 1 (Critical): revoke client EXECUTE on enqueue_push ─────────────────
-- PostgREST exposes every public-schema function as an RPC endpoint, and
-- Postgres grants EXECUTE on newly created functions to PUBLIC by default —
-- which anon/authenticated inherit. Without this revoke, any client can call
-- enqueue_push(uuid, text, jsonb) directly and enqueue arbitrary pushes to
-- any user (bypassing the event triggers entirely). Triggers and other
-- SECURITY DEFINER functions are unaffected: they run as the function owner,
-- not as the calling client role.
REVOKE EXECUTE ON FUNCTION public.enqueue_push(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;


-- ── FIX 2 (Important): suppress self-initiated session_invite pushes ────────
-- Room-code self-joins (join_session_by_code) and group-join auto-invites
-- (invite_new_member_to_future_sessions) insert a session_participants row
-- where the acting user IS the invitee — those are self-initiated actions,
-- not an invite from someone else, so no "you were invited" push should
-- fire. Organizer-inserted invitee rows are unaffected: the organizer
-- (acting user) is never the invitee, so the new guard doesn't match and the
-- push still fires. Mirrors the engine_guard self-check idiom from
-- 20260714000001_session_engine_rpcs.sql. Every other part of the function
-- is copied forward unchanged from 20260716000001_push_schema.sql.
CREATE OR REPLACE FUNCTION public.push_session_invite() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id   uuid;
  v_organizer_name text;
BEGIN
  -- Self-initiated insert (acting user == invitee): suppress the push.
  IF NEW.user_id::text = current_setting('request.jwt.claim.sub', true) THEN
    RETURN NEW;
  END IF;

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
-- Trigger zzpush_session_invite (AFTER INSERT ON session_participants)
-- already points at this function by name — no re-CREATE TRIGGER needed.
