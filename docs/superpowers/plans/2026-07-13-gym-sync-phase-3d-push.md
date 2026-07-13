# Gym Sync — Phase 3d: Push Notifications Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** APNs push notifications for the spec's event matrix (§6.3): device registration, per-category preferences, DB-driven event outbox, cron events (15-min reminder, idle ladder, 6h abandon), a `push-dispatcher` Edge Function, permission-priming + preferences UI, and notification action buttons.

**Architecture:** Outbox pattern. Postgres triggers and pg_cron enqueue rows into `push_queue`; a single `push-dispatcher` Edge Function (Deno) drains the queue on a 1-minute cron (pg_cron → pg_net http_post), joins device tokens + preferences, signs an ES256 APNs JWT, and POSTs to APNs HTTP/2. The app registers tokens into `push_devices` and handles `UNUserNotificationCenter` categories/actions.

**Tech stack additions:** Supabase Edge Functions (first in project — CI deploy job added), `pg_cron` + `pg_net` extensions, Deno tests.

**Reference:** `.superpowers/push-dossier.md` (cited as "Dossier §X") — spec quotes, existing trigger insertion points, infra gaps. The dossier is the plan's factual source; consult the spec only if the dossier is ambiguous.

## Global Constraints

- Spec event table (Dossier §A.3) is authoritative. **3d scope = 10 events**: friend_request, session_invite, session_reminder_15min, session_lobby_open, your_turn, partner_pr, lateness_chirp, session_idle_30min, session_idle_60min, chat_mention. **Deferred with their features** (recorded): leaderboard_passed → Phase 4; streak pushes → Phase 6; venue joins → Phase 8. The preferences UI ships all 10 designer categories (its "Leaderboard changes" toggle persists but gates nothing until P4).
- **Migrations append-only; next free timestamp `20260716000001`.** Apply ONLY via `export $(grep -v '^#' .env.local | xargs) && npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`. pgTAP via `node scripts/run_pgtap.js` (all files must pass).
- pgTAP conventions: fixture-scoped counts, `throws_ok('42501')` for INSERT policy violations, row-count CTEs for silent RLS filtering.
- App code: GSTheme/GSFont tokens, zero-radius, flush-left rows, 44pt+contentShape, centered commit-CTAs, no Timers (state-driven), no print(), no force-unwraps. Audio-session files untouchable.
- Git: branch `feature/phase-3d-push`; specific-file `git add`; CI green per task (`gh run list --branch feature/phase-3d-push`); PR `--base master` at the end.
- **User-action dependencies (Task 0 — may land mid-phase):** APNs .p8 key (manual portal step) and `SUPABASE_ACCESS_TOKEN` (Supabase PAT). Tasks 1–2 and 5–6 have NO dependency on them. Task 3's deno tests mock APNs (no key needed). Only Task 4's deploy job and Task 7's live E2E need the real credentials.
- Recorded assumptions: priming screen is an UNNUMBERED onboarding interstitial between Home Gym and Welcome (no pip renumbering); preferences toggles use system `Toggle` tinted `theme.accent` (designer left it open); `aps-environment: development` in entitlements (App Store distribution signing rewrites to production; dispatcher targets `api.push.apple.com` since TestFlight uses production APNs).

## File Structure

```
supabase/migrations/20260716000001_push_schema.sql        # T1: push_devices, notification_prefs, push_queue, enqueue triggers
supabase/migrations/20260716000002_push_cron.sql          # T2: pg_cron+pg_net, last_activity_at, reminder/idle/abandon enqueuers, drain schedule
supabase/tests/push_schema_test.sql                       # T1
supabase/tests/push_cron_test.sql                         # T2
supabase/functions/push-dispatcher/index.ts               # T3
supabase/functions/push-dispatcher/apns.ts                # T3 (JWT + HTTP/2 client, injectable fetch)
supabase/functions/push-dispatcher/test.ts                # T3 (deno test, mocked APNs)
supabase/functions/_shared/                               # T3 if needed
.github/workflows/backend.yml                             # T4: deno-test job + deploy job
GymSyncApp/GymSync/App/AppDelegate.swift                  # T5
GymSyncApp/GymSync/Services/PushReceiver.swift            # T5
GymSyncApp/GymSync/Models/PushDeviceRepository.swift      # T5 (+ NotificationPrefsRepository)
GymSyncApp/GymSync/Features/Onboarding/PushPrimingView.swift   # T6
GymSyncApp/GymSync/Features/You/NotificationPreferencesView.swift # T6
Modified: GymSyncApp.swift, OnboardingCoordinator.swift, YouTabView.swift, project.yml (T5/T6)
GymSyncApp/GymSyncTests/PushRegistrationTests.swift       # T5
```

---

### Task 0: User actions (tracked, not blocking Tasks 1–3/5–6)

- [ ] USER: create an APNs Auth Key at developer.apple.com → Certificates, Identifiers & Profiles → Keys → "+" → enable Apple Push Notifications service → download the `.p8` ONCE → save to `G:/Projects/Keys/GymSync/` → report the 10-char Key ID. (Dossier §B.2: not possible via API.)
- [ ] USER: create a Supabase personal access token (supabase.com → account → Access Tokens) → add `SUPABASE_ACCESS_TOKEN=<token>` to `.env.local`. Controller then runs `gh secret set SUPABASE_ACCESS_TOKEN` and `npx supabase secrets set` for the APNs vars (Task 7).
- [ ] USER (optional): confirm `AuthKey_RVND9TW64Y.p8` is the old App-Manager ASC key (memory says yes) — if so it can be revoked; it is NOT used by this plan.

---

### Task 1: Push schema — devices, preferences, outbox, event triggers

**Files:** Create `supabase/migrations/20260716000001_push_schema.sql`, `supabase/tests/push_schema_test.sql`.

**Interfaces (later tasks consume):**
- `push_devices(id uuid pk default, user_id uuid → profiles cascade, apns_token text unique not null, last_seen_at timestamptz default now())`; RLS: owner-only ALL (Dossier §A.2).
- `notification_prefs(user_id uuid → profiles cascade, category text, enabled boolean not null default true, updated_at timestamptz default now(), PK(user_id, category))`; category CHECK in the 10 designer categories + 'leaderboard_passed'; RLS owner-only ALL. Absence of a row = enabled (default-on per spec).
- `push_queue(id bigint identity pk, user_id uuid → profiles cascade, event text not null, payload jsonb not null default '{}', created_at timestamptz default now(), sent_at timestamptz, attempts int not null default 0)`; RLS: NO client policies (service-role only — clients never read/write the queue); index on (sent_at) WHERE sent_at IS NULL.
- SQL helper `enqueue_push(p_user uuid, p_event text, p_payload jsonb)` SECURITY DEFINER — inserts unless a `notification_prefs` row exists with enabled=false for the event's category, and never enqueues to the acting user themselves where the event semantics exclude self (callers pass correct recipients).
- Event triggers (find exact insertion points in Dossier §B.3; read the named migrations before writing):
  - `friend_request`: AFTER INSERT ON friendships WHERE status='pending' → recipient.
  - `session_invite`: AFTER INSERT ON session_participants (inviter ≠ invitee; skip organizer's own row) → invitee, payload {session_id, organizer name if cheap}.
  - `session_lobby_open`: AFTER UPDATE OF state ON sessions when new state='lobby_open' → all participants except those already checked-in/present.
  - `your_turn`: AFTER UPDATE OF current_turn_user_id ON sessions → the new turn holder (skip NULL).
  - `partner_pr`: AFTER INSERT ON chat_messages WHERE kind='system_pr' → group members except the PR author (Dossier §B.3: announce_pr already fans out the chat rows — enqueue per recipient here, dedupe by author).
  - `lateness_chirp`: AFTER UPDATE OF check_in_state ON session_participants when new state='late' → other participants.
  - `chat_mention`: AFTER INSERT ON chat_messages (kind='text') — parse body for `@username` tokens, match group members case-insensitively (reuse the lower(username) convention), enqueue per mentioned member except author.
- pgTAP (≥10 assertions): owner-only RLS on push_devices/notification_prefs (insert/select allow, outsider 42501/0-rows); push_queue client SELECT returns 0 rows + INSERT 42501; each trigger enqueues the right recipient(s) (fixture-scoped counts); prefs opt-out suppresses enqueue; mention parsing (one mention, multi-mention, no self-mention, non-member @name ignored).

Apply via db push; full pgTAP suite green; CI (Backend) green. Commit `feat(push): schema — devices, prefs, outbox queue, event triggers`.

---

### Task 2: Cron events — reminders, idle ladder, abandon, queue drain schedule

**Files:** Create `supabase/migrations/20260716000002_push_cron.sql`, `supabase/tests/push_cron_test.sql`.

Contract:
- `CREATE EXTENSION IF NOT EXISTS pg_cron; CREATE EXTENSION IF NOT EXISTS pg_net;` (Supabase-hosted supports both).
- `sessions.last_activity_at timestamptz` + update triggers: on set_logs INSERT (session's row), on chat_messages INSERT for the session's group while session in_progress (join via sessions.group_id), plus RPC `touch_session_activity(p_session uuid)` SECURITY DEFINER for the client foreground heartbeat (Dossier §A.4 activity definition; soundboard broadcasts are DB-invisible — heartbeat covers them).
- SQL function `enqueue_scheduled_pushes()` run every minute by pg_cron:
  - reminder: sessions with `scheduled_for` in [now()+14min, now()+15min) and state='scheduled' → enqueue `session_reminder_15min` to all participants (idempotent: guard with a `reminded_at` column or NOT EXISTS on push_queue for that session+event+user).
  - idle 30: in_progress sessions with last_activity_at < now()-30min, not already flagged (add `idle_30_notified_at`/`idle_60_notified_at` columns; "Still Going" resets both + last_activity_at) → organizer.
  - idle 60: analogous → all participants.
  - abandon: in_progress with last_activity_at < now()-6h → state='abandoned', completed_at=last_activity_at (Dossier §A.4; use the engine GUC pattern to pass state guards if any).
- `cron.schedule('push-drain', '* * * * *', $$ SELECT net.http_post(url:='<SUPABASE_URL>/functions/v1/push-dispatcher', headers:=jsonb_build_object('Authorization','Bearer '||current_setting('app.settings.service_key', true), 'Content-Type','application/json'), body:='{}') $$)` — IMPORTANT: don't hardcode the service key in the migration; use Supabase Vault (`vault.decrypted_secrets`) or `app.settings` GUC seeded out-of-band; document the chosen mechanism in the migration comments and in the report. Also `cron.schedule('push-enqueue','* * * * *', $$SELECT enqueue_scheduled_pushes()$$)`.
- pgTAP: T-31min idle fixture → organizer queue row (spec-mandated test, Dossier §A.6); T-61min → all participants; 6h → state abandoned + completed_at=last_activity_at; reminder window enqueues once (re-run function → no duplicate); heartbeat RPC updates last_activity_at; NULL scheduled_for sessions never enqueue reminders.
- NOTE: pg_cron jobs run in prod immediately — the drain URL will 404 until Task 7 deploys the function; net.http_post failures are async and harmless, but verify no error tables fill unboundedly (pg_net keeps a response table — set `cron.schedule` for pg_net cleanup or note Supabase's default retention).

Apply, pgTAP green, CI green. Commit `feat(push): pg_cron enqueuers — reminders, idle ladder, abandon; drain schedule`.

---

### Task 3: push-dispatcher Edge Function + deno tests

**Files:** Create `supabase/functions/push-dispatcher/index.ts`, `apns.ts`, `test.ts` (+ `deno.json` if needed).

Contract:
- Handler (service-role protected: reject unless `Authorization` bearer equals `SUPABASE_SERVICE_ROLE_KEY` env — the cron drain and manual invocations use it):
  1. Claim up to 100 unsent queue rows (`UPDATE ... SET attempts = attempts+1 WHERE id IN (SELECT id FROM push_queue WHERE sent_at IS NULL AND attempts < 5 ORDER BY id LIMIT 100 FOR UPDATE SKIP LOCKED) RETURNING *` via service-role Postgres REST or direct SQL over `postgres` deno driver — pick the simpler supabase-js service client `.rpc()` route: add a `claim_push_batch(n int)` SECURITY DEFINER SQL function in the SAME task via migration `20260716000003_claim_push_batch.sql` if REST can't express it atomically).
  2. Join `push_devices` for each row's user (skip users with no devices; mark sent).
  3. Build APNs payload per event (title/body/category map — copy strings from Dossier §A.3 examples; category ids: `FRIEND_REQUEST`, `SESSION_INVITE`, `SESSION_VIEW`, `OPEN_LOBBY`, `OPEN_SESSION`, `ROAST`, `IDLE_ACTIONS`; thread-id = session_id/group_id where present).
  4. `apns.ts`: ES256 JWT (kid=APNS_KEY_ID, iss=APNS_TEAM_ID, cached ≤50min), POST `https://api.push.apple.com/3/device/{token}` with `apns-topic: app.gymsync.ios`, `apns-push-type: alert`. Deno's fetch speaks HTTP/2. On 410/`BadDeviceToken`: delete that push_devices row. On 429/5xx: leave row unsent (attempts already bumped) for retry next drain.
  5. Env: `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (p8 PEM), `APNS_TOPIC`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` (auto-injected by platform).
- `apns.ts` takes an injectable `fetch` — `test.ts` (pure `deno test`, NO network): payload map per event (assert exact title/body/category for all 10 events — spec test hook Dossier §A.6), JWT header/claims shape (decode, don't verify sig), 410 → device-delete call recorded, retry rows left unsent, batch respects prefs already filtered at enqueue (dispatcher does NOT re-check prefs — document).
- Local verification: `deno test` must pass locally (deno is installable via scoop/winget if absent — or run in CI only; if local deno is unavailable, say so and rely on the Task 4 CI job you build FIRST in that case).

Commit `feat(push): push-dispatcher edge function — APNs ES256, queue drain, deno tests`. (No deploy yet — Task 7.)

---

### Task 4: CI — deno tests + functions deploy job

**Files:** Modify `.github/workflows/backend.yml`.

Contract: two additions, both path-gated on `supabase/functions/**`:
- `deno-test` job: `denoland/setup-deno@v2` (v1.x pin ok) + `deno test --allow-none supabase/functions/push-dispatcher/` (adjust flags to what the tests need — they must need NO network/env).
- `deploy-functions` job: only on `push` to master; `supabase/setup-cli@v1` + `supabase functions deploy push-dispatcher --project-ref $SUPABASE_PROJECT_REF` with `SUPABASE_ACCESS_TOKEN` from secrets. **Guard**: `if: github.ref == 'refs/heads/master' && github.event_name == 'push'` plus step-level check that the secret exists (skip with a notice if not yet configured — Task 0 may lag).
- Do NOT touch the pgtap job. Backend CI green on the branch (deno-test runs; deploy skipped off-master). Commit `ci(backend): deno tests + functions deploy job`.

---

### Task 5: App — registration, delegate, actions, deep-link routing

**Files:** Create `App/AppDelegate.swift`, `Services/PushReceiver.swift`, `Models/PushDeviceRepository.swift` (+ NotificationPrefsRepository in the same file or `Models/NotificationPrefs.swift`); Modify `App/GymSyncApp.swift` (`@UIApplicationDelegateAdaptor`), `GymSyncApp/project.yml` (entitlements `aps-environment: development`), Test `GymSyncTests/PushRegistrationTests.swift`.

Contract:
- `PushReceiver` (@MainActor, @Observable): `authorizationStatus` (refreshed via notification center), `requestAuthorization() async -> Bool` (alert+sound+badge), `registerTokenIfAuthorized()` (calls `UIApplication.shared.registerForRemoteNotifications()`), token callback → `PushDeviceRepository.upsert(token:)` (hex-encode Data; upsert on apns_token, update last_seen_at; on sign-out DELETE own device rows — hook SupabaseService.signOut or AuthService equivalent — READ how sign-out flows first).
- `AppDelegate`: `didRegisterForRemoteNotificationsWithDeviceToken` → PushReceiver; `UNUserNotificationCenterDelegate`: `willPresent` — suppress banner (`[]`) when the notification's thread/session matches the currently open live session or chat (expose "current context" via AppState — simple optional `activeSessionID`/`activeChatGroupID` set by GroupSessionLiveView/ChatView on appear/disappear; Dossier §B.7); otherwise `.banner .sound`. `didReceive response`: route by category/action —
  - Default tap: set `appState.selectedTab` + a new lightweight `pendingRoute` on AppState (enum: lobby(sessionID), session(sessionID), chat(groupID), friends) that HomeView/SocialTabView consume in `.task`/onChange (minimal deep-link v1 — implement consumption for lobby + chat + friends; session routes to Home tab lobby list if direct push isn't trivial — document).
  - `IDLE_ACTIONS` Wrap Up / Still Going: background call WITHOUT app launch — register `UNNotificationAction` non-foreground; handler calls new RPCs `wrap_up_session(p_session)` / `still_going(p_session)` via a plain URLSession POST to PostgREST `rpc/` endpoints with the stored anon key + user access token — READ how supabase-swift exposes the current access token; if token access is awkward from the notification handler, fall back to `.foreground` actions opening the app and executing — RECORD the choice. (RPCs: add migration `20260716000004_idle_rpcs.sql`: wrap_up sets completed_at=last_activity_at & state='completed' (participant-gated); still_going resets last_activity_at + clears idle-notified flags; pgTAP 4 cases appended to push_cron_test or new file.)
  - Friend Accept/Decline actions: call the existing friendship accept/decline path (FriendRepository — read it) as non-foreground actions.
- Notification categories registered at launch with the ids Task 3 emits.
- Onboarding heartbeat: GroupSessionLiveView (or SessionLiveService) calls `touch_session_activity` on scenePhase active while in a session (Dossier §A.4 "app foreground >5s" — a single call on active is acceptable v1; no timers).
- `PushRegistrationTests`: hex-encoding of token data; PushDeviceRepository upsert round-trip (live-DB pattern); prefs repository round-trip (set false → read false; delete → default true).
- project.yml entitlement addition; verify XcodeGen still generates (CI proves).

CI (iOS) green. Commit `feat(push): registration, delegate, action categories, deep-link routing`.

---

### Task 6: UI — priming interstitial + preferences screen + You-tab row

**Files:** Create `Features/Onboarding/PushPrimingView.swift`, `Features/You/NotificationPreferencesView.swift`; Modify `Features/Onboarding/OnboardingCoordinator.swift`, `Features/You/YouTabView.swift`.

Contract (designer brief Feature 1+2, Dossier §A.7 — read the mic priming proof `G:/Projects/Midas/gs-proofs/p32-priming.jpeg` as the visual pattern; bell variant not yet designed — reuse the frame with `bell.badge` SF symbol, recorded assumption):
- PushPrimingView states: pre-prompt (headline "Never miss your turn on the bar", 3 benefit bullets exactly per brief, GSPrimary "Turn on notifications" → `PushReceiver.requestAuthorization()` then advance; ghost "Not now" → advance), granted (auto-advance silently), denied (headline "Notifications are off" + "Open Settings" deep-link via UIApplication.openSettingsURLString; no "Not now" in onboarding — but back button visible in You-tab re-entry mode). `isOnboarding` flag like HomeGymSetupView's pattern.
- OnboardingCoordinator: gym → **priming** → welcome (unnumbered interstitial; skip entirely if authorization already determined).
- NotificationPreferencesView (nav-pushed): 10 toggle rows (labels verbatim from the brief's table), grouped with GSSectionHeader if natural; system `Toggle` tinted accent; header note "All on by default"; system-denied state shows banner + "Open Settings" (prefs still persist per brief); rows read/write via NotificationPrefsRepository (absent row = on; toggling off inserts enabled=false; toggling on may upsert true or delete — pick one, document).
- YouTabView: `GSSettingsRow(title: "Notifications")` after healthSyncRow → NavigationLink/pushed NotificationPreferencesView (this is the priming re-entry point when denied: preferences screen shows the denied banner — matches brief).
- 44pt targets, tokens, zero-radius throughout.

CI green. Commit `feat(push): priming interstitial + notification preferences UI`.

---

### Task 7: Wire-up, deploy, E2E (needs Task 0 credentials)

- [ ] Controller: `gh secret set SUPABASE_ACCESS_TOKEN` from `.env.local`; `npx supabase secrets set APNS_KEY_ID=... APNS_TEAM_ID=299EBDGH62 APNS_TOPIC=app.gymsync.ios APNS_PRIVATE_KEY="$(cat .../AuthKey_<ID>.p8)"` (needs access token env).
- [ ] Deploy: `npx supabase functions deploy push-dispatcher --project-ref $SUPABASE_PROJECT_REF` (or merge → CI deploy job does it).
- [ ] Seed the drain URL/service-key mechanism chosen in Task 2 (Vault secret / GUC) — document exact commands in the report.
- [ ] Smoke: insert a synthetic push_queue row for the CI test user via SQL, run dispatcher manually (`curl` with service key), verify row marked sent and APNs returns 400 BadDeviceToken for a fake token (proves the full path up to Apple).
- [ ] Device E2E (user): install TestFlight build, accept priming → token row appears; friend_request push from ci_test_user_2; your_turn during a live session; idle-30 Wrap Up action from lock screen (spec's manual checklist, Dossier §A.6).

### Task 8: Ship

- [ ] Full pgTAP + deno + iOS CI green; final whole-branch review (opus, review-package from merge-base, ledger Minor roll-up); `gh pr create --base master`; merge per standing authorization; watch deploy (TestFlight + functions deploy job).

---

## Self-Review Notes

- Spec coverage: all §6.3 events in 3d scope have an enqueuer (T1 triggers, T2 cron) and payload mapping (T3); action buttons T5; priming/prefs UI T6; test hooks from Dossier §A.6 all present (payload assert in deno, T-31min pgTAP, lock-screen Wrap Up in device E2E).
- Type/name consistency: category ids defined once (T3 list, registered in T5); `enqueue_push`/`claim_push_batch`/`touch_session_activity`/`wrap_up_session`/`still_going` defined where introduced and consumed by name elsewhere; NotificationPrefsRepository shared T5→T6.
- User-action isolation verified: T1/T2/T3/T5/T6 run with existing credentials; only T4's deploy step and T7 need Task 0 — the phase can build and review fully in parallel with the user's two 5-minute actions.
- Placeholder scan: none — every task carries exact schemas, event lists, and file paths; contract-style bodies match this repo's established plan style.
