-- ============================================================
-- Phase H / Task 3: body weight log + trend
-- ============================================================
-- Master spec (docs/superpowers/specs/2026-06-28-gymsync-design.md:395-401)
-- `body_weight_logs` schema, verbatim columns:
--
--   body_weight_logs (
--     id                  uuid PRIMARY KEY,
--     user_id             uuid REFERENCES profiles(id),
--     weight              numeric(5,2),
--     unit                text DEFAULT 'lbs',
--     logged_at           timestamptz DEFAULT now()
--   )
--
-- RLS list (`:658`): "body_weight_logs — owner only." No relationship
-- oracle needed (unlike is_blocked()/is_group_member() elsewhere) — a plain
-- single-owner table, same shape as `user_settings`
-- (20260717000001_user_settings.sql) and `blocked_users`
-- (20260721000001_moderation_block_report.sql): one `FOR ALL` policy
-- covering SELECT/INSERT/UPDATE/DELETE, all gated on `user_id = auth.uid()`.
--
-- Beyond the terse 5-line spec block (same "spec is the column list, not
-- the DDL" gap every other table in this repo has closed identically —
-- blocked_users' spec block has no NOT NULL/ON DELETE CASCADE/CHECK either,
-- and the applied migration added all three): `id` defaults
-- `gen_random_uuid()` (user_reports' idiom), `user_id`/`weight`/`unit`/
-- `logged_at` are NOT NULL (every writer — the app's log sheet, the QA seed
-- script — always supplies or defaults all four; a body-weight row with no
-- weight is meaningless), the `user_id` FK cascades on profile deletion
-- (same as blocked_users/user_reports — this is personal history, not a
-- shared record another user's row could dangle-reference). Two defensive
-- CHECK constraints not in the spec's literal text, same "spec is silent,
-- codebase convention fills the gap" reasoning as blocked_users' self-block
-- CHECK: `weight > 0` (a non-positive body weight is never valid) and
-- `unit IN ('lbs', 'kg')` (a controlled vocabulary, same idiom as
-- `user_settings.palette`/`user_reports.status`) — 'lbs' is the only unit
-- this app writes today (no unit-preference setting exists anywhere in
-- `profiles`/`user_settings`, confirmed by grep before this migration was
-- written; the log sheet defaults to lbs per the task brief), 'kg' is
-- included as the obvious future value so a later unit-preference feature
-- doesn't need a fix-forward CHECK replacement for day-one data.
CREATE TABLE public.body_weight_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  weight      numeric(5,2) NOT NULL CHECK (weight > 0),
  unit        text NOT NULL DEFAULT 'lbs' CHECK (unit IN ('lbs', 'kg')),
  logged_at   timestamptz NOT NULL DEFAULT now()
);

-- Backs "this user's rows, most recent first" — the only query shape the
-- app issues (BodyWeightLogRepository.recent), same single (owner, time)
-- composite index idiom as personal_records' access pattern.
CREATE INDEX body_weight_logs_user_id_logged_at_idx
  ON public.body_weight_logs(user_id, logged_at DESC);

ALTER TABLE public.body_weight_logs ENABLE ROW LEVEL SECURITY;

-- Owner-only, both directions, single ALL policy — no relationship oracle
-- needed (this table is never read/written by anyone but its owner), same
-- shape as "owner manages own settings" (user_settings) / "owner manages
-- own devices" (push_devices, 20260716000001_push_schema.sql) / "blocker
-- manages own blocks" (blocked_users).
CREATE POLICY "owner manages own body weight logs"
  ON public.body_weight_logs FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
