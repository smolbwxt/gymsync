CREATE TABLE public.friendships (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','accepted','blocked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

-- One friendship per pair regardless of direction (no reverse duplicate requests)
CREATE UNIQUE INDEX friendships_canonical_pair_idx
  ON public.friendships (LEAST(user_id, friend_id), GREATEST(user_id, friend_id));
CREATE INDEX friendships_friend_id_idx ON public.friendships(friend_id);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "parties can read their friendships"
  ON public.friendships FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR friend_id = auth.uid());

CREATE POLICY "requester creates pending request"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "recipient accepts"
  ON public.friendships FOR UPDATE TO authenticated
  USING (friend_id = auth.uid())
  WITH CHECK (friend_id = auth.uid() AND status = 'accepted');

CREATE POLICY "either party deletes"
  ON public.friendships FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR friend_id = auth.uid());
