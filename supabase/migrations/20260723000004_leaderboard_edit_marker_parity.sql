-- ============================================================
-- Whole-branch review, trust-surface asymmetry: leaderboard_refresh_on_
-- set_log_change silently omits is_edited
-- ============================================================
-- Finding, verbatim: leaderboard_refresh_on_set_log_change (20260723000001_
-- public_workout_repository.sql:367-403) recomputes an entry's total_volume/
-- top_sets when set_logs change post-completion, but deliberately omits
-- is_edited from its UPDATE's SET list — see that migration's own comment at
-- :399, "time_seconds and is_edited are deliberately absent from this SET
-- list". So a retroactively-inflated volume entry shows NO "edited" marker,
-- while the duration-edit path (leaderboard_lock_on_duration_edit, same
-- migration :338-347) both locks time_seconds AND marks is_edited = true on
-- the very same leaderboard_entries row. Two post-completion mutation paths
-- on the same table, one honest about having mutated the row, one silent.
--
-- Review recommendation: the refresh trigger only ever fires when a
-- leaderboard_entries row already exists — its own early-out (:387-389 of
-- that migration, "Only refresh an entry that already exists") guarantees
-- this — and that row is created exclusively by
-- leaderboard_recompute_on_session_completion (:245-303 of that migration).
-- By construction, therefore, every UPDATE/DELETE this trigger ever reaches
-- is a POST-completion mutation of an already-finalized entry — exactly the
-- class of retroactive edit is_edited exists to flag. There is no code path
-- where this trigger fires on a still-in-progress attempt (no entry row
-- would exist yet to refresh).
--
-- Fix (fix-forward, append-only — 20260723000001 is applied live): CREATE OR
-- REPLACE the function with ONE change — the entry UPDATE also sets
-- is_edited = true. Guard clauses, metrics computation, and the trigger
-- itself (name/signature unchanged, so no DROP/CREATE TRIGGER needed) are
-- otherwise untouched. time_seconds remains structurally locked — still not
-- in the SET list; only is_edited joins total_volume/top_sets/computed_at.
-- ============================================================

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

  -- is_edited = true (fix-forward, this migration): this trigger only ever
  -- reaches an entry that already exists, and entries only ever come to
  -- exist via the completion recompute — so every UPDATE this function
  -- performs is, by construction, a retroactive edit of an already-finalized
  -- entry. Same class of mutation leaderboard_lock_on_duration_edit already
  -- marks; this closes the asymmetry where a set_log-driven volume change
  -- went unmarked.
  UPDATE public.leaderboard_entries
    SET total_volume = v_metrics.total_volume,
        top_sets = v_metrics.top_sets,
        is_edited = true,
        computed_at = now()
    WHERE attempt_id = v_attempt_id;
    -- time_seconds is still deliberately absent from this SET list — the
    -- structural lock is unchanged as of this migration.

  RETURN COALESCE(NEW, OLD);
END;
$$;
