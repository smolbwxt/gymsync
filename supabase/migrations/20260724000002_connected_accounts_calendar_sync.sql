-- ============================================================
-- Phase H / Task 5: Google Calendar staging — SCHEMA STAGING ONLY
-- ============================================================
-- Master spec (docs/superpowers/specs/2026-06-28-gymsync-design.md:619-640),
-- verbatim columns:
--
--   connected_accounts (
--     id                  uuid PRIMARY KEY,
--     user_id             uuid REFERENCES profiles(id),
--     provider            text CHECK (provider IN ('google_calendar')),  -- extensible for future providers
--     provider_account_id text,
--     access_token        text NOT NULL,                   -- encrypted at rest
--     refresh_token       text NOT NULL,                   -- encrypted at rest
--     scopes              text[],
--     expires_at          timestamptz,
--     created_at          timestamptz DEFAULT now(),
--     UNIQUE (user_id, provider)
--   )
--
--   -- Session -> external calendar mapping (for updates/deletes to sync properly)
--   session_calendar_syncs (
--     session_id          uuid REFERENCES sessions(id) ON DELETE CASCADE,
--     provider            text,
--     external_event_id   text NOT NULL,
--     synced_at           timestamptz DEFAULT now(),
--     PRIMARY KEY (session_id, provider)
--   )
--
-- RLS list (:672-673):
--   "connected_accounts -- owner only, both read and write. Access + refresh
--   tokens are stored encrypted (Supabase Vault or column-level encryption)."
--   "session_calendar_syncs -- owner (session organizer) + app_admin."
--
-- Flow 10 (:927-946) -- one-way sessions -> Google Calendar sync via an Edge
-- Function on sessions INSERT/UPDATE (scheduled_for changed) that creates an
-- event and records the mapping in session_calendar_syncs; on session
-- delete/abandon the event is deleted; on Google 401 the connection is
-- marked "expired" and a non-blocking "Reconnect Google Calendar" banner
-- shows in the You tab. Section 6.6 (:1221-1227) reiterates tokens are
-- "stored in connected_accounts with column-level encryption (Supabase
-- Vault)" and that refresh is handled server-side -- "client never sees
-- refresh tokens after initial exchange."
--
-- CONTROLLER RULING (task-5-brief.md item 1; resolved conditional): the
-- user's Google Cloud OAuth consent screen is NOT created/approved yet.
-- This migration is SCHEMA STAGING ONLY -- no OAuth client code, no Edge
-- Function sync implementation, no token-exchange logic anywhere in this
-- commit or any other file touched by this task. Nothing here ever writes
-- a real token; the columns exist so the future Edge Function build has a
-- landing surface, gated behind the access controls proven in
-- supabase/tests/connected_accounts_calendar_sync_test.sql.
--
-- ── Vault finding (read before choosing a token-storage design) ──────────
-- grep for `vault\.` / `supabase_vault` across every file in
-- supabase/migrations found exactly ONE real usage: 20260716000003_push_
-- cron.sql calls `vault.create_secret()` and reads `vault.decrypted_secrets`
-- for a single GLOBAL shared secret ('push_drain_auth') consumed by one
-- SECURITY DEFINER cron function. That confirms the `supabase_vault`
-- extension IS installed on this project -- but the only established idiom
-- is "one named secret, read by one definer function." There is no
-- precedent anywhere in this schema for per-row, per-user Vault-backed
-- secrets: N connected_accounts rows would need N `vault.create_secret()`
-- calls at write time, a secret-id-reference column instead of a plain text
-- column, a key-rotation story, and a decrypt-path definer function scoped
-- to the Edge Function's service role -- none of which exist today, and
-- none of which this pass is permitted to build (controller ruling: no
-- token-exchange logic). Wiring a partial Vault integration now -- columns
-- that reference vault.secrets.id but that nothing in this commit ever
-- populates or decrypts, exercised by zero real OAuth callbacks -- would be
-- encryption theater: an untested code path is not a security control.
--
-- Per the master spec's own RLS-list framing ("Supabase Vault OR column-
-- level encryption", :672) and §6.6's literal column names, this migration
-- takes the honest column-level-encryption fork: `access_token` /
-- `refresh_token` stay `text NOT NULL` exactly as specced, physically
-- PLAINTEXT at rest today (no fake "encrypted" claim -- see legacy-honest-
-- numbers / project CLAUDE.md). Wrapping them with real Vault encryption is
-- explicit TODO work for the future Edge Function build, before the first
-- real token is ever written -- tracked in the roadmap stub note appended
-- to docs/superpowers/plans/2026-07-16-remaining-build-roadmap.md by this
-- same commit. The security property THIS migration is responsible for is
-- narrower and fully deliverable today: the client must never be able to
-- read these two columns back out over PostgREST, under any row it owns,
-- so that whenever real tokens start landing here the existing client
-- surface still can't exfiltrate them.
--
-- ── Token-column protection mechanism (verified, not assumed) ────────────
-- A column-level REVOKE alone does NOT achieve client-SELECT-denial in this
-- project. 20260717000003_curation.sql already discovered and documented
-- this for UPDATE: `authenticated`/`anon` hold TABLE-WIDE privileges on
-- every table (including brand-new ones) via Supabase's platform-level
-- `ALTER DEFAULT PRIVILEGES`, applied once at project bootstrap, outside
-- any migration file. Postgres ACL evaluation for a given (role, column,
-- privilege) is a plain OR across the table-level grant and any column-
-- level grant -- a column-level REVOKE cannot subtract from a table-level
-- GRANT that is still in force. curation.sql's fix for UPDATE was a guard
-- trigger; SELECT has no trigger event to hook, so the fix here is
-- different: REVOKE the table-wide grant entirely (all privileges, all
-- columns), then GRANT SELECT back on an explicit, named column list that
-- simply never mentions access_token / refresh_token. With no table-wide
-- grant left to OR against, the column-level GRANT becomes the ONLY source
-- of SELECT privilege for `authenticated`, and it structurally cannot cover
-- the two omitted columns. The same REVOKE ALL also removes the platform-
-- default INSERT/UPDATE/DELETE grants, which combined with RLS having no
-- policy for those commands (implicit deny) double-enforces "server-side
-- writes only" for both tables in this migration.
--
-- Proven empirically, not assumed, in
-- supabase/tests/connected_accounts_calendar_sync_test.sql: the owning user
-- attempts `SELECT access_token`, `SELECT refresh_token`, and `SELECT *`
-- against their own connected_accounts row and each is asserted to throw
-- 42501 (insufficient_privilege) -- the actual PostgREST-facing failure
-- mode, not a policy-level 0-row no-op.

-- ── 1. connected_accounts ─────────────────────────────────────────────────
-- `status` is not in the master spec's literal column list, but Flow 10
-- requires it ("Edge Function catches 401 -> marks connection as `expired`
-- -> non-blocking banner") and this task's own RLS instructions name it
-- among the owner-readable non-secret columns. Same "spec is the column
-- list, not the DDL" gap every prior migration in this repo has closed
-- (body_weight_logs' weight/unit CHECKs, user_reports' status enum) --
-- filled here with the same controlled-vocabulary CHECK idiom as
-- user_reports.status. The task brief's "connected_at" is this table's
-- `created_at` (the spec's literal name) -- no separate column added.
CREATE TABLE public.connected_accounts (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id               uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  provider              text NOT NULL CHECK (provider IN ('google_calendar')),
  provider_account_id   text,
  access_token          text NOT NULL,
  refresh_token         text NOT NULL,
  scopes                text[],
  expires_at            timestamptz,
  status                text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'expired')),
  created_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, provider)
);

ALTER TABLE public.connected_accounts ENABLE ROW LEVEL SECURITY;

-- Owner-only SELECT (row filter). This is deliberately the ONLY RLS policy
-- on this table -- no INSERT/UPDATE/DELETE policy for `authenticated`
-- exists, matching user_reports' "no UPDATE/DELETE policy: ... not a
-- client-writable surface" idiom (20260721000001_moderation_block_report.sql).
-- Writes happen exclusively server-side: the future Edge Function inserts
-- via service role after a successful OAuth exchange, and client-initiated
-- "disconnect" goes through a future endpoint (which itself uses service
-- role / calls Google's revoke endpoint), never a direct table DELETE.
CREATE POLICY "owner reads own connected account"
  ON public.connected_accounts FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Table-wide REVOKE + column-scoped GRANT -- see header comment for why a
-- column-level REVOKE alone would be a no-op in this project. This is the
-- actual enforcement mechanism for hiding access_token/refresh_token from
-- PostgREST; the RLS policy above only ever restricted which ROWS are
-- visible, not which COLUMNS.
REVOKE ALL ON public.connected_accounts FROM authenticated, anon;
GRANT SELECT (
  id, user_id, provider, provider_account_id, scopes, expires_at, status, created_at
) ON public.connected_accounts TO authenticated;
-- access_token / refresh_token are deliberately absent from the GRANT
-- above -- structurally unreadable by `authenticated`/`anon` regardless of
-- which row RLS would otherwise let them see. service_role keeps its
-- platform-default full grant (never revoked) -- the future Edge Function
-- both writes and reads tokens under service_role, bypassing RLS entirely
-- (BYPASSRLS) and unaffected by this REVOKE (roles are named explicitly).

-- ── 2. session_calendar_syncs ─────────────────────────────────────────────
-- provider gets the same controlled-vocabulary CHECK as connected_accounts
-- (spec's literal column is bare `text`) -- both columns represent the same
-- provider vocabulary, and an unconstrained provider string here would let
-- a typo silently break the future disconnect/re-sync lookup by (session_id,
-- provider). session_id NOT NULL mirrors session_participants' explicit
-- NOT NULL-on-a-PK-column style (20260709000006_create_sessions.sql) even
-- though the PK already implies it.
CREATE TABLE public.session_calendar_syncs (
  session_id          uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  provider            text NOT NULL CHECK (provider IN ('google_calendar')),
  external_event_id   text NOT NULL,
  synced_at           timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (session_id, provider)
);

ALTER TABLE public.session_calendar_syncs ENABLE ROW LEVEL SECURITY;

-- Spec RLS list (:673): "owner (session organizer) + app_admin." No
-- app_admin SELECT arm here -- same posture and same reasoning as
-- user_reports (20260721000001_moderation_block_report.sql:46-51):
-- app_admin is not an RLS-visible role/claim anywhere in this schema today,
-- so a role-based policy would be speculative. Admin reads happen out-of-
-- band via service role / direct SQL, same v1 posture as moderation.
-- Reuses is_session_organizer() (20260709000006_create_sessions.sql) --
-- the existing SECURITY DEFINER helper, no new function needed.
CREATE POLICY "organizer reads own session's calendar syncs"
  ON public.session_calendar_syncs FOR SELECT TO authenticated
  USING (public.is_session_organizer(session_calendar_syncs.session_id, auth.uid()));

-- No INSERT/UPDATE/DELETE policy: this table is populated exclusively by
-- the future Edge Function (service role) after a successful Google
-- Calendar API call -- never a client write, including by the organizer
-- themselves. Same table-wide REVOKE + re-GRANT pattern as
-- connected_accounts, for the same double-enforcement reason (RLS's
-- implicit deny on unpoliced commands, backed by an explicit table-level
-- REVOKE rather than relying on the platform default alone). No secret
-- columns here, so the re-GRANT covers every column.
REVOKE ALL ON public.session_calendar_syncs FROM authenticated, anon;
GRANT SELECT ON public.session_calendar_syncs TO authenticated;
