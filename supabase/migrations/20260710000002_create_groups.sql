CREATE TABLE public.groups (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 text NOT NULL,
  avatar_url           text,
  created_by           uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  default_late_penalty jsonb,
  default_routine_id   uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.group_members (
  group_id  uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role      text NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX group_members_user_id_idx ON public.group_members(user_id);

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helpers break groups<->group_members RLS recursion
-- (same pattern as sessions, see 20260709000006_create_sessions.sql)
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'admin');
$$;

CREATE OR REPLACE FUNCTION public.is_group_creator(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.groups
                 WHERE id = p_group_id AND created_by = p_user_id);
$$;

-- Spec §5: max group size v1 = 25
CREATE OR REPLACE FUNCTION public.enforce_group_size() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (SELECT count(*) FROM public.group_members WHERE group_id = NEW.group_id) >= 25 THEN
    RAISE EXCEPTION 'group is full (max 25 members)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER group_size_cap BEFORE INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.enforce_group_size();

-- groups policies
CREATE POLICY "members and creator can read group"
  ON public.groups FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR public.is_group_member(groups.id, auth.uid()));

CREATE POLICY "creator can insert group"
  ON public.groups FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "admin can update group"
  ON public.groups FOR UPDATE TO authenticated
  USING (public.is_group_admin(groups.id, auth.uid()))
  WITH CHECK (public.is_group_admin(groups.id, auth.uid()));

CREATE POLICY "admin can delete group"
  ON public.groups FOR DELETE TO authenticated
  USING (public.is_group_admin(groups.id, auth.uid()));

-- group_members policies
CREATE POLICY "members can read membership"
  ON public.group_members FOR SELECT TO authenticated
  USING (user_id = auth.uid()
         OR public.is_group_member(group_members.group_id, auth.uid()));

-- Admins add members; the creator may bootstrap ONLY their own admin row.
CREATE POLICY "admin adds members or creator bootstraps"
  ON public.group_members FOR INSERT TO authenticated
  WITH CHECK (
    public.is_group_admin(group_members.group_id, auth.uid())
    OR (user_id = auth.uid() AND role = 'admin'
        AND public.is_group_creator(group_members.group_id, auth.uid()))
  );

CREATE POLICY "admin updates roles"
  ON public.group_members FOR UPDATE TO authenticated
  USING (public.is_group_admin(group_members.group_id, auth.uid()))
  WITH CHECK (public.is_group_admin(group_members.group_id, auth.uid()));

CREATE POLICY "self-leave or admin removes"
  ON public.group_members FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         OR public.is_group_admin(group_members.group_id, auth.uid()));
