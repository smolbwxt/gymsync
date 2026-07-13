BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

-- ── Fixtures ──────────────────────────────────────────────────────────────────
-- cu1 alice = owner
-- cu2 erin  = outsider — NOT touching alice's row, used for RLS-denial checks
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'cu1@t.com'),
  ('00000000-0000-0000-0000-0000000c0002', 'cu2@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000c0001', 'cu_alice'),
  ('00000000-0000-0000-0000-0000000c0002', 'cu_erin');


-- ============================================================
-- Owner: insert, defaults, select, update
-- ============================================================
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000c0001';

-- ── 1. Owner can insert own settings row, omitting default_rest_seconds/palette ──
SELECT lives_ok(
  $$INSERT INTO user_settings (user_id) VALUES
    ('00000000-0000-0000-0000-0000000c0001')$$,
  'owner can insert own user_settings row'
);

-- ── 2. Column defaults apply when omitted (120 / 'midnight') ──────────────────
SELECT results_eq(
  $$SELECT default_rest_seconds, palette FROM user_settings
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  $$VALUES (120, 'midnight'::text)$$,
  'default_rest_seconds/palette fall back to their column defaults when omitted'
);

-- ── 3. Owner sees own row (exactly 1) ──────────────────────────────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM user_settings WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  ARRAY[1],
  'owner sees own user_settings row'
);

-- ── 4. Owner can update own row (lives_ok) ─────────────────────────────────────
SELECT lives_ok(
  $$UPDATE user_settings SET default_rest_seconds = 180, palette = 'arena'
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  'owner can update own user_settings row'
);

-- ── 5. Update is reflected ──────────────────────────────────────────────────────
SELECT results_eq(
  $$SELECT default_rest_seconds, palette FROM user_settings
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  $$VALUES (180, 'arena'::text)$$,
  'owner update changes default_rest_seconds and palette'
);

-- ── 6. CHECK constraint: palette outside the 4 allowed values raises 23514 ─────
SELECT throws_ok(
  $$UPDATE user_settings SET palette = 'sunburst'
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  '23514', NULL,
  'palette outside (midnight, arena, ink, modernist) violates the CHECK constraint'
);

-- ── 7. CHECK constraint: default_rest_seconds below 15 raises 23514 ────────────
SELECT throws_ok(
  $$UPDATE user_settings SET default_rest_seconds = 10
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  '23514', NULL,
  'default_rest_seconds below 15 violates the CHECK constraint'
);

-- ── 8. CHECK constraint: default_rest_seconds above 900 raises 23514 ───────────
SELECT throws_ok(
  $$UPDATE user_settings SET default_rest_seconds = 901
    WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  '23514', NULL,
  'default_rest_seconds above 900 violates the CHECK constraint'
);


-- ============================================================
-- Outsider: denied read/write
-- ============================================================
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000c0002';

-- ── 9. Outsider cannot see alice's row (0 rows, not an error) ──────────────────
SELECT results_eq(
  $$SELECT count(*)::int FROM user_settings WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  ARRAY[0],
  'outsider cannot see another user''s settings row'
);

-- ── 10. Outsider cannot impersonate-insert a row for another user (42501) ──────
SELECT throws_ok(
  $$INSERT INTO user_settings (user_id) VALUES
    ('00000000-0000-0000-0000-0000000c0001')$$,
  '42501', NULL,
  'outsider cannot insert a user_settings row for another user'
);

-- ── 11. Outsider's UPDATE targeting alice's row affects 0 rows (RLS-filtered,
--         not an error) and leaves alice's data untouched ────────────────────
SELECT results_eq(
  $$WITH upd AS (
      UPDATE user_settings SET default_rest_seconds = 999
      WHERE user_id = '00000000-0000-0000-0000-0000000c0001'
      RETURNING 1
    ) SELECT count(*)::int FROM upd$$,
  ARRAY[0],
  'outsider''s update of another user''s settings row affects 0 rows'
);

-- ── 12. postgres-role read confirms alice's row is unchanged ──────────────────
SET LOCAL role postgres;
SELECT results_eq(
  $$SELECT default_rest_seconds FROM user_settings WHERE user_id = '00000000-0000-0000-0000-0000000c0001'$$,
  ARRAY[180],
  'alice''s row is unchanged after the outsider''s no-op update attempt'
);

SELECT * FROM finish();
ROLLBACK;
