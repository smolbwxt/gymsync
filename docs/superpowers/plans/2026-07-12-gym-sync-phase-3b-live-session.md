# Gym Sync — Phase 3b: Live Session (Chess Clock) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The in-session experience — round-robin chess clock, live partner set feed, penalty (burpee) logging, End Session with HealthKit write and recap, completed-session duration editing — plus the security/hygiene tickets accumulated during 3a/RS reviews.

**Architecture:** Two new SECURITY DEFINER RPCs make session mechanics atomic and race-safe: `start_session` (lateness + turn_order assignment + first turn + state flip in one transaction) and `advance_turn` (current-lifter-or-organizer gated, wraps by turn_order). A penalty-guard trigger closes the burpees-zeroing hole. `set_logs` joins the realtime publication (same-task rule). Client side: `SessionLiveService` (three streams on one channel) drives `GroupSessionLiveView`, whose chess clock is `Text(turnStartedAt, style: .timer)` — local render, no server tick, per spec §5.

**Tech Stack:** unchanged. Next free migrations: `20260714000001+`.

## Global Constraints

- All prior global constraints apply (RLS ± pgTAP patterns, SECURITY DEFINER helpers, fix-forward migrations, repository conventions, CI-verified Swift, publication-with-subscription rule).
- **Chess clock**: computed locally from `sessions.current_turn_started_at` — never a server tick, never a Swift Timer; use `Text(_:style: .timer)`.
- **Turn order**: assigned at start by `check_in_at ASC NULLS LAST, user_id ASC`; rotation wraps.
- **Penalty sets**: `set_logs.is_penalty = true`; excluded from PRs (already true in trigger) and from recap volume totals (client).
- **Solo flow untouched**: `WorkoutSessionView`/`startSolo` (Phase 1) stay as-is; `GroupSessionLiveView` is the multiplayer surface.
- Branch `feature/phase-3b-live-session`; `gh pr create --base master`. Standard CI loop on that branch.
- ⚠️ Concurrent design-agent UI work: keep view-file diffs additive where possible; new screens in NEW files.

## Explicitly deferred (do NOT build)

- Soundboard, in-session emoji reactions, voice messages (3c). Idle-detection ladder, all pushes incl. "your turn" (3d). Heart rate (Phase 5). Session sub-thread chat. Leaderboards/attempts (Phase 4). Supersets (v2).

## File Structure

```
supabase/migrations/
├── 20260714000001_session_engine_rpcs.sql     # Task 1 (start_session, advance_turn, penalty guard)
└── 20260714000002_live_plumbing.sql           # Task 2 (set_logs publication, no_show rejoin fix)
supabase/tests/
├── session_engine_test.sql                    # Task 1
└── live_plumbing_test.sql                     # Task 2
GymSyncApp/GymSync/
├── Services/SessionLiveService.swift          # Task 3
├── Services/ExerciseNameCache.swift           # Task 3
├── Models/SessionRepository.swift             # Task 3 (start→RPC, advanceTurn, sessionSets)
├── Features/Sessions/GroupSessionLiveView.swift   # Task 4 (replaces placeholder content)
├── Features/Sessions/SessionRecapView.swift   # Task 4
├── Features/Sessions/SessionInProgressView.swift  # Task 4 (thin: routes to GroupSessionLiveView)
├── Features/Sessions/LobbyView.swift          # Task 4 (unsubscribe on start-nav; exercise names)
├── Features/Sessions/CompletedSessionView.swift   # Task 5
└── Features/Social/GroupView.swift            # Task 5 (past rows navigate)
GymSyncApp/GymSyncTests/
└── SessionEngineTests.swift                   # Task 3
```

---

### Task 0: Branch

- [ ] `cd /g/Projects/GymSync && git checkout master && git pull --ff-only && git checkout -b feature/phase-3b-live-session`

---

### Task 1: Session engine RPCs + penalty guard

**Files:** Create `supabase/migrations/20260714000001_session_engine_rpcs.sql`; Test `supabase/tests/session_engine_test.sql`.

**Interfaces:**
- Consumes: `sessions` (3a shape incl. current_turn_*), `session_participants`, `evaluate_lateness` (kept, called internally).
- Produces:
  - `public.start_session(p_session_id uuid) RETURNS void` SECURITY DEFINER — organizer-only (`P0001 'only the organizer may start the session'`); requires state IN ('scheduled','lobby_open') (`P0001 'session cannot be started'` otherwise); atomically: lateness pass (inline UPDATE identical in effect to evaluate_lateness — call `evaluate_lateness` does NOT work inside since it re-checks auth: it checks organizer via auth.uid(), which is preserved inside the definer function → calling it IS fine; do call it), assign `turn_order` = row_number over (ORDER BY check_in_at ASC NULLS LAST, user_id ASC), set `current_turn_user_id` = turn_order 1, `current_turn_started_at = now()`, `state='in_progress'`, `started_at=now()`.
  - `public.advance_turn(p_session_id uuid) RETURNS uuid` SECURITY DEFINER — caller must be `current_turn_user_id` OR organizer (`P0001 'not your turn'`); session must be in_progress; sets `current_turn_user_id` to the next participant by turn_order (wrapping; skip participants with `check_in_state='no_show'`), `current_turn_started_at = now()`; returns the new current user id. Row-lock the session (`FOR UPDATE`) to serialize concurrent advances.
  - **Penalty guard**: BEFORE UPDATE trigger on `session_participants` — when `current_setting('request.jwt.claim.sub', true)` equals `OLD.user_id::text` AND the definer-bypass GUC is off (`current_setting('gymsync.engine', true) IS DISTINCT FROM 'on'`), RAISE (`P0001 'penalty fields are read-only'`) if `NEW.late_minutes/burpees_owed/turn_order` differ from OLD. `start_session`/`evaluate_lateness` set `PERFORM set_config('gymsync.engine','on', true)` first (fix-forward CREATE OR REPLACE of evaluate_lateness copying live body + one line).
- pgTAP scenarios (organizer A, participant B, both checked in; B late): non-organizer start fails P0001; organizer start → state in_progress, turn_orders 1&2 assigned by check-in order, current_turn = first, B's burpees computed; B (not current) advance_turn fails 'not your turn'; A (current) advance → returns B's id, current_turn_started_at advanced; B advance → wraps to A; B self-zeroing burpees via direct UPDATE fails P0001 'penalty fields are read-only'; B updating own check_in_state (non-penalty column) still succeeds (self-service check-in preserved). RECOUNT plan(N).
- Commit `feat(db): atomic session start + turn rotation RPCs, penalty-field guard`.

---

### Task 2: Live plumbing (set_logs publication + no_show rejoin)

**Files:** Create `supabase/migrations/20260714000002_live_plumbing.sql`; Test `supabase/tests/live_plumbing_test.sql`.

**Interfaces:**
- Produces: `ALTER PUBLICATION supabase_realtime ADD TABLE public.set_logs;` (Task 3 subscribes — same-task rule satisfied here since Task 3 is its consumer and this precedes it; the pair 2+3 is the unit). Fix-forward CREATE OR REPLACE `join_session_by_code` (copy live body from `20260712000005`): the `ON CONFLICT (session_id, user_id) DO NOTHING` becomes `DO UPDATE SET check_in_state='online', check_in_at=NULL, check_in_method=NULL WHERE session_participants.check_in_state='no_show'` (a no_show re-joining by code gets a clean slate; other states untouched via the WHERE).
- pgTAP: publication membership =1 for set_logs; rejoin scenario — participant marked no_show, calls join RPC with the room code → state flips to 'online'; a 'ready' participant re-joining stays 'ready'. RECOUNT plan(N).
- Commit `feat(db): set_logs realtime publication + no-show rejoin via room code`.

---

### Task 3: SessionLiveService + repository engine methods + ExerciseNameCache

**Files:** Create `Services/SessionLiveService.swift`, `Services/ExerciseNameCache.swift`; Modify `Models/SessionRepository.swift`; Test `GymSyncTests/SessionEngineTests.swift`.

**Interfaces:**
- Consumes: Tasks 1-2; `ChatRealtimeService`/`LobbyRealtimeService` patterns (READ both — decoder, stream-before-subscribe, teardown).
- Produces (Task 4 compiles against):
  - `SessionRepository.start(sessionID:)` REPLACED internally: now calls `client.rpc("start_session", params:)` (signature unchanged — LobbyView untouched).
  - `SessionRepository.advanceTurn(sessionID: UUID) async throws` (rpc advance_turn).
  - `SessionRepository.sessionSets(sessionID: UUID) async throws -> [SetLog]` — READ `Models/SetLog.swift` (Phase 1) for the model; ordered logged_at asc.
  - `SessionRepository.logSet(...)` — check whether Phase 1's set-logging goes through a repository (READ `Features/Workout/LogSetSheet.swift` + `Models/SetLog.swift`); reuse the existing insert path; if it's view-embedded, extract `SetLogRepository.insert(...)`-style function preserving the solo path.
  - `@MainActor final class SessionLiveService`: `subscribe(sessionID: UUID, onSessionChange: @escaping @MainActor (WorkoutSession) -> Void, onParticipantsChange: @escaping @MainActor () -> Void, onSetLogged: @escaping @MainActor (SetLog) -> Void) async` — one channel `session:{id}:live`; streams: sessions UPDATE (filter id, decodeRecord → WorkoutSession), session_participants ALL (filter session_id, coarse), set_logs INSERT (filter session_id, decodeRecord → SetLog); `unsubscribe() async`.
  - `enum ExerciseNameCache`: `static func name(for id: UUID) async -> String` + `preload() async` — single fetchAll-backed `[UUID: String]` (actor-safe via @MainActor static state or an actor; implementer's choice), fallback "Exercise".
- Tests (live DB, single actor): schedule ad-hoc self-only session → checkIn → `start` → refetch: state in_progress, my turn_order==1, currentTurnUserID==me; `advanceTurn` → still me (wraps single participant), currentTurnStartedAt advanced (>previous); direct PATCH of own burpees_owed via client → throws (guard); logSet on the session → sessionSets returns it; complete; cleanup. (Turn-denial and multi-user paths are pgTAP-covered.)
- Commit `feat: session engine service — live streams, turn rpcs, exercise names`; push; CI green.

---

### Task 4: GroupSessionLiveView (the chess clock)

**Files:** Create `Features/Sessions/GroupSessionLiveView.swift`, `Features/Sessions/SessionRecapView.swift`; Modify `SessionInProgressView.swift` (becomes a thin router to the new view), `LobbyView.swift` (unsubscribe before start-navigation; exercise names via ExerciseNameCache in routine card).

**Interfaces:**
- Consumes: everything from Task 3; `LogSetSheet` (READ — reuse for set entry); `HealthKitBridge` (READ how the solo flow writes the workout on completion — replicate on End Session); `currentSession` refetch + scenePhase patterns.
- Produces (contract):
  - `GroupSessionLiveView(session: WorkoutSession)`:
    - Header: routine name + session elapsed (`Text(startedAt, style: .timer)`).
    - **Turn card**: current lifter's username + avatar-initials + chess clock `Text(currentTurnStartedAt, style: .timer)` (updates when realtime delivers the sessions UPDATE — state-driven, no Timer). If it's MY turn: big "Log Set" button → LogSetSheet (exercise picker limited to the session routine's exercises via ExerciseNameCache + routine fetch; free choice if no routine) → on submit: insert set_log → `advanceTurn` → sheet dismiss. If not my turn: "Pass to me" hidden; organizer additionally gets "Skip turn" (advanceTurn as organizer).
    - **Penalty banner** (when my burpees_owed > 0): "You owe N burpees" + "Log burpees" button → LogSetSheet preset (exercise = seeded burpee if present else free pick, `is_penalty=true`); banner decrements display by summed penalty reps logged (client calc).
    - **Feed**: reverse-chronological set_logs (username · exercise name · reps×weight · 🔥 if that insert triggered a PR — approximate: match against chat system_pr payload optional; SIMPLER v1: omit PR flair in feed) — cap 30 rows, live-appended via onSetLogged.
    - **End Session** (any participant per spec): confirmation → `SessionRepository.complete` → HealthKit workout write (same call shape as solo flow) → present `SessionRecapView`.
  - `SessionRecapView(session:sets:participants:)` — per-participant totals (sets, volume Σ reps×weight excluding is_penalty, penalty reps separately), duration, dismiss-to-root button (`onDone` closure the presenter uses to pop).
  - `SessionInProgressView` keeps its name/signature (LobbyView navigates to it) but now just embeds `GroupSessionLiveView(session:)`.
  - LobbyView: before navigating on start, `await lobbyRealtime.unsubscribe()` (ticket); routine card rows show real exercise names via ExerciseNameCache (ticket).
- No new XCTests (UI): CI compile + suites green; device QA in Task 6.
- Commit `feat: live session — chess clock, turn rotation, set feed, penalties, recap`; push; CI green.

---

### Task 5: CompletedSessionView + duration edit

**Files:** Create `Features/Sessions/CompletedSessionView.swift`; Modify `Features/Social/GroupView.swift` (past rows navigate to it); Modify `Models/SessionRepository.swift` (add `editDuration`).

**Interfaces:**
- Consumes: `session_duration_edits` table (Phase 1, unused until now — READ `20260709000006` for columns), `sessions.duration_was_edited/edited_by` (3a columns), `sessionSets`.
- Produces:
  - `SessionRepository.editDuration(sessionID: UUID, newStartedAt: Date, newCompletedAt: Date, reason: String?) async throws` — inserts `session_duration_edits` audit row (old/new values, edited_by me), updates session (`started_at/completed_at/duration_was_edited=true/edited_by`). Editable by any participant (existing UPDATE policy covers; spec Flow 6). Validation: completed > started, both within ±48h of originals (`.validation` otherwise).
  - `CompletedSessionView(session: WorkoutSession)`: summary (duration + "✏️ edited" tag when flagged, per-participant set/volume totals reusing SessionRecapView internals — extract shared `SessionStatsList` if trivial, else duplicate 20 lines), Duration row with pencil → sheet (two DatePickers + reason field → editDuration → reload). HealthKit re-write on edit is deferred to 3c polish (note in code comment; spec wants it, ticket it).
  - GroupView past rows: NavigationLink → CompletedSessionView.
- Commit `feat: completed session detail with audited duration editing`; push; CI green.

---

### Task 6: Hygiene sweep + ship

**Files:** Modify `SessionSeries.swift` (DRY formatter — RS follow-up), migration `20260714000003_sessions_delete_parity.sql` (RS follow-up: member-gate the sessions DELETE policy) + extend `supabase/tests/session_engine_test.sql` or new small test.

> Input clamps deliberately DROPPED per user decision (2026-07-12): proposal set/rep inputs stay unclamped — outlandish proposals are the veto system's job, not the input field's.

- [ ] `20260714000003_sessions_delete_parity.sql`: DROP/CREATE `"organizer deletes own scheduled sessions"` adding `AND (sessions.group_id IS NULL OR public.is_group_member(sessions.group_id, auth.uid()))`; pgTAP: departed organizer cannot delete their old group session (CTE 0), solo (groupless) delete still works.
- [ ] DRY the `yyyy-MM-dd` formatter (single static in SessionSeries used by repository).
- [ ] `node scripts/run_pgtap.js` ALL PASSED; commit `chore: 3b hygiene — delete-policy parity, formatter DRY`; push; CI green.
- [ ] PR `--base master`: "Phase 3b: Live session — chess clock, turns, penalties, recap". Merge after review+CI (coordinate with design-agent work per controller).
- [ ] Device QA (controller drives ci_test_user_2; extend `scripts/qa_p3a.js` with `advance`/`logset` actions at QA time):
  1. Start with both ready → turn order by check-in, chess clock ticking, no Timer jank
  2. My turn → log set → turn flips to test user LIVE; their scripted advance flips back
  3. Test user's scripted set INSERT appears in my feed live (name + numbers)
  4. Late tester owes burpees → banner; log penalty burpees → excluded from volume
  5. Out-of-turn advance from script → 'not your turn' error surfaced
  6. Scripted PATCH of own burpees → blocked by guard
  7. End Session → HealthKit row on phone, recap totals correct, ✅ chat message
  8. Completed session in Group tab → duration edit → ✏️ tag + audit row
  9. Regression: solo workout, series scheduling, lobby flows

---

## Self-Review Notes (already applied)

- **Spec coverage (Flow 2 steps 6-9 + Flow 6 duration edit):** turn card/clock (T4), set feed (T3/4), penalties (T1 guard + T4 banner), End+HealthKit+recap (T4), duration edit + audit + leaderboard-lock note (T5 — leaderboards don't exist until Phase 4; only the ✏️ tag ships now). Idle ladder explicitly 3d.
- **Accumulated tickets closed:** burpees guard (T1), start transactionality (T1), no_show rejoin (T2), set_logs publication-with-subscription (T2+3), lobby unsubscribe on start-nav (T4), exercise-name lookups (T3/4), input clamps + sessions DELETE parity + formatter DRY (T6). Remaining open: signed-URL re-resolution, storage orphan cleanup (unchanged priority).
- **Type consistency:** `SessionLiveService.subscribe(onSessionChange:onParticipantsChange:onSetLogged:)` names used identically in T3 contract and T4 consumption; `advanceTurn`/`start_session` naming aligned SQL↔Swift.
- **Verbatim SQL deliberately omitted for T1/T2 function bodies** (they copy live bodies + specified deltas — same fix-forward pattern proven in RS Task 2); pgTAP scenarios are fully enumerated; migrations tasks remain TDD-gated.
