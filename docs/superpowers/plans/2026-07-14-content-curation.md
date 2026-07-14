# Content Curation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personalized soundboard (4 favorites in the live dock + full library sheet) and a curator-published "Featured" routine shelf in the Library tab — the UI layer over curation scripts that already exist (`scripts/add_sound.js`, `scripts/seed_routines.js`).

**Architecture:** One migration adds catalog metadata (emoji icon + category), a dedicated `soundboard_favorites` table (deliberately NOT a `user_settings` column — that table's full-row upsert pattern caused the Canvas-Completion B1 clobber; favorites isolate into their own single-purpose row), a `profiles.is_curator` flag with column-level write revocation, and server-enforced curator-only publishing on `routines`. The app gets three small data surfaces (catalog, favorites, public-routines/clone) and two UI deliverables per the designer's blessed frames.

**Tech Stack:** Supabase (Postgres RLS + column privileges, PostgREST), SwiftUI/GSTheme, pgTAP via `node scripts/run_pgtap.js`.

## Global Constraints

- **Design authority:** `docs/design/sections/2026-07-curation.dc.html` — the markup IS the spec. Frame 1 = favorites ribbon in the live dock; frame 2 = sound library sheet; frame 3 = Library Featured. Copy verbatim from frames: "YOUR SOUNDS", "Edit", "All", "Sounds", "Tap to send · star to favorite", "Your 4 favorites · drag to reorder", "All sounds", segments "Hype/Funny/FX", "Featured · curated packs", "SEASONAL", "Add to my routines", "Your routines".
- **Do NOT touch `user_settings`** (table or `UserSettingsRepository`) — favorites live in their own table.
- Migrations append-only; next free timestamp is `20260717000003`; apply ONLY via `export $(grep -v '^#' .env.local | xargs) && npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`.
- pgTAP tests fixture-scoped (never global counts); runner `node scripts/run_pgtap.js`.
- Curator-only publish is enforced SERVER-side (RLS WITH CHECK), not just hidden UI. `is_curator` is not client-writable (column-level REVOKE).
- Audio sacred rules: soundboard playback stays on `SoundboardPlayer` (never touches AVAudioSession category); the dock's voice controls (PTTDockRow) are untouched by this phase.
- Swift idiom: GSTheme tokens, GSFont, existing repository `enum` pattern (`static func`, `ErrorMapping.map`), canvas button doctrine.
- iOS verification = GitHub Actions build-test (no local Mac). Backend verification = pgTAP runner.
- Never `git add -A`; stage explicit paths.

## File Structure

| File | Responsibility |
|---|---|
| `supabase/migrations/20260717000003_curation.sql` | Catalog columns + backfill, favorites table + RLS, is_curator + REVOKE, routines publish policies |
| `supabase/tests/curation_test.sql` | pgTAP: publish gate, favorites RLS, catalog columns |
| `scripts/add_sound.js` (modify) | `--icon`/`--category` args + real WAV duration |
| `GymSyncApp/GymSync/Models/Soundboard.swift` (new) | `SoundboardSound` model + `SoundboardRepository` (catalog) + `SoundboardFavoritesRepository` |
| `GymSyncApp/GymSync/Models/Profile.swift` (modify) | `isCurator` decode |
| `GymSyncApp/GymSync/Models/Routine.swift` (modify) | `visibility` on save, `publicRoutines()`, `clone(id:)` |
| `GymSyncApp/GymSync/Features/Sessions/SoundLibrarySheet.swift` (new) | Frame-2 sheet: favorites reorder/star + categorized catalog + tap-to-send |
| `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` (modify) | Dock ribbon reads favorites; Edit/All open the sheet |
| `GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift` (modify) | Curator-only publish toggle |
| `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift` (modify) | Featured shelf per frame 3 |
| `GymSyncApp/GymSyncTests/CurationRepositoryTests.swift` (new) | Live-DB tests: catalog decode, favorites round-trip, non-curator publish rejection, clone |

---

### Task 1: Migration + pgTAP + add_sound.js metadata

**Files:**
- Create: `supabase/migrations/20260717000003_curation.sql`
- Create: `supabase/tests/curation_test.sql`
- Modify: `scripts/add_sound.js`

**Interfaces:**
- Produces (later tasks rely on): `soundboard_sounds.icon text`, `soundboard_sounds.category text` ('hype'|'funny'|'fx'|NULL); table `soundboard_favorites(user_id uuid PK, slugs text[] NOT NULL DEFAULT '{}', updated_at timestamptz)`; `profiles.is_curator boolean NOT NULL DEFAULT false`; routines INSERT/UPDATE policies gate `visibility='public'` on caller's `is_curator`.

- [ ] **Step 1: Write the migration**

```sql
-- 20260717000003_curation.sql
-- Curation phase: catalog metadata, per-user soundboard favorites,
-- curator-gated routine publishing.

-- ── 1. Catalog metadata (designer frames use emoji icons + 3 categories) ──
ALTER TABLE public.soundboard_sounds
  ADD COLUMN icon text,
  ADD COLUMN category text CHECK (category IN ('hype','funny','fx'));

UPDATE public.soundboard_sounds SET icon = '📯', category = 'hype'  WHERE slug = 'airhorn';
UPDATE public.soundboard_sounds SET icon = '🔥', category = 'hype'  WHERE slug = 'lets-go';
UPDATE public.soundboard_sounds SET icon = '🔔', category = 'fx'    WHERE slug = 'ding';
UPDATE public.soundboard_sounds SET icon = '📣', category = 'funny' WHERE slug = 'boo';

-- ── 2. Per-user favorites — DELIBERATELY its own table, not a user_settings
--       column: user_settings is written via full-row upserts from multiple
--       cached views (see the Canvas-Completion B1 fix); a favorites column
--       there would be clobbered by every rest-timer/palette save. ──
CREATE TABLE public.soundboard_favorites (
  user_id    uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  slugs      text[] NOT NULL DEFAULT '{}',
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.soundboard_favorites ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own soundboard favorites"
  ON public.soundboard_favorites FOR SELECT TO authenticated
  USING (auth.uid() = user_id);
CREATE POLICY "users insert own soundboard favorites"
  ON public.soundboard_favorites FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);
CREATE POLICY "users update own soundboard favorites"
  ON public.soundboard_favorites FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

-- ── 3. Curator flag — readable by all (profiles SELECT already public to
--       authenticated), writable by NOBODY client-side (column privilege
--       revoked; service role/superuser only). ──
ALTER TABLE public.profiles
  ADD COLUMN is_curator boolean NOT NULL DEFAULT false;
REVOKE UPDATE (is_curator) ON public.profiles FROM authenticated, anon;

-- ── 4. Curator-gated publishing: replace routines INSERT/UPDATE policies so
--       visibility='public' requires is_curator. 'private'/'shared' behavior
--       unchanged. ──
DROP POLICY "users can insert their own routines" ON public.routines;
CREATE POLICY "users can insert their own routines"
  ON public.routines FOR INSERT TO authenticated
  WITH CHECK (
    auth.uid() = owner_id
    AND (visibility <> 'public'
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );

DROP POLICY "users can update their own routines" ON public.routines;
CREATE POLICY "users can update their own routines"
  ON public.routines FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id)
  WITH CHECK (
    auth.uid() = owner_id
    AND (visibility <> 'public'
         OR (SELECT is_curator FROM public.profiles WHERE id = auth.uid()))
  );
```

- [ ] **Step 2: Write the pgTAP test** (fixture-scoped; mirrors `supabase/tests/user_settings_test.sql`'s structure — read it first for the BEGIN/rollback + fixture-user conventions used by `run_pgtap.js`)

```sql
-- curation_test.sql
BEGIN;
SELECT plan(10);

-- Fixture users (pattern from user_settings_test.sql: insert auth.users +
-- profiles rows inside the rolled-back txn)
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-4000-a000-000000000101', 'cur-test-plain@test.local'),
  ('00000000-0000-4000-a000-000000000102', 'cur-test-curator@test.local');
INSERT INTO public.profiles (id, username) VALUES
  ('00000000-0000-4000-a000-000000000101', 'cur_plain'),
  ('00000000-0000-4000-a000-000000000102', 'cur_curator');
UPDATE public.profiles SET is_curator = true
  WHERE id = '00000000-0000-4000-a000-000000000102';

-- 1-2. Catalog columns exist
SELECT has_column('public','soundboard_sounds','icon','icon column exists');
SELECT has_column('public','soundboard_sounds','category','category column exists');

-- 3. Backfill applied (fixture-scoped to the known seed slug)
SELECT is(
  (SELECT icon FROM public.soundboard_sounds WHERE slug = 'airhorn'),
  '📯', 'airhorn backfilled with emoji icon');

-- 4-5. Favorites RLS: owner can write, non-owner blocked
SET LOCAL role authenticated;
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-a000-000000000101","role":"authenticated"}';
INSERT INTO public.soundboard_favorites (user_id, slugs)
  VALUES ('00000000-0000-4000-a000-000000000101', ARRAY['ding','boo']);
SELECT is(
  (SELECT slugs FROM public.soundboard_favorites
   WHERE user_id = '00000000-0000-4000-a000-000000000101'),
  ARRAY['ding','boo'], 'owner writes+reads own favorites');
SELECT throws_ok(
  $$INSERT INTO public.soundboard_favorites (user_id, slugs)
    VALUES ('00000000-0000-4000-a000-000000000102', ARRAY['ding'])$$,
  '42501', NULL, 'cannot insert favorites for another user');

-- 6. is_curator not client-writable (column privilege)
SELECT throws_ok(
  $$UPDATE public.profiles SET is_curator = true
    WHERE id = '00000000-0000-4000-a000-000000000101'$$,
  '42501', NULL, 'authenticated cannot self-promote to curator');

-- 7. Non-curator cannot publish
SELECT throws_ok(
  $$INSERT INTO public.routines (owner_id, name, visibility)
    VALUES ('00000000-0000-4000-a000-000000000101', 'Sneaky Public', 'public')$$,
  '42501', NULL, 'non-curator cannot insert public routine');

-- 8. Non-curator private insert still works
INSERT INTO public.routines (owner_id, name, visibility)
  VALUES ('00000000-0000-4000-a000-000000000101', 'My Private', 'private');
SELECT pass('non-curator private insert unaffected');

-- 9-10. Curator can publish; everyone can read it
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-a000-000000000102","role":"authenticated"}';
INSERT INTO public.routines (owner_id, name, visibility)
  VALUES ('00000000-0000-4000-a000-000000000102', 'Featured Pack', 'public');
SELECT pass('curator publishes public routine');
SET LOCAL request.jwt.claims = '{"sub":"00000000-0000-4000-a000-000000000101","role":"authenticated"}';
SELECT is(
  (SELECT count(*) FROM public.routines
   WHERE name = 'Featured Pack' AND visibility = 'public')::int,
  1, 'other users see the published routine');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Run pgTAP locally, expect the new file to fail before the migration is applied**

Run: `node scripts/run_pgtap.js`
Expected: `curation_test.sql` FAILS (columns/table missing); all pre-existing files PASS.

- [ ] **Step 4: Apply the migration**

Run: `export $(grep -v '^#' .env.local | xargs) && npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`
Expected: `20260717000003_curation.sql` applied.

- [ ] **Step 5: Re-run pgTAP, all green**

Run: `node scripts/run_pgtap.js`
Expected: ALL files pass, including `curation_test.sql` (10/10).

- [ ] **Step 6: add_sound.js metadata support** — extend the arg parsing and the upsert row (current signature `node scripts/add_sound.js <path> "<Display Name>" [slug]`; keep it backward-compatible, add flags):

```js
// After the existing slug derivation, add flag parsing:
const flag = (name) => {
  const i = process.argv.indexOf(`--${name}`);
  return i >= 0 ? process.argv[i + 1] : undefined;
};
const icon = flag('icon') ?? null;          // e.g. --icon 🥁
const category = flag('category') ?? null;  // hype|funny|fx
if (category && !['hype', 'funny', 'fx'].includes(category)) {
  console.error(`--category must be hype|funny|fx, got "${category}"`);
  process.exit(1);
}

// Real duration for PCM WAVs (replaces the hardcoded 1000; non-WAV → null):
function wavDurationMs(buf) {
  try {
    if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') return null;
    let off = 12, byteRate = null;
    while (off + 8 <= buf.length) {
      const id = buf.toString('ascii', off, off + 4);
      const size = buf.readUInt32LE(off + 4);
      if (id === 'fmt ') byteRate = buf.readUInt32LE(off + 16);
      if (id === 'data' && byteRate) return Math.round((size / byteRate) * 1000);
      off += 8 + size + (size % 2);
    }
    return null;
  } catch { return null; }
}
```

In the DB upsert body replace `duration_ms: 1000` with:

```js
      body: JSON.stringify({
        slug, display_name: displayName, storage_path: storagePath,
        duration_ms: ext === '.wav' ? wavDurationMs(fs.readFileSync(filePath)) : null,
        icon, category,
      }),
```

Note: flags must be excluded from the positional-arg destructure — filter `process.argv` entries starting with `--` (and their values) before the `[, , filePath, displayName, slugArg]` destructure, e.g. build `positional = argv.filter(...)` first.

- [ ] **Step 7: Smoke the script read path** (no upload): `node scripts/add_sound.js` with no args → usage message, exit 1.

- [ ] **Step 8: Commit**

```bash
git add supabase/migrations/20260717000003_curation.sql supabase/tests/curation_test.sql scripts/add_sound.js
git commit -m "feat(curation): catalog metadata, favorites table, curator-gated publishing"
```

CI note: pushing `supabase/**`+`scripts/**` triggers the Backend workflow — pgtap job must be green.

---

### Task 2: App data layer

**Files:**
- Create: `GymSyncApp/GymSync/Models/Soundboard.swift`
- Modify: `GymSyncApp/GymSync/Models/Profile.swift` (add `isCurator`)
- Modify: `GymSyncApp/GymSync/Models/Routine.swift` (visibility + public fetch + clone)
- Test: `GymSyncApp/GymSyncTests/CurationRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 1's schema.
- Produces: `SoundboardSound { slug, displayName, storagePath, durationMs, isCurated, icon, category: String? }`; `SoundboardRepository.fetchCatalog() async throws -> [SoundboardSound]`; `SoundboardFavoritesRepository.get() async throws -> [String]` / `.set(_ slugs: [String]) async throws`; `Profile.isCurator: Bool` (decoded from optional, defaults false); `RoutineRepository.publicRoutines() async throws -> [(routine: Routine, ownerUsername: String)]`; `RoutineRepository.clone(routineID: UUID) async throws -> Routine`; `Routine.visibility` respected by `save`.

- [ ] **Step 1: Profile.isCurator** — add to the struct with decode-default (the column always exists post-migration, but keep older cached rows safe):

```swift
    let isCurator: Bool
    // in CodingKeys:
    case isCurator = "is_curator"
    // custom decode default so any pre-migration cached JSON still decodes:
    // in init(from:) if one exists; otherwise add:
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        username = try c.decode(String.self, forKey: .username)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName)
        avatarURL = try c.decodeIfPresent(URL.self, forKey: .avatarURL)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        lifetimeVolumeLifted = try c.decode(Decimal.self, forKey: .lifetimeVolumeLifted)
        isCurator = try c.decodeIfPresent(Bool.self, forKey: .isCurator) ?? false
    }
```

(Adding a custom `init(from:)` removes the synthesized memberwise init some code may use — check `Profile(` construction sites first with grep; if any exist, add an explicit memberwise init preserving current signatures plus `isCurator: Bool = false`.)

- [ ] **Step 2: Soundboard.swift** — model + two repositories in the established enum style:

```swift
import Foundation
import Supabase

/// Catalog row from `soundboard_sounds` (fetched for UI lists — playback
/// caching stays in SoundboardPlayer, which keeps its own minimal decode).
struct SoundboardSound: Codable, Identifiable, Sendable, Equatable {
    let slug: String
    let displayName: String?
    let storagePath: String
    let durationMs: Int?
    let isCurated: Bool
    let icon: String?      // emoji, per designer frames
    let category: String?  // hype | funny | fx

    var id: String { slug }
    var label: String { displayName ?? slug }

    enum CodingKeys: String, CodingKey {
        case slug
        case displayName = "display_name"
        case storagePath = "storage_path"
        case durationMs = "duration_ms"
        case isCurated = "is_curated"
        case icon
        case category
    }
}

enum SoundboardRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetchCatalog() async throws -> [SoundboardSound] {
        do {
            let rows: [SoundboardSound] = try await client
                .from("soundboard_sounds")
                .select()
                .order("slug")
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}

/// One row per user; absent row = no favorites chosen yet (callers fall back
/// to the first four curated catalog sounds). Deliberately NOT part of
/// user_settings — see migration 20260717000003 header.
enum SoundboardFavoritesRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    private struct Row: Codable {
        let userID: UUID
        let slugs: [String]
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case slugs
        }
    }

    static func get() async throws -> [String] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Row] = try await client
                .from("soundboard_favorites")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute()
                .value
            return rows.first?.slugs ?? []
        } catch { throw ErrorMapping.map(error) }
    }

    static func set(_ slugs: [String]) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("soundboard_favorites")
                .upsert(Row(userID: userID, slugs: slugs))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
```

- [ ] **Step 3: Routine.swift additions** — read the existing `Routine` struct + `save` first; keep its shape. Add:

```swift
    /// Public (curator-published) routines with their owner's username, for
    /// the Library "Featured" shelf. Newest first — frame 3's hero is the
    /// newest publication.
    static func publicRoutines() async throws -> [(routine: Routine, ownerUsername: String)] {
        do {
            struct RowWithOwner: Decodable {
                let routine: Routine
                let owner: OwnerRef
                struct OwnerRef: Decodable { let username: String }
                init(from decoder: Decoder) throws {
                    routine = try Routine(from: decoder)
                    let c = try decoder.container(keyedBy: JoinKeys.self)
                    owner = try c.decode(OwnerRef.self, forKey: .profiles)
                }
                enum JoinKeys: String, CodingKey { case profiles }
            }
            let rows: [RowWithOwner] = try await client
                .from("routines")
                .select("*, profiles!routines_owner_id_fkey(username)")
                .eq("visibility", value: "public")
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows.map { ($0.routine, $0.owner.username) }
        } catch { throw ErrorMapping.map(error) }
    }

    /// "Add to my routines": copies a (public) routine + its exercises into a
    /// new private routine owned by the caller. Reads are allowed by the
    /// public-visibility RLS; writes are plain own-row inserts.
    static func clone(routineID: UUID) async throws -> Routine {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let (source, exercises) = try await fetch(id: routineID) else {
            throw GymSyncError.notFound
        }
        let copy = Routine(
            id: UUID(), ownerID: userID, name: source.name,
            description: source.description, visibility: "private",
            createdAt: Date(), updatedAt: Date()
        )
        let copiedExercises = exercises.map { ex in
            RoutineExercise(
                id: UUID(), routineID: copy.id, exerciseID: ex.exerciseID,
                position: ex.position, targetSets: ex.targetSets,
                targetReps: ex.targetReps, targetWeight: ex.targetWeight,
                restSeconds: ex.restSeconds, notes: ex.notes
            )
        }
        try await save(copy, exercises: copiedExercises)
        return copy
    }
```

(Adjust the `Routine`/`RoutineExercise` memberwise-init argument lists to the structs' actual field order — read them; the FK hint `routines_owner_id_fkey` must match the real constraint name: verify with `node scripts/db_query.js "SELECT conname FROM pg_constraint WHERE conrelid='public.routines'::regclass AND contype='f'"` and use the actual name.)

- [ ] **Step 4: Publish support in the builder's save path** — `RoutineBuilderView` currently hardcodes `visibility: "private"` (~line 366). Change that line to pass a new `@State private var publishAsFeatured = false` → `visibility: publishAsFeatured ? "public" : "private"` (UI toggle added in Task 4; this task just makes save honor it — keep the property in the view, default false, no UI yet, zero behavior change).

- [ ] **Step 5: Tests** — `CurationRepositoryTests.swift`, same live-DB conventions as existing network tests (sign-in via `TestAuth.signInIfConfigured()` in setUp; skip when unconfigured):

```swift
import XCTest
@testable import GymSync

/// Live-DB tests (ci_test_user). Curator-positive publishing is NOT tested
/// here — the CI user is deliberately not a curator, and self-promotion is
/// server-blocked (that's test 6's subject); the curator happy path is
/// covered by pgTAP (fixture curator) + manual QA.
final class CurationRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testCatalogDecodesWithIconAndCategory() async throws {
        let catalog = try await SoundboardRepository.fetchCatalog()
        XCTAssertGreaterThanOrEqual(catalog.count, 4)
        let airhorn = try XCTUnwrap(catalog.first { $0.slug == "airhorn" })
        XCTAssertEqual(airhorn.icon, "📯")
        XCTAssertEqual(airhorn.category, "hype")
    }

    func testFavoritesRoundTrip() async throws {
        let original = try await SoundboardFavoritesRepository.get()
        defer { Task { try? await SoundboardFavoritesRepository.set(original) } }
        try await SoundboardFavoritesRepository.set(["boo", "ding"])
        let fetched = try await SoundboardFavoritesRepository.get()
        XCTAssertEqual(fetched, ["boo", "ding"])
    }

    func testNonCuratorCannotPublish() async throws {
        guard let uid = await SupabaseService.shared.currentUserID() else {
            throw XCTSkip("unconfigured")
        }
        let sneaky = Routine(
            id: UUID(), ownerID: uid, name: "Sneaky Publish Test",
            description: nil, visibility: "public",
            createdAt: Date(), updatedAt: Date()
        )
        do {
            try await RoutineRepository.save(sneaky, exercises: [])
            // If the insert somehow succeeded, clean up and fail loudly.
            try? await RoutineRepository.delete(id: sneaky.id)
            XCTFail("non-curator publish must be rejected by RLS")
        } catch {
            // expected: RLS violation surfaces as an error
        }
    }

    func testCloneCopiesExercisesAsPrivate() async throws {
        guard let uid = await SupabaseService.shared.currentUserID() else {
            throw XCTSkip("unconfigured")
        }
        // Source: the caller's own routine (public not required for clone's
        // read path when you own it — RLS allows either way).
        let source = Routine(
            id: UUID(), ownerID: uid, name: "Clone Source",
            description: nil, visibility: "private",
            createdAt: Date(), updatedAt: Date()
        )
        let exercises = try await ExerciseRepository.fetchAll()
        let ex = try XCTUnwrap(exercises.first)
        let sourceExercises = [RoutineExercise(
            id: UUID(), routineID: source.id, exerciseID: ex.id,
            position: 1, targetSets: 3, targetReps: "10",
            targetWeight: nil, restSeconds: 90, notes: nil
        )]
        try await RoutineRepository.save(source, exercises: sourceExercises)
        defer { Task { try? await RoutineRepository.delete(id: source.id) } }

        let copy = try await RoutineRepository.clone(routineID: source.id)
        defer { Task { try? await RoutineRepository.delete(id: copy.id) } }

        XCTAssertEqual(copy.visibility, "private")
        XCTAssertEqual(copy.name, "Clone Source")
        let (_, copiedEx) = try XCTUnwrap(try await RoutineRepository.fetch(id: copy.id))
        XCTAssertEqual(copiedEx.count, 1)
        XCTAssertEqual(copiedEx.first?.targetReps, "10")
    }
}
```

(Adjust memberwise inits + `ExerciseRepository.fetchAll()` to actual signatures — read `Routine.swift` and the exercises model first. If `Routine` lacks a memberwise init accessible to tests, construct via the same pattern `RoutineBuilderView` uses.)

- [ ] **Step 6: Push, watch iOS CI build-test green** (tests run there). Commit first:

```bash
git add GymSyncApp/GymSync/Models/Soundboard.swift GymSyncApp/GymSync/Models/Profile.swift GymSyncApp/GymSync/Models/Routine.swift GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift GymSyncApp/GymSyncTests/CurationRepositoryTests.swift
git commit -m "feat(curation): app data layer — catalog, favorites, curator flag, public routines + clone"
```

---

### Task 3: Soundboard UI — favorites ribbon + library sheet

**Files:**
- Create: `GymSyncApp/GymSync/Features/Sessions/SoundLibrarySheet.swift`
- Modify: `GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift` (the `soundboardDock` block at ~line 573 and the `soundSlugs`/`soundIcons` constants at ~113-122)

**Interfaces:**
- Consumes: `SoundboardRepository.fetchCatalog()`, `SoundboardFavoritesRepository.get()/set(_:)`, `SoundboardSound` (Task 2); the existing sound-send path in `GroupSessionLiveView` (read `soundboardDock`'s current tile action — it broadcasts via the session broadcast service AND plays locally; REUSE that exact closure, parameterized by slug).
- Produces: `SoundLibrarySheet(catalog:favorites:onFavoritesChanged:onSend:)` SwiftUI view.

- [ ] **Step 1: Replace the hardcoded dock constants.** Delete `soundSlugs`/`soundIcons`. Add state + load:

```swift
    @State private var soundCatalog: [SoundboardSound] = []
    @State private var soundFavorites: [String] = []
    @State private var showSoundLibrary = false

    /// Frame 1: the dock shows the user's 4 favorites; before any are chosen,
    /// the first four curated catalog sounds (matches today's fixed set).
    private var dockSounds: [SoundboardSound] {
        let bySlug = Dictionary(uniqueKeysWithValues: soundCatalog.map { ($0.slug, $0) })
        let chosen = soundFavorites.compactMap { bySlug[$0] }
        if !chosen.isEmpty { return Array(chosen.prefix(4)) }
        return Array(soundCatalog.filter(\.isCurated).prefix(4))
    }
```

Load in the view's existing `.task`/reload path (find where the view already does async setup): `soundCatalog = (try? await SoundboardRepository.fetchCatalog()) ?? []` and `soundFavorites = (try? await SoundboardFavoritesRepository.get()) ?? []` — failures degrade to the curated fallback, never block the session.

- [ ] **Step 2: Rebuild `soundboardDock` per frame 1** — "YOUR SOUNDS" kicker + "Edit" (opens sheet) header row; 4 tiles (emoji `sound.icon ?? "🔊"` at 22pt + `sound.label` in `GSFont.bold(10)`, surface fill, 1px divider border) + the dashed-accent "All" expand button (grid glyph + "All", opens the same sheet). Tile tap = the existing send closure with `sound.slug`. Sheet presentation:

```swift
        .sheet(isPresented: $showSoundLibrary) {
            SoundLibrarySheet(
                catalog: soundCatalog,
                favorites: soundFavorites,
                onFavoritesChanged: { updated in
                    soundFavorites = updated
                    Task { try? await SoundboardFavoritesRepository.set(updated) }
                },
                onSend: { slug in sendSound(slug) }   // ← the existing dock send closure, extracted to a method if inline today
            )
        }
```

- [ ] **Step 3: SoundLibrarySheet per frame 2** — structure (copy verbatim from the frame): grab handle; header "Sounds" + caption "Tap to send · star to favorite"; section "Your 4 favorites · drag to reorder" as a `List` section with `.onMove` (drag handle glyph, emoji, name, filled star = tap removes from favorites); "All sounds" header with segment control Hype/Funny/FX (filters by `category`; nil-category sounds appear in every segment); two-column `LazyVGrid` of catalog rows (emoji + name + star: filled if favorited — tap toggles, capped at 4 with the oldest dropped; row tap = `onSend(slug)` + `dismiss()`). Favorites edits call `onFavoritesChanged` with the new array (optimistic; persistence is the caller's closure). Use `GSFont`/theme tokens throughout; `presentationDetents([.medium, .large])`.

- [ ] **Step 4: Self-review the send path** — tile/row send MUST reuse the existing broadcast+echo+local-play closure so chat echo rows and remote overlays behave identically to today. No new audio APIs.

- [ ] **Step 5: Commit; push; iOS CI green.**

```bash
git add GymSyncApp/GymSync/Features/Sessions/SoundLibrarySheet.swift GymSyncApp/GymSync/Features/Sessions/GroupSessionLiveView.swift
git commit -m "feat(curation): favorites ribbon + sound library sheet per designer frames"
```

---

### Task 4: Library Featured shelf + publish toggle

**Files:**
- Modify: `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`
- Modify: `GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift`

**Interfaces:**
- Consumes: `RoutineRepository.publicRoutines()`, `RoutineRepository.clone(routineID:)` (Task 2); `publishAsFeatured` state (Task 2 Step 4); `AppState.currentProfile?.isCurator`.

- [ ] **Step 1: Publish toggle in RoutineBuilderView** — visible ONLY when `appState.currentProfile?.isCurator == true` (read how the view accesses AppState — match it). A bordered row above the save button: `GSToggle`-style row (reuse the shipped toggle idiom from NotificationPreferencesView) labeled "Publish as Featured" with caption "Visible to every Gym Sync user". Binds `$publishAsFeatured`; editing an existing routine pre-sets it from `editing?.visibility == "public"`.

- [ ] **Step 2: Featured shelf in LibraryTabView per frame 3** — above the existing "Your routines" content:
  - `@State private var featured: [(routine: Routine, ownerUsername: String)] = []`, loaded in the tab's existing `.task`/refresh path via `RoutineRepository.publicRoutines()`; on failure or empty → render nothing (section fully absent — no empty-state chrome).
  - Header row: accent star glyph + "Featured · curated packs" (muted h6 styling).
  - Hero card (newest = `featured.first`): 150pt image placeholder block (neutral300 fill + centered photo glyph at 30% — assets come later), gradient overlay bottom, "SEASONAL" accent chip, routine name in `GSFont.bold(22)` white, "by {ownerUsername}" caption; full-width `GSPrimaryButtonStyle` button "Add to my routines" + plus glyph → `clone`.
  - Horizontal scroll of the remaining `featured.dropFirst()`: 150pt-wide bordered cards (84pt placeholder block, name, exercise-count caption, "Add" secondary button → `clone`).
  - After a successful clone: refresh the user's own routines list (call the view's existing reload) so the copy appears immediately; disable the tapped button while the clone is in flight (`@State private var cloningIDs: Set<UUID> = []`).
- [ ] **Step 3: Promote the owner's account (manual, out-of-repo):** document in the report — `node scripts/db_query.js "UPDATE profiles SET is_curator = true WHERE username ILIKE 'smola'"` (run by controller post-merge; NOT in any migration).
- [ ] **Step 4: Commit; push; iOS CI green.**

```bash
git add GymSyncApp/GymSync/Features/Library/LibraryTabView.swift GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift
git commit -m "feat(curation): Library Featured shelf + curator publish toggle per frame 3"
```

---

## Verification & Ship

- Whole-branch final review (most capable model), PR `--base master`, merge per standing authorization; watch Backend + iOS deploys.
- Post-merge controller steps: promote the owner's profile to curator (Task 4 Step 3 command); seed one public seasonal routine via the app (or `seed_routines.js` + a manual `UPDATE ... SET visibility='public'` as curator) so the Featured shelf isn't empty at first QA.
- Device QA (user): favorites edit + reorder survives relaunch; new sound added via `add_sound.js --icon 🥁 --category hype` appears in the sheet; publish toggle visible on their (curator) account and absent on others; Featured Add lands the copy in "Your routines".

## Self-Review Notes

- Spec coverage: frame 1 (ribbon) → T3; frame 2 (sheet incl. reorder/star/segments) → T3; frame 3 (Featured incl. hero/cards/Add) → T4; catalog emoji/category → T1/T2; curator-only publish server-enforced → T1 (policies) + T4 (UI gate); scripts upgrade → T1. Pack IMAGES are placeholder blocks by design (no asset pipeline yet — noted for the designer follow-up). Multi-routine "packs" ("8 weeks · 4×/wk" card copy) deliberately simplified to single routines for v1 — the schema has no pack concept; noted as a product follow-up.
- Placeholder scan: clean — every code step carries real code; the two "read the actual struct first" notes are implementer verification steps with the grep/query commands supplied.
- Type consistency: `SoundboardSound`/repositories named identically across T2/T3; `publishAsFeatured` defined in T2 Step 4, consumed in T4 Step 1; `publicRoutines()` tuple shape matches T4 Step 2's state type.
