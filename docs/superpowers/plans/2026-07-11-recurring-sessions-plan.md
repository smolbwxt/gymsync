# Gym Sync — Recurring Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Teams-style recurring sessions — weekly pattern with per-day routines, until-date bounded, materialized upfront, with Edit/Cancel × Occurrence/Series semantics and late-joiner auto-invites.

**Architecture:** Per approved spec [`docs/superpowers/specs/2026-07-11-recurring-sessions-design.md`](../specs/2026-07-11-recurring-sessions-design.md) — series entity (`session_series` + `session_series_days`) anchors the rule; every occurrence is a real `sessions` row bulk-created client-side; announcements are suppressed per-occurrence and replaced by one `finalize_series` RPC summary; a trigger auto-invites new group members to future sessions.

**Tech Stack:** Same as Phase 3a. pgTAP via `node scripts/run_pgtap.js`; migrations via `export $(grep -v '^#' .env.local | xargs) && npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`.

## Global Constraints

- All Phase 3a global constraints apply verbatim (RLS + positive/negative pgTAP per policy; CTE row-count for UPDATE/DELETE negatives, throws_ok('42501') for INSERT; SECURITY DEFINER helpers for cross-table RLS; repositories as enums with ErrorMapping; no print/force-unwraps; CI-verified Swift; append-only migrations).
- **Next free migration numbers: `20260713000001+`** (hotfixes consumed `20260712000006/7`).
- **NEW (3a QA lesson):** any postgres_changes subscription must ship its publication migration in the same task. This plan adds NO new subscriptions — series changes manifest via the already-published `sessions` table.
- Weekday convention: **1=Sunday … 7=Saturday** (Swift `Calendar.component(.weekday)`), CHECK-constrained in DB.
- until_date cap: **26 weeks** from creation (DB CHECK + client clamp). Series require a group (v1).
- Series ops are client-orchestrated and non-transactional — documented limitation; ops must be safe to re-run.
- Branch `feature/recurring-sessions`; `gh pr create --base master`.
- CI loop (Swift tasks): commit → push → wait ~20s → `"/c/Program Files/GitHub CLI/gh.exe" run watch $("/c/Program Files/GitHub CLI/gh.exe" run list --workflow ios.yml --branch feature/recurring-sessions --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status --interval 60` — BLOCK until it returns.

## Explicitly deferred (do NOT build)

- Forever/rolling series, monthly patterns, multiple slots per weekday, ad-hoc friend-set series, detached-occurrence exception preservation, timezone migration on organizer move, series push notifications (3d).

## File Structure

```
supabase/migrations/
├── 20260713000001_session_series.sql          # Task 1
├── 20260713000002_series_announcements.sql    # Task 2 (suppression + finalize RPC + sessions DELETE policy)
└── 20260713000003_late_joiner_invites.sql     # Task 3
supabase/tests/
├── rls_series_test.sql                        # Task 1
├── series_announcements_test.sql              # Task 2
└── late_joiner_test.sql                       # Task 3
GymSyncApp/GymSync/
├── Models/SessionSeries.swift                 # Task 4 (models + SeriesRepository)
├── Features/Sessions/ScheduleSessionView.swift# Task 5 (repeats section)
├── Features/Sessions/LobbyView.swift          # Task 6 (Teams menus)
├── Features/Sessions/SeriesEditorView.swift   # Task 6
├── Features/Home/HomeView.swift               # Task 6 (🔁 badge)
└── Features/Social/GroupView.swift            # Task 6 (🔁 badge)
GymSyncApp/GymSyncTests/
└── SeriesRepositoryTests.swift                # Task 4
```

---

### Task 0: Branch

- [ ] `cd /g/Projects/GymSync && git checkout master && git pull --ff-only && git checkout -b feature/recurring-sessions`

---

### Task 1: Series schema + RLS

**Files:** Create `supabase/migrations/20260713000001_session_series.sql`; Test `supabase/tests/rls_series_test.sql`.

**Interfaces:**
- Consumes: `groups`, `is_group_member`, `is_group_admin` (Phase 2), `sessions` (3a shape).
- Produces: tables per spec; helper `is_series_organizer(uuid, uuid)` SECURITY DEFINER; helper `series_group_id(uuid) RETURNS uuid` SECURITY DEFINER; `sessions.series_id` column. Task 4 inserts into all three tables directly.

- [ ] **Step 1: failing pgTAP** — `supabase/tests/rls_series_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000b9', 'sr-a@t.com'),
  ('00000000-0000-0000-0000-0000000000c9', 'sr-b@t.com'),
  ('00000000-0000-0000-0000-0000000000d9', 'sr-c@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000b9', 'sr_user_a'),
  ('00000000-0000-0000-0000-0000000000c9', 'sr_user_b'),
  ('00000000-0000-0000-0000-0000000000d9', 'sr_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('aa000000-0000-0000-0000-000000000001', 'Series Crew',
   '00000000-0000-0000-0000-0000000000b9');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b9', 'admin'),
  ('aa000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000c9', 'member');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b9';

-- Positive: group member creates a series + days
SELECT lives_ok(
  $$INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
    ('bb000000-0000-0000-0000-000000000001',
     'aa000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b9',
     'America/New_York', (now() + interval '8 weeks')::date)$$,
  'organizer creates series');
SELECT lives_ok(
  $$INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
    ('bb000000-0000-0000-0000-000000000001', 2, '19:00'),
    ('bb000000-0000-0000-0000-000000000001', 4, '19:00')$$,
  'organizer adds series days');

-- Negative: until_date beyond 26 weeks (23514)
SELECT throws_ok(
  $$INSERT INTO session_series (group_id, organizer_id, timezone, until_date) VALUES
    ('aa000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b9',
     'America/New_York', (now() + interval '30 weeks')::date)$$,
  '23514', NULL, 'until_date capped at 26 weeks');

-- Member B: read yes, mutate no
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c9';
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series$$, ARRAY[1], 'group member reads series');
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series_days$$, ARRAY[2], 'group member reads days');
SELECT results_eq(
  $$WITH upd AS (UPDATE session_series SET until_date = until_date + 7 RETURNING 1)
    SELECT count(*)::int FROM upd$$, ARRAY[0], 'non-organizer cannot edit series');
SELECT results_eq(
  $$WITH del AS (DELETE FROM session_series_days RETURNING 1)
    SELECT count(*)::int FROM del$$, ARRAY[0], 'non-organizer cannot delete days');

-- Outsider C: invisible
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000d9';
SELECT results_eq(
  $$SELECT count(*)::int FROM session_series$$, ARRAY[0], 'outsider cannot read series');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2:** `node scripts/run_pgtap.js` → FAILS (relation absent).
- [ ] **Step 3: migration** — `supabase/migrations/20260713000001_session_series.sql`:

```sql
CREATE TABLE public.session_series (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  organizer_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  timezone      text NOT NULL,
  until_date    date NOT NULL,
  late_penalty  jsonb NOT NULL DEFAULT '{"exercise":"burpee","per_minute":5}'::jsonb,
  ended_at      timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (until_date <= (created_at + interval '26 weeks')::date)
);

CREATE TABLE public.session_series_days (
  series_id  uuid NOT NULL REFERENCES public.session_series(id) ON DELETE CASCADE,
  weekday    int NOT NULL CHECK (weekday BETWEEN 1 AND 7),  -- 1=Sunday (Swift Calendar)
  time_local time NOT NULL,
  routine_id uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  PRIMARY KEY (series_id, weekday)
);

ALTER TABLE public.sessions
  ADD COLUMN series_id uuid REFERENCES public.session_series(id) ON DELETE SET NULL;
CREATE INDEX sessions_series_idx ON public.sessions(series_id)
  WHERE series_id IS NOT NULL;

ALTER TABLE public.session_series      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_series_days ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.series_group_id(p_series_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT group_id FROM public.session_series WHERE id = p_series_id;
$$;

CREATE OR REPLACE FUNCTION public.is_series_organizer(p_series_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.session_series
                 WHERE id = p_series_id AND organizer_id = p_user_id);
$$;

CREATE POLICY "group members read series"
  ON public.session_series FOR SELECT TO authenticated
  USING (public.is_group_member(session_series.group_id, auth.uid()));
CREATE POLICY "organizer creates series in own group"
  ON public.session_series FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid()
              AND public.is_group_member(session_series.group_id, auth.uid()));
CREATE POLICY "organizer updates series"
  ON public.session_series FOR UPDATE TO authenticated
  USING (organizer_id = auth.uid()) WITH CHECK (organizer_id = auth.uid());
CREATE POLICY "organizer deletes series"
  ON public.session_series FOR DELETE TO authenticated
  USING (organizer_id = auth.uid());

CREATE POLICY "group members read series days"
  ON public.session_series_days FOR SELECT TO authenticated
  USING (public.is_group_member(
           public.series_group_id(session_series_days.series_id), auth.uid()));
CREATE POLICY "organizer writes series days"
  ON public.session_series_days FOR INSERT TO authenticated
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid()));
CREATE POLICY "organizer updates series days"
  ON public.session_series_days FOR UPDATE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid()))
  WITH CHECK (public.is_series_organizer(session_series_days.series_id, auth.uid()));
CREATE POLICY "organizer deletes series days"
  ON public.session_series_days FOR DELETE TO authenticated
  USING (public.is_series_organizer(session_series_days.series_id, auth.uid()));
```

- [ ] **Step 4:** push + `node scripts/run_pgtap.js` → ALL TESTS PASSED. (Recount `plan(N)` against actual assertions.)
- [ ] **Step 5:** commit `feat(db): session series schema with organizer RLS and 26-week cap`.

---

### Task 2: Announcement suppression + finalize RPC + sessions DELETE policy

**Files:** Create `supabase/migrations/20260713000002_series_announcements.sql`; Test `supabase/tests/series_announcements_test.sql`.

**Interfaces:**
- Consumes: `announce_session_lifecycle` (from `20260712000002` — READ it; CREATE OR REPLACE verbatim plus ONE new early-return), `chat_messages`, `session_series(_days)` (Task 1).
- Produces: sessions with `series_id` do NOT announce on INSERT (start/complete/abandon still announce); RPC `finalize_series(p_series_id uuid) RETURNS void` — raises `P0001 'only the series organizer may finalize'` for non-organizers, else inserts ONE `system_session` message: body `'🔁 Sessions scheduled ' || <Sun/Mon/…-joined weekday abbreviations ordered by weekday> || ' until ' || to_char(until_date,'Mon DD')`, payload `{series_id, until_date}`; NEW sessions DELETE policy: `organizer_id = auth.uid() AND state = 'scheduled'`. Task 4 calls the RPC and relies on the DELETE policy.

- [ ] **Step 1: failing pgTAP** — `supabase/tests/series_announcements_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(7);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000e9', 'sa-a@t.com'),
  ('00000000-0000-0000-0000-0000000000f9', 'sa-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000e9', 'sa_user_a'),
  ('00000000-0000-0000-0000-0000000000f9', 'sa_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('cc110000-0000-0000-0000-000000000001', 'Announce Crew',
   '00000000-0000-0000-0000-0000000000e9');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('cc110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000e9', 'admin'),
  ('cc110000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000f9', 'member');
INSERT INTO session_series (id, group_id, organizer_id, timezone, until_date) VALUES
  ('dd110000-0000-0000-0000-000000000001',
   'cc110000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000e9',
   'America/New_York', (now() + interval '4 weeks')::date);
INSERT INTO session_series_days (series_id, weekday, time_local) VALUES
  ('dd110000-0000-0000-0000-000000000001', 2, '19:00'),
  ('dd110000-0000-0000-0000-000000000001', 6, '07:00');

-- Bulk series-occurrence inserts stay SILENT
INSERT INTO sessions (id, organizer_id, group_id, series_id, state, scheduled_for) VALUES
  ('ee110000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001',
   'dd110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '1 day'),
  ('ee110000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001',
   'dd110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '3 days');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001' AND kind='system_session'$$,
  ARRAY[0], 'series occurrences do not announce individually');

-- Non-series sessions still announce
INSERT INTO sessions (organizer_id, group_id, state, scheduled_for) VALUES
  ('00000000-0000-0000-0000-0000000000e9',
   'cc110000-0000-0000-0000-000000000001', 'scheduled', now() + interval '2 days');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001' AND kind='system_session'$$,
  ARRAY[1], 'single sessions still announce');

SET LOCAL role authenticated;

-- Non-organizer cannot finalize
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f9';
SELECT throws_ok(
  $$SELECT public.finalize_series('dd110000-0000-0000-0000-000000000001')$$,
  'P0001', 'only the series organizer may finalize',
  'non-organizer cannot finalize');

-- Organizer finalizes → exactly ONE summary containing weekday abbreviations
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000e9';
SELECT lives_ok(
  $$SELECT public.finalize_series('dd110000-0000-0000-0000-000000000001')$$,
  'organizer finalizes');
SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='cc110000-0000-0000-0000-000000000001'
      AND kind='system_session' AND body LIKE '🔁%Mon%Fri%'$$,
  ARRAY[1], 'one series summary with weekday names');

-- Sessions DELETE policy: organizer deletes scheduled, member cannot
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM sessions WHERE id='ee110000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1], 'organizer deletes own scheduled session');
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000f9';
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM sessions WHERE id='ee110000-0000-0000-0000-000000000002' RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[0], 'non-organizer cannot delete sessions');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2:** run → FAILS (first assertion: 2 announcements exist; finalize_series absent).
- [ ] **Step 3: migration** — `supabase/migrations/20260713000002_series_announcements.sql`: CREATE OR REPLACE `announce_session_lifecycle()` — copy the CURRENT body from `20260712000002` verbatim and add, immediately after the `group_id IS NULL` early-return:

```sql
  IF TG_OP = 'INSERT' AND NEW.series_id IS NOT NULL THEN
    RETURN NEW;  -- series occurrences announce once via finalize_series
  END IF;
```

then append:

```sql
CREATE OR REPLACE FUNCTION public.finalize_series(p_series_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_series public.session_series%ROWTYPE;
  v_days   text;
BEGIN
  SELECT * INTO v_series FROM public.session_series
    WHERE id = p_series_id AND organizer_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'only the series organizer may finalize';
  END IF;
  SELECT string_agg(
           CASE weekday WHEN 1 THEN 'Sun' WHEN 2 THEN 'Mon' WHEN 3 THEN 'Tue'
                        WHEN 4 THEN 'Wed' WHEN 5 THEN 'Thu' WHEN 6 THEN 'Fri'
                        ELSE 'Sat' END, '/' ORDER BY weekday)
    INTO v_days
    FROM public.session_series_days WHERE series_id = p_series_id;
  INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
  VALUES (v_series.group_id, NULL, 'system_session',
          '🔁 Sessions scheduled ' || COALESCE(v_days, '?')
            || ' until ' || to_char(v_series.until_date, 'Mon DD'),
          jsonb_build_object('series_id', p_series_id,
                             'until_date', v_series.until_date));
END;
$$;

CREATE POLICY "organizer deletes own scheduled sessions"
  ON public.sessions FOR DELETE TO authenticated
  USING (organizer_id = auth.uid() AND state = 'scheduled');
```

- [ ] **Step 4:** push + full suite green (existing `session_system_messages_test` must stay green — non-series inserts unaffected).
- [ ] **Step 5:** commit `feat(db): series announcement suppression, finalize RPC, scheduled-session delete policy`.

---

### Task 3: Late-joiner auto-invite trigger

**Files:** Create `supabase/migrations/20260713000003_late_joiner_invites.sql`; Test `supabase/tests/late_joiner_test.sql`.

**Interfaces:**
- Consumes: `group_members` (has BEFORE trigger `group_size_cap` — the new AFTER trigger coexists), `sessions`, `session_participants`.
- Produces: `AFTER INSERT ON group_members` trigger `invite_new_member_to_future_sessions` (SECURITY DEFINER) inserting `('invited')` participant rows for that group's `state='scheduled' AND scheduled_for > now()` sessions, `ON CONFLICT DO NOTHING`. Applies to series and single sessions alike.

- [ ] **Step 1: failing pgTAP** — `supabase/tests/late_joiner_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-00000000a1a1', 'lj-a@t.com'),
  ('00000000-0000-0000-0000-00000000b1b1', 'lj-b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-00000000a1a1', 'lj_user_a'),
  ('00000000-0000-0000-0000-00000000b1b1', 'lj_user_b');
INSERT INTO groups (id, name, created_by) VALUES
  ('ff220000-0000-0000-0000-000000000001', 'Joiner Crew',
   '00000000-0000-0000-0000-00000000a1a1');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('ff220000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-00000000a1a1', 'admin');
-- one future scheduled, one past scheduled, one started
INSERT INTO sessions (id, organizer_id, group_id, state, scheduled_for) VALUES
  ('ab330000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'scheduled', now() + interval '2 days'),
  ('ab330000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'scheduled', now() - interval '2 days'),
  ('ab330000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-00000000a1a1',
   'ff220000-0000-0000-0000-000000000001', 'in_progress', now() + interval '3 days');

-- B joins the group → invited to the FUTURE scheduled session only
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('ff220000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-00000000b1b1', 'member');

SELECT results_eq(
  $$SELECT count(*)::int FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY[1], 'new member invited to exactly one session');
SELECT results_eq(
  $$SELECT session_id::text FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY['ab330000-0000-0000-0000-000000000001'], 'the future scheduled one');
SELECT results_eq(
  $$SELECT check_in_state FROM session_participants
    WHERE user_id='00000000-0000-0000-0000-00000000b1b1'$$,
  ARRAY['invited'], 'as invited');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2:** run → FAILS (count 0).
- [ ] **Step 3: migration** — `supabase/migrations/20260713000003_late_joiner_invites.sql`:

```sql
CREATE OR REPLACE FUNCTION public.invite_new_member_to_future_sessions()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  INSERT INTO public.session_participants (session_id, user_id, check_in_state)
  SELECT s.id, NEW.user_id, 'invited'
  FROM public.sessions s
  WHERE s.group_id = NEW.group_id
    AND s.state = 'scheduled'
    AND s.scheduled_for > now()
  ON CONFLICT (session_id, user_id) DO NOTHING;
  RETURN NEW;
END;
$$;
CREATE TRIGGER invite_new_member_to_future_sessions
  AFTER INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.invite_new_member_to_future_sessions();
```

- [ ] **Step 4:** push + full suite green (group-creation bootstrap inserts fire the trigger with zero matching sessions — no-op; existing group tests unaffected).
- [ ] **Step 5:** commit `feat(db): auto-invite new group members to future scheduled sessions`.

---

### Task 4: SessionSeries models + SeriesRepository (Swift)

**Files:** Create `GymSyncApp/GymSync/Models/SessionSeries.swift`; Test `GymSyncApp/GymSyncTests/SeriesRepositoryTests.swift`.

**Interfaces:**
- Consumes: Tasks 1-3 schema/RPC/policies; `SessionRepository` conventions (READ `Models/Session.swift` + `SessionRepository.swift`); `GroupRepository.members`.
- Produces (Tasks 5-6 compile against these EXACT signatures):
  - `struct SessionSeries: Codable, Identifiable, Sendable` — `id, groupID, organizerID, timezone: String, untilDate: Date, endedAt: Date?, createdAt` (snake_case CodingKeys; `until_date` is a DATE column — decode via the repository using a `yyyy-MM-dd` strategy or fetch as String and convert; implementer picks the cleaner and documents)
  - `struct SeriesDay: Codable, Sendable, Hashable` — `seriesID, weekday: Int (1=Sun…7=Sat), timeLocal: String ("HH:mm:ss" or "HH:mm" — match what PostgREST returns for `time`), routineID: UUID?`
  - `enum SeriesRepository`:
    - `create(groupID: UUID, days: [SeriesDay's inputs — use a small struct `SeriesDayInput { weekday: Int; hour: Int; minute: Int; routineID: UUID? }`], untilDate: Date, timezone: TimeZone = .current) async throws -> SessionSeries` — inserts series + days; **materializes**: for each calendar day from tomorrow-or-today through untilDate (inclusive) in `timezone`, if its weekday is in the rule and the combined date+time is strictly future → bulk-insert a `sessions` row (`state='scheduled'`, `series_id`, day's `routine_id`, series `late_penalty` default) + participant rows (organizer `online`, every other current group member `invited`); then calls RPC `finalize_series`. Use ONE bulk insert per table (array payloads), not per-row requests.
    - `occurrences(seriesID: UUID) async throws -> [WorkoutSession]` (scheduled_for ascending)
    - `series(id: UUID) async throws -> SessionSeries?`; `seriesDays(seriesID: UUID) async throws -> [SeriesDay]`
    - `cancelOccurrence(sessionID: UUID) async throws` (DELETE sessions row)
    - `cancelSeriesForward(seriesID: UUID) async throws` — UPDATE ended_at=now, DELETE future scheduled occurrences
    - `editSeriesForward(seriesID: UUID, days: [SeriesDayInput], untilDate: Date) async throws` — update series.until_date, replace days rows, DELETE future scheduled occurrences, re-materialize (shared private helper with create), finalize_series again (posts updated summary)
  - Materialization helper must be a pure static `static func occurrenceDates(days: [SeriesDayInput], from: Date, until: Date, timezone: TimeZone) -> [(date: Date, input: SeriesDayInput)]` — unit-testable without network.
- **Tests** (`SeriesRepositoryTests`):
  - Hermetic: `occurrenceDates` — fixed tz America/New_York, fixed `from` (construct a known Wednesday), Mon+Fri rule for 2 weeks → exactly 4 dates, all strictly after `from`, all weekday-correct, times 19:00 local; DST boundary case (a range crossing 2026-11-01 US fall-back keeps 19:00 local).
  - Live DB: create group → series Mon+Wed until +13 days → occurrence count == hermetic-computed expectation; every occurrence has `seriesID` set and self as participant; exactly ONE 🔁 system message in group chat; `cancelSeriesForward` empties future occurrences; cleanup deletes group.
- CI loop per Global Constraints; commit `feat: series repository — materialization, finalize, teams series ops`.

---

### Task 5: ScheduleSessionView repeats section

**Files:** Modify `GymSyncApp/GymSync/Features/Sessions/ScheduleSessionView.swift` (READ fully first).

**Interfaces:** Consumes `SeriesRepository.create` + `SeriesDayInput` (Task 4). `onScheduled` callback fires with the FIRST occurrence (so Home navigation still works).

Behavior (contract):
- New "Repeats" section, visible ONLY when WHO == Group. Toggle "Repeat weekly". When on: 7 weekday chips (S M T W T F S); each selected weekday reveals a row: time picker (default = the main WHEN time) + optional routine picker (default = the main routine selection). Until-date picker (default +8 weeks, clamped ≤ +26 weeks, ≥ +1 day). Footer text "N sessions will be scheduled" computed live via `SeriesRepository.occurrenceDates`.
- Schedule button: when repeating → `SeriesRepository.create(...)`, call `onScheduled(firstOccurrence)` (fetch via `occurrences(...).first`), dismiss; single-session path unchanged.
- Commit `feat: weekly repeat configuration in schedule sheet` (NO push — Task 6 completes the compile unit if needed; if Task 5 compiles standalone, push + CI).

---

### Task 6: Teams menus + 🔁 badges

**Files:** Modify `LobbyView.swift`, `HomeView.swift`, `GroupView.swift`; Create `Features/Sessions/SeriesEditorView.swift` (READ all first).

**Interfaces:** Consumes Task 4 repository + `currentSession ?? session` pattern (LobbyView already refetches the session row — hotfix 5264b39).

Behavior (contract):
- **Badges**: Home upcoming rows and GroupView session rows show `Image(systemName: "repeat")` when `session.seriesID != nil` (add `seriesID` decode to `WorkoutSession` if Task 4 didn't — check).
- **LobbyView toolbar** (visible only while state=='scheduled' or 'lobby_open'): Menu "Manage".
  - Non-series session: "Change time" (sheet: DatePicker → UPDATE via a new small `SessionRepository.reschedule(sessionID:to:)` — add it in this task following repo conventions), "Cancel session" (confirmation → `SeriesRepository.cancelOccurrence` → dismiss).
  - Series session (seriesID != nil): "Edit this session" (same change-time sheet), "Edit series…" (SeriesEditorView sheet), "Cancel this session" (confirm → cancelOccurrence → dismiss), "Cancel rest of series" (confirm with occurrence count → cancelSeriesForward → dismiss). Organizer-only items hidden for others (compare organizerID to currentProfile.id).
- **SeriesEditorView(seriesID:)**: loads series + days via Task 4 getters, same weekday-chip editor as Task 5's repeats section (extract a shared `WeekdayRuleEditor` view used by both), Save → `editSeriesForward` → dismiss. Shows "applies to future sessions only" caption.
- Push (compiles Tasks 5+6 together if 5 wasn't pushed), CI green. Commit `feat: teams-style series menus, editor, and repeat badges`.

---

### Task 7: Ship

- [ ] `node scripts/run_pgtap.js` → ALL TESTS PASSED.
- [ ] `gh pr create --base master --title "Recurring sessions — Teams-style weekly series" --body` (summary + QA checklist below).
- [ ] Merge after CI green (auto-deploys TestFlight).
- [ ] Device QA (controller drives ci_test_user_2 via existing scripts):
  1. Schedule Mon/Wed/Fri series 4 weeks out → ONE 🔁 chat summary; occurrence count correct in footer & Upcoming; 🔁 badges
  2. Cancel one occurrence → gone from lists, others intact
  3. Edit series forward (change a weekday/time) → future occurrences regenerate; updated 🔁 summary posts
  4. Cancel rest of series → future occurrences gone; past/started intact
  5. Late joiner: remove ci_test_user_2 from group (or use a fresh group), re-add → they gain invites to all future occurrences (script `sessions` shows them)
  6. Regression: single-session scheduling still announces 📅 once; lobby flows intact

---

## Self-Review Notes (already applied)

- **Spec coverage:** schema/RLS (T1), suppression+RPC+DELETE policy (T2), late-joiner (T3), materialization+series ops (T4), Repeats UI (T5), Teams menus+editor+badges (T6) — all spec sections mapped. Known limitations carried in spec, not re-implemented.
- **Type consistency:** `SeriesDayInput{weekday,hour,minute,routineID}` used by Tasks 4/5/6; `SeriesRepository` method names identical across tasks; weekday 1=Sun everywhere.
- **Announcement trigger edit is fix-forward** (CREATE OR REPLACE copying current live body from `20260712000002` — NOT editing the applied migration).
- **plan(N) counts:** implementers recount per file (Task 1 test shown with 8; verify).
- **Tasks 4-6 are contract-style** (implementers must read existing Session/Lobby/Schedule files) — same proven 3a approach; migrations are verbatim.
