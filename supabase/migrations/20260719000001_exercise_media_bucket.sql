-- exercise-media: public bucket, authenticated read.
-- Populated one-time by scripts/import_exercise_media.js (service role);
-- clients never write.
INSERT INTO storage.buckets (id, name, public)
VALUES ('exercise-media', 'exercise-media', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "authenticated users read exercise media files"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'exercise-media');
