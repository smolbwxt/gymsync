-- 20260918000102_routine_proposals_drop.sql
--
-- APPLIED LIVE 2026-09-18 19:05:29 UTC (schema_migrations version
-- 20260918190529).
--
-- IRREVERSIBLE. Phase B2 plan, task D4, "the six data decisions," the
-- irreversible gate (constraint 9). The routine-proposal flow's app code
-- was removed in Phase A; D3 (chore(proposals): retire the pgTAP suites,
-- the QA commands and the comments that name routine_proposals) retired
-- every reference in supabase/** and scripts/** and is pushed
-- (f111622). This drop follows it, as constraint 9 requires.
--
-- ── The irreversible gate, both preconditions confirmed before this file
--    was written:
--
--   1. The row export exists in the workspace:
--      .superpowers/sdd/2026-09-18-group-session-phase-b2-plan/
--      routine-proposal-rows-2026-09-18.json (exported_at
--      2026-09-18T18:45:50Z) -- 6 routine_proposals rows (ids and status
--      recorded), 10 routine_proposal_votes rows (count recorded). No git
--      tag is needed for this drop (unlike the soundboard's D5): the app
--      code for this flow was removed in Phase A, and the tables' full
--      definition lives on, undeleted, in
--      supabase/migrations/20260712000003_routine_proposals.sql.
--   2. D3 is pushed: f111622 (chore(proposals): retire the pgTAP suites,
--      the QA commands and the comments that name routine_proposals),
--      confirmed present in this branch's history before this file was
--      written.
--
-- ── Read-only verification against the live project immediately before
--    writing this file (chjkkwqwdlmaxacwglzm, no DDL, no DML):
--   * No foreign key from any OTHER table references either table
--     (information_schema.table_constraints / key_column_usage /
--     constraint_column_usage, zero rows).
--   * No view or materialized view's definition mentions either table
--     (pg_views, zero rows).
--   * No function body outside the three named below contains the exact
--     substring 'routine_proposal' (pg_proc.prosrc, zero rows) -- the
--     "ad-hoc resolve_proposal_debug*" objects
--     20260727000004_proposal_session_id_private_schema.sql's header
--     flagged as live-only and out-of-scope no longer exist.
--   * Both tables ARE members of the supabase_realtime publication
--     (pg_publication_tables) -- added by
--     20260712000006_session_realtime_publication.sql:6-7 -- so the
--     publication drop below is not a no-op.
--
-- ── Three functions are proposal-only, live, and become orphaned by the
--    table drops if not also dropped here:
--   * private.proposal_session_id(uuid) -- decision text and the brief
--     name this one. Originally public.proposal_session_id
--     (20260712000003), relocated to private
--     (20260727000004_proposal_session_id_private_schema.sql) as a
--     session_id-oracle closure, same exposure class as
--     message_group_id/series_group_id. Read by
--     routine_proposal_votes' two policies
--     (20260726000001_is_session_participant_dual_schema.sql:224-231
--     repointed the outer is_session_participant wrapper to private but
--     left this inner call as public.proposal_session_id at the time;
--     20260727000004 is the migration that finished the relocation) --
--     those policies leave WITH their table below, so this DROP is safe
--     once it does.
--   * public.on_proposal_insert() and public.resolve_proposal() -- NOT
--     named by decision text or the brief, added to this migration by
--     the same reasoning R-B19 applied to the soundboard's
--     touch_soundboard_favorites_updated_at(): both are AFTER-INSERT
--     trigger functions (20260712000003_routine_proposals.sql) whose
--     only triggers (proposal_insert on routine_proposals,
--     proposal_vote_cast on routine_proposal_votes -- live-confirmed,
--     read-only, immediately before writing this file) live on the two
--     tables this migration drops. DROP TABLE takes the TRIGGERS with
--     it; it does not touch the trigger FUNCTIONS. Left alone, both
--     would remain as standalone objects with no table, no trigger and
--     no caller, each naming (`FROM public.routine_proposals`,
--     `FROM public.session_participants ... WHERE session_id =
--     v_proposal.session_id` after a SELECT INTO from the now-dropped
--     table) a relation this migration removes. Dropped last, after the
--     tables that were their only callers no longer exist.
--
-- Accepted consequence, stated in the plan: a tester on an older
-- TestFlight build still subscribing to either realtime stream gets an
-- empty stream rather than rows -- the app code for this flow left in
-- Phase A, so nothing renders either way.

-- ── 1. The publication rows, explicit and first ─────────────────────────
-- DROP TABLE would remove these automatically; stating it explicitly is
-- what makes the replication change reviewable on its own line, and it
-- fails loudly if the publication was ever edited by hand to not include
-- these tables (it is not -- verified above).
ALTER PUBLICATION supabase_realtime DROP TABLE public.routine_proposal_votes;
ALTER PUBLICATION supabase_realtime DROP TABLE public.routine_proposals;

-- ── 2. The tables, child before parent (routine_proposal_votes.proposal_id
--    REFERENCES routine_proposals(id)) -- takes each table's own policies
--    and triggers with it.
DROP TABLE IF EXISTS public.routine_proposal_votes;
DROP TABLE IF EXISTS public.routine_proposals;

-- ── 3. The trigger functions the table drops orphaned (not named by
--    decision text -- see the header note above).
DROP FUNCTION IF EXISTS public.on_proposal_insert();
DROP FUNCTION IF EXISTS public.resolve_proposal();

-- ── 4. The session_id oracle, now unreferenced by any policy.
DROP FUNCTION IF EXISTS private.proposal_session_id(uuid);
