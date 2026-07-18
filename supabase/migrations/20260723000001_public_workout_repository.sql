-- ============================================================
-- Phase L Task 1: Public Workout Repository backend core —
-- workout_attempts + leaderboard_entries + recompute + RLS.
-- ============================================================
-- Design doc citations:
--   Schema (verbatim column set)     — docs/superpowers/specs/2026-06-28-
--                                       gymsync-design.md:404-432
--   Flow 4 (attempt lifecycle)       — same file:790-797
--   Flow 6 (duration-edit lock rule) — same file:831-836
--   Phase L design §1                — docs/superpowers/specs/2026-07-18-
--                                       discover-leaderboards-design.md:7-11
--
-- ── FINDING 1: which `routines` public-workout fields already exist ────────
-- Phase L §1 names 5 routine-level fields: visibility, is_featured,
-- default_sort, scoring_metrics, scoring_top_set_exercise_id. Audit of every
-- migration that has ever touched public.routines
-- (20260709000005_create_routines.sql — the CREATE TABLE — and
-- 20260717000003_curation.sql, the only other migration that ALTERs
-- routines, which only touches its INSERT/UPDATE policies, not columns;
-- grepped is_featured/default_sort/scoring_metrics/
-- scoring_top_set_exercise_id across supabase/migrations/ and
-- GymSyncApp/ — zero hits anywhere before this migration) shows only
-- `visibility` shipped. The other 4 are added below, fix-forward,
-- nullable/defaulted so every existing row (curated seed content included)
-- stays valid with no backfill.
-- ============================================================

-- ── 1. Missing `routines` public-workout columns (fix-forward) ─────────────
ALTER TABLE public.routines
  ADD COLUMN is_featured                 boolean NOT NULL DEFAULT false,
  ADD COLUMN default_sort                text
    CHECK (default_sort IS NULL OR default_sort IN ('time','volume','top_set','recent')),
  ADD COLUMN scoring_metrics             text[]
    CHECK (scoring_metrics IS NULL OR scoring_metrics <@ ARRAY['time','volume','top_set']::text[]),
  ADD COLUMN scoring_top_set_exercise_id uuid REFERENCES public.exercises(id) ON DELETE SET NULL;
-- default_sort/scoring_metrics value sets are a judgment call, not spec text
-- verbatim (the spec names the columns but never enumerates their allowed
-- values): derived from Flow 4's own leaderboard-sort language ("sortable by
-- Time / Total Volume / Top Set / Recent — default sort set by creator",
-- :792) — 'recent' included in default_sort (a valid sort key per Flow 4)
-- but deliberately excluded from scoring_metrics (it's a display ordering,
-- not a scored metric a routine is judged by).

-- ============================================================
-- ── 2. workout_attempts + leaderboard_entries (spec-verbatim column sets) ──
-- ============================================================
-- NOT NULL / ON DELETE choices are NOT spec-verbatim (the spec's ASCII
-- pseudo-schema has no NOT NULL or ON DELETE annotations for ANY table in
-- the whole document, including tables already shipped — e.g. set_logs'
-- pseudo-schema :373-385 shows no NOT NULL either, yet
-- 20260709000007_create_set_logs.sql adds NOT NULL to user_id/session_id).
-- Following that established precedent: user_id/session_id are the rows'
-- defining identity (an attempt without either is meaningless) -> NOT NULL
-- + ON DELETE CASCADE, matching every user_id FK in the codebase and the
-- set_logs/routine_proposals/session_duration_edits "child of a session"
-- CASCADE idiom. routine_id stays nullable + ON DELETE SET NULL, matching
-- sessions.routine_id's own precedent exactly (20260709000006_create_
-- sessions.sql:3) — preserves attempt/leaderboard history if a routine is
-- later deleted, rather than losing it or blocking the delete.
--
-- The spec's own inline comment "-- must have visibility='public'" on
-- workout_attempts.routine_id (:409) is an application-level invariant, not
-- a DB constraint — it can't be expressed as a CHECK (requires a cross-table
-- lookup at insert time) and this migration deliberately does NOT enforce it
-- via a constraint trigger. It is Task 2's attempt-start RPC's
-- responsibility to validate routine.visibility='public' before inserting;
-- see the RLS section below for why no other write path can reach this
-- table at all.

CREATE TABLE public.workout_attempts (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id               uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  user_id                  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id               uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  is_opt_in_leaderboard    boolean DEFAULT false,
  started_at               timestamptz,
  completed_at             timestamptz,
  is_complete              boolean DEFAULT false
);

-- One attempt per (session, user) — not spec-annotated but required for the
-- recompute/refresh triggers below to be sound rather than best-effort
-- (LIMIT 1 semantics over a not-actually-unique key would silently drop
-- data). A user's per-session attempt row is 1:1 by construction: it
-- represents "this user's attempt at the public routine within this one
-- session," and every write path (Task 2's future attempt-start RPC) only
-- ever needs to create it once at session start.
CREATE UNIQUE INDEX workout_attempts_session_user_idx
  ON public.workout_attempts(session_id, user_id);

CREATE TABLE public.leaderboard_entries (
  attempt_id          uuid PRIMARY KEY REFERENCES public.workout_attempts(id) ON DELETE CASCADE,
  routine_id          uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  user_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  time_seconds        integer,
  total_volume        numeric(10,2),
  top_sets            jsonb,
  is_complete         boolean NOT NULL DEFAULT false,
  is_edited           boolean DEFAULT false,
  computed_at         timestamptz DEFAULT now()
);

-- The two indexes named verbatim in the spec's own comment block (:430-431).
CREATE INDEX leaderboard_entries_routine_time_idx
  ON public.leaderboard_entries(routine_id, time_seconds ASC NULLS LAST);
CREATE INDEX leaderboard_entries_routine_volume_idx
  ON public.leaderboard_entries(routine_id, total_volume DESC NULLS LAST);

-- ============================================================
-- ── 3. RLS ───────────────────────────────────────────────────────────────
-- ============================================================
-- Placement judgment call (per the brief): the spec places
-- is_opt_in_leaderboard ONLY on workout_attempts, never denormalizing it
-- onto leaderboard_entries (:418-429 lists leaderboard_entries' full column
-- set and it is not there). Since Task 1 is scoped to the spec's tables
-- "verbatim," this migration does NOT add an extra boolean column to
-- leaderboard_entries beyond spec — the entries SELECT policy instead joins
-- through workout_attempts, exactly the same shape as the pre-existing
-- "routine_exercises follow parent routine visibility" policy
-- (20260709000005_create_routines.sql:48-54, a plain EXISTS subquery to a
-- single parent table with no back-reference — safe from the RLS-recursion
-- problem that requires SECURITY DEFINER helpers elsewhere in this repo,
-- e.g. is_session_participant/is_group_member, because those pairs
-- reference EACH OTHER; workout_attempts' own policy never references
-- leaderboard_entries, so there is no cycle here).

ALTER TABLE public.workout_attempts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.leaderboard_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "opt-in or owner can read workout attempts"
  ON public.workout_attempts FOR SELECT TO authenticated
  USING (is_opt_in_leaderboard = true OR user_id = auth.uid());

CREATE POLICY "opt-in or owner can read leaderboard entries"
  ON public.leaderboard_entries FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.workout_attempts wa
      WHERE wa.id = leaderboard_entries.attempt_id
        AND wa.is_opt_in_leaderboard = true
    )
  );

-- No INSERT/UPDATE/DELETE policy for `authenticated` on either table — same
-- "trigger-only writes" idiom as 20260719000006_streaks.sql (user_streaks/
-- group_streaks) and 20260709000008_lifetime_volume_trigger.sql
-- (increment_lifetime_volume writing to profiles despite profiles' own
-- restrictive RLS): the absence of a write policy makes every client
-- INSERT/UPDATE/DELETE fail closed with 42501, and all real writes below
-- are SECURITY DEFINER functions owned by the migration role, which are
-- exempt from their own tables' RLS as table owner.
--
-- workout_attempts' actual INSERT (attempt-start) is explicitly Task 2's
-- scope, not this migration's — "the attempt row itself gets created by
-- Task 2's RPC" (brief). This migration deliberately leaves NO authenticated
-- INSERT policy so that RPC is forced to be SECURITY DEFINER (or otherwise
-- privileged) to do its job, exactly like every other write path on these
-- two tables. Documented here so Task 2 does not need to reverse-engineer
-- why a naive client-side .insert() would fail.

-- ============================================================
-- ── 4. Recompute: DEFINER function + trigger on session completion ────────
-- ============================================================
-- ── THE RECOMPUTE-HOOK FINDING (cite everything) ────────────────────────────
-- Grepped every write path that can ever set sessions.state = 'completed':
--   • SessionRepository.complete(sessionID:) (GymSyncApp/GymSync/Models/
--     SessionRepository.swift:59-71) — a direct client
--     `.from("sessions").update(["state":"completed","completed_at":...])`.
--     This is the ONLY completion call site in the entire Swift app — used
--     for BOTH solo (WorkoutSessionView.swift:681) AND group
--     (GroupSessionLiveView.swift:1831) "End Session" taps. There is no
--     separate "group complete() RPC": group sessions complete through this
--     exact same function as solo ones.
--   • idle_rpcs.sql's wrap-up/auto-abandon path (20260716000006_idle_rpcs.sql
--     :36-39) — `UPDATE public.sessions SET state='completed', completed_at=
--     COALESCE(last_activity_at, started_at) WHERE id=... AND
--     state='in_progress'` (organizer "Wrap Up" push action + cron).
-- Both paths funnel through one choke point: a plain UPDATE of
-- `sessions.state` (and completed_at, in the same statement). This is
-- IDENTICAL to the hook 20260719000006_streaks.sql already uses for the
-- exact same event ("wire a trigger on sessions completion... consistent
-- with the streak trigger's shape" — brief) —
-- `AFTER UPDATE OF state ON public.sessions`, same OLD/NEW state-diff guard,
-- same "only 'completed' triggers real work" branch. Reusing that shape
-- rather than inventing a new one on workout_attempts itself (e.g. `UPDATE
-- OF is_complete`) is the honest choice: nothing ever writes
-- workout_attempts.is_complete directly except this very trigger, so
-- watching for that write would be circular.
--
-- Per Flow 6 (:825-826), an `abandoned` session computes NO leaderboard
-- entry at all — the WHEN clause below only fires on `state = 'completed'`,
-- never 'abandoned', matching that rule exactly.
--
-- Anchoring time_seconds on workout_attempts' OWN started_at/completed_at
-- (not the session's) rather than NEW.started_at/NEW.completed_at directly:
-- workout_attempts.started_at is set once, at attempt-start, by Task 2's RPC
-- (out of this migration's scope); this trigger sets
-- workout_attempts.completed_at = NEW.completed_at (the session's official
-- end time) exactly once, the moment `state` transitions into 'completed'.
-- That single write is also what makes the duration-edit lock rule (Flow 6,
-- :831-836) true BY CONSTRUCTION rather than by a separate guard: a later
-- manual duration edit (SessionRepository.editDuration, see the duration-
-- edit trigger below) updates sessions.started_at/completed_at directly but
-- NEVER touches `state` (the session is already 'completed'), so this
-- `AFTER UPDATE OF state` trigger simply never re-fires for it — time_seconds
-- (and workout_attempts.completed_at) are physically never touched again
-- after the one completion event, with no need for an extra "don't overwrite
-- if already set" branch.

CREATE OR REPLACE FUNCTION public.leaderboard_attempt_volume(p_session_id uuid, p_user_id uuid)
RETURNS TABLE(total_volume numeric, top_sets jsonb)
LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  -- Shared by the recompute trigger and the set_log-edit refresh trigger
  -- below. Excl.-penalty/failed idiom matches the established pattern in
  -- increment_lifetime_volume (20260709000008_lifetime_volume_trigger.sql:4)
  -- and is_pr (20260709000009_pr_detection_trigger.sql:11-13): `is_failed =
  -- false AND is_penalty = false`. "Top set" = per-exercise best (max)
  -- weight among those same non-failed non-penalty logs, per the spec's own
  -- inline comment on top_sets ("{exercise_id: best_weight}", :424).
  SELECT
    COALESCE((
      SELECT SUM(reps * weight) FROM public.set_logs
      WHERE session_id = p_session_id AND user_id = p_user_id
        AND is_failed = false AND is_penalty = false
        AND reps IS NOT NULL AND weight IS NOT NULL
    ), 0)::numeric(10,2) AS total_volume,
    COALESCE((
      SELECT jsonb_object_agg(x.exercise_id::text, x.max_weight)
      FROM (
        SELECT exercise_id, MAX(weight) AS max_weight
        FROM public.set_logs
        WHERE session_id = p_session_id AND user_id = p_user_id
          AND is_failed = false AND is_penalty = false AND weight IS NOT NULL
        GROUP BY exercise_id
      ) x
    ), '{}'::jsonb) AS top_sets;
$$;

-- Internal plumbing only (same idiom as streak_bump_*/streak_break_* —
-- 20260719000006_streaks.sql:249-255): never a client RPC, only ever called
-- from the SECURITY DEFINER trigger functions below.
REVOKE EXECUTE ON FUNCTION public.leaderboard_attempt_volume(uuid, uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.leaderboard_recompute_on_session_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec            RECORD;
  v_time_seconds integer;
  v_metrics      RECORD;
BEGIN
  -- Same OLD/NEW state-diff guard shape as streak_on_session_state_change
  -- (20260719000006_streaks.sql:309-314): a same-value refire, or any
  -- transition that isn't INTO 'completed' (including 'abandoned' — Flow 6
  -- :825-826, no leaderboard entry for abandoned sessions), is a no-op.
  IF NEW.state IS NOT DISTINCT FROM OLD.state OR NEW.state <> 'completed' THEN
    RETURN NEW;
  END IF;

  -- A session can carry more than one attempt (a group of friends all
  -- attempting the same public routine together, each opted in
  -- individually) — loop over every workout_attempts row tied to this
  -- session, not just one.
  FOR rec IN
    SELECT * FROM public.workout_attempts WHERE session_id = NEW.id
  LOOP
    UPDATE public.workout_attempts
      SET completed_at = NEW.completed_at,
          is_complete = true
      WHERE id = rec.id;

    v_time_seconds := CASE
      WHEN rec.started_at IS NOT NULL AND NEW.completed_at IS NOT NULL
      THEN EXTRACT(EPOCH FROM (NEW.completed_at - rec.started_at))::integer
      ELSE NULL
    END;

    SELECT * INTO v_metrics
      FROM public.leaderboard_attempt_volume(NEW.id, rec.user_id);

    INSERT INTO public.leaderboard_entries
      (attempt_id, routine_id, user_id, time_seconds, total_volume, top_sets, is_complete, computed_at)
    VALUES
      (rec.id, rec.routine_id, rec.user_id, v_time_seconds,
       v_metrics.total_volume, v_metrics.top_sets, true, now())
    ON CONFLICT (attempt_id) DO UPDATE
      SET routine_id   = EXCLUDED.routine_id,
          user_id      = EXCLUDED.user_id,
          time_seconds = EXCLUDED.time_seconds,
          total_volume = EXCLUDED.total_volume,
          top_sets     = EXCLUDED.top_sets,
          is_complete  = EXCLUDED.is_complete,
          computed_at  = now();
          -- is_edited deliberately excluded from this SET list — a recompute
          -- must never clear a duration-edit's "edited" flag. Defensive only:
          -- the state-diff guard above means 'completed' fires exactly once
          -- per session in practice, so this ON CONFLICT branch should be
          -- unreachable, but the guard costs nothing and documents intent.
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leaderboard_recompute_on_completion ON public.sessions;
CREATE TRIGGER leaderboard_recompute_on_completion
  AFTER UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.leaderboard_recompute_on_session_completion();

-- ============================================================
-- ── 5. Duration-edit lock: is_edited flips, time_seconds NEVER updates ─────
-- ============================================================
-- ── THE DURATION-EDIT HOOK FINDING (cite everything) ────────────────────────
-- SessionRepository.editDuration (GymSyncApp/GymSync/Models/
-- SessionRepository.swift:414-522) is the ONLY write path that ever touches
-- sessions.started_at/completed_at after creation (grepped the whole app +
-- every migration for both column names — no other UPDATE site exists). It
-- always performs the SAME two writes in the SAME order every single call:
--   1. INSERT into session_duration_edits (the audit row) — swift:507-510.
--   2. UPDATE sessions SET started_at=..., completed_at=...,
--      duration_was_edited=true, edited_by=... — swift:513-522.
-- Hooking on session_duration_edits' own AFTER INSERT (rather than on
-- `sessions AFTER UPDATE OF completed_at`) is deliberate: the FIRST-EVER
-- completion of a session (SessionRepository.complete(), and idle_rpcs.sql's
-- wrap-up path) ALSO writes sessions.completed_at as part of the very same
-- statement that sets state='completed'. A trigger keyed on `UPDATE OF
-- completed_at` would fire on that initial completion too and falsely stamp
-- every brand-new leaderboard entry as "edited" before a human ever touched
-- it. session_duration_edits has exactly one INSERT call site in the whole
-- app (editDuration) and it fires ONLY for a genuine post-hoc correction of
-- an already-completed session (the pencil-icon flow, Flow 6:831-836) — the
-- honest, unambiguous hook for "a duration was edited."
--
-- time_seconds is never referenced anywhere in this function — the lock is
-- structural (the column simply isn't in the UPDATE's SET list), not a
-- guard that could be bypassed by a future edit to this function.

CREATE OR REPLACE FUNCTION public.leaderboard_lock_on_duration_edit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE public.leaderboard_entries le
    SET is_edited = true
    FROM public.workout_attempts wa
    WHERE wa.id = le.attempt_id AND wa.session_id = NEW.session_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS leaderboard_lock_on_duration_edit ON public.session_duration_edits;
CREATE TRIGGER leaderboard_lock_on_duration_edit
  AFTER INSERT ON public.session_duration_edits
  FOR EACH ROW EXECUTE FUNCTION public.leaderboard_lock_on_duration_edit();

-- ============================================================
-- ── 6. Volume/top_sets refresh on set_log edits (Flow 6: "update normally") ─
-- ============================================================
-- Flow 6 (:836): "Other metrics (volume, top sets) update normally since
-- they derive from set logs" — scoped, per the brief, to UPDATE/DELETE only
-- (a set_log INSERT during an in-progress attempt is already captured
-- whole by the completion-time recompute above; the only remaining gap is
-- correcting/removing an already-logged set on an attempt whose
-- leaderboard_entries row already exists). Bounded via two early-outs so
-- the overwhelming majority of set_log writes app-wide (which belong to
-- sessions with no public-workout attempt at all) do the cheapest possible
-- check and return.

CREATE OR REPLACE FUNCTION public.leaderboard_refresh_on_set_log_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_session_id uuid := COALESCE(NEW.session_id, OLD.session_id);
  v_user_id    uuid := COALESCE(NEW.user_id, OLD.user_id);
  v_attempt_id uuid;
  v_metrics    RECORD;
BEGIN
  SELECT id INTO v_attempt_id
    FROM public.workout_attempts
    WHERE session_id = v_session_id AND user_id = v_user_id;

  IF NOT FOUND THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Only refresh an entry that already exists (created by the completion
  -- recompute above). An attempt still in progress has no leaderboard_entries
  -- row yet — nothing to refresh, and it will get its first, full
  -- computation (time_seconds included) when its session completes.
  IF NOT EXISTS (SELECT 1 FROM public.leaderboard_entries WHERE attempt_id = v_attempt_id) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  SELECT * INTO v_metrics
    FROM public.leaderboard_attempt_volume(v_session_id, v_user_id);

  UPDATE public.leaderboard_entries
    SET total_volume = v_metrics.total_volume,
        top_sets = v_metrics.top_sets,
        computed_at = now()
    WHERE attempt_id = v_attempt_id;
    -- time_seconds and is_edited are deliberately absent from this SET list.

  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS leaderboard_refresh_on_set_log_change ON public.set_logs;
CREATE TRIGGER leaderboard_refresh_on_set_log_change
  AFTER UPDATE OR DELETE ON public.set_logs
  FOR EACH ROW EXECUTE FUNCTION public.leaderboard_refresh_on_set_log_change();
