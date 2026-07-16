# Phase S — Schedule-Based Streaks + Session-Lifecycle Gaps — Design

**Status:** approved scope (roadmap Phase S + its leakage-audit additions). Product authority: the master spec (`docs/superpowers/specs/2026-06-28-gymsync-design.md`) §Streaks schema + Flow 7 — streak rules are NOT re-decided here.

## Why the lifecycle gaps ride this phase

Two recorded product gaps are prerequisites or siblings of streaks:
1. **`no_show` is unreachable in production** (ledger, canvas-completion phase) — yet Flow 7's streak-break rule fires on exactly that transition. Without wiring it, streaks can never break. BLOCKING prerequisite.
2. **Burpee settlement** — `burpees_owed` never decrements; the Burpee Ledger renders owed-only. Session-lifecycle schema work in the same domain.

## Components

### 1. `no_show` wiring (server-side)
Flow 6 rule: a participant later than the threshold (default 15 min, group-configurable via the session's `late_penalty`/group config — use whatever the schema already stores; discover) transitions `check_in_state → 'no_show'`. Server-side via the established pg_cron + RPC pattern from 3d (reminders/idle ladder precedent): a cron pass over sessions past `scheduled_for + threshold` still carrying non-ready participants, while the session is `lobby_open`/`in_progress`. Late re-join stays possible per Flow 6 (burpees compound; a no_show who checks in flips back to `late`/`ready` — match Flow 6's text: "She can still join late but burpees compound" — discover the exact current check-in transition code and preserve it).

### 2. Burpee settlement (decision recorded)
**Decision: derive settled from existing data — no new counter column.** Penalty work is already logged as `set_logs` rows with `is_penalty = true` (Flow 2 step 8; the logging path shipped in 3b). Settled-per-user-per-session = Σ reps of their penalty set_logs (burpee sets). The Burpee Ledger RPC gains `paid` alongside `owed` (canvas frame 25 already shows "paid off 20"); UI shows owed vs paid and a settled state when paid ≥ owed. Rationale: no schema mutation, no drift risk between a counter and the logs it summarizes, append-only history preserved.

### 3. Streaks (master spec verbatim)
- Tables `user_streaks` + `group_streaks` exactly per the master spec §Streaks (current/longest/last_streak_session_id/broken_at/broken_by_session_id), RLS: user_streaks readable by owner + friends; group_streaks by members; **writable ONLY by the trigger functions**.
- Trigger on `sessions.state → completed|abandoned` and on `session_participants.check_in_state → no_show`, recomputing affected streaks per Flow 7's rules (scheduled-at-any-point sessions only; completed-with-ready increments; next-scheduled no_show/abandoned-unattended breaks; ad-hoc solo lifts neutral; group streak = all invited ready).
- pgTAP: the full Flow 7 rule matrix (increment, break, neutral ad-hoc, group all-ready, longest-watermark), positive + negative RLS.

### 4. Streak pushes (3d outbox, reserved cases)
- Milestones (7/14/30/60/90/180/365): celebratory push + `system_session`-style chat message where a group applies.
- At-risk: 30 min before `scheduled_for` if not checked in ("🔥 Your N-session streak needs you…") — cron in the 3d reminder idiom.
- Break: SILENT (no push) per Flow 7.
- Wire through the existing outbox → push-dispatcher (payload cases were explicitly deferred to this phase in 3d).

### 5. UI + capture
- Stats tab: current + longest streak (master spec places them on Stats). No canvas frame exists — design from the system (GSStatTile/GSCard idioms), file a designer note, record an accepted-deviation entry (`streaks` screen unmapped or mapped-with-note).
- Burpee Ledger: owed/paid/settled rendering per frame 25's existing treatment.
- Fixture seed: extend `seed_qa_fixtures.js` so the CI account carries a live streak (scheduled+completed sessions chain) → harness captures populated streak UI.

## Acceptance
- pgTAP: full suite green including the new matrix; second-run idempotency of seed extensions.
- A no_show actually occurs in a test fixture and breaks a streak (the end-to-end proof the gap is closed).
- Parity captures for the Stats streak surface + updated Burpee Ledger.
- Milestone/at-risk pushes enqueue in outbox tests (not device-delivered — that's device QA).

## Non-goals
Streak repair/freeze (spec v2); achievements/badges (v2); redesigning Stats beyond the streak tiles; client-side streak computation (server triggers only).
