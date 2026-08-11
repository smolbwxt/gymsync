-- Session commitments (crew room commit widget): a member's signal for an
-- upcoming group session — 'in' or 'out'; absence of a row = hasn't said.
-- Ternary by design (owner decision 2026-08-11): an explicit OUT is social
-- information a binary flag can't carry.

-- Helper: is this session a group session the user belongs to? SECURITY
-- DEFINER in the private schema, matching the is_group_member relocation
-- (20260725000002) — policies reference it without tripping sessions RLS.
CREATE OR REPLACE FUNCTION private.session_group_member(p_session_id uuid, p_user_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.sessions s
    JOIN public.group_members gm
      ON gm.group_id = s.group_id AND gm.user_id = p_user_id
    WHERE s.id = p_session_id
      AND s.group_id IS NOT NULL
  );
$$;

CREATE TABLE public.session_commitments (
  session_id uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status     text NOT NULL CHECK (status IN ('in', 'out')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.session_commitments ENABLE ROW LEVEL SECURITY;

-- Any member of the session's group can read the crew's commitments.
CREATE POLICY "group members read session commitments"
  ON public.session_commitments FOR SELECT
  TO authenticated
  USING (private.session_group_member(session_id, auth.uid()));

-- You write only your own row, and only for sessions of groups you're in.
CREATE POLICY "members insert own commitment"
  ON public.session_commitments FOR INSERT
  TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND private.session_group_member(session_id, auth.uid())
  );

CREATE POLICY "members update own commitment"
  ON public.session_commitments FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (
    user_id = auth.uid()
    AND private.session_group_member(session_id, auth.uid())
  );

CREATE POLICY "members delete own commitment"
  ON public.session_commitments FOR DELETE
  TO authenticated
  USING (user_id = auth.uid());
