-- CI-account isolation (2026-07-30). Run: node scripts/run_pgtap.js scripts/ci-account-isolation.sql
--
-- WHY: ci_test_user_2 (the GymSyncScreenshots sign-in account) is a REAL
-- user on the production backend. Merely LAUNCHING the app during a CI run
-- flips its check_in_state to 'online' in any session it's a participant
-- of — which put a ghost into a live rotation on 2026-07-30 (observed:
-- the bot sat WAITING in a real session while five CI runs signed it in).
-- The screenshots tests themselves only tap tabs; membership is the
-- entire attack surface.
--
-- WHAT: evict the bot from every group and session it does not itself
-- organize, so future CI sign-ins can never touch a real user's data.
-- Its own fixtures (self-organized sessions, own routines) are preserved —
-- that is what the screenshots render. Idempotent; re-run any time.
--
-- (Not a migration: this is operational data cleanup, not schema.)

WITH bot AS (
  SELECT id FROM public.profiles WHERE username = 'ci_test_user_2'
),
evicted_sessions AS (
  DELETE FROM public.session_participants sp
  USING bot
  WHERE sp.user_id = bot.id
    AND sp.session_id IN (
      SELECT s.id FROM public.sessions s, bot b WHERE s.organizer_id <> b.id
    )
  RETURNING sp.session_id
),
evicted_groups AS (
  DELETE FROM public.group_members gm
  USING bot
  WHERE gm.user_id = bot.id
    AND gm.group_id IN (
      SELECT g.id FROM public.groups g, bot b WHERE g.created_by <> b.id
    )
  RETURNING gm.group_id
)
SELECT
  (SELECT count(*) FROM evicted_sessions) AS sessions_evicted,
  (SELECT count(*) FROM evicted_groups)  AS groups_evicted;
