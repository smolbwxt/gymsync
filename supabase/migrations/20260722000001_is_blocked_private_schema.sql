-- ============================================================
-- Phase M / Task 1 fix-forward: close the is_blocked() PostgREST oracle
-- ============================================================
-- Critical review finding (post-1ffed22): public.is_blocked(uuid,uuid) is
-- SECURITY DEFINER + `GRANT EXECUTE ... TO authenticated` in the `public`
-- schema, which is PostgREST-exposed (supabase/config.toml [api] schemas =
-- ["public", "graphql_public"] — explicit, not defaulted; either way a new
-- `private` schema is not in that list, so it would be unexposed regardless).
-- That combination auto-mints POST /rest/v1/rpc/is_blocked, callable with
-- ANY two arbitrary uuids by any authenticated user:
--   - is_blocked(A, B) for arbitrary A, B answers "did A block B?" for any
--     pair, defeating blocked_users' blocker-only SELECT policy
--     (20260721000001, "blocker manages own blocks") whose entire purpose is
--     to hide that fact from everyone except the blocker.
--   - is_blocked(<anyone>, my_id) lets a caller enumerate "who has blocked
--     me" by sweeping candidate uuids.
-- A blanket `p_blocker = auth.uid()` guard in the function body was
-- considered and rejected: the friendships INSERT WITH CHECK
-- (20260721000001, "requester creates pending request") legitimately calls
-- is_blocked(friend_id, user_id) — neither argument is auth.uid() in that
-- call, so a self-only guard would break the addressee-blocked-requester
-- check it exists to enforce.
--
-- Fix: move the function to a non-API-exposed `private` schema. RLS policy
-- evaluation still resolves it (see step 2 below for why), but PostgREST
-- never introspects `private`, so no HTTP RPC endpoint is ever minted for
-- it. This is the reviewer-specified fix, not a body-level patch.

-- ── 1. private schema — exists for RLS-callable, never API-exposed helpers ─
CREATE SCHEMA IF NOT EXISTS private;
COMMENT ON SCHEMA private IS
  'Holds SECURITY DEFINER helper functions that RLS policies must be able '
  'to call but that must never be reachable as a PostgREST RPC endpoint. '
  'Not listed in supabase/config.toml [api] schemas (and would not be '
  'auto-exposed even if it were, since only public/graphql_public are '
  'included by default) — PostgREST only mints /rest/v1/rpc/* endpoints '
  'for functions in exposed schemas, so it never introspects this one. '
  'Do NOT grant USAGE on this schema to anon or authenticated: that grant '
  'is what would let a role resolve `private.<fn>` by name at all (via '
  'direct SQL, not PostgREST, since PostgREST cannot see this schema '
  'either way). Leaving USAGE unrevoked from a client-facing role would '
  'reopen exactly the kind of oracle this schema exists to prevent, even '
  'though PostgREST itself would still be blind to it.';

-- Belt-and-suspenders: PUBLIC (and therefore every role, since all roles
-- are implicitly members of PUBLIC) gets neither USAGE nor CREATE on this
-- schema by default in Postgres 15+, but this project's Postgres major
-- version is 17 per supabase/config.toml [db] — explicit REVOKE here so
-- the lockdown doesn't depend on the default and is self-documenting.
REVOKE ALL ON SCHEMA private FROM PUBLIC;

-- ── 2. private.is_blocked() — same contract, unreachable schema ─────────
-- Body, SECURITY DEFINER, STABLE, and search_path pinning are identical to
-- public.is_blocked (20260721000001) — search_path stays pinned to `public`
-- because the underlying table (blocked_users) still lives there; only the
-- function's own schema location changes.
--
-- No REVOKE/GRANT EXECUTE lines here, unlike the public-schema version:
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, and that default is
-- deliberately left in place (not revoked, not narrowed) because it is not
-- the exploitable surface. EXECUTE-on-function is checked at every call,
-- including calls embedded in an RLS policy's USING/WITH CHECK expression
-- evaluated for role `authenticated` — so EXECUTE must remain available to
-- that role or the two policies below would fail closed for every caller.
-- SCHEMA USAGE, by contrast, is a name-resolution privilege checked when a
-- query is parsed/analyzed, not re-checked when a previously-analyzed
-- expression (like a stored policy qual, resolved to this function's OID
-- when the CREATE POLICY statements below ran under the migration role)
-- is later evaluated. That asymmetry is exactly what makes this pattern
-- work: revoking schema USAGE from authenticated/anon blocks them from
-- ever naming `private.is_blocked` in a query of their own (and PostgREST
-- can't route to it either way, since it never sees the schema), while the
-- two RLS policies — whose qual already carries the resolved function OID
-- from CREATE POLICY time — keep working because that lookup already
-- happened once, under full privileges, and is never redone per-call.
CREATE FUNCTION private.is_blocked(p_blocker uuid, p_blocked uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.blocked_users
    WHERE blocker_id = p_blocker AND blocked_id = p_blocked
  );
$$;

-- ── 3. Repoint the two policies to private.is_blocked ────────────────────
-- Postgres has no CREATE OR REPLACE POLICY — DROP then CREATE is the only
-- way to change a policy's expression (same idiom this file's predecessor,
-- 20260721000001, already used twice for these exact two policies when it
-- added the block-aware AND clause / WITH CHECK terms in the first place).
-- Full USING/WITH CHECK text transplanted verbatim from
-- 20260721000001_moderation_block_report.sql, changing only
-- `public.is_blocked` -> `private.is_blocked` (fully qualified).

DROP POLICY "group members read messages" ON public.chat_messages;
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (
    (
      (chat_messages.session_id IS NULL
       AND public.is_group_member(chat_messages.group_id, auth.uid()))
      OR (chat_messages.session_id IS NOT NULL
          AND public.is_session_participant(chat_messages.session_id, auth.uid()))
    )
    AND NOT private.is_blocked(auth.uid(), chat_messages.author_id)
  );

DROP POLICY "requester creates pending request" ON public.friendships;
CREATE POLICY "requester creates pending request"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (
    user_id = auth.uid()
    AND status = 'pending'
    AND NOT private.is_blocked(friend_id, user_id)
    AND NOT private.is_blocked(user_id, friend_id)
  );

-- ── 4. Drop the oracle ────────────────────────────────────────────────────
-- Must run AFTER the two policies above stop referencing public.is_blocked:
-- a policy dependency on the function would otherwise block this DROP.
-- Confirmed no other consumer exists — grepped the repo (migrations, Swift
-- app, edge functions) for `is_blocked` outside this file and
-- 20260721000001 itself: no client code calls the `is_blocked` RPC, so
-- there is no legitimate caller to preserve, only the oracle to close.
DROP FUNCTION public.is_blocked(uuid, uuid);
