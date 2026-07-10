BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'fa@t.com'),
  ('00000000-0000-0000-0000-00000000000b', 'fb@t.com'),
  ('00000000-0000-0000-0000-00000000000c', 'fc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'fr_user_a'),
  ('00000000-0000-0000-0000-00000000000b', 'fr_user_b'),
  ('00000000-0000-0000-0000-00000000000c', 'fr_user_c');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Positive: A can send a pending request to B
SELECT lives_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'pending')$$,
  'requester can create pending request'
);

-- Negative: A cannot create a request pretending to be B (WITH CHECK -> 42501)
SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c', 'pending')$$,
  '42501', NULL, 'cannot insert request as another user'
);

-- Negative: A cannot skip pending and insert accepted directly
SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c', 'accepted')$$,
  '42501', NULL, 'cannot insert pre-accepted friendship'
);

-- Negative: A (requester) cannot accept their own outgoing request (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE friendships SET status='accepted'
      WHERE user_id='00000000-0000-0000-0000-00000000000a'
        AND friend_id='00000000-0000-0000-0000-00000000000b'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'requester cannot self-accept'
);

-- Switch to B (recipient)
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';

-- Positive: B sees the incoming request
SELECT results_eq(
  $$SELECT count(*)::int FROM friendships WHERE friend_id='00000000-0000-0000-0000-00000000000b'$$,
  ARRAY[1], 'recipient can read incoming request'
);

-- Positive: B accepts
SELECT results_eq(
  $$WITH upd AS (
      UPDATE friendships SET status='accepted'
      WHERE user_id='00000000-0000-0000-0000-00000000000a'
        AND friend_id='00000000-0000-0000-0000-00000000000b'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'recipient can accept request'
);

-- Switch to C (third party)
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';

-- Negative: C cannot see the A-B friendship
SELECT results_eq(
  $$SELECT count(*)::int FROM friendships$$,
  ARRAY[0], 'third party cannot read others friendships'
);

-- Negative: C cannot delete the A-B friendship (RLS-filtered DELETE = 0 rows)
SELECT results_eq(
  $$WITH del AS (DELETE FROM friendships RETURNING 1) SELECT count(*)::int FROM del$$,
  ARRAY[0], 'third party cannot delete others friendships'
);

SELECT * FROM finish();
ROLLBACK;
