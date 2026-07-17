-- Phase F Task 6: user avatars.
--
-- 20260711000002_storage_buckets.sql already made the `avatars` bucket
-- public-read and gave GROUP admins a write path at `groups/{group_id}.jpg`
-- (folder derives the entity, filename-sans-extension is the entity id,
-- `is_group_admin` gates the write). No policy exists yet for a user's OWN
-- avatar — a client upload to any path today falls through to "no matching
-- policy" and RLS-denies the INSERT.
--
-- Per-entity convention mirrored, self-owned instead of admin-owned:
-- path = users/{user_id}.jpg — folder derives "this is a user avatar",
-- filename-sans-extension must equal the uploader's own auth.uid() (no
-- separate ownership-lookup function needed, unlike groups' admin check,
-- since the "entity" and the "owner" are the same id here).
--
-- SELECT is already covered by 20260711000002's "anyone reads avatars"
-- policy (bucket_id = 'avatars', no folder restriction) — no new SELECT
-- policy needed.

CREATE POLICY "users upload own avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'users'
    AND split_part(storage.filename(name), '.', 1)::uuid = auth.uid()
  );

CREATE POLICY "users replace own avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'users'
    AND split_part(storage.filename(name), '.', 1)::uuid = auth.uid()
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'users'
    AND split_part(storage.filename(name), '.', 1)::uuid = auth.uid()
  );
