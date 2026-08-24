-- Field bug 2026-08-24: @Coach still silent AFTER the RLS insert-policy
-- fix. Root cause: 20260822000003 added chat_messages_kind_check_v3
-- (which allows 'coach_reply') but dropped a constraint named
-- chat_messages_kind_check_v2 — the live table's original constraint is
-- named chat_messages_kind_check, and IF EXISTS made the wrong-name
-- drop silent. Postgres enforces EVERY check constraint on a row, so
-- coach_reply inserts passed RLS and then violated the stale original.
ALTER TABLE public.chat_messages
  DROP CONSTRAINT IF EXISTS chat_messages_kind_check;
