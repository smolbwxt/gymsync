# GymSync Functional Audit — 2026-07-20 (Opus, live backend)

**Scope & honesty boundary:** this audit exercises the **live backend + business logic** (RPCs, triggers, RLS, Edge Functions) against the production DB, verifying behavior matches spec *intent* — not just that our own tests pass. It does **NOT** cover the iOS/watchOS UI/interaction layer (Swift compiles only in CI; no simulator/device available), which is genuine on-device QA. Method: read live definitions, run adversarial/edge probes as real roles (rollback-wrapped), and check spec intent vs implementation — complementing the **820-assertion pgTAP regression baseline (GREEN, 0 failures)** which already covers specified RLS/trigger/RPC behavior.

Verdict legend: **PASS** (behaves as intended) · **LATENT** (correct today, breaks under a future change) · **GAP** (spec intent not fully met) · **BUG** (misbehaves now).

---

## D1 — Live-session RPCs

- `advance_turn` — **PASS**, with one **LATENT**. Auth (current-lifter-or-organizer), state guard, `FOR UPDATE` serialization, no-show skipping, round-robin wrap, and liveness guard are all correct. LATENT: resolves the next lifter via `turn_order > v_current_order` / wrap `<= v_current_order`; if `current_turn_user_id` ever pointed at a user with **no `session_participants` row**, `v_current_order` is NULL and every comparison returns zero rows → session becomes permanently un-advanceable even with other active lifters. **Unreachable today** — verified there is NO participant-removal path (no `leave`/`remove` RPC, no client `DELETE session_participants`; `mark_no_shows` only flips `check_in_state`, the row survives so `v_current_order` stays non-NULL). Becomes a live brick the moment a "leave session" feature is added — `advance_turn` must handle NULL `v_current_order` then.
- `mark_no_shows` — **PASS**, one low-severity edge noted: it sweeps participants in `in_progress` sessions (not just `lobby_open`) to `no_show` when `check_in_at IS NULL`. A current lifter who is actively lifting but never got a `check_in_at` stamped could be swept mid-session; the lobby check-in flow should prevent an un-checked-in participant reaching in_progress, so this is edge-only. The `'late' means present` fix (check_in_at IS NULL gate) and the malformed-`no_show_after_minutes` defensive cast are both correct.

---

## Live data-integrity invariant sweep (all production rows, independent of fixtures)

Ran counting probes over the *entire* production dataset for states that RLS/triggers are supposed to make impossible. A clean count proves every write that ever happened obeyed the invariant — stronger than a fixture test.

| Invariant | Result | Meaning |
|---|---|---|
| Sessions whose `current_turn_user_id` is not a participant | **0** | `advance_turn` NULL-order brick is unreachable (confirms D1 LATENT) |
| `leaderboard_entries` with no parent `workout_attempt` | **0** | No leaderboard fabrication |
| `chat_messages` authored by a non-member of the group | **0** | Group-membership write-gate holds under all real writes |
| `campaign_progress` rows without a matching `campaign_participants` | **0** | No progress without participation |
| `user_streaks`: negative / current>longest / broken-but-nonzero | **0 / 0 / 0** | Streak state machine never entered an impossible state |
| `personal_records` not beating `previous_best` / negative weight-reps | **0 / 0** | PR recompute only writes genuine records |
| `push_devices` with null/empty `apns_token` | **0** | No malformed device rows |

---

## D2 — Leaderboards / PRs / attempts

- **Opt-out leaderboard privacy — PASS (proven live).** Found 1 physical `leaderboard_entries` row for an attempt with `is_opt_in_leaderboard=false` (owner b766, 2026-07-18). This is *correct by design*, not a leak: entries are always computed; visibility is gated at read time by RLS `(user_id = auth.uid()) OR EXISTS(… wa.is_opt_in_leaderboard=true)`, evaluated against the **live** flag so opt-in/opt-out is instant with no recompute. Faithful role-gated probe of that exact row: **owner sees 1, non-owner sees 0, anon sees 0.** The past opt-out leak is fixed and holds under adversarial reads.
- **PR integrity — PASS.** Every `personal_records` row genuinely beats its `previous_best`; no negatives (invariant sweep).
- **Leaderboard fabrication — PASS.** No entries without a parent attempt (invariant sweep).

## D3 — Streaks

- **PASS.** No streak in production is negative, has `current > longest`, or is `broken_at`-set-but-nonzero. The streak state machine (`user_streaks` with `broken_at`/`broken_by_session_id`) has never entered an impossible state across all real data.

## D6 — Social (friendships)

- **Friendship model — PASS.** Confirmed single-row directed model (requester→accepter; 1 accepted + 1 pending in production, 0 self-edges). RLS must let both endpoints read the one row — the `accepted_one_directional=1` my sweep flagged is a *false positive of a two-row assumption*, not a bug. (Chat/group-membership + block privacy audited below.)

## D4 — Moderation & blocks

- **`is_blocked` / `is_group_member` in `private` schema — PASS.** Confirmed both moderation helpers are `private.*` SECURITY DEFINER (the RLS-recursion-safe pattern from the debt-zero law); policies call them instead of inlining subqueries that would re-trigger the target table's RLS.
- **⚠️ FINDING (Important) — inconsistent block enforcement: chat is unidirectional, set_logs is bidirectional.** `private.is_blocked(p_blocker, p_blocked)` is strictly directional (one `blocked_users` row = one direction). The `set_logs` read policy checks **both** directions (`NOT is_blocked(user_id, auth.uid()) AND NOT is_blocked(auth.uid(), user_id)`) — correct mutual-block semantic. But the `chat_messages` read policy checks **only** `NOT is_blocked(auth.uid(), author_id)`. **Consequence:** if A blocks B, A stops seeing B's group messages, but **B continues to see all of A's messages** (B's read evaluates `is_blocked(B, A)` = false). The `set_logs` precedent shows the intended semantic is mutual, so this asymmetry is very likely an oversight. **Recommended fix:** add `AND (NOT private.is_blocked(author_id, auth.uid()))` to the `chat_messages` SELECT policy to match `set_logs`. (Product-intent confirmation warranted, but the internal inconsistency between two policies over the same concept is the strong signal.) *Not device-QA — this is a live backend policy gap.*
- `blocked_users` table currently empty in production (no live block to passively observe); finding above is from policy analysis + the directional `is_blocked` definition.

## D5 — Campaigns

- **Draft isolation — PASS (proven live).** RLS: `(NOT is_draft) OR private.is_campaign_participant(id, auth.uid())`. Faithful role-gated probe against the real "QA Test Campaign" draft (is_draft=true, 1 participant b766): **participant sees 1, non-participant (0b0b) sees 0, anon sees 0.** Drafts are invisible to everyone except their participants.
- **Progress integrity — PASS.** No `campaign_progress` row exists without a matching `campaign_participants` (invariant sweep). `endedParticipated()` surface (added this session) is double-gated (embed `!inner` filter + RLS) and CampaignDetail freezes join/leave + live-subscription when `windowState()==.ended`.
- Campaigns have **no `owner_id`** — they are global admin content (`is_featured`/`is_draft`/`curated_routine_ids`), gated for regular users purely by `is_draft` + participation. (Admin-write path is service-role/edge, out of client reach.)

## D4 (cont.) — Account-deletion cascade (Edge Function)

- **PASS — completeness live-verified.** The function leans entirely on DB FK rules and only explicitly handles: avatar Storage object removal, ownership handoff (groups/sessions/series → a surviving member so shared resources aren't cascade-deleted, preferring an existing admin and promoting the heir to `admin`), and idempotent `deleteUser` retry. Verified against live constraints, not the code comment: **(a)** zero user-referencing FKs are `RESTRICT`/`NO ACTION` (so `deleteAuthUser` can't fail on an FK violation), **(b)** zero user-referencing columns lack an FK (so no orphaned PII) — true even for tables added after the function's comment (campaigns, leaderboard_entries, workout_attempts). Auth model is sound: deleted id comes only from the verified JWT `sub`, never a request param — a caller can only delete themselves.
- **Known caveat (device-QA/UI, already flagged in-code):** a tombstoned `chat_messages` row (author_id SET NULL) renders as an unattributed centered system message, not a labeled "Deleted User" bubble — the message body survives intact; the label is cosmetic Swift UI work.

## D1 (cont.) & D8 — remaining RPCs

- `join_session_by_code` — **PASS.** Resolves code → session in `scheduled`/`lobby_open` only; inserts caller as `auth.uid()` (no join-as-other, no join to in-progress/ended); `ON CONFLICT … WHERE check_in_state='no_show'` only reactivates a no-show. Code-possession-is-auth is the intended private-session model.
- `register_push_device` — **PASS.** Requires sign-in; `ON CONFLICT (apns_token) DO UPDATE SET user_id=auth.uid()` is correct device-reregistration (token possession = device control), not a hijack vector.

---

## Verdict summary (live backend / logic)

| Domain | Verdict | Evidence |
|---|---|---|
| Live-session RPCs (advance_turn, mark_no_shows, join_by_code) | **PASS** (+1 latent) | def analysis + INV-1 clean |
| Leaderboards / opt-out privacy / PRs | **PASS** | 3-role RLS probe + INV sweep |
| Streaks | **PASS** | INV sweep (no impossible states) |
| Moderation — private-schema helpers, account deletion | **PASS** | live FK-rule verification |
| Moderation — block enforcement symmetry | **⚠️ Important finding** | chat unidirectional vs set_logs bidirectional |
| Campaigns — draft isolation, progress | **PASS** | 3-role RLS probe + INV-4 clean |
| Social — friendships, chat membership gate | **PASS** | model check + policy analysis |
| Push registration | **PASS** | def analysis |
| pgTAP regression baseline | **PASS** | 820 ok / 0 not ok / 63 files |

**Actionable finding (1):** block enforcement asymmetry in `chat_messages` (D4) — a blocked user can still read the blocker's group messages; `set_logs` proves the intended semantic is mutual. Recommended one-line policy fix documented above. This is a live backend gap, not device-QA.

---

## Requires on-device QA (the interaction layer I cannot exercise)

Swift compiles only in CI; there is no simulator/device here, so nothing below was functionally exercised — these are genuine device-QA items, not audit gaps:

- **All SwiftUI views, navigation, gestures, empty/error states** — including the new Past-campaigns section and frozen ended-campaign detail added this session (logic/RLS verified; visual/interaction unverified).
- **Apple Watch** — HR capture, watch↔phone live-session handoff, complications (the whole watch-capture infra is a separate Mac-gated plan).
- **Real push delivery** — registration + outbox verified; actual APNs delivery to a physical device is not.
- **LiveKit real-time media** — token issuance verified (edge fn); actual audio/video session is not.
- **Avatar camera/photo upload UX**, soundboard playback, haptics.
- **Chat tombstone rendering** — the "Deleted User" label gap (D4 caveat) is a visual check.
- **Offline / reconnection / realtime subscription behavior** under live network conditions.
- **GCal integration** — blocked on the user-owned Google OAuth client + consent test-user (not code).
