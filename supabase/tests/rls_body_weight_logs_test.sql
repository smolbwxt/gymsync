-- Phase H / Task 3: body_weight_logs RLS
-- (20260724000001_body_weight_logs.sql). Covers: owner insert (explicit +
-- default-unit), owner select, owner update (+ reflected), owner delete
-- (+ reflected), both CHECK constraints (weight > 0, unit enum), and the
-- full negative suite in both directions — outsider cannot select, insert
-- (spoofed user_id), update, or delete alice's rows — closing with a
-- postgres-role read proving alice's data survived every outsider no-op.
--
-- Fixture idiom mirrors user_settings_test.sql (single owner + single
-- outsider, same "cu"-style id shape) — the closest existing precedent for
-- a single-owner `FOR ALL` policy table with no relationship oracle.
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(15);

-- ── Fixtures ──────────────────────────────────────────────────────────────
-- a1 alice = owner
-- a2 erin  = outsider — NOT touching alice's rows, used for RLS-denial checks
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000a0001', 'bwa1@t.com'),
  ('00000000-0000-0000-0000-0000000a0002', 'bwa2@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000a0001', 'bw_alice'),
  ('00000000-0000-0000-0000-0000000a0002', 'bw_erin');

-- ============================================================
-- 1. Owner: insert (explicit + default unit), select, update, delete
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0001';  -- Alice

-- ── 1. Owner can insert own row with weight/unit/logged_at all explicit ──
SELECT lives_ok(
  $$INSERT INTO body_weight_logs (id, user_id, weight, unit, logged_at) VALUES
    ('b0000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000a0001', 182.4, 'lbs', '2026-07-01T09:00:00Z')$$,
  'owner can insert own body_weight_logs row with all columns explicit'
);

-- ── 2. Owner can insert own row omitting unit -> defaults to 'lbs' ────────
SELECT lives_ok(
  $$INSERT INTO body_weight_logs (id, user_id, weight) VALUES
    ('b0000000-0000-0000-0000-000000000002',
     '00000000-0000-0000-0000-0000000a0001', 181.0)$$,
  'owner can insert own row omitting unit'
);
SELECT results_eq(
  $$SELECT unit FROM body_weight_logs
    WHERE id = 'b0000000-0000-0000-0000-000000000002'$$,
  ARRAY['lbs'],
  'unit falls back to its column default (''lbs'') when omitted'
);

-- ── 3. Owner sees both own rows ────────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM body_weight_logs
    WHERE user_id = '00000000-0000-0000-0000-0000000a0001'$$,
  ARRAY[2],
  'owner sees both of their own body_weight_logs rows'
);

-- ── 4. Owner can update own row ────────────────────────────────────────────
SELECT lives_ok(
  $$UPDATE body_weight_logs SET weight = 180.5
    WHERE id = 'b0000000-0000-0000-0000-000000000001'$$,
  'owner can update own body_weight_logs row'
);
SELECT results_eq(
  $$SELECT weight FROM body_weight_logs
    WHERE id = 'b0000000-0000-0000-0000-000000000001'$$,
  ARRAY[180.5::numeric(5,2)],
  'owner update changes weight'
);

-- ── 5. CHECK constraints: weight must be > 0, unit must be lbs/kg ────────
SELECT throws_ok(
  $$UPDATE body_weight_logs SET weight = 0
    WHERE id = 'b0000000-0000-0000-0000-000000000001'$$,
  '23514', NULL,
  'weight <= 0 violates the CHECK constraint'
);
SELECT throws_ok(
  $$UPDATE body_weight_logs SET unit = 'stone'
    WHERE id = 'b0000000-0000-0000-0000-000000000001'$$,
  '23514', NULL,
  'unit outside (lbs, kg) violates the CHECK constraint'
);

-- ── 6. Owner can delete own row ────────────────────────────────────────────
SELECT lives_ok(
  $$DELETE FROM body_weight_logs
    WHERE id = 'b0000000-0000-0000-0000-000000000002'$$,
  'owner can delete own body_weight_logs row'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM body_weight_logs
    WHERE user_id = '00000000-0000-0000-0000-0000000a0001'$$,
  ARRAY[1],
  'deleted row is gone: owner now sees exactly 1 row'
);

-- ============================================================
-- 7. Outsider: denied read/write in every direction
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000a0002';  -- Erin

-- ── 8. Outsider cannot see alice's row (0 rows, not an error) ─────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM body_weight_logs
    WHERE user_id = '00000000-0000-0000-0000-0000000a0001'$$,
  ARRAY[0],
  'outsider cannot see another user''s body_weight_logs row'
);

-- ── 9. Outsider cannot insert a row pretending to be alice (42501) ────────
SELECT throws_ok(
  $$INSERT INTO body_weight_logs (user_id, weight) VALUES
    ('00000000-0000-0000-0000-0000000a0001', 999.0)$$,
  '42501', NULL,
  'outsider cannot insert a body_weight_logs row spoofing another user''s id'
);

-- ── 10. Outsider's UPDATE targeting alice's row affects 0 rows ────────────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE body_weight_logs SET weight = 999.0
      WHERE id = 'b0000000-0000-0000-0000-000000000001'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'outsider''s update of another user''s row affects 0 rows'
);

-- ── 11. Outsider's DELETE targeting alice's row affects 0 rows ────────────
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM body_weight_logs
      WHERE id = 'b0000000-0000-0000-0000-000000000001'
      RETURNING 1
    ) SELECT count(*)::int FROM del$$,
  ARRAY[0],
  'outsider''s delete of another user''s row affects 0 rows'
);

-- ── 12. postgres-role read confirms alice's row survived every outsider
-- no-op untouched ───────────────────────────────────────────────────────────
RESET ROLE;
SELECT results_eq(
  $$SELECT weight FROM body_weight_logs
    WHERE id = 'b0000000-0000-0000-0000-000000000001'$$,
  ARRAY[180.5::numeric(5,2)],
  'alice''s row is unchanged after every outsider no-op attempt above'
);

SELECT * FROM finish();
ROLLBACK;
