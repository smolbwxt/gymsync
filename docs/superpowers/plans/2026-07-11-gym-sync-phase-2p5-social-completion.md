# Gym Sync — Phase 2.5: Social Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the features deferred from Phase 2 — image chat messages and group avatars (Supabase Storage), live reaction updates, typing indicators, realtime friend-request refresh — plus the two security follow-ups from the Phase 2 final review.

**Architecture:** Two new Storage buckets (`chat-images` private with signed-URL access, `avatars` public) whose RLS policies derive group membership from the object path via the existing `is_group_member`/`is_group_admin` SECURITY DEFINER helpers. Realtime expands to three more streams: reaction INSERTs (RLS-filtered), typing presence, and friendship INSERTs. All fix-forward migrations (Phase 2 migrations are applied and append-only).

**Tech Stack:** Same as Phase 2 — iOS 17+, SwiftUI (PhotosUI for picking), supabase-swift 2.51 (Storage + Realtime), pgTAP via `node scripts/run_pgtap.js`, migrations via `npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`.

**Design spec:** [`docs/superpowers/specs/2026-06-28-gymsync-design.md`](../specs/2026-06-28-gymsync-design.md) §2 (Supabase Storage), §3 Chat (`storage_path`), §5 Realtime (typing channel, chat channel).

## Global Constraints

- **iOS 17.0** minimum; **Swift 5.9+**.
- **RLS on every table AND on storage.objects policies**; every new policy gets positive + negative pgTAP tests. INSERT `WITH CHECK` violations → `throws_ok('42501')`; UPDATE/DELETE negatives → row-count CTE (silent 0 rows).
- **Applied migrations are append-only** — all schema/policy changes are NEW migrations. Next free numbers start at `20260711000001`.
- **Cross-table RLS references** go through existing SECURITY DEFINER helpers (`is_group_member`, `is_group_admin`, `message_group_id`).
- **Storage path conventions (load-bearing for RLS):** chat images `chat-images/{group_id}/{message_id}.jpg`; group avatars `avatars/groups/{group_id}.jpg`.
- **Realtime DELETE events are NOT RLS-filtered by Supabase** — never add a table to the publication expecting DELETE privacy. Live reactions stream INSERTs only; un-reactions by others refresh on next fetch (documented limitation).
- **All Supabase calls through repository/service enums or the two realtime service classes**; errors wrapped via `ErrorMapping.map(error)`; `GymSyncError.unauthorized` when no session; no `print()` (use `AppLogger`); no force-unwraps in production code.
- **No local Xcode.** Swift verification = push → GitHub Actions `build-test` (~6 min). Backend verification local: `node scripts/run_pgtap.js`.
- **Image processing:** JPEG, max dimension 1600 px, compression quality 0.7, EXIF stripped by re-render.
- **Work on branch `feature/phase-2p5-social-completion`**; conventional commits; the repo default branch is now `master` — **always pass `--base master` to `gh pr create`**.
- CI loop (all Swift tasks): commit → `git push` → wait ~20s → `"/c/Program Files/GitHub CLI/gh.exe" run watch $("/c/Program Files/GitHub CLI/gh.exe" run list --workflow ios.yml --branch feature/phase-2p5-social-completion --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status --interval 60`.

## Explicitly deferred (do NOT build)

- Profile (user) avatars — only GROUP avatars in this phase; `profiles.avatar_url` stays unused.
- Avatar selection inside CreateGroupView — avatars are set from GroupView's Members tab after creation.
- Live un-reaction updates from OTHER users (see DELETE-event constraint above).
- Image messages in DMs, captions on images, multi-image sends.
- Push notifications (Phase 10).

## File Structure

```
supabase/migrations/
├── 20260711000001_security_followups.sql        # Task 1
├── 20260711000002_storage_buckets.sql           # Task 2
├── 20260711000003_reactions_publication.sql     # Task 6
└── 20260711000004_friendships_publication.sql   # Task 8
supabase/tests/
├── security_followups_test.sql                  # Task 1
├── storage_policies_test.sql                    # Task 2
├── reactions_publication_test.sql               # Task 6
└── friendships_publication_test.sql             # Task 8
GymSyncApp/GymSync/
├── Services/ImageProcessor.swift                # Task 3
├── Services/StorageService.swift                # Task 3
├── Services/ChatRealtimeService.swift           # Tasks 6, 7 (extend)
├── Services/FriendRealtimeService.swift         # Task 8
├── Models/ChatMessage.swift                     # Task 4 (add sendImage)
├── Models/GymGroup.swift                        # Task 5 (add avatar methods)
├── Features/Social/ChatView.swift               # Tasks 4, 6, 7 (extend)
├── Features/Social/GroupView.swift              # Task 5 (avatar UI)
└── Features/Social/SocialTabView.swift          # Tasks 5, 8 (avatar row, live badge)
GymSyncApp/GymSyncTests/
├── ImageProcessorTests.swift                    # Task 3
├── StorageServiceTests.swift                    # Task 3
└── ChatImageTests.swift                         # Task 4
```

---

### Task 0: Branch setup

- [ ] **Step 1:**

```bash
cd /g/Projects/GymSync
git checkout master && git pull
git checkout -b feature/phase-2p5-social-completion
```

---

### Task 1: Security follow-ups (read-state gate + case-insensitive usernames)

> **REVISED after user decision (2026-07-11):** usernames are CASE-PRESERVING for display ("Smola" stays "Smola") with CASE-INSENSITIVE uniqueness and lookup. The original lowercase CHECK constraint is replaced by a unique functional index on `lower(username)`, and `ProfileRepository.fetchByUsername` switches from `.eq` on lowercased input to an escaped `.ilike` exact match.

**Files:**
- Create: `supabase/migrations/20260711000001_security_followups.sql`
- Modify: `GymSyncApp/GymSync/Models/Profile.swift` (fetchByUsername → ilike)
- Test: `supabase/tests/security_followups_test.sql`; extend `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift`

**Interfaces:**
- Consumes: `chat_read_state` policies (from `20260710000003`), `profiles`.
- Produces: hardened `chat_read_state` UPDATE policy (membership re-checked); unique index `profiles_username_lower_idx ON profiles (lower(username))`; `fetchByUsername` matches any casing (so FriendRepository/GroupRepository add-by-username work against mixed-case handles transitively).

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/security_followups_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a4', 'sfa@t.com'),
  ('00000000-0000-0000-0000-0000000000b4', 'sfb@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a4', 'sf_user_a'),
  ('00000000-0000-0000-0000-0000000000b4', 'sf_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('80000000-0000-0000-0000-000000000001', 'SF Crew',
   '00000000-0000-0000-0000-0000000000a4');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a4', 'admin'),
  ('80000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b4', 'member');
INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
  ('90000000-0000-0000-0000-000000000001',
   '80000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a4', 'text', 'hi');
-- B has a read-state row, then B is removed from the group
INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
  ('80000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000b4',
   '90000000-0000-0000-0000-000000000001');
DELETE FROM group_members
  WHERE group_id='80000000-0000-0000-0000-000000000001'
    AND user_id='00000000-0000-0000-0000-0000000000b4';

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b4';

-- Negative: expelled user cannot update their stale read-state row (0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_read_state SET last_read_message_id = NULL
      WHERE user_id='00000000-0000-0000-0000-0000000000b4' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'expelled member cannot update read state');

-- Positive: current member still can
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a4';
SELECT lives_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('80000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a4',
     '90000000-0000-0000-0000-000000000001')$$,
  'member writes own read state');
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_read_state SET last_read_message_id = NULL
      WHERE user_id='00000000-0000-0000-0000-0000000000a4' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'member updates own read state');

-- Negative: username differing only in case collides (unique lower index, 23505)
SELECT throws_ok(
  $$INSERT INTO profiles (id, username)
    SELECT '00000000-0000-0000-0000-0000000000c4', 'SF_User_A'$$,
  '23505', NULL, 'case-variant username rejected by unique lower index');

SELECT * FROM finish();
ROLLBACK;
```

(Add a third auth.users fixture row with id `...c4` to the setup block so the FK is satisfiable — the insert must fail on the INDEX, not the FK.)

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: `security_followups_test.sql` FAILS — assertion 1 gets 1 row (old policy lets the expelled user update) and assertion 4 gets no error.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260711000001_security_followups.sql`:

```sql
-- Follow-up 1 (Phase 2 final review): read-state writes must require CURRENT membership.
DROP POLICY "user updates own read-state" ON public.chat_read_state;
CREATE POLICY "user updates own read-state"
  ON public.chat_read_state FOR UPDATE TO authenticated
  USING (user_id = auth.uid()
         AND public.is_group_member(chat_read_state.group_id, auth.uid()))
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(chat_read_state.group_id, auth.uid()));

-- Follow-up 2 (REVISED): usernames are case-preserving for display but must be
-- case-insensitively unique, and lookups match any casing.
CREATE UNIQUE INDEX profiles_username_lower_idx
  ON public.profiles (lower(username));
```

Then in `GymSyncApp/GymSync/Models/Profile.swift`, replace `fetchByUsername`'s query line

```swift
                .eq("username", value: username.lowercased())
```

with an escaped case-insensitive exact match (`_` and `%` are ILIKE wildcards):

```swift
                .ilike("username", pattern: username
                    .replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "%", with: "\\%")
                    .replacingOccurrences(of: "_", with: "\\_"))
```

And add to `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift`:

```swift
    func testFetchByUsernameIsCaseInsensitive() async throws {
        try await TestAuth.signInIfConfigured()
        let profile = try await ProfileRepository.fetchByUsername("CI_TEST_USER_2")
        XCTAssertEqual(profile?.username, "ci_test_user_2",
                       "lookup must match any casing but return the stored casing")
    }
```

- [ ] **Step 4: Push + full suite**

```bash
export $(grep -v '^#' .env.local | xargs)
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: ALL TESTS PASSED. (If CREATE UNIQUE INDEX fails, two existing usernames collide case-insensitively — STOP and report the offending rows; known-good as of 2026-07-11: `Smola`, `ci_test_user`, `ci_test_user_2`.)

- [ ] **Step 5: Commit, push, verify CI** (this task now touches Swift)

```bash
git add supabase/migrations/20260711000001_security_followups.sql supabase/tests/security_followups_test.sql GymSyncApp/GymSync/Models/Profile.swift GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift
git commit -m "fix: read-state membership gate + case-insensitive unique usernames"
git push -u origin feature/phase-2p5-social-completion
```
CI loop → `build-test` PASS.

---

### Task 2: Storage buckets + policies + image message kind

**Files:**
- Create: `supabase/migrations/20260711000002_storage_buckets.sql`
- Test: `supabase/tests/storage_policies_test.sql`

**Interfaces:**
- Consumes: `is_group_member`, `is_group_admin` helpers; `chat_messages` policies (`20260710000003` INSERT, `20260710000006` UPDATE).
- Produces: buckets `chat-images` (private) and `avatars` (public). Path conventions Tasks 3-5 rely on: `chat-images/{group_id}/{message_id}.jpg`, `avatars/groups/{group_id}.jpg`. `chat_messages` INSERT policy now allows `kind IN ('text','image')` (image requires `storage_path`); UPDATE policy allows editing/soft-deleting both kinds.

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/storage_policies_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a5', 'sta@t.com'),
  ('00000000-0000-0000-0000-0000000000c5', 'stc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a5', 'st_user_a'),
  ('00000000-0000-0000-0000-0000000000c5', 'st_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('a0000000-0000-0000-0000-000000000001', 'Storage Crew',
   '00000000-0000-0000-0000-0000000000a5');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('a0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a5', 'admin');

-- Buckets exist
SELECT results_eq(
  $$SELECT count(*)::int FROM storage.buckets WHERE id IN ('chat-images','avatars')$$,
  ARRAY[2], 'both buckets exist');
SELECT results_eq(
  $$SELECT public::int FROM storage.buckets WHERE id='avatars'$$,
  ARRAY[1], 'avatars bucket is public');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a5';

-- Positive: member uploads a chat image under their group's folder
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-images', 'a0000000-0000-0000-0000-000000000001/msg1.jpg',
     '00000000-0000-0000-0000-0000000000a5')$$,
  'member uploads chat image to own group folder');

-- Positive: admin uploads the group avatar
SELECT lives_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/a0000000-0000-0000-0000-000000000001.jpg',
     '00000000-0000-0000-0000-0000000000a5')$$,
  'admin uploads group avatar');

-- Positive: member can insert an image chat message (kind now allowed)
SELECT lives_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, storage_path) VALUES
    ('a0000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a5', 'image',
     'a0000000-0000-0000-0000-000000000001/msg1.jpg')$$,
  'member sends image message');

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c5';

-- Negative: outsider cannot upload into that group's chat-images folder (42501)
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('chat-images', 'a0000000-0000-0000-0000-000000000001/hack.jpg',
     '00000000-0000-0000-0000-0000000000c5')$$,
  '42501', NULL, 'outsider cannot upload to group folder');

-- Negative: non-admin cannot overwrite the group avatar (42501)
SELECT throws_ok(
  $$INSERT INTO storage.objects (bucket_id, name, owner) VALUES
    ('avatars', 'groups/a0000000-0000-0000-0000-000000000001.jpg',
     '00000000-0000-0000-0000-0000000000c5')$$,
  '42501', NULL, 'non-admin cannot upload group avatar');

SELECT * FROM finish();
ROLLBACK;
```

(Environment note: if `storage.objects` INSERTs fail on a NOT NULL/trigger unrelated to policy — e.g. a `path_tokens` or `owner_id` requirement in this Storage schema version — adapt the fixture columns minimally and note it; the policy assertions themselves must stay.)

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: fails on assertion 1 (buckets don't exist).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260711000002_storage_buckets.sql`:

```sql
INSERT INTO storage.buckets (id, name, public)
VALUES ('chat-images', 'chat-images', false)
ON CONFLICT (id) DO NOTHING;
INSERT INTO storage.buckets (id, name, public)
VALUES ('avatars', 'avatars', true)
ON CONFLICT (id) DO NOTHING;

-- chat-images: path = {group_id}/{message_id}.jpg — folder derives membership
CREATE POLICY "group members upload chat images"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat-images'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

CREATE POLICY "group members read chat images"
  ON storage.objects FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat-images'
    AND public.is_group_member(((storage.foldername(name))[1])::uuid, auth.uid())
  );

-- avatars: public read (bucket is public); writes restricted.
-- path = groups/{group_id}.jpg — filename derives the admin check
CREATE POLICY "anyone reads avatars"
  ON storage.objects FOR SELECT TO authenticated
  USING (bucket_id = 'avatars');

CREATE POLICY "group admin uploads group avatar"
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

CREATE POLICY "group admin replaces group avatar"
  ON storage.objects FOR UPDATE TO authenticated
  USING (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  )
  WITH CHECK (
    bucket_id = 'avatars'
    AND (storage.foldername(name))[1] = 'groups'
    AND public.is_group_admin(split_part(storage.filename(name), '.', 1)::uuid, auth.uid())
  );

-- chat_messages: clients may now send images (storage_path required for images)
DROP POLICY "members send text as themselves" ON public.chat_messages;
CREATE POLICY "members send text or image as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (
    author_id = auth.uid()
    AND kind IN ('text','image')
    AND (kind <> 'image' OR storage_path IS NOT NULL)
    AND public.is_group_member(chat_messages.group_id, auth.uid())
  );

-- and edit/soft-delete both kinds (20260710000006 pinned kind='text', which
-- would have made image messages un-deletable)
DROP POLICY "author edits own messages" ON public.chat_messages;
CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (author_id = auth.uid()
         AND public.is_group_member(chat_messages.group_id, auth.uid()))
  WITH CHECK (author_id = auth.uid() AND kind IN ('text','image')
              AND public.is_group_member(chat_messages.group_id, auth.uid()));
```

- [ ] **Step 4: Push + full suite**

```bash
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: ALL TESTS PASSED (including the Phase 2 chat tests — the recreated policies must keep them green).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260711000002_storage_buckets.sql supabase/tests/storage_policies_test.sql
git commit -m "feat(db): storage buckets with membership-derived policies + image message kind"
```

---

### Task 3: ImageProcessor + StorageService (iOS)

**Files:**
- Create: `GymSyncApp/GymSync/Services/ImageProcessor.swift`
- Create: `GymSyncApp/GymSync/Services/StorageService.swift`
- Test: `GymSyncApp/GymSyncTests/ImageProcessorTests.swift`, `GymSyncApp/GymSyncTests/StorageServiceTests.swift`

**Interfaces:**
- Consumes: buckets/paths from Task 2; `SupabaseService.shared.client.storage`.
- Produces (Tasks 4-5 depend on these exact signatures):
  - `ImageProcessor.jpegForUpload(from data: Data, maxDimension: CGFloat = 1600, quality: CGFloat = 0.7) -> Data?`
  - `StorageService.uploadChatImage(groupID: UUID, messageID: UUID, jpegData: Data) async throws -> String` (returns the storage path)
  - `StorageService.signedChatImageURL(path: String) async throws -> URL` (1-hour expiry)
  - `StorageService.uploadGroupAvatar(groupID: UUID, jpegData: Data) async throws -> URL` (public URL with cache-busting `?v=` query)

- [ ] **Step 1: Write ImageProcessor**

Create `GymSyncApp/GymSync/Services/ImageProcessor.swift`:

```swift
import UIKit

enum ImageProcessor {
    /// Re-renders to JPEG capped at maxDimension. Re-rendering also strips EXIF (incl. GPS).
    static func jpegForUpload(from data: Data,
                              maxDimension: CGFloat = 1600,
                              quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let largestSide = max(image.size.width, image.size.height)
        let scale = min(1, maxDimension / largestSide)
        let targetSize = CGSize(width: image.size.width * scale,
                                height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: targetSize,
                                               format: .init(for: .init(displayScale: 1)))
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return rendered.jpegData(compressionQuality: quality)
    }
}
```

- [ ] **Step 2: Write StorageService**

Create `GymSyncApp/GymSync/Services/StorageService.swift`:

```swift
import Foundation
import Supabase

enum StorageService {
    static func uploadChatImage(groupID: UUID, messageID: UUID,
                                jpegData: Data) async throws -> String {
        let path = "\(groupID.uuidString.lowercased())/\(messageID.uuidString.lowercased()).jpg"
        do {
            try await SupabaseService.shared.client.storage
                .from("chat-images")
                .upload(path, data: jpegData,
                        options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func signedChatImageURL(path: String) async throws -> URL {
        do {
            return try await SupabaseService.shared.client.storage
                .from("chat-images")
                .createSignedURL(path: path, expiresIn: 3600)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func uploadGroupAvatar(groupID: UUID, jpegData: Data) async throws -> URL {
        let path = "groups/\(groupID.uuidString.lowercased()).jpg"
        do {
            try await SupabaseService.shared.client.storage
                .from("avatars")
                .upload(path, data: jpegData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try SupabaseService.shared.client.storage
                .from("avatars")
                .getPublicURL(path: path)
            // Cache-buster: same path is overwritten on each change
            var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(
                name: "v", value: String(Int(Date().timeIntervalSince1970)))]
            return components?.url ?? publicURL
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
```

(API-drift note: supabase-swift 2.51 Storage — `upload(_:data:options:)`, `createSignedURL(path:expiresIn:)`, `getPublicURL(path:)`. If CI reports different signatures, adapt minimally; the path conventions and return semantics are the fixed contract.)

- [ ] **Step 3: Write the tests**

Create `GymSyncApp/GymSyncTests/ImageProcessorTests.swift`:

```swift
import XCTest
import UIKit
@testable import GymSync

final class ImageProcessorTests: XCTestCase {
    private func makeImageData(width: CGFloat, height: CGFloat) -> Data {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height))
        let img = renderer.image { ctx in
            UIColor.systemGreen.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        return img.pngData()!
    }

    func testDownscalesLargeImageToMaxDimension() throws {
        let data = makeImageData(width: 4000, height: 2000)
        let jpeg = try XCTUnwrap(ImageProcessor.jpegForUpload(from: data))
        let out = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertLessThanOrEqual(max(out.size.width, out.size.height), 1600)
        XCTAssertEqual(out.size.width / out.size.height, 2.0, accuracy: 0.05,
                       "aspect ratio preserved")
    }

    func testSmallImageNotUpscaled() throws {
        let data = makeImageData(width: 300, height: 200)
        let jpeg = try XCTUnwrap(ImageProcessor.jpegForUpload(from: data))
        let out = try XCTUnwrap(UIImage(data: jpeg))
        XCTAssertEqual(out.size.width, 300, accuracy: 2)
    }

    func testGarbageDataReturnsNil() {
        XCTAssertNil(ImageProcessor.jpegForUpload(from: Data([0x00, 0x01, 0x02])))
    }
}
```

Create `GymSyncApp/GymSyncTests/StorageServiceTests.swift`:

```swift
import XCTest
import UIKit
@testable import GymSync

final class StorageServiceTests: XCTestCase {
    func testChatImageUploadAndSignedURLRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Storage Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let jpeg = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.8)!

        let messageID = UUID()
        let path = try await StorageService.uploadChatImage(
            groupID: group.id, messageID: messageID, jpegData: jpeg)
        XCTAssertEqual(path,
            "\(group.id.uuidString.lowercased())/\(messageID.uuidString.lowercased()).jpg")

        let url = try await StorageService.signedChatImageURL(path: path)
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertGreaterThan(data.count, 100, "signed URL serves the uploaded JPEG")

        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Services/ImageProcessor.swift GymSyncApp/GymSync/Services/StorageService.swift GymSyncApp/GymSyncTests/ImageProcessorTests.swift GymSyncApp/GymSyncTests/StorageServiceTests.swift
git commit -m "feat: image processing + storage service (chat images, group avatars)"
git push -u origin feature/phase-2p5-social-completion
```
Then run the CI loop from Global Constraints. Expected: `build-test` PASS.

---

### Task 4: Image chat messages

**Files:**
- Modify: `GymSyncApp/GymSync/Models/ChatMessage.swift` (decode `storage_path`, add `sendImage`)
- Modify: `GymSyncApp/GymSync/Features/Social/ChatView.swift` (PhotosPicker + image bubbles)
- Test: `GymSyncApp/GymSyncTests/ChatImageTests.swift`

**Interfaces:**
- Consumes: `StorageService.uploadChatImage/signedChatImageURL`, `ImageProcessor.jpegForUpload` (Task 3); image `kind` allowance (Task 2).
- Produces: `ChatMessage.storagePath: String?` now decoded; `ChatRepository.sendImage(groupID: UUID, imageData: Data) async throws -> ChatMessage` (compresses, uploads, inserts `kind='image'`).

- [ ] **Step 1: Extend the model + repository**

In `GymSyncApp/GymSync/Models/ChatMessage.swift`:

1. Add to the `ChatMessage` struct after `body`:

```swift
    let storagePath: String?
```

and to `CodingKeys`:

```swift
        case storagePath = "storage_path"
```

2. Add to `ChatRepository`:

```swift
    static func sendImage(groupID: UUID, imageData: Data) async throws -> ChatMessage {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let messageID = UUID()
        let path = try await StorageService.uploadChatImage(
            groupID: groupID, messageID: messageID, jpegData: jpeg)
        do {
            let row: ChatMessage = try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(["id": messageID.uuidString,
                         "group_id": groupID.uuidString,
                         "author_id": me.uuidString,
                         "kind": "image",
                         "storage_path": path])
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw ErrorMapping.map(error)
        }
    }
```

- [ ] **Step 2: Extend ChatView**

In `GymSyncApp/GymSync/Features/Social/ChatView.swift`:

1. Add `import PhotosUI` at the top.
2. Add state:

```swift
    @State private var pickerItem: PhotosPickerItem?
    @State private var imageURLs: [UUID: URL] = [:]
    @State private var isSendingImage = false
```

3. In the input-bar `HStack`, BEFORE the TextField, add:

```swift
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Image(systemName: "photo").font(.title3)
                }
                .disabled(isSendingImage)
```

4. After the input-bar `.padding()`, add the picker handler:

```swift
            .onChange(of: pickerItem) {
                guard let item = pickerItem else { return }
                pickerItem = nil
                Task { await sendImage(item) }
            }
```

5. Add the send + URL-resolution helpers:

```swift
    private func sendImage(_ item: PhotosPickerItem) async {
        isSendingImage = true
        defer { isSendingImage = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                errorText = "That image couldn't be loaded."
                return
            }
            let sent = try await ChatRepository.sendImage(groupID: group.id, imageData: data)
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
            await resolveImageURLs()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func resolveImageURLs() async {
        for message in messages where message.kind == .image {
            guard imageURLs[message.id] == nil,
                  let path = message.storagePath else { continue }
            imageURLs[message.id] = try? await StorageService.signedChatImageURL(path: path)
        }
    }
```

6. In `messageRow`, replace the message-body `Text(...)` line (the one with the deleted-message ternary) with a content switch:

```swift
                messageContent(message)
```

and add alongside `messageRow`:

```swift
    @ViewBuilder
    private func messageContent(_ message: ChatMessage) -> some View {
        if message.deletedAt != nil {
            Text("[deleted message]").italic()
                .padding(10)
                .background(Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        } else if message.kind == .image {
            AsyncImage(url: imageURLs[message.id]) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .failure:
                    Label("Image unavailable", systemImage: "photo.badge.exclamationmark")
                        .font(.footnote).foregroundStyle(.secondary).padding(10)
                default:
                    ProgressView().frame(width: 120, height: 120)
                }
            }
            .frame(maxWidth: 240, maxHeight: 320)
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            Text(message.body ?? "")
                .padding(10)
                .background(message.authorID == appState.currentProfile?.id
                                ? Color.accentColor.opacity(0.25)
                                : Color(.secondarySystemBackground),
                            in: RoundedRectangle(cornerRadius: 14))
        }
    }
```

(Keep the `.contextMenu` reaction modifier attached to `messageContent(message)` where the old Text was, so images can be reacted to as well.)

7. In `load()`, after `messages = page.reversed()`, add `await resolveImageURLs()`. In the realtime `onInsert` closure, after `messages.append(message)`, the existing `Task { await resolveUsernames() }` becomes `Task { await resolveUsernames(); await resolveImageURLs() }`.

- [ ] **Step 3: Write the test**

Create `GymSyncApp/GymSyncTests/ChatImageTests.swift`:

```swift
import XCTest
import UIKit
@testable import GymSync

final class ChatImageTests: XCTestCase {
    func testSendImageInsertsImageMessageWithStoragePath() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Image Chat Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128))
        let png = renderer.image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }.pngData()!

        let sent = try await ChatRepository.sendImage(groupID: group.id, imageData: png)
        XCTAssertEqual(sent.kind, .image)
        XCTAssertNil(sent.body)
        let path = try XCTUnwrap(sent.storagePath)
        XCTAssertTrue(path.hasPrefix(group.id.uuidString.lowercased() + "/"))

        let fetched = try await ChatRepository.messages(groupID: group.id)
        XCTAssertEqual(fetched.first?.id, sent.id)
        XCTAssertEqual(fetched.first?.storagePath, path)

        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Models/ChatMessage.swift GymSyncApp/GymSync/Features/Social/ChatView.swift GymSyncApp/GymSyncTests/ChatImageTests.swift
git commit -m "feat: image chat messages — picker, compressed upload, signed-URL rendering"
git push
```
CI loop → `build-test` PASS.

---

### Task 5: Group avatars

**Files:**
- Modify: `GymSyncApp/GymSync/Models/GymGroup.swift` (add `setAvatar`)
- Modify: `GymSyncApp/GymSync/Features/Social/GroupView.swift` (avatar picker in Members tab)
- Modify: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift` (render avatar in rows)

**Interfaces:**
- Consumes: `StorageService.uploadGroupAvatar`, `ImageProcessor` (Task 3); `avatars` bucket policies (Task 2); `GymGroup.avatarURL` (exists since Phase 2).
- Produces: `GroupRepository.setAvatar(groupID: UUID, imageData: Data) async throws -> URL` (uploads + persists `groups.avatar_url`, returns the new URL).

- [ ] **Step 1: Extend GroupRepository**

Add to `GroupRepository` in `GymSyncApp/GymSync/Models/GymGroup.swift`:

```swift
    static func setAvatar(groupID: UUID, imageData: Data) async throws -> URL {
        guard let jpeg = ImageProcessor.jpegForUpload(from: imageData, maxDimension: 512) else {
            throw GymSyncError.validation("That image couldn't be processed.")
        }
        let url = try await StorageService.uploadGroupAvatar(groupID: groupID, jpegData: jpeg)
        do {
            try await SupabaseService.shared.client
                .from("groups")
                .update(["avatar_url": url.absoluteString])
                .eq("id", value: groupID.uuidString)
                .execute()
            return url
        } catch {
            throw ErrorMapping.map(error)
        }
    }
```

- [ ] **Step 2: Avatar UI in GroupView**

In `GymSyncApp/GymSync/Features/Social/GroupView.swift`:

1. `import PhotosUI` at top; add state:

```swift
    @State private var avatarItem: PhotosPickerItem?
    @State private var avatarURL: URL?
```

2. In `membersList`, add a new FIRST section (above the add-by-username section):

```swift
            Section {
                HStack(spacing: 12) {
                    if let url = avatarURL ?? group.avatarURL {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFill()
                        } placeholder: {
                            InitialsAvatar(name: group.name)
                        }
                        .frame(width: 56, height: 56)
                        .clipShape(Circle())
                    } else {
                        InitialsAvatar(name: group.name)
                    }
                    PhotosPicker(selection: $avatarItem, matching: .images) {
                        Text("Change Group Photo")
                    }
                }
            }
```

3. Add the handler on the `membersList` `List` (alongside its other modifiers):

```swift
        .onChange(of: avatarItem) {
            guard let item = avatarItem else { return }
            avatarItem = nil
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        errorText = "That image couldn't be loaded."
                        return
                    }
                    avatarURL = try await GroupRepository.setAvatar(
                        groupID: group.id, imageData: data)
                    errorText = nil
                } catch let error as GymSyncError {
                    errorText = error.errorDescription
                } catch {
                    errorText = error.localizedDescription
                }
            }
        }
```

(Non-admins will get an RLS error surfaced in `errorText` — acceptable for Phase 2.5; role-aware hiding is polish.)

- [ ] **Step 3: Render avatars in SocialTabView rows**

In `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`, replace `InitialsAvatar(name: group.name)` inside the groups `ForEach` label with:

```swift
                                if let url = group.avatarURL {
                                    AsyncImage(url: url) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        InitialsAvatar(name: group.name)
                                    }
                                    .frame(width: 34, height: 34)
                                    .clipShape(Circle())
                                } else {
                                    InitialsAvatar(name: group.name)
                                }
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Models/GymGroup.swift GymSyncApp/GymSync/Features/Social/GroupView.swift GymSyncApp/GymSync/Features/Social/SocialTabView.swift
git commit -m "feat: group avatars — admin upload, public-URL rendering with initials fallback"
git push
```
CI loop → `build-test` PASS. (UI-only beyond the repository method; repository path is exercised on-device in QA.)

---

### Task 6: Live reaction updates

**Files:**
- Create: `supabase/migrations/20260711000003_reactions_publication.sql`
- Test: `supabase/tests/reactions_publication_test.sql`
- Modify: `GymSyncApp/GymSync/Services/ChatRealtimeService.swift`
- Modify: `GymSyncApp/GymSync/Features/Social/ChatView.swift`

**Interfaces:**
- Consumes: `chat_message_reactions` RLS SELECT policy (WALRUS filters INSERT events to group members).
- Produces: `ChatRealtimeService.subscribeReactions(onInsert: @escaping @MainActor () -> Void)` — must be called AFTER `subscribe(groupID:onInsert:)`; it attaches to the same channel before it subscribes. To keep one channel per chat, the service's API changes to a configure-then-start shape (see Step 3) — ChatView is the only caller and is updated in the same task.

- [ ] **Step 1: Publication migration + pgTAP**

Create `supabase/tests/reactions_publication_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(1);
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND tablename='chat_message_reactions'$$,
  ARRAY[1], 'reactions table is in the realtime publication');
SELECT * FROM finish();
ROLLBACK;
```

Run `node scripts/run_pgtap.js` → this file FAILS (count 0). Then create `supabase/migrations/20260711000003_reactions_publication.sql`:

```sql
-- INSERT events only are consumed by clients. DELETE events are NOT added to
-- client logic: Supabase realtime does not RLS-filter DELETE payloads, so
-- un-reactions refresh on next fetch instead of streaming.
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_message_reactions;
```

Push + full suite green. Commit:

```bash
git add supabase/migrations/20260711000003_reactions_publication.sql supabase/tests/reactions_publication_test.sql
git commit -m "feat(db): reactions in realtime publication (INSERT streaming only)"
```

- [ ] **Step 2: Restructure ChatRealtimeService for multi-stream channels**

Replace the `subscribe`/`unsubscribe` methods in `GymSyncApp/GymSync/Services/ChatRealtimeService.swift` with (decoder property stays as is):

```swift
    func subscribe(groupID: UUID,
                   onInsert: @escaping @MainActor (ChatMessage) -> Void,
                   onReaction: (@MainActor () -> Void)? = nil) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: "group_id=eq.\(groupID.uuidString)"
        )
        // Reactions have no group_id column; RLS (WALRUS) already limits INSERT
        // events to messages the subscriber can read, and the callback only
        // refreshes the currently open chat.
        let reactionInserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_message_reactions"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            for await action in inserts {
                do {
                    let message = try action.decodeRecord(
                        decoder: Self.postgresDecoder) as ChatMessage
                    onInsert(message)
                } catch {
                    AppLogger.chat.error("realtime decode failed: \(error, privacy: .public)")
                }
            }
        }
        if let onReaction {
            reactionTask = Task {
                for await _ in reactionInserts {
                    onReaction()
                }
            }
        }
    }

    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        reactionTask?.cancel()
        reactionTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
```

and add the property next to `streamTask`:

```swift
    private var reactionTask: Task<Void, Never>?
```

- [ ] **Step 3: Wire ChatView**

In `ChatView.load()`, change the subscribe call to:

```swift
            await realtime.subscribe(groupID: group.id, onInsert: { message in
                guard !messages.contains(where: { $0.id == message.id }) else { return }
                messages.append(message)
                Task { await resolveUsernames(); await resolveImageURLs() }
            }, onReaction: {
                Task { await refreshReactions() }
            })
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Services/ChatRealtimeService.swift GymSyncApp/GymSync/Features/Social/ChatView.swift
git commit -m "feat: live reaction updates via realtime INSERT stream"
git push
```
CI loop → `build-test` PASS (existing ChatRealtimeTests covers the message stream; the reaction callback is exercised on-device in QA).

---

### Task 7: Typing indicators

**Files:**
- Modify: `GymSyncApp/GymSync/Services/ChatRealtimeService.swift`
- Modify: `GymSyncApp/GymSync/Features/Social/ChatView.swift`

**Interfaces:**
- Consumes: Realtime Presence on channel `chat:{group_id}:typing` (spec §5 channel scheme).
- Produces:
  - `ChatRealtimeService.subscribeTyping(groupID: UUID, selfUsername: String, onChange: @escaping @MainActor (Set<String>) -> Void) async`
  - `ChatRealtimeService.setTyping(_ typing: Bool) async` (tracks/untracks self on the typing channel; no-op if subscribeTyping wasn't called)
  - `unsubscribe()` also tears down the typing channel.

- [ ] **Step 1: Extend ChatRealtimeService**

Add properties:

```swift
    private var typingChannel: RealtimeChannelV2?
    private var typingTask: Task<Void, Never>?
    private var typingUsername: String?
    private var isTracked = false
```

Add methods:

```swift
    func subscribeTyping(groupID: UUID, selfUsername: String,
                         onChange: @escaping @MainActor (Set<String>) -> Void) async {
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString):typing")
        let presence = channel.presenceChange()
        typingChannel = channel
        typingUsername = selfUsername
        await channel.subscribe()
        typingTask = Task {
            for await _ in presence {
                let states = await channel.presenceState()
                var names: Set<String> = []
                for entry in states {
                    for presenceItem in entry.presences {
                        if let name = presenceItem.state["username"]?.stringValue,
                           name != selfUsername {
                            names.insert(name)
                        }
                    }
                }
                onChange(names)
            }
        }
    }

    func setTyping(_ typing: Bool) async {
        guard let typingChannel, let typingUsername else { return }
        if typing && !isTracked {
            try? await typingChannel.track(["username": .string(typingUsername)])
            isTracked = true
        } else if !typing && isTracked {
            await typingChannel.untrack()
            isTracked = false
        }
    }
```

And extend `unsubscribe()` (before `channel = nil`):

```swift
        typingTask?.cancel()
        typingTask = nil
        if let typingChannel {
            await SupabaseService.shared.client.removeChannel(typingChannel)
        }
        typingChannel = nil
        isTracked = false
```

(API-drift note: 2.51 Presence — `presenceChange()` stream, `presenceState()`, `track(_:)` taking `[String: AnyJSON]`, `untrack()`. If the presence-state iteration shape differs — e.g. `states` is keyed differently or `state` is named `payload` — adapt the extraction; the contract is "set of OTHER users' usernames currently tracking".)

- [ ] **Step 2: Wire ChatView**

Add state:

```swift
    @State private var typingUsers: Set<String> = []
    @State private var typingDebounce: Task<Void, Never>?
```

In `load()` after the realtime subscribe call:

```swift
            if let username = appState.currentProfile?.username {
                await realtime.subscribeTyping(groupID: group.id,
                                               selfUsername: username) { names in
                    typingUsers = names
                }
            }
```

Above the input-bar `HStack` (inside the outer VStack), add the indicator line:

```swift
            if !typingUsers.isEmpty {
                Text("\(typingUsers.sorted().joined(separator: ", ")) typing…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }
```

Add the draft hook (a modifier on the outer VStack, next to `.task`):

```swift
        .onChange(of: draft) {
            typingDebounce?.cancel()
            let isEmpty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            Task { await realtime.setTyping(!isEmpty) }
            guard !isEmpty else { return }
            typingDebounce = Task {
                try? await Task.sleep(for: .seconds(4))
                guard !Task.isCancelled else { return }
                await realtime.setTyping(false)
            }
        }
```

And in `send()`, after `draft = ""`:

```swift
        typingDebounce?.cancel()
        Task { await realtime.setTyping(false) }
```

- [ ] **Step 3: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Services/ChatRealtimeService.swift GymSyncApp/GymSync/Features/Social/ChatView.swift
git commit -m "feat: typing indicators via presence channel with 4s idle debounce"
git push
```
CI loop → `build-test` PASS. (Presence behavior verified on-device in QA — the CI suite has no second live client.)

---

### Task 8: Realtime friend-request refresh

**Files:**
- Create: `supabase/migrations/20260711000004_friendships_publication.sql`
- Test: `supabase/tests/friendships_publication_test.sql`
- Create: `GymSyncApp/GymSync/Services/FriendRealtimeService.swift`
- Modify: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`

**Interfaces:**
- Consumes: `friendships` SELECT RLS (WALRUS filters events to the two parties).
- Produces: `FriendRealtimeService.subscribe(userID: UUID, onFriendshipEvent: @escaping @MainActor () -> Void) async` / `unsubscribe() async` — fires on INSERT (new incoming request) and UPDATE (request accepted) involving me.

- [ ] **Step 1: Publication migration + pgTAP**

Create `supabase/tests/friendships_publication_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(1);
SELECT results_eq(
  $$SELECT count(*)::int FROM pg_publication_tables
    WHERE pubname='supabase_realtime' AND tablename='friendships'$$,
  ARRAY[1], 'friendships table is in the realtime publication');
SELECT * FROM finish();
ROLLBACK;
```

Run suite → FAILS (count 0). Create `supabase/migrations/20260711000004_friendships_publication.sql`:

```sql
ALTER PUBLICATION supabase_realtime ADD TABLE public.friendships;
```

Push + suite green. Commit:

```bash
git add supabase/migrations/20260711000004_friendships_publication.sql supabase/tests/friendships_publication_test.sql
git commit -m "feat(db): friendships in realtime publication"
```

- [ ] **Step 2: Write FriendRealtimeService**

Create `GymSyncApp/GymSync/Services/FriendRealtimeService.swift`:

```swift
import Foundation
import Supabase

@MainActor
final class FriendRealtimeService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    func subscribe(userID: UUID,
                   onFriendshipEvent: @escaping @MainActor () -> Void) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("user:\(userID.uuidString)")
        // Incoming requests target me as friend_id; acceptances of MY outgoing
        // requests arrive as UPDATEs where I'm user_id. RLS already scopes both.
        let incoming = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "friendships",
            filter: "friend_id=eq.\(userID.uuidString)"
        )
        let accepted = channel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "friendships",
            filter: "user_id=eq.\(userID.uuidString)"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in incoming { onFriendshipEvent() }
                }
                group.addTask { @MainActor in
                    for await _ in accepted { onFriendshipEvent() }
                }
            }
        }
    }

    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}
```

- [ ] **Step 3: Wire SocialTabView**

Add state:

```swift
    @State private var friendRealtime = FriendRealtimeService()
```

Extend the `.task { await refresh() }` modifier to also subscribe:

```swift
            .task {
                await refresh()
                if let me = await SupabaseService.shared.currentUserID() {
                    await friendRealtime.subscribe(userID: me) {
                        Task { await refresh() }
                    }
                }
            }
            .onDisappear { Task { await friendRealtime.unsubscribe() } }
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Services/FriendRealtimeService.swift GymSyncApp/GymSync/Features/Social/SocialTabView.swift
git commit -m "feat: live friend-request badge via friendships realtime stream"
git push
```
CI loop → `build-test` PASS.

---

### Task 9: Ship — PR, merge, TestFlight QA

- [ ] **Step 1:** `node scripts/run_pgtap.js` → ALL TESTS PASSED.

- [ ] **Step 2: Open the PR — NOTE `--base master` is mandatory:**

```bash
"/c/Program Files/GitHub CLI/gh.exe" pr create --base master --title "Phase 2.5: Social completion — images, avatars, live reactions, typing, live friends" --body "## Summary
- Storage buckets (chat-images private + signed URLs, avatars public) with membership-derived RLS
- Image chat messages (PhotosPicker, 1600px/0.7 JPEG, EXIF stripped)
- Group avatars (admin upload, cache-busted public URLs)
- Live reaction updates (INSERT stream; un-reactions refresh on fetch — DELETE events aren't RLS-filtered)
- Typing indicators (presence, 4s idle debounce)
- Live friend-request/acceptance refresh
- Security follow-ups: read-state membership gate, lowercase-username DB constraint

## Test plan
- [ ] pgTAP all green
- [ ] iOS CI green
- [ ] Device QA below

🤖 Generated with [Claude Code](https://claude.com/claude-code)
"
```

- [ ] **Step 3:** Merge after CI green (auto-deploys TestFlight).

- [ ] **Step 4: Device QA** (controller drives `ci_test_user_2` via `scripts/qa_live_user2.js`):
1. Send a photo in chat → renders on both sides; reload app → image still renders (signed URL re-resolved)
2. ci_test_user_2 reacts to your message → count appears live on your phone
3. Set a group photo → appears in Social list and Members tab; non-admin attempt surfaces error
4. Typing: ci_test_user_2 tracks presence → "… typing" appears and clears after ~4s idle
5. ci_test_user_2 sends you a friend request → badge appears on Social tab WITHOUT reopening
6. Regression: text chat realtime, unread dots, PR system message, solo logging

---

## Self-Review Notes (already applied)

- **Policy interplay:** Task 2 re-creates BOTH chat_messages write policies — the Phase 2 hardening (`_006`) pinned `kind='text'` on UPDATE, which would have made image messages un-soft-deletable; the new policies allow `('text','image')` while keeping the membership + author gates. Phase 2 pgTAP chat tests must stay green (they only assert text + system behavior, which is preserved).
- **Realtime privacy:** reactions stream INSERT-only (DELETE events bypass RLS — documented in migration comment and Global Constraints); friendships events are WALRUS-filtered to the two parties; typing presence exposes only usernames to channel subscribers (group members by convention — channel names are unguessable UUIDs, acceptable for Phase 2.5, revisit with private channels later).
- **Type consistency:** `subscribe(groupID:onInsert:onReaction:)` keeps a default `onReaction: nil` so Task 9's existing `ChatRealtimeTests` (which calls the two-argument form) still compiles unchanged.
- **Storage pgTAP caveat:** storage.objects internals vary by Supabase version — the test includes an adaptation note; policy assertions are the fixed part.
- **QA reality:** presence and live-reaction flows have no CI coverage (single test client); they're explicitly in the device QA list with the controller driving the second account.
