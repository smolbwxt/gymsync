-- ============================================================
-- Pump Check P1: workout_posts + post_reactions + workout-photos bucket.
-- Spec: docs/superpowers/specs/2026-07-27-pump-check-design.md
-- ============================================================
-- A post is an IMMUTABLE SNAPSHOT of a finished workout: photo (optional),
-- denormalized summary jsonb (exercises/sets frozen at post time — later
-- set edits never rewrite history, and the feed renders with zero joins
-- into set_logs), opt-in HR aggregates, and a BeReal-style late flag.
--
-- Visibility = the solo-workout-privacy posture verbatim
-- (20260725000004): author, or an ACCEPTED friend with no block in either
-- direction. private.is_friend / private.is_blocked are the established
-- SECURITY DEFINER helpers; block-severs-friendship (20260722000003) makes
-- the is_blocked clauses belt-and-suspenders, kept anyway — a policy that
-- relies on a trigger having fired elsewhere is a policy with a
-- prerequisite.

-- ── 1. workout_posts ─────────────────────────────────────────────────────
CREATE TABLE public.workout_posts (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id  uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  -- storage object path ('posts/{author_id}/{post_id}.jpg'); NULL = a
  -- summary-only post (the 1-minute window lapsed and they skipped the
  -- photo, or chose not to take one).
  photo_path  text,
  -- Snapshot at post time: { duration_seconds, total_volume_lbs,
  -- exercises: [{ name, equipment, sets: [{ weight_lbs, reps, is_pr,
  -- is_failed }] }] }. Weights canonical POUNDS (Units doctrine); the
  -- client renders in the VIEWER'S unit.
  summary     jsonb NOT NULL CHECK (jsonb_typeof(summary) = 'object'),
  includes_hr boolean NOT NULL DEFAULT false,
  avg_bpm     integer CHECK (avg_bpm > 0 AND avg_bpm < 250),
  max_bpm     integer CHECK (max_bpm > 0 AND max_bpm < 250),
  -- HR fields may only carry values when the per-post toggle was ON.
  CHECK (includes_hr OR (avg_bpm IS NULL AND max_bpm IS NULL)),
  is_late     boolean NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- Feed reads newest-first with keyset pagination on created_at; RLS
-- filters to friends. Author index serves profile/own-post lookups and the
-- storage policy's per-author path convention.
CREATE INDEX workout_posts_created_at_idx ON public.workout_posts(created_at DESC);
CREATE INDEX workout_posts_author_created_idx ON public.workout_posts(author_id, created_at DESC);

ALTER TABLE public.workout_posts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "posts visible to author and unblocked accepted friends"
  ON public.workout_posts FOR SELECT TO authenticated
  USING (
    author_id = auth.uid()
    OR (
      private.is_friend(workout_posts.author_id, auth.uid())
      AND NOT private.is_blocked(workout_posts.author_id, auth.uid())
      AND NOT private.is_blocked(auth.uid(), workout_posts.author_id)
    )
  );

-- INSERT: self-authored, and only about a session the author was actually
-- in (is_session_participant — same integrity discipline as kudos'
-- recipient-binding, 20260720000001). No posting about other people's
-- workouts.
CREATE POLICY "author posts own finished session"
  ON public.workout_posts FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND public.is_session_participant(workout_posts.session_id, auth.uid())
  );

-- DELETE: author only. NO UPDATE POLICY — posts are immutable snapshots;
-- an UPDATE from any client matches no row and silently affects nothing.
CREATE POLICY "author deletes own post"
  ON public.workout_posts FOR DELETE TO authenticated
  USING (author_id = auth.uid());

-- ── 2. post_reactions ────────────────────────────────────────────────────
-- Kudos-emoji tap reactions (spec decision 3). Unlike session_kudos'
-- one-row-per-tap, reactions TOGGLE: PK (post_id, user_id, emoji), insert
-- to react, delete your own row to unreact.
CREATE TABLE public.post_reactions (
  post_id    uuid NOT NULL REFERENCES public.workout_posts(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji      text NOT NULL CHECK (emoji IN ('💪', '🔥', '👏', '🏆', '⚡')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (post_id, user_id, emoji)
);

CREATE INDEX post_reactions_post_idx ON public.post_reactions(post_id);

ALTER TABLE public.post_reactions ENABLE ROW LEVEL SECURITY;

-- Visibility rides the post's own RLS: the EXISTS subquery runs AS THE
-- VIEWER, so workout_posts' SELECT policy applies inside it — a reaction
-- is visible exactly when its post is, with no second copy of the
-- friendship predicate to drift. (No recursion: workout_posts' policies
-- never reference post_reactions.)
CREATE POLICY "reactions visible with their post"
  ON public.post_reactions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.workout_posts wp WHERE wp.id = post_reactions.post_id)
  );

CREATE POLICY "user reacts to visible posts"
  ON public.post_reactions FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND EXISTS (SELECT 1 FROM public.workout_posts wp WHERE wp.id = post_reactions.post_id)
  );

CREATE POLICY "user removes own reaction"
  ON public.post_reactions FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- ── 3. workout-photos bucket + policies ──────────────────────────────────
-- PRIVATE bucket (unlike public-read avatars): photos are friends-only.
-- Path convention: posts/{author_id}/{post_id}.jpg — the SECOND folder
-- component derives ownership with no row lookup, which also makes the
-- upload-then-insert order safe (the object can exist before its post row;
-- orphans only ever live in the uploader's own folder).
INSERT INTO storage.buckets (id, name, public)
VALUES ('workout-photos', 'workout-photos', false)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "author uploads own workout photo"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'workout-photos'
    AND (storage.foldername(name))[1] = 'posts'
    AND ((storage.foldername(name))[2])::uuid = auth.uid()
  );

-- SELECT mirrors the post table's visibility, keyed off the author folder
-- (same predicate, no row lookup — an object with no post row yet is
-- still only readable by its author's friends, which is strictly tighter
-- than needed).
CREATE POLICY "author and friends read workout photos"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'workout-photos'
    AND (storage.foldername(name))[1] = 'posts'
    AND (
      ((storage.foldername(name))[2])::uuid = auth.uid()
      OR (
        private.is_friend(((storage.foldername(name))[2])::uuid, auth.uid())
        AND NOT private.is_blocked(((storage.foldername(name))[2])::uuid, auth.uid())
        AND NOT private.is_blocked(auth.uid(), ((storage.foldername(name))[2])::uuid)
      )
    )
  );

CREATE POLICY "author deletes own workout photo"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'workout-photos'
    AND (storage.foldername(name))[1] = 'posts'
    AND ((storage.foldername(name))[2])::uuid = auth.uid()
  );
