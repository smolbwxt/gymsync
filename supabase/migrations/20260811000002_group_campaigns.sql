-- Group campaigns (minimal real, owner decision 2026-08-11): a named
-- multi-week push the crew adopts — the crew room's campaign meter tracks
-- WK n OF m from started_on + weeks. Trainer-lite campaign content layers
-- on later; this table is deliberately just the meter's spine.

CREATE TABLE public.group_campaigns (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id   uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  name       text NOT NULL CHECK (char_length(name) BETWEEN 1 AND 60),
  weeks      int  NOT NULL CHECK (weeks BETWEEN 1 AND 52),
  started_on date NOT NULL DEFAULT current_date,
  created_by uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX group_campaigns_group_idx ON public.group_campaigns (group_id, started_on DESC);

ALTER TABLE public.group_campaigns ENABLE ROW LEVEL SECURITY;

CREATE POLICY "group members read campaigns"
  ON public.group_campaigns FOR SELECT
  TO authenticated
  USING (private.is_group_member(group_id, auth.uid()));

CREATE POLICY "group members start campaigns"
  ON public.group_campaigns FOR INSERT
  TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND private.is_group_member(group_id, auth.uid())
  );

-- Ending a campaign early: its creator or a group admin.
CREATE POLICY "creator or admin ends campaigns"
  ON public.group_campaigns FOR DELETE
  TO authenticated
  USING (
    created_by = auth.uid()
    OR private.is_group_admin(group_id, auth.uid())
  );
