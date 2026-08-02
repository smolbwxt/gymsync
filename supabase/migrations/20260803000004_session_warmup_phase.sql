-- Warm-up phase with unanimous-ready vote (2026-08-01 user-approved
-- design): an organizer-set warm-up window precedes lifting. Every PRESENT
-- participant votes "I'm warm" (mark_warmup_ready); the moment the LAST
-- present participant votes, lifting begins for everyone. The organizer can
-- also force-start (start_lifting — the AFK escape hatch). Old clients are
-- unaffected: warmup_minutes defaults to 0 — no warm-up window, exactly
-- today's flow — and nothing server-side reads lifting_started_at yet.
--
-- "Present" is advance_turn's rotation predicate, verbatim
-- (20260802000001): check_in_state IN ('online','ready','late'). One
-- definition of "here", now used by rotation AND warm-up — invited/NULL
-- ghosts, no_shows and leavers can never hold the warm-up hostage, for
-- exactly the reason they can't hold the rotation.

-- ── 1. Schema: warm-up window + lifting gate + the vote ──────────────────
ALTER TABLE public.sessions
  ADD COLUMN warmup_minutes integer NOT NULL DEFAULT 0
    CHECK (warmup_minutes BETWEEN 0 AND 60);

COMMENT ON COLUMN public.sessions.warmup_minutes IS
  'Organizer-set warm-up window (minutes) between session start and '
  'lifting. 0 = no warm-up phase: pre-feature clients and sessions behave '
  'exactly as before.';

ALTER TABLE public.sessions
  ADD COLUMN lifting_started_at timestamptz;

COMMENT ON COLUMN public.sessions.lifting_started_at IS
  'When lifting actually began: set by the LAST present participant''s '
  'warm-up vote (mark_warmup_ready) or the organizer''s force-start '
  '(start_lifting). NULL while warming up — and on every pre-feature row.';

ALTER TABLE public.session_participants
  ADD COLUMN warmup_ready boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.session_participants.warmup_ready IS
  '"I''m warm" vote. When every PRESENT participant (advance_turn''s trio: '
  'online/ready/late) has voted, lifting begins immediately.';

-- ── 2. mark_warmup_ready: the unanimous-ready vote ───────────────────────
-- Returns true when lifting has now started — either this vote completed
-- unanimity, or lifting had already begun (organizer force-start / an
-- earlier unanimous vote) — false while the room is still waiting.
CREATE FUNCTION public.mark_warmup_ready(p_session_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_state              text;
  v_lifting_started_at timestamptz;
BEGIN
  -- Lock the session row to serialize concurrent votes (advance_turn's
  -- serialization point). Without it, two "last" voters racing under READ
  -- COMMITTED each see the other's warmup_ready = false and NEITHER opens
  -- lifting — classic write skew.
  SELECT state, lifting_started_at
    INTO v_state, v_lifting_started_at
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

  -- Authorization: caller must be a participant of this session. The vote
  -- itself is the membership probe — zero rows means not a participant
  -- (or no such session).
  UPDATE public.session_participants
     SET warmup_ready = true
   WHERE session_id = p_session_id
     AND user_id    = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'not a session participant' USING ERRCODE = 'P0001';
  END IF;

  -- Already lifting: report started so the caller's UI moves straight on.
  IF v_lifting_started_at IS NOT NULL THEN
    RETURN true;
  END IF;

  -- Unanimity only gates an in-progress session; a pre-start vote is
  -- recorded but cannot begin lifting.
  IF v_state IS DISTINCT FROM 'in_progress' THEN
    RETURN false;
  END IF;

  -- Unanimity: every PRESENT participant — advance_turn's rotation trio,
  -- verbatim (20260802000001) — has voted. Non-present states (invited /
  -- NULL, no_show, left) do not block.
  IF EXISTS (
       SELECT 1 FROM public.session_participants
        WHERE session_id = p_session_id
          AND check_in_state IN ('online', 'ready', 'late')
          AND NOT warmup_ready) THEN
    RETURN false;
  END IF;

  UPDATE public.sessions
     SET lifting_started_at = now()
   WHERE id = p_session_id;
  RETURN true;
END;
$$;

-- ── 3. start_lifting: organizer force-start (AFK escape hatch) ───────────
-- Returns true when THIS call started lifting; false when the session is
-- not in progress or lifting had already begun. Non-organizers are
-- rejected with P0001, the engine's authorization idiom (start_session,
-- advance_turn).
CREATE FUNCTION public.start_lifting(p_session_id uuid)
RETURNS boolean LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_organizer_id       uuid;
  v_state              text;
  v_lifting_started_at timestamptz;
BEGIN
  SELECT organizer_id, state, lifting_started_at
    INTO v_organizer_id, v_state, v_lifting_started_at
    FROM public.sessions
    WHERE id = p_session_id
    FOR UPDATE;

  IF v_organizer_id IS NULL OR auth.uid() IS DISTINCT FROM v_organizer_id THEN
    RAISE EXCEPTION 'only the organizer may start lifting' USING ERRCODE = 'P0001';
  END IF;

  IF v_state IS DISTINCT FROM 'in_progress' OR v_lifting_started_at IS NOT NULL THEN
    RETURN false;
  END IF;

  UPDATE public.sessions
     SET lifting_started_at = now()
   WHERE id = p_session_id;
  RETURN true;
END;
$$;

-- ── 4. Grants ────────────────────────────────────────────────────────────
-- House RPC idiom (20260721000001, 20260723000002): functions get PUBLIC
-- EXECUTE by default, which anon inherits, so REVOKE FROM PUBLIC, anon and
-- GRANT back explicitly TO authenticated. Do NOT include authenticated in
-- the REVOKE.
REVOKE EXECUTE ON FUNCTION public.mark_warmup_ready(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.mark_warmup_ready(uuid) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.start_lifting(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_lifting(uuid) TO authenticated;
