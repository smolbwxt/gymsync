-- ============================================================
-- Training Programs P1: program_enrollments — table + owner-only RLS.
-- ============================================================
-- Design doc: docs/superpowers/specs/2026-07-24-training-programs-design.md
-- ("Server state: one table" section — schema quoted verbatim below; RLS:
-- "owner-only for SELECT/INSERT/UPDATE/DELETE (`user_id = auth.uid()`),
-- the `soundboard_favorites` idiom. No curator/admin surface, no
-- cross-user reads in P1").
--
-- Programs are the SELF-ASSIGNED counterpart to Phase C's team-curated
-- community campaigns (20260728000001_campaigns_schema.sql) and share no
-- tables, triggers, or RPCs with them (spec non-goals: "No coupling to
-- community campaigns' tables, triggers, or leaderboards"). Templates are
-- bundled in the app (spec: "Templates: bundled in-app, not in the
-- database"), so `template_slug` is a plain text tag, deliberately NOT an
-- FK — there is nothing server-side to reference in P1.
--
-- Derived-state posture (spec): current week is date math off
-- `started_on`; progress is derived from existing set_logs. No counters,
-- no triggers, nothing a client could double-count — the polar opposite
-- of campaign_progress's trigger-only counters, on purpose.
--
-- Tightenings beyond the spec's column list (documented per the
-- "spec is the column list, not the DDL" precedent,
-- 20260724000001_body_weight_logs.sql:22-41):
--   * ended_reason gains an allowed-values CHECK ('completed'|'abandoned'
--     — the spec's own two named values) and a pairing CHECK with
--     ended_at ((ended_at IS NULL) = (ended_reason IS NULL)): a reason
--     without a timestamp (or vice versa) can only ever be a client bug.
--   * template_slug/focus/baseline NOT NULL are spec-stated; focus and
--     baseline default to no value (the client always sends them —
--     baseline may be '{}'::jsonb for volume-driven templates per the
--     spec's hypertrophy note, but that is the CLIENT writing an explicit
--     empty object, not a server default masking a missing write).
CREATE TABLE public.program_enrollments (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  template_slug  text NOT NULL,
  focus          jsonb NOT NULL,
  baseline       jsonb NOT NULL,
  started_on     date NOT NULL,
  weeks          integer NOT NULL CHECK (weeks BETWEEN 1 AND 52),
  ended_at       timestamptz,
  ended_reason   text CHECK (ended_reason IN ('completed', 'abandoned')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  CHECK ((ended_at IS NULL) = (ended_reason IS NULL))
);

-- Spec verbatim: "one active program at a time" — enforced by the partial
-- unique index, not client logic. Ending a program (ended_at set) frees
-- the slot; history rows accumulate without limit.
CREATE UNIQUE INDEX one_active_program_per_user
  ON public.program_enrollments(user_id) WHERE ended_at IS NULL;

ALTER TABLE public.program_enrollments ENABLE ROW LEVEL SECURITY;

-- Owner-only ALL — the blocked_users "manages own rows" idiom
-- (20260721000001_moderation_block_report.sql): one FOR ALL policy, USING
-- for read/update/delete visibility, WITH CHECK for insert/update writes.
-- No admin/curator policy, no cross-user read (P3 community programs will
-- design that surface when it exists; nothing is opened speculatively).
CREATE POLICY "user manages own program enrollments"
  ON public.program_enrollments FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
