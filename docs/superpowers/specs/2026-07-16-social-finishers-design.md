# Phase F — Social Finishers — Design

**Status:** approved scope (roadmap Phase F + Phase U's frame-8 adjudication + Phase S deferrals + USER PRODUCT DECISION 2026-07-16).

## Components

### 0. Streak credit for late-but-completed (USER DECISION — leads the phase)
The user resolved the spec self-conflict: **showing up late but completing the session KEEPS the streak** (the schema-comment reading, "completed without a no_show"; avoids double-punishing lateness, which burpees already price). Implementation: fix-forward migration extending the increment predicate from `check_in_state = 'ready'` to `check_in_state IN ('ready','late')` — in BOTH the individual increment and the group all-ready rule (a late-but-present member no longer blocks the group increment; same principle, applied consistently — recorded as part of the decision). `no_show`/never-checked-in remain excluded; break rules unchanged. pgTAP: late participant increments (user + group), no_show still excluded, group with one late member increments.

### 1. Session sub-thread chat (spec §Chat, deferred 3a→3b→3c)
`chat_messages.session_id` sub-threads: migration adds the column (nullable FK; NULL = group-level, NOT NULL = session thread) + RLS read/write via session participation (mirror the group-membership policy shape); realtime publication per repo doctrine (same-task migration). UI: a chat thread surface in the session context (lobby + live session), using the existing ChatView componentry scoped to the session thread — the phase plan discovers the cleanest reuse (ChatView parameterization vs a sibling view). System messages already carry `session_id` semantics conceptually (PR/lateness messages are session-scoped in spirit) — leave existing rows/producers untouched (group-level), new sub-thread is for participant text messages during a session.

### 2. Kudos + group celebration recap (canvas frame 8, adjudicated in Phase U)
- **Kudos backend**: `session_kudos` table (id, session_id FK, sender_id, recipient_id, emoji text, created_at; one row per tap; rate-limit client-side like soundboard's 1/sec discipline). RLS: participants of the session read/insert (sender = auth.uid()); no update/delete v1. Realtime publication so recap counts update live.
- **Group celebration recap** (frame 8, render `proof-frame-08.png`): full-screen "Session Complete" presented to each participant when a GROUP session completes (from GroupSessionLiveView's completed transition): navy hero (crew·routine, duration, date·lifters, TOTAL LBS/SETS/PRS), volume leaderboard with per-member kudos-received counts, "YOUR PR THIS SESSION" card, kudos-send emoji row (the 5 emoji from the frame), Share Recap + Done. Session Detail (frame 34) remains the from-history view.

### 3. Group Stats sub-tab (spec Flow 5, deferred from Phase 2)
GroupView gains the **Stats** sub-tab: collective metrics (total sessions, PRs, total volume), per-member leaderboards (volume-based, reusing the ledger/leaderboard row idioms), and the **group streak** tile (deferred from Phase S — `group_streaks` read via the members RLS). One aggregate RPC in the established DEFINER/LATERAL idiom if client-side aggregation would N+1.

### 4. Edit Profile + user avatars (deferred from 2.5; You-tab Edit button currently inert)
- Profile avatars: upload to the existing `avatars` bucket (group-avatar precedent from 2.5), `profiles.avatar_url` write (owner RLS exists), render across chat/roster/leaderboards/You header wherever `GSInitialsAvatar` currently falls back (avatar-or-initials component upgrade).
- Edit Profile screen: display name + avatar picker, wired from the You-tab Edit button.
- CreateGroupView gains the avatar picker while in there (2.5 deferral).

## Acceptance
- pgTAP green incl. new matrices (streak-late, sub-thread RLS, kudos RLS); suite totals honest.
- Parity: `group-recap → frame 8` capture (catalog route with fixture state — the celebration needs staged data), group-stats capture if a frame exists (19/22 territory — map only what's authoritative), edit-profile capture (no frame — accepted-deviation entry).
- Live E2E where cheap: kudos insert visible in recap counts via realtime (device QA for the live path; pgTAP for RLS).

## Non-goals
Community/global feeds; kudos outside sessions; avatar moderation flows (Phase M handles report/block surfaces); group streak pushes beyond what S shipped.
