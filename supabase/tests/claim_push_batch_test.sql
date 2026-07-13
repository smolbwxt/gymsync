BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

-- ── Isolation preamble ───────────────────────────────────────────────────────
-- This suite runs against the real linked project (SUPABASE_DB_URL), and
-- push_queue already accumulates real rows from the live pg_cron enqueuers
-- (enqueue_scheduled_pushes, 20260716000003_push_cron.sql) — push_drain_dispatch
-- has been a guarded no-op (Vault secret not seeded until Task 7), so nothing
-- has ever drained the backlog. Since claim_push_batch orders by id ASC, any
-- pre-existing claimable row would be claimed ahead of this file's fixtures
-- and break every "claim returns exactly my fixture rows" assertion below.
-- Exhaust the existing backlog first (attempts is brand new — nothing else
-- increments it, so every pre-existing row starts at 0; 5 max-limit claims
-- guarantees every one of them crosses the attempts<5 threshold and becomes
-- permanently unclaimable for the rest of this transaction) so the fixtures
-- inserted below are the only claimable rows left. Everything here is inside
-- the same BEGIN...ROLLBACK as the rest of the file — no real data changes.
SET LOCAL role service_role;
DO $$
BEGIN
  FOR i IN 1..5 LOOP
    PERFORM public.claim_push_batch(2000000000);
  END LOOP;
END;
$$;

-- ── Fixtures ──────────────────────────────────────────────────────────────────
SET LOCAL role postgres;
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'claim_alice@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'claim_alice');

-- a, b, c: claimable (sent_at NULL, attempts 0). Inserted in this order so
-- id ordering is deterministic (bigint identity, ascending) — and, per the
-- isolation preamble above, these are now the ONLY claimable rows in the
-- table.
INSERT INTO push_queue (user_id, event, payload) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'claim_test_a', '{}'),
  ('00000000-0000-0000-0000-0000000c0001', 'claim_test_b', '{}'),
  ('00000000-0000-0000-0000-0000000c0001', 'claim_test_c', '{}');

-- d: already sent — must never be claimed regardless of attempts.
INSERT INTO push_queue (user_id, event, payload, sent_at) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'claim_test_sent', '{}', now());

-- e: attempts maxed out (5) — must never be claimed even though unsent.
INSERT INTO push_queue (user_id, event, payload, attempts) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'claim_test_exhausted', '{}', 5);


-- ============================================================
-- Grants: only service_role may call claim_push_batch
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000c0001';

-- ── 1. authenticated cannot call claim_push_batch (42501) ─────────────────
SELECT throws_ok(
  $$SELECT * FROM public.claim_push_batch(10)$$,
  '42501', NULL,
  'authenticated clients cannot call claim_push_batch directly'
);

SET LOCAL role anon;

-- ── 2. anon cannot call claim_push_batch (42501) ───────────────────────────
SELECT throws_ok(
  $$SELECT * FROM public.claim_push_batch(10)$$,
  '42501', NULL,
  'anon cannot call claim_push_batch directly'
);


-- ============================================================
-- service_role: claim semantics (table is isolated to just this file's
-- fixtures per the preamble above, so exact-set assertions are deterministic)
-- ============================================================
SET LOCAL role service_role;

-- ── 3. First claim with limit=2 returns exactly 2 rows ─────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM public.claim_push_batch(2)$$,
  ARRAY[2],
  'claim_push_batch(2) returns exactly 2 rows'
);

-- ── 4. Those 2 rows are the lowest-id claimable rows (a, b) — ORDER BY id ──
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event IN ('claim_test_a', 'claim_test_b') AND attempts = 1$$,
  ARRAY[2],
  'claim honors ORDER BY id — the two lowest-id claimable rows (a, b) were bumped to attempts=1'
);

-- ── 5. c (next-lowest id) was NOT included in the limit=2 claim ───────────
SELECT results_eq(
  $$SELECT attempts FROM push_queue WHERE event = 'claim_test_c'$$,
  ARRAY[0],
  'the third claimable row (c) is untouched by a limit=2 claim'
);

-- ── 6. The sent fixture was never touched ───────────────────────────────────
SELECT results_eq(
  $$SELECT attempts FROM push_queue WHERE event = 'claim_test_sent'$$,
  ARRAY[0],
  'already-sent row is never claimed (attempts unchanged)'
);

-- ── 7. The exhausted fixture was never touched ──────────────────────────────
SELECT results_eq(
  $$SELECT attempts FROM push_queue WHERE event = 'claim_test_exhausted'$$,
  ARRAY[5],
  'attempts>=5 row is never claimed (attempts unchanged)'
);

-- ── 8. A second, larger claim call picks up ALL still-unsent rows —
--        including a and b again. claim_push_batch only excludes sent_at IS
--        NOT NULL / attempts>=5; it does not itself remove a row from
--        future claims just because it was claimed once. That's intentional
--        (documented in the migration + brief): marking sent is the
--        dispatcher's job after actual delivery, so a row an in-flight
--        drain never got to delivering stays retryable next pass. ─────────
SELECT results_eq(
  $$SELECT count(*)::int FROM public.claim_push_batch(10)
    WHERE event IN ('claim_test_a', 'claim_test_b', 'claim_test_c')$$,
  ARRAY[3],
  'second claim call re-claims a and b and claims c for the first time (all 3 still unsent)'
);

-- ── 9. attempts reflects claim count per row: a and b claimed twice (2),
--        c claimed once (1) — sum = 5 ─────────────────────────────────────
SELECT results_eq(
  $$SELECT sum(attempts)::int FROM push_queue
    WHERE event IN ('claim_test_a', 'claim_test_b', 'claim_test_c')$$,
  ARRAY[5],
  'attempts accumulate correctly across repeated claims (2+2+1=5)'
);

-- ── 10. Rows are still unsent after claiming — claim only bumps attempts;
--        marking sent is the dispatcher's job after actual delivery ────────
SELECT results_eq(
  $$SELECT count(*)::int FROM push_queue
    WHERE event IN ('claim_test_a', 'claim_test_b', 'claim_test_c') AND sent_at IS NULL$$,
  ARRAY[3],
  'claim_push_batch does not itself set sent_at'
);

SELECT * FROM finish();
ROLLBACK;
