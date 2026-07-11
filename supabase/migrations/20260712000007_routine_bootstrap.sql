-- Fix: bootstrap a routine when a unanimous add_exercise lands on a routine-less session.
-- Sessions scheduled without a routine (routine_id IS NULL) now get a private routine
-- created on their behalf the first time an add_exercise proposal is unanimously approved.
CREATE OR REPLACE FUNCTION public.resolve_proposal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_proposal   public.routine_proposals%ROWTYPE;
  v_participants integer;
  v_approves     integer;
  v_position     integer;
  v_ids          uuid[];
  v_i            integer;
BEGIN
  SELECT * INTO v_proposal FROM public.routine_proposals
    WHERE id = NEW.proposal_id AND status = 'open' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;  -- already resolved
  END IF;

  IF NEW.vote = 'veto' THEN
    UPDATE public.routine_proposals
      SET status = 'vetoed', resolved_at = now() WHERE id = v_proposal.id;
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_participants FROM public.session_participants
    WHERE session_id = v_proposal.session_id;
  SELECT count(*) INTO v_approves FROM public.routine_proposal_votes
    WHERE proposal_id = v_proposal.id AND vote = 'approve';
  IF v_approves < v_participants THEN
    RETURN NEW;
  END IF;

  -- Bootstrap: sessions scheduled without a routine get one on first unanimous add
  IF v_proposal.proposal_type = 'add_exercise' THEN
    PERFORM 1 FROM public.sessions
      WHERE id = v_proposal.session_id AND routine_id IS NULL;
    IF FOUND THEN
      WITH new_routine AS (
        INSERT INTO public.routines (id, owner_id, name, visibility)
        SELECT gen_random_uuid(), s.organizer_id, 'Session Routine', 'private'
        FROM public.sessions s WHERE s.id = v_proposal.session_id
        RETURNING id
      )
      UPDATE public.sessions
        SET routine_id = (SELECT id FROM new_routine)
        WHERE id = v_proposal.session_id;
    END IF;
  END IF;

  -- Unanimous: apply to the session's routine
  IF v_proposal.proposal_type = 'add_exercise' THEN
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
      FROM public.routine_exercises re
      JOIN public.sessions s ON s.routine_id = re.routine_id
      WHERE s.id = v_proposal.session_id;
    INSERT INTO public.routine_exercises
      (id, routine_id, exercise_id, position, target_sets, target_reps,
       target_weight, rest_seconds)
    SELECT gen_random_uuid(), s.routine_id,
           (v_proposal.payload->>'exercise_id')::uuid,
           COALESCE((v_proposal.payload->>'position')::int, v_position),
           (v_proposal.payload->>'target_sets')::int,
           v_proposal.payload->>'target_reps',
           v_proposal.payload->>'target_weight',
           (v_proposal.payload->>'rest_seconds')::int
    FROM public.sessions s WHERE s.id = v_proposal.session_id;
  ELSIF v_proposal.proposal_type = 'remove_exercise' THEN
    DELETE FROM public.routine_exercises
      WHERE id = (v_proposal.payload->>'routine_exercise_id')::uuid;
  ELSIF v_proposal.proposal_type = 'edit_exercise' THEN
    UPDATE public.routine_exercises re SET
      target_sets  = COALESCE((v_proposal.payload->>'target_sets')::int, re.target_sets),
      target_reps  = COALESCE(v_proposal.payload->>'target_reps', re.target_reps),
      target_weight = COALESCE(v_proposal.payload->>'target_weight', re.target_weight),
      rest_seconds = COALESCE((v_proposal.payload->>'rest_seconds')::int, re.rest_seconds)
    WHERE re.id = (v_proposal.payload->>'routine_exercise_id')::uuid;
  ELSIF v_proposal.proposal_type = 'reorder' THEN
    SELECT array(SELECT jsonb_array_elements_text(
      v_proposal.payload->'ordered_routine_exercise_ids'))::uuid[] INTO v_ids;
    -- two-pass to dodge the UNIQUE(routine_id, position) constraint
    FOR v_i IN 1..COALESCE(array_length(v_ids, 1), 0) LOOP
      UPDATE public.routine_exercises SET position = v_i + 1000 WHERE id = v_ids[v_i];
    END LOOP;
    FOR v_i IN 1..COALESCE(array_length(v_ids, 1), 0) LOOP
      UPDATE public.routine_exercises SET position = v_i WHERE id = v_ids[v_i];
    END LOOP;
  END IF;

  UPDATE public.routine_proposals
    SET status = 'approved', resolved_at = now() WHERE id = v_proposal.id;
  RETURN NEW;
END;
$$;
