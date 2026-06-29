# GymSync — Design Document

**Date:** 2026-06-28
**Status:** Draft for review
**Working name:** GymSync (placeholder — final name TBD; an App Store search shows several apps with similar names, so the production name will likely need invention)

---

## 1. Overview

### Problem

Lifting with a partner is one of the most reliably motivating ways to train — but it requires both people to be in the same place at the same time. When partners move apart, switch schedules, or want to lift with a friend across the country, that social structure collapses. Workout-tracking apps exist (Strong, Hevy, Strava) but they're all individual journals; there is no app that recreates the *moment-to-moment* feeling of lifting with a partner across distance.

### Heart of the product

**Synchronous workouts across space.** Two or more lifters share a single workout in real time, alternating turns through a chess-clock-style timer, reacting to each other's lifts through a Discord-style soundboard, and logging their sets into a shared ledger that persists across sessions.

The chess clock is the central metaphor: when it's your partner's turn, the app shows their clock ticking; when they finish their set, the turn passes to you. The partner's "turn" *is* your rest period — the metaphor and the use case align.

### Scope

This document specifies **v1** of GymSync. It targets **iPhone first** (native Swift / SwiftUI), with an **Apple Watch companion app** as a true differentiator for the synchronous use case. Android and a web client are out of scope for v1.

**v1 includes:**
- N-person scheduled sessions with fixed round-robin chess clock
- Friend list + room codes
- Pre-game lobby with geofence check-in (home gym + traveling override) and burpee-on-late penalty (group-configurable)
- Collaborative routine editing in lobby with per-edit unanimous vote
- Discord-style soundboard + emoji reactions, mixed with user's music
- Curated 150–300 exercise library with demo videos
- Personal + shared ledger (shared sessions visible to participants; solo workouts private by default with opt-in to share)
- Public workout repository ("The Murph", "Cbum's Chest Day", etc.) with multi-metric sortable leaderboards
- Persistent friend Groups with per-group chat (text + reactions + system messages)
- System messages in chat for PRs, RSVPs, lateness, leaderboard placements
- PR auto-detection and real-time celebration during sessions
- Apple Health workout export
- iOS Calendar sync for scheduled sessions
- Stat trends / Swift Charts in ledger
- Block / report for chat, friends, and published routines
- Onboarding flow (Sign in with Apple → username → home gym → choose first action)
- Apple Watch companion (whose-turn indicator, soundboard, log a set)
- Per-session and per-exercise notes
- Body weight log
- Plate-math helper

**Deferred to v2:** Achievements/badges system, supersets/circuits, search across ledger, progress photos, warm-up vs. working set distinction, auto-suggested groups from recurring participants, live audio/group call during sessions.

---

## 2. System Architecture

### Diagram

```
                      ┌────────────────────────────────────┐
                      │           iOS Client               │
                      │      (Swift / SwiftUI)             │
                      │                                    │
                      │  ┌─────────────────────────────┐   │
                      │  │   UI Layer (SwiftUI views)  │   │
                      │  ├─────────────────────────────┤   │
                      │  │   Domain (ViewModels,       │   │
                      │  │   session state machines)   │   │
                      │  ├─────────────────────────────┤   │
                      │  │   Services:                 │   │
                      │  │    • SupabaseClient         │   │
                      │  │    • AudioSession (mixing)  │   │
                      │  │    • LocationProvider       │   │
                      │  │    • PushReceiver (APNs)    │   │
                      │  │    • LocalStore (SwiftData) │   │
                      │  │    • HealthKit bridge       │   │
                      │  │    • EventKit bridge        │   │
                      │  │    • WatchConnectivity      │   │
                      │  └─────────────────────────────┘   │
                      └──────────────┬─────────────────────┘
                                     │ HTTPS / WSS
                                     ▼
       ┌──────────────────────────────────────────────────────┐
       │                  Supabase Project                    │
       │                                                      │
       │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐   │
       │  │  Postgres   │  │  Realtime   │  │    Auth     │   │
       │  │ (workouts,  │◄─┤ (presence,  │  │ (Sign in    │   │
       │  │  routines,  │  │  broadcast, │  │  with Apple)│   │
       │  │  ledger,    │  │  postgres_  │  └─────────────┘   │
       │  │  votes,     │  │  changes)   │                    │
       │  │  chat)      │  └─────────────┘  ┌─────────────┐   │
       │  └──────┬──────┘                   │   Storage   │   │
       │         │  RLS policies enforce    │ (soundboard │   │
       │         │  per-user/per-session    │  audio,     │   │
       │         │  data isolation          │  avatars,   │   │
       │         │                          │  exercise   │   │
       │         │                          │  demos)     │   │
       │         │                          └─────────────┘   │
       │  ┌──────▼──────────────────────────────────┐         │
       │  │      Edge Functions (TypeScript)        │         │
       │  │  • push-dispatcher (→ APNs)             │         │
       │  │  • lateness-evaluator (cron)            │         │
       │  │  • idle-session-detector (cron)         │         │
       │  │  • leaderboard-recompute                │         │
       │  │  • account-deletion-cascade             │         │
       │  └──────────────────┬──────────────────────┘         │
       └─────────────────────┼────────────────────────────────┘
                             │
                             ▼
                     ┌──────────────────┐
                     │      APNs        │  (Apple Push Notifications)
                     └──────────────────┘

       ┌──────────────────────────────────────────────────────┐
       │            Apple Watch companion app                 │
       │  (Pairs with iPhone via WatchConnectivity;           │
       │   shows turn indicator, soundboard buttons,          │
       │   tap-to-log-set, basic ledger glance)               │
       └──────────────────────────────────────────────────────┘
```

### Components

**iOS client (Swift / SwiftUI):**
- UI layer using SwiftUI for views; MVVM-ish pattern with reactive view models.
- Services (singletons or dependency-injected):
  - `SupabaseClient` — network + realtime.
  - `AudioSession` — manages `AVAudioSession` configuration; the **critical mix-with-others** setup for soundboard.
  - `LocationProvider` — `whenInUse` location for geofence check-in.
  - `PushReceiver` — APNs token registration; handles `UNUserNotificationCenterDelegate` for push action buttons.
  - `LocalStore` — SwiftData for offline cache (routines, exercises, recent sessions, set_logs, pending writes queue).
  - `HealthKitBridge` — writes completed sessions as `HKWorkout` records with `.functionalStrengthTraining` type.
  - `EventKitBridge` — syncs scheduled sessions to the user's iOS Calendar.
  - `WatchConnectivity` — bidirectional state sync to the Watch companion app.

**Supabase Postgres** — single source of truth for everything persistent. Row Level Security (RLS) policies enforce that a user can only read/write their own data + data for sessions/groups they participate in. RLS is the primary security boundary.

**Supabase Realtime** — three primitives used for different jobs:
- **Presence** — lobby occupancy, typing indicators.
- **Broadcast** — ephemeral events (soundboard plays, emoji reactions, turn pings).
- **postgres_changes** — persistent state updates (set logs, session state, votes, chat messages).

**Supabase Edge Functions (TypeScript)** — thin server-side glue:
- `push-dispatcher` — single entry point for all APNs pushes; called from triggers and other functions.
- `lateness-evaluator` — cron-triggered at session start time; computes who was late, appends burpees.
- `idle-session-detector` — cron that detects idle sessions and triggers wrap-up pushes (see §6.2).
- `leaderboard-recompute` — recalculates rankings when an attempt completes or is edited.
- `account-deletion-cascade` — App Store-required full account deletion with tombstoning of shared records.

**Supabase Storage** — soundboard audio assets, avatar images, exercise demo videos (or links to externally hosted demos).

**APNs** — Apple Push Notifications. Standard.

**Apple Watch companion app** — standalone watchOS target that pairs with the iPhone app via `WatchConnectivity`. Shows whose turn it is, lets the user fire soundboard sounds and log a set from the wrist.

### What's deliberately NOT here (and why)

- **No separate cache / Redis layer.** Postgres + Realtime presence handles v1 scale (single-digit thousands of users) comfortably. Caching is added when measured to be needed.
- **No CDN.** Supabase Storage serves through its own CDN; soundboard audio files are tiny static assets.
- **No analytics pipeline (Amplitude / Mixpanel).** Server-side logging via Sentry is enough for debugging in v1; product analytics waits until we have users worth analyzing.
- **No web client or Android.** v1 is iPhone + Apple Watch only. Because all business logic is server-side (Postgres + Edge Functions), a future Android or web client is additive, not architectural rework.
- **No authoritative server-side session state machine.** The session state machine lives primarily in the iOS client, with Supabase as a sync layer. Server-side authoritative state machines are appropriate when client misbehavior has cross-user consequences; for this app, a misbehaving client mostly hurts only its own user. Easy to revisit if needed.

---

## 3. Data Model

Postgres schema. Loose DDL syntax; exact types and constraints finalized in migrations.

### Identity & Social

```sql
-- Supabase Auth manages `auth.users` (Apple ID, email) automatically.
profiles (
  id                  uuid PRIMARY KEY REFERENCES auth.users(id),
  username            text UNIQUE NOT NULL,           -- chosen at first launch
  display_name        text,
  avatar_url          text,
  created_at          timestamptz DEFAULT now(),
  show_solo_workouts  boolean DEFAULT false           -- opt-in solo visibility
)

friendships (
  user_id             uuid REFERENCES profiles(id),
  friend_id           uuid REFERENCES profiles(id),
  status              text CHECK (status IN ('pending','accepted','blocked')),
  created_at          timestamptz,
  PRIMARY KEY (user_id, friend_id)
)

push_devices (
  id                  uuid PRIMARY KEY,
  user_id             uuid REFERENCES profiles(id),
  apns_token          text UNIQUE NOT NULL,
  last_seen_at        timestamptz
)

groups (
  id                  uuid PRIMARY KEY,
  name                text NOT NULL,
  avatar_url          text,
  created_by          uuid REFERENCES profiles(id),
  default_late_penalty jsonb,                          -- group's lateness rules
  default_routine_id  uuid REFERENCES routines(id),    -- optional pinned routine
  created_at          timestamptz DEFAULT now()
)

group_members (
  group_id            uuid REFERENCES groups(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES profiles(id),
  role                text CHECK (role IN ('admin','member')) DEFAULT 'member',
  joined_at           timestamptz DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
)
```

### Geography (for check-in)

```sql
gyms (
  id                  uuid PRIMARY KEY,
  user_id             uuid REFERENCES profiles(id),
  name                text,                            -- "Home Gym", "Planet Fitness"
  latitude            double precision,
  longitude           double precision,
  radius_meters       integer DEFAULT 200,
  is_primary          boolean DEFAULT false
)
```

### Exercise Library (curated, app-shipped)

```sql
exercises (
  id                  uuid PRIMARY KEY,
  name                text NOT NULL,                   -- "Bench Press"
  slug                text UNIQUE NOT NULL,            -- "bench-press"
  category            text,                            -- "compound", "isolation"
  primary_muscle      text,                            -- "chest"
  secondary_muscles   text[],                          -- ["triceps","front_delts"]
  equipment           text,                            -- "barbell","dumbbell","bodyweight"
  default_unit        text,                            -- "lbs","reps","seconds"
  demo_video_url      text,                            -- short loop demo
  is_user_defined     boolean DEFAULT false            -- v1 = always false; v2 hook
)
```

### Routines (private templates + public published workouts)

```sql
routines (
  id                  uuid PRIMARY KEY,
  owner_id            uuid REFERENCES profiles(id),
  name                text NOT NULL,
  description         text,
  visibility          text CHECK (visibility IN ('private','shared','public')) DEFAULT 'private',
  -- public-workout fields (NULL unless visibility='public'):
  is_featured         boolean DEFAULT false,           -- "The Murph", curated highlights
  default_sort        text,                            -- 'time','volume','top_set','recent'
  scoring_metrics     text[],                          -- which sorts apply
  scoring_top_set_exercise_id uuid REFERENCES exercises(id),
  created_at          timestamptz DEFAULT now(),
  updated_at          timestamptz DEFAULT now()
)

routine_exercises (
  id                  uuid PRIMARY KEY,
  routine_id          uuid REFERENCES routines(id) ON DELETE CASCADE,
  exercise_id         uuid REFERENCES exercises(id),
  position            integer NOT NULL,                -- 1, 2, 3, ...
  target_sets         integer,
  target_reps         text,                            -- "5" or "8-12" or "AMRAP"
  target_weight       text,                            -- "bodyweight", "75% 1RM", "135"
  rest_seconds        integer,
  notes               text,
  UNIQUE (routine_id, position)
)
```

### Sessions

```sql
sessions (
  id                       uuid PRIMARY KEY,
  routine_id               uuid REFERENCES routines(id),
  organizer_id             uuid REFERENCES profiles(id),
  group_id                 uuid REFERENCES groups(id),  -- optional; NULL if ad-hoc
  room_code                text UNIQUE,                  -- for code-based join; NULL if invite-based
  state                    text CHECK (state IN
                           ('scheduled','lobby_open','editing','voting','locked',
                            'in_progress','completed','abandoned')),
  scheduled_for            timestamptz,
  started_at               timestamptz,
  completed_at             timestamptz,
  current_turn_user_id     uuid REFERENCES profiles(id),
  current_turn_started_at  timestamptz,                  -- chess clock source of truth
  late_penalty             jsonb DEFAULT '{"exercise":"burpee","per_minute":5}'::jsonb,
  duration_was_edited      boolean DEFAULT false,
  edited_by                uuid REFERENCES profiles(id),
  created_at               timestamptz DEFAULT now()
)

session_participants (
  session_id          uuid REFERENCES sessions(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES profiles(id),
  turn_order          integer,                         -- for fixed round-robin
  check_in_state      text CHECK (check_in_state IN
                       ('invited','online','ready','late','no_show')),
  check_in_at         timestamptz,
  check_in_method     text,                            -- 'geofence' | 'traveling_override'
  late_minutes        integer DEFAULT 0,
  burpees_owed        integer DEFAULT 0,
  PRIMARY KEY (session_id, user_id)
)

session_duration_edits (
  id                  uuid PRIMARY KEY,
  session_id          uuid REFERENCES sessions(id),
  edited_by           uuid REFERENCES profiles(id),
  old_started_at      timestamptz,
  old_completed_at    timestamptz,
  new_started_at      timestamptz,
  new_completed_at    timestamptz,
  reason              text,
  edited_at           timestamptz DEFAULT now()
)
```

### Live Lobby: Routine Edit Proposals + Votes

```sql
routine_proposals (
  id                      uuid PRIMARY KEY,
  session_id              uuid REFERENCES sessions(id) ON DELETE CASCADE,
  proposer_id             uuid REFERENCES profiles(id),
  proposal_type           text CHECK (proposal_type IN
                          ('add_exercise','remove_exercise','edit_exercise','reorder')),
  payload                 jsonb NOT NULL,
  affects_exercise_id     uuid,                         -- for serializing conflicting edits
  status                  text CHECK (status IN
                          ('open','approved','vetoed','superseded')) DEFAULT 'open',
  resolved_at             timestamptz,
  created_at              timestamptz DEFAULT now()
)

routine_proposal_votes (
  proposal_id         uuid REFERENCES routine_proposals(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES profiles(id),
  vote                text CHECK (vote IN ('approve','veto')),
  voted_at            timestamptz DEFAULT now(),
  PRIMARY KEY (proposal_id, user_id)
)
```

### Set Logs (the ledger)

```sql
set_logs (
  id                  uuid PRIMARY KEY,                -- client-generated for idempotent retry
  user_id             uuid REFERENCES profiles(id),
  session_id          uuid REFERENCES sessions(id),    -- NULL = solo (see notes)
  exercise_id         uuid REFERENCES exercises(id),
  set_index           integer NOT NULL,
  reps                integer,
  weight              numeric(7,2),
  rpe                 numeric(3,1),                    -- 1.0 - 10.0
  is_failed           boolean DEFAULT false,
  is_penalty          boolean DEFAULT false,           -- true for late-penalty burpees
  note                text,
  logged_at           timestamptz DEFAULT now()
)

-- Indexes for ledger queries:
-- (user_id, exercise_id, logged_at DESC)  -- "your bench press history"
-- (user_id, logged_at DESC)               -- "your recent activity"
-- (session_id, user_id, set_index)        -- "everyone's sets this session"

-- Solo workouts: a sessions row IS created (with single participant) so the
-- data model and rendering code stay unified. set_logs.session_id is never NULL.

body_weight_logs (
  id                  uuid PRIMARY KEY,
  user_id             uuid REFERENCES profiles(id),
  weight              numeric(5,2),
  unit                text DEFAULT 'lbs',
  logged_at           timestamptz DEFAULT now()
)
```

### Public Workout Repository: Attempts + Leaderboards

```sql
workout_attempts (
  id                       uuid PRIMARY KEY,
  routine_id               uuid REFERENCES routines(id),   -- must have visibility='public'
  user_id                  uuid REFERENCES profiles(id),
  session_id               uuid REFERENCES sessions(id),
  is_opt_in_leaderboard    boolean DEFAULT false,
  started_at               timestamptz,
  completed_at             timestamptz,
  is_complete              boolean DEFAULT false
)

leaderboard_entries (
  attempt_id          uuid PRIMARY KEY REFERENCES workout_attempts(id) ON DELETE CASCADE,
  routine_id          uuid REFERENCES routines(id),    -- denormalized for fast filter
  user_id             uuid REFERENCES profiles(id),
  time_seconds        integer,                         -- if 'time' applies; else NULL
  total_volume        numeric(10,2),                   -- if 'volume' applies
  top_sets            jsonb,                           -- {exercise_id: best_weight}
  is_complete         boolean,
  is_edited           boolean DEFAULT false,           -- session duration was edited;
                                                        -- time_seconds remains the ORIGINAL
  computed_at         timestamptz DEFAULT now()
)
-- (routine_id, time_seconds ASC NULLS LAST)
-- (routine_id, total_volume DESC NULLS LAST)
```

### Soundboard

```sql
soundboard_sounds (
  id                  uuid PRIMARY KEY,
  slug                text UNIQUE NOT NULL,            -- 'airhorn', 'lets-go'
  display_name        text,
  storage_path        text NOT NULL,                   -- path in Supabase Storage
  duration_ms         integer,
  is_curated          boolean DEFAULT true             -- v1 = always true
)
-- Soundboard PLAYS are not stored. They are broadcast over Realtime as
-- ephemeral events. A chat_messages echo (kind='soundboard_echo') is inserted
-- separately to preserve the play in chat history.
```

### Chat

```sql
chat_messages (
  id                  uuid PRIMARY KEY,
  group_id            uuid REFERENCES groups(id) ON DELETE CASCADE,
  session_id          uuid REFERENCES sessions(id),    -- NULL = group-level chat;
                                                        -- NOT NULL = session sub-thread
  author_id           uuid REFERENCES profiles(id),    -- NULL for system messages
  kind                text CHECK (kind IN
                      ('text','image','system_pr','system_session','system_late',
                       'system_leaderboard','soundboard_echo')) DEFAULT 'text',
  -- system_session = session lifecycle (scheduled/started/completed/abandoned)
  -- system_pr      = inserted by PR trigger on set_logs
  -- system_late    = inserted by lateness-evaluator when burpees are computed
  -- system_leaderboard = inserted when a member's rank changes on a public workout
  -- soundboard_echo = inserted by client after broadcasting a soundboard play
  body                text,
  payload             jsonb,                           -- structured data for system msgs
  storage_path        text,                            -- for images
  reply_to_id         uuid REFERENCES chat_messages(id),
  created_at          timestamptz DEFAULT now(),
  edited_at           timestamptz,
  deleted_at          timestamptz                      -- soft delete
)

chat_message_reactions (
  message_id          uuid REFERENCES chat_messages(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES profiles(id),
  emoji               text NOT NULL,
  PRIMARY KEY (message_id, user_id, emoji)
)

chat_read_state (
  group_id            uuid REFERENCES groups(id),
  user_id             uuid REFERENCES profiles(id),
  last_read_message_id uuid REFERENCES chat_messages(id),
  PRIMARY KEY (group_id, user_id)
)
```

### Moderation

```sql
user_reports (
  id                  uuid PRIMARY KEY,
  reporter_id         uuid REFERENCES profiles(id),
  reported_user_id    uuid REFERENCES profiles(id),
  reported_content_type text,                          -- 'chat_message','routine','profile'
  reported_content_id uuid,
  reason              text,
  created_at          timestamptz DEFAULT now(),
  status              text DEFAULT 'open'              -- 'open','dismissed','actioned'
)
```

### Row Level Security (RLS) — security model

Every table has RLS enabled. Policies in plain English:

- **`profiles`** — anyone can read public fields; only owner can update.
- **`friendships`** — only readable by the two parties involved.
- **`push_devices`** — only readable/writable by the owner.
- **`groups`** + **`group_members`** — readable by group members only.
- **`gyms`** — only readable/writable by the owner. Never shared.
- **`exercises`** — global read, no write (curated content).
- **`routines`** — readable when `visibility='public'`, or when owner, or when the requester is a member of any session referencing this routine. Writable only by owner.
- **`routine_exercises`** — inherits the parent routine's read policy.
- **`sessions`** + **`session_participants`** — readable by participants only.
- **`session_duration_edits`** — readable by participants only.
- **`routine_proposals`** + **`routine_proposal_votes`** — readable by participants of the parent session only.
- **`set_logs`** — readable by the user who logged it, plus participants of the session it belongs to. Solo workouts where `profiles.show_solo_workouts=false` are owner-only; otherwise friends can read.
- **`body_weight_logs`** — owner only.
- **`workout_attempts`** + **`leaderboard_entries`** — readable by anyone if `is_opt_in_leaderboard=true`; otherwise owner-only.
- **`soundboard_sounds`** — global read.
- **`chat_messages`** + **`chat_message_reactions`** + **`chat_read_state`** — readable by group members only. The `deleted_at` soft-delete is respected by the read policy (deleted rows return as `[deleted message]`).
- **`user_reports`** — writable by anyone; readable by reporter + users with the `app_admin` role. The `app_admin` role is granted manually via SQL for v1 (just you); a proper moderation queue UI is deferred to v2 (see §8).

---

## 4. Core User Flows

### Tab structure

Five top-level tabs in the iPhone app:

```
┌─────────┬─────────┬─────────┬─────────┬─────────┐
│  Home   │ Library │ Social  │  Stats  │   You   │
└─────────┴─────────┴─────────┴─────────┴─────────┘
```

- **Home** — dashboard: today's scheduled session, upcoming sessions, recent group chat, quick actions (Start Solo Workout, Schedule Session). Glanceable, not a content destination.
- **Library** — three sub-tabs: **Routines** (your saved templates), **Exercises** (curated library with demo videos), **Discover** (public workout repository with leaderboards). The "lean-back, plan workouts at home" surface.
- **Social** — friends + groups + chat in one tab. List of groups (with unread badges) and direct friends; tapping a group opens chat + sessions + stats sub-views.
- **Stats** — personal ledger: recent activity feed, per-exercise trend charts, PRs hall of fame, body weight trend.
- **You** — profile, settings, home gym management, notification preferences, blocked users, Apple Health sync toggle, sign out.

### Flow 1 — First launch / onboarding

```
App icon tap
  → [Splash] Sign in with Apple sheet
  → Supabase.signInWithIdToken(.apple, idToken) — session + auth.users row created
  → [Onboarding 1/4] Choose username (validates uniqueness server-side)
  → [Onboarding 2/4] Set primary home gym
       • iOS prompts for location-when-in-use permission
       • Map view; "Use my current location" or search
       • Saves gyms row, is_primary=true, radius=200m default
       • "Skip for now" available — falls back to Traveling override
  → [Onboarding 3/4] Push notifications permission
       • Standard iOS prompt; saves APNs token to push_devices
  → [Onboarding 4/4] "What's next?" — three big buttons:
       • Lift with a friend     → Social tab, friend invite flow
       • Try a featured workout → Library → Discover, featured grid
       • Build your routine library → Library → Routines, builder
  → [Home tab]
```

The three-path "what's next" is critical: a brand-new user with no friends needs immediate engagement. The Discover path solves first-launch emptiness; the Build Library path serves users who are not at the gym at signup time.

### Flow 2 — Scheduled session (the marquee flow)

State diagram for `sessions.state`:

```
scheduled → lobby_open → editing → voting → locked → in_progress → completed
    ↓           ↓                                                       ↓
abandoned   abandoned                                                abandoned
```

Walkthrough:

1. **Schedule.** Organizer taps "+ Session" → picks group OR individual friends OR generates room code → picks routine from library (or skips, vote in lobby) → picks date + time → tap Schedule.
   - `sessions` row created with `state='scheduled'`, `scheduled_for=...`.
   - `session_participants` rows created (one per invitee, `check_in_state='invited'`).
   - System message inserted into group chat: "📅 Push Day scheduled for Tue Mar 12, 7:00 PM. Routine: Tommy's Push v2."
   - APNs push to all invitees: "Tommy invited you to Push Day."

2. **15 minutes before scheduled_for:** Edge Function cron fires → APNs push to all participants: "Push Day starts in 15 min. Tap to enter lobby."

3. **Lobby opens.** First participant opens the lobby → `sessions.state → 'lobby_open'`. Each participant joining the lobby publishes Realtime Presence to channel `lobby:{session_id}` with state `{app_state, check_in_state}`. Lobby UI shows:
   - Routine summary card.
   - Participant list with states (⬜ online · ✅ ready · 🚫 not joined).
   - "Edit Routine" button (state → `editing`).
   - "Check In" button (per-user; runs geofence check against home gym OR offers Traveling override; on success, `check_in_state='ready'`).

4. **Routine editing (optional).** Any participant may propose edits:
   - "Edit Routine" → state → `editing`.
   - Add / Remove / Edit / Reorder → creates a `routine_proposals` row.
   - Realtime card on all participants' screens: "Tommy proposed: add Pull-ups 4×6. [Approve] [Veto]".
   - Each tap creates a `routine_proposal_votes` row.
   - One veto → status `vetoed`, proposal grays out.
   - Unanimous approve → status `approved`, routine updated.
   - Conflicting concurrent edits to the same exercise are serialized via the `affects_exercise_id` lock; second proposer sees "this exercise has an open proposal" notice.

5. **Start.** When all `check_in_state='ready'`, organizer's "Start Session" button unlocks. Tap → `state → in_progress`, `started_at = now()`.
   - Lateness evaluator runs: anyone whose `check_in_at > scheduled_for` has `late_minutes` and `burpees_owed` computed.
   - System message: "🏁 Push Day started. 👀 Sarah is 7 min late — owes 35 burpees."

6. **In-session UI for the current lifter:**

   ```
   ┌────────────────────────────────────────────┐
   │  Exercise 1 of 4: Bench Press              │
   │  Set 1 of 5  • Target: 5 reps @ 185 lbs    │
   │                                            │
   │           [ ▶ GO ]                         │
   │                                            │
   │  Other lifters: Sarah ⏸  Mike ⏸            │
   │  [🔊 Soundboard]  [😀 React]               │
   └────────────────────────────────────────────┘
   ```

   When my turn starts, local timer counts up from `current_turn_started_at`. Tap "Done" → log sheet (reps spinner, weight field, RPE slider, optional note). Submit → `set_logs` INSERT → Realtime postgres_changes notifies all participants. PR trigger fires on the server (see §5). Turn passes to next user by `turn_order`.

7. **Soundboard + reactions** flow at all times. Broadcast over `session:{session_id}` channel. Each play also inserts a `chat_messages` row with `kind='soundboard_echo'` so it persists in chat history.

8. **End.** Organizer (or any participant) taps "End Session":
   - If anyone has `burpees_owed > 0`, append a "Penalty" block: target sets logged with `is_penalty=true` (excluded from PR comparisons and trend charts).
   - `state → completed`, `completed_at = now()`.
   - System message: "✅ Push Day complete — 47 sets logged. Tommy hit a PR on Bench. Sarah owes 35 burpees (logged 30 so far)."
   - If session was a public-workout attempt, `leaderboard_entries` row computed; if `is_opt_in_leaderboard=true`, appears on public leaderboard.
   - HealthKit: `HKWorkout` written with `.functionalStrengthTraining` type, duration, exercise stats.

9. **Recap screen** per participant: today's lifts summary, PRs hit, total volume, time, partners, reaction emoji counts, tap into ledger.

### Flow 3 — Solo workout

Home → "Quick Workout" → pick routine from library → solo session UI (same chess clock, no turn rotation, no soundboard/reactions visible since no partners). PR detection works identically (compares against your historical max). On end, writes HealthKit record and updates ledger.

Solo workouts DO create a `sessions` row (with single participant) — keeps data model and rendering code unified.

### Flow 4 — Public workout attempt (e.g., "The Murph")

Library → Discover → tap "The Murph". Workout detail page shows description, scoring metrics, leaderboard (sortable by Time / Total Volume / Top Set / Recent — default sort set by creator).

Two big CTAs: **Attempt Solo** (launches Flow 3 with the public routine pre-selected) and **Attempt with Friends** (launches Flow 2 schedule sheet pre-loaded). "Show me on leaderboard" toggle is opt-in per attempt.

On completion, `workout_attempts` row is created and `leaderboard_entries` is computed across all applicable metrics. If `is_opt_in_leaderboard=true`, entry is visible on the public leaderboard. A system message lands in the user's group chat: "Tommy attempted The Murph — finished in 42:13 (#187 globally)."

### Flow 5 — Creating a group + chatting

Social → "+ Group" → name, avatar, add members. Group view has three sub-tabs:
- **Chat** — text + reactions + system messages (PRs, RSVPs, lateness, leaderboards, soundboard echoes).
- **Sessions** — past + upcoming sessions for this group.
- **Stats** — collective metrics (total sessions, PRs, volume), per-member leaderboards.

Chat works via Supabase Realtime subscription to `chat:{group_id}`. Reactions via separate subscription. Read state updated by the receiving client when a message comes into view.

### Flow 6 — Late arrival + idle detection

**Late arrival:**
- Session starts at `scheduled_for`; participants not yet `ready` enter `late` state.
- Push to other participants: "👀 Sarah is 3 min late."
- Sarah opens app, checks in late. `late_minutes = now() - scheduled_for`. `burpees_owed = late_minutes × per_minute_rate`.
- Sarah's UI shows routine prefixed with Penalty block.
- She can grind burpees at start, end, or sprinkled in. Same logging UI; `is_penalty=true`.
- If `late_minutes` exceeds threshold (default 15), `check_in_state → no_show`; session continues without her. She can still join late but burpees compound.

**Idle detection ladder** (replaces simple flat auto-abandon):

```
Session is in_progress with no activity for:
  • 30 min → APNs push to ORGANIZER with [Wrap Up] [Still Going] actions.
              Wrap Up sets completed_at = last_activity_at; state → completed.
              Still Going resets 30-min timer.
  • 60 min → APNs push to ALL PARTICIPANTS with same actions.
  • 6 hours → Edge Function cron auto-transitions to 'abandoned'.
              Participants' set_logs are kept; no leaderboard entry computed.
```

"Activity" = any new `set_logs`, soundboard broadcast, chat message in session thread, or app foreground for >5s by any participant.

**Manual session duration edit** (on completed sessions):
- Pencil icon next to "Duration: 1h 47m" on session detail screen.
- Editable by organizer OR any participant.
- Editable: `started_at`, `completed_at` (duration derived). Set log timestamps NOT editable.
- On save: `duration_was_edited=true`, `edited_by` set; HealthKit re-write; `session_duration_edits` audit row inserted.
- **Leaderboard time is locked to original.** If the session was a public-workout attempt, `leaderboard_entries.time_seconds` does NOT update; an "✏️ edited" indicator appears next to the entry (link explains: "duration corrected by participant after session"). Other metrics (volume, top sets) update normally since they derive from set logs.

---

## 5. Realtime Layer

### Primitives at a glance

| Primitive | Job |
|---|---|
| **Presence** | Lobby occupancy ("who has the app open"), typing indicators |
| **Broadcast** | Soundboard plays, emoji reactions, turn pings — ephemeral events |
| **postgres_changes** | Session state, set logs, votes, chat messages, leaderboards — persistent |

### Channel naming scheme

```
lobby:{session_id}                ← Presence
session:{session_id}              ← Broadcast (soundboard, reactions, pings)
session:{session_id}:db           ← postgres_changes (session-related rows)
chat:{group_id}                   ← postgres_changes (chat_messages, reactions)
chat:{group_id}:typing            ← Presence (typing indicators)
discover:leaderboard:{routine_id} ← postgres_changes (leaderboard updates)
user:{user_id}                    ← postgres_changes (friend requests, invites)
```

Every channel has a clearly bounded audience — no wildcards, no global channels.

### Per-feature wire shapes

**Lobby presence** (`lobby:{session_id}`)

```json
{
  "user_id": "uuid",
  "username": "tommy",
  "app_state": "active",
  "check_in_state": "ready"
}
```

Snapshot delivered to all clients on any membership change. Lobby UI renders from snapshot. Backgrounding the app drops presence within ~30s; persistent `session_participants.check_in_state` in DB is unaffected.

**Session state changes** (`session:{session_id}:db`)

Subscribed to changes on `sessions`, `session_participants`, `set_logs`, `routine_proposals`, `routine_proposal_votes`. Events arrive with `eventType`, `old`, `new`.

The chess clock is **computed locally** from `current_turn_started_at`. The client renders `now() - that` at 60Hz with a `Timer`. No server tick. When turn changes, the UPDATE event arrives and the clock resets. Cheapest possible architecture for a high-frequency UI element. Also means offline reconnect "just works" — the clock keeps ticking even with no network.

**Set log + PR detection**

INSERT on `set_logs` propagates to all participants. Postgres trigger fires:

```sql
CREATE TRIGGER pr_check AFTER INSERT ON set_logs
  FOR EACH ROW EXECUTE FUNCTION check_and_announce_pr();
```

The trigger function compares `NEW.weight` against `MAX(weight)` for `(user_id, exercise_id)` excluding `is_penalty=true` and `is_failed=true`. If new max, INSERT a `chat_messages` row with `kind='system_pr'`. The client picks up the new chat message via the chat channel subscription and renders the PR animation.

**Soundboard + reactions** (`session:{session_id}` broadcast)

```json
{
  "type": "broadcast",
  "event": "soundboard",
  "payload": { "user_id": "...", "sound_slug": "airhorn", "ts": 1741800000123 }
}
```

Client-side rate limit: 1 sound per second per user. After firing, originating client ALSO inserts a `chat_messages` row with `kind='soundboard_echo'` for persistence.

**Routine voting**

Standard `postgres_changes` on `routine_proposals` + `routine_proposal_votes`. When vote count reaches `participants.count` with no vetoes, a server trigger marks `status='approved'` and applies the change. Any veto → `vetoed`. Clients animate proposals based on status flips.

**Chat** (`chat:{group_id}`)

`postgres_changes` on `chat_messages WHERE group_id = ?`. Reactions are a separate subscription. Read state updated on view.

**Typing indicators** (`chat:{group_id}:typing`)

Presence-based. `track()` self with `{typing: true}` on input; `untrack()` on stop or 5s timeout.

### Disconnection and reconnection

1. **Mid-session network drop.** Realtime disconnect callback fires. Local state freezes at last-known. Small "Reconnecting…" pill at top of screen (non-blocking; mid-bench-press modals would be hostile). Chess clock keeps ticking locally because it's derived from a timestamp, not pushed.

2. **On reconnect.** Re-subscribe to all channels. For each `postgres_changes` channel, REST-fetch current state (`SELECT * FROM sessions WHERE id=...`, etc.). Why: postgres_changes only delivers events that occurred while subscribed; refetch ensures consistency.

3. **Missed broadcast events** (soundboard plays during disconnect) are lost by design. Chat echoes provide persistent record.

4. **Set log written while offline.** SwiftData local store queues the write. UI shows it optimistically with "syncing" indicator. On reconnect, queued INSERT is sent. Idempotent on retry because PKs are client-generated UUIDs.

5. **Organizer disconnects mid-session.** Session continues. "End Session" button is not organizer-only.

6. **Everyone disconnects.** Session stays `in_progress`. First participant to reopen sees it as resumable. Chess clock resumes from `current_turn_started_at`. Idle detection (§4 Flow 6) eventually fires if session is truly abandoned.

### Scale and rate limits

| Concern | Plan |
|---|---|
| Realtime channel concurrency | ~3 channels × N clients per session. At v1 scale (~thousands MAU, <100 concurrent sessions), well within Supabase free tier. |
| Soundboard event spam | Client-side: 1/sec/user. Server-side: no validation in v1; if abuse appears, replace direct broadcast with RLS-checked function call. |
| postgres_changes for chat at large groups | Bound to `group_id`; max group size v1 = 25. Trivial event rate. |
| Leaderboard update fanout | Featured workouts could have thousands of subscribers; updates only on attempt completion, so volume stays low. |

---

## 6. Cross-cutting Concerns

### 6.1 Audio session config (hard requirement)

**Soundboard sounds, emoji reaction sounds, "your turn" pings, and PR celebration audio must mix with — never interrupt, pause, or duck — the user's music.** Non-negotiable.

```swift
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

    func configure() throws {
        // .ambient = does NOT take audio focus; respects existing playback
        // .mixWithOthers = our sounds layer on top of Spotify/Apple Music/etc.
        // NO .duckOthers (that would lower music volume — wrong)
        try session.setCategory(
            .ambient,
            mode: .default,
            options: [.mixWithOthers]
        )
        try session.setActive(true)
    }
}
```

| Setting | Choice | Why |
|---|---|---|
| Category | `.ambient` | Secondary audio; music apps stay primary. |
| `.mixWithOthers` | **on** | Simultaneous playback with other apps' audio. Most important option. |
| `.duckOthers` | **off** | Would lower music volume during our playback. |
| `.interruptSpokenAudioAndMixWithOthers` | **off** | Would pause podcasts/audiobooks. |

Soundboard playback uses a pool of `AVAudioPlayer` instances (one per concurrent play, capped at 8) so simultaneous sounds layer cleanly:

```swift
final class SoundboardPlayer {
    private var activePlayers: [AVAudioPlayer] = []
    func play(soundURL: URL) throws {
        let player = try AVAudioPlayer(contentsOf: soundURL)
        player.delegate = self  // remove from activePlayers on finish
        player.prepareToPlay()
        player.play()
        activePlayers.append(player)
        if activePlayers.count > 8 { activePlayers.removeFirst() }
    }
}
```

**Verification matrix** (manual, before every TestFlight; see §7):
1. Spotify + airhorn: music must continue at full volume.
2. Apple Music + airhorn: same.
3. Apple Podcasts + airhorn: same.
4. Silent mode on: sounds do NOT play (correct ambient behavior).
5. App backgrounded: sounds do NOT play (correct; backgrounded soundboard would be hostile).

**Regression guard:** unit test asserts `AVAudioSession.sharedInstance().categoryOptions.contains(.mixWithOthers) == true` after `AudioSessionManager.configure()`.

### 6.2 Sign in with Apple

```swift
import AuthenticationServices

// On "Sign in with Apple" button tap:
let request = ASAuthorizationAppleIDProvider().createRequest()
request.requestedScopes = [.fullName, .email]
// ASAuthorizationController shows the iOS sheet.
// On success: ASAuthorizationAppleIDCredential with identityToken (JWT).

try await supabase.auth.signInWithIdToken(
    credentials: .init(provider: .apple, idToken: idToken)
)
```

Session persisted in iOS Keychain by the Supabase SDK. "Hide My Email" works transparently (Supabase stores the relay address). Sign in with Apple is the only auth provider in v1 — App Store policy §4.8 is fully satisfied.

**Account deletion** (App Store-required): "Delete Account" in You tab → calls `account-deletion-cascade` Edge Function. Cascades: profile, friendships, gyms, push devices, set_logs, owned routines, authored chat messages. Sessions/groups the user was a member of get tombstoned `deleted_user` references (their messages remain anonymized as "Deleted User"), preserving shared records.

### 6.3 Push notifications

All pushes go through Edge Functions → APNs. The `push-dispatcher` Edge Function is the single entry point — called from triggers, cron, and other functions.

| Event | Triggered when | Recipient | Has actions? |
|---|---|---|---|
| `friend_request` | New row in `friendships(status='pending')` | Recipient | Accept / Decline |
| `session_invite` | New `session_participants` row | Each invitee | View / Decline |
| `session_reminder_15min` | Cron, 15 min before `scheduled_for` | All participants | View |
| `session_lobby_open` | `sessions.state → lobby_open` and you weren't there yet | All participants | Open Lobby |
| `your_turn` | `sessions.current_turn_user_id` changes to you | The new lifter | Open Session |
| `partner_pr` | `system_pr` chat message inserted | Other group members | View |
| `lateness_chirp` | A participant flips to `late` state | Other participants | Roast (opens soundboard at them) |
| `session_idle_30min` | Cron detects idle | Organizer | Wrap Up / Still Going |
| `session_idle_60min` | Cron detects idle | All participants | Wrap Up / Still Going |
| `leaderboard_passed` | A leaderboard entry knocks you down a rank | The passed user | View Leaderboard |
| `chat_mention` | @username appears in a chat_message | Mentioned user | Reply |

Per-category opt-outs in You tab. Defaults: all on for v1.

**Action buttons** use `UNNotificationCategory` with action identifiers handled by `UNUserNotificationCenterDelegate`. Wrap-Up and RSVP perform background URLSession requests to the relevant Edge Function — no app launch required.

### 6.4 Offline behavior

The app is **offline-first for write operations on your own data**, online-required for everything social/realtime.

**Offline-capable:**
- Logging sets (queued in SwiftData)
- Browsing your own routine library
- Browsing your own ledger / past sessions (last 90 days cached)
- Editing your routines
- Browsing exercises (curated library bundled in app binary; demo videos stream on demand)

**Online-required:**
- Joining or running a live session
- Chat
- Discover / leaderboards
- Friend requests, group operations
- PR detection (server-side trigger needs the write)

**Local store:** SwiftData (iOS 17+ Apple-blessed). Cached: profile, friends, groups (metadata only — not messages), routines (full), exercises (full), past sessions (last 90 days), set_logs (last 90 days), pending writes queue.

**Conflict resolution:** All writes have client-generated UUID PKs → INSERTs are idempotent on retry. Updates to your own routines (the only offline-editable thing) use last-write-wins on `updated_at`.

### 6.5 Error handling philosophy

1. **Network failures are normal, not exceptional.** Every Supabase call goes through a wrapper that distinguishes recoverable from terminal errors. No generic "Something went wrong" — every error path has a specific human-readable message and, where applicable, a Retry action.
2. **Optimistic UI for user-initiated writes.** Tap "Log Set" → set appears immediately with faint "syncing" indicator. If write fails server-side, inline retry (not a modal that breaks flow).
3. **Pessimistic UI for state-machine transitions.** Tap "Start Session" → button disables, spinner until server confirms. Don't optimistically transition; cost of mis-rendering is high.
4. **No silent failures.** Every catch block either retries, surfaces, or logs to Sentry. Empty catch is a code review red flag.
5. **Crash reports via Sentry.** Each crash includes sanitized `SessionState` snapshot (no chat content, no PII) for reproducibility.
6. **Realtime disconnects show non-blocking banners**, never modals. "Reconnecting…" pill at top of screen.

---

## 7. Testing Strategy

### Test layers

```
┌─────────────────────────────────┐
│  Manual device tests            │  ← AVAudioSession, Watch sync,
│  (real iPhone + real Spotify)   │     geofence accuracy
├─────────────────────────────────┤
│  E2E UI tests (XCUITest)        │  ← the 6 user flows
│  Hits staging Supabase project  │
├─────────────────────────────────┤
│  Integration tests              │  ← RLS, triggers, Edge Functions,
│  Postgres + Realtime, no client │     leaderboard math
├─────────────────────────────────┤
│  Unit tests (XCTest)            │  ← state machines, view models,
│  Pure Swift, no network         │     scoring computations
└─────────────────────────────────┘
```

### Unit (XCTest, Swift, hermetic)

- Lobby/session state machine transitions; invalid transitions must throw.
- Round-robin turn rotation logic (skipping no-shows).
- Chess clock derivation (timezone + DST edge cases).
- Per-set PR computation (excluding penalty and failed sets).
- Leaderboard metric computation (time, total_volume, top_set per exercise).
- Late-minute calculation (rounded, multiplied, capped at no_show threshold).
- Plate math (target weight + bar weight → plate stack).
- Offline write queue (enqueue → drain → conflict resolution).
- Audio session config assertion (regression guard from §6.1).

### Integration (Postgres + Supabase Realtime, no iOS)

- **RLS policy tests** for every table. Each policy paired with positive ("user X CAN read row Y") AND negative ("user Z CANNOT read row Y") cases. **Missing negative tests are a merge blocker.** This is the most important integration test category.
- PR trigger: insert `set_logs` row that beats previous max → assert `chat_messages` row with `kind='system_pr'` is inserted.
- Leaderboard recompute trigger: insert `workout_attempts` → assert `leaderboard_entries` correct; update set_logs → assert leaderboard updates.
- Penalty appendix: insert participant with `late_minutes=7`, `per_minute=5` → assert `burpees_owed=35`.
- Routine proposal voting: N approves → status `approved` + routine updated. One veto → status `vetoed`, routine unchanged.
- Edge Function tests: push-dispatcher fired with mock event → assert correct APNs payload.
- Idle detection cron: simulate session with last activity at T-31min → assert organizer push generated.
- Realtime fanout: two clients subscribed to session channel; insert set log; assert both receive.

### E2E (XCUITest hitting dedicated staging Supabase project)

The six user flows from §4, each as one test (onboarding, scheduled session with stubbed second participant, solo workout, public workout attempt, group chat, late arrival). Slow — runs on PR + nightly, not every commit.

### Manual device tests (real iPhone, before every TestFlight)

- **AVAudioSession verification matrix** (§6.1): Spotify + airhorn, Apple Music + airhorn, Podcasts + airhorn, silent mode, app backgrounded. Cannot be CI-tested.
- **Apple Watch flow:** start session on phone, verify watch shows turn indicator; tap "Done" on watch, verify phone updates; fire soundboard from watch, verify phone plays it.
- **Geofence accuracy:** check in from inside saved home gym → success; from a coffee shop → fails with traveling-override prompt. Both indoor (poor GPS) and outdoor.
- **Push notification action buttons:** receive `session_idle_30min` on lock screen, tap "Wrap Up" → verify session state transitions without opening app.
- **Sign in with Apple flow:** including "Hide My Email" and "Use Different Apple ID" paths.

### High-risk areas (silent failure-prone)

**RLS policies.** Pair every positive read test with a negative read test. A permissive policy is a silent vulnerability. Test fixture creates known users/friendships/sessions/logs; every policy gets paired tests.

**Realtime reconnection.** Manual airplane-mode toggle during active session. Assertions: chess clock keeps ticking; missed set_logs appear on reconnect; soundboard plays during disconnect are lost (correct); session state catches up to current, not stale-last-known.

**Audio session config.** Manual matrix + unit test regression guard. The unit test catches "someone changed the category"; cannot catch "iOS update broke `.mixWithOthers`" — that's why the manual matrix stays in the TestFlight checklist.

### CI lanes

```
on PR:        unit + integration + RLS policy tests              (~3 min)
on PR (UI):   E2E XCUITest against staging Supabase              (~10 min)
nightly:      full E2E + load test (100 concurrent sessions)
on tag:       build + sign + TestFlight upload + manual checklist
```

The "manual checklist" on tag is a Slack message with the 5-item manual device test list. No TestFlight build ships until ticked off.

---

## 8. Open questions / deferred decisions

These are tunable parameters and items deliberately deferred. Listed here so they're not lost.

### Tunable defaults (need to be picked, but not architecturally load-bearing)

- **Burpees per minute late** — default to 5. Group-configurable.
- **No-show threshold** — default 15 min late → `check_in_state=no_show`. Group-configurable.
- **Idle detection thresholds** — 30 min (organizer push), 60 min (all participants), 6 hours (auto-abandon).
- **Geofence radius** — default 200 m. Per-gym configurable.
- **Group size cap** — 25 in v1.
- **Soundboard rate limit** — 1 sound per second per user (client-side).
- **Offline cache window** — 90 days of past sessions and set_logs in SwiftData.
- **Set log fields** — reps, weight, RPE (1–10), optional note. No tempo, no drop sets in v1.

### Deferred to v2

- Achievements / badges system
- Supersets / circuits (breaks the round-robin chess clock; needs design work)
- Search across ledger
- Progress photos
- Warm-up vs. working set distinction
- Auto-suggested groups from recurring participants
- Live audio / group call during sessions
- User-defined custom exercises with structured variants
- Web client / Android client
- Public profile pages / user-discoverable feed
- Server-authoritative session state machine (if client-side proves insufficient at scale)

### Future considerations

- **App Store name.** "GymSync" is a working title; a quick App Store search shows several apps with similar names. Production name TBD.
- **Moderation queue UI.** v1 grants the `app_admin` role manually via SQL and reads `user_reports` directly through a Postgres client. A real moderation queue UI is deferred to v2 (or later — depends on actual report volume).
- **Curated exercise library content.** ~150–300 records with metadata + demo videos. Seedable from Free Exercise DB (public source). Not engineering work — content work.
- **Soundboard sound library.** Curated set of fun, gym-appropriate sounds (airhorn, "LET'S GO", etc.). Licensing/sourcing TBD.
- **Featured public workouts.** Initial seed set ("The Murph", strength program templates, hypertrophy splits). Content work.

---

*End of design document.*
