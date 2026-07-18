# Phase M — Moderation & Compliance (App Store Gate) — Design

**Status:** approved scope (roadmap Phase M). Product law: master spec §Moderation tables, RLS list, §6.2 account deletion, §6.7 guardrails vocabulary. Both headline items are App Store review requirements for UGC apps (Guidelines 1.2 / 5.1.1) — no public submission without them. TestFlight unaffected.

## Components

### 1. Block / report backend
- Tables per master spec verbatim: `user_reports` (reporter, reported_user, content type/id, reason, status default 'open') and `blocked_users` (blocker, blocked, PK pair).
- RLS: reports writable by any authenticated (reporter = auth.uid()), readable by reporter (admin reads via service/SQL — the spec's v1 posture: `app_admin` granted manually, no queue UI).
- **Block enforcement at the query/policy level** (spec's RLS list): chat SELECT excludes messages authored by users the caller blocked (fix-forward the chat SELECT policy: `NOT EXISTS (SELECT 1 FROM blocked_users WHERE blocker_id = auth.uid() AND blocked_id = chat_messages.author_id)` — composed with the existing narrowing); friend-request INSERT rejected when either direction of block exists (policy or trigger per the friendships write path's real shape); reactions/kudos ride the message/session gates (evaluate whether author-block filtering must extend there — decide with citations, keep v1 honest: chat content + friend requests are the spec's named surfaces).
- `is_blocked(a,b)` DEFINER helper for reuse.

### 2. Block / report UI
- Report + Block actions: profile contexts (Friends rows, group Members rows), chat message context menu, published/featured routine detail. Sheet with reason categories (freeform text + a few fixed reasons — system-designed, no canvas frame; deviation entry).
- You tab: Blocked Users list (unblock action) — master spec's You-tab list.
- Blocking UX: confirm dialog; blocked users' messages vanish on next fetch (policy-driven); friend rows filtered client-side where already-fetched.

### 3. Account deletion (App Store 5.1.1)
- `account-deletion-cascade` Edge Function (repo's second function; push-dispatcher idioms): authenticated caller deletes THEIR OWN account — cascades owned data (profile, friendships, gyms, push devices, own set_logs, owned routines, authored messages anonymized→tombstone "Deleted User" per spec §6.2, storage avatar), then deletes the auth user (admin API). Ordering matters (FKs); document the cascade table-by-table with ON DELETE behaviors cited.
- You tab: Delete Account row → typed-confirmation sheet → call function → sign out locally.

### 4. Solo-workout privacy opt-in
- Surface `profiles.show_solo_workouts` (exists since day 1, default false) as a You-tab toggle.
- Enforce in `set_logs` SELECT RLS per the master spec's list (owner + session participants; solo rows visible to accepted friends ONLY when the owner opted in) — fix-forward the current policy with citations to its real present shape.

## Acceptance
- pgTAP: block filtering (chat rows vanish for blocker, remain for others), friend-request rejection both directions, report RLS, deletion-cascade integration test (deno; fixture user), solo-privacy matrix (friend sees solo rows iff opt-in).
- Captures: blocked-users list + report sheet (catalog; deviations — no frames). Delete-account flow device-QA only (destructive).
- The App-Store-ready milestone: after merge, block/report + deletion verified = submission-compliance gate met.

## Non-goals
Moderation queue UI (v2 per spec); government-ID verification; server-side push-notification block filtering beyond the named surfaces (tracked if found leaking); Local-Hub-specific guardrails (Phase V).
