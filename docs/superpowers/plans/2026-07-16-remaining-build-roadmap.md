# Remaining Build Roadmap — 2026-07-16

**Status:** approved scope (user, 2026-07-16): finish harness merge + ExerciseDB media + PR-celebration takeover + unbuilt design frames + P6 Streaks, then release the QA build.

**Method:** each phase runs subagent-driven development on its own feature branch: spec → plan (writing-plans) → fresh implementer subagent per task → task review → CI gate → whole-branch review → merge to `master`. Every `master` merge auto-deploys a TestFlight build (`CURRENT_PROJECT_VERSION = github.run_number`); the last merge is the designated QA build.

**Verification backbone:** the design-parity harness (merged in Phase 0) verifies every UI phase below — each new screen gets a capture + `frame-map.json` entry, and the CI parity report proves faithfulness against its canvas frame. The harness compounds: phases P and U exist *because* it surfaced/tracked them.

---

## Phase 0 — Harness merge (in flight)

Final whole-branch review (running) → fix wave if findings → merge `feature/design-parity-harness` to `master`.

- Branch: `feature/design-parity-harness` (10 commits, all tasks CI-green; parity job validated: 22 pairs, catalog Ink fix proven, `pr-celebration` 64% = top real divergence).
- Deferred Minors from per-task reviews are triaged by the final review (must-fix vs ship).
- Merge auto-deploys a build (harness is invisible to release users — all app changes `#if DEBUG`).

## Phase E — ExerciseDB demonstration media

**Goal:** every exercise in our catalog shows a demonstration GIF on Exercise Detail.

**Decisions (user-approved 2026-07-16):**
- Source: **ExerciseDB open dataset** (11k+ exercises with GIFs) — matched to our `exercises.slug` catalog.
- Hosting: **mirror into Supabase Storage** (one-time import script downloads matched GIFs into a public bucket; app loads from our storage CDN). No third-party runtime dependency, no hotlink/ToS exposure.

**Scope:**
1. Migration: `exercises.demo_media_path` (nullable text) + a public-read storage bucket `exercise-media`.
2. `scripts/import_exercise_media.js` — maps our slugs → ExerciseDB entries (name/equipment/target matching, with a reviewable mapping file for ambiguous cases), downloads GIFs, uploads to the bucket, writes `demo_media_path`. Idempotent (skip already-populated rows). Same `.env.local` service-key pattern as `seed_qa_fixtures.js`.
3. iOS: Exercise Detail renders the GIF (animated, `GSCard`-framed, placeholder when null). SwiftUI has no native GIF view — decode via `CGImageSource` frames or `WKWebView`; the phase spec picks one (lean: CGImageSource-based `GSGifView`).
4. Parity: Exercise Detail already has canvas frame 14 — add the capture + map entry if not present.

**Verification:** unit tests for the mapping logic; import run evidence (counts: matched/ambiguous/missing); CI screenshot of Exercise Detail with media.

## Phase P — PR-celebration takeover (harness finding #1)

**Goal:** replace the small inline PR card with the designed full-screen PR celebration moment (canvas frame 29) — the top divergence (64%) in the first parity report.

**Scope:**
1. Build the full-screen takeover per frame 29 (proof renderable any time via `render_proofs.js`), presented when a set resolves as a PR during a live/solo session; dismiss returns to the session.
2. Keep the existing catalog screen (`pr-celebration`) but point it at the REAL view once it exists (removing the visual-reproduction drift risk flagged in Task 4).
3. Parity: `pr-celebration → frame 29` mapping already exists — the score dropping from 64% into the noise band IS the acceptance test.

## Phase U — Unbuilt design frames

**Goal:** close out the held design frames that are genuinely unbuilt.

**Corrected inventory (2026-07-16):** frame 26 "Rich states" = chat rich states (images/reactions/typing) — ALREADY BUILT in Phase 2.5; the unbuilt-frames README mislabeled it (fix the README in this phase). Actual work:
1. **Stat Tiles states (frame 41):** real loading (redacted) / error / empty states for Home + Stats stat tiles (today they render blank/zero while fetching). Catalog screens `stattile-*` then present the REAL states, not reproductions.
2. **Activity Feed (frame 45):** dedicated scrollable feed (sessions, PRs, friend events) — today Stats only links "View sessions". New view reachable from Stats (and/or Home), fed by existing tables (`sessions`, `personal_records`, friendships) — the phase spec defines the query/RLS shape.
3. README + `frame-map.json` reconciliation: map `stattile-*` and the new feed screen; retire `docs/design/unbuilt-frames/` once all its frames are built or reclassified.

## Phase S — P6 Streaks (largest)

**Goal:** schedule-based streaks per the master spec (`docs/superpowers/specs/2026-06-28-gymsync-design.md` §Streaks + Flow 7) — already product-speced there:
- `user_streaks` + `group_streaks` tables, written ONLY by trigger functions on session completion transitions.
- Streak = consecutive *planned* sessions completed (checked in + logged ≥1 set; group variant for group sessions). Missing a planned session breaks it; unscheduled solo lifts are bonus, never streak-breaking.
- RLS: `user_streaks` readable by owner + friends; `group_streaks` by members; writable only by trigger.
- Display: Stats tab (current + longest), plus wherever the phase spec places the flex (profile/social surfaces).

**Scope:** migration + trigger functions + pgTAP tests (backend), streak display UI (frontend), fixture-seed extension so the harness captures populated streak UI. No canvas frame exists for streak UI — design from the established system (GSTheme/GSCard/GSStatTile), file a designer note for post-hoc blessing, and record the deviation in `accepted-deviations.json` until blessed.

## Release

After Phase S merges: confirm the final TestFlight build number, run the parity report against it, hand the user a consolidated device-QA checklist covering: ExerciseDB GIFs, PR takeover, stat-tile states, Activity Feed, streak lifecycle (needs a planned session completed/missed), plus the standing build-200 items (voice, soundboard, Library/Social/gym-search fixes).

---

## Sequencing rationale

E → P → U → S: front-load the independent, high-user-value phase (E) while it can't conflict with UI phases; P is a one-screen win that retires the harness's top finding; U closes the design backlog; S is the largest and benefits from everything before it (fixture seed extension, harness coverage, populated feed). Each phase merges independently — nothing blocks on the whole sequence.

## Standing constraints (all phases)

- Never `git add -A`; secrets only in gitignored `.env.local`; service-role key stays OUT of CI.
- Swift verifies only in CI (`build-test` / `screenshots` jobs) — implementers reason, reviewers verify signatures, CI is the compiler.
- Migrations append-only, applied only via `db push`; every `postgres_changes` subscription ships its publication migration in the same task.
- pgTAP via `node scripts/run_pgtap.js`; fixture-scope all test data.
- Design is authoritative: canvas frames win on visuals; deviations recorded in `accepted-deviations.json` with reasons.
