-- ============================================================
-- Phase O / Task 1, fix-wave 2 (Part 2 of 2): relocate is_group_admin() and
-- is_group_creator() to `private` — same-shape helpers flagged but not
-- queued in fix-wave 1 (task-1-report.md, "Concerns for the controller" #2:
-- "is_group_admin and is_group_creator ... carry the same oracle shape ...
-- but are not in this task's queue — flagged ... not touched").
-- ============================================================
-- CLASSIFICATION: both public.is_group_admin(p_group_id uuid, p_user_id
-- uuid) and public.is_group_creator(p_group_id uuid, p_user_id uuid) are
-- SECURITY DEFINER STABLE, live in the exposed `public` schema
-- (20260710000002_create_groups.sql:32-44, never redefined), and carry no
-- REVOKE/GRANT EXECUTE statements anywhere (grep-confirmed) — default
-- PUBLIC EXECUTE, auto-minted as POST /rest/v1/rpc/is_group_admin and
-- .../is_group_creator, each callable by any authenticated caller with two
-- arbitrary uuids. Same oracle SHAPE as the rest of this sweep: each
-- answers a role-membership question ("is p_user_id an admin of
-- p_group_id?" / "did p_user_id create p_group_id?") that groups'/
-- group_members' own RLS does not expose to a non-member at all (groups'
-- SELECT policy requires membership; group_members' SELECT policy requires
-- membership) — a non-member can learn a target's admin/creator status by
-- RPC-sweeping candidate group/user id pairs without ever needing read
-- access to the row itself. DECISION: same exposure class as the six
-- already-relocated helpers — relocate.
--
-- BUNDLED (one migration, not two): unlike every other pairing in this
-- sweep, is_group_admin and is_group_creator are co-referenced inside the
-- SAME single policy ("admin adds members or creator bootstraps" — see
-- dependent #3 below), not merely both flagged in the same review note.
-- Both are in scope for this fix wave and neither is blocked, so bundling
-- avoids two separate DROP+CREATE POLICY cycles on that one policy across
-- two migration files — the same "shared lineage" bundling rationale
-- fix-wave 1 already used for message_group_id + can_access_message
-- (task-1-report.md, "Batching rationale").
--
-- RPC-caller check (the exact grep that caught fix-wave 1's
-- is_session_participant blocker): grepped supabase/functions/**/*.ts for
-- `.rpc(` — two hits total in the whole Edge Function tree
-- (livekit-token/index.ts:42 "is_session_participant", already handled in
-- 20260726000001; push-dispatcher/index.ts:50 "claim_push_batch",
-- unrelated). Also grepped supabase/functions/ and GymSyncApp/**/*.swift
-- directly for the literal strings `is_group_admin` / `is_group_creator`:
-- zero hits (account-deletion-cascade/index.ts:104,181 mention
-- "is_group_admin()" only inside `//` comments explaining role semantics,
-- never as a `.rpc()` call target — that Edge Function reassigns group
-- ownership via direct `.from("group_members")` queries under its own
-- service-role client, not via this RPC). No client, Edge Function, or SQL
-- function body calls either helper by name anywhere in the repo — clean
-- relocation, no dual-function treatment needed.
--
-- Live POLICY dependents (grep-confirmed, none redefined since their listed
-- migration — 20260710000002_create_groups.sql throughout except #6-7):
--   1. groups UPDATE ("admin can update group") — is_group_admin only.
--   2. groups DELETE ("admin can delete group") — is_group_admin only.
--   3. group_members INSERT ("admin adds members or creator bootstraps") —
--      BOTH helpers: is_group_admin(...) OR (user_id = auth.uid() AND
--      role = 'admin' AND is_group_creator(...)). The only policy either
--      helper shares.
--   4. group_members UPDATE ("admin updates roles") — is_group_admin only.
--   5. group_members DELETE ("self-leave or admin removes") —
--      is_group_admin only (OR'd with user_id = auth.uid()).
--   6-7. storage.objects INSERT/UPDATE ("group admin uploads group
--      avatar", "group admin replaces group avatar",
--      20260711000002_storage_buckets.sql) — is_group_admin only. (Storage
--      avatar policies for a USER's own avatar,
--      20260720000005_user_avatar_storage.sql, are unrelated — self-owned
--      path check, no is_group_admin call.)
--
-- No SQL-function-body callers for either helper anywhere in the repo
-- (grep-confirmed: every non-comment occurrence of `is_group_admin(` /
-- `is_group_creator(` outside their own CREATE FUNCTION resolves to one of
-- the 7 policy dependents above).
-- ============================================================

-- ── 1. private.is_group_admin() / private.is_group_creator() — same
--    contract, unreachable schema. `private` already exists (CREATE SCHEMA
--    IF NOT EXISTS + REVOKE ALL FROM PUBLIC,
--    20260722000001_is_blocked_private_schema.sql) — not recreated here.
--    No REVOKE/GRANT EXECUTE lines: neither source function ever had any
--    (default PUBLIC EXECUTE), so each relocated copy keeps the exact same
--    grant posture, matching every prior relocation in this sweep except
--    is_blocked's own (which had a narrowed grant to preserve).
CREATE FUNCTION private.is_group_admin(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'admin');
$$;

CREATE FUNCTION private.is_group_creator(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.groups
                 WHERE id = p_group_id AND created_by = p_user_id);
$$;

-- ── 2. Repoint the 7 dependent policies ──────────────────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE, this repo's
-- established idiom throughout.

DROP POLICY "admin can update group" ON public.groups;
CREATE POLICY "admin can update group"
  ON public.groups FOR UPDATE TO authenticated
  USING (private.is_group_admin(groups.id, auth.uid()))
  WITH CHECK (private.is_group_admin(groups.id, auth.uid()));

DROP POLICY "admin can delete group" ON public.groups;
CREATE POLICY "admin can delete group"
  ON public.groups FOR DELETE TO authenticated
  USING (private.is_group_admin(groups.id, auth.uid()));

DROP POLICY "admin adds members or creator bootstraps" ON public.group_members;
CREATE POLICY "admin adds members or creator bootstraps"
  ON public.group_members FOR INSERT TO authenticated
  WITH CHECK (
    private.is_group_admin(group_members.group_id, auth.uid())
    OR (user_id = auth.uid() AND role = 'admin'
        AND private.is_group_creator(group_members.group_id, auth.uid()))
  );

DROP POLICY "admin updates roles" ON public.group_members;
CREATE POLICY "admin updates roles"
  ON public.group_members FOR UPDATE TO authenticated
  USING (private.is_group_admin(group_members.group_id, auth.uid()))
  WITH CHECK (private.is_group_admin(group_members.group_id, auth.uid()));

DROP POLICY "self-leave or admin removes" ON public.group_members;
CREATE POLICY "self-leave or admin removes"
  ON public.group_members FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         OR private.is_group_admin(group_members.group_id, auth.uid()));

DROP POLICY "group admin uploads group avatar" ON storage.objects;
CREATE POLICY "group admin uploads group avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND private.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

DROP POLICY "group admin replaces group avatar" ON storage.objects;
CREATE POLICY "group admin replaces group avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND private.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND private.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

-- ── 3. Drop both oracles ──────────────────────────────────────────────────
-- Must run AFTER all seven policies above stop referencing the public
-- functions: a policy dependency on either function would otherwise block
-- these DROPs. is_group_creator dropped first (no dependents of its own
-- once the shared policy above is repointed); order between the two
-- doesn't otherwise matter (neither calls the other).
DROP FUNCTION public.is_group_creator(uuid, uuid);
DROP FUNCTION public.is_group_admin(uuid, uuid);
