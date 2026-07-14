-- 20260717000004_curator_guard_trigger.sql
-- The REAL enforcement for profiles.is_curator (20260717000003's column-level
-- REVOKE is a no-op here: authenticated/anon hold TABLE-WIDE UPDATE on
-- public.profiles via this project's default privileges, and Postgres ORs
-- table- and column-level ACLs — a column REVOKE cannot subtract from a
-- table-wide GRANT).
--
-- Covers BOTH write paths:
--   UPDATE: any client-role change to is_curator is rejected.
--   INSERT: the profiles INSERT policy is only WITH CHECK (auth.uid() = id)
--           with no column restriction, so without this a crafted signup
--           INSERT could self-promote (`is_curator: true`) at creation.
--
-- Keyed off the `role` GUC — matches authenticated/anon as set for PostgREST
-- requests and by pgTAP's SET LOCAL role. postgres/service_role stay able to
-- promote curators directly.
--
-- Idempotent by design (OR REPLACE + DROP IF EXISTS): the UPDATE-only
-- predecessor of this trigger was hand-applied to the live DB during the
-- previous migration's development; replaying this file converges any
-- environment to the same end state.
CREATE OR REPLACE FUNCTION public.guard_is_curator()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF current_setting('role', true) IN ('authenticated', 'anon') THEN
    IF TG_OP = 'INSERT' THEN
      IF NEW.is_curator THEN
        RAISE EXCEPTION 'is_curator is not client-writable'
          USING ERRCODE = '42501';
      END IF;
    ELSIF NEW.is_curator IS DISTINCT FROM OLD.is_curator THEN
      RAISE EXCEPTION 'is_curator is not client-writable'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS profiles_guard_is_curator ON public.profiles;
CREATE TRIGGER profiles_guard_is_curator
  BEFORE INSERT OR UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.guard_is_curator();
