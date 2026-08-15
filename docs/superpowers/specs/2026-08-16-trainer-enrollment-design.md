# Trainer Enrollment — Individual + Gym-Sponsored Seats

**Owner-approved 2026-08-16.** Two rails for becoming a trainer, both
surfaced in the Shop's COACHING card; billing dormant until ASC products
and the web portal exist.

## Principles

1. **Charge capacity, not enrollment.** Becoming a trainer is free with a
   small taste (2 clients). The trainer subscription gates client
   capacity beyond it (client-count tier bands — the Trainerize model,
   pinned 2026-08-14). Trainers are acquisition channels: every trainer
   recruits their clients into the app, so the door stays open and the
   upgrade is what's sold.
2. **Gyms buy seats off-app; keys redeem in-app.** Institutions purchase
   seat blocks on the web (v1: direct sales, invite-only — no self-serve
   checkout), the server provisions `gym_seat_keys`, and employed
   trainers redeem a key in the Shop. Slack precedent: externally
   purchased institutional entitlements honored in-app. Avoids handing
   Apple 30% of a B2B contract and keeps App Review simple.
3. **Seats hang off venues.** A gym's seat block belongs to its venue row:
   the venue owner administers keys through the existing owner-menu
   machinery, and a sponsored trainer can wear a "gym-verified trainer"
   tag (ties into the deferred venue-verification tier).
4. **Revocation never touches data.** A trainer who loses their seat (or
   lapses their subscription) drops to the free capacity tier. Client
   relationships, prescriptions, and notes are untouched — client data is
   never hostage to an employer's subscription.

## Schema (20260816000001)

- `trainer_entitlements` — user, source (`individual_sub` | `gym_seat`),
  optional venue, client_cap (NULL = unlimited band), active window,
  revoked_at. Written by service role only (verify-entitlement edge fn /
  web portal); readable by the owner and, for gym seats, the venue
  creator.
- `gym_seat_keys` — venue, unique code, client_cap, redeemed_by/at,
  revoked_at. Provisioned by service role; redeemed via SECURITY DEFINER
  RPC `redeem_gym_seat_key(p_code)` (validates unredeemed + unrevoked,
  stamps redemption, mints the entitlement). Venue creator reads their
  block; a redeemer reads their own key.

Capacity enforcement reads `trainer_entitlements` and stays DORMANT until
the paywall flips — same posture as M1.

## Shop surface (next UI slice)

COACHING card → three doors:
- **Train with a coach** — redeem a client invite (existing flow).
- **Become a trainer** — free start, capacity subscription upsell
  (dormant until ASC trainer products exist).
- **Redeem a gym key** — code entry → `redeem_gym_seat_key`.

## Backlog

- **GymSync web portal** (owner 2026-08-16: "sounds like we're making a
  website as well now"): gym seat purchasing (invoice → provision seat
  blocks), seat-block administration for gym owners, revocation. Later:
  creator program sales pages. Server-authoritative writer for
  `trainer_entitlements` / `gym_seat_keys`.
- Gym self-serve checkout (post-invite-only phase).
- "Gym-verified trainer" profile tag once venue verification tiers ship.
- Client-cap enforcement wiring when the trainer paywall goes live.
