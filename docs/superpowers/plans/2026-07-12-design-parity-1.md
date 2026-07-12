# Gym Sync — Design Parity Iteration 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the gaps found by the 2026-07-12 design-vs-implementation audit: fix all 10 button/interaction defects, correct styling deviations, and build the canvas content that the existing backend can already support (Home content model, Stats chart + PRs, You profile card, solo recap, onboarding screens 3-4, custom tab dock).

**Architecture:** View-layer rebuilds against the committed canvas, plus one new backend unit (`personal_records` table + repository) that powers four PR surfaces, and one new write path (`GymRepository`) onto the existing `gyms` table. Everything else consumes existing repositories.

**Tech Stack:** unchanged (SwiftUI, Supabase, Swift Charts NOT used — canvas bar chart is plain flex bars; MapKit added for gym picker).

**Reference documents (implementers read the sections named in their task):**
- Audit: `docs/design/requests/2026-07-12-design-vs-implementation-audit.md`
- Dossier (exact canvas markup + Swift interfaces): `.superpowers/parity-dossier.md` — cited as "Dossier §X" below. THE DOSSIER'S CANVAS TRANSCRIPTIONS ARE THE BUILD CONTRACT; consult the canvas HTML itself only if the dossier is ambiguous.
- Canvas: `docs/design/Gym Sync App Designs.dc.html` (large — read targeted line ranges only).

## Global Constraints

- **Design authority:** canvas wins on everything it shows. Canvas colors are the modernist palette; the app ships midnight — map canvas CSS vars to `GSTheme` tokens (`--color-accent` → `theme.accent`, `--color-accent-100` → `theme.accent100`, `--color-accent-700` → `theme.accent700`, `--color-neutral-400` → `theme.neutral400`, muted text → `theme.neutral700`, `--color-bg` → `theme.bg`, `--color-surface` → `theme.surface`). Archivo via `GSFont` only. Zero corner radius. Flush-left labels. 2px dividers via `GSDivider`.
- **Recorded deviations (deliberate, do not "fix"):** Home keeps Upcoming Sessions list + Join-with-Code + Schedule Session BELOW the canvas content (canvas is silent on them; they are load-bearing group-session entry points). Stats keeps the per-exercise navigation list below canvas content. You tab keeps the Theme row and OMITS Edit Profile + Notifications rows (their destinations don't exist yet — dead rows are worse than absent rows). Recap share button: canvas draws 30×30 but tap target must be ≥44pt (see next rule).
- **44pt minimum tap targets everywhere.** Visual size may match canvas; hit area must reach 44×44 via `.frame(minWidth: 44, minHeight: 44)` or padding + `.contentShape(Rectangle())`.
- **Every `Button` uses a GS*ButtonStyle where one fits; any remaining `.buttonStyle(.plain)` with a hand-rolled label MUST carry `.contentShape(Rectangle())`.**
- **Zero functional regressions:** realtime, dedup guards, scenePhase refetch, markRead, navigation targets, organizer gating, check-in flow, HealthKit export all survive.
- **Audio sacred rule:** `AudioSessionManagerTests.swift` and `AudioSessionRestoreTests.swift` are UNTOUCHABLE; no task here touches the audio session.
- **Migrations append-only; next free timestamp `20260715000002`.** Apply ONLY via `export $(grep -v '^#' .env.local | xargs) && npx supabase db push --db-url "$SUPABASE_DB_URL" --yes` from repo root (bash). pgTAP via `node scripts/run_pgtap.js`.
- Git: branch `feature/design-parity-1` (already created). Specific-file `git add` only (NEVER `git add -A`). Commit per task. CI must be green per task: `gh run list --branch feature/design-parity-1` after push.
- PR at the end: `gh pr create --base master`.
- Tests: new logic (PR repository, gym repository, week-bucketing, stat derivations) gets unit tests; pure view restyles are covered by build + `ScaffoldTests`.

## File Structure

```
supabase/migrations/20260715000002_personal_records.sql   # Task 2
supabase/tests/personal_records_test.sql                   # Task 2
GymSyncApp/GymSync/Models/PersonalRecord.swift             # Task 2 (model + repository)
GymSyncApp/GymSync/Models/GymRepository.swift              # Task 7 (write path onto gyms)
GymSyncApp/GymSync/DesignSystem/GSComponents.swift         # Task 1 (GSSettingsRow, GSStatTile additions), Task 4 (GSTabBar)
Modified: UsernameView, LobbyView, ProposalCardView, GroupSessionLiveView,
CompletedSessionView, ChatView, WorkoutSessionView, LibraryTabView, LogSetSheet,
SocialTabView, RootView, HomeView, StatsTabView, YouTabView, OnboardingCoordinator (+ 2 new onboarding views)
GymSyncApp/GymSyncTests/PersonalRecordTests.swift          # Task 2
GymSyncApp/GymSyncTests/GymRepositoryTests.swift           # Task 7
GymSyncApp/GymSyncTests/StatDerivationTests.swift          # Task 5/6 (week bucketing, tile math)
```

---

### Task 1: Interaction hygiene — all 10 audit defects

**Files:** Modify `Features/Sessions/GroupSessionLiveView.swift`, `Features/Sessions/CompletedSessionView.swift`, `Features/Onboarding/UsernameView.swift`, `Features/Sessions/LobbyView.swift`, `Features/Sessions/ProposalCardView.swift`, `Features/Social/ChatView.swift`.

**Source:** Audit §5 (DEFECT-1 … DEFECT-10) — read it in full; it has file:line + evidence for every defect. Dossier §B.6 confirms all three GS button styles already apply `.contentShape(Rectangle())`.

Contract (per defect):
- DEFECT-1 (End-Session X, GroupSessionLiveView:368): keep 30×30 visual box, wrap hit area to 44×44 (`.frame(width: 44, height: 44).contentShape(Rectangle())` outside the visual overlay).
- DEFECT-2 (pencil, CompletedSessionView:150): same pattern — visual unchanged, hit area ≥44.
- DEFECT-3 (username suggestion chips): `.frame(minHeight: 44)` + `.contentShape(Rectangle())`; visual padding may stay.
- DEFECT-4 (Edit Routine, LobbyView:546): add `.contentShape(Rectangle())` + `.frame(minHeight: 44)`.
- DEFECT-5 (Veto/Approve, ProposalCardView:52-76): `.frame(minHeight: 44)` on both labels + `.contentShape(Rectangle())`; horizontal padding unchanged.
- DEFECT-6 (mic, ChatView:249): bump frame to 44×44; guard the `pressing:` closure body with `guard !isSendingVoice else { return }`; add `.opacity(isSendingVoice ? 0.4 : 1)` for disabled affordance. Do NOT convert to Button (hold gesture is the interaction).
- DEFECT-7 (Check In, LobbyView:605): add `.contentShape(Rectangle())` (button is visually fine; only hit-testing broken).
- DEFECT-8 (solo End button): DEFERRED to Task 9 (rebuilt with the elapsed timer).
- DEFECT-9 (tab bar): DEFERRED to Task 4.
- DEFECT-10 (Lock in & Start / Log Set & Pass): add `.contentShape(Rectangle())` to both.

No behavior changes; only hit-testing/sizing. Build + full test suite green in CI. Commit `fix(ui): 44pt tap targets + contentShape on hand-rolled buttons (audit DEFECT-1..7,10)`.

---

### Task 2: personal_records — migration, repository, wire into both detection sites

**Files:** Create `supabase/migrations/20260715000002_personal_records.sql`, `supabase/tests/personal_records_test.sql`, `Models/PersonalRecord.swift`, `GymSyncTests/PersonalRecordTests.swift`; Modify `Features/Workout/WorkoutSessionView.swift` (PR detection at :325-333), `Features/Sessions/GroupSessionLiveView.swift` (PR detection at :883-889).

**Interfaces (later tasks consume):**
```swift
struct PersonalRecord: Codable, Identifiable, Sendable {
    let id: UUID; let userID: UUID; let exerciseID: UUID
    let weight: Decimal; let reps: Int; let previousBest: Decimal
    let sessionID: UUID?; let achievedAt: Date
}
enum PersonalRecordRepository {
    static func record(exerciseID: UUID, weight: Decimal, reps: Int, previousBest: Decimal, sessionID: UUID?) async throws -> PersonalRecord
    static func recent(userID: UUID, limit: Int) async throws -> [PersonalRecord]   // desc by achieved_at
    static func countSince(userID: UUID, date: Date) async throws -> Int            // for "PRs this month" tile
}
```

Migration: table `personal_records` (columns matching the struct, snake_case, `achieved_at timestamptz default now()`, FK user_id→profiles ON DELETE CASCADE, exercise_id→exercises, session_id nullable→sessions ON DELETE SET NULL); RLS enabled; policies: SELECT/INSERT scoped `auth.uid() = user_id` (no UPDATE/DELETE policies — records are immutable); indexes on `(user_id, achieved_at desc)`.

pgTAP (follow `supabase/tests/comms_schema_test.sql` patterns — fixture-scoped counts, `throws_ok('42501')` for INSERT violations, row-count CTE for UPDATE/DELETE negatives): owner can insert+select own; outsider insert rejected 42501; outsider select returns 0 rows; UPDATE silently affects 0 rows (no policy).

Wire-in: at both detection sites, where `weight > priorMax` currently only flashes a toast, ALSO fire `try? await PersonalRecordRepository.record(...)` with `previousBest: priorMax` (best-effort — a PR record failure must never block set logging). In WorkoutSessionView additionally accumulate `@State private var sessionPRs: [PersonalRecord]` (Task 9's recap consumes it; store the returned record, or construct one locally if the insert failed).

Swift tests (live-DB pattern like `SessionRepositoryTests`): record→recent round trip; countSince boundary.

Apply migration via db push; run pgTAP; run Swift tests in CI. Commit `feat(pr): personal_records table + repository, recorded at both detection sites`.

---

### Task 3: Styling parity smalls

**Files:** Modify `Features/Library/LibraryTabView.swift`, `Features/Workout/LogSetSheet.swift`, `Features/Social/ChatView.swift`, `Features/Social/SocialTabView.swift`.

Contract:
- **Library segmented control** (Dossier §A.6): replace `Picker(.segmented)` with a custom two-option control matching the canvas spec exactly: `HStack(spacing: 0)`, wrapped in 1px `theme.divider` border, internal 1px divider, selected option = `theme.accent` fill + `theme.bg` text, unselected transparent, `padding(7px 12px)`, 13pt `GSFont.bodyMedium`, hugging content (`alignSelf flex-start` → do not expand full width), each option ≥44pt tap height via `.frame(minHeight: 44)` + `.contentShape(Rectangle())`. Binding target unchanged (same state the Picker drove).
- **LogSetSheet drag handle** (:45): `RoundedRectangle(cornerRadius: 2)` → `Rectangle()`.
- **ChatView** (:475): `RoundedRectangle(cornerRadius: 0)` → `Rectangle()`.
- **SocialTabView group rows** (Dossier §B — audit §2.6): add last-message preview line (13pt, `theme.neutral700`, single line, truncated) under the group name. Data: for each group in `myGroups()`, fetch the latest message (`ChatRepository` — find its fetch method and call with limit 1; run the per-group fetches concurrently in a task group; nil-safe → no preview line when group has no messages). Preview text: body for text kind, "📷 Photo" for image, "🎤 Voice message" for audio, body as-is for soundboard_echo/system kinds. PRESERVE unread badge + navigation.

CI green. Commit `feat(design): segmented control per canvas, zero-radius fixes, group row previews`.

---

### Task 4: Custom tab dock (DEFECT-9)

**Files:** Modify `App/RootView.swift` (MainTabView), `DesignSystem/GSComponents.swift` (add `GSTabBar`).

**Source:** Dossier §A.5 (exact canvas spec) + §B.8 (current structure).

Contract: replace system `TabView` with:
```swift
VStack(spacing: 0) {
    ZStack { /* switch appState.selectedTab { case .home: HomeView() ... } */ }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    GSTabBar(selection: $appState.selectedTab)
}
.ignoresSafeArea(.keyboard, edges: .bottom)
```
`GSTabBar`: `theme.bg` background, 2pt top border (`theme.divider`), 5 equal-flex items; OUTLINE SF Symbols (`house`, `book`, `person.2`, `chart.bar`, `person.crop.circle` — no `.fill`), 21pt icon, 10pt `GSFont.bold` label, `padding(.top, 8)`, bottom safe-area respected; active = `theme.accent`, inactive = `theme.text.opacity(0.45)`; each item full-height `Button` with `.contentShape(Rectangle())` and ≥44pt height.

Behavior notes: each tab's root view keeps its own `NavigationStack` (verify — if the NavigationStack currently lives outside the TabView, move it inside each case). Views ARE recreated on tab switch with this structure — verify each tab refetches via `.task` (they do; Dossier §B.4/§B.5) so no stale-blank states. Keyboard must not shove the dock up (ignoresSafeArea above). Chat/unread flows unaffected.

CI green. Commit `feat(design): custom GSTabBar dock replaces system TabView (DEFECT-9)`.

---

### Task 5: Home content model

**Files:** Modify `Features/Home/HomeView.swift`; add `GSStatTile` to `DesignSystem/GSComponents.swift`; Create `GymSyncTests/StatDerivationTests.swift` (shared with Task 6 — create here, Task 6 appends).

**Source:** Dossier §A.1 (exact canvas order/content) + §B.1/§B.4.

Contract — new layout order (canvas first, preserved behavior below):
1. Greeting (exists) — keep.
2. **Start Solo Workout** full-width `GSPrimaryButtonStyle` CTA (15pt, 14pt vertical padding). Action: opens the existing solo-workout entry — READ how Library/Workout currently starts a solo session (WorkoutSessionView init) and present a routine-picker sheet (list of `RoutineRepository.fetchAll` routines + "No routine" option) that pushes/presents `WorkoutSessionView` the same way the existing entry point does. Do not build a new session-start mechanism.
3. **PR card** (accent100 GSCard): latest `PersonalRecordRepository.recent(limit: 1)`; kicker "🔥 New personal record", title "{Exercise name} — {weight} lbs × {reps}", meta "Beat previous best by {weight - previousBest} lbs". Resolve exercise name via `ExerciseRepository`. Hide card entirely when no PRs.
4. **Today's routine card**: most-recently-used routine — derive from `SessionRepository.history(userID:, limit: 20)` first session with `routineID`, fetch via `RoutineRepository.fetch(id:)`; fallback: first of `fetchAll`; hide when none. Kicker "Today's routine", title = routine name, body = exercise names joined " · " (first 3, then "+N more"), meta "{n} exercises". Tapping it opens the same routine-picker→start flow preselected.
5. **Stat tile row** — 3 `GSStatTile`s: "Workouts this week" (count of `history()` sessions with completedAt in current week, Monday start, user's calendar), "Lifetime lbs" (profile.lifetimeVolumeLifted, compact-formatted e.g. "48.1k"), "PRs this month" (accent700 value; `PersonalRecordRepository.countSince(startOfMonth)`).
6. `GSDivider`, then EXISTING Upcoming Sessions section + Join with Code + Schedule Session — preserved verbatim (recorded deviation).

`GSStatTile(value: String, label: String, valueColor: Color? = nil)` — surface card, flex:1, value 20pt `GSFont.bold`, label 10pt `theme.neutral700`.

Stat derivations (week bucketing, compact number formatting) go in a small testable helper (e.g. `enum StatMath` in a new or existing Models file) with unit tests: week-boundary edges (Sunday/Monday), compact formatting (999→"999", 48_120→"48.1k", 1_200_000→"1.2M").

`refresh()` extends the existing best-effort parallel fetch. CI green. Commit `feat(design): home content model — solo CTA, PR card, routine card, stat tiles`.

---

### Task 6: Stats tab — weekly volume chart + Recent PRs

**Files:** Modify `Features/Stats/StatsTabView.swift`, `Models/SessionRepository.swift` (one new query), `GymSyncTests/StatDerivationTests.swift` (append).

**Source:** Dossier §A.2 + §B.1/§B.5.

Contract:
- New repository method: `static func recentSetLogs(userID: UUID, since: Date) async throws -> [SetLog]` — single query on set_logs filtered by user_id + logged_at >= since, excluding failed/penalty (mirror `exerciseHistory` filters).
- **Weekly volume card**: 6 bars = last 6 calendar weeks (current week last). Volume per week = Σ reps×weight from `recentSetLogs(since: 6 weeks ago)`, bucketed by week (reuse `StatMath` week logic; add `StatMath.weeklyVolumes(logs:weeks:calendar:) -> [Decimal]` with tests: logs spanning boundaries, empty weeks → 0). Bars: HStack gap 8, height 76, each bar `Rectangle()` flex-equal, height proportional to max (max week = 100%); weeks 1-5 `theme.neutral400`, current week `theme.accent`; zero-volume week renders 2pt floor bar. Axis: "W1".."W6" 9pt centered, current week `theme.accent700`, others `theme.neutral700`.
- **Recent PRs table**: `GSSectionHeader("Recent PRs")` + header row (Exercise / Best / Date, 11pt neutral700) + up to 5 rows from `PersonalRecordRepository.recent(limit: 5)`: name (resolve via the exercises already fetched), "{weight} lbs", short date ("Jul 10"). 1px divider between rows. Empty state: single muted line "No PRs yet — go set one."
- Hero card + existing per-exercise list + navigation preserved (hero stays; new cards slot between hero and the exercise list).

CI green. Commit `feat(design): stats — weekly volume bars + recent PRs table`.

---

### Task 7: GymRepository + You tab rebuild

**Files:** Create `Models/GymRepository.swift`, `GymSyncTests/GymRepositoryTests.swift`; Modify `Features/You/YouTabView.swift`, `DesignSystem/GSComponents.swift` (add `GSSettingsRow`).

**Source:** Dossier §A.3 (canvas You tab) + §B.5 (current state: NO profile wiring) + §B.9 (gyms schema + CheckInService.primaryGym).

**Interfaces:**
```swift
enum GymRepository {
    static func upsertPrimary(name: String, latitude: Double, longitude: Double, radiusMeters: Int) async throws -> Gym
    // If a primary gym exists: UPDATE it. Else INSERT with is_primary=true. (Unique index enforces one primary.)
}
struct GSSettingsRow: View {  // init(title: String, action: @escaping () -> Void)
    // full-width row: 14pt GSFont.bodyMedium title flush-left, trailing chevron.right 14pt,
    // padding(.vertical, 14) → ≥44pt, contentShape(Rectangle()), 1px divider bottom
}
```

You tab contract (canvas order):
1. **Avatar card** (centered GSCard): 60×60 `theme.accent` square with initials (from displayName else username, 20pt bold, `theme.bg` text); display name 18pt bold (fallback "@username"); muted "@{username} · Member since {MMM yyyy}" from `profile.createdAt`. Data: `appState.currentProfile`, refreshed via `ProfileRepository.refresh` in `.task`.
2. **Stat tiles** (2 × `GSStatTile`, 18pt values): "Lifetime volume" ("{compact} lbs"), "Workouts logged" (count of `SessionRepository.history(userID:, limit: 500)` — acceptable ceiling for now; note as future aggregate).
3. `GSSectionHeader("Settings")` + rows: **Home Gym** (opens the gym editor sheet — Task 8 builds `HomeGymSetupView`; this task lands the row wired to a placeholder sheet showing current `CheckInService.primaryGym()` name or "Not set" — Task 8 replaces the placeholder), **Apple Health Sync** (row shows current authorization state as trailing text instead of chevron; tap calls `HealthKitBridge.requestPermission()` and refreshes state), **Theme** row (existing, restyled as a GSSettingsRow-shaped static row — recorded deviation). Edit Profile + Notifications rows OMITTED (recorded deviation).
4. **Sign Out**: full-width, centered label (canvas exception to flush-left — `justify-content:center` explicit in canvas), `theme.accent700` text, secondary border — reuse/promote the private `GSSecondarySignOutButtonStyle` (Dossier §B.6) or inline the treatment; pinned toward bottom.

GymRepositoryTests (live-DB): upsert creates then updates (same row id), radius respected.

CI green. Commit `feat(design): you tab — avatar card, stat tiles, settings rows; GymRepository`.

---

### Task 8: Onboarding — Set your home gym + You're set

**Files:** Create `Features/Onboarding/HomeGymSetupView.swift`, `Features/Onboarding/WelcomeView.swift`; Modify `Features/Onboarding/OnboardingCoordinator.swift`, `Features/Onboarding/UsernameView.swift` (step label), `Features/You/YouTabView.swift` (swap placeholder sheet → `HomeGymSetupView`).

**Source:** Dossier §A.7 (both screens, exact content) + §B.9 (gyms/CheckInService/LocationOneShotHelper).

Contract:
- **UsernameView**: "STEP 2 OF 2" → "STEP 2 OF 3", third pip added (audit §2.4).
- **HomeGymSetupView** (STEP 3 OF 3, 3 pips): heading "Set your home gym" 28pt + muted subtext per canvas. Body: MapKit `Map` (230pt tall, 1px divider border) centered on user location (request via the existing one-shot location helper; fallback: a continental-US default region) — user pans; gym location = map center; fixed center pin overlay (accent `mappin` 30pt) + translucent accent geofence circle (120pt, 2px accent border) — both static overlays over the map (canvas draws them centered; live map pans underneath). Below: GSCard row with a gym-name `TextField` (placeholder "Gym name", 15pt bold) + meta line "check-in radius 200 m". Footer: `Skip` (GSGhostButtonStyle) + `Set Home Gym` (GSPrimaryButtonStyle, flex) side-by-side, both ≥44pt. Set Home Gym: requires non-empty name; calls `GymRepository.upsertPrimary(name:, latitude:, longitude:, radiusMeters: 200)`; both buttons advance to WelcomeView. Handle location-permission denial: map shows default region, flow still completable (gym = map center).
- **WelcomeView** ("You're set", canvas screen 4): 60×60 accent square + `checkmark` 30pt; `You're in,\n@{username}.` 40pt bold; muted subtext per canvas; two shortcut rows (1px border box, icon + title/subtitle + chevron, ≥44pt): "Build your first routine" → sets `appState.selectedTab = .library` then completes onboarding; "Add your friends" → `.social` then completes. Footer: "Enter Gym Sync" GSPrimaryButtonStyle (centered label per canvas `justify-content:center`) → completes onboarding (sets `appState.currentProfile = profile` — the existing completion mechanism in OnboardingCoordinator; READ it and preserve exactly).
- **OnboardingCoordinator**: username → HomeGymSetupView → WelcomeView → complete. Profile creation stays where it is today (after username); the coordinator threads the created `Profile` through to WelcomeView for the handle + completion.
- **YouTabView**: Home Gym row now presents `HomeGymSetupView` in a sheet (reused; footer inside the sheet reads Skip → "Cancel" via an `isOnboarding: Bool = true` init flag; when false, Set Home Gym dismisses the sheet instead of advancing).
- project.yml: no changes needed (sources auto-globbed) — verify build.
- `NSLocationWhenInUseUsageDescription` already present (Dossier — Info.plist). MapKit import needs no entitlement.

CI green. Commit `feat(onboarding): home gym setup + welcome screens; you-tab gym editor`.

---

### Task 9: Solo workout — elapsed timer, End button, full canvas recap

**Files:** Modify `Features/Workout/WorkoutSessionView.swift`.

**Source:** Dossier §A.4 (exact recap spec), §B.7 (current completionCard/endSession), §B.10 (data availability), §B.3 (HealthKitBridge). DEFECT-8 from audit §5.

Contract:
- **Nav bar during workout**: leading/principal elapsed timer `Text(startedAt, style: .timer)` (14pt `GSFont.bold`) — state-driven, ZERO Swift Timers (same pattern as the 3b chess clock); trailing **End** button restyled as a bordered secondary treatment (GSSecondaryButtonStyle-like compact: 1px accent border, 13pt, `.frame(minHeight: 44)` hit area).
- **endSession()**: capture health-export outcome — `@State healthSynced: Bool` set true only when `exportWorkout` did not throw (change `try?` to do/catch around the export ONLY; permission failure or export failure → false; never block completion). Also capture `completedSession` (has completedAt) and keep `loggedSets`.
- **Recap rebuild** (replaces completionCard, matching Dossier §A.4 exactly):
  1. Header: "Workout Complete" 14pt bold + trailing share button (30×30 visual, 44pt hit area) using `ShareLink` with a text summary ("Push Day — 42:06, 7,240 lbs, 10 sets").
  2. Accent hero: routine-name kicker (uppercase, 10pt, or "SOLO WORKOUT" when no routine); duration hero 52pt (`completedAt - startedAt`, "m:ss" / "h:mm:ss"); subline "{weekday, month day} · solo"; 3-cell stat row — TOTAL LBS (`HealthKitBridge.totalVolume(from: loggedSets)`, compact-formatted), SETS (non-penalty count), PR (`sessionPRs.count` from Task 2).
  3. PR celebration card (accent100, only when `sessionPRs` non-empty; show the heaviest): kicker "🔥 New personal record", title "{Exercise} — {weight} lbs × {reps}", meta "▲ Beat previous best by {delta} lbs" accent700.
  4. "By exercise" breakdown: group `loggedSets` (excluding penalty) by exerciseID preserving first-logged order; row: exercise name 14pt bold + "{n} sets · top {w} × {r}" 11pt muted; `GSTag("PR", style: .accent)` trailing on exercises present in `sessionPRs`; 1px dividers between.
  5. Apple Health card (only when `healthSynced`): row card — accent `plus.circle` icon, "Synced to Apple Health" 13pt bold, meta "{duration} min · {sets} sets" (canvas shows kcal; we don't compute kcal — use sets; recorded deviation).
  6. Sticky footer: **Done** GSPrimaryButtonStyle, centered label, 15pt — dismisses as today.
- All data already in view state (Dossier §B.10) — no new queries.

CI green. Commit `feat(workout): elapsed timer, bordered End, full canvas recap (DEFECT-8)`.

---

### Task 10: Ship

- [ ] Full pgTAP suite green (`node scripts/run_pgtap.js`), CI green on branch.
- [ ] Final whole-branch review (opus, review-package from merge-base with master) — include the Minor-findings roll-up from per-task reviews.
- [ ] `gh pr create --base master --title "Design parity 1: interaction fixes + canvas gap closure"` with audit-linked summary.
- [ ] Merge (auto-TestFlight) per user's standing authorization for this iteration.

---

## Self-Review Notes

- Spec coverage: all 10 audit defects have a task (1, 4, 9); all buildable §2 deviations (2.1-2.9) covered by Tasks 3,5,6,7,9; §4 unbuilt inventory covered except notification prefs/PTT/palette (design-blocked, sent to designer) and CompletedSessionView/SeriesEditor/ActivityFeed designs (undesigned — designer will supply; audit §3 items stay as-is).
- Type consistency: `PersonalRecord`/`PersonalRecordRepository` (Task 2) consumed by Tasks 5, 6, 9 with matching signatures; `GSStatTile` (Task 5) consumed by Task 7; `StatMath` (Task 5) consumed by Task 6; `GymRepository` (Task 7) consumed by Task 8.
- Deliberate deviations from canvas are enumerated in Global Constraints so reviewers don't flag them as spec violations.
- Contract-style tasks match this repo's established plan style (design-adoption plan precedent); the dossier carries the exact values.
