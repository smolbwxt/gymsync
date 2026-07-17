# Phase M — Moderation & Compliance — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** the two App Store compliance requirements (block/report + account deletion) plus solo-workout privacy — the gate before any public submission.

**Architecture:** backend-first. Block/report tables + enforcement policies + helper, then UI; account-deletion Edge Function + You-tab flow; solo-privacy RLS + toggle. Spec: `docs/superpowers/specs/2026-07-17-moderation-compliance-design.md`; product law: master spec §Moderation / §6.2 / RLS list.

**Tech Stack:** Postgres + pgTAP; Supabase Edge Function (Deno, TypeScript) + deno tests; SwiftUI (CI-only compile); parity harness.

## Global Constraints

- Applied migrations append-only — fix-forward only (the chat SELECT policy + set_logs SELECT policy are LIVE; replace via new migration, transplanting current behavior verbatim + adding the new clause). Every migration ships pgTAP (positive + negative RLS = merge blocker). Honest suite totals.
- Edge Function follows the `push-dispatcher` idioms (repo's first function — read its structure, secrets handling via `.env.local`/vault, deploy via `supabase functions deploy` with SUPABASE_ACCESS_TOKEN, deno test pattern). It's the repo's SECOND function.
- Account deletion is DESTRUCTIVE and App-Store-required — the cascade must be exhaustive + ordered + idempotent; tombstone shared records ("Deleted User"), never orphan FKs.
- Swift CI-only; cite declarations; memberwise trap; commit-don't-push; destructive UI flows (delete account) get typed confirmation.
- Never `git add -A`; secrets only in gitignored `.env.local`.

## Task 1: Block / report backend

- [ ] Read: master spec §Moderation (`user_reports`/`blocked_users` schema) + RLS list (block enforcement lines); the CURRENT chat SELECT policy (`20260719000010`+`0011` final form — the narrowed+can_access_message version); the friendships write path (`20260710000001` + how requests INSERT — RPC or direct); `is_session_participant`/`is_group_member` DEFINER helper idiom.
- [ ] Migration: both tables per spec; RLS (reports: insert reporter=auth.uid(), select reporter-only; blocked_users: all owner=blocker). `is_blocked(p_a uuid, p_b uuid) returns boolean` DEFINER helper (blocker→blocked directional; document direction). Fix-forward the chat SELECT policy adding `AND NOT (author blocked by caller)` composed with the existing clause (transplant current verbatim). Friend-request block: reject INSERT (or the RPC) when `is_blocked` either direction — implement at the real write path; cite.
- [ ] pgTAP: report insert/select RLS (+ negatives); block insert/select; chat rows authored by a blocked user vanish for the blocker, remain for a third party; friend request blocked both directions; a NON-blocked user's messages/requests unaffected (regression). Suite green, TRUE totals. `db push`.
- [ ] Commit `feat(moderation): block/report tables, enforcement policies, is_blocked helper`.

## Task 2: Block / report UI

- [ ] Read: profile/row contexts (FriendsView rows, GroupView Members rows), ChatView message context menu (does one exist? add per idiom), routine detail; the You-tab list idioms; existing sheet/confirm-dialog idioms.
- [ ] Report action → sheet (reason categories + freeform), inserts `user_reports`. Block action → confirm dialog → `blocked_users` insert + client-side removal of the now-hidden content where already fetched. You-tab **Blocked Users** list + unblock. Repositories per idiom (decode structs snake_case).
- [ ] Captures: `report-sheet` + `blocked-users` catalog cases (deviations — no frames). Commit `feat(moderation): report + block UI, blocked-users list`.

## Task 3: Account deletion cascade

- [ ] Read: `supabase/functions/push-dispatcher/` (structure, deno.json, secrets, deploy, test.ts pattern); the full FK graph touching `profiles` (grep `REFERENCES profiles` across migrations — enumerate every table + its ON DELETE); spec §6.2 (cascade + tombstone list).
- [ ] `supabase/functions/account-deletion-cascade/`: authenticated caller (verify JWT → user id), deletes own data in FK-safe order, tombstones authored shared records (chat_messages author → NULL/"Deleted User" per the existing system-message author-NULL convention; sessions/groups membership), deletes storage avatar, finally `auth.admin.deleteUser`. Idempotent (re-run safe). Deno tests: a fixture user with data across the graph → invoke → assert owned rows gone, shared records tombstoned not orphaned, auth user removed. Deploy via the 3d idiom.
- [ ] Commit `feat(compliance): account-deletion-cascade Edge Function`.

## Task 4: Solo-privacy + Delete-Account UI

- [ ] set_logs SELECT RLS: read the CURRENT policy (cite); fix-forward so solo rows (session with single participant / the solo semantics — determine how "solo" is expressed: session_participants count or a flag; cite) are visible to accepted friends ONLY when `profiles.show_solo_workouts = true` for the owner; owner + session participants always. pgTAP matrix: friend sees solo rows iff opt-in; non-friend never; participant always; owner always. `db push`.
- [ ] You tab: `show_solo_workouts` toggle (writes profiles; owner RLS) + **Delete Account** row → typed-confirmation sheet ("type DELETE") → calls the Edge Function → local sign-out (AuthService). Cite the settings-row + sign-out idioms.
- [ ] Captures: You-tab already captured; add accepted-deviation note for the new rows if they shift layout. Commit `feat(compliance): solo-privacy toggle + delete-account flow`.

## Task 5 (controller): gate + merge + App-Store-ready milestone
- [ ] Push; CI + whole-branch review parallel; fix waves; merge. Record the App-Store-ready milestone (block/report + deletion verified) — the submission-compliance gate.

## Self-Review
Spec §1→T1, §2→T2, §3→T3, §4→T4; acceptance→pgTAP in T1/T4 + deno in T3 + T5 review. Fix-forward targets (chat SELECT, set_logs SELECT, friendships write) flagged as cite-current-then-transplant. Destructive deletion gets exhaustive-ordered-idempotent + typed confirmation. Edge Function = second in repo, follows push-dispatcher.
