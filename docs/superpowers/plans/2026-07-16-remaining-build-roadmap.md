# Remaining Build Roadmap — 2026-07-16

**Status:** approved scope (user, 2026-07-16): finish harness merge + ExerciseDB media + PR-celebration takeover + unbuilt design frames + P6 Streaks, then release the QA build.
**Amended (user, 2026-07-16):** coverage audit of the original master design (`docs/superpowers/specs/2026-06-28-gymsync-design.md`) found 13 spec'd tables and several iOS integrations never built. User decision: **add all recovered features — nothing from the original design is dropped.** Phase M is the gate before any public App Store submission.
**Amended again (plan-leakage audit, 2026-07-16):** a sweep of all 15 historical phase plans + the execution ledger (114 items adjudicated) surfaced deferrals that had escaped every phase. Recovered here: **Phase F** (session sub-thread chat, group Stats sub-tab, Edit Profile + user avatars); Phase S gains no_show production wiring + burpee settlement + streak pushes; Phase U gains the recap-celebration adjudication + backend-gap canvas features; Phase O gains the named 3e follow-up queue + reliability debt list. Full order: **E → P → U → S → F → M → L → H → O → W → C → V**.

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
1. Storage: a public-read bucket `exercise-media`. Reuse the EXISTING `exercises.demo_video_url` column (present since migration 20260709000002) — no new column unless the phase spec finds a reason.
2. `scripts/import_exercise_media.js` — maps our slugs → ExerciseDB entries (name/equipment/target matching, with a reviewable mapping file for ambiguous cases), downloads GIFs, uploads to the bucket, writes the media URL. Idempotent (skip already-populated rows). Same `.env.local` service-key pattern as `seed_qa_fixtures.js`.
3. **Library expansion (coverage-audit addition):** the master spec targets a 150–300 exercise curated library; we have 30 seeded. The same import pipeline seeds new `exercises` rows (name/slug/category/muscles/equipment from ExerciseDB) up to a curated ~150–300 set, each with media.
4. iOS: Exercise Detail renders the GIF (animated, `GSCard`-framed, placeholder when null). SwiftUI has no native GIF view — decode via `CGImageSource` frames or `WKWebView`; the phase spec picks one (lean: CGImageSource-based `GSGifView`).
5. Parity: Exercise Detail already has canvas frame 14 — add the capture + map entry if not present.

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

**Leakage-audit additions (2026-07-16):**
4. **Recap-celebration adjudication:** canvas frames 8 and 17 are full-screen "Session Complete" celebrations (kudos, session leaderboard) — the app implements the quieter Session Detail (frame 34). Adjudicate which the design intends for group-session end (likely: celebration at session end, Session Detail from history), build what's missing, map the frames.
5. **Backend-gap canvas features** (parked during visual-parity because the schema lacked them): proposal countdown/expiry, kudos, presence/last-active, exercise swap proposals, lobby voice card, countdown hero. Re-inventory each against the CURRENT schema (several gaps have since closed); build the ones now buildable, record the rest with their missing prerequisite.

## Phase S — P6 Streaks (largest)

**Goal:** schedule-based streaks per the master spec (`docs/superpowers/specs/2026-06-28-gymsync-design.md` §Streaks + Flow 7) — already product-speced there:
- `user_streaks` + `group_streaks` tables, written ONLY by trigger functions on session completion transitions.
- Streak = consecutive *planned* sessions completed (checked in + logged ≥1 set; group variant for group sessions). Missing a planned session breaks it; unscheduled solo lifts are bonus, never streak-breaking.
- RLS: `user_streaks` readable by owner + friends; `group_streaks` by members; writable only by trigger.
- Display: Stats tab (current + longest), plus wherever the phase spec places the flex (profile/social surfaces).

**Scope:** migration + trigger functions + pgTAP tests (backend), streak display UI (frontend), fixture-seed extension so the harness captures populated streak UI. No canvas frame exists for streak UI — design from the established system (GSTheme/GSCard/GSStatTile), file a designer note for post-hoc blessing, and record the deviation in `accepted-deviations.json` until blessed.

**Leakage-audit additions (2026-07-16) — prerequisites and spec'd companions:**
- **`no_show` production wiring (BLOCKING prerequisite):** no code path ever sets `check_in_state='no_show'` today (ledger product gap), yet the spec's streak-break rule fires on exactly that transition. Wire the lateness threshold (default 15 min → no_show, spec Flow 6) server-side before the streak triggers land, or streaks can never break.
- **Burpee settlement:** `burpees_owed` never decrements — no settled state exists (Burpee Ledger renders owed-only). Add the settlement mechanism (penalty set_logs with `is_penalty=true` decrementing owed, or a `burpees_paid` counter — phase spec decides with product rationale recorded).
- **Streak pushes (spec Flow 7 notifications, deferred from 3d):** milestone pushes (7/14/30/60/90/180/365), streak-at-risk push (30 min before `scheduled_for`, not checked in), silent on break. The 3d push-dispatcher taxonomy already reserved these.

---

# Recovered phases (coverage audit, 2026-07-16)

The 2026-06-28 master design's v1 list was audited against migrations + Swift source. Everything below was spec'd for v1, never built, and is now committed roadmap. (The spec's own v2 deferrals — badges, supersets, ledger search, progress photos, custom exercises, etc. — remain correctly deferred and are NOT in scope.)

## Phase F — Social finishers (plan-leakage recoveries)

Three spec'd v1 social features that were deferred phase-to-phase and escaped every net:
1. **Session sub-thread chat** (spec §Chat: `chat_messages.session_id` sub-threads; deferred at 3a → 3b → 3c): per-session chat thread inside the session/lobby surfaces, distinct from group-level chat. Schema already has the column shape spec'd; comms migration currently lacks it — extend + wire read/send + realtime.
2. **Group Stats sub-tab** (spec Flow 5; GroupView today has only Chat + Sessions): collective metrics (total sessions, PRs, volume) + per-member leaderboards for the group.
3. **Edit Profile + user avatars** (Phase 2.5 deferral; You-tab "Edit" button is currently inert): display-name edit, avatar upload (Storage `avatars` bucket precedent exists from group avatars), avatar rendering across chat/roster/leaderboards; avatar picker in CreateGroupView while in there.

## Phase M — Moderation & compliance (App Store gate)

**Why first among recovered phases:** both items are App Store review requirements for UGC apps; no public submission can happen until M ships. TestFlight is unaffected.
1. **Block / report** (spec §Moderation): `user_reports` + `blocked_users` tables + RLS; Block/Report actions on profiles, chat messages, published routines; block enforcement at query level (chat filtered, friend requests rejected, blocked users excluded everywhere). `app_admin` role granted via SQL; moderation queue UI stays v2.
2. **Account deletion cascade** (spec §6.2): `account-deletion-cascade` Edge Function + "Delete Account" in You tab; cascades owned data, tombstones shared records ("Deleted User").
3. **Solo-workout privacy opt-in**: surface `profiles.show_solo_workouts` (spec'd column) in settings; enforce in `set_logs` RLS read policy.

## Phase L — Discover + public workout leaderboards (largest missing pillar)

Spec Flow 4 + §Public Workout Repository:
1. Tables: `workout_attempts`, `leaderboard_entries` + `leaderboard-recompute` (trigger or Edge Function).
2. Library gains the **Discover** sub-tab: public workout detail (description, scoring metrics, sortable leaderboard — Time / Volume / Top Set / Recent), Attempt Solo / Attempt with Friends CTAs, per-attempt opt-in leaderboard toggle.
3. Routine publishing extended with public-workout fields (`is_featured`, `default_sort`, `scoring_metrics`, `scoring_top_set_exercise_id` — spec'd, unbuilt).
4. **Top Lifters** global leaderboard on lifetime volume; leaderboard system messages (`system_leaderboard`) + `leaderboard_passed` push.
5. Duration-edit interaction honored: leaderboard time locked to original, "✏️ edited" indicator.
6. Content: seed featured workouts ("The Murph", strength templates) — pairs with Phase E's expanded library.

## Phase H — Health & calendar integrations

1. **Apple Health export** (spec §2, Flow 2 step 8): `HealthKitBridge`; completed sessions written as `HKWorkout` (`.functionalStrengthTraining`); toggle in You tab (the designed Apple Health row becomes functional); re-write on duration edit.
2. **iOS Calendar sync** (EventKit): scheduled sessions → calendar events; update/delete on reschedule/cancel.
3. **Body weight log + trend** (spec'd `body_weight_logs` + Stats trend chart).
4. **Plate-math helper** (spec v1 list): target weight + bar → plate stack; surfaced from the live set UI.
5. **Google Calendar sync (sub-phase, gated on OAuth consent approval ~1-2 weeks — start the Google Cloud verification at Phase H kickoff):** `connected_accounts` (Vault-encrypted tokens) + `session_calendar_syncs` + Edge Function sync per spec Flow 10.

## Phase O — Reliability + accumulated polish debt

1. **Offline-first set logging** (spec §6.4): SwiftData local store + pending-writes queue (client-generated UUID PKs make retries idempotent — already true); optimistic UI with syncing indicator; 90-day cache window.
2. **Sentry** crash reporting + sanitized session-state snapshots (spec §6.8.5).
3. **3e voice follow-up queue** (canonical 8-item backlog, priority order per its triage): sign-out bounded `leave()` timeout; chat mic gate during `.connecting`; join session-scope guard; muted-others roster rows; coach mark + "voice connected" toast + voice mixer sheet + transmit hero/80pt dock variant (designer-proposed); Lobby↔Live back-nav rejoin blip; restore-helper DRY; SeriesEditorView device-tz picker residual.
4. **Reliability/debt roll-up** (from the plan-leakage audit — each small, none forgotten): storage orphan cleanup + signed-URL re-resolution (chat/avatars); tab-switch transient-state loss (design discussion: lift to AppState vs keep-alive); series ops transactionality (client-orchestrated today) + until-date inclusive semantics (Teams parity) ; chat_read_state UPDATE policy membership re-check + DB-level lowercase-username constraint; PushPrimingView re-entry dead code (wire or delete) + `.restricted` auth no-op CTA; friend_request threadId passthrough + deep-link re-push dedupe; soundboard favorites `updated_at` bump; `publicRoutines()` smoke test; demoted-curator republish lock (document or add demotion flow); chat foreground-refetch confirmation (key screens have scenePhase handling; verify chat).

## Phase W — Apple Watch companion + heart rate broadcast

The spec's "true differentiator." New watchOS target (CI builds it like the iOS app):
1. Watch app: whose-turn indicator, soundboard buttons, tap-to-log-set, ledger glance (WatchConnectivity sync).
2. **Heart rate broadcast** (spec §6.5, wire shape §5): opt-in `share_heart_rate`, `HKAnchoredObjectQuery` on Watch → phone → `session:{id}:hr` broadcast at 1/5s, zone-colored HR pills (canvas Live frames already show "BPM · LIVE"), ephemeral only — never persisted.

## Phase C — Seasonal campaigns

Spec Flow 8: `campaigns`/`campaign_participants`/`campaign_progress` tables + progress trigger; Library **Campaigns** sub-tab + Home carousel; community progress bar (live via postgres_changes); per-campaign leaderboard; completion badge + system message. Ops prerequisite: team-curated campaign calendar (content work — user).

## Phase V — Local venue hubs (18+, last)

Spec Flow 9 + §6.7: `venues`/`venue_users`/`venue_join_requests`; QR scan flow; Gym Hub view (local leaderboard, open crews, anonymized activity); crew join requests. **Prerequisites before build:** Twilio Verify account (phone verification), age-gate copy, privacy-policy update + legal review for phone-number handling, venue seeding strategy. Safety measures per spec are mandatory scope, not optional.

---

## Release

Two release gates instead of one:
1. **QA build** after Phase S (as originally planned): consolidated device-QA checklist — ExerciseDB GIFs + expanded library, PR takeover, stat-tile states, Activity Feed, streak lifecycle, plus standing build-200 items (voice, soundboard, Library/Social/gym-search).
2. **App-Store-ready milestone** after Phase M (plus whatever else has merged): block/report + account deletion verified — the compliance gate for public submission.

---

## Sequencing rationale

E → P → U → S (original four): front-load the independent, high-user-value phase (E) while it can't conflict with UI phases; P is a one-screen win that retires the harness's top finding; U closes the design backlog; S is the largest of the four and benefits from everything before it.
Then F → M → L → H → O → W → C → V (recovered): F is a small social-completion sprint right after S (its features share S's session/social surfaces); M is small and unblocks the store; L is the biggest missing product pillar; H and O are medium integrations; W opens a new platform target; C and V close the list — both need ops/legal/content setup beyond code (campaign calendar; Twilio + privacy review), so their lead time runs in parallel while earlier phases build. Each phase merges independently — nothing blocks on the whole sequence.

## Content backlog (not code — user/designer)

From the leakage audit, tracked so they don't silently drop: featured-pack artwork + an asset pipeline (packs render placeholder blocks today); additional soundboard sounds the designer proposed (Drumroll, Clap, Dig in, Lightweight) via `scripts/add_sound.js`; the multi-routine "packs" product concept (v1 deliberately ships single routines); the seasonal campaign calendar (Phase C prerequisite); real featured-workout seed set for Phase L ("The Murph" etc. — shared with L's scope).

## Standing constraints (all phases)

- Never `git add -A`; secrets only in gitignored `.env.local`; service-role key stays OUT of CI.
- Swift verifies only in CI (`build-test` / `screenshots` jobs) — implementers reason, reviewers verify signatures, CI is the compiler.
- Migrations append-only, applied only via `db push`; every `postgres_changes` subscription ships its publication migration in the same task.
- pgTAP via `node scripts/run_pgtap.js`; fixture-scope all test data.
- Design is authoritative: canvas frames win on visuals; deviations recorded in `accepted-deviations.json` with reasons.
