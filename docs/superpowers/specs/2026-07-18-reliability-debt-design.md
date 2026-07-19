# Phase O — Reliability + Accumulated Debt — Design

**Status:** approved scope (roadmap Phase O + the execution ledger's accumulated handoffs). This is a debt-retirement phase: no new product pillars; every item pre-adjudicated by a prior review or the roadmap.

## Components

### 1. DEFINER-helper security sweep (backend)
Relocate the remaining public-schema SECURITY DEFINER helpers into the locked `private` schema, per the established `is_blocked` pattern (`20260722000001` — REVOKEd schema, catalog-OID policy resolution, no PostgREST RPC endpoints). Queue in order: **`is_friend` FIRST** (relationship oracle — the worst exposure), then `is_session_participant`, `is_group_member`, `message_group_id`, `can_access_message`, `is_solo_session`, and (added by Phase H review) confirm `is_session_organizer`'s exposure class while in there. Each move: new migration (CREATE in private, repoint every dependent policy, DROP public version, restate grants), pgTAP re-proof of every dependent policy's behavior (positive+negative), full-suite regression run. Fix-forward doctrine; append-only.

### 2. Phase H handoff batch (8 items, ledgered at gate)
Calendar reconcile sweep on app-foreground (toggle-on + granted only: enumerate mapped session_ids, fetch states, remove events for cancelled/abandoned/deleted; absorbs the toggle race N-2, stale-reschedule N-3, just-past backfill N-5, and denied-window misses); batch/background the serial per-occurrence EventKit awaits (progress affordance or fire-and-forget post-dismiss); SeriesEditorView `routineExerciseCounts` threading; locale-safe Decimal parsing — ONE shared helper (`Decimal.parseUserInput` accepting both separators) adopted at the 3 submit surfaces; TrendChartView y-label parameterization (a11y correctness for body weight); plate-math deviation-entry touch-up (inline-card context); `replaceWorkout` deleted-0 log disambiguation. (GCal build prereqs stay gated on the user's OAuth consent — NOT this phase.)

### 3. Offline-first set logging (master spec §6.4)
SwiftData local store + pending-writes queue for set logs; client-generated UUID PKs already make retries idempotent; optimistic UI with a syncing indicator; 90-day cache window. Scope honestly: set logging only (the spec's stated surface), not a general offline layer.

### 4. Sentry crash reporting (master spec §6.8.5)
SDK + sanitized session-state snapshots. **Config-gated:** requires a Sentry project DSN. If no DSN exists in the secrets store at build time, land the integration behind a nil-DSN no-op (honest stub, zero runtime effect) and record the USER ACTION (create Sentry project, provide DSN).

### 5. 3e voice follow-up queue (canonical 8 items, priority order)
Sign-out bounded `leave()` timeout; chat mic gate during `.connecting`; join session-scope guard; muted-others roster rows; coach mark + "voice connected" toast + voice mixer sheet + transmit hero/80pt dock variant; Lobby↔Live back-nav rejoin blip; restore-helper DRY; SeriesEditorView device-tz picker residual.

### 6. Reliability/debt roll-up (plan-leakage audit list)
Storage orphan cleanup + signed-URL re-resolution (chat/avatars); tab-switch transient-state loss (adjudicate: lift to AppState vs keep-alive — small design note in plan); series ops transactionality note + until-date inclusive semantics; chat_read_state UPDATE policy membership re-check + DB lowercase-username constraint; PushPrimingView re-entry dead code (wire or delete) + `.restricted` auth no-op CTA; friend_request threadId passthrough + deep-link re-push dedupe; soundboard favorites `updated_at` bump; `publicRoutines()` smoke test; demoted-curator republish lock (document); chat foreground-refetch verification.

### 7. Pre-GA ledger items
Group-attempt start hook at LobbyView Start (Attempt-with-Friends is currently entry-less — wire `start_attempt` for group sessions launched from Discover); QA seed scoping off prod + remove the CI Murph board entry from production visibility (adjudicate mechanism: env-scoped seeding vs cleanup script); Discover Recent-sort LIMIT(200) axis fix (recency-vs-metric); record the blocked-user-visible-on-boards deviation.

## Acceptance
pgTAP for every migration (sweep re-proofs + new constraints); hermetic tests for parse helper/plate/queue logic; offline queue integration test (airplane-mode simulation in unit form — enqueue/replay/dedupe); captures for any visible surface (syncing indicator, voice polish, mixer sheet); full-suite regression green; CI + parity.

## Non-goals
Google Calendar OAuth build (user-gated); Watch/HR (Phase W); campaigns (C); venue hubs (V); new design frames (D).
