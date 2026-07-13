BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(26);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- pu1 alice = organizer / PR scorer / late-participant test author
-- pu2 bob   = invitee / mentioned member / opts out of friend_request later
-- pu3 carol = invitee / mentioned member
-- pu4 dave  = mentioned member (not in the test session)
-- pu5 erin  = outsider — NOT a group member, used for RLS-denial + non-member-mention checks
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000f0001', 'pf1@t.com'),
  ('00000000-0000-0000-0000-0000000f0002', 'pf2@t.com'),
  ('00000000-0000-0000-0000-0000000f0003', 'pf3@t.com'),
  ('00000000-0000-0000-0000-0000000f0004', 'pf4@t.com'),
  ('00000000-0000-0000-0000-0000000f0005', 'pf5@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000f0001', 'pf_alice'),
  ('00000000-0000-0000-0000-0000000f0002', 'pf_bob'),
  ('00000000-0000-0000-0000-0000000f0003', 'pf_carol'),
  ('00000000-0000-0000-0000-0000000f0004', 'pf_dave'),
  ('00000000-0000-0000-0000-0000000f0005', 'pf_erin');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

INSERT INTO groups (id, name, created_by) VALUES
  ('00000000-0000-0000-0000-0000000f1001', 'Push Crew', '00000000-0000-0000-0000-0000000f0001');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f0001', 'admin');

SET LOCAL role postgres;
-- Bulk-add the remaining members as postgres to avoid needing per-actor admin
-- context switches for fixture setup (RLS on group_members writes isn't what
-- this file is testing).
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f0002', 'member'),
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f0003', 'member'),
  ('00000000-0000-0000-0000-0000000f1001', '00000000-0000-0000-0000-0000000f0004', 'member');
-- pu5 (erin) deliberately NOT added — she's the outsider for this file.


-- ============================================================
-- push_devices: owner-only RLS
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

-- ── 1. Owner registers own device (lives_ok) ───────────────────────────────
SELECT lives_ok(
  $$INSERT INTO push_devices (user_id, apns_token) VALUES
    ('00000000-0000-0000-0000-0000000f0001', 'tok-alice-1')$$,
  'owner can register own push device'
);

-- ── 2. Owner can see own device ────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_devices WHERE user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[1],
  'owner sees own registered device'
);

-- ── 3. Outsider cannot see the device (0 rows, not an error) ──────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0005';
SELECT results_eq(
  $$SELECT count(*)::int FROM push_devices WHERE user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[0],
  'outsider cannot see another user''s push device'
);

-- ── 4. Outsider cannot impersonate-insert a device for another user (42501) ─
SELECT throws_ok(
  $$INSERT INTO push_devices (user_id, apns_token) VALUES
    ('00000000-0000-0000-0000-0000000f0001', 'tok-impersonate')$$,
  '42501', NULL,
  'outsider cannot insert a push device for another user'
);


-- ============================================================
-- notification_prefs: owner-only RLS
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

-- ── 5. Owner sets own pref (lives_ok) ──────────────────────────────────────
SELECT lives_ok(
  $$INSERT INTO notification_prefs (user_id, category, enabled) VALUES
    ('00000000-0000-0000-0000-0000000f0001', 'chat_mention', true)$$,
  'owner can insert own notification pref'
);

-- ── 6. Owner sees own pref ─────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM notification_prefs WHERE user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[1],
  'owner sees own notification pref'
);

-- ── 7. Outsider cannot see the pref ────────────────────────────────────────
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0005';
SELECT results_eq(
  $$SELECT count(*)::int FROM notification_prefs WHERE user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[0],
  'outsider cannot see another user''s notification pref'
);

-- ── 8. Outsider cannot impersonate-insert a pref for another user (42501) ──
SELECT throws_ok(
  $$INSERT INTO notification_prefs (user_id, category, enabled) VALUES
    ('00000000-0000-0000-0000-0000000f0001', 'session_invite', false)$$,
  '42501', NULL,
  'outsider cannot insert a notification pref for another user'
);


-- ============================================================
-- friend_request trigger
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

-- ── 9. Pending friend request from alice to bob enqueues a push to bob ─────
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0002', 'pending');

SET LOCAL role postgres;
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'friend_request' AND user_id = '00000000-0000-0000-0000-0000000f0002'$$,
  ARRAY[1],
  'friend_request push enqueued for the recipient (friend_id)'
);


-- ============================================================
-- push_queue: no client access at all
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0002';

-- ── 10. Client SELECT on push_queue returns 0 rows despite a row existing ──
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue$$,
  ARRAY[0],
  'push_queue is invisible to clients even though rows exist'
);

-- ── 11. Client INSERT into push_queue is rejected (42501) ─────────────────
SELECT throws_ok(
  $$INSERT INTO push_queue (user_id, event, payload) VALUES
    ('00000000-0000-0000-0000-0000000f0002', 'fake_event', '{}')$$,
  '42501', NULL,
  'client cannot insert directly into push_queue'
);


-- ============================================================
-- session_invite trigger
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f0001',
   '00000000-0000-0000-0000-0000000f1001', 'scheduled', now() + interval '1 hour');

-- Organizer's own participant row — must NOT enqueue a session_invite push.
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f0001', 'online');

-- Invitees.
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f0002', 'invited'),
  ('00000000-0000-0000-0000-0000000f2001', '00000000-0000-0000-0000-0000000f0003', 'online');

SET LOCAL role postgres;

-- ── 12. Organizer's own row is skipped ─────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_invite' AND user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[0],
  'session_invite is not enqueued for the organizer''s own participant row'
);

-- ── 13. Invitees (bob, carol) each get a session_invite push ──────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_invite'
      AND user_id IN ('00000000-0000-0000-0000-0000000f0002', '00000000-0000-0000-0000-0000000f0003')$$,
  ARRAY[2],
  'session_invite is enqueued for each non-organizer invitee'
);


-- ============================================================
-- session_lobby_open trigger
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

UPDATE sessions SET state = 'lobby_open'
  WHERE id = '00000000-0000-0000-0000-0000000f2001';

SET LOCAL role postgres;

-- ── 14. bob (still 'invited', not yet present) gets a lobby_open push ─────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_lobby_open' AND user_id = '00000000-0000-0000-0000-0000000f0002'$$,
  ARRAY[1],
  'session_lobby_open pushes a participant who has not checked in yet'
);

-- ── 15. carol and alice (already 'online') do NOT get a lobby_open push ───
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'session_lobby_open'
      AND user_id IN ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0003')$$,
  ARRAY[0],
  'session_lobby_open skips participants who are already checked in / present'
);


-- ============================================================
-- your_turn trigger
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

UPDATE sessions SET current_turn_user_id = '00000000-0000-0000-0000-0000000f0002'
  WHERE id = '00000000-0000-0000-0000-0000000f2001';

SET LOCAL role postgres;

-- ── 16. bob gets a your_turn push ──────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'your_turn' AND user_id = '00000000-0000-0000-0000-0000000f0002'$$,
  ARRAY[1],
  'your_turn push enqueued for the new turn holder'
);

SET LOCAL role authenticated;
UPDATE sessions SET current_turn_user_id = NULL
  WHERE id = '00000000-0000-0000-0000-0000000f2001';
UPDATE sessions SET current_turn_user_id = '00000000-0000-0000-0000-0000000f0003'
  WHERE id = '00000000-0000-0000-0000-0000000f2001';

SET LOCAL role postgres;

-- ── 17. Clearing to NULL never enqueues; only carol (the real new holder) does ─
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue WHERE event = 'your_turn'$$,
  ARRAY[2],
  'your_turn skips the NULL transition (only 2 real turn-holder pushes total)'
);


-- ============================================================
-- partner_pr trigger
-- ============================================================
SET LOCAL role postgres;
INSERT INTO chat_messages (id, group_id, author_id, kind, body, payload) VALUES
  ('00000000-0000-0000-0000-0000000f3010', '00000000-0000-0000-0000-0000000f1001', NULL,
   'system_pr', 'test pr announcement',
   jsonb_build_object('user_id', '00000000-0000-0000-0000-0000000f0001'));

-- ── 18. bob, carol, dave (all other group members) get a partner_pr push ──
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'partner_pr' AND payload ->> 'message_id' = '00000000-0000-0000-0000-0000000f3010'$$,
  ARRAY[3],
  'partner_pr pushes every other group member'
);

-- ── 19. alice (the PR scorer / author) does not get pushed her own PR ─────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'partner_pr' AND user_id = '00000000-0000-0000-0000-0000000f0001'$$,
  ARRAY[0],
  'partner_pr excludes the PR scorer'
);


-- ============================================================
-- lateness_chirp trigger
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

UPDATE session_participants SET check_in_state = 'late'
  WHERE session_id = '00000000-0000-0000-0000-0000000f2001'
    AND user_id = '00000000-0000-0000-0000-0000000f0002';

SET LOCAL role postgres;

-- ── 20. alice and carol (the other participants) get a lateness_chirp push ─
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'lateness_chirp'
      AND user_id IN ('00000000-0000-0000-0000-0000000f0001', '00000000-0000-0000-0000-0000000f0003')$$,
  ARRAY[2],
  'lateness_chirp pushes the other participants'
);

-- ── 21. bob (the late one) does not get pushed his own lateness ───────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'lateness_chirp' AND user_id = '00000000-0000-0000-0000-0000000f0002'$$,
  ARRAY[0],
  'lateness_chirp excludes the late participant themselves'
);


-- ============================================================
-- chat_mention trigger — parsing scenarios
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0001';

-- Single mention: alice mentions bob.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000f3001', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f0001', 'text', 'hey @pf_bob check this out');

-- Multi mention: alice mentions bob, carol and dave.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000f3002', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f0001', 'text', 'cc @pf_bob @pf_carol @pf_dave');

-- No mention.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000f3003', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f0001', 'text', 'no mentions here at all');

-- Self mention: alice mentions herself.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000f3004', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f0001', 'text', '@pf_alice thanks everyone');

-- Non-member mention: alice mentions erin, who is not in this group.
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('00000000-0000-0000-0000-0000000f3005', '00000000-0000-0000-0000-0000000f1001',
   '00000000-0000-0000-0000-0000000f0001', 'text', '@pf_erin are you around?');

SET LOCAL role postgres;

-- ── 22. Single mention pushes exactly bob ──────────────────────────────────
SELECT results_eq(
  $$SELECT user_id FROM push_queue
    WHERE event = 'chat_mention' AND payload ->> 'message_id' = '00000000-0000-0000-0000-0000000f3001'$$,
  $$VALUES ('00000000-0000-0000-0000-0000000f0002'::uuid)$$,
  'single @mention pushes exactly the mentioned member'
);

-- ── 23. Multi mention pushes bob, carol, dave (3 rows) ─────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'chat_mention' AND payload ->> 'message_id' = '00000000-0000-0000-0000-0000000f3002'$$,
  ARRAY[3],
  'multi @mention pushes every distinct mentioned member'
);

-- ── 24. No-mention message enqueues nothing ────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'chat_mention' AND payload ->> 'message_id' = '00000000-0000-0000-0000-0000000f3003'$$,
  ARRAY[0],
  'message with no @mention enqueues no chat_mention push'
);

-- ── 25. Self mention + non-member mention both enqueue nothing ────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'chat_mention'
      AND payload ->> 'message_id' IN (
        '00000000-0000-0000-0000-0000000f3004', '00000000-0000-0000-0000-0000000f3005')$$,
  ARRAY[0],
  'self-mention and non-member @mention are both silently ignored'
);


-- ============================================================
-- Prefs opt-out suppresses enqueue
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0002';

INSERT INTO notification_prefs (user_id, category, enabled) VALUES
  ('00000000-0000-0000-0000-0000000f0002', 'friend_request', false);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000f0003';
INSERT INTO friendships (user_id, friend_id, status) VALUES
  ('00000000-0000-0000-0000-0000000f0003', '00000000-0000-0000-0000-0000000f0002', 'pending');

SET LOCAL role postgres;

-- ── 26. Opted-out bob still has exactly 1 friend_request row (the earlier
--        one from alice, before he opted out) — the new one from carol was
--        suppressed by enqueue_push's prefs check ───────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event = 'friend_request' AND user_id = '00000000-0000-0000-0000-0000000f0002'$$,
  ARRAY[1],
  'notification_prefs opt-out suppresses further enqueue for that category'
);

SELECT * FROM finish();
ROLLBACK;
