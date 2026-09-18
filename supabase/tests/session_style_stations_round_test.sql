BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

-- Migration under test: 20260913000101_session_style_stations_round.sql
-- (sessions.style/stations/round/round_started_at). Plan task D2. Fixture
-- block: 0fxx UUIDs (this suite's namespace, constraint 17 -- 01xx-09xx and
-- 0axx-0exx are already taken; 0fxx was the next free block, grepped
-- against every existing supabase/tests/*.sql fixture before writing this).
--   A = ...0f01 organizer   B = ...0f02 participant   C = ...0f03 participant
--   D = ...0f04, a non-participant of the session -- fixture only, same as
--       session_participant_energy_test.sql's D: the "a non-participant
--       reads nothing" proof already belongs to
--       is_session_participant_dual_schema_test.sql and is not re-asserted
--       here. C is likewise fixture-only, matching the same precedent file
--       (its C is never named in an assertion either) -- this suite proves
--       the four columns' shape, defaults and CHECK, not session RLS from
--       scratch.
--
-- DEVIATION FROM THE BRIEF, RECORDED: the brief lists five numbered proof
-- points, but two of them collapse into one assertion here, and plan(9) --
-- stated by the brief itself -- is the arithmetic that proves it should:
-- 4 has_column + 3 col_type_is + 1 + 1 = 9, not 10. The fixture is
-- explicitly ONE lobby_open session, so brief item 5 ("a fresh session's
-- round reads 1 and stations reads NULL") cannot mean a second inserted
-- row -- it means round/stations are still their insert-time defaults on
-- THE session, which is exactly what item 3's own UPDATE...RETURNING can
-- prove in the same statement it already needs for the style read-back.
-- Assertion 8 below does both jobs at once; see its comment.
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-f000-000000000f01', 'style-a@test.local'),
  ('00000000-0000-4000-f000-000000000f02', 'style-b@test.local'),
  ('00000000-0000-4000-f000-000000000f03', 'style-c@test.local'),
  ('00000000-0000-4000-f000-000000000f04', 'style-d@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-f000-000000000f01', 'style_a'),
  ('00000000-0000-4000-f000-000000000f02', 'style_b'),
  ('00000000-0000-4000-f000-000000000f03', 'style_c'),
  ('00000000-0000-4000-f000-000000000f04', 'style_d');

INSERT INTO sessions (id, organizer_id, state) VALUES
  ('00000000-0000-4000-f000-000000000f10',
   '00000000-0000-4000-f000-000000000f01', 'lobby_open');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('00000000-0000-4000-f000-000000000f10', '00000000-0000-4000-f000-000000000f01'),
  ('00000000-0000-4000-f000-000000000f10', '00000000-0000-4000-f000-000000000f02'),
  ('00000000-0000-4000-f000-000000000f10', '00000000-0000-4000-f000-000000000f03');
-- D is deliberately left out of session_participants for this session.

-- 1-4. The columns themselves, checked before any role switch (precedent:
-- curation_test.sql:19-20 and session_participant_energy_test.sql:35-38 run
-- has_column/col_type_is ahead of SET LOCAL role too).
SELECT has_column('public', 'sessions', 'style', 'sessions.style exists');
SELECT has_column('public', 'sessions', 'stations', 'sessions.stations exists');
SELECT has_column('public', 'sessions', 'round', 'sessions.round exists');
SELECT has_column('public', 'sessions', 'round_started_at', 'sessions.round_started_at exists');

-- 5-7. Column types. round_started_at's type is not separately asserted --
-- has_column above already proves it exists, and the brief's own type-check
-- list names only style/stations/round.
SELECT col_type_is('public', 'sessions', 'style', 'text', 'style is text');
SELECT col_type_is('public', 'sessions', 'stations', 'jsonb', 'stations is jsonb');
SELECT col_type_is('public', 'sessions', 'round', 'integer', 'round is integer');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-f000-000000000f02';

-- 8. THE ASSERTION THAT COULD HAVE BEEN WRONG, doing two jobs at once (see
-- the DEVIATION note above). B is a participant, not the organizer --
-- decision 1 is that the CREW chooses the style, not only the organizer --
-- and "organizer or participant can update session" (20260709000006, no
-- column list) is what has to grant this write; D1 adds no policy of its
-- own, so if this failed the fault would be RLS, not a missing grant. The
-- same RETURNING also proves round and stations are untouched by a
-- style-only UPDATE: still their insert-time defaults (round=1,
-- stations=NULL).
SELECT results_eq(
  $$UPDATE sessions SET style = 'together'
    WHERE id = '00000000-0000-4000-f000-000000000f10'
    RETURNING style, round, stations$$,
  $$VALUES ('together'::text, 1, NULL::jsonb)$$,
  'B (a participant, not the organizer) sets style to together; round and stations keep their defaults');

-- 9. The CHECK: style is one of rounds/freestyle/together, nothing else.
SELECT throws_ok(
  $$UPDATE sessions SET style = 'sprints'
    WHERE id = '00000000-0000-4000-f000-000000000f10'$$,
  '23514', NULL, 'style = sprints is rejected -- the CHECK admits only rounds/freestyle/together');

SELECT * FROM finish();
ROLLBACK;
