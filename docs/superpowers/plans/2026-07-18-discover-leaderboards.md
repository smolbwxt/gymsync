# Phase L — Discover + Leaderboards — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the public workout repository — attempts, multi-metric leaderboards, the Discover sub-tab, Top Lifters, and the attempt flow — per master spec Flow 4.

**Architecture:** backend-first: attempts/entries schema + recompute trigger + RLS, then the attempt plumbing (opt-in, completion hook, system message + leaderboard_passed push), then Discover UI (grid → detail → sortable board → CTAs), Top Lifters, publishing fields, seeded content. Spec: `docs/superpowers/specs/2026-07-18-discover-leaderboards-design.md`; product law = master spec §Public Workout Repository / Flow 4 / duration-edit rule — implementers read those sections directly.

**Tech Stack:** Postgres + pgTAP; SwiftUI (CI-only); the 3d outbox for the push; parity harness; seed idioms.

## Global Constraints

- Applied migrations append-only; fix-forwards transplant verbatim; every migration ships pgTAP (pos+neg RLS = blocker); honest totals; `db push` per task.
- chat_messages CHECK extension (if `system_leaderboard` kind is missing) uses NOT VALID + VALIDATE CONSTRAINT (the S-phase lock doctrine — chat_messages is the growing table).
- Duration-edit rule is law: `leaderboard_entries.time_seconds` NEVER updates after completion; `is_edited` flips when the session's duration is edited; volume/top_sets DO update from set_log changes (spec Flow 6).
- Pushes ride the 3d outbox (`payloads.ts` reserved `leaderboard_passed` case); deno tests per pattern; single-recipient fan-out (the displaced user only).
- Swift CI-only; citations; memberwise traps; commit-don't-push; defensive captures; catalog cases wired everywhere (enum/count-test/ScreenshotTests/frame-map-or-deviation).
- DEFINER helpers: gate-first, search_path pinned, REVOKE/GRANT idiom; NO new public-schema relationship oracles (the M lesson — anything sensitive goes in `private`).
- Never `git add -A`.

## Task 1: Attempts + entries schema + recompute (backend core)
- [ ] Read master spec §Public Workout Repository verbatim + the `routines` table's CURRENT columns (which public-workout fields exist vs need adding — cite) + the session-completion paths (solo endSession / group complete — where an attempt completes) + the duration-edit path (session_duration_edits, 3b).
- [ ] Migration(s): `workout_attempts` + `leaderboard_entries` per spec (+ any missing `routines` fields, fix-forward). Recompute as a DEFINER function + trigger on the attempt-completion write (compute time from started/completed, total_volume + top_sets jsonb from the user's session set_logs excl. penalty/failed; is_complete). Duration-edit hook: trigger on `session_duration_edits` insert (or the sessions update path — cite the real mechanism) flips `is_edited` WITHOUT touching time_seconds. RLS per spec (opt-in public read, else owner).
- [ ] pgTAP: recompute correctness with fixture numbers; opt-in vs owner-only RLS both directions; duration-edit lock (time unchanged + is_edited true); volume/top_sets update on set_log change while time stays. Suite TRUE totals; push.
- [ ] Commit.

## Task 2: Attempt plumbing (backend)
- [ ] Attempt creation at attempt-start (Flow 4: an attempt row when a public-routine session begins with the opt-in choice) — find the honest hook (session creation with routine visibility=public? an explicit client call? judge: an `start_attempt(p_routine, p_session, p_opt_in)` RPC the client calls when launching from Discover keeps it explicit + testable — decide, cite).
- [ ] Completion: system message (`system_leaderboard` kind — verify/extend chat kinds w/ NOT VALID doctrine) to the user's group(s)? Spec: "lands in the user's group chat" — singular primary group ambiguity: send to the session's group if the attempt session is a group session, else skip chat (solo attempts get no group message — honest read; record). `leaderboard_passed` detection in recompute (rank before/after among opt-in complete entries per default metric) → outbox enqueue (payloads.ts case + deno test).
- [ ] pgTAP + deno. Push + deploy dispatcher.
- [ ] Commit.

## Task 3: Discover UI (grid + detail + board + CTAs)
- [ ] Read LibraryTabView (sub-tab enum from curation-era), canvas for any Discover frames (render candidates; likely undesigned → system-designed + deviations), the Featured shelf (grid idioms), BurpeeLedger/GroupStats leaderboard row idioms, RoutineDetailChoice (the M block/report surface — wire Discover detail to reach it).
- [ ] Discover sub-tab: public workouts grid (is_featured first); workout detail: description, metrics chips, sortable leaderboard (segmented Time/Volume/TopSet/Recent per scoring_metrics; ✏️ indicator on edited rows; opt-in rows only), Attempt Solo (→ WorkoutSessionView w/ routine preselected + opt-in toggle) + Attempt with Friends (→ schedule sheet preloaded). Repository methods per idiom.
- [ ] Captures + frame-map/deviations. Commit.

## Task 4: Top Lifters + publishing fields + seed
- [ ] Top Lifters: global board on lifetime_volume_lifted (profiles public-read — cite; a LIMIT-ed ordered query, no new RLS). Surface from Discover. 
- [ ] RoutineBuilder publish path (curator-gated): default_sort/scoring_metrics/top-set-exercise pickers (minimal UI per idioms).
- [ ] Seed: featured workouts pack ("The Murph" per its canonical definition + 2 templates) via the curator seed idiom; CI-account attempt fixture so a leaderboard renders in captures. Idempotent.
- [ ] Captures. Commit.

## Task 5 (controller): gate + merge.

## Self-Review
Spec §1→T1, §2→T2, §3→T3 (+M dead-surface closure), §4/content→T4. Ambiguities pinned: attempt-start hook (T2 decides w/ citation), solo-attempt chat message (skip, recorded), Top Lifters opt-in basis (public profile data, recorded). Duration-edit law restated in constraints.
