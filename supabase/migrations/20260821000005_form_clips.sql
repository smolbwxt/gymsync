-- 20260821000005_form_clips.sql
--
-- Form video v1 (owner rulings 2026-08-21): async clips attached to
-- logged sets for trainer form review. Storage is GATED - the client
-- only persists for PRO or coach-linked athletes; everyone else gets
-- an immediate local review with NO retention (the client never
-- uploads). Live broadcast during group sets is phase 2; coach-paid
-- storage extensions are the billing pass.
INSERT INTO storage.buckets (id, name, public)
VALUES ('form-clips', 'form-clips', false)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE public.set_log_clips (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  set_log_id       uuid NOT NULL REFERENCES public.set_logs(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  storage_path     text NOT NULL,
  duration_seconds numeric,
  created_at       timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX set_log_clips_set_idx  ON public.set_log_clips (set_log_id);
CREATE INDEX set_log_clips_user_idx ON public.set_log_clips (user_id);

ALTER TABLE public.set_log_clips ENABLE ROW LEVEL SECURITY;

-- The athlete owns their clips outright.
CREATE POLICY "owner manages own clips"
  ON public.set_log_clips FOR ALL TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- The ACTIVE trainer watches form - same relationship row that gates
-- every other client surface (trainer_clients, 20260814000005).
CREATE POLICY "active trainer views client clips"
  ON public.set_log_clips FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.trainer_clients tc
    WHERE tc.trainer_id = auth.uid()
      AND tc.client_id = set_log_clips.user_id
      AND tc.status = 'active'
  ));

-- Bucket path = {user_id}/{clip_id}.mov - the folder derives ownership,
-- the same shape as chat-images.
CREATE POLICY "owner uploads own form clips"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'form-clips'
    AND ((storage.foldername(name))[1])::uuid = auth.uid()
  );

CREATE POLICY "owner reads own form clips"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'form-clips'
    AND ((storage.foldername(name))[1])::uuid = auth.uid()
  );

CREATE POLICY "owner deletes own form clips"
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'form-clips'
    AND ((storage.foldername(name))[1])::uuid = auth.uid()
  );

CREATE POLICY "active trainer reads client form clips"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'form-clips'
    AND EXISTS (
      SELECT 1 FROM public.trainer_clients tc
      WHERE tc.trainer_id = auth.uid()
        AND tc.client_id = ((storage.foldername(name))[1])::uuid
        AND tc.status = 'active'
    )
  );
