BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

-- Migration under test: 20260912000101_session_participant_energy.sql
-- (session_participants.energy smallint, 1-5, NULL until reported). Plan
-- task D2. Fixture block: 0axx UUIDs (this suite's namespace, constraint 17
-- -- 0axx was free; 09xx already collides between rotation_presence_test.sql
-- and crew_consistency_honor_test.sql).
--   A = ...0a01 organizer   B = ...0a02 crewmate   C = ...0a03 crewmate
--   D = ...0a04, a non-participant of the session -- fixture only. The
--       "a non-participant reads nothing" proof already belongs to
--       is_session_participant_dual_schema_test.sql and is not re-asserted
--       here.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000a01', 'energy-a@test.local'),
  ('00000000-0000-4000-f000-000000000a02', 'energy-b@test.local'),
  ('00000000-0000-4000-f000-000000000a03', 'energy-c@test.local'),
  ('00000000-0000-4000-f000-000000000a04', 'energy-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000a01', 'energy_a'),
  ('00000000-0000-4000-f000-000000000a02', 'energy_b'),
  ('00000000-0000-4000-f000-000000000a03', 'energy_c'),
  ('00000000-0000-4000-f000-000000000a04', 'energy_d');

INSERT INTO sessions (id, organizer_id, state, started_at) VALUES
  ('00000000-0000-4000-f000-000000000a10',
   '00000000-0000-4000-f000-000000000a01', 'lobby_open', now());
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000a10', '00000000-0000-4000-f000-000000000a01'),
  ('00000000-0000-4000-f000-000000000a10', '00000000-0000-4000-f000-000000000a02'),
  ('00000000-0000-4000-f000-000000000a10', '00000000-0000-4000-f000-000000000a03');
-- D is deliberately left out of session_participants for this session.

-- 1-3. The column itself, checked before any role switch (precedent:
-- curation_test.sql:19-20 runs has_column ahead of SET LOCAL role too).
SELECT has_column('public', 'session_participants', 'energy',
  'session_participants.energy exists');
SELECT col_type_is('public', 'session_participants', 'energy', 'smallint',
  'energy is smallint');
SELECT col_is_null('public', 'session_participants', 'energy',
  'energy is nullable -- "not yet reported" must be representable');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000a01';

-- 4. THE ASSERTION THAT COULD HAVE BEEN WRONG. session_participants carries
-- three BEFORE UPDATE triggers, and none of them may reject an energy-only
-- self-update:
--   * engine_guard (20260714000001_session_engine_rpcs.sql) DOES run its
--     full guard here (caller == row owner), but only rejects a change to
--     late_minutes / burpees_owed / turn_order -- untouched by this UPDATE.
--   * checkin_window_guard (20260715000003_checkin_window.sql) short-
--     circuits on its first line because NEW.check_in_state (NULL, this
--     fixture never checks anyone in) IS DISTINCT FROM 'ready'.
--   * late_joiner_to_rotation_end (20260802000001_rotation_presence.sql) is
--     declared BEFORE UPDATE OF check_in_state, so Postgres never invokes it
--     for a statement whose SET list doesn't mention that column.
-- If any guard rejected the write, RETURNING would produce zero rows, not
-- (4), and results_eq would catch it.
SELECT results_eq(
  $$UPDATE session_participants SET energy = 4
    WHERE session_id = '00000000-0000-4000-f000-000000000a10'
      AND user_id = '00000000-0000-4000-f000-000000000a01'
    RETURNING energy$$,
  $$VALUES (4::smallint)$$,
  'A can self-report energy 4 -- no session-engine trigger blocks it');

-- 5. The CHECK's floor: 0 is not a valid "reported" value.
SELECT throws_ok(
  $$UPDATE session_participants SET energy = 0
    WHERE session_id = '00000000-0000-4000-f000-000000000a10'
      AND user_id = '00000000-0000-4000-f000-000000000a01'$$,
  '23514', NULL, 'energy = 0 is rejected -- NULL is the only absence');

-- 6. The CHECK's ceiling: the scale tops out at 5.
SELECT throws_ok(
  $$UPDATE session_participants SET energy = 6
    WHERE session_id = '00000000-0000-4000-f000-000000000a10'
      AND user_id = '00000000-0000-4000-f000-000000000a01'$$,
  '23514', NULL, 'energy = 6 is rejected -- the scale tops out at 5');

SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000a02';

-- 7. B cannot write A's energy. "participant updates own check-in"
-- (20260712000001_sessions_phase3_columns.sql:22-25) is
-- USING (user_id = auth.uid()) with no column list, so B's own USING clause
-- leaves zero rows matching user_id = A -- the UPDATE silently affects
-- nothing rather than raising, hence a row-count comparison rather than
-- throws_ok. The UPDATE is wrapped in its own WITH and passed as SQL text
-- (house precedent: campaigns_test.sql:513-517, block_goals_test.sql:280-283)
-- rather than nested inside is()'s argument list -- a data-modifying CTE
-- must be the top-level statement of the query that executes it, and
-- results_eq's dynamic-text argument is exactly that; a literal subquery
-- embedded in the calling SELECT would not be.
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants SET energy = 5
      WHERE session_id = '00000000-0000-4000-f000-000000000a10'
        AND user_id = '00000000-0000-4000-f000-000000000a01'
      RETURNING 1
    )
    SELECT count(*) FROM upd$$,
  $$VALUES (0::bigint)$$,
  'B cannot write A''s energy -- RLS leaves zero rows to update');

-- 8. B reads A's energy -- the whole point of the widget. "participants
-- readable by other participants" (20260726000001_is_session_participant
-- _dual_schema.sql:182-187) is row-level with no column list, so the crew
-- already sees it through the existing SELECT policy -- no new policy
-- needed, per the migration's own "NO NEW POLICY, ON PURPOSE" note.
SELECT results_eq(
  $$SELECT energy FROM session_participants
    WHERE session_id = '00000000-0000-4000-f000-000000000a10'
      AND user_id = '00000000-0000-4000-f000-000000000a01'$$,
  $$VALUES (4::smallint)$$,
  'B reads A''s energy as 4 -- the crew sees each other''s number');

SELECT * FROM finish();
ROLLBACK;
