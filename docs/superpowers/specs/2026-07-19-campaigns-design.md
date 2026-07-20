# Phase C — Seasonal Campaigns — Design

**Status:** approved scope (roadmap Phase C). Product law: master spec Flow 8 + the campaigns schema section (`docs/superpowers/specs/2026-06-28-gymsync-design.md` — implementers read them verbatim). Ops note: REAL campaign content is the USER's (calendar/copy/badges); this phase ships the machinery + one seeded test campaign.

## Components

### 1. Backend (per master spec verbatim)
`campaigns` / `campaign_participants` / `campaign_progress` tables + the progress trigger (spec's stated mechanism — progress increments from completed sessions/sets per the campaign's goal type during its date window). RLS per spec (campaigns public-read while active; participants/progress owner-scoped + aggregate exposure per the community-bar need — read what Flow 8's community progress actually requires and design the honest aggregate surface: a DEFINER aggregate RPC in the established pattern if row-level RLS can't express it — `private`-schema discipline for any helper). Join/leave RPC or direct insert per spec. pgTAP throughout.

### 2. UI
Library gains the **Campaigns** sub-tab (the roadmap's four-sub-tab structure completes); Home carousel card for active campaigns (per canvas if frames exist — check; else system-designed + deviations); campaign detail: description, dates, community progress bar (LIVE via the established Realtime idiom — spec says postgres_changes on campaign_progress; verify against the wire-shape section), per-campaign leaderboard (opt-in semantics per the workout-leaderboard precedent — adjudicate: campaigns are inherently communal; read the spec's line), completion badge + system chat message (`system_campaign` kind? — check the chat kinds; NOT VALID+VALIDATE if extending).

### 3. Content
One seeded test campaign via the seed idiom (idempotent, CI-account-scoped visibility considerations per the Murph de-leak precedent — a test campaign must NOT pollute real users' active-campaign surfaces: adjudicate mechanism, e.g. a far-past date window or draft flag per spec).

## Acceptance
pgTAP (RLS both directions, trigger correctness with fixture numbers, join/leave); hermetic tests for pure logic; captures for the new surfaces + deviations; live proof: the CI account joins the test campaign and progress increments on a completed fixture session.

## Non-goals
Real campaign content (user's); campaign push notifications beyond what the spec's Flow 8 names (check — if it names one, it rides the 3d outbox pattern); venues (V); design polish (D).
