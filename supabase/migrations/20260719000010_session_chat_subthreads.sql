-- ============================================================
-- Phase F / Task 2: session sub-thread chat — backend
-- ============================================================
-- Master spec (docs/superpowers/specs/2026-06-28-gymsync-design.md, §Chat):
--   chat_messages.session_id uuid REFERENCES sessions(id) — NULL = group-level
--   chat; NOT NULL = session sub-thread.
-- Phase spec (docs/superpowers/specs/2026-07-16-social-finishers-design.md,
-- §1): participants-only read/write for sub-thread rows; existing
-- group-level behavior untouched; system-message producers untouched.
--
-- FINDING: the session_id column already exists — it has been on
-- chat_messages since the table's creation
-- (20260710000003_create_chat.sql: "session_id uuid REFERENCES
-- public.sessions(id) ON DELETE SET NULL"). No RLS policy has ever looked at
-- it and no index covered it — every row, sub-thread or not, was gated
-- purely by group membership. This migration is what actually wires it up;
-- there is no ADD COLUMN here.
--
-- FINDING: solo/ad-hoc sessions (sessions.group_id IS NULL, added by
-- 20260712000001_sessions_phase3_columns.sql) have no group to attach a
-- sub-thread message to, yet chat_messages.group_id was NOT NULL. The task
-- brief's design decision — "for solo/ad-hoc sessions (group_id NULL) the
-- row's group_id is NULL" — is therefore not just a policy question, it
-- requires a schema change: group_id must become nullable. Without this, a
-- solo session's chat sub-thread cannot exist at all (there is no group to
-- reference). This is a deliberate, minimal schema change to unblock the
-- explicitly-requested "solo session (group_id NULL) thread: participant can
-- read/write" pgTAP case, not scope creep — recorded here since the brief
-- text describes it as a foregone fact rather than a change to make.
--
-- Verified safe: every other place that reads chat_messages.group_id is
-- either (a) a SECURITY DEFINER helper built on is_group_member(), which
-- already treats a NULL group_id as "not a member of anything" (WHERE
-- group_id = NULL is never true — no error, no match), or (b) an AFTER
-- INSERT trigger keyed on NEW.group_id (push_partner_pr, push_chat_mention
-- in 20260716000001_push_schema.sql; touch_session_activity_on_chat in
-- 20260716000003_push_cron.sql) which simply matches zero rows for a NULL
-- group_id and no-ops. None of these raise on NULL.

-- ── 1. group_id becomes nullable ────────────────────────────────────────────
ALTER TABLE public.chat_messages ALTER COLUMN group_id DROP NOT NULL;

-- ── 2. Index for sub-thread reads ───────────────────────────────────────────
-- Partial: only sub-thread rows are ever queried by session_id.
CREATE INDEX chat_messages_session_created_idx
  ON public.chat_messages(session_id, created_at DESC)
  WHERE session_id IS NOT NULL;

-- ── 3. SELECT policy — fix-forward replace ──────────────────────────────────
-- The existing policy (unchanged since 20260710000003_create_chat.sql) is a
-- single FOR SELECT policy with no session_id awareness:
--   USING (public.is_group_member(chat_messages.group_id, auth.uid()))
-- Postgres OR-combines multiple *permissive* policies for the same command,
-- so simply ADDING a second "session participants" policy would not achieve
-- participants-only semantics: this old policy would still match
-- session-thread rows (a group-backed session's rows keep group_id = that
-- group) and grant read access to every group member, participant or not —
-- the opposite of the "participants-only" reading the phase spec calls for.
-- The policy must be narrowed, not just supplemented, hence the fix-forward
-- drop + recreate (per task brief instruction).
DROP POLICY "group members read messages" ON public.chat_messages;
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    -- session_id IS NULL rows: verbatim pre-existing behavior, unchanged.
    (chat_messages.session_id IS NULL
     AND public.is_group_member(chat_messages.group_id, auth.uid()))
    -- session_id IS NOT NULL rows: participants only. A group member who is
    -- NOT a participant of this specific session cannot read its thread,
    -- even though the row's group_id may equal a group they belong to.
    OR (chat_messages.session_id IS NOT NULL
        AND public.is_session_participant(chat_messages.session_id, auth.uid()))
  );

-- ── 4. INSERT policy — fix-forward replace (same reasoning as #3) ──────────
-- Current version lives in 20260715000001_comms_schema.sql
-- ("members send client messages as themselves" — the same additive-
-- composition trap applies: a group-id-only check doesn't look at
-- session_id, so a group member could otherwise post into a session thread
-- they never joined).
DROP POLICY "members send client messages as themselves" ON public.chat_messages;
CREATE POLICY "members send client messages as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text', 'image', 'audio', 'soundboard_echo')
    AND (kind NOT IN ('image', 'audio') OR storage_path IS NOT NULL)
    AND (kind <> 'soundboard_echo' OR payload IS NOT NULL)
    AND (
      (chat_messages.session_id IS NULL
       AND public.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid()))
    )
  );

-- ── 5. Deliberately untouched — documented, not silently dropped ───────────
--
-- UPDATE ("author edits own messages", last touched in
-- 20260715000001_comms_schema.sql) is still gated by
-- is_group_member(chat_messages.group_id, auth.uid()) only, with no
-- session_id branch. For a group-backed session's sub-thread rows this is
-- unaffected (group_id is the session's real group). For a SOLO session's
-- sub-thread rows (group_id now NULL) this means the author cannot
-- edit/soft-delete their own sub-thread message. The task brief scopes this
-- task to rows that are "readable + insertable" by participants — edit/
-- delete was not requested. Flagged as a follow-up, not silently broken.
--
-- chat_read_state stays group-scoped, per task brief — sub-thread unread
-- tracking is explicitly out of scope for this task.
--
-- chat_message_reactions ("group members read/react messages",
-- 20260710000003_create_chat.sql) is keyed through
-- message_group_id() -> is_group_member(). For a solo session's sub-thread
-- messages (group_id now NULL) this evaluates to false for everyone,
-- including the thread's own participants — reactions on solo sub-thread
-- messages are unreachable today. Same story: not requested by this task,
-- flagged rather than silently broken by the group_id nullability change.
--
-- Realtime publication: chat_messages was added to supabase_realtime in
-- 20260710000003_create_chat.sql ("ALTER PUBLICATION supabase_realtime ADD
-- TABLE public.chat_messages") and has never been removed. Publication
-- membership is table-level, not row- or policy-scoped — sub-thread rows
-- ride the exact same publication automatically. RLS (WALRUS) is what scopes
-- the postgres_changes events actually delivered to each subscriber, and the
-- policy changes above (#3) are what make that scoping participants-only for
-- session threads. No publication migration needed here.
