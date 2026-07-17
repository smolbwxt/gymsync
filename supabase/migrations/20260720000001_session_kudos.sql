-- ============================================================
-- Phase F / Task 4: kudos backend — session_kudos table + RLS + realtime.
-- ============================================================
-- Spec (docs/superpowers/specs/2026-07-16-social-finishers-design.md, §2):
--   "session_kudos table (id, session_id FK, sender_id, recipient_id, emoji
--   text, created_at; one row per tap; rate-limit client-side like
--   soundboard's 1/sec discipline). RLS: participants of the session
--   read/insert (sender = auth.uid()); no update/delete v1. Realtime
--   publication so recap counts update live."
--
-- Emoji set verified against proof-frame-08.png ("SEND KUDOS TO THE CREW"
-- row, five boxes left-to-right): flexed bicep, fire, clapping hands,
-- trophy, lightning bolt — 💪 🔥 👏 🏆 ⚡. Matches spec §2's listed set
-- verbatim; CHECK constraint below is the enforcement point.
--
-- one-row-per-tap: deliberately no UNIQUE/upsert constraint on
-- (session_id, sender_id, recipient_id) — repeated taps from the same
-- sender to the same recipient are additional rows, not an incrementing
-- counter column. The recap's per-recipient kudos count is a client-side
-- COUNT(*) GROUP BY recipient_id over these rows (see GroupRecapView).
--
-- No sender<>recipient CHECK: the UI's send row is crew-wide (fires one
-- INSERT per OTHER participant per tap — see GroupRecapView's
-- kudos-send model), so a self-targeted row is never produced by the
-- client. Not worth enforcing server-side for v1 (no spec requirement, no
-- harm if it ever happened) — documented rather than silently omitted.

CREATE TABLE public.session_kudos (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id   uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  sender_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  recipient_id uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji        text NOT NULL CHECK (emoji IN ('💪', '🔥', '👏', '🏆', '⚡')),
  created_at   timestamptz NOT NULL DEFAULT now()
);

-- Recap's leaderboard reads/aggregates "kudos received per recipient,
-- within this session" — that's the query this index serves.
CREATE INDEX session_kudos_session_recipient_idx
  ON public.session_kudos(session_id, recipient_id);

ALTER TABLE public.session_kudos ENABLE ROW LEVEL SECURITY;

-- SELECT: any participant of the session can read every kudos row for it
-- (the leaderboard shows everyone's received count to everyone, not just
-- your own — proof-frame-08.png shows all four lifters' counts at once).
-- is_session_participant() is the same SECURITY DEFINER helper
-- session_participants/chat_messages/chat_message_reactions already use to
-- break the sessions<->session_participants RLS recursion
-- (20260715000002_personal_records.sql:32-39 defines it).
CREATE POLICY "session participants read kudos"
  ON public.session_kudos FOR SELECT TO authenticated
  USING (public.is_session_participant(session_kudos.session_id, auth.uid()));

-- INSERT: three-part gate —
--   1. sender-spoof guard: sender_id must equal the caller's own uid.
--   2. sender must actually be a participant of the session.
--   3. recipient must ALSO be a participant of the SAME session — same
--      discipline as the chat sub-thread group-binding fix
--      (20260719000011_chat_subthread_lock_hardening.sql, Finding 2: a
--      WITH CHECK subquery/helper call binds a foreign key to a value it
--      must actually match, not a client-supplied id trusted at face
--      value). Without this, a participant could tap kudos at an
--      arbitrary profile id who never worked out in the session, corrupting
--      the recap's per-member kudos-received counts and leaderboard.
CREATE POLICY "session participants send kudos to session participants"
  ON public.session_kudos FOR INSERT TO authenticated
  WITH CHECK (
    sender_id = auth.uid()
    AND public.is_session_participant(session_kudos.session_id, auth.uid())
    AND public.is_session_participant(session_kudos.session_id, recipient_id)
  );

-- No UPDATE/DELETE policies — v1 is append-only per spec §2 ("no
-- update/delete v1"): a kudos tap is never edited or retracted. With RLS
-- enabled and no policy for a command, Postgres denies that command by
-- default (zero rows visible/matched — not an error; proven in pgTAP as
-- "0 rows affected", mirroring personal_records' immutability tests).

-- Realtime publication — same migration as the table (repo doctrine,
-- plan's Global Constraints: "every postgres_changes consumer ships its
-- publication migration in the same task"). RLS above (SELECT policy) is
-- what scopes the WALRUS-delivered postgres_changes events to session
-- participants only; publication membership itself is table-level.
ALTER PUBLICATION supabase_realtime ADD TABLE public.session_kudos;
