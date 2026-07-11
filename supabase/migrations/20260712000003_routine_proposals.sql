CREATE TABLE public.routine_proposals (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id          uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  proposer_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  proposal_type       text NOT NULL CHECK (proposal_type IN
                        ('add_exercise','remove_exercise','edit_exercise','reorder')),
  payload             jsonb NOT NULL,
  affects_exercise_id uuid,
  status              text NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open','approved','vetoed','superseded')),
  resolved_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX routine_proposals_session_idx
  ON public.routine_proposals(session_id, status);

CREATE TABLE public.routine_proposal_votes (
  proposal_id uuid NOT NULL REFERENCES public.routine_proposals(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  vote        text NOT NULL CHECK (vote IN ('approve','veto')),
  voted_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (proposal_id, user_id)
);

ALTER TABLE public.routine_proposals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_proposal_votes  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.proposal_session_id(p_proposal_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT session_id FROM public.routine_proposals WHERE id = p_proposal_id;
$$;

CREATE POLICY "session participants read proposals"
  ON public.routine_proposals FOR SELECT TO authenticated
  USING (public.is_session_participant(routine_proposals.session_id, auth.uid()));

CREATE POLICY "session participants propose as themselves"
  ON public.routine_proposals FOR INSERT TO authenticated
  WITH CHECK (proposer_id = auth.uid()
              AND public.is_session_participant(routine_proposals.session_id, auth.uid()));

CREATE POLICY "session participants read votes"
  ON public.routine_proposal_votes FOR SELECT TO authenticated
  USING (public.is_session_participant(
           public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

CREATE POLICY "session participants vote as themselves"
  ON public.routine_proposal_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_session_participant(
                    public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

-- Serialize conflicting edits + auto-cast the proposer's approve
CREATE OR REPLACE FUNCTION public.on_proposal_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.affects_exercise_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.routine_proposals
    WHERE session_id = NEW.session_id
      AND affects_exercise_id = NEW.affects_exercise_id
      AND status = 'open' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'this exercise has an open proposal';
  END IF;
  INSERT INTO public.routine_proposal_votes (proposal_id, user_id, vote)
  VALUES (NEW.id, NEW.proposer_id, 'approve');
  RETURN NEW;
END;
$$;
-- BEFORE for the conflict check would be cleaner, but the auto-vote needs the
-- row to exist (FK) — use AFTER for the vote and rely on the same-statement
-- visibility of NEW for the conflict check.
CREATE TRIGGER proposal_insert AFTER INSERT ON public.routine_proposals
  FOR EACH ROW EXECUTE FUNCTION public.on_proposal_insert();

-- Vote resolution: veto -> vetoed; approves == participant count -> approved + apply
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
CREATE TRIGGER proposal_vote_cast AFTER INSERT ON public.routine_proposal_votes
  FOR EACH ROW EXECUTE FUNCTION public.resolve_proposal();
