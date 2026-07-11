# Gym Sync — Phase 3a: Scheduled Sessions + Lobby Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the first half of the marquee flow — schedule a session with your group (or by room code), get a pre-game lobby with live presence, geofence check-in with traveling override, collaborative routine editing with unanimous voting, and a gated Start that computes lateness penalties.

**Architecture:** Fix-forward migrations extend the Phase 1 `sessions`/`session_participants` tables with the full spec columns (group link, room code, chess-clock fields, penalty config). New `routine_proposals`/`routine_proposal_votes` tables carry lobby editing; a Postgres trigger resolves votes (unanimous approve applies the change server-side, any veto kills it). A `LobbyRealtimeService` combines Presence (`lobby:{session_id}`) with postgres_changes (`sessions`, `session_participants`, proposals, votes). Check-in is client-side CoreLocation against the user's `gyms` row, with a Traveling override. Session lifecycle system messages land in group chat.

**Tech Stack:** iOS 17+, SwiftUI, CoreLocation, supabase-swift 2.51 (Realtime Presence + postgres_changes), pgTAP, fix-forward migrations.

## Phase 3 Roadmap (this plan is 3a)

| Sub-phase | Scope | Depends on | Plan status |
|---|---|---|---|
| **3a (THIS PLAN)** | Schedule flow, lobby presence, geofence check-in, routine proposals + voting, Start gating + lateness evaluation, session system messages | Phase 2.5 | Executable below |
| 3b | In-session experience: chess clock (local render from `current_turn_started_at`), round-robin turn rotation, partner set-log feed, penalty block logging, End Session, recap screen, session duration edit | 3a | Plan written when 3a ships |
| 3c | Soundboard (curated sounds bucket, broadcast channel, AVAudioPlayer pool, chat echoes) + emoji reactions in-session + **voice messages in chat** (hold-to-record, `.playAndRecord` category swap that restores `.ambient+.mixWithOthers` — must not break the Phase 1 audio regression guard) | 3a (voice: none — chat only) | Plan written when 3b ships |
| 3d | Push notifications: APNs key, `push_devices` table, `push-dispatcher` Edge Function, session reminders cron, idle-detection ladder, notification actions | 3a (events exist) | Plan written when 3c ships |

Until 3d, everything works via in-app realtime; there are simply no pushes when the app is closed.

## Global Constraints

- **iOS 17.0** minimum; **Swift 5.9+**.
- **RLS on every new table; every policy positive + negative pgTAP.** INSERT WITH CHECK → `throws_ok('42501')`; UPDATE/DELETE negatives → row-count CTE.
- **Applied migrations are append-only.** Next free numbers start after Phase 2.5's `20260711000004` — use `20260712000001+`.
- **Cross-table RLS via existing SECURITY DEFINER helpers** (`is_session_participant`, `is_session_organizer`, `is_group_member`).
- **Sessions readable by participants only** (spec §3 RLS) — scheduling into a group does NOT make it group-readable; invitees become participants at schedule time.
- **Chess-clock fields land in 3a but are driven in 3b**: `current_turn_user_id`, `current_turn_started_at` are nullable and untouched by 3a logic.
- **Client-generated UUID PKs** for all inserts.
- **Repositories are enums wrapping `SupabaseService.shared.client`**; `ErrorMapping.map`; `GymSyncError.unauthorized/.notFound`; no `print()`; no production force-unwraps.
- **No local Xcode** — Swift verification via CI `build-test`; backend via `node scripts/run_pgtap.js`.
- **Location**: `NSLocationWhenInUseUsageDescription` already in project.yml. Check-in geofence: distance ≤ `gyms.radius_meters` (default 200 m). Traveling override always available ("I'm not at my home gym").
- **Late penalty default**: `{"exercise":"burpee","per_minute":5}`; no-show threshold 15 min (evaluated in 3b start/idle logic; 3a computes `late_minutes`/`burpees_owed` at Start).
- **Room codes**: 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789` (no 0/O/1/I/L).
- **Branch `feature/phase-3a-scheduling-lobby`**; `gh pr create --base master` (repo default was wrong once already).
- CI loop: commit → push → wait ~20s → `"/c/Program Files/GitHub CLI/gh.exe" run watch $("/c/Program Files/GitHub CLI/gh.exe" run list --workflow ios.yml --branch feature/phase-3a-scheduling-lobby --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status --interval 60`.

## Explicitly deferred (do NOT build in 3a)

- Chess clock rendering, turn rotation, in-session set logging UI, "your turn" logic (3b) — after Start, 3a lands on a minimal `SessionInProgressView` placeholder showing "Session live — full workout UI ships in 3b" plus an End Session button (state → completed, so QA can complete the loop).
- Soundboard, in-session reactions, voice messages (3c).
- All APNs pushes, cron reminders, idle detection (3d).
- iOS Calendar (EventKit) sync — spec v1 scope but decoupled; slots into 3b polish.
- Session sub-thread chat (`chat_messages.session_id`) — group chat is the only thread until 3b.
- `session_duration_edits` usage (table exists since Phase 1; editing UI is 3b).

## File Structure

```
supabase/migrations/
├── 20260712000001_sessions_phase3_columns.sql     # Task 1
├── 20260712000002_session_system_messages.sql     # Task 2
└── 20260712000003_routine_proposals.sql           # Task 3
supabase/tests/
├── sessions_phase3_test.sql                       # Task 1
├── session_system_messages_test.sql               # Task 2
└── rls_proposals_test.sql                         # Task 3
GymSyncApp/GymSync/
├── Models/Session.swift                           # Task 4 (extend WorkoutSession + repository)
├── Models/RoutineProposal.swift                   # Task 5
├── Services/LobbyRealtimeService.swift            # Task 6
├── Services/CheckInService.swift                  # Task 7 (CoreLocation geofence)
├── Features/Sessions/ScheduleSessionView.swift    # Task 8
├── Features/Sessions/LobbyView.swift              # Task 9
├── Features/Sessions/ProposalCardView.swift       # Task 9
├── Features/Sessions/SessionInProgressView.swift  # Task 9 (placeholder + End)
├── Features/Home/HomeView.swift                   # Task 10 (upcoming sessions + Schedule CTA)
└── Features/Social/GroupView.swift                # Task 10 (Sessions sub-tab now real)
GymSyncApp/GymSyncTests/
├── SessionSchedulingTests.swift                   # Task 4
├── ProposalRepositoryTests.swift                  # Task 5
└── CheckInServiceTests.swift                      # Task 7
```

---

### Task 0.5: Refetch-on-foreground (Phase 2.5 QA finding)

**Files:**
- Modify: `GymSyncApp/GymSync/Features/Social/ChatView.swift`
- Modify: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`

**Why:** Device QA proved that backgrounding drops the realtime socket and missed events never render until the view reloads (spec §5 reconnect: "on reconnect, re-subscribe and REST-fetch current state"). The lobby (Task 9) inherits this pattern.

**Interfaces:**
- Produces: the scenePhase-refetch pattern Task 9's LobbyView must copy.

- [ ] **Step 1:** In `ChatView`, add `@Environment(\.scenePhase) private var scenePhase` to the properties, and alongside the existing view modifiers add:

```swift
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await load() }
        }
```

(`load()` is already idempotent: `realtime.subscribe` tears down the old channel first, and the message fetch replaces state. The dedup guard prevents doubled rows.)

- [ ] **Step 2:** In `SocialTabView`, add the same `@Environment(\.scenePhase)` property and:

```swift
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task {
                    await refresh()
                    if let me = await SupabaseService.shared.currentUserID() {
                        await friendRealtime.subscribe(userID: me) {
                            Task { await refresh() }
                        }
                    }
                }
            }
```

(`FriendRealtimeService.subscribe` self-cleans via `unsubscribe()` first — re-subscribe is safe.)

- [ ] **Step 3:** Commit `fix: refetch + resubscribe realtime on return to foreground`, push (`git push -u origin feature/phase-3a-scheduling-lobby`), CI loop → `build-test` PASS.

---

### Task 1: Sessions Phase-3 columns + participant check-in fields

**Files:**
- Create: `supabase/migrations/20260712000001_sessions_phase3_columns.sql`
- Test: `supabase/tests/sessions_phase3_test.sql`

**Interfaces:**
- Consumes: Phase 1 `sessions`/`session_participants` (see `20260709000006`), `groups` (Phase 2).
- Produces: `sessions` gains `group_id uuid`, `room_code text UNIQUE`, `current_turn_user_id uuid`, `current_turn_started_at timestamptz`, `late_penalty jsonb`, `edited_by uuid`. `session_participants` gains `check_in_at timestamptz`, `check_in_method text CHECK (IN ('geofence','traveling_override'))`, `late_minutes integer DEFAULT 0`, `burpees_owed integer DEFAULT 0`. New RLS: participants may UPDATE their OWN participant row's check-in fields (Phase 1 allowed only the organizer to update participants — check-in requires self-service). Helper `public.evaluate_lateness(p_session_id uuid)` SECURITY DEFINER: for each participant, if `check_in_at > scheduled_for` (or NULL), sets `late_minutes = ceil(extract(epoch from (COALESCE(check_in_at, now()) - scheduled_for))/60)` and `burpees_owed = late_minutes * (late_penalty->>'per_minute')::int`, flips state to `'late'` for checked-in-late users. Callable only by the session organizer (guard inside the function).

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/sessions_phase3_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a6', 's3a@t.com'),
  ('00000000-0000-0000-0000-0000000000b6', 's3b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a6', 's3_user_a'),
  ('00000000-0000-0000-0000-0000000000b6', 's3_user_b');
INSERT INTO sessions (id, organizer_id, state, scheduled_for, late_penalty) VALUES
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a6', 'lobby_open',
   now() - interval '10 minutes',
   '{"exercise":"burpee","per_minute":5}'::jsonb);
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a6', 'ready'),
  ('b0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000b6', 'invited');
-- A checked in on time (before scheduled_for), B checks in 10 min late
UPDATE session_participants SET check_in_at = now() - interval '15 minutes'
  WHERE user_id = '00000000-0000-0000-0000-0000000000a6';

SET LOCAL role authenticated;

-- Positive: B self-serves their own check-in
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b6';
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants
      SET check_in_state='ready', check_in_at=now(), check_in_method='geofence'
      WHERE session_id='b0000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000b6'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'participant can self check-in');

-- Negative: B cannot update A's participant row (0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE session_participants SET check_in_state='no_show'
      WHERE session_id='b0000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000a6'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'participant cannot modify another participant row');

-- Negative: non-organizer cannot run the lateness evaluator
SELECT throws_ok(
  $$SELECT public.evaluate_lateness('b0000000-0000-0000-0000-000000000001')$$,
  'P0001', 'only the session organizer may evaluate lateness',
  'non-organizer cannot evaluate lateness');

-- Positive: organizer runs it; B owes 5/min for ~10 late minutes
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a6';
SELECT lives_ok(
  $$SELECT public.evaluate_lateness('b0000000-0000-0000-0000-000000000001')$$,
  'organizer evaluates lateness');
SELECT results_eq(
  $$SELECT (late_minutes BETWEEN 9 AND 11)::int, (burpees_owed = late_minutes*5)::int
    FROM session_participants
    WHERE session_id='b0000000-0000-0000-0000-000000000001'
      AND user_id='00000000-0000-0000-0000-0000000000b6'$$,
  $$VALUES (1, 1)$$,
  'late participant owes per-minute burpees');
SELECT results_eq(
  $$SELECT late_minutes FROM session_participants
    WHERE session_id='b0000000-0000-0000-0000-000000000001'
      AND user_id='00000000-0000-0000-0000-0000000000a6'$$,
  ARRAY[0], 'on-time participant owes nothing');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: fails — `check_in_at` column / `evaluate_lateness` don't exist.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260712000001_sessions_phase3_columns.sql`:

```sql
ALTER TABLE public.sessions
  ADD COLUMN group_id                uuid REFERENCES public.groups(id) ON DELETE SET NULL,
  ADD COLUMN room_code               text UNIQUE,
  ADD COLUMN current_turn_user_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN current_turn_started_at timestamptz,
  ADD COLUMN late_penalty            jsonb NOT NULL DEFAULT '{"exercise":"burpee","per_minute":5}'::jsonb,
  ADD COLUMN edited_by               uuid REFERENCES public.profiles(id) ON DELETE SET NULL;

ALTER TABLE public.session_participants
  ADD COLUMN check_in_at     timestamptz,
  ADD COLUMN check_in_method text CHECK (check_in_method IN ('geofence','traveling_override')),
  ADD COLUMN late_minutes    integer NOT NULL DEFAULT 0,
  ADD COLUMN burpees_owed    integer NOT NULL DEFAULT 0;

CREATE INDEX sessions_group_scheduled_idx
  ON public.sessions(group_id, scheduled_for DESC) WHERE group_id IS NOT NULL;
CREATE INDEX sessions_scheduled_state_idx
  ON public.sessions(scheduled_for) WHERE state = 'scheduled';

-- Check-in is self-service: participants update their OWN row.
-- (Phase 1 policy only allowed the organizer to update participant rows.)
CREATE POLICY "participant updates own check-in"
  ON public.session_participants FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Lateness evaluation runs as the organizer at Start.
CREATE OR REPLACE FUNCTION public.evaluate_lateness(p_session_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_scheduled timestamptz;
  v_per_minute integer;
BEGIN
  SELECT scheduled_for, COALESCE((late_penalty->>'per_minute')::int, 5)
    INTO v_scheduled, v_per_minute
    FROM public.sessions
    WHERE id = p_session_id AND organizer_id = auth.uid();
  IF v_scheduled IS NULL THEN
    RAISE EXCEPTION 'only the session organizer may evaluate lateness';
  END IF;

  UPDATE public.session_participants sp
  SET late_minutes = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int,
      burpees_owed = GREATEST(0, CEIL(EXTRACT(EPOCH FROM
        (COALESCE(sp.check_in_at, now()) - v_scheduled)) / 60))::int * v_per_minute,
      check_in_state = CASE
        WHEN sp.check_in_at IS NOT NULL AND sp.check_in_at > v_scheduled THEN 'late'
        ELSE sp.check_in_state END
  WHERE sp.session_id = p_session_id
    AND (sp.check_in_at IS NULL OR sp.check_in_at > v_scheduled);
END;
$$;
```

- [ ] **Step 4: Push + full suite** (commands as in prior phases). Expected: ALL TESTS PASSED — Phase 1 session tests must stay green (new columns are nullable/defaulted; new UPDATE policy is additive).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260712000001_sessions_phase3_columns.sql supabase/tests/sessions_phase3_test.sql
git commit -m "feat(db): phase-3 session columns, self-service check-in, lateness evaluator"
```

---

### Task 2: Session lifecycle system messages

**Files:**
- Create: `supabase/migrations/20260712000002_session_system_messages.sql`
- Test: `supabase/tests/session_system_messages_test.sql`

**Interfaces:**
- Consumes: `chat_messages` (`kind='system_session'`), `sessions.group_id` (Task 1), `profiles`, `routines`.
- Produces: trigger `session_lifecycle_announce` AFTER INSERT OR UPDATE OF state ON sessions — when `group_id IS NOT NULL`, inserts a `system_session` chat message on: INSERT with state='scheduled' ("📅 {routine|Workout} scheduled for {scheduled_for} by {username}"), transitions to 'in_progress' ("🏁 Session started"), 'completed' ("✅ Session complete"), 'abandoned' ("🌫️ Session abandoned"). Payload: `{session_id, state, scheduled_for}`.

- [ ] **Step 1: Failing pgTAP test**

Create `supabase/tests/session_system_messages_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a7', 'ss@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a7', 'ss_user_a');
INSERT INTO groups (id, name, created_by) VALUES
  ('c0000000-0000-0000-0000-000000000001', 'Session Crew',
   '00000000-0000-0000-0000-0000000000a7');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('c0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a7', 'admin');

-- Scheduling a group session announces in chat
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a7',
   'c0000000-0000-0000-0000-000000000001',
   'scheduled', now() + interval '1 day');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[1], 'scheduling announces in group chat');

-- Transition to in_progress announces
UPDATE sessions SET state='in_progress', started_at=now()
  WHERE id='d0000000-0000-0000-0000-000000000001';
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[2], 'start announces');

-- Non-state UPDATE does not announce
UPDATE sessions SET current_turn_user_id='00000000-0000-0000-0000-0000000000a7'
  WHERE id='d0000000-0000-0000-0000-000000000001';
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='c0000000-0000-0000-0000-000000000001'
      AND kind='system_session'$$,
  ARRAY[2], 'non-state update stays silent');

-- Ad-hoc (no group) session announces nowhere
INSERT INTO sessions (id, organizer_id, state, scheduled_for) VALUES
  ('d0000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000a7', 'scheduled', now() + interval '1 day');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages WHERE kind='system_session'$$,
  ARRAY[2], 'groupless session announces nothing');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run** → fails (0 messages, trigger absent).

- [ ] **Step 3: Migration**

Create `supabase/migrations/20260712000002_session_system_messages.sql`:

```sql
CREATE OR REPLACE FUNCTION public.announce_session_lifecycle() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_username text;
  v_routine  text;
  v_body     text;
BEGIN
  IF NEW.group_id IS NULL THEN
    RETURN NEW;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;

  SELECT username INTO v_username FROM public.profiles WHERE id = NEW.organizer_id;
  SELECT name INTO v_routine FROM public.routines WHERE id = NEW.routine_id;

  v_body := CASE
    WHEN TG_OP = 'INSERT' AND NEW.state = 'scheduled' THEN
      '📅 ' || COALESCE(v_routine, 'Workout') || ' scheduled for '
           || to_char(NEW.scheduled_for AT TIME ZONE 'UTC', 'Dy Mon DD, HH24:MI')
           || ' UTC by ' || v_username
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'in_progress' THEN
      '🏁 ' || COALESCE(v_routine, 'Session') || ' started'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'completed' THEN
      '✅ ' || COALESCE(v_routine, 'Session') || ' complete'
    WHEN TG_OP = 'UPDATE' AND NEW.state = 'abandoned' THEN
      '🌫️ ' || COALESCE(v_routine, 'Session') || ' abandoned'
    ELSE NULL
  END;

  IF v_body IS NOT NULL THEN
    INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
    VALUES (NEW.group_id, NULL, 'system_session', v_body,
            jsonb_build_object('session_id', NEW.id, 'state', NEW.state,
                               'scheduled_for', NEW.scheduled_for));
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER session_lifecycle_announce
  AFTER INSERT OR UPDATE OF state ON public.sessions
  FOR EACH ROW EXECUTE FUNCTION public.announce_session_lifecycle();
```

- [ ] **Step 4: Push + full suite green.** (Phase 1 session tests insert `state='in_progress'` sessions without groups — the `group_id IS NULL` early return keeps them silent.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260712000002_session_system_messages.sql supabase/tests/session_system_messages_test.sql
git commit -m "feat(db): session lifecycle system messages into group chat"
```

---

### Task 3: Routine proposals + votes + unanimous-approval trigger

**Files:**
- Create: `supabase/migrations/20260712000003_routine_proposals.sql`
- Test: `supabase/tests/rls_proposals_test.sql`

**Interfaces:**
- Consumes: `sessions`, `session_participants`, `is_session_participant`; `routines`, `routine_exercises` (Phase 1).
- Produces: tables per spec §3 (`routine_proposals(id, session_id, proposer_id, proposal_type, payload, affects_exercise_id, status, resolved_at, created_at)`, `routine_proposal_votes(proposal_id, user_id, vote, voted_at)`); RLS: participants of the parent session read/insert both; proposer's vote is auto-cast 'approve' by trigger on proposal insert. Vote-resolution trigger: any 'veto' → `status='vetoed'`; approves == participant count → `status='approved'` AND the payload is applied to `routine_exercises` server-side. Conflict lock: an INSERT for an `affects_exercise_id` that already has an `open` proposal raises exception ('this exercise has an open proposal').
- **Payload shapes (fixed contract for Tasks 5/9):**
  - `add_exercise`: `{"exercise_id": uuid, "position": int, "target_sets": int, "target_reps": text, "target_weight": text|null, "rest_seconds": int|null}`
  - `remove_exercise`: `{"routine_exercise_id": uuid}`
  - `edit_exercise`: `{"routine_exercise_id": uuid, "target_sets": int|null, "target_reps": text|null, "target_weight": text|null, "rest_seconds": int|null}` (NULL = leave unchanged)
  - `reorder`: `{"ordered_routine_exercise_ids": [uuid, ...]}`

- [ ] **Step 1: Failing pgTAP test**

Create `supabase/tests/rls_proposals_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a8', 'pa8@t.com'),
  ('00000000-0000-0000-0000-0000000000b8', 'pb8@t.com'),
  ('00000000-0000-0000-0000-0000000000c8', 'pc8@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a8', 'pr_user_a8'),
  ('00000000-0000-0000-0000-0000000000b8', 'pr_user_b8'),
  ('00000000-0000-0000-0000-0000000000c8', 'pr_user_c8');
INSERT INTO routines (id, owner_id, name) VALUES
  ('e0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a8', 'Lobby Routine');
INSERT INTO sessions (id, organizer_id, routine_id, state, scheduled_for) VALUES
  ('f0000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a8',
   'e0000000-0000-0000-0000-000000000001', 'editing', now());
INSERT INTO session_participants (session_id, user_id, check_in_state) VALUES
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a8', 'ready'),
  ('f0000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b8', 'online');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a8';

-- Positive: participant proposes an add (using seeded bench-press)
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload, affects_exercise_id)
    SELECT '11110000-0000-0000-0000-000000000001',
           'f0000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-0000000000a8',
           'add_exercise',
           jsonb_build_object('exercise_id', e.id, 'position', 1,
                              'target_sets', 4, 'target_reps', '6'),
           e.id
    FROM exercises e WHERE e.slug='bench-press'$$,
  'participant can propose');

-- Proposer's approve vote was auto-cast
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposal_votes
    WHERE proposal_id='11110000-0000-0000-0000-000000000001' AND vote='approve'$$,
  ARRAY[1], 'proposer auto-approves own proposal');

-- Conflict lock: second open proposal on same exercise rejected
SELECT throws_ok(
  $$INSERT INTO routine_proposals (session_id, proposer_id, proposal_type, payload, affects_exercise_id)
    SELECT 'f0000000-0000-0000-0000-000000000001',
           '00000000-0000-0000-0000-0000000000a8',
           'remove_exercise', '{}'::jsonb, e.id
    FROM exercises e WHERE e.slug='bench-press'$$,
  'P0001', 'this exercise has an open proposal',
  'conflicting concurrent edit is serialized');

-- Outsider can neither read nor vote
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c8';
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_proposals$$,
  ARRAY[0], 'outsider cannot read proposals');
SELECT throws_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('11110000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c8', 'approve')$$,
  '42501', NULL, 'outsider cannot vote');

-- B approves -> unanimous (2/2) -> approved + applied to routine_exercises
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b8';
SELECT lives_ok(
  $$INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
    ('11110000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b8', 'approve')$$,
  'second participant approves');
SELECT results_eq(
  $$SELECT status FROM routine_proposals
    WHERE id='11110000-0000-0000-0000-000000000001'$$,
  ARRAY['approved'], 'unanimous approval resolves proposal');
SELECT results_eq(
  $$SELECT count(*)::int FROM routine_exercises re
    JOIN exercises e ON e.id = re.exercise_id
    WHERE re.routine_id='e0000000-0000-0000-0000-000000000001'
      AND e.slug='bench-press'$$,
  ARRAY[1], 'approved add_exercise applied to routine');

-- Veto path: B proposes, A vetoes -> vetoed, not applied
SELECT lives_ok(
  $$INSERT INTO routine_proposals (id, session_id, proposer_id, proposal_type, payload)
    VALUES ('11110000-0000-0000-0000-000000000002',
            'f0000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-0000000000b8',
            'reorder', '{"ordered_routine_exercise_ids":[]}'::jsonb)$$,
  'participant proposes reorder');
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a8';
-- (final assertion counts toward plan: veto resolves)
SELECT results_eq(
  $$WITH v AS (
      INSERT INTO routine_proposal_votes (proposal_id, user_id, vote) VALUES
        ('11110000-0000-0000-0000-000000000002',
         '00000000-0000-0000-0000-0000000000a8', 'veto')
      RETURNING 1)
    SELECT (SELECT status FROM routine_proposals
            WHERE id='11110000-0000-0000-0000-000000000002')$$,
  ARRAY['vetoed'], 'any veto kills the proposal');

SELECT * FROM finish();
ROLLBACK;
```

(Count check: 9 assertions — lives_ok ×3, results_eq ×5, throws_ok ×2 = 10? Recount when writing: adjust `plan(N)` to the true count of assertion calls in the final file.)

- [ ] **Step 2: Run** → fails (tables absent).

- [ ] **Step 3: Migration**

Create `supabase/migrations/20260712000003_routine_proposals.sql`:

```sql
CREATE TABLE public.routine_proposals (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id          uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  proposer_id         uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  proposal_type       text NOT NULL CHECK (proposal_type IN
                        ('add_exercise','remove_exercise','edit_exercise','reorder')),
  payload             jsonb NOT NULL,
  affects_exercise_id uuid,
  status              text NOT NULL DEFAULT 'open'
                        CHECK (status IN ('open','approved','vetoed','superseded')),
  resolved_at         timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX routine_proposals_session_idx
  ON public.routine_proposals(session_id, status);

CREATE TABLE public.routine_proposal_votes (
  proposal_id uuid NOT NULL REFERENCES public.routine_proposals(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  vote        text NOT NULL CHECK (vote IN ('approve','veto')),
  voted_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (proposal_id, user_id)
);

ALTER TABLE public.routine_proposals       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_proposal_votes  ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.proposal_session_id(p_proposal_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT session_id FROM public.routine_proposals WHERE id = p_proposal_id;
$$;

CREATE POLICY "session participants read proposals"
  ON public.routine_proposals FOR SELECT TO authenticated
  USING (public.is_session_participant(routine_proposals.session_id, auth.uid()));

CREATE POLICY "session participants propose as themselves"
  ON public.routine_proposals FOR INSERT TO authenticated
  WITH CHECK (proposer_id = auth.uid()
              AND public.is_session_participant(routine_proposals.session_id, auth.uid()));

CREATE POLICY "session participants read votes"
  ON public.routine_proposal_votes FOR SELECT TO authenticated
  USING (public.is_session_participant(
           public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

CREATE POLICY "session participants vote as themselves"
  ON public.routine_proposal_votes FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_session_participant(
                    public.proposal_session_id(routine_proposal_votes.proposal_id), auth.uid()));

-- Serialize conflicting edits + auto-cast the proposer's approve
CREATE OR REPLACE FUNCTION public.on_proposal_insert() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.affects_exercise_id IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.routine_proposals
    WHERE session_id = NEW.session_id
      AND affects_exercise_id = NEW.affects_exercise_id
      AND status = 'open' AND id <> NEW.id
  ) THEN
    RAISE EXCEPTION 'this exercise has an open proposal';
  END IF;
  INSERT INTO public.routine_proposal_votes (proposal_id, user_id, vote)
  VALUES (NEW.id, NEW.proposer_id, 'approve');
  RETURN NEW;
END;
$$;
-- BEFORE for the conflict check would be cleaner, but the auto-vote needs the
-- row to exist (FK) — use AFTER for the vote and rely on the same-statement
-- visibility of NEW for the conflict check.
CREATE TRIGGER proposal_insert AFTER INSERT ON public.routine_proposals
  FOR EACH ROW EXECUTE FUNCTION public.on_proposal_insert();

-- Vote resolution: veto -> vetoed; approves == participant count -> approved + apply
CREATE OR REPLACE FUNCTION public.resolve_proposal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_proposal   public.routine_proposals%ROWTYPE;
  v_participants integer;
  v_approves     integer;
  v_position     integer;
  v_ids          uuid[];
  v_i            integer;
BEGIN
  SELECT * INTO v_proposal FROM public.routine_proposals
    WHERE id = NEW.proposal_id AND status = 'open' FOR UPDATE;
  IF NOT FOUND THEN
    RETURN NEW;  -- already resolved
  END IF;

  IF NEW.vote = 'veto' THEN
    UPDATE public.routine_proposals
      SET status = 'vetoed', resolved_at = now() WHERE id = v_proposal.id;
    RETURN NEW;
  END IF;

  SELECT count(*) INTO v_participants FROM public.session_participants
    WHERE session_id = v_proposal.session_id;
  SELECT count(*) INTO v_approves FROM public.routine_proposal_votes
    WHERE proposal_id = v_proposal.id AND vote = 'approve';
  IF v_approves < v_participants THEN
    RETURN NEW;
  END IF;

  -- Unanimous: apply to the session's routine
  IF v_proposal.proposal_type = 'add_exercise' THEN
    SELECT COALESCE(MAX(position), 0) + 1 INTO v_position
      FROM public.routine_exercises re
      JOIN public.sessions s ON s.routine_id = re.routine_id
      WHERE s.id = v_proposal.session_id;
    INSERT INTO public.routine_exercises
      (id, routine_id, exercise_id, position, target_sets, target_reps,
       target_weight, rest_seconds)
    SELECT gen_random_uuid(), s.routine_id,
           (v_proposal.payload->>'exercise_id')::uuid,
           COALESCE((v_proposal.payload->>'position')::int, v_position),
           (v_proposal.payload->>'target_sets')::int,
           v_proposal.payload->>'target_reps',
           v_proposal.payload->>'target_weight',
           (v_proposal.payload->>'rest_seconds')::int
    FROM public.sessions s WHERE s.id = v_proposal.session_id;
  ELSIF v_proposal.proposal_type = 'remove_exercise' THEN
    DELETE FROM public.routine_exercises
      WHERE id = (v_proposal.payload->>'routine_exercise_id')::uuid;
  ELSIF v_proposal.proposal_type = 'edit_exercise' THEN
    UPDATE public.routine_exercises re SET
      target_sets  = COALESCE((v_proposal.payload->>'target_sets')::int, re.target_sets),
      target_reps  = COALESCE(v_proposal.payload->>'target_reps', re.target_reps),
      target_weight = COALESCE(v_proposal.payload->>'target_weight', re.target_weight),
      rest_seconds = COALESCE((v_proposal.payload->>'rest_seconds')::int, re.rest_seconds)
    WHERE re.id = (v_proposal.payload->>'routine_exercise_id')::uuid;
  ELSIF v_proposal.proposal_type = 'reorder' THEN
    SELECT array(SELECT jsonb_array_elements_text(
      v_proposal.payload->'ordered_routine_exercise_ids'))::uuid[] INTO v_ids;
    -- two-pass to dodge the UNIQUE(routine_id, position) constraint
    FOR v_i IN 1..COALESCE(array_length(v_ids, 1), 0) LOOP
      UPDATE public.routine_exercises SET position = v_i + 1000 WHERE id = v_ids[v_i];
    END LOOP;
    FOR v_i IN 1..COALESCE(array_length(v_ids, 1), 0) LOOP
      UPDATE public.routine_exercises SET position = v_i WHERE id = v_ids[v_i];
    END LOOP;
  END IF;

  UPDATE public.routine_proposals
    SET status = 'approved', resolved_at = now() WHERE id = v_proposal.id;
  RETURN NEW;
END;
$$;
CREATE TRIGGER proposal_vote_cast AFTER INSERT ON public.routine_proposal_votes
  FOR EACH ROW EXECUTE FUNCTION public.resolve_proposal();
```

- [ ] **Step 4: Push + full suite green.** Note: the routines UPDATE applied by the trigger runs as definer — the routine owner's RLS is bypassed deliberately (unanimous participants may modify the session's routine, per spec Flow 2 step 4).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260712000003_routine_proposals.sql supabase/tests/rls_proposals_test.sql
git commit -m "feat(db): routine proposals + votes with unanimous-approval application"
```

---

### Task 4: Session scheduling repository (iOS)

**Files:**
- Modify: `GymSyncApp/GymSync/Models/Session.swift`
- Test: `GymSyncApp/GymSyncTests/SessionSchedulingTests.swift`

**Interfaces:**
- Consumes: Task 1 columns; existing `WorkoutSession` model + `SessionRepository` (READ `Models/Session.swift` and `Models/SessionRepository.swift` first — extend, don't fork; `startSolo` must keep working).
- Produces (Tasks 8-10 depend on):
  - `WorkoutSession` gains decoded fields: `groupID: UUID?`, `roomCode: String?`, `scheduledFor: Date?`, `state: String` (if not already decoded — match existing model style)
  - `SessionParticipant: Codable` — `sessionID, userID, turnOrder: Int?, checkInState: String?, checkInAt: Date?, checkInMethod: String?, lateMinutes: Int, burpeesOwed: Int`
  - `SessionRepository.schedule(groupID: UUID?, inviteeIDs: [UUID], routineID: UUID?, scheduledFor: Date, generateRoomCode: Bool) async throws -> WorkoutSession` — inserts session `state='scheduled'` (+ room code if requested), inserts organizer + invitee participant rows (`check_in_state='invited'`, organizer `'online'`)
  - `SessionRepository.joinByCode(_ code: String) async throws -> WorkoutSession` — looks up by room_code, inserts self as participant. **RLS note:** sessions are participant-readable only, so the lookup goes through a new SECURITY DEFINER RPC — add to Task 1's migration? No: add here as its own tiny migration `20260712000004_join_by_code.sql` containing `public.join_session_by_code(p_code text) RETURNS uuid` (SECURITY DEFINER: finds scheduled/lobby_open session by code, inserts caller as participant if not already, returns session id) + pgTAP positive/negative (bad code raises 'invalid room code'). Then the Swift call is `client.rpc("join_session_by_code", params: ["p_code": code])`.
  - `SessionRepository.upcoming() async throws -> [WorkoutSession]` — my sessions `state IN ('scheduled','lobby_open','editing','voting','locked')` ordered by scheduled_for
  - `SessionRepository.participants(sessionID: UUID) async throws -> [(participant: SessionParticipant, profile: Profile)]`
  - `SessionRepository.openLobby(sessionID: UUID) async throws` (state → lobby_open if currently scheduled)
  - `SessionRepository.checkIn(sessionID: UUID, method: String) async throws` (own row → ready + check_in_at/method)
  - `SessionRepository.start(sessionID: UUID) async throws` — calls `evaluate_lateness` RPC then updates state → in_progress, started_at
  - `SessionRepository.complete(sessionID: UUID) async throws` (state → completed, completed_at)
  - Room-code generator: 6 chars from `ABCDEFGHJKMNPQRSTUVWXYZ23456789`
- Tests (single-actor, live DB): schedule ad-hoc session with self only → appears in upcoming → openLobby → checkIn(traveling_override) → start → complete; joinByCode with garbage code throws.

(The implementer writes the Swift verbatim following the established repository pattern from `GymGroup.swift`/`ChatMessage.swift`; the exact method signatures above are the binding contract. Full code is authored at implementation time because the existing `Session.swift`/`SessionRepository.swift` shape must be read first — the task reviewer checks contract compliance.)

- [ ] Steps: extend model + repository; add `20260712000004_join_by_code.sql` + pgTAP (positive join, `throws_ok('P0001','invalid room code')`); write `SessionSchedulingTests`; push migration + pgTAP green; commit `feat: session scheduling repository + join-by-code RPC`; push; CI green.

---

### Task 5: RoutineProposal model + repository (iOS)

**Files:**
- Create: `GymSyncApp/GymSync/Models/RoutineProposal.swift`
- Test: `GymSyncApp/GymSyncTests/ProposalRepositoryTests.swift`

**Interfaces:**
- Consumes: Task 3 tables + payload shapes (copy the four payload JSON shapes from Task 3's Interfaces block into Swift structs).
- Produces:
  - `RoutineProposal: Codable, Identifiable, Sendable` — `id, sessionID, proposerID, proposalType: ProposalType, status: Status, affectsExerciseID: UUID?, createdAt` (+ `payload` decoded as `[String: AnyJSON]?` for rendering)
  - `ProposalVote: Codable` — `proposalID, userID, vote: Vote`
  - `ProposalRepository.propose(sessionID: UUID, type: ProposalType, payload: [String: AnyJSON], affectsExerciseID: UUID?) async throws -> RoutineProposal`
  - `ProposalRepository.vote(proposalID: UUID, approve: Bool) async throws`
  - `ProposalRepository.open(sessionID: UUID) async throws -> [RoutineProposal]`
  - `ProposalRepository.votes(proposalIDs: [UUID]) async throws -> [ProposalVote]`
- Tests: propose add_exercise on own single-participant session → auto-approved instantly (participant count 1, proposer auto-vote resolves it) → status approved + routine_exercises row exists; duplicate `affects_exercise_id` proposal throws (`P0001` mapped to `.validation`).

- [ ] Steps: write model + repository + tests; commit `feat: routine proposal model + repository`; push; CI green.

---

### Task 6: LobbyRealtimeService

**Files:**
- Create: `GymSyncApp/GymSync/Services/LobbyRealtimeService.swift`

**Interfaces:**
- Consumes: channels `lobby:{session_id}` (Presence, wire shape spec §5: `{user_id, username, app_state, check_in_state}`) and postgres_changes on `sessions` (UPDATE, filter `id=eq.{sessionID}`), `session_participants` (all events, filter `session_id=eq.{sessionID}`), `routine_proposals` + `routine_proposal_votes` (INSERT+UPDATE, filter `session_id=eq.{sessionID}` / unfiltered votes relying on RLS, mirroring the Phase 2.5 reactions pattern).
- Produces:
  - `@MainActor final class LobbyRealtimeService` with `subscribe(sessionID: UUID, selfID: UUID, username: String, onPresence: @escaping @MainActor (Set<UUID>) -> Void, onChange: @escaping @MainActor () -> Void) async` — presence set = user IDs currently in the lobby; `onChange` fires on ANY db event (caller refetches session + participants + proposals — coarse-grained refresh keeps the service simple)
  - `unsubscribe() async`
  - Tracks self into presence on subscribe (`app_state: "active"`), untracks on unsubscribe.
- Patterned exactly on `ChatRealtimeService` (decoder, task lifecycle, deprecation-tolerant API use). No XCTest (presence needs a second live client) — CI compile + device QA.

- [ ] Steps: implement; commit `feat: lobby realtime service (presence + session db events)`; push; CI green.

---

### Task 7: CheckInService (geofence)

**Files:**
- Create: `GymSyncApp/GymSync/Services/CheckInService.swift`
- Test: `GymSyncApp/GymSyncTests/CheckInServiceTests.swift`

**Interfaces:**
- Consumes: `gyms` table (Phase 1: `user_id, latitude, longitude, radius_meters, is_primary`); CoreLocation.
- Produces:
  - `CheckInService.primaryGym() async throws -> Gym?` (owner-only RLS; `Gym: Codable` model added here if Phase 1 didn't define one — READ `Models/` first)
  - `CheckInService.distanceCheck(gym: Gym, location: CLLocation) -> Bool` — pure function: `location.distance(from: gymLocation) <= Double(gym.radiusMeters)`
  - `CheckInService.requestLocation() async throws -> CLLocation` — one-shot `CLLocationManager` wrapper (continuation-based; throws `.validation("Location unavailable")` on denial/timeout)
- Tests (hermetic, no network/GPS): `distanceCheck` true inside radius / false outside using constructed CLLocations ~150 m and ~500 m apart from a fixed gym coordinate.

- [ ] Steps: implement + tests; commit `feat: check-in service — geofence distance + one-shot location`; push; CI green.

---

### Task 8: ScheduleSessionView

**Files:**
- Create: `GymSyncApp/GymSync/Features/Sessions/ScheduleSessionView.swift`

**Interfaces:**
- Consumes: `SessionRepository.schedule`, `GroupRepository.myGroups/members`, `FriendRepository.friends`, `RoutineRepository` (Phase 1 — READ `Models/Routine.swift` for its list API).
- Produces: `ScheduleSessionView(onScheduled: (WorkoutSession) -> Void)` sheet — pick ONE of: group / individual friends / room code toggle; optional routine picker; date+time picker (default next hour); Schedule button → `SessionRepository.schedule(...)`. Mirrors CreateGroupView's form/error/dismiss conventions.

- [ ] Steps: implement (form sections: Who [group picker segmented with friends multi-select fallback + "Generate room code" toggle], What [routine optional], When [DatePicker]); commit `feat: schedule session sheet`; DO NOT push yet (compile unit completes in Task 9).

---

### Task 9: LobbyView + ProposalCardView + SessionInProgressView placeholder

**Files:**
- Create: `GymSyncApp/GymSync/Features/Sessions/LobbyView.swift`
- Create: `GymSyncApp/GymSync/Features/Sessions/ProposalCardView.swift`
- Create: `GymSyncApp/GymSync/Features/Sessions/SessionInProgressView.swift`

**Interfaces:**
- Consumes: everything from Tasks 4-7.
- Produces: `LobbyView(session: WorkoutSession)`:
  - On appear: `openLobby` if scheduled, subscribe LobbyRealtimeService, load participants/proposals.
  - Routine summary card (name + exercise list via `routine_exercises` fetch).
  - Participant rows: username + presence dot (⬜ offline / 🟢 online via presence set) + check-in state icon (✅ ready, 🕐 invited/online, ⏰ late).
  - Room code banner (tap to copy) when `roomCode != nil`.
  - **Check In button**: geofence flow — `primaryGym()`; if found, `requestLocation()` + `distanceCheck`; success → `checkIn(method: "geofence")`; failure or no gym → confirmation dialog offering Traveling override → `checkIn(method: "traveling_override")`.
  - **Edit Routine**: opens proposal composer (reuse exercise picker pattern from RoutineBuilderView — READ it first); proposals render as `ProposalCardView` ("{user} proposed: add Pull-ups 4×6 [Approve] [Veto]", live vote counts, status-colored when resolved).
  - **Start Session button**: visible to organizer, enabled when all participants `ready` (spec) OR organizer confirms an override dialog ("2 people haven't checked in — start anyway?" → participants stay non-ready, lateness evaluator marks them); calls `SessionRepository.start` → navigates to `SessionInProgressView`.
  - `SessionInProgressView(session:)`: "🏋️ Session live — full workout UI ships in Phase 3b", participant list with burpees owed badges, End Session button → `complete(sessionID:)` → dismiss.
- No XCTest (UI) — CI compile + device QA.

- [ ] Steps: implement all three views; commit `feat: lobby — presence, check-in, proposals, gated start + in-progress placeholder`; push (compiles Tasks 8+9); CI green.

---

### Task 10: Entry points — Home + Group sessions tab

**Files:**
- Modify: `GymSyncApp/GymSync/Features/Home/HomeView.swift`
- Modify: `GymSyncApp/GymSync/Features/Social/GroupView.swift`

**Interfaces:**
- Consumes: `SessionRepository.upcoming`, `ScheduleSessionView`, `LobbyView`.
- Produces: HomeView gains "Upcoming Sessions" section (rows: routine name / group / scheduled time; tap → LobbyView) + "+ Schedule Session" button (sheet) + "Join with Code" field → `joinByCode` → LobbyView. GroupView gains a third segmented sub-tab **Sessions** listing that group's upcoming + past 10 sessions (fetch via `sessions?group_id=eq.` — participant RLS means only sessions you're in appear; empty-state text explains). READ HomeView first and integrate with its existing layout.

- [ ] Steps: implement; commit `feat: session entry points — home upcoming/schedule/join, group sessions tab`; push; CI green.

---

### Task 11: Ship

- [ ] `node scripts/run_pgtap.js` → ALL TESTS PASSED.
- [ ] `gh pr create --base master --title "Phase 3a: Scheduled sessions + lobby" --body` (summary of tasks; device QA checklist below).
- [ ] Merge after CI green (auto-deploys TestFlight).
- [ ] Device QA (controller drives `ci_test_user_2` via `scripts/qa_live_user2.js` extensions — the controller adds session-join/check-in/vote actions to that script during QA):
  1. Schedule a group session → 📅 system message in group chat; appears in Home upcoming
  2. Open lobby → your presence dot green; ci_test_user_2 joins (script) → their dot flips live
  3. Check In with no gym configured → Traveling override path works, state → ready
  4. Propose "add exercise" → card appears; ci_test_user_2 approves (script) → unanimous → routine updates live
  5. Second proposal vetoed by ci_test_user_2 → card grays out
  6. Start with a non-ready participant → override dialog → lateness/burpees computed (visible in in-progress placeholder)
  7. End Session → ✅ system message in chat; session leaves upcoming
  8. Join-by-code: schedule with room code, join from script as ci_test_user_2 → participant appears
  9. Regression: solo workout, chat (text/image/reactions/typing), stats

---

## Self-Review Notes (already applied)

- **Spec coverage (3a slice of Flow 2):** steps 1 (schedule), 2 (reminder push → 3d), 3 (lobby presence + check-in), 4 (editing/voting incl. conflict serialization), 5 (start + lateness evaluator) — covered. Steps 6-9 (in-session, soundboard, end recap) → 3b/3c by design.
- **State machine:** 3a drives scheduled → lobby_open → (editing implicit via proposals) → in_progress → completed. `editing/voting/locked` states exist in the CHECK but 3a treats lobby_open as the umbrella lobby state (proposals allowed while lobby_open); strict sub-state transitions are 3b polish if needed — deviation documented here deliberately to keep 3a shippable.
- **Tasks 4-10 carry contracts, not full Swift listings** — deliberate exception to verbatim-code practice: these tasks must integrate with existing files (`Session.swift`, `HomeView.swift`, `RoutineBuilderView.swift`) whose current shape the implementer must read first. Binding signatures are all specified; task reviewers gate contract compliance. Migration/SQL tasks (1-3) remain fully verbatim since they touch nothing existing.
- **plan(N) counts** in Tasks 1-3 tests: implementer must recount assertion calls and set N accordingly (noted inline in Task 3).
- **Type consistency:** `WorkoutSession` (existing name, NOT `Session` — SwiftData collision), `SessionParticipant`, `RoutineProposal`, `ProposalVote`, `Gym` names used consistently across Tasks 4-10.
