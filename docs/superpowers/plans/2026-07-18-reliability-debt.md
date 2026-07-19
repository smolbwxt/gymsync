# Phase O — Reliability + Accumulated Debt — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** retire the accumulated security, reliability, and polish debt — DEFINER sweep, Phase H handoff, offline-first set logging, Sentry, the 3e voice queue, the audit roll-up, and the pre-GA ledger — with zero new product surface.

**Architecture:** seven independent debt batches; backend-security first (T1 gates nothing but is highest risk-reduction), then the H handoff (T2), then the two subsystems (T3 offline, T4 Sentry), then the client polish batches (T5, T6), then pre-GA (T7). Spec: `docs/superpowers/specs/2026-07-18-reliability-debt-design.md`; each item's authority is its originating review finding (progress ledger) or master-spec section — implementers read those directly.

**Tech Stack:** Postgres + pgTAP (private-schema pattern per `20260722000001`), SwiftData (T3), Sentry SDK (T4, config-gated), SwiftUI/LiveKit (T5), the parity harness.

## Global Constraints
- Migrations append-only; fix-forward; every dependent-policy repoint ships pgTAP re-proofs (positive AND negative) + full-suite TRUE totals; `db push` per the established command.
- NO new public-schema DEFINER surface anywhere; anything sensitive goes in `private` (the M lesson).
- Swift CI-only; citations file:line; memberwise traps; commit-don't-push; catalog/deviations for visible changes.
- Locale fix (T2) must NOT change stored-data semantics — parse-side only.
- Offline queue (T3): client-generated UUIDs are the idempotency key; replay must be safe against partial prior success (verify server-side upsert/conflict behavior and cite).
- Sentry (T4): sanitized snapshots only — NO tokens, NO message content, NO PII in breadcrumbs/context; DSN absent → provable no-op.
- Never `git add -A`.

## Task 1: DEFINER-helper sweep → private schema
- [ ] Read `20260722000001` (the is_blocked relocation — the pattern is law) + every helper in the queue: `is_friend` (FIRST), `is_session_participant`, `is_group_member`, `message_group_id`, `can_access_message`, `is_solo_session`; also classify `is_session_organizer` (report, relocate only if same exposure class). For each: grep ALL dependent policies before writing.
- [ ] Migration(s): relocate in queue order — CREATE in `private` (search_path pinned, gate-first), repoint every dependent policy, DROP the public version, restate grants. Batch sensibly (one migration per helper or grouped — judge by dependency overlap; state the choice).
- [ ] pgTAP: per helper, re-prove every dependent policy both directions + prove the public function is GONE (call attempt fails) and PostgREST can't reach the private one. Full suite TRUE totals. Push. Commit.

## Task 2: Phase H handoff batch
- [ ] Calendar reconcile sweep: `EventKitBridge.reconcile()` on app-foreground (gated: toggle on + permission granted) — enumerate `SessionCalendarSyncStore.allSessionIDs()`, batch-fetch their states, remove events for cancelled/abandoned/nonexistent; cite the foreground hook idiom (scenePhase). Absorbs N-2/N-3/N-5 (read the gate review's descriptions in the ledger).
- [ ] Batch the serial per-occurrence awaits: fire the per-occurrence EventKit loop AFTER dismiss (structured Task post-server-success), or batch with a progress affordance — judge against the sheet UX; keep best-effort posture.
- [ ] `SeriesEditorView`: thread `routineExerciseCounts` into `loadData()` (mirror ScheduleSessionView's precedent) — kill the 60-min fallback for routine-assigned occurrences.
- [ ] Shared `Decimal` parse helper accepting `.` and `,` (pure, hermetic-tested); adopt at BodyWeightLogSheet, LogSetSheet, GroupSessionLiveView submit paths; PlateStackDisclosure's live parse too if same idiom. No stored-data change.
- [ ] TrendChartView: parameterize the mark/a11y label (default preserves ExerciseHistoryView; body-weight consumer passes its own). Plate-math deviation-entry touch-up (inline-card context). `replaceWorkout` deleted-0 log disambiguation (one line).
- [ ] Hermetic tests where pure; captures if visible chrome changed. Commit.

## Task 3: Offline-first set logging (spec §6.4)
- [ ] Read master spec §6.4 verbatim + the current set-log write paths (LogSetSheet submit, GroupSessionLiveView inline card, penalty flows) + SetLog's PK generation (client UUID — verify, cite) + server conflict behavior on duplicate PK insert (test live; cite).
- [ ] SwiftData model + pending-writes queue: enqueue on submit when offline/failed, optimistic local append with syncing indicator state, replay on connectivity restore (ordered, idempotent, drop-on-permanent-4xx with surfaced error), 90-day local window prune.
- [ ] Wire the 3 submit surfaces through the queue; syncing indicator per design idiom (small chip/spinner — record deviation).
- [ ] Tests: hermetic queue logic (enqueue/replay/dedupe/prune, simulated failure sequences); honest device-QA list for real connectivity flaps. Commit.

## Task 4: Sentry (spec §6.8.5, config-gated)
- [ ] Check secrets for a Sentry DSN (`.env.local` template + CI secrets — do NOT echo values). Expected absent → build the nil-DSN no-op path.
- [ ] SDK via SPM (project.yml per idiom), init behind DSN presence, sanitized session-state snapshot on crash (screen name, session state enum, counts — NO PII/tokens/content; enumerate exactly what's captured in the report), breadcrumbs for the major flows.
- [ ] Test: DSN-absent no-op provable (unit-level: init skipped). USER ACTION recorded: create Sentry project, add DSN to secrets. Commit.

## Task 5: 3e voice queue (8 items, canonical order)
- [ ] Read the 3e follow-up queue's canonical list (ledger/roadmap §O.3) + `VoiceService`/dock/roster code. Implement in priority order: bounded `leave()` on sign-out; mic gate during `.connecting`; join session-scope guard; muted-others roster rows; coach mark; "voice connected" toast; mixer sheet + transmit hero/80pt dock variant (designer-proposed — follow the design notes); back-nav rejoin blip; restore-helper DRY; SeriesEditorView tz-picker residual.
- [ ] Captures for new chrome (coach mark, toast, mixer) + deviations. Device-QA list for real-voice flows. Commit.

## Task 6: Reliability/debt roll-up (audit list)
- [ ] Work the spec §6 list item-by-item; for each: cite the originating audit line, smallest honest fix, test where testable. The two adjudications to make and record: tab-switch transient-state (lift to AppState vs keep-alive — pick per existing AppState idioms); demoted-curator republish (document-only unless trivial).
- [ ] Backend items (chat_read_state UPDATE policy re-check, lowercase-username constraint w/ NOT VALID+VALIDATE if applied to a growing table) ship as migrations + pgTAP. Commit per coherent chunk.

## Task 7: Pre-GA ledger
- [ ] Group-attempt start hook: wire `start_attempt` at LobbyView Start for sessions created via Discover's "Attempt with Friends" (read how the routine/session linkage carries the attempt intent; the RPC's gates are already live — cite `20260723000002/3`).
- [ ] Seed scoping: adjudicate env-scoped seeding vs cleanup for the CI Murph entry + QA fixtures on prod; implement the chosen mechanism honestly (no silent data deletion — script + report).
- [ ] Discover Recent-sort LIMIT(200) axis fix; record blocked-user-visible-on-boards deviation. Commit.

## Task 8 (controller): gate + merge.

## Self-Review
Spec §1→T1 … §7→T7, 1:1. Sentry + GCal user-gates both explicit. Offline scope pinned to set logging. The three in-task adjudications (T2 batch-vs-background, T6 two calls, T7 seed mechanism) are named with deciders. No placeholders; authorities cited per item.
