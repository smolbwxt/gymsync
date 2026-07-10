# Gym Sync — Phase 2: Friends, Groups, Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the social layer — friend requests by username, persistent groups (max 25 members), and realtime group chat with reactions, read state, and system PR messages — on top of the Phase 1 foundation.

**Architecture:** Four new Postgres migrations (friendships, groups+members, chat tables, PR-announce trigger) with RLS on every table, following the Phase 1 SECURITY DEFINER helper pattern to break policy recursion. iOS side adds three model+repository pairs, one Realtime service (postgres_changes on `chat_messages`), and a new Social tab (friends list, group list, group chat view). All Supabase calls go through `SupabaseService.shared.client` via repository enums, matching Phase 1.

**Tech Stack:** Same as Phase 1 — iOS 17+, Swift 5.9, SwiftUI, Supabase Swift SDK v2, pgTAP via `node scripts/run_pgtap.js`, migrations via `npx supabase db push --db-url "$SUPABASE_DB_URL" --yes`.

**Design spec:** [`docs/superpowers/specs/2026-06-28-gymsync-design.md`](../specs/2026-06-28-gymsync-design.md) — §3 Identity & Social, §3 Chat, §3 RLS, §4 Flow 5, §5 Realtime.

## Global Constraints

- **iOS 17.0** minimum deployment target. **Swift 5.9+**.
- **RLS enabled on every new Postgres table.** No exceptions.
- **Every RLS policy paired with positive AND negative pgTAP test.** Missing negative test = merge blocker.
- **RLS-filtered UPDATE/DELETE fails silently (0 rows).** Negative tests for UPDATE/DELETE must use row-count CTE assertions (`WITH upd AS (UPDATE ... RETURNING 1) SELECT count(*)::int FROM upd` = 0), NOT `throws_ok`. INSERT `WITH CHECK` violations DO raise `42501` — `throws_ok` is correct there.
- **Cross-table RLS subqueries recurse.** Any policy referencing another RLS table must go through a `SECURITY DEFINER STABLE` helper function (see `20260709000006_create_sessions.sql`).
- **Every persistent write has a client-generated UUID PK** for idempotent retry.
- **All Supabase calls go through repository enums** wrapping `SupabaseService.shared.client`; wrap errors with `ErrorMapping.map(error)`.
- **No `print()`** — use `AppLogger`. **No force-unwraps** outside tests.
- **App name in user-visible strings: "Gym Sync"** (two words). Bundle ID `app.gymsync.ios`.
- **No local Xcode.** Swift verification = push to branch → GitHub Actions `build-test` job (~6 min). Write test + implementation together per task, then push and watch CI. Backend verification is local: `node scripts/run_pgtap.js`.
- **Swift naming:** the groups model is `GymGroup` — plain `Group` collides with `SwiftUI.Group`.
- **Type collision:** `Session` model exists in Phase 1 (`Models/Session.swift` = `WorkoutSession`). Don't shadow.
- **CI network tests run as `ci_test_user`** (creds in `TestSecrets.swift`); tests that need a counterpart account target the seeded `ci_test_user_2` profile (Task 5) but never sign in as it — multi-actor semantics are covered by pgTAP.
- **Commit style:** conventional commits (`feat:`, `test:`, `chore:`), one commit per task minimum. Work on branch `feature/phase-2-social`.

## Explicitly deferred (do NOT build)

- Image chat messages (`kind='image'`, Storage buckets) — later phase; DB column exists, client never sends it.
- Typing indicators (`chat:{group_id}:typing` Presence) — Phase 3 polish.
- Live reaction updates via Realtime — reactions refresh on fetch; only message INSERTs stream.
- Group avatars (Storage upload) — render initials circle; `avatar_url` stays NULL.
- Block/report, push notifications — Phase 10 per roadmap.
- Friend-request realtime channel `user:{user_id}` — friend lists refresh on view appear.
- Group sub-tabs "Sessions" and "Stats" — need Phase 3 `sessions.group_id`; GroupView ships Chat + Members sub-tabs only.

## File Structure

```
supabase/migrations/
├── 20260710000001_create_friendships.sql          # Task 1
├── 20260710000002_create_groups.sql               # Task 2
├── 20260710000003_create_chat.sql                 # Task 3
└── 20260710000004_pr_system_messages.sql          # Task 4
supabase/tests/
├── rls_friendships_test.sql                       # Task 1
├── rls_groups_test.sql                            # Task 2
├── rls_chat_test.sql                              # Task 3
└── pr_system_message_test.sql                     # Task 4
scripts/
└── create_second_test_user.js                     # Task 5
GymSyncApp/GymSync/
├── Models/Friendship.swift                        # Task 6 (model + FriendRepository)
├── Models/GymGroup.swift                          # Task 7 (models + GroupRepository)
├── Models/ChatMessage.swift                       # Task 8 (model + ChatRepository)
├── Models/Profile.swift                           # Task 5 (add fetchByUsername, fetchMany)
├── Services/ChatRealtimeService.swift             # Task 9
├── Features/Social/SocialTabView.swift            # Task 10
├── Features/Social/FriendsView.swift              # Task 10
├── Features/Social/CreateGroupView.swift          # Task 10
├── Features/Social/GroupView.swift                # Task 11
├── Features/Social/ChatView.swift                 # Task 11
└── App/RootView.swift                             # Task 11 (replace Social placeholder)
GymSyncApp/GymSyncTests/
├── FriendRepositoryTests.swift                    # Task 6
├── GroupRepositoryTests.swift                     # Task 7
├── ChatRepositoryTests.swift                      # Task 8
└── ChatRealtimeTests.swift                        # Task 9
```

---

### Task 0: Branch setup

- [ ] **Step 1: Create the working branch**

```bash
cd /g/Projects/GymSync
git checkout master && git pull
git checkout -b feature/phase-2-social
```

---

### Task 1: `friendships` table + RLS

**Files:**
- Create: `supabase/migrations/20260710000001_create_friendships.sql`
- Test: `supabase/tests/rls_friendships_test.sql`

**Interfaces:**
- Produces: table `public.friendships(user_id, friend_id, status, created_at)` — `user_id` is the REQUESTER, `friend_id` the RECIPIENT. Recipient accepts by updating `status='accepted'`. Either party deletes to decline/cancel/unfriend.

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/rls_friendships_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'fa@t.com'),
  ('00000000-0000-0000-0000-00000000000b', 'fb@t.com'),
  ('00000000-0000-0000-0000-00000000000c', 'fc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-00000000000a', 'fr_user_a'),
  ('00000000-0000-0000-0000-00000000000b', 'fr_user_b'),
  ('00000000-0000-0000-0000-00000000000c', 'fr_user_c');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000a';

-- Positive: A can send a pending request to B
SELECT lives_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000b', 'pending')$$,
  'requester can create pending request'
);

-- Negative: A cannot create a request pretending to be B (WITH CHECK -> 42501)
SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000c', 'pending')$$,
  '42501', NULL, 'cannot insert request as another user'
);

-- Negative: A cannot skip pending and insert accepted directly
SELECT throws_ok(
  $$INSERT INTO friendships (user_id, friend_id, status) VALUES
    ('00000000-0000-0000-0000-00000000000a', '00000000-0000-0000-0000-00000000000c', 'accepted')$$,
  '42501', NULL, 'cannot insert pre-accepted friendship'
);

-- Negative: A (requester) cannot accept their own outgoing request (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE friendships SET status='accepted'
      WHERE user_id='00000000-0000-0000-0000-00000000000a'
        AND friend_id='00000000-0000-0000-0000-00000000000b'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'requester cannot self-accept'
);

-- Switch to B (recipient)
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000b';

-- Positive: B sees the incoming request
SELECT results_eq(
  $$SELECT count(*)::int FROM friendships WHERE friend_id='00000000-0000-0000-0000-00000000000b'$$,
  ARRAY[1], 'recipient can read incoming request'
);

-- Positive: B accepts
SELECT results_eq(
  $$WITH upd AS (
      UPDATE friendships SET status='accepted'
      WHERE user_id='00000000-0000-0000-0000-00000000000a'
        AND friend_id='00000000-0000-0000-0000-00000000000b'
      RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'recipient can accept request'
);

-- Switch to C (third party)
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-00000000000c';

-- Negative: C cannot see the A-B friendship
SELECT results_eq(
  $$SELECT count(*)::int FROM friendships$$,
  ARRAY[0], 'third party cannot read others friendships'
);

-- Negative: C cannot delete the A-B friendship (RLS-filtered DELETE = 0 rows)
SELECT results_eq(
  $$WITH del AS (DELETE FROM friendships RETURNING 1) SELECT count(*)::int FROM del$$,
  ARRAY[0], 'third party cannot delete others friendships'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: `rls_friendships_test.sql` FAILS with `relation "friendships" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260710000001_create_friendships.sql`:

```sql
CREATE TABLE public.friendships (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  friend_id  uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','accepted','blocked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, friend_id),
  CHECK (user_id <> friend_id)
);

-- One friendship per pair regardless of direction (no reverse duplicate requests)
CREATE UNIQUE INDEX friendships_canonical_pair_idx
  ON public.friendships (LEAST(user_id, friend_id), GREATEST(user_id, friend_id));
CREATE INDEX friendships_friend_id_idx ON public.friendships(friend_id);

ALTER TABLE public.friendships ENABLE ROW LEVEL SECURITY;

CREATE POLICY "parties can read their friendships"
  ON public.friendships FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR friend_id = auth.uid());

CREATE POLICY "requester creates pending request"
  ON public.friendships FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() AND status = 'pending');

CREATE POLICY "recipient accepts"
  ON public.friendships FOR UPDATE TO authenticated
  USING (friend_id = auth.uid())
  WITH CHECK (friend_id = auth.uid() AND status = 'accepted');

CREATE POLICY "either party deletes"
  ON public.friendships FOR DELETE TO authenticated
  USING (user_id = auth.uid() OR friend_id = auth.uid());
```

- [ ] **Step 4: Push migration, run tests**

```bash
source .env.local 2>/dev/null || export $(grep -v '^#' .env.local | xargs)
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: all suites PASS (existing 18 + new 8 assertions).

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260710000001_create_friendships.sql supabase/tests/rls_friendships_test.sql
git commit -m "feat(db): friendships table with directional request/accept RLS"
```

---

### Task 2: `groups` + `group_members` + RLS + size cap

**Files:**
- Create: `supabase/migrations/20260710000002_create_groups.sql`
- Test: `supabase/tests/rls_groups_test.sql`

**Interfaces:**
- Consumes: `profiles`, `routines` (Phase 1).
- Produces: tables `public.groups(id, name, avatar_url, created_by, default_late_penalty, default_routine_id, created_at)`, `public.group_members(group_id, user_id, role, joined_at)`; SECURITY DEFINER helpers `is_group_member(uuid,uuid)`, `is_group_admin(uuid,uuid)`, `is_group_creator(uuid,uuid)` — Tasks 3 and 4 call `is_group_member`. Creation protocol: client inserts `groups` row, then inserts own `group_members` row with `role='admin'` (bootstrap allowed via `is_group_creator`).

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/rls_groups_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(9);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'ga@t.com'),
  ('00000000-0000-0000-0000-0000000000b1', 'gb@t.com'),
  ('00000000-0000-0000-0000-0000000000c1', 'gc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a1', 'gr_user_a'),
  ('00000000-0000-0000-0000-0000000000b1', 'gr_user_b'),
  ('00000000-0000-0000-0000-0000000000c1', 'gr_user_c');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a1';

-- Positive: A creates a group and bootstraps self as admin
SELECT lives_ok(
  $$INSERT INTO groups (id, name, created_by) VALUES
    ('20000000-0000-0000-0000-000000000001', 'Push Crew',
     '00000000-0000-0000-0000-0000000000a1')$$,
  'creator can insert group'
);
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a1', 'admin')$$,
  'creator can bootstrap self as admin'
);

-- Positive: admin A adds member B
SELECT lives_ok(
  $$INSERT INTO group_members (group_id, user_id, role) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b1', 'member')$$,
  'admin can add a member'
);

-- Switch to member B
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b1';

-- Positive: member B can read the group
SELECT results_eq(
  $$SELECT count(*)::int FROM groups WHERE id='20000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'member can read group'
);

-- Negative: non-admin B cannot add member C (WITH CHECK -> 42501)
SELECT throws_ok(
  $$INSERT INTO group_members (group_id, user_id) VALUES
    ('20000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c1')$$,
  '42501', NULL, 'non-admin cannot add members'
);

-- Negative: non-admin B cannot rename the group (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (UPDATE groups SET name='Hacked' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'non-admin cannot update group'
);

-- Positive: member B can leave (delete own membership)
SELECT results_eq(
  $$WITH del AS (
      DELETE FROM group_members
      WHERE group_id='20000000-0000-0000-0000-000000000001'
        AND user_id='00000000-0000-0000-0000-0000000000b1'
      RETURNING 1)
    SELECT count(*)::int FROM del$$,
  ARRAY[1], 'member can leave group'
);

-- Switch to outsider C
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c1';

-- Negative: outsider cannot see the group or its member list
SELECT results_eq(
  $$SELECT count(*)::int FROM groups$$,
  ARRAY[0], 'outsider cannot read groups'
);
SELECT results_eq(
  $$SELECT count(*)::int FROM group_members$$,
  ARRAY[0], 'outsider cannot read group members'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: `rls_groups_test.sql` FAILS with `relation "groups" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260710000002_create_groups.sql`:

```sql
CREATE TABLE public.groups (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name                 text NOT NULL,
  avatar_url           text,
  created_by           uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  default_late_penalty jsonb,
  default_routine_id   uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  created_at           timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.group_members (
  group_id  uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  role      text NOT NULL DEFAULT 'member' CHECK (role IN ('admin','member')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX group_members_user_id_idx ON public.group_members(user_id);

ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- SECURITY DEFINER helpers break groups<->group_members RLS recursion
-- (same pattern as sessions, see 20260709000006_create_sessions.sql)
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id);
$$;

CREATE OR REPLACE FUNCTION public.is_group_admin(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members
                 WHERE group_id = p_group_id AND user_id = p_user_id AND role = 'admin');
$$;

CREATE OR REPLACE FUNCTION public.is_group_creator(p_group_id uuid, p_user_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.groups
                 WHERE id = p_group_id AND created_by = p_user_id);
$$;

-- Spec §5: max group size v1 = 25
CREATE OR REPLACE FUNCTION public.enforce_group_size() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF (SELECT count(*) FROM public.group_members WHERE group_id = NEW.group_id) >= 25 THEN
    RAISE EXCEPTION 'group is full (max 25 members)' USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$$;
CREATE TRIGGER group_size_cap BEFORE INSERT ON public.group_members
  FOR EACH ROW EXECUTE FUNCTION public.enforce_group_size();

-- groups policies
CREATE POLICY "members and creator can read group"
  ON public.groups FOR SELECT TO authenticated
  USING (created_by = auth.uid() OR public.is_group_member(groups.id, auth.uid()));

CREATE POLICY "creator can insert group"
  ON public.groups FOR INSERT TO authenticated
  WITH CHECK (created_by = auth.uid());

CREATE POLICY "admin can update group"
  ON public.groups FOR UPDATE TO authenticated
  USING (public.is_group_admin(groups.id, auth.uid()))
  WITH CHECK (public.is_group_admin(groups.id, auth.uid()));

CREATE POLICY "admin can delete group"
  ON public.groups FOR DELETE TO authenticated
  USING (public.is_group_admin(groups.id, auth.uid()));

-- group_members policies
CREATE POLICY "members can read membership"
  ON public.group_members FOR SELECT TO authenticated
  USING (user_id = auth.uid()
         OR public.is_group_member(group_members.group_id, auth.uid()));

-- Admins add members; the creator may bootstrap ONLY their own admin row.
CREATE POLICY "admin adds members or creator bootstraps"
  ON public.group_members FOR INSERT TO authenticated
  WITH CHECK (
    public.is_group_admin(group_members.group_id, auth.uid())
    OR (user_id = auth.uid() AND role = 'admin'
        AND public.is_group_creator(group_members.group_id, auth.uid()))
  );

CREATE POLICY "admin updates roles"
  ON public.group_members FOR UPDATE TO authenticated
  USING (public.is_group_admin(group_members.group_id, auth.uid()))
  WITH CHECK (public.is_group_admin(group_members.group_id, auth.uid()));

CREATE POLICY "self-leave or admin removes"
  ON public.group_members FOR DELETE TO authenticated
  USING (user_id = auth.uid()
         OR public.is_group_admin(group_members.group_id, auth.uid()));
```

- [ ] **Step 4: Push migration, run tests**

```bash
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: all suites PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260710000002_create_groups.sql supabase/tests/rls_groups_test.sql
git commit -m "feat(db): groups + group_members with admin RLS and 25-member cap"
```

---

### Task 3: Chat tables + RLS + Realtime publication

**Files:**
- Create: `supabase/migrations/20260710000003_create_chat.sql`
- Test: `supabase/tests/rls_chat_test.sql`

**Interfaces:**
- Consumes: `groups`, `group_members`, `is_group_member` (Task 2); `sessions`, `profiles` (Phase 1).
- Produces: `public.chat_messages(id, group_id, session_id, author_id, kind, body, payload, storage_path, reply_to_id, created_at, edited_at, deleted_at)`, `public.chat_message_reactions(message_id, user_id, emoji)`, `public.chat_read_state(group_id, user_id, last_read_message_id)`; helper `message_group_id(uuid) RETURNS uuid`. `chat_messages` added to `supabase_realtime` publication (Task 9 subscribes). Clients may INSERT only `kind='text'` as themselves; system kinds are trigger-inserted (Task 4).

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/rls_chat_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(10);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a2', 'ca@t.com'),
  ('00000000-0000-0000-0000-0000000000b2', 'cb@t.com'),
  ('00000000-0000-0000-0000-0000000000c2', 'cc@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a2', 'ch_user_a'),
  ('00000000-0000-0000-0000-0000000000b2', 'ch_user_b'),
  ('00000000-0000-0000-0000-0000000000c2', 'ch_user_c');
INSERT INTO groups (id, name, created_by) VALUES
  ('30000000-0000-0000-0000-000000000001', 'Chat Crew',
   '00000000-0000-0000-0000-0000000000a2');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000a2', 'admin'),
  ('30000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-0000000000b2', 'member');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000a2';

-- Positive: member sends a text message
SELECT lives_ok(
  $$INSERT INTO chat_messages (id, group_id, author_id, kind, body) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2', 'text', 'first!')$$,
  'member can send text message'
);

-- Negative: cannot send as another author (42501)
SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2', 'text', 'spoofed')$$,
  '42501', NULL, 'cannot spoof author');

-- Negative: client cannot insert system kinds (42501)
SELECT throws_ok(
  $$INSERT INTO chat_messages (group_id, author_id, kind, body) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000a2', 'system_pr', 'fake PR')$$,
  '42501', NULL, 'client cannot insert system messages');

-- Positive: author can soft-delete own message
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_messages SET deleted_at = now()
      WHERE id='40000000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[1], 'author can soft-delete own message');

-- Member B: read + react + read-state
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000b2';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='30000000-0000-0000-0000-000000000001'$$,
  ARRAY[1], 'member can read group messages');

SELECT lives_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2', '🔥')$$,
  'member can react');

SELECT lives_ok(
  $$INSERT INTO chat_read_state (group_id, user_id, last_read_message_id) VALUES
    ('30000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000b2',
     '40000000-0000-0000-0000-000000000001')$$,
  'member can write own read state');

-- Negative: B cannot edit A's message (RLS-filtered UPDATE = 0 rows)
SELECT results_eq(
  $$WITH upd AS (
      UPDATE chat_messages SET body='vandalized'
      WHERE id='40000000-0000-0000-0000-000000000001' RETURNING 1)
    SELECT count(*)::int FROM upd$$,
  ARRAY[0], 'member cannot edit another authors message');

-- Outsider C
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-0000000000c2';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages$$,
  ARRAY[0], 'outsider cannot read chat');

SELECT throws_ok(
  $$INSERT INTO chat_message_reactions (message_id, user_id, emoji) VALUES
    ('40000000-0000-0000-0000-000000000001',
     '00000000-0000-0000-0000-0000000000c2', '👀')$$,
  '42501', NULL, 'outsider cannot react');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: `rls_chat_test.sql` FAILS with `relation "chat_messages" does not exist`.

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260710000003_create_chat.sql`:

```sql
CREATE TABLE public.chat_messages (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id     uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  session_id   uuid REFERENCES public.sessions(id) ON DELETE SET NULL,
  author_id    uuid REFERENCES public.profiles(id) ON DELETE SET NULL,  -- NULL = system
  kind         text NOT NULL DEFAULT 'text'
                    CHECK (kind IN ('text','image','system_pr','system_session',
                                    'system_late','system_leaderboard','soundboard_echo')),
  body         text,
  payload      jsonb,
  storage_path text,
  reply_to_id  uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  created_at   timestamptz NOT NULL DEFAULT now(),
  edited_at    timestamptz,
  deleted_at   timestamptz
);
CREATE INDEX chat_messages_group_created_idx
  ON public.chat_messages(group_id, created_at DESC);

CREATE TABLE public.chat_message_reactions (
  message_id uuid NOT NULL REFERENCES public.chat_messages(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  emoji      text NOT NULL,
  PRIMARY KEY (message_id, user_id, emoji)
);

CREATE TABLE public.chat_read_state (
  group_id             uuid NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id              uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  last_read_message_id uuid REFERENCES public.chat_messages(id) ON DELETE SET NULL,
  PRIMARY KEY (group_id, user_id)
);

ALTER TABLE public.chat_messages          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_message_reactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_read_state        ENABLE ROW LEVEL SECURITY;

-- Definer helper so reaction policies don't re-enter chat_messages RLS
CREATE OR REPLACE FUNCTION public.message_group_id(p_message_id uuid)
RETURNS uuid LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = public AS $$
  SELECT group_id FROM public.chat_messages WHERE id = p_message_id;
$$;

-- chat_messages
CREATE POLICY "group members read messages"
  ON public.chat_messages FOR SELECT TO authenticated
  USING (public.is_group_member(chat_messages.group_id, auth.uid()));

CREATE POLICY "members send text as themselves"
  ON public.chat_messages FOR INSERT TO authenticated
  WITH CHECK (author_id = auth.uid() AND kind = 'text'
              AND public.is_group_member(chat_messages.group_id, auth.uid()));

CREATE POLICY "author edits own messages"
  ON public.chat_messages FOR UPDATE TO authenticated
  USING (author_id = auth.uid())
  WITH CHECK (author_id = auth.uid());

-- chat_message_reactions
CREATE POLICY "group members read reactions"
  ON public.chat_message_reactions FOR SELECT TO authenticated
  USING (public.is_group_member(
           public.message_group_id(chat_message_reactions.message_id), auth.uid()));

CREATE POLICY "members react as themselves"
  ON public.chat_message_reactions FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(
                    public.message_group_id(chat_message_reactions.message_id), auth.uid()));

CREATE POLICY "user removes own reaction"
  ON public.chat_message_reactions FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- chat_read_state
CREATE POLICY "group members read read-state"
  ON public.chat_read_state FOR SELECT TO authenticated
  USING (public.is_group_member(chat_read_state.group_id, auth.uid()));

CREATE POLICY "user inserts own read-state"
  ON public.chat_read_state FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid()
              AND public.is_group_member(chat_read_state.group_id, auth.uid()));

CREATE POLICY "user updates own read-state"
  ON public.chat_read_state FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Realtime: stream chat message INSERTs (postgres_changes respects RLS)
ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
```

- [ ] **Step 4: Push migration, run tests**

```bash
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: all suites PASS.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260710000003_create_chat.sql supabase/tests/rls_chat_test.sql
git commit -m "feat(db): chat messages, reactions, read state with member-only RLS + realtime publication"
```

---

### Task 4: PR system messages (upgrade Phase 1 stub)

**Files:**
- Create: `supabase/migrations/20260710000004_pr_system_messages.sql`
- Test: `supabase/tests/pr_system_message_test.sql`

**Interfaces:**
- Consumes: `set_logs` (Phase 1, has `user_id, exercise_id, weight, is_failed, is_penalty`), `chat_messages` (Task 3), `group_members` (Task 2).
- Produces: trigger `pr_announce AFTER INSERT ON set_logs` → inserts `kind='system_pr'` rows (author NULL, payload `{user_id, exercise_id, weight, set_log_id}`) into every group the lifter belongs to. Phase 1's `is_pr()` client function stays untouched (still powers the local toast).

- [ ] **Step 1: Write the failing pgTAP test**

Create `supabase/tests/pr_system_message_test.sql`:

```sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-0000000000a3', 'pa@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-0000000000a3', 'pr_user_a');
INSERT INTO groups (id, name, created_by) VALUES
  ('50000000-0000-0000-0000-000000000001', 'PR Crew',
   '00000000-0000-0000-0000-0000000000a3');
INSERT INTO group_members (group_id, user_id, role) VALUES
  ('50000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3', 'admin');

-- Use a seeded exercise (Phase 1 seed guarantees bench-press exists)
-- and a session owned by the user (set_logs requires session context as in Phase 1)
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('60000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3', 'in_progress');
INSERT INTO session_participants (session_id, user_id) VALUES
  ('60000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-0000000000a3');

-- First lift: 100 lbs -> PR (no history)
INSERT INTO set_logs (id, session_id, user_id, exercise_id, set_index, reps, weight)
SELECT '70000000-0000-0000-0000-000000000001',
       '60000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-0000000000a3',
       e.id, 1, 5, 100
FROM exercises e WHERE e.slug = 'bench-press';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='50000000-0000-0000-0000-000000000001' AND kind='system_pr'$$,
  ARRAY[1], 'first lift announces a PR in group chat');

SELECT results_eq(
  $$SELECT (payload->>'weight')::numeric::int FROM chat_messages
    WHERE kind='system_pr'
      AND group_id='50000000-0000-0000-0000-000000000001'$$,
  ARRAY[100], 'payload carries the PR weight');

-- Second lift: 90 lbs -> NOT a PR, no new message
INSERT INTO set_logs (id, session_id, user_id, exercise_id, set_index, reps, weight)
SELECT '70000000-0000-0000-0000-000000000002',
       '60000000-0000-0000-0000-000000000001',
       '00000000-0000-0000-0000-0000000000a3',
       e.id, 2, 5, 90
FROM exercises e WHERE e.slug = 'bench-press';

SELECT results_eq(
  $$SELECT count(*)::int FROM chat_messages
    WHERE group_id='50000000-0000-0000-0000-000000000001' AND kind='system_pr'$$,
  ARRAY[1], 'lower weight does not announce');

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run to verify it fails**

Run: `node scripts/run_pgtap.js`
Expected: `pr_system_message_test.sql` FAILS on assertion 1 (0 system_pr rows — trigger doesn't exist yet).

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260710000004_pr_system_messages.sql`:

```sql
-- Phase 2 upgrade of the Phase 1 PR stub (see 20260709000009): on a new PR,
-- fan a system_pr chat message out to every group the lifter belongs to.
CREATE OR REPLACE FUNCTION public.announce_pr() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_username text;
  v_exercise text;
BEGIN
  IF NEW.is_failed OR NEW.is_penalty OR NEW.weight IS NULL THEN
    RETURN NEW;
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.set_logs
    WHERE user_id = NEW.user_id AND exercise_id = NEW.exercise_id
      AND is_failed = false AND is_penalty = false
      AND id <> NEW.id AND weight >= NEW.weight
  ) THEN
    RETURN NEW;  -- not a PR
  END IF;

  SELECT username INTO v_username FROM public.profiles  WHERE id = NEW.user_id;
  SELECT name     INTO v_exercise FROM public.exercises WHERE id = NEW.exercise_id;

  INSERT INTO public.chat_messages (group_id, author_id, kind, body, payload)
  SELECT gm.group_id, NULL, 'system_pr',
         '🔥 ' || v_username || ' hit a PR on ' || v_exercise || ': '
              || trim(to_char(NEW.weight, 'FM999999.99')) || ' lbs',
         jsonb_build_object('user_id', NEW.user_id, 'exercise_id', NEW.exercise_id,
                            'weight', NEW.weight, 'set_log_id', NEW.id)
  FROM public.group_members gm
  WHERE gm.user_id = NEW.user_id;

  RETURN NEW;
END;
$$;

CREATE TRIGGER pr_announce AFTER INSERT ON public.set_logs
  FOR EACH ROW EXECUTE FUNCTION public.announce_pr();
```

- [ ] **Step 4: Push migration, run tests**

```bash
npx supabase db push --db-url "$SUPABASE_DB_URL" --yes
node scripts/run_pgtap.js
```
Expected: all suites PASS. (If Phase 1 `volume_trigger_test.sql` or `pr_trigger_test.sql` breaks because the new trigger now also fires during those tests, add `AND group_id IS NOT NULL` guards to their assertions or scope their counts by group — the new trigger only writes when the user has groups, and those tests' users have none, so breakage is unlikely.)

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260710000004_pr_system_messages.sql supabase/tests/pr_system_message_test.sql
git commit -m "feat(db): PR trigger fans system_pr messages into the lifter's group chats"
```

---

### Task 5: Second CI test user + Profile lookup helpers

**Files:**
- Create: `scripts/create_second_test_user.js`
- Modify: `GymSyncApp/GymSync/Models/Profile.swift` (add `fetchByUsername`, `fetchMany`)
- Test: `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift` (add one test)

**Interfaces:**
- Consumes: `ProfileRepository` (Phase 1: `fetch(userID:)`, `create`, `usernameAvailable`, `refresh`).
- Produces: `ProfileRepository.fetchByUsername(_ username: String) async throws -> Profile?` and `ProfileRepository.fetchMany(ids: [UUID]) async throws -> [Profile]` — Tasks 6–8 and the UI use both. Seeded counterpart account: username `ci_test_user_2` (email `ci-tests-2@gymsync.app`) that Swift tests target but never sign in as.

- [ ] **Step 1: Write the seeding script**

Create `scripts/create_second_test_user.js` (mirror the env-loading style of the existing `scripts/create_test_user.js` if it differs):

```javascript
// Seeds the second CI test account used as the counterpart in friend/group tests.
// Swift tests never sign in as this user; they only target its username/id.
require('dotenv').config({ path: '.env.local' });
const { createClient } = require('@supabase/supabase-js');

const admin = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SECRET_KEY);

(async () => {
  const { data, error } = await admin.auth.admin.createUser({
    email: 'ci-tests-2@gymsync.app',
    password: process.env.SUPABASE_DB_PASSWORD, // never used to sign in
    email_confirm: true,
  });
  if (error) throw error;
  const { error: pErr } = await admin
    .from('profiles')
    .insert({ id: data.user.id, username: 'ci_test_user_2' });
  if (pErr) throw pErr;
  console.log('ci_test_user_2 id:', data.user.id);
})();
```

- [ ] **Step 2: Run it once against the live project**

Run: `node scripts/create_second_test_user.js`
Expected: prints `ci_test_user_2 id: <uuid>`. (If it errors "already been registered", the user exists — fine.)

- [ ] **Step 3: Add Profile helpers**

Append to the `ProfileRepository` enum in `GymSyncApp/GymSync/Models/Profile.swift`:

```swift
    static func fetchByUsername(_ username: String) async throws -> Profile? {
        do {
            let row: Profile = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .eq("username", value: username)
                .single()
                .execute()
                .value
            return row
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func fetchMany(ids: [UUID]) async throws -> [Profile] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [Profile] = try await SupabaseService.shared.client
                .from("profiles")
                .select()
                .in("id", values: ids.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }
```

- [ ] **Step 4: Add the test**

Append to `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift`:

```swift
    func testFetchByUsernameFindsSecondCIUser() async throws {
        try await TestAuth.signInIfConfigured()
        let profile = try await ProfileRepository.fetchByUsername("ci_test_user_2")
        XCTAssertNotNil(profile, "seeded counterpart account must exist (run scripts/create_second_test_user.js)")
        XCTAssertEqual(profile?.username, "ci_test_user_2")
    }
```

- [ ] **Step 5: Commit and push; verify CI**

```bash
git add scripts/create_second_test_user.js GymSyncApp/GymSync/Models/Profile.swift GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift
git commit -m "feat: profile lookup helpers + second CI test account seeding"
git push -u origin feature/phase-2-social
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS.

---

### Task 6: Friendship model + FriendRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/Friendship.swift`
- Test: `GymSyncApp/GymSyncTests/FriendRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProfileRepository.fetchByUsername`, `.fetchMany` (Task 5); `SupabaseService.shared` (Phase 1).
- Produces:
  - `struct Friendship: Codable, Sendable, Equatable` with `userID: UUID` (requester), `friendID: UUID` (recipient), `status: Status` (`.pending/.accepted/.blocked`), `createdAt: Date`
  - `enum FriendRepository` with:
    - `sendRequest(toUsername: String) async throws`
    - `incomingRequests() async throws -> [Profile]`
    - `outgoingRequests() async throws -> [Profile]`
    - `accept(requesterID: UUID) async throws`
    - `removeFriendship(with otherID: UUID) async throws` (decline / cancel / unfriend)
    - `friends() async throws -> [Profile]`

- [ ] **Step 1: Write model + repository**

Create `GymSyncApp/GymSync/Models/Friendship.swift`:

```swift
import Foundation
import Supabase

struct Friendship: Codable, Sendable, Equatable {
    let userID: UUID      // requester
    let friendID: UUID    // recipient
    let status: Status
    let createdAt: Date

    enum Status: String, Codable, Sendable {
        case pending, accepted, blocked
    }

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case friendID = "friend_id"
        case status
        case createdAt = "created_at"
    }
}

enum FriendRepository {
    static func sendRequest(toUsername username: String) async throws {
        guard let target = try await ProfileRepository.fetchByUsername(username) else {
            throw GymSyncError.notFound
        }
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .insert(["user_id": me.uuidString,
                         "friend_id": target.id.uuidString,
                         "status": "pending"])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func incomingRequests() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("friend_id", value: me.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            return try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func outgoingRequests() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("user_id", value: me.uuidString)
                .eq("status", value: "pending")
                .execute()
                .value
            return try await ProfileRepository.fetchMany(ids: rows.map(\.friendID))
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func accept(requesterID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .update(["status": "accepted"])
                .eq("user_id", value: requesterID.uuidString)
                .eq("friend_id", value: me.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func removeFriendship(with otherID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("friendships")
                .delete()
                .or("and(user_id.eq.\(me.uuidString),friend_id.eq.\(otherID.uuidString)),and(user_id.eq.\(otherID.uuidString),friend_id.eq.\(me.uuidString))")
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func friends() async throws -> [Profile] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [Friendship] = try await SupabaseService.shared.client
                .from("friendships")
                .select()
                .eq("status", value: "accepted")
                .or("user_id.eq.\(me.uuidString),friend_id.eq.\(me.uuidString)")
                .execute()
                .value
            let ids = rows.map { $0.userID == me ? $0.friendID : $0.userID }
            return try await ProfileRepository.fetchMany(ids: ids)
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
```

- [ ] **Step 2: Write the tests**

Create `GymSyncApp/GymSyncTests/FriendRepositoryTests.swift` (single-actor lifecycle: send → visible outgoing → cancel; accept semantics are pgTAP-covered in Task 1):

```swift
import XCTest
@testable import GymSync

final class FriendRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        // Clean slate: remove any leftover request to the counterpart account
        if let other = try await ProfileRepository.fetchByUsername("ci_test_user_2") {
            try? await FriendRepository.removeFriendship(with: other.id)
        }
    }

    func testSendRequestAppearsInOutgoingThenCancel() async throws {
        try await FriendRepository.sendRequest(toUsername: "ci_test_user_2")

        let outgoing = try await FriendRepository.outgoingRequests()
        XCTAssertTrue(outgoing.contains { $0.username == "ci_test_user_2" },
                      "sent request must appear in outgoing list")

        let other = try await ProfileRepository.fetchByUsername("ci_test_user_2")!
        try await FriendRepository.removeFriendship(with: other.id)

        let after = try await FriendRepository.outgoingRequests()
        XCTAssertFalse(after.contains { $0.username == "ci_test_user_2" },
                       "cancelled request must disappear")
    }

    func testSendRequestToUnknownUsernameThrowsNotFound() async throws {
        do {
            try await FriendRepository.sendRequest(toUsername: "no_such_user_zzz")
            XCTFail("expected notFound")
        } catch let error as GymSyncError {
            guard case .notFound = error else {
                return XCTFail("expected .notFound, got \(error)")
            }
        }
    }
}
```

- [ ] **Step 3: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Models/Friendship.swift GymSyncApp/GymSyncTests/FriendRepositoryTests.swift
git commit -m "feat: friendship model + friend request repository"
git push
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS.

---

### Task 7: GymGroup + GroupMember models + GroupRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/GymGroup.swift`
- Test: `GymSyncApp/GymSyncTests/GroupRepositoryTests.swift`

**Interfaces:**
- Consumes: `ProfileRepository.fetchByUsername`, `.fetchMany` (Task 5); tables from Task 2.
- Produces:
  - `struct GymGroup: Codable, Identifiable, Sendable, Hashable` — `id: UUID`, `name: String`, `avatarURL: URL?`, `createdBy: UUID`, `createdAt: Date`
  - `struct GroupMember: Codable, Sendable, Equatable` — `groupID: UUID`, `userID: UUID`, `role: Role` (`.admin/.member`), `joinedAt: Date`
  - `enum GroupRepository` with:
    - `create(name: String) async throws -> GymGroup` (inserts group + bootstraps self admin)
    - `myGroups() async throws -> [GymGroup]`
    - `members(groupID: UUID) async throws -> [(member: GroupMember, profile: Profile)]`
    - `addMember(groupID: UUID, username: String) async throws`
    - `leave(groupID: UUID) async throws`
    - `deleteGroup(groupID: UUID) async throws` (admin only; used by tests for cleanup)

- [ ] **Step 1: Write models + repository**

Create `GymSyncApp/GymSync/Models/GymGroup.swift`:

```swift
import Foundation
import Supabase

// Named GymGroup because `Group` collides with SwiftUI.Group.
struct GymGroup: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let avatarURL: URL?
    let createdBy: UUID
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, name
        case avatarURL = "avatar_url"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct GroupMember: Codable, Sendable, Equatable {
    let groupID: UUID
    let userID: UUID
    let role: Role
    let joinedAt: Date

    enum Role: String, Codable, Sendable { case admin, member }

    enum CodingKeys: String, CodingKey {
        case groupID = "group_id"
        case userID = "user_id"
        case role
        case joinedAt = "joined_at"
    }
}

enum GroupRepository {
    static func create(name: String) async throws -> GymGroup {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let groupID = UUID()
        do {
            let group: GymGroup = try await SupabaseService.shared.client
                .from("groups")
                .insert(["id": groupID.uuidString,
                         "name": name,
                         "created_by": me.uuidString])
                .select()
                .single()
                .execute()
                .value
            try await SupabaseService.shared.client
                .from("group_members")
                .insert(["group_id": groupID.uuidString,
                         "user_id": me.uuidString,
                         "role": "admin"])
                .execute()
            return group
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func myGroups() async throws -> [GymGroup] {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let memberships: [GroupMember] = try await SupabaseService.shared.client
                .from("group_members")
                .select()
                .eq("user_id", value: me.uuidString)
                .execute()
                .value
            guard !memberships.isEmpty else { return [] }
            let groups: [GymGroup] = try await SupabaseService.shared.client
                .from("groups")
                .select()
                .in("id", values: memberships.map(\.groupID.uuidString))
                .order("created_at", ascending: false)
                .execute()
                .value
            return groups
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func members(groupID: UUID) async throws -> [(member: GroupMember, profile: Profile)] {
        do {
            let rows: [GroupMember] = try await SupabaseService.shared.client
                .from("group_members")
                .select()
                .eq("group_id", value: groupID.uuidString)
                .execute()
                .value
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return rows.compactMap { row in
                byID[row.userID].map { (member: row, profile: $0) }
            }
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func addMember(groupID: UUID, username: String) async throws {
        guard let target = try await ProfileRepository.fetchByUsername(username) else {
            throw GymSyncError.notFound
        }
        do {
            try await SupabaseService.shared.client
                .from("group_members")
                .insert(["group_id": groupID.uuidString,
                         "user_id": target.id.uuidString,
                         "role": "member"])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func leave(groupID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("group_members")
                .delete()
                .eq("group_id", value: groupID.uuidString)
                .eq("user_id", value: me.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func deleteGroup(groupID: UUID) async throws {
        do {
            try await SupabaseService.shared.client
                .from("groups")
                .delete()
                .eq("id", value: groupID.uuidString)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
```

- [ ] **Step 2: Write the tests**

Create `GymSyncApp/GymSyncTests/GroupRepositoryTests.swift`:

```swift
import XCTest
@testable import GymSync

final class GroupRepositoryTests: XCTestCase {
    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    func testCreateGroupBootstrapsSelfAsAdminThenAddMemberAndCleanup() async throws {
        let group = try await GroupRepository.create(name: "CI Test Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        // Creator appears as admin
        let members = try await GroupRepository.members(groupID: group.id)
        XCTAssertEqual(members.count, 1)
        XCTAssertEqual(members.first?.member.role, .admin)

        // Group appears in myGroups
        let mine = try await GroupRepository.myGroups()
        XCTAssertTrue(mine.contains { $0.id == group.id })

        // Admin adds the counterpart account
        try await GroupRepository.addMember(groupID: group.id, username: "ci_test_user_2")
        let after = try await GroupRepository.members(groupID: group.id)
        XCTAssertEqual(after.count, 2)
        XCTAssertTrue(after.contains { $0.profile.username == "ci_test_user_2" })

        // Explicit cleanup (defer above is a safety net)
        try await GroupRepository.deleteGroup(groupID: group.id)
        let gone = try await GroupRepository.myGroups()
        XCTAssertFalse(gone.contains { $0.id == group.id })
    }

    func testAddUnknownMemberThrowsNotFound() async throws {
        let group = try await GroupRepository.create(name: "CI Ghost Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }
        do {
            try await GroupRepository.addMember(groupID: group.id, username: "no_such_user_zzz")
            XCTFail("expected notFound")
        } catch let error as GymSyncError {
            guard case .notFound = error else {
                return XCTFail("expected .notFound, got \(error)")
            }
        }
        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
```

- [ ] **Step 3: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Models/GymGroup.swift GymSyncApp/GymSyncTests/GroupRepositoryTests.swift
git commit -m "feat: group models + repository with admin bootstrap"
git push
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS.

---

### Task 8: ChatMessage model + ChatRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/ChatMessage.swift`
- Test: `GymSyncApp/GymSyncTests/ChatRepositoryTests.swift`

**Interfaces:**
- Consumes: `GroupRepository` (Task 7), tables from Task 3.
- Produces:
  - `struct ChatMessage: Codable, Identifiable, Sendable, Equatable` — `id, groupID, sessionID?, authorID?, kind: Kind, body?, replyToID?, createdAt, editedAt?, deletedAt?` (`payload`/`storage_path` intentionally not decoded in Phase 2 — system message rendering uses `body`)
  - `struct ChatReaction: Codable, Sendable, Equatable` — `messageID, userID, emoji`
  - `enum ChatRepository` with:
    - `messages(groupID: UUID, before: Date?, limit: Int) async throws -> [ChatMessage]` (newest-first)
    - `send(groupID: UUID, body: String) async throws -> ChatMessage`
    - `react(messageID: UUID, emoji: String) async throws`
    - `unreact(messageID: UUID, emoji: String) async throws`
    - `reactions(messageIDs: [UUID]) async throws -> [ChatReaction]`
    - `markRead(groupID: UUID, messageID: UUID) async throws`
    - `hasUnread(groupID: UUID) async throws -> Bool`

- [ ] **Step 1: Write model + repository**

Create `GymSyncApp/GymSync/Models/ChatMessage.swift`:

```swift
import Foundation
import Supabase

struct ChatMessage: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let groupID: UUID
    let sessionID: UUID?
    let authorID: UUID?      // nil = system message
    let kind: Kind
    let body: String?
    let replyToID: UUID?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?

    enum Kind: String, Codable, Sendable {
        case text, image
        case systemPR = "system_pr"
        case systemSession = "system_session"
        case systemLate = "system_late"
        case systemLeaderboard = "system_leaderboard"
        case soundboardEcho = "soundboard_echo"
    }

    var isSystem: Bool { authorID == nil }

    enum CodingKeys: String, CodingKey {
        case id
        case groupID = "group_id"
        case sessionID = "session_id"
        case authorID = "author_id"
        case kind, body
        case replyToID = "reply_to_id"
        case createdAt = "created_at"
        case editedAt = "edited_at"
        case deletedAt = "deleted_at"
    }
}

struct ChatReaction: Codable, Sendable, Equatable {
    let messageID: UUID
    let userID: UUID
    let emoji: String

    enum CodingKeys: String, CodingKey {
        case messageID = "message_id"
        case userID = "user_id"
        case emoji
    }
}

enum ChatRepository {
    static func messages(groupID: UUID, before: Date? = nil,
                         limit: Int = 50) async throws -> [ChatMessage] {
        do {
            var query = SupabaseService.shared.client
                .from("chat_messages")
                .select()
                .eq("group_id", value: groupID.uuidString)
            if let before {
                query = query.lt("created_at", value: before.ISO8601Format())
            }
            let rows: [ChatMessage] = try await query
                .order("created_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func send(groupID: UUID, body: String) async throws -> ChatMessage {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: ChatMessage = try await SupabaseService.shared.client
                .from("chat_messages")
                .insert(["id": UUID().uuidString,
                         "group_id": groupID.uuidString,
                         "author_id": me.uuidString,
                         "kind": "text",
                         "body": body])
                .select()
                .single()
                .execute()
                .value
            return row
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func react(messageID: UUID, emoji: String) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .insert(["message_id": messageID.uuidString,
                         "user_id": me.uuidString,
                         "emoji": emoji])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func unreact(messageID: UUID, emoji: String) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .delete()
                .eq("message_id", value: messageID.uuidString)
                .eq("user_id", value: me.uuidString)
                .eq("emoji", value: emoji)
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func reactions(messageIDs: [UUID]) async throws -> [ChatReaction] {
        guard !messageIDs.isEmpty else { return [] }
        do {
            let rows: [ChatReaction] = try await SupabaseService.shared.client
                .from("chat_message_reactions")
                .select()
                .in("message_id", values: messageIDs.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func markRead(groupID: UUID, messageID: UUID) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await SupabaseService.shared.client
                .from("chat_read_state")
                .upsert(["group_id": groupID.uuidString,
                         "user_id": me.uuidString,
                         "last_read_message_id": messageID.uuidString])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func hasUnread(groupID: UUID) async throws -> Bool {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let latest = try await messages(groupID: groupID, limit: 1)
            guard let latestID = latest.first?.id else { return false }

            struct ReadState: Codable {
                let lastReadMessageID: UUID?
                enum CodingKeys: String, CodingKey {
                    case lastReadMessageID = "last_read_message_id"
                }
            }
            let states: [ReadState] = try await SupabaseService.shared.client
                .from("chat_read_state")
                .select("last_read_message_id")
                .eq("group_id", value: groupID.uuidString)
                .eq("user_id", value: me.uuidString)
                .execute()
                .value
            return states.first?.lastReadMessageID != latestID
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
```

- [ ] **Step 2: Write the tests**

Create `GymSyncApp/GymSyncTests/ChatRepositoryTests.swift`:

```swift
import XCTest
@testable import GymSync

final class ChatRepositoryTests: XCTestCase {
    private var group: GymGroup!

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        group = try await GroupRepository.create(name: "CI Chat Group")
    }

    override func tearDown() async throws {
        if let group {
            try? await GroupRepository.deleteGroup(groupID: group.id)
        }
    }

    func testSendFetchReactReadLifecycle() async throws {
        // New group: no messages, no unread
        let empty = try await ChatRepository.messages(groupID: group.id)
        XCTAssertTrue(empty.isEmpty)
        let unreadEmpty = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertFalse(unreadEmpty, "empty chat has nothing unread")

        // Send
        let sent = try await ChatRepository.send(groupID: group.id, body: "hello ci")
        XCTAssertEqual(sent.kind, .text)
        XCTAssertEqual(sent.body, "hello ci")

        // Fetch newest-first
        let fetched = try await ChatRepository.messages(groupID: group.id)
        XCTAssertEqual(fetched.first?.id, sent.id)

        // Unread until marked read
        let unread = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertTrue(unread)
        try await ChatRepository.markRead(groupID: group.id, messageID: sent.id)
        let afterRead = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertFalse(afterRead)

        // React / unreact
        try await ChatRepository.react(messageID: sent.id, emoji: "🔥")
        var reactions = try await ChatRepository.reactions(messageIDs: [sent.id])
        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions.first?.emoji, "🔥")
        try await ChatRepository.unreact(messageID: sent.id, emoji: "🔥")
        reactions = try await ChatRepository.reactions(messageIDs: [sent.id])
        XCTAssertTrue(reactions.isEmpty)
    }
}
```

- [ ] **Step 3: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Models/ChatMessage.swift GymSyncApp/GymSyncTests/ChatRepositoryTests.swift
git commit -m "feat: chat message model + repository (send, react, read state)"
git push
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS.

---

### Task 9: ChatRealtimeService

**Files:**
- Create: `GymSyncApp/GymSync/Services/ChatRealtimeService.swift`
- Test: `GymSyncApp/GymSyncTests/ChatRealtimeTests.swift`

**Interfaces:**
- Consumes: `ChatMessage` (Task 8); `chat_messages` in `supabase_realtime` publication (Task 3).
- Produces: `@MainActor final class ChatRealtimeService` with `func subscribe(groupID: UUID, onInsert: @escaping @MainActor (ChatMessage) -> Void) async` and `func unsubscribe() async`. ChatView (Task 11) owns one instance per open chat.

**API note:** supabase-swift v2 realtime — `client.channel(_:)` → `channel.postgresChange(InsertAction.self, schema:table:filter:)` → `await channel.subscribe()` → `for await` the stream. `decodeRecord` needs an explicit date-capable decoder; the built-in Postgrest decoder is not exposed here. If CI reports API drift (method signatures change between SDK minor versions), adapt to the installed SDK — the *behavior contract* (decoded `ChatMessage` per INSERT on the group's chat) is what matters.

- [ ] **Step 1: Write the service**

Create `GymSyncApp/GymSync/Services/ChatRealtimeService.swift`:

```swift
import Foundation
import Supabase

@MainActor
final class ChatRealtimeService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    // Postgrest timestamps: "2026-07-10T19:00:00.123456+00:00" (fractional) or without.
    nonisolated static let postgresDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let value = try dec.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "unparseable timestamp: \(value)"))
        }
        return decoder
    }()

    func subscribe(groupID: UUID,
                   onInsert: @escaping @MainActor (ChatMessage) -> Void) async {
        await unsubscribe()
        let channel = SupabaseService.shared.client
            .channel("chat:\(groupID.uuidString)")
        let inserts = channel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "chat_messages",
            filter: "group_id=eq.\(groupID.uuidString)"
        )
        self.channel = channel
        await channel.subscribe()
        streamTask = Task {
            for await action in inserts {
                do {
                    let message = try action.decodeRecord(
                        decoder: Self.postgresDecoder) as ChatMessage
                    onInsert(message)
                } catch {
                    AppLogger.chat.error("realtime decode failed: \(error, privacy: .public)")
                }
            }
        }
    }

    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}
```

Also add a `chat` logger category. In `GymSyncApp/GymSync/Services/AppLogger.swift`, add alongside the existing categories:

```swift
    static let chat = Logger(subsystem: subsystem, category: "chat")
```
(Match the existing property style in that file — if categories are declared differently, follow the file's pattern.)

- [ ] **Step 2: Write the round-trip test**

Create `GymSyncApp/GymSyncTests/ChatRealtimeTests.swift`:

```swift
import XCTest
@testable import GymSync

final class ChatRealtimeTests: XCTestCase {
    func testInsertIsDeliveredToSubscriber() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Realtime Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let expectation = XCTestExpectation(description: "realtime insert delivered")
        let service = await ChatRealtimeService()

        await service.subscribe(groupID: group.id) { message in
            if message.body == "realtime ping" { expectation.fulfill() }
        }
        // Give the socket a beat to be fully joined before writing
        try await Task.sleep(for: .seconds(2))

        _ = try await ChatRepository.send(groupID: group.id, body: "realtime ping")

        await fulfillment(of: [expectation], timeout: 15)
        await service.unsubscribe()
        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
```

- [ ] **Step 3: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Services/ChatRealtimeService.swift GymSyncApp/GymSync/Services/AppLogger.swift GymSyncApp/GymSyncTests/ChatRealtimeTests.swift
git commit -m "feat: realtime chat subscription service (postgres_changes on chat_messages)"
git push
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS. If the realtime test is flaky on CI (socket join latency), raise the pre-send sleep to 4s before considering API-level debugging.

---

### Task 10: Social tab — friends list, group list, create group

**Files:**
- Create: `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`
- Create: `GymSyncApp/GymSync/Features/Social/FriendsView.swift`
- Create: `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift`

**Interfaces:**
- Consumes: `FriendRepository` (Task 6), `GroupRepository` (Task 7), `ChatRepository.hasUnread` (Task 8).
- Produces: `SocialTabView` (root view for the tab — Task 11 wires it into MainTabView), navigates to `FriendsView`, `CreateGroupView` (sheet), and `GroupView(group:)` (Task 11 — stub it here as `Text(group.name)` placeholder ONLY if building Task 10 before 11; if executing in order, Task 11 lands first in the same push, so reference it directly).

**Note:** Tasks 10 and 11 are UI — no XCTest (repositories are already covered). Verification = CI build green + manual TestFlight QA (Task 12). Push both tasks together if preferred, but commit separately.

- [ ] **Step 1: Write SocialTabView**

Create `GymSyncApp/GymSync/Features/Social/SocialTabView.swift`:

```swift
import SwiftUI

struct SocialTabView: View {
    @State private var groups: [GymGroup] = []
    @State private var unread: Set<UUID> = []
    @State private var friendCount = 0
    @State private var pendingCount = 0
    @State private var showCreateGroup = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        FriendsView()
                    } label: {
                        HStack {
                            Label("Friends", systemImage: "person.2.fill")
                            Spacer()
                            if pendingCount > 0 {
                                Text("\(pendingCount)")
                                    .font(.caption.bold())
                                    .padding(6)
                                    .background(.red, in: Circle())
                                    .foregroundStyle(.white)
                            }
                            Text("\(friendCount)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Groups") {
                    if groups.isEmpty {
                        Text("No groups yet. Create one to start chatting.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        NavigationLink {
                            GroupView(group: group)
                        } label: {
                            HStack {
                                InitialsAvatar(name: group.name)
                                Text(group.name)
                                Spacer()
                                if unread.contains(group.id) {
                                    Circle().fill(.blue).frame(width: 10, height: 10)
                                }
                            }
                        }
                    }
                }

                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("Social")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showCreateGroup = true
                    } label: {
                        Label("New Group", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCreateGroup) {
                CreateGroupView { newGroup in
                    groups.insert(newGroup, at: 0)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        do {
            groups = try await GroupRepository.myGroups()
            friendCount = try await FriendRepository.friends().count
            pendingCount = try await FriendRepository.incomingRequests().count
            var unreadIDs: Set<UUID> = []
            for group in groups where (try? await ChatRepository.hasUnread(groupID: group.id)) == true {
                unreadIDs.insert(group.id)
            }
            unread = unreadIDs
            errorText = nil
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription
                ?? error.localizedDescription
        }
    }
}

struct InitialsAvatar: View {
    let name: String

    var body: some View {
        Text(initials)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(Color.accentColor.gradient, in: Circle())
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
```

- [ ] **Step 2: Write FriendsView**

Create `GymSyncApp/GymSync/Features/Social/FriendsView.swift`:

```swift
import SwiftUI

struct FriendsView: View {
    @State private var friends: [Profile] = []
    @State private var incoming: [Profile] = []
    @State private var outgoing: [Profile] = []
    @State private var addUsername = ""
    @State private var errorText: String?

    var body: some View {
        List {
            Section("Add Friend") {
                HStack {
                    TextField("username", text: $addUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Send") {
                        Task { await sendRequest() }
                    }
                    .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }

            if !incoming.isEmpty {
                Section("Requests") {
                    ForEach(incoming) { profile in
                        HStack {
                            Text(profile.username)
                            Spacer()
                            Button("Accept") {
                                Task {
                                    try? await FriendRepository.accept(requesterID: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            Button("Decline") {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if !outgoing.isEmpty {
                Section("Sent") {
                    ForEach(outgoing) { profile in
                        HStack {
                            Text(profile.username)
                            Spacer()
                            Button("Cancel") {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            Section("Friends") {
                if friends.isEmpty {
                    Text("No friends yet. Send a request by username.")
                        .foregroundStyle(.secondary)
                }
                ForEach(friends) { profile in
                    Text(profile.username)
                        .swipeActions {
                            Button("Remove", role: .destructive) {
                                Task {
                                    try? await FriendRepository.removeFriendship(with: profile.id)
                                    await refresh()
                                }
                            }
                        }
                }
            }
        }
        .navigationTitle("Friends")
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    private func sendRequest() async {
        let username = addUsername.trimmingCharacters(in: .whitespaces)
        do {
            try await FriendRepository.sendRequest(toUsername: username)
            addUsername = ""
            errorText = nil
            await refresh()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refresh() async {
        friends = (try? await FriendRepository.friends()) ?? []
        incoming = (try? await FriendRepository.incomingRequests()) ?? []
        outgoing = (try? await FriendRepository.outgoingRequests()) ?? []
    }
}
```

- [ ] **Step 3: Write CreateGroupView**

Create `GymSyncApp/GymSync/Features/Social/CreateGroupView.swift`:

```swift
import SwiftUI

struct CreateGroupView: View {
    let onCreated: (GymGroup) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var friends: [Profile] = []
    @State private var selected: Set<UUID> = []
    @State private var isCreating = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Group Name") {
                    TextField("e.g. Push Crew", text: $name)
                }
                Section("Add Friends") {
                    if friends.isEmpty {
                        Text("No friends to add yet — you can add members later.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(friends) { profile in
                        Button {
                            if selected.contains(profile.id) {
                                selected.remove(profile.id)
                            } else {
                                selected.insert(profile.id)
                            }
                        } label: {
                            HStack {
                                Text(profile.username).foregroundStyle(.primary)
                                Spacer()
                                if selected.contains(profile.id) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            .navigationTitle("New Group")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { Task { await create() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || isCreating)
                }
            }
            .task {
                friends = (try? await FriendRepository.friends()) ?? []
            }
        }
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }
        do {
            let group = try await GroupRepository.create(
                name: name.trimmingCharacters(in: .whitespaces))
            let selectedProfiles = friends.filter { selected.contains($0.id) }
            for profile in selectedProfiles {
                try await GroupRepository.addMember(groupID: group.id,
                                                    username: profile.username)
            }
            onCreated(group)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
```

- [ ] **Step 4: Commit**

```bash
git add GymSyncApp/GymSync/Features/Social/
git commit -m "feat: social tab UI — friends management + group list + create group"
```
(Do not push yet — Task 11 completes the compile unit; `GroupView` is referenced but not yet created.)

---

### Task 11: GroupView + ChatView + tab wiring

**Files:**
- Create: `GymSyncApp/GymSync/Features/Social/GroupView.swift`
- Create: `GymSyncApp/GymSync/Features/Social/ChatView.swift`
- Modify: `GymSyncApp/GymSync/App/RootView.swift` (replace `Text("Social — Phase 2")` placeholder)

**Interfaces:**
- Consumes: `ChatRepository`, `ChatRealtimeService`, `GroupRepository.members/leave`, `InitialsAvatar` (Task 10), `AppState` (Phase 1 — has `currentProfile: Profile?`).
- Produces: `GroupView(group: GymGroup)` — sub-tabs Chat + Members. ChatView marks messages read, streams inserts, renders system messages distinctly, supports 4-emoji reaction bar on long-press.

- [ ] **Step 1: Write GroupView**

Create `GymSyncApp/GymSync/Features/Social/GroupView.swift`:

```swift
import SwiftUI

struct GroupView: View {
    let group: GymGroup

    private enum SubTab: String, CaseIterable {
        case chat = "Chat"
        case members = "Members"
    }

    @Environment(\.dismiss) private var dismiss
    @State private var subTab: SubTab = .chat
    @State private var members: [(member: GroupMember, profile: Profile)] = []
    @State private var addUsername = ""
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("View", selection: $subTab) {
                ForEach(SubTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)

            switch subTab {
            case .chat:
                ChatView(group: group)
            case .members:
                membersList
            }
        }
        .navigationTitle(group.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { members = (try? await GroupRepository.members(groupID: group.id)) ?? [] }
    }

    private var membersList: some View {
        List {
            Section {
                HStack {
                    TextField("add by username", text: $addUsername)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Add") { Task { await addMember() } }
                        .disabled(addUsername.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let errorText {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("\(members.count) members") {
                ForEach(members, id: \.member.userID) { entry in
                    HStack {
                        Text(entry.profile.username)
                        Spacer()
                        if entry.member.role == .admin {
                            Text("admin")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section {
                Button("Leave Group", role: .destructive) {
                    Task {
                        try? await GroupRepository.leave(groupID: group.id)
                        dismiss()
                    }
                }
            }
        }
    }

    private func addMember() async {
        do {
            try await GroupRepository.addMember(
                groupID: group.id,
                username: addUsername.trimmingCharacters(in: .whitespaces))
            addUsername = ""
            errorText = nil
            members = (try? await GroupRepository.members(groupID: group.id)) ?? []
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
```

- [ ] **Step 2: Write ChatView**

Create `GymSyncApp/GymSync/Features/Social/ChatView.swift`:

```swift
import SwiftUI

struct ChatView: View {
    let group: GymGroup

    @Environment(AppState.self) private var appState
    @State private var messages: [ChatMessage] = []   // oldest-first for rendering
    @State private var reactions: [UUID: [ChatReaction]] = [:]
    @State private var usernames: [UUID: String] = [:]
    @State private var draft = ""
    @State private var realtime = ChatRealtimeService()
    @State private var errorText: String?

    private static let reactionChoices = ["👍", "🔥", "💪", "😂"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(messages) { message in
                            messageRow(message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: messages.count) {
                    if let last = messages.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                        Task { try? await ChatRepository.markRead(groupID: group.id,
                                                                  messageID: last.id) }
                    }
                }
            }

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }

            HStack {
                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Button {
                    Task { await send() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill").font(.title2)
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding()
        }
        .task { await load() }
        .onDisappear { Task { await realtime.unsubscribe() } }
    }

    @ViewBuilder
    private func messageRow(_ message: ChatMessage) -> some View {
        if message.isSystem {
            Text(message.body ?? "")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
        } else {
            let mine = message.authorID == appState.currentProfile?.id
            VStack(alignment: mine ? .trailing : .leading, spacing: 3) {
                if !mine, let author = message.authorID {
                    Text(usernames[author] ?? "…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(message.deletedAt != nil ? "[deleted message]" : (message.body ?? ""))
                    .italic(message.deletedAt != nil)
                    .padding(10)
                    .background(mine ? Color.accentColor.opacity(0.25)
                                     : Color(.secondarySystemBackground),
                                in: RoundedRectangle(cornerRadius: 14))
                    .contextMenu {
                        ForEach(Self.reactionChoices, id: \.self) { emoji in
                            Button(emoji) {
                                Task {
                                    try? await ChatRepository.react(
                                        messageID: message.id, emoji: emoji)
                                    await refreshReactions()
                                }
                            }
                        }
                    }
                if let messageReactions = reactions[message.id], !messageReactions.isEmpty {
                    let counts = Dictionary(grouping: messageReactions, by: \.emoji)
                        .mapValues(\.count)
                        .sorted { $0.key < $1.key }
                    HStack(spacing: 4) {
                        ForEach(counts, id: \.key) { emoji, count in
                            Text("\(emoji) \(count)")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color(.tertiarySystemBackground),
                                            in: Capsule())
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: mine ? .trailing : .leading)
        }
    }

    private func load() async {
        do {
            let page = try await ChatRepository.messages(groupID: group.id)
            messages = page.reversed()
            await refreshReactions()
            await resolveUsernames()
            await realtime.subscribe(groupID: group.id) { message in
                guard !messages.contains(where: { $0.id == message.id }) else { return }
                messages.append(message)
                Task { await resolveUsernames() }
            }
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func send() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        draft = ""
        do {
            let sent = try await ChatRepository.send(groupID: group.id, body: body)
            if !messages.contains(where: { $0.id == sent.id }) {
                messages.append(sent)
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func refreshReactions() async {
        let all = (try? await ChatRepository.reactions(
            messageIDs: messages.map(\.id))) ?? []
        reactions = Dictionary(grouping: all, by: \.messageID)
    }

    private func resolveUsernames() async {
        let unknown = Set(messages.compactMap(\.authorID)).subtracting(usernames.keys)
        guard !unknown.isEmpty else { return }
        let profiles = (try? await ProfileRepository.fetchMany(ids: Array(unknown))) ?? []
        for profile in profiles {
            usernames[profile.id] = profile.username
        }
    }
}
```

- [ ] **Step 3: Wire the tab**

In `GymSyncApp/GymSync/App/RootView.swift`, replace:

```swift
            Text("Social — Phase 2")  // placeholder in Phase 1
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .tag(AppState.Tab.social)
```

with:

```swift
            SocialTabView()
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .tag(AppState.Tab.social)
```

- [ ] **Step 4: Commit, push, verify CI**

```bash
git add GymSyncApp/GymSync/Features/Social/ GymSyncApp/GymSync/App/RootView.swift
git commit -m "feat: group chat UI with realtime stream, reactions, read state + Social tab wiring"
git push
gh run watch $(gh run list --workflow ios.yml --branch feature/phase-2-social --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status
```
Expected: `build-test` PASS (this compiles Tasks 10 + 11 together).

---

### Task 12: Ship — PR, merge, TestFlight QA

- [ ] **Step 1: Full local backend verification**

Run: `node scripts/run_pgtap.js`
Expected: all suites PASS (Phase 1's 18 + ~30 new assertions).

- [ ] **Step 2: Open the PR**

```bash
gh pr create --title "Phase 2: Friends, Groups, Chat" --body "## Summary
- friendships table + directional request/accept RLS
- groups + group_members (SECURITY DEFINER helpers, 25-member cap)
- chat_messages / reactions / read_state + realtime publication
- PR trigger now fans system_pr messages into the lifter's groups
- iOS: FriendRepository, GroupRepository, ChatRepository, ChatRealtimeService
- iOS: Social tab (friends, groups, create group, group chat with realtime + reactions)

## Test plan
- [ ] pgTAP green (run_pgtap.js)
- [ ] iOS CI green (build-test)
- [ ] Manual TestFlight QA (below)
"
```

- [ ] **Step 3: Merge after CI green** (merging to master auto-deploys to TestFlight via `deploy-testflight`)

- [ ] **Step 4: Manual device QA checklist (two physical accounts: your iPhone + a second Apple ID or the CI account via a debug build)**

1. Social tab renders; Friends shows empty state
2. Send friend request by username → appears in Sent
3. (Second account) accept → both sides see each other under Friends
4. Create group with a friend pre-selected → group appears for both
5. Send chat messages both directions → arrive live without pull-to-refresh (realtime)
6. Long-press a message → react 🔥 → count renders on both devices
7. Leave and re-enter chat → read state: unread dot appears for new messages, clears on open
8. Log a solo workout with a PR → 🔥 system message appears in the group chat
9. Member list shows roles; Leave Group works
10. Regression: solo workout logging, stats, Health export all still work

- [ ] **Step 5: Update memory/project docs** — mark Phase 2 shipped; note any new CI gotchas discovered en route.

---

## Self-Review Notes (already applied)

- **Recursion:** all cross-table policy references go through SECURITY DEFINER helpers (`is_group_member`, `is_group_admin`, `is_group_creator`, `message_group_id`).
- **Silent RLS UPDATE/DELETE:** all negative UPDATE/DELETE tests use row-count CTEs; INSERT negatives use `throws_ok('42501')`.
- **Naming consistency check:** `GymGroup`/`GroupMember`/`ChatMessage`/`ChatReaction` and repository method names are identical between the Interfaces blocks, implementations, tests, and views.
- **Spec deviations (deliberate, documented):** no images/typing/live reactions/avatars/blocks (see "Explicitly deferred"); GroupView has Chat+Members sub-tabs (Sessions/Stats need Phase 3 data); `sessions` table gains no `group_id` column until Phase 3.
- **Known risk:** supabase-swift Realtime API surface varies across v2 minors — Task 9's note authorizes adapting signatures; the behavior contract is fixed. Set-log columns in Task 4's test were verified against `20260709000007` (`set_index`, `reps`, `weight`, `is_failed`, `is_penalty`).
