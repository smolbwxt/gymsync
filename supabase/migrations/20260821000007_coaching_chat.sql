-- 20260821000007_coaching_chat.sql
--
-- Trainer<->client chat (owner 2026-08-21: "a chat between you and your
-- client available in each client page"). A DM would duplicate ~740
-- lines of chat machinery; instead each ACTIVE relationship gets a
-- hidden two-person backing group (kind='coaching') and rides the
-- entire existing chat stack - realtime, reactions, read state, push.
-- The Crews tab filters coaching groups out client-side; the chat is
-- reached from the client page (trainer) and CoachingView (athlete).
ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS kind text NOT NULL DEFAULT 'crew'
    CHECK (kind IN ('crew', 'coaching'));

ALTER TABLE public.trainer_clients
  ADD COLUMN IF NOT EXISTS chat_group_id uuid REFERENCES public.groups(id) ON DELETE SET NULL;

-- Idempotent: creates the backing group + both memberships on first
-- call, returns the existing one after. Either side of an ACTIVE
-- relationship may call. SECURITY DEFINER because the client is not
-- the group creator and memberships are inserted for both parties.
CREATE OR REPLACE FUNCTION public.ensure_coaching_chat(p_relationship_id uuid)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rel   public.trainer_clients%ROWTYPE;
  v_group uuid;
BEGIN
  SELECT * INTO v_rel FROM public.trainer_clients
   WHERE id = p_relationship_id
   FOR UPDATE;
  IF NOT FOUND OR v_rel.status <> 'active' OR v_rel.client_id IS NULL THEN
    RAISE EXCEPTION 'no active relationship';
  END IF;
  IF auth.uid() NOT IN (v_rel.trainer_id, v_rel.client_id) THEN
    RAISE EXCEPTION 'not your relationship';
  END IF;
  IF v_rel.chat_group_id IS NOT NULL THEN
    RETURN v_rel.chat_group_id;
  END IF;
  INSERT INTO public.groups (name, created_by, kind)
  VALUES ('Coaching', v_rel.trainer_id, 'coaching')
  RETURNING id INTO v_group;
  INSERT INTO public.group_members (group_id, user_id, role)
  VALUES (v_group, v_rel.trainer_id, 'admin'),
         (v_group, v_rel.client_id, 'member');
  UPDATE public.trainer_clients SET chat_group_id = v_group
   WHERE id = p_relationship_id;
  RETURN v_group;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_coaching_chat(uuid) FROM anon, public;
GRANT EXECUTE ON FUNCTION public.ensure_coaching_chat(uuid) TO authenticated;
