BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(11);

-- Migration under test: 20260918000201_venue_rack_counts.sql
-- (venues.rack_counts / _updated_by / _updated_at, public.set_venue_rack_count).
-- Fixture block: 15xx UUIDs (constraint 17 -- this plan claims 15xx for D2
-- and 16xx for D4; 01xx-12xx are taken on master, 13xx/14xx by the held
-- B2 data branch, not this plan's to touch).
--   V = ...1500 the venue under test
--   A = ...1501 checked into V 2 hours ago  -- inside the 12-hour window
--   B = ...1502 checked into V 20 hours ago -- outside the window
--   C = ...1503 never checked into V
--
-- venue_checkins.created_at is set relative to now() (2/20 hours ago), not
-- a fixed 2099 date (constraint 16's usual convention): the assertion
-- under test IS the 12-hour rolling window, so the fixture has to move
-- with now() the same way session_round_engine_test.sql's round timings
-- do. Nothing here does a broad current-date scan of venue_checkins (the
-- RPC filters by venue_id AND user_id = auth.uid()), so there is no real
-- row this fixture could collide with.
--
-- 10-11 are review-data.md's F4/F5 negatives, added here because this is
-- the suite that owns set_venue_rack_count: anon holds no EXECUTE (the
-- established has_function_privilege idiom, friends_live_test.sql:235),
-- and the `auth.uid() IS NULL -> 'sign-in required'` gate, previously
-- untested anywhere in the repo (F5's dead path) -- exercised by clearing
-- request.jwt.claim.sub rather than switching to anon, since anon is
-- revoked before the function body's own gate would ever run.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-e000-000000001501', 'rack-a@test.local'),
  ('00000000-0000-4000-e000-000000001502', 'rack-b@test.local'),
  ('00000000-0000-4000-e000-000000001503', 'rack-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-e000-000000001501', 'rack_a'),
  ('00000000-0000-4000-e000-000000001502', 'rack_b'),
  ('00000000-0000-4000-e000-000000001503', 'rack_c');

INSERT INTO venues (id, name, latitude, longitude, created_by) VALUES
  ('00000000-0000-4000-e000-000000001500', 'Rack Count Gym', 34.0000, -118.0000,
   '00000000-0000-4000-e000-000000001501');

INSERT INTO venue_checkins (venue_id, user_id, created_at) VALUES
  ('00000000-0000-4000-e000-000000001500', '00000000-0000-4000-e000-000000001501', now() - interval '2 hours'),
  ('00000000-0000-4000-e000-000000001500', '00000000-0000-4000-e000-000000001502', now() - interval '20 hours');

-- Helper for assertion 7: folds the two boundary checks (0 and 100) into
-- the one assertion this suite's plan(9) allots the clamp rule. pg_temp
-- disappears at this suite's ROLLBACK like the rest of the fixture; the
-- function runs SECURITY INVOKER (the default), so it inherits whatever
-- role/claim is active at CALL time -- only set_venue_rack_count itself
-- needs to be SECURITY DEFINER.
CREATE FUNCTION pg_temp.rack_count_clamp_rejects_both(p_venue uuid)
RETURNS boolean LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    PERFORM public.set_venue_rack_count(p_venue, 'cable', 0);
    RETURN false; -- did not raise -- the clamp failed to reject 0
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    NULL; -- expected
  END;
  BEGIN
    PERFORM public.set_venue_rack_count(p_venue, 'cable', 100);
    RETURN false; -- did not raise -- the clamp failed to reject 100
  EXCEPTION WHEN SQLSTATE 'P0001' THEN
    NULL; -- expected
  END;
  RETURN true;
END;
$$;

-- 1. The column exists, defaulting to the empty object (a missing key
--    means unknown, never zero -- there is nothing to default a count to).
SELECT is(
  (SELECT column_default FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'venues'
      AND column_name = 'rack_counts'),
  '''{}''::jsonb',
  'venues.rack_counts exists, defaulting to the empty object');

-- 2. The function exists with the (uuid, text, int) signature the app
--    calls through PostgREST.
SELECT is(
  (SELECT array_agg(t::regtype::text ORDER BY ord)
     FROM pg_proc p, unnest(p.proargtypes) WITH ORDINALITY AS u(t, ord)
    WHERE p.proname = 'set_venue_rack_count'
      AND p.pronamespace = 'public'::regnamespace),
  ARRAY['uuid', 'text', 'integer'],
  'set_venue_rack_count takes (uuid, text, integer)');

-- 3. It is SECURITY DEFINER -- that is what lets it read the policy-less
--    venue_checkins table at all.
SELECT is(
  (SELECT prosecdef FROM pg_proc
    WHERE proname = 'set_venue_rack_count'
      AND pronamespace = 'public'::regnamespace),
  true, 'set_venue_rack_count is SECURITY DEFINER');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001501';

-- 4. A (checked in 2h ago) sets barbell to 3; the count and its author land.
SELECT public.set_venue_rack_count(
  '00000000-0000-4000-e000-000000001500', 'barbell', 3);
SELECT results_eq(
  $$SELECT rack_counts->>'barbell', rack_counts_updated_by::text
      FROM venues WHERE id = '00000000-0000-4000-e000-000000001500'$$,
  $$VALUES ('3', '00000000-0000-4000-e000-000000001501')$$,
  'A sets barbell to 3, recorded as the author');

-- 5. A second call for a different class touches only that key --
--    jsonb_set on one key, not a wholesale replace.
SELECT public.set_venue_rack_count(
  '00000000-0000-4000-e000-000000001500', 'machine', 2);
SELECT results_eq(
  $$SELECT rack_counts FROM venues WHERE id = '00000000-0000-4000-e000-000000001500'$$,
  $$VALUES ('{"barbell": 3, "machine": 2}'::jsonb)$$,
  'jsonb_set touches one key -- barbell stays 3 after machine is set');

-- 6. An unlisted class is rejected -- 'bench' is the brief's own example
--    key, and the whitelist is the five venues.equipment classes.
SELECT throws_ok(
  $$SELECT public.set_venue_rack_count(
      '00000000-0000-4000-e000-000000001500', 'bench', 4)$$,
  'P0001', 'unknown equipment class: bench',
  'an unlisted equipment class is rejected by the whitelist');

-- 7. The clamp rejects both ends -- an unknown count is an absent key,
--    never a zero, and a triple-digit rack count is not a real gym.
SELECT ok(
  pg_temp.rack_count_clamp_rejects_both('00000000-0000-4000-e000-000000001500'),
  '0 and 100 both throw -- a rack count is between 1 and 99');

-- 8. B checked in 20 hours ago -- outside the 12-hour presence window.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001502';
SELECT throws_ok(
  $$SELECT public.set_venue_rack_count(
      '00000000-0000-4000-e000-000000001500', 'dumbbell', 5)$$,
  'P0001', 'you need to be at this gym to set its rack count',
  'a 20-hour-old check-in no longer proves presence');

-- 9. C never checked in at all -- same raise, same reason.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-e000-000000001503';
SELECT throws_ok(
  $$SELECT public.set_venue_rack_count(
      '00000000-0000-4000-e000-000000001500', 'dumbbell', 5)$$,
  'P0001', 'you need to be at this gym to set its rack count',
  'a stranger who never checked in cannot set a count either');

-- 10. anon holds no EXECUTE (review-data.md F4).
SELECT ok(
  NOT has_function_privilege('anon', 'public.set_venue_rack_count(uuid,text,integer)', 'EXECUTE'),
  'anon cannot execute set_venue_rack_count');

-- 11. Signed in as `authenticated` but with no JWT sub claim: auth.uid()
--     is NULL, so the function's own first gate raises before the
--     presence check ever runs (review-data.md F5's dead path).
SET LOCAL request.jwt.claim.sub = '';
SELECT throws_ok(
  $$SELECT public.set_venue_rack_count(
      '00000000-0000-4000-e000-000000001500', 'barbell', 3)$$,
  'P0001', 'sign-in required',
  'a caller with no JWT sub cannot set a rack count');

SELECT * FROM finish();
ROLLBACK;
