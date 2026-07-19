# Phase W — Apple Watch Companion + Heart-Rate Broadcast — Design

**Status:** approved scope (roadmap Phase W — the master spec's "true differentiator"). Product law: master spec §6.5 (HR broadcast + wire shape §5), the Watch-app feature list, and the canvas Live frames' "BPM · LIVE" zone-colored pills.

## Components

### 1. watchOS target (infrastructure)
New watchOS app target in `GymSyncApp/project.yml` (xcodegen; CI builds it in the same ios.yml pipeline — a watchOS-simulator build job or a combined scheme; judge the cheapest CI shape that PROVES compilation; TestFlight archive must embed the Watch app in the iOS archive). Design-system subset ported (GSTheme tokens + minimal type ramp — watch surfaces are tiny; no full GSComponents port). NO standalone-watch auth: the phone owns the Supabase session; the Watch is a WatchConnectivity peripheral only (spec's stated shape — cite in implementation).

### 2. Watch app surfaces (4, all fed via WatchConnectivity from the phone)
- **Whose-turn indicator**: current exercise, current lifter (name/initials), turn state — the Watch's home screen during a live group session.
- **Tap-to-log-set**: reps stepper + weight (crown-adjustable) + log button — sends the set to the phone, which routes it through the EXISTING submit path (LogSetSheet's repository call + offline queue — the Watch never talks to Supabase).
- **Soundboard buttons**: the user's 4 favorites (synced from phone), tap → phone plays/broadcasts per the existing soundboard flow.
- **Ledger glance**: burpee ledger summary (owed/paid counts) — read-only.
Idle state (no live session): today's next scheduled session or "no session" — minimal.

### 3. Phone↔Watch plumbing
`WatchConnectivityBridge` (phone) + Watch-side counterpart: session state pushes (applicationContext for latest-wins state; sendMessage for interactive log/soundboard actions with replies). Explicit versioned message schema (a small Codable envelope — future-proof). Watch reachability degradations handled honestly (phone app not reachable → Watch shows stale-state indicator).

### 4. Heart-rate broadcast (spec §6.5 — ephemeral only)
- **Opt-in**: `share_heart_rate` toggle (per spec; check whether user_settings has the column — add via migration if absent). Default OFF. Watch requests HealthKit HR read permission ONLY on first enable (permission discipline law).
- **Pipeline**: Watch `HKAnchoredObjectQuery` (workout-session-backed for continuous delivery) → WatchConnectivity → phone → Supabase Realtime broadcast channel `session:{id}:hr` at max 1 msg/5s per user (wire shape §5 — read it verbatim; the payload is {user_id, bpm, zone?}).
- **Display**: zone-colored HR pills on the Live roster (canvas Live frames show "BPM · LIVE" — render the frames for authority; zones per the spec's formula or standard 5-zone %-of-max with age-from-profile if spec silent — record the choice).
- **EPHEMERAL ONLY — never persisted**: no DB table, no logs of bpm values (AppLogger must not log readings), broadcast-only Realtime (no postgres_changes). This is a hard privacy law from the spec.

### 5. Explicitly deferred
Watch-side offline set queue (phone's queue covers it — Watch requires phone reachability for logging, honest v1); Watch complications; standalone Watch workouts; HR persistence/analytics (never, per spec); Watch UI polish beyond system idioms (Phase D designs the Watch family).

## Acceptance
CI proves watchOS compilation + iOS archive embedding; hermetic tests for the message envelope codec + HR throttle/zone logic (pure parts); pgTAP for the settings migration (if any); captures for the phone-side HR pills (catalog case + deviations; Watch screens are device-QA + Phase D territory); device-QA list (real Watch flows can't run in CI).

## Non-goals
Campaigns (C), venues (V), design sharpening (D); any HR storage; standalone Watch auth.
