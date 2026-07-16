# Phase E — Exercise Demo Media + Library Expansion — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every exercise shows a demonstration GIF on Exercise Detail, and the catalog expands from 30 to a curated ~200 exercises — one import pipeline delivers both.

**Architecture:** A migration adds a public-read `exercise-media` storage bucket. A Node import script runs two idempotent passes: (1) upsert new `exercises` rows from a checked-in, human-reviewable expansion pack; (2) for every exercise with `demo_video_url IS NULL`, resolve its ExerciseDB match, download the GIF once, upload to the bucket, and write the URL. On iOS, a dependency-free `GSGifView` (CGImageSource frame decode wrapped in `UIImageView.animationImages`) renders the GIF at the top of Exercise Detail per canvas frame 14.

**Tech Stack:** Node ≥18 builtins (`node:test`, `fetch`), Supabase Storage REST, Swift/SwiftUI + ImageIO/UIKit (no third-party deps), existing CI (`build-test`/`screenshots`/`parity`).

## Global Constraints

- **License gate is mandatory and blocking:** before any mass GIF download, the implementer must locate and read the ExerciseDB dataset's license and record the verdict + URL in the script header AND the mapping file header. If redistribution/mirroring is not permitted, STOP and report BLOCKED (fallback per spec: wger dataset) — do not mirror unlicensed media.
- Reuse the existing `exercises.demo_video_url` column (migration `20260709000002`). No new column.
- Never mutate the 30 seeded exercises' identity fields (name/slug/category/muscles/equipment) — the expand pass only inserts new slugs and only fills `demo_video_url` where NULL.
- Bucket: `exercise-media`, public read, write via service role only — follow the shape of `supabase/migrations/20260711000002_storage_buckets.sql`.
- Credentials only from gitignored `.env.local` (`SUPABASE_URL` + `SUPABASE_SECRET_KEY`), same pattern as `scripts/seed_qa_fixtures.js`. Never print values; never commit `.env.local`.
- Migrations are append-only, applied ONLY via `npx supabase db push --db-url <session-pooler-url> --yes` (pooler: `aws-0-ca-central-1.pooler.supabase.com:5432`, user `postgres.chjkkwqwdlmaxacwglzm`, password in `.env.local` as `SUPABASE_DB_PASSWORD`).
- Swift compiles ONLY in CI (`build-test` job). No local xcodebuild. The controller pushes and watches CI — implementers commit but do NOT push.
- Never `git add -A` — stage explicit paths.
- Verbose progress logging in the import loop (long-running download job).
- JS tests via Node's built-in `node:test`; they must be discovered by `npm run test:parity` (bare `node --test` auto-discovery of `scripts/tests/*.test.js`).

---

## File Structure

- Create: `supabase/migrations/20260719000001_exercise_media_bucket.sql` — bucket + policies.
- Create: `scripts/lib/exercise_match.js` — pure matching/normalization helpers (exported for tests).
- Create: `scripts/tests/exercise_match.test.js` — unit tests for the helpers + pack validation.
- Create: `scripts/exercise_packs/expansion_v1.json` — curated ~170-exercise expansion pack (content).
- Create: `scripts/import_exercise_media.js` — the two-pass CLI.
- Create: `GymSyncApp/GymSync/DesignSystem/GSGifView.swift` — animated GIF view.
- Modify: `GymSyncApp/GymSync/Features/Library/ExerciseDetailView.swift` (locate exact file in Task 5; it's the Exercise Detail screen under `Features/Library/`) — GIF card at top.
- Modify: `GymSyncApp/GymSyncUITests/ScreenshotTests.swift` + `docs/design/frame-map.json` — `exercise-detail` capture → frame 14.

---

## Task 1: Storage bucket migration

**Files:**
- Create: `supabase/migrations/20260719000001_exercise_media_bucket.sql`

**Interfaces:**
- Produces: bucket `exercise-media` (public read; authenticated/anon cannot write). Task 4's uploads use the service role (bypasses policies).

- [ ] **Step 1: Read the precedent** — `supabase/migrations/20260711000002_storage_buckets.sql` — and mirror its idiom exactly (bucket insert + policies).

- [ ] **Step 2: Write the migration**

```sql
-- Public-read bucket for exercise demonstration GIFs (Phase E).
-- Mirrored one-time from the ExerciseDB open dataset by
-- scripts/import_exercise_media.js (service role); clients only read.
insert into storage.buckets (id, name, public)
values ('exercise-media', 'exercise-media', true)
on conflict (id) do nothing;

-- Public read (bucket is public, but keep an explicit select policy for parity
-- with existing buckets' style if 20260711000002 does so — mirror it).
create policy "exercise media public read"
  on storage.objects for select
  using (bucket_id = 'exercise-media');

-- No insert/update/delete policies: only the service role (which bypasses
-- RLS) writes. Follow 20260711000002's comment style.
```

Adjust to match the precedent file's exact style (policy naming, whether public buckets there carry explicit select policies).

- [ ] **Step 3: Apply**

Run: `cd /g/Projects/GymSync && npx supabase db push --db-url "postgresql://postgres.chjkkwqwdlmaxacwglzm:$DB_PASS@aws-0-ca-central-1.pooler.supabase.com:5432/postgres" --yes` (DB_PASS from `.env.local` `SUPABASE_DB_PASSWORD` — export it in the shell without echoing).
Expected: migration applies cleanly.

- [ ] **Step 4: Verify**

Run: `node scripts/db_query.js "select id, public from storage.buckets where id='exercise-media'"`
Expected: one row, `public = true`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260719000001_exercise_media_bucket.sql
git commit -m "feat(media): exercise-media storage bucket"
```

---

## Task 2: Matching helpers + tests (TDD)

**Files:**
- Create: `scripts/lib/exercise_match.js`
- Create: `scripts/tests/exercise_match.test.js`

**Interfaces:**
- Produces: `normalizeName(s) => string` (lowercase, strip punctuation/parentheticals, collapse spaces); `slugify(s) => string`; `scoreMatch(ours, theirs) => number` in [0,1] where `ours = {name, equipment, primaryMuscle}` and `theirs = {name, equipment, target}` (0.6 weight on name token overlap, 0.2 equipment equality after normalization, 0.2 target-muscle equality after a small alias map e.g. chest↔pectorals, back↔lats/upper back); `bestMatch(ours, candidates, threshold = 0.75) => {candidate, score} | null`; `validatePack(pack) => string[]` (array of error strings; empty = valid) enforcing: unique slugs, required fields (`slug,name,category,primary_muscle,equipment,match_key`), category ∈ {compound, isolation}, slug format `^[a-z0-9-]+$`.

- [ ] **Step 1: Write the failing tests**

```js
const { test } = require('node:test');
const assert = require('node:assert');
const { normalizeName, slugify, scoreMatch, bestMatch, validatePack } = require('../lib/exercise_match.js');

test('normalizeName strips parentheticals and case', () => {
  assert.equal(normalizeName('Bench Press (Barbell)'), 'bench press');
  assert.equal(normalizeName('  DB  Shoulder-Press '), 'db shoulder press');
});

test('slugify produces kebab', () => {
  assert.equal(slugify('Incline Bench Press'), 'incline-bench-press');
});

test('scoreMatch rewards exact name+equipment+muscle', () => {
  const s = scoreMatch(
    { name: 'bench press', equipment: 'barbell', primaryMuscle: 'chest' },
    { name: 'bench press', equipment: 'barbell', target: 'pectorals' }
  );
  assert.ok(s > 0.95, `expected ~1, got ${s}`);
});

test('bestMatch returns null below threshold', () => {
  const r = bestMatch(
    { name: 'back squat', equipment: 'barbell', primaryMuscle: 'quads' },
    [{ name: 'bicep curl', equipment: 'dumbbell', target: 'biceps' }]
  );
  assert.equal(r, null);
});

test('validatePack catches duplicate slugs and bad category', () => {
  const errs = validatePack([
    { slug: 'a-b', name: 'A', category: 'compound', primary_muscle: 'chest', equipment: 'barbell', match_key: 'x' },
    { slug: 'a-b', name: 'B', category: 'weird', primary_muscle: 'back', equipment: 'cable', match_key: 'y' },
  ]);
  assert.ok(errs.some(e => e.includes('duplicate slug')));
  assert.ok(errs.some(e => e.includes('category')));
});
```

- [ ] **Step 2: Run to verify failure** — `node --test scripts/tests/exercise_match.test.js` → FAIL (module not found).

- [ ] **Step 3: Implement `scripts/lib/exercise_match.js`** — pure functions, no I/O, matching the interfaces above exactly (including the muscle alias map: chest↔pectorals, back↔lats↔upper back, quads↔quadriceps, hamstrings, glutes, shoulders↔delts↔deltoids, biceps, triceps, calves, abs↔abdominals↔core).

- [ ] **Step 4: Run to verify pass** — `node --test scripts/tests/exercise_match.test.js` → all pass; then `npm run test:parity` → full suite green (12 existing + these).

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/exercise_match.js scripts/tests/exercise_match.test.js
git commit -m "feat(media): exercise matching helpers + tests"
```

---

## Task 3: Dataset discovery + license gate + expansion pack (content)

**Files:**
- Create: `scripts/exercise_packs/expansion_v1.json`

**Interfaces:**
- Consumes: `validatePack` (Task 2) for self-checking.
- Produces: the pack — an array of `{ slug, name, category, primary_muscle, secondary_muscles?, equipment, match_key }` (match_key = the ExerciseDB exercise id or exact name that identifies the GIF source). Header conventions: since JSON has no comments, the pack's FIRST element is `{ "_meta": { "dataset": "<url>", "license": "<name + verdict>", "retrieved": "<date>" } }` and `validatePack` must skip `_meta`.

- [ ] **Step 1: Discover the dataset.** Find the ExerciseDB open dataset (start: github.com/ExerciseDB/exercisedb-api — its README links the dataset/API). Identify: how to enumerate all exercises (JSON dump or paged API), the GIF URL field, the id/name fields, equipment + target vocabularies. Record exact URLs.

- [ ] **Step 2: LICENSE GATE (blocking).** Read the dataset's license. Record verdict (license name, whether mirroring GIFs into our own storage is permitted, source URL) in `_meta`. If not permitted → report BLOCKED with the license text reference; do NOT proceed.

- [ ] **Step 3: Author the pack.** ~170 new exercises (target total ≈200 with the existing 30). Coverage rule: every major muscle group (chest, back, shoulders, biceps, triceps, quads, hamstrings, glutes, calves, abs) × common equipment (barbell, dumbbell, cable, machine, bodyweight) where a sensible movement exists; compound + isolation mix. Slugs must not collide with the existing 30 (`node scripts/seed_routines.js --list-exercises` lists them). Every entry's `match_key` must be verified to exist in the dataset (spot-check programmatically: resolve each match_key, assert a GIF URL comes back — a tiny throwaway loop is fine, keep it under 20 requests/sec).

- [ ] **Step 4: Validate** — add a temporary check `node -e "const {validatePack}=require('./scripts/lib/exercise_match.js');const p=require('./scripts/exercise_packs/expansion_v1.json');const e=validatePack(p.filter(x=>!x._meta));console.log(e.length?e:'pack valid: '+(p.length-1)+' exercises');process.exit(e.length?1:0)"` → `pack valid: ~170 exercises`.

- [ ] **Step 5: Commit**

```bash
git add scripts/exercise_packs/expansion_v1.json
git commit -m "feat(media): expansion pack v1 (~170 exercises) + dataset license record"
```

---

## Task 4: Import CLI + live run

**Files:**
- Create: `scripts/import_exercise_media.js`

**Interfaces:**
- Consumes: Task 2 helpers, Task 3 pack, bucket (Task 1), `.env.local` service key.
- Produces (CLI): `node scripts/import_exercise_media.js [--dry-run] [--pack scripts/exercise_packs/expansion_v1.json]`. Pass 1 (expand): insert pack exercises whose slug is absent. Pass 2 (backfill): for each `exercises` row with `demo_video_url IS NULL`, resolve the GIF (pack `match_key` for pack rows; `bestMatch` against the dataset for the original 30, writing resolutions to `scripts/exercise_media_map.json` for review), download, upload to `exercise-media/<slug>.gif` (storage REST, `Authorization: Bearer <service key>`, upsert), update `demo_video_url` to the bucket's public URL. Skip populated rows. End summary: `expanded X · matched Y · uploaded Z · skipped W · UNMATCHED: [slugs]`. `--dry-run` does everything except upload/update.

- [ ] **Step 1: Implement** — mirror `seed_qa_fixtures.js`'s env-loading + `rest()` helper; add a `storageUpload(path, buffer, contentType)` helper (POST `${SUPABASE_URL}/storage/v1/object/exercise-media/${path}` with `x-upsert: true`). Progress-log every row. Throttle downloads (≤5 concurrent).

- [ ] **Step 2: Dry run** — `node scripts/import_exercise_media.js --dry-run` → full resolution report, zero writes, no UNMATCHED among pack rows (fix pack keys if any).

- [ ] **Step 3: Live run** — expect `expanded ~170 · uploaded ~200`. Spot-check: `node scripts/db_query.js "select count(*) filter (where demo_video_url is not null) as with_media, count(*) as total from exercises"` → with_media ≈ total.

- [ ] **Step 4: Idempotency second run** — rerun; expect `expanded 0 · uploaded 0 · skipped ~200`. Counts stable.

- [ ] **Step 5: Commit**

```bash
git add scripts/import_exercise_media.js scripts/exercise_media_map.json
git commit -m "feat(media): import CLI — expand pass + media backfill (idempotent)"
```

---

## Task 5: GSGifView + Exercise Detail (Swift — CI-verified)

**Files:**
- Create: `GymSyncApp/GymSync/DesignSystem/GSGifView.swift`
- Modify: the Exercise Detail view (locate under `GymSyncApp/GymSync/Features/Library/` — the view pushed from `ExercisesListView`; read it first)

**Interfaces:**
- Produces: `GSGifView(url: URL?)` — renders animated GIF from `url`; placeholder (existing photo-glyph idiom on `theme.neutral300`) while loading or when nil. Uses `URLSession.shared` with `URLCache` default; decodes ALL frames via `CGImageSource` (ImageIO), computes per-frame delays, wraps in `UIImageView` (`animationImages` + `animationDuration` = Σ delays) via `UIViewRepresentable`. `import SwiftUI`, `import ImageIO`, `import UIKit`.

- [ ] **Step 1: Read the target views** — Exercise Detail's real file/initializer and the `Exercise` model (confirm it decodes `demo_video_url`; if the Swift model lacks the field, add `demoVideoURL: String?` with the snake_case CodingKey, decode-optional so existing call sites compile).

- [ ] **Step 2: Implement GSGifView** (complete, dependency-free):

```swift
import SwiftUI
import UIKit
import ImageIO

/// Animated-GIF view for exercise demonstrations (Phase E). Dependency-free:
/// downloads via URLSession (URLCache-backed), decodes every frame with
/// ImageIO, and animates through UIImageView.animationImages. Shows the
/// standard photo-glyph placeholder while loading or when url is nil.
struct GSGifView: View {
    let url: URL?
    @Environment(\.gsTheme) private var theme
    @State private var frames: [UIImage] = []
    @State private var duration: TimeInterval = 0

    var body: some View {
        ZStack {
            Rectangle().fill(theme.neutral300)
            if frames.isEmpty {
                Image(systemName: "photo")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.text.opacity(0.3))
            } else {
                AnimatedImageView(frames: frames, duration: duration)
            }
        }
        .task(id: url) { await load() }
    }

    private func load() async {
        frames = []; duration = 0
        guard let url else { return }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return }
        var imgs: [UIImage] = []
        var total: TimeInterval = 0
        for i in 0..<CGImageSourceGetCount(source) {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            imgs.append(UIImage(cgImage: cg))
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any]
            let gif = props?[kCGImagePropertyGIFDictionary] as? [CFString: Any]
            let delay = (gif?[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval)
                .flatMap { $0 > 0.011 ? $0 : nil }
                ?? (gif?[kCGImagePropertyGIFDelayTime] as? TimeInterval)
                ?? 0.1
            total += delay
        }
        frames = imgs
        duration = max(total, 0.1)
    }
}

private struct AnimatedImageView: UIViewRepresentable {
    let frames: [UIImage]
    let duration: TimeInterval

    func makeUIView(context: Context) -> UIImageView {
        let v = UIImageView()
        v.contentMode = .scaleAspectFit
        v.clipsToBounds = true
        // Without a low content-hugging/compression priority the intrinsic
        // image size fights the SwiftUI frame.
        v.setContentHuggingPriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        v.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return v
    }

    func updateUIView(_ v: UIImageView, context: Context) {
        v.stopAnimating()
        v.animationImages = frames
        v.animationDuration = duration
        v.animationRepeatCount = 0
        v.image = frames.first
        v.startAnimating()
    }
}
```

- [ ] **Step 3: Integrate on Exercise Detail** — a `GSGifView(url: exercise.demoVideoURL.flatMap(URL.init))` card at the top (height ≈ 220, `.clipped()`, `GSCard`/border idiom per frame 14 — read the frame proof `proof-frame-14.png` via the rendered proofs for the exact layout), above the existing metadata.

- [ ] **Step 4: Parity capture** — in `ScreenshotTests.swift` add `testExerciseDetail()` (Library tab → Exercises segment → tap first exercise row → settle ×2 for GIF load → `attachScreenshot(app, named: "app-exercise-detail.png")`, defensive guards per file convention). Add `"exercise-detail": { "frame": 14, "title": "Exercise Detail" }` to `docs/design/frame-map.json`.

- [ ] **Step 5: Commit** (do NOT push — controller pushes/watches CI)

```bash
git add GymSyncApp/GymSync/DesignSystem/GSGifView.swift GymSyncApp/GymSync/Features/Library/<ExerciseDetailFile>.swift GymSyncApp/GymSyncUITests/ScreenshotTests.swift docs/design/frame-map.json
git commit -m "feat(media): GSGifView + Exercise Detail demo GIF (frame 14) + parity capture"
```

(If the Exercise model needed the decode field, include that file in the same commit.)

---

## Task 6: CI verification (controller-led)

- [ ] Push; watch `build-test` (compiles GSGifView + model change) → green.
- [ ] Watch `screenshots` + `parity`; download artifacts; confirm `app-exercise-detail.png` shows a real GIF frame (not placeholder) and the parity report has the frame-14 row.
- [ ] Ledger + roadmap tick.

---

## Self-Review

**Spec coverage:** bucket (T1)=spec §1; import script + mapping file + license gate (T3/T4)=spec §2 + license gate; expansion (T3)=spec expansion; GSGifView (T5)=spec §3; Exercise Detail + parity (T5)=spec §4-5; verification (T2/T4/T6)=spec §Verification. Column reuse honored (no migration touches `exercises`). ✓
**Placeholder scan:** all steps carry code/commands; T3 is content authorship with explicit coverage rules + verification loop; T5 Step 1 names the discovery the implementer must do (real file/initializer) rather than guessing a path. ✓
**Type consistency:** `scoreMatch/bestMatch/validatePack` signatures match between T2 tests and T4 usage; `_meta` skip rule stated once and used in T3 Step 4's validation command; `demo_video_url` ↔ `demoVideoURL` CodingKey noted in T5. ✓
