-- ============================================================
-- Phase C Task 3 fix-forward (fix wave 1, controller-ruled): gate the
-- completion chat message on the campaign NOT being a draft.
-- ============================================================
-- ── The incident this closes (live, observed, not hypothetical) ─────────
-- Task 3's live proof completed a fixture session against the seeded
-- draft "QA Test Campaign" (is_draft = true) for the CI account
-- (ci_test_user_2), which crossed the campaign's individual_target and —
-- per 20260728000002's fan-out ("every group the achiever belongs to") —
-- posted the system_campaign completion message into a REAL, shared
-- group ("Men for Christ") the CI account happens to belong to, in front
-- of a real user. The polluting row was identified and deleted live
-- (task-3-report.md, Fix wave 1 section, before/after transcript); this
-- migration prevents recurrence.
--
-- ── Why the gate is right (not just convenient) ─────────────────────────
-- A draft campaign is test/pre-launch content by definition (Task 1's
-- Adjudication 3, 20260728000001_campaigns_schema.sql:91-111): its RLS
-- makes it invisible to everyone except its own participants. Fanning a
-- draft campaign's completion into group chats whose members cannot even
-- SEE the campaign is therefore incoherent on its own terms — the
-- message references an entity its audience is structurally unable to
-- resolve — in addition to being the pollution vector observed live.
-- Progress ACCRUAL for drafts is deliberately left untouched: 20260728
-- 000002's own header (":88-93") explains that accrual must work for
-- drafts because the seeded test campaign's live progress proof IS Phase
-- C's acceptance bar; only the outward-facing chat side effect is gated.
--
-- ── Fix-forward doctrine (handoff §3.2) ─────────────────────────────────
-- Applied migrations are append-only; 20260728000002 is immutable. The
-- trigger function body below is transplanted VERBATIM from 20260728
-- 000002_campaign_progress_trigger.sql:191-342 with exactly two deltas,
-- both marked with "-- [000005]" comments inline:
--   1. `c.is_draft` added to the FOR-loop SELECT list.
--   2. `AND NOT rec.is_draft` added to the completion-crossing IF.
-- Everything else — the state-diff guard, early-outs, the Finding-1(a)
-- row lock, the volume formula, the counter math, the fan-out INSERT —
-- is byte-for-byte the shipped logic; re-read 000002's own header for
-- the reasoning behind each of those (not re-litigated here).
--
-- ── Grants: none needed ─────────────────────────────────────────────────
-- Verified 20260728000002 issued NO GRANT/REVOKE on this function
-- (grep: zero matches — trigger functions are not client-callable
-- surfaces; PostgREST RPC exposure is irrelevant to a RETURNS trigger
-- function, and the 0A000 "trigger functions can only be called as
-- triggers" guard covers direct calls). CREATE OR REPLACE preserves
-- existing grants (handoff §3.2: "CREATE OR REPLACE does NOT reset
-- grants; DROP+CREATE and signature changes DO") — same name, same
-- (empty) argument list, same return type, so this is a pure body swap:
-- grants unchanged, and the existing `campaign_progress_on_completion`
-- trigger on public.sessions keeps pointing at this same function OID —
-- no DROP/CREATE TRIGGER needed or issued.
-- ============================================================

CREATE OR REPLACE FUNCTION public.campaign_progress_on_session_completion()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  rec              RECORD;
  v_session_volume numeric(12,2);
  v_old_sessions   integer;
  v_old_workouts   integer;
  v_old_volume     numeric(12,2);
  v_new_sessions   integer;
  v_new_workouts   integer;
  v_new_volume     numeric(12,2);
  v_target_n       integer;
  v_old_count      integer;
  v_new_count      integer;
  v_unit_label     text;
  v_username       text;
BEGIN
  -- Same OLD/NEW state-diff guard shape as streak_on_session_state_change
  -- and leaderboard_recompute_on_session_completion: a same-value refire,
  -- or any transition that isn't INTO 'completed' (including 'abandoned'
  -- -- Flow 8 names no abandoned-session behavior at all), is a no-op.
  IF NEW.state IS NOT DISTINCT FROM OLD.state OR NEW.state <> 'completed' THEN
    RETURN NEW;
  END IF;

  -- Cheap early-out: a session with no routine can never match any
  -- campaign's curated_routine_ids.
  IF NEW.routine_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Cheap early-out: skip the participant lock entirely unless at least
  -- one campaign's window+routine could possibly match this session.
  -- Campaigns table is small by product design ("1-2 active seasonal
  -- campaigns at a time", spec :1375), so this is a trivial scan.
  IF NOT EXISTS (
    SELECT 1 FROM public.campaigns c
    WHERE NEW.routine_id = ANY(c.curated_routine_ids)
      AND NEW.completed_at BETWEEN c.starts_at AND c.ends_at
  ) THEN
    RETURN NEW;
  END IF;

  -- Race guard reused from streak_trigger_race_fixes.sql Finding 1(a):
  -- lock this session's session_participants rows before evaluating
  -- readiness, serializing against a concurrent mark_no_shows() tick.
  PERFORM 1 FROM public.session_participants
    WHERE session_id = NEW.id
    FOR UPDATE;

  FOR rec IN
    SELECT c.id AS campaign_id, c.name AS campaign_name, c.individual_target,
           c.is_draft,  -- [000005] read the draft flag for the message gate below
           sp.user_id
    FROM public.campaigns c
    JOIN public.campaign_participants cpart ON cpart.campaign_id = c.id
    JOIN public.session_participants sp
      ON sp.session_id = NEW.id
     AND sp.user_id = cpart.user_id
     AND sp.check_in_state = 'ready'
    WHERE NEW.routine_id = ANY(c.curated_routine_ids)
      AND NEW.completed_at BETWEEN c.starts_at AND c.ends_at
  LOOP
    -- This session's volume contribution, same exclusions as
    -- increment_lifetime_volume/leaderboard_attempt_volume/group_stats:
    -- reps * weight, excluding is_penalty and is_failed rows.
    SELECT COALESCE(SUM(sl.reps * sl.weight), 0)
      INTO v_session_volume
      FROM public.set_logs sl
      WHERE sl.session_id = NEW.id AND sl.user_id = rec.user_id
        AND sl.is_failed = false AND sl.is_penalty = false
        AND sl.reps IS NOT NULL AND sl.weight IS NOT NULL;

    -- streak_bump_user idiom: INSERT...ON CONFLICT DO NOTHING to
    -- guarantee the row exists, then SELECT...FOR UPDATE to lock it and
    -- read the pre-write counts (needed for the completion-crossing check
    -- below), then a plain UPDATE with the computed new values. This
    -- avoids the INSERT-vs-UPDATE trigger-fan-out gap a naive
    -- `INSERT ... ON CONFLICT DO UPDATE` would have if the completion
    -- check instead lived in a separate `AFTER UPDATE ON campaign_progress`
    -- trigger (a brand-new participant's first-ever qualifying session
    -- would take the INSERT path and never fire such a trigger at all).
    INSERT INTO public.campaign_progress (campaign_id, user_id)
      VALUES (rec.campaign_id, rec.user_id)
      ON CONFLICT (campaign_id, user_id) DO NOTHING;

    SELECT sessions_completed, workouts_completed, volume_lifted
      INTO v_old_sessions, v_old_workouts, v_old_volume
      FROM public.campaign_progress
      WHERE campaign_id = rec.campaign_id AND user_id = rec.user_id
      FOR UPDATE;

    v_new_sessions := v_old_sessions + 1;
    v_new_workouts := v_old_workouts + 1;
    v_new_volume   := v_old_volume + v_session_volume;

    UPDATE public.campaign_progress
      SET sessions_completed = v_new_sessions,
          workouts_completed = v_new_workouts,
          volume_lifted      = v_new_volume,
          updated_at         = now()
      WHERE campaign_id = rec.campaign_id AND user_id = rec.user_id;

    -- ── Completion check: individual_target crossing, fires once ──────
    -- Picks whichever key the campaign's individual_target actually uses
    -- (spec :592, "{"sessions":12} or {"workouts_completed":4}") -- NULL
    -- individual_target or an unrecognized key is a silent no-op (no
    -- completion message), not an error.
    v_target_n := NULL;
    IF rec.individual_target ? 'sessions' THEN
      v_target_n  := (rec.individual_target->>'sessions')::integer;
      v_old_count := v_old_sessions;
      v_new_count := v_new_sessions;
      v_unit_label := 'sessions';
    ELSIF rec.individual_target ? 'workouts_completed' THEN
      v_target_n  := (rec.individual_target->>'workouts_completed')::integer;
      v_old_count := v_old_workouts;
      v_new_count := v_new_workouts;
      v_unit_label := 'workouts';
    END IF;

    -- Crossing, not "landing exactly": both counters move by exactly +1
    -- per qualifying session (never re-set, never decremented -- there is
    -- no break/undo concept for campaigns), so old < target <= new can
    -- only ever be true on the ONE session that first reaches the target,
    -- same "fires exactly once" argument push_streak_milestone_user/group
    -- make for their own ANY-membership check
    -- (20260719000008_streak_pushes.sql:118-126).
    --
    -- [000005] `NOT rec.is_draft` gates the MESSAGE only, never the
    -- accrual above: a draft campaign's completion is a private,
    -- test/pre-launch event — its audience (group members who cannot even
    -- SEE the campaign under the draft SELECT policy) must not receive a
    -- chat message about it. See this migration's header for the live
    -- incident that proved this out.
    IF v_target_n IS NOT NULL AND NOT rec.is_draft
       AND v_old_count < v_target_n AND v_new_count >= v_target_n THEN
      SELECT username INTO v_username FROM public.profiles WHERE id = rec.user_id;

      -- Fan out to every group the achiever belongs to -- same shape as
      -- announce_pr() (20260710000007_pr_body_format.sql:24-31) and
      -- push_streak_milestone_group's chat insert
      -- (20260719000008_streak_pushes.sql:161-164): author_id NULL =
      -- system, payload carries structured facts, body carries the
      -- human-readable copy. A groupless user (zero group_members rows)
      -- silently produces zero message rows, same as announce_pr's own
      -- documented behavior for a groupless lifter -- not a new gap.
      INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
      SELECT gm.group_id, NULL, 'system_campaign',
             '🌊 ' || v_username || ' just completed ' || rec.campaign_name
                  || ' — ' || v_new_count || '/' || v_target_n || ' ' || v_unit_label || '!',
             jsonb_build_object('user_id', rec.user_id, 'campaign_id', rec.campaign_id,
                                'target', v_target_n, 'value', v_new_count)
      FROM public.group_members gm
      WHERE gm.user_id = rec.user_id;
    END IF;
  END LOOP;

  RETURN NEW;
END;
$$;
