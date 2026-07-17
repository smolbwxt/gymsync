# Phase F — Social Finishers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the streak-credit product decision, session sub-thread chat, kudos + the frame-8 group celebration recap, the group Stats sub-tab (+ group streak tile), and Edit Profile + user avatars.

**Architecture:** backend-first per cluster: (1) the one-predicate streak fix-forward; (2) sub-thread schema + RLS + publication, then UI reuse of ChatView; (3) `session_kudos` + realtime, then the frame-8 recap in GroupSessionLiveView's completion path; (4) group-stats aggregate RPC + the sub-tab; (5) avatars + Edit Profile. Spec: `docs/superpowers/specs/2026-07-16-social-finishers-design.md`; product law: master spec §Chat/Flow 5 + canvas frames 8 (recap) and the existing component idioms.

**Tech Stack:** Postgres + pgTAP; SwiftUI (CI-only compile); Supabase Storage (avatars bucket exists); realtime publications; parity harness.

## Global Constraints

- Applied migrations are append-only — fix-forward only. Every migration ships pgTAP (positive + negative RLS = merge blocker). Suite totals reported honestly (`node scripts/run_pgtap.js`).
- Every `postgres_changes` consumer ships its publication migration in the same task (repo doctrine).
- Swift: CI-only compile; cite real declarations (file:line); memberwise-init trap; commit-don't-push; defensive XCUITest captures.
- Absence discipline: presence = `check_in_at IS NOT NULL` / states `ready`,`late`; never state-label-only reasoning for absence.
- USER DECISION (binding): streak credit predicate = `check_in_state IN ('ready','late')`, individual AND group all-ready rule.
- Seed changes idempotent; never delete personal_records.
- Never `git add -A`.

## Task 1: Streak credit fix-forward (the user decision)

- [ ] Read `20260719000006_streaks.sql` + `...007_streak_trigger_race_fixes.sql` — the CURRENT final definitions of the completion trigger (individual increment predicate + group all-ready check).
- [ ] New migration: `CREATE OR REPLACE` the completion trigger function with both predicates extended to `IN ('ready','late')`. Header comment: the user decision (2026-07-16), the spec self-conflict it resolves (Flow 7 'ready' vs §Streaks schema comment 'without a no_show'), and the double-punishment rationale. Preserve FOR UPDATE + broken_by guards verbatim.
- [ ] pgTAP additions (`streaks_test.sql`): late-participant solo completion increments; group with one late member increments (all-present); no_show still excluded; never-checked-in still excluded. Realistic fixtures (late rows carry check_in_at). Suite green, true totals. `db push` + migration list confirm.
- [ ] Commit `feat(streaks): late-but-completed keeps the streak (user decision)`.

## Task 2: Session sub-thread chat — backend

- [ ] Read `20260715000001_comms_schema.sql` (chat_messages shape, RLS, publication) + `20260712000006_session_realtime_publication.sql` idiom + `is_session_participant` helper (`20260711000001`/3a security work — find it).
- [ ] Migration: `chat_messages.session_id uuid NULL REFERENCES sessions(id)` + index (session_id, created_at); RLS: rows with session_id readable/insertable by session PARTICIPANTS (extend or add policies — read the existing group-membership policy shape and mirror; group_id remains required? decide from schema: sub-thread rows keep group_id of the session's group when present, solo sessions' threads are participant-only — keep it simple: policy = (session_id IS NULL AND existing-group-rules) OR (session_id IS NOT NULL AND is_session_participant(session_id)); verify existing policies compose or need replacement — fix-forward style if replacing). Publication already covers chat_messages (verify — cite).
- [ ] pgTAP: participant reads/writes session-thread rows; non-participant group member CANNOT read a session thread of a session they're not in (if that's the composed policy's behavior — decide + document: master spec says session sub-thread; participants-only is the honest read); group-level rows unaffected. Suite green. `db push`.
- [ ] Commit `feat(social): session sub-thread chat schema + RLS`.

## Task 3: Session sub-thread chat — UI

- [ ] Read `ChatView` (init/params/data flow) + LobbyView + GroupSessionLiveView structure. Decide reuse: parameterize ChatView with an optional `sessionID` scope (repository + realtime filter changes) vs a scoped sibling — pick the smaller diff that keeps ChatView's behavior for groups byte-identical; cite.
- [ ] Surface: a chat affordance in LobbyView + GroupSessionLiveView (read the canvas lobby/live frames for any chat affordance precedent — frames 5/6/7; if the design shows none, a modest sheet/button consistent with the dock idiom; note as system-designed).
- [ ] Repository: send/fetch/realtime scoped to session thread. Captures: catalog or seeded-navigation capture for the thread surface (defensive); map only if a frame is authoritative.
- [ ] Commit `feat(social): session sub-thread chat UI`.

## Task 4: Kudos backend + frame-8 group celebration recap

- [ ] Backend migration: `session_kudos` per spec §2 (participants read/insert, sender=auth.uid(), no update/delete; publication for live counts — same task). pgTAP: participant inserts/reads; non-participant rejected; sender-spoof rejected. `db push`.
- [ ] Read `proof-frame-08.png` + GroupSessionLiveView's completed transition (what currently shows at group end — cite) + SoloRecapView (component idioms to reuse: hero card shape).
- [ ] `GroupRecapView`: frame-8 layout — hero (crew·routine kicker, MM:SS, date·lifters, TOTAL LBS/SETS/PRS), volume leaderboard (existing leaderboard row idiom from the live roster/burpee views) with kudos-received counts (realtime-updating), YOUR-PR card (reuse), kudos-send emoji row (the frame's 5: 💪 🔥 👏 🏆 ⚡ — verify against the proof; insert on tap, 1/sec client discipline like soundboard), Share Recap (existing share idiom from PRCelebrationOverlay's ShareLink), Done.
- [ ] Present from GroupSessionLiveView on completed (replacing whatever it does today — cite before/after; the overlay-lifetime lesson applies: check PR overlay interplay).
- [ ] Catalog: `group-recap` case + fixture state (CatalogScreen + tests count + ScreenshotTests + `frame-map.json → 8`). Commit backend and UI as separate commits within the task.

## Task 5: Group Stats sub-tab

- [ ] Read GroupView (sub-tab enum), Flow 5's Stats description, `group_streaks` read contract, existing aggregate idioms.
- [ ] Aggregate RPC `group_stats(p_group_id)` (DEFINER + membership gate + LATERAL, per precedents): total sessions (completed), total volume, total PRs, per-member volume leaderboard rows. pgTAP incl. membership negative. `db push`.
- [ ] UI: Stats sub-tab — collective tiles (GSStatTile idiom), group streak tile (current/longest from `group_streaks`), per-member leaderboard list. Capture via seeded crew (defensive), map to frame 22/19 ONLY if the proof genuinely depicts this surface (render + judge; else accepted-deviation note).
- [ ] Commit `feat(social): group Stats sub-tab + group streak`.

## Task 6: Edit Profile + avatars

- [ ] Read: avatars bucket policies (`20260711000002`), group-avatar upload flow from 2.5 (the Storage upload idiom in Swift — cite), `GSInitialsAvatar` call sites, You-tab Edit button (inert — cite), `profiles` RLS (owner update).
- [ ] `EditProfileView`: display-name field + avatar PhotosPicker → upload to `avatars/<uid>.jpg` (upsert; the group-avatar idiom) → `profiles.avatar_url` update. Wire the Edit button. CreateGroupView: avatar picker (2.5 deferral) using the same components.
- [ ] Avatar rendering: upgrade the initials-avatar component to avatar-or-initials (AsyncImage with initials fallback) — audit call sites (chat rows, rosters, leaderboards, You header) and adopt where the data flows already carry avatar_url (do NOT plumb new fetches everywhere — adopt where cheap, note the rest).
- [ ] Captures: `edit-profile` catalog case (no frame — accepted-deviation entry). Commit `feat(social): Edit Profile + user avatars`.

## Task 7 (controller): gate + merge
- [ ] Push once after T6; CI + whole-branch review parallel; fix waves; merge → build.

## Self-Review
Spec §0→T1, §1→T2+T3, §2→T4, §3→T5, §4→T6; acceptance→gates in T1/T2/T4/T5 pgTAP + T7 parity. Discovery items are cited-read steps, not guesses; the ChatView-reuse and recap-presentation decisions are bounded with "smaller diff wins + cite" rules.
