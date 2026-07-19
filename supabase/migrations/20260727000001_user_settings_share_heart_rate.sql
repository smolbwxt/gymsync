-- 20260727000001_user_settings_share_heart_rate.sql
--
-- Phase W Task 4 (watch-hr design §4, "Opt-in": `share_heart_rate` toggle —
-- `docs/superpowers/specs/2026-07-19-watch-hr-design.md:21`; wire shape §5,
-- `docs/superpowers/specs/2026-06-28-gymsync-design.md:1035`, "Opt-in per
-- user (`profiles.share_heart_rate`)").
--
-- PLACEMENT DEVIATION (recorded, task-4-report.md): the master spec's Data
-- Model section lists this column under `profiles`
-- (2026-06-28-gymsync-design.md:185), and §5's prose above still says
-- "profiles.share_heart_rate" — but that Data Model section is explicitly
-- "loose DDL syntax; exact types and constraints finalized in migrations"
-- (same doc, line 172), and no `profiles.share_heart_rate` column has ever
-- actually been created (grepped every migration before writing this one:
-- zero hits). `user_settings` (Canvas Completion Task 2,
-- 20260717000001_user_settings.sql) is this codebase's ACTUAL "single
-- settings row per user" home for opt-in preference toggles today
-- (default_rest_seconds, palette) — the task-4 brief instructs adding it
-- here explicitly, and this migration follows that instruction.
--
-- Default false (opt-in, design §4: "Default OFF"). NOT NULL — a boolean
-- preference toggle has no meaningful "unset" state distinct from "off."
ALTER TABLE public.user_settings
  ADD COLUMN share_heart_rate boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.user_settings.share_heart_rate IS
  'Opt-in: broadcast this user''s heart rate on the session:{id}:hr Realtime channel while in a live session (watch-hr design §4/§6.5; master spec §5). Enabling this column does NOT trigger any permission prompt on the phone — HealthKit heart-rate read authorization is requested WATCH-side, only when the Watch actually starts sampling for a live session (T5 scope). This column is a pure preference write. EPHEMERAL LAW: heart-rate samples (bpm) are never persisted anywhere — this column only stores the opt-in choice, never a reading.';
