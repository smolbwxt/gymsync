# Venue Hubs (Local Hub) — Design

**Date:** 2026-07-25
**Origin:** User request 2026-07-25: "work those two items and get the hubs feature
defined and developed." Supersedes the BENCHED Phase V (`docs/superpowers/plans/
2026-07-16-remaining-build-roadmap.md:149-153`), which was parked on 2026-07-20 over
Twilio Verify cost + legal review.
**Source spec:** `2026-06-28-gymsync-design.md` §3 (lines 513–551, 663–666), Flow 9
(886–925), §6.7 (1229–1251).

---

## Scoping decisions (read first)

The original spec lists five **mandatory-before-shipping** safety measures. One of them —
SMS phone verification via Twilio Verify — is the exact thing the user benched
("don't need 2FA here, bench it and move on"). Resolution, recorded explicitly rather
than silently dropped:

| Safety measure | v1 status |
|---|---|
| Age gate (self-attested 18+) | **BUILT** — free, no external dependency |
| Block exclusion from every hub surface | **BUILT** — server-enforced in RLS + RPC |
| Opt-in-only visibility (no passive presence) | **BUILT** — `is_visible_on_hub` defaults false |
| Rate limits (3 check-ins/hr) | **BUILT** — server-enforced in the check-in RPC |
| "Meet in a public area" advisory | **BUILT** — shown on first hub entry |
| **SMS phone verification** | **NOT BUILT — user-benched (Twilio cost + legal review)** |

**Consequence to weigh before any public launch of this feature:** phone verification
exists in the spec specifically to stop throwaway accounts from harassing real people at
a physical location they've disclosed. Without it, the anti-abuse floor is account
creation + the block/report path. That is defensible for a friends-and-testers build,
and is a real gap for a public 18+ location feature. The schema below keeps
`profiles.phone_verified_at` so switching it on later is a gate check, not a migration.

**Second scoping call — GPS-first, QR later.** The spec's entry path is scanning a
gym-printed QR code. No gym has a GymSync QR code today (partner-first seeding never
happened), so a QR-only door means the feature can never open. v1 uses the
**server-verified GPS geofence** as the entry path and keeps `qr_code_token` in the
schema; QR scanning becomes a shortcut to add when a partner venue exists.

**Third — crews are H2.** Flow 9's "open crews + request to join" needs `groups`
columns, a join-request table, and an admin approve/decline inbox. A join request with
no way to accept it is a dead end, so crews ship whole in H2 or not at all. v1 = the
hub itself: presence, leaderboard, check-in, claiming.

---

## H1 architecture (this spec's buildable scope)

### Tables

```sql
venues (                          -- spec §3 verbatim column set
  id, name, latitude, longitude,
  radius_meters   integer DEFAULT 200,
  qr_code_token   text UNIQUE NOT NULL,   -- generated now, scanned in H2
  created_by      uuid REFERENCES profiles(id),
  is_verified     boolean DEFAULT false,  -- gym-partnership flag, admin-only
  claimed_at, banner_url
)
venue_users (
  venue_id, user_id,
  is_visible_on_hub boolean DEFAULT false,
  joined_at, last_seen_at,
  PRIMARY KEY (venue_id, user_id)
)
```

Plus `profiles.age_verified_18plus_at timestamptz` and `profiles.phone_verified_at
timestamptz` (the latter written by nothing in v1 — it is the switch-on point).

### RLS (spec §3:663-666)

- **venues** — global read for `authenticated` (a venue existing is not private).
  INSERT by the claimer (`created_by = auth.uid()`), and **never** with
  `is_verified = true` (partnership flag is admin/service-role only, the same
  RLS-gated-column pattern as `routines.is_featured`). UPDATE by the creator only
  while `NOT is_verified`.
- **venue_users** — you always read your own row. You read *other* rows at a venue only
  when **all** hold: that row is `is_visible_on_hub = true`, you are a member of the
  same venue, and neither of you has blocked the other. No delete-others, no write-others.
- Presence is not a location history: `last_seen_at` is a single mutable column, never
  an append log, and it is only readable through the same visibility gate.

### The check-in RPC — where the real enforcement lives

```
public.check_in_to_venue(p_venue_id uuid, p_lat double precision, p_lng double precision)
```
SECURITY DEFINER, gate-first (the `group_stats` idiom), performing in order:

1. **Age gate** — `profiles.age_verified_18plus_at IS NOT NULL`, else `P0001
   'age verification required'`.
2. **Rate limit** — ≤3 check-ins in the trailing hour for this user, else `P0001
   'too many check-ins, try again later'`. Counted off `venue_users.last_seen_at`
   history via a small `venue_checkins` audit table (needed because `last_seen_at`
   alone can't count).
3. **Geofence** — great-circle distance between (`p_lat`,`p_lng`) and the venue must be
   ≤ `radius_meters`, else `P0001 'you need to be at <venue> to check in'`.
   **This is the first server-side distance check in the codebase** — today's session
   check-in evaluates the geofence client-side only (trivially spoofable). Distance is
   computed in SQL with the haversine formula (no PostGIS dependency).
4. Upserts the `venue_users` row (`is_visible_on_hub` untouched on re-check-in — the
   user's own toggle is never silently flipped by walking in) and stamps `last_seen_at`.

Client-side distance is still checked first for a friendly message; the RPC is the
authority. Same "client is UX, server is truth" split as the 20-minute session check-in
window trigger.

### Presence semantics

A user appears on a hub only while **opted in AND recently seen** — `last_seen_at`
within 4 hours (a gym session's realistic outer bound). This is what makes presence a
"who's here now" surface rather than a "who trains here" directory, and it means
forgetting to toggle off decays on its own.

### Screens (Social ▸ Local sub-tab)

- **Local tab root**: nearby venues (client-side distance sort over the global venue
  list — the list is small in v1), each showing name, distance, and live count of
  visible members; a "Add this gym" CTA opening the map search claim flow (the exact
  `MKLocalSearch` pattern `HomeGymSetupView` already uses).
- **Hub view** (per venue): header (name, member-count), **"I'm here — show me on the
  hub"** toggle, **Who's here** (opted-in + recent, block-filtered, initials avatars),
  **This month's leaderboard** (total volume at this venue among opted-in users), and
  the advisory on first entry.
- **Age gate modal** on first Local interaction: Confirm → stamps
  `age_verified_18plus_at`; Decline → friendly unavailable screen, rest of app
  unaffected.

Onyx language throughout, reusing `GSCard`/`GSSectionHeader`/`GSEmptyState`/
`GSInitialsAvatar` — no new component chrome. Three catalog screens for CI capture:
`venue-local-tab`, `venue-hub`, `venue-age-gate`.

### Testing

- **pgTAP** `venue_hubs_test.sql`: global venue read; non-creator cannot update; a
  non-curator cannot self-verify (`is_verified`); invisible members are unreadable by
  peers; own row always readable; blocked pair mutually invisible; RPC rejects outside
  the radius, without the age stamp, and past the rate limit; RPC succeeds inside.
- **Swift pure math** `VenueMathTests`: haversine distance parity with the SQL formula
  at known coordinates, presence-window (`last_seen_at`) boundary, month-volume
  bucketing.

### Explicit non-goals for H1

QR scanning; open crews + join requests + admin inbox (H2); phone verification
(user-benched); venue editing beyond the creator's own claim; venue photos/banner
upload; realtime presence channel (`venue:{id}` Presence is H2 — v1 refreshes on
appear/pull).
