BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(16);

-- Venue Hubs H1 (20260729000002). Covers the three enforcement layers the
-- design doc calls load-bearing: venue write gating, the opt-in + block
-- visibility rules on venue_users, and check_in_to_venue's gate-first
-- age/rate-limit/geofence chain.

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-d000-000000000401', 'venue-a@test.local'),
  ('00000000-0000-4000-d000-000000000402', 'venue-b@test.local'),
  ('00000000-0000-4000-d000-000000000403', 'venue-c@test.local');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-4000-d000-000000000401', 'venue_a'),
  ('00000000-0000-4000-d000-000000000402', 'venue_b'),
  ('00000000-0000-4000-d000-000000000403', 'venue_c');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000401';

-- 1-2. Claiming: allowed as self, never pre-verified.
SELECT lives_ok(
  $$INSERT INTO venues (id, name, latitude, longitude, created_by)
    VALUES ('50000000-0000-4000-d000-000000000401', 'Iron Temple', 34.0000, -118.0000,
            '00000000-0000-4000-d000-000000000401')$$,
  'user claims a venue as themselves');
SELECT throws_ok(
  $$INSERT INTO venues (name, latitude, longitude, created_by, is_verified)
    VALUES ('Fake Partner', 34.0, -118.0, '00000000-0000-4000-d000-000000000401', true)$$,
  '42501', NULL, 'cannot self-insert a verified (partnership) venue');

-- 3. Cannot claim on someone else's behalf.
SELECT throws_ok(
  $$INSERT INTO venues (name, latitude, longitude, created_by)
    VALUES ('Impostor Gym', 34.0, -118.0, '00000000-0000-4000-d000-000000000402')$$,
  '42501', NULL, 'cannot claim a venue as another user');

-- 4. Global read: a different user sees the venue exists.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000402';
SELECT is(
  (SELECT count(*) FROM venues WHERE id = '50000000-0000-4000-d000-000000000401')::int,
  1, 'venues are globally readable');

-- 5. Non-creator cannot edit it.
UPDATE venues SET name = 'Hijacked' WHERE id = '50000000-0000-4000-d000-000000000401';
SELECT is(
  (SELECT name FROM venues WHERE id = '50000000-0000-4000-d000-000000000401'),
  'Iron Temple', 'non-creator UPDATE touched nothing');

-- 6. Creator cannot self-verify. Unlike assertion 5 (which no-ops because
--    USING excludes the row), this row DOES match USING — so the WITH CHECK
--    rejects it outright rather than silently matching zero rows.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000401';
SELECT throws_ok(
  $$UPDATE venues SET is_verified = true
    WHERE id = '50000000-0000-4000-d000-000000000401'$$,
  '42501', NULL, 'creator cannot flip is_verified (partnership flag is admin-only)');

-- ── check_in_to_venue gate chain ────────────────────────────────────────
-- 7. Age gate first: no attestation -> rejected even standing on the spot.
SELECT throws_ok(
  $$SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000)$$,
  'P0001', 'age verification required', 'check-in requires the 18+ attestation');

-- Attest (self-attestation is the intended client mechanism).
UPDATE profiles SET age_verified_18plus_at = now()
  WHERE id = '00000000-0000-4000-d000-000000000401';

-- 8. Geofence: ~1.1 km away (0.01 deg latitude) with a 200 m radius.
SELECT throws_ok(
  $$SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0100, -118.0000)$$,
  'P0001', 'you need to be at Iron Temple to check in',
  'check-in rejected outside the geofence');

-- 9-10. Inside the radius succeeds and creates an INVISIBLE membership.
SELECT lives_ok(
  $$SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000)$$,
  'check-in succeeds inside the geofence');
SELECT is(
  (SELECT is_visible_on_hub FROM venue_users
   WHERE venue_id = '50000000-0000-4000-d000-000000000401'
     AND user_id = '00000000-0000-4000-d000-000000000401'),
  false, 'check-in never opts you into hub visibility');

-- 11. Rate limit: 3/hour. One check-in is spent; two more pass, the 4th fails.
SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000);
SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000);
SELECT throws_ok(
  $$SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000)$$,
  'P0001', 'too many check-ins, try again later', 'rate limit caps check-ins at 3/hour');

-- ── venue_users visibility ──────────────────────────────────────────────
-- User B joins the same venue and opts IN; A stays opted out.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000402';
UPDATE profiles SET age_verified_18plus_at = now()
  WHERE id = '00000000-0000-4000-d000-000000000402';
SELECT check_in_to_venue('50000000-0000-4000-d000-000000000401', 34.0000, -118.0000);
UPDATE venue_users SET is_visible_on_hub = true
  WHERE venue_id = '50000000-0000-4000-d000-000000000401'
    AND user_id = '00000000-0000-4000-d000-000000000402';

-- 12. A (a co-member) sees B's visible row.
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000401';
SELECT is(
  (SELECT count(*) FROM venue_users
   WHERE venue_id = '50000000-0000-4000-d000-000000000401'
     AND user_id = '00000000-0000-4000-d000-000000000402')::int,
  1, 'co-member sees an opted-in member');

-- 13. B does NOT see A's opted-out row (but A still sees their own — 14).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000402';
SELECT is(
  (SELECT count(*) FROM venue_users
   WHERE venue_id = '50000000-0000-4000-d000-000000000401'
     AND user_id = '00000000-0000-4000-d000-000000000401')::int,
  0, 'opted-out member is invisible to co-members');
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000401';
SELECT is(
  (SELECT count(*) FROM venue_users
   WHERE venue_id = '50000000-0000-4000-d000-000000000401'
     AND user_id = '00000000-0000-4000-d000-000000000401')::int,
  1, 'you always see your own membership row');

-- 15. Block exclusion: A blocks B -> B''s visible row disappears for A.
INSERT INTO blocked_users (blocker_id, blocked_id)
  VALUES ('00000000-0000-4000-d000-000000000401', '00000000-0000-4000-d000-000000000402');
SELECT is(
  (SELECT count(*) FROM venue_users
   WHERE venue_id = '50000000-0000-4000-d000-000000000401'
     AND user_id = '00000000-0000-4000-d000-000000000402')::int,
  0, 'blocked user is excluded from hub presence');

-- 16. Non-member cannot read the venue leaderboard (gate-first RPC).
SET LOCAL request.jwt.claim.sub = '00000000-0000-4000-d000-000000000403';
SELECT throws_ok(
  $$SELECT * FROM venue_month_leaderboard('50000000-0000-4000-d000-000000000401')$$,
  'P0001', 'not a member of this venue', 'non-member cannot read the local leaderboard');

SELECT * FROM finish();
ROLLBACK;
