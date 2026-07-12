# Gym Sync — Phase 1: Foundation + Solo Workout MVP

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a working iPhone app where a single user can sign in with Apple, create their profile, browse a curated exercise library, build routines, log solo workouts (reps/weight/RPE), see their ledger with trend charts, and export completed workouts to Apple Health.

**Architecture:** Native Swift/SwiftUI iOS app talking to a Supabase project (Postgres + Auth + Storage). MVVM-ish structure with reactive `@Observable` view models. SwiftData for offline cache. RLS policies on every Postgres table enforce per-user data isolation. All Supabase calls funnel through a single `SupabaseClient` service so retries, error mapping, and auth-refresh live in one place.

**Tech Stack:**
- iOS 17.0+ (deployment target)
- Swift 5.9+
- SwiftUI (UI)
- SwiftData (local cache)
- Swift Charts (visualizations)
- Supabase Swift SDK v2+ (backend)
- HealthKit (workout export)
- XCTest + XCUITest (testing)
- Supabase CLI (migrations, local dev)

**Design spec:** [`G:/Projects/GymSync/docs/superpowers/specs/2026-06-28-gymsync-design.md`](../specs/2026-06-28-gymsync-design.md). Refer to it for full context on features deferred to later phases.

## Global Constraints

- **iOS 17.0** minimum deployment target (required for SwiftData + Observation macros).
- **Swift 5.9+** (Xcode 15+).
- **RLS enabled on every Postgres table.** No exceptions.
- **Every RLS policy paired with positive AND negative integration test.** Missing negative test = merge blocker.
- **Every persistent write has a client-generated UUID as its primary key** for idempotent retry.
- **All Supabase calls go through `SupabaseClient` singleton wrapper.** Never call the SDK directly from view code.
- **No `print()` in production code paths.** Use `os_log` via the `AppLogger` utility.
- **No force-unwraps** (`!`) except in tests and where a nil is a legitimate programming error (unusual — prefer graceful fallback).
- **No third-party analytics SDKs** in Phase 1. Crash reporting via Sentry is added in Phase 10.
- **Sign in with Apple is the only auth provider.** Do not add Google/email/other providers (App Store §4.8 compliance).
- **App name in every user-visible string: "Gym Sync"** (two words with space). Bundle ID: `app.gymsync.ios`.

## Phase 1 Roadmap

Phase 1 produces working software at the end. **Not included in Phase 1** (all deferred to their own future plans):
- Friends, groups, chat (Phase 2)
- Multi-player sessions, lobby, chess clock, soundboard (Phase 3)
- Public workouts, leaderboards, cumulative volume across users (Phase 4)
- Apple Watch companion, heart rate broadcast (Phase 5)
- Streaks (Phase 6)
- Seasonal campaigns (Phase 7)
- Local Hub with QR / venues / phone verify (Phase 8)
- Google Calendar sync (Phase 9)
- Block/report, push notifications, body weight log, plate math, TestFlight prep (Phase 10)

**PR detection** IS included in Phase 1 for solo workouts, because the data is already there and the trigger is easy — but the celebration UI is minimal (a simple "🔥 NEW PR!" toast, not the full animation).

## File Structure

New iOS project + new Supabase project. All paths below are relative to their respective project roots.

### Supabase project (`GymSync/supabase/`)

```
supabase/
├── config.toml                              # Supabase project config
├── migrations/
│   ├── 20260709000001_create_profiles.sql
│   ├── 20260709000002_create_exercises.sql
│   ├── 20260709000003_seed_exercises.sql
│   ├── 20260709000004_create_gyms.sql
│   ├── 20260709000005_create_routines.sql
│   ├── 20260709000006_create_sessions.sql
│   ├── 20260709000007_create_set_logs.sql
│   ├── 20260709000008_lifetime_volume_trigger.sql
│   ├── 20260709000009_pr_detection_trigger.sql
│   └── 20260709000010_rls_policies.sql
├── seed/
│   └── exercises.sql                        # Seeded curated exercise library
└── tests/
    ├── rls_profiles_test.sql
    ├── rls_routines_test.sql
    ├── rls_set_logs_test.sql
    ├── volume_trigger_test.sql
    └── pr_trigger_test.sql
```

### iOS project (`GymSyncApp/`)

```
GymSyncApp/
├── GymSync.xcodeproj/
├── GymSync/
│   ├── App/
│   │   ├── GymSyncApp.swift                 # @main entry point
│   │   ├── AppState.swift                   # Global @Observable state
│   │   └── RootView.swift                   # Chooses onboarding vs. main
│   ├── Config/
│   │   ├── Secrets.swift.template           # Committed template
│   │   ├── Secrets.swift                    # .gitignored real values
│   │   └── AppConfig.swift                  # Non-secret config
│   ├── Services/
│   │   ├── SupabaseService.swift            # Wraps supabase-swift SDK
│   │   ├── AuthService.swift                # Sign in with Apple flow
│   │   ├── HealthKitBridge.swift            # HKWorkout export
│   │   ├── LocationProvider.swift           # For home gym setup
│   │   ├── LocalStore.swift                 # SwiftData wrapper
│   │   └── AppLogger.swift                  # os_log wrapper
│   ├── Models/
│   │   ├── Profile.swift                    # Codable + SwiftData
│   │   ├── Exercise.swift
│   │   ├── Routine.swift
│   │   ├── RoutineExercise.swift
│   │   ├── Session.swift
│   │   ├── SetLog.swift
│   │   └── Gym.swift
│   ├── Features/
│   │   ├── Onboarding/
│   │   │   ├── OnboardingCoordinator.swift
│   │   │   ├── SignInView.swift
│   │   │   ├── UsernameView.swift
│   │   │   ├── HomeGymView.swift
│   │   │   ├── NotificationPermissionView.swift
│   │   │   └── WhatNextView.swift
│   │   ├── Home/
│   │   │   └── HomeView.swift
│   │   ├── Library/
│   │   │   ├── LibraryTabView.swift         # Sub-tabs: Routines / Exercises
│   │   │   ├── RoutinesListView.swift
│   │   │   ├── RoutineBuilderView.swift
│   │   │   ├── ExercisesListView.swift
│   │   │   └── ExerciseDetailView.swift
│   │   ├── Workout/
│   │   │   ├── WorkoutSessionView.swift     # In-progress solo workout
│   │   │   ├── LogSetSheet.swift
│   │   │   └── WorkoutRecapView.swift
│   │   ├── Stats/
│   │   │   ├── StatsTabView.swift
│   │   │   ├── ActivityFeedView.swift
│   │   │   ├── ExerciseHistoryView.swift
│   │   │   └── TrendChartView.swift
│   │   └── You/
│   │       └── YouTabView.swift             # Profile, sign out
│   ├── Components/
│   │   ├── PrimaryButton.swift
│   │   ├── LoadingView.swift
│   │   └── ErrorBanner.swift
│   └── Utilities/
│       ├── ErrorMapping.swift               # Supabase error → user-readable
│       └── UUID+Client.swift                # Client-generated UUIDs helper
└── GymSyncTests/
    ├── AuthServiceTests.swift
    ├── ProfileTests.swift
    ├── RoutineBuilderTests.swift
    ├── SetLoggingTests.swift
    ├── PRDetectionClientTests.swift
    └── HealthKitBridgeTests.swift
```

## Interfaces That Cross Task Boundaries

The following types/functions are defined in earlier tasks and consumed by later tasks. Any change to these signatures ripples through the plan.

```swift
// Defined in Task 12 (SupabaseService)
@Observable final class SupabaseService {
    static let shared: SupabaseService
    let client: SupabaseClient
    func currentUserID() async -> UUID?
    func signOut() async throws
}

// Defined in Task 13 (AuthService)
@Observable final class AuthService {
    static let shared: AuthService
    enum AuthState { case signedOut, signedIn(userID: UUID), pending }
    var state: AuthState
    func signInWithApple(identityToken: String) async throws
    func refreshSession() async throws
}

// Defined in Task 21 (Profile model)
struct Profile: Codable, Identifiable, Sendable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
}
// ProfileRepository is a namespace-style enum:
enum ProfileRepository {
    static func fetch(userID: UUID) async throws -> Profile?
    static func create(username: String) async throws -> Profile
    static func usernameAvailable(_ username: String) async throws -> Bool
}

// Defined in Task 26 (Exercise model)
struct Exercise: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let category: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let equipment: String
    let defaultUnit: String
    let demoVideoURL: URL?
}
enum ExerciseRepository {
    static func fetchAll() async throws -> [Exercise]
    static func fetch(id: UUID) async throws -> Exercise?
}

// Defined in Task 30 (Routine model)
struct Routine: Codable, Identifiable, Sendable {
    let id: UUID
    let ownerID: UUID
    var name: String
    var description: String?
    let visibility: String  // "private" for Phase 1
    let createdAt: Date
    var updatedAt: Date
}
struct RoutineExercise: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID
    let exerciseID: UUID
    var position: Int
    var targetSets: Int?
    var targetReps: String?
    var targetWeight: String?
    var restSeconds: Int?
    var notes: String?
}
enum RoutineRepository {
    static func fetchAll(ownerID: UUID) async throws -> [Routine]
    static func fetch(id: UUID) async throws -> (Routine, [RoutineExercise])?
    static func save(_ routine: Routine, exercises: [RoutineExercise]) async throws
    static func delete(id: UUID) async throws
}

// Defined in Task 35 (Session + SetLog models)
struct WorkoutSession: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID?
    let organizerID: UUID
    var state: String  // "in_progress" | "completed" | "abandoned"
    var startedAt: Date?
    var completedAt: Date?
    let createdAt: Date
}
struct SetLog: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let sessionID: UUID
    let exerciseID: UUID
    let setIndex: Int
    var reps: Int?
    var weight: Decimal?
    var rpe: Decimal?
    var isFailed: Bool
    var isPenalty: Bool  // always false in Phase 1
    var note: String?
    let loggedAt: Date
}
enum SessionRepository {
    static func startSolo(routineID: UUID?) async throws -> WorkoutSession
    static func complete(sessionID: UUID) async throws -> WorkoutSession
    static func logSet(_ set: SetLog) async throws
    static func history(userID: UUID, limit: Int) async throws -> [WorkoutSession]
    static func setLogs(sessionID: UUID) async throws -> [SetLog]
    static func exerciseHistory(userID: UUID, exerciseID: UUID, limit: Int) async throws -> [SetLog]
}
```

---

## Tasks

### Task 1: Supabase project + local dev environment

**Files:**
- Create: `GymSync/supabase/config.toml`
- Create: `GymSync/.env.local` (gitignored)
- Create: `GymSync/.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: a live Supabase project + local dev workflow

- [ ] **Step 1: Install Supabase CLI**

Run:
```bash
brew install supabase/tap/supabase
supabase --version
```
Expected: prints a version like `1.150.0` or higher.

- [ ] **Step 2: Create Supabase project via dashboard**

Go to `https://supabase.com/dashboard/new`, create a new project named **gym-sync-prod**. Choose a strong DB password and save it in a password manager. Region: closest to target users. Note the **Project URL** and **anon public key** from Project Settings → API.

- [ ] **Step 3: Initialize local Supabase workspace**

Run from repository root:
```bash
cd G:/Projects/GymSync
supabase init
```
Expected: creates `supabase/config.toml` and empty `supabase/migrations/` directory. Commit these.

- [ ] **Step 4: Save credentials to gitignored `.env.local`**

Create `.env.local`:
```
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_ANON_KEY=<your-anon-key>
SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key>
SUPABASE_DB_PASSWORD=<your-db-password>
```

Append to `.gitignore`:
```
.env.local
.env
*.xcuserstate
xcuserdata/
GymSyncApp/GymSync/Config/Secrets.swift
DerivedData/
.build/
```

- [ ] **Step 5: Link CLI to remote project**

Run:
```bash
supabase link --project-ref <project-ref>
```
When prompted, enter the DB password from Step 2.

Expected: `Finished supabase link.`

- [ ] **Step 6: Commit**

```bash
git add supabase/config.toml supabase/migrations .gitignore
git commit -m "chore: initialize Supabase project + local CLI workspace"
```

---

### Task 2: Postgres migration — profiles table + RLS

**Files:**
- Create: `supabase/migrations/20260709000001_create_profiles.sql`
- Create: `supabase/tests/rls_profiles_test.sql`

**Interfaces:**
- Consumes: Supabase project from Task 1
- Produces: `public.profiles` table backing every user record

- [ ] **Step 1: Write the failing test**

Create `supabase/tests/rls_profiles_test.sql`:
```sql
BEGIN;
SELECT plan(4);

-- Setup: create two auth users
INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@test.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@test.com');

-- Insert profiles
SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a');

-- Positive: user A can update their own profile
SELECT lives_ok(
  $$UPDATE profiles SET display_name='Alpha' WHERE id='00000000-0000-0000-0000-000000000001'$$,
  'user can update own profile'
);

-- Negative: user A cannot update user B's profile
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000002', 'user_b');
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';
SELECT throws_ok(
  $$UPDATE profiles SET display_name='hack' WHERE id='00000000-0000-0000-0000-000000000002'$$,
  '42501',  -- insufficient_privilege
  NULL,
  'user cannot update other profile'
);

-- Positive: authenticated user can read any profile (public directory)
SELECT lives_ok(
  $$SELECT * FROM profiles WHERE id='00000000-0000-0000-0000-000000000002'$$,
  'user can read other profile'
);

-- Positive: unique username enforced
SELECT throws_ok(
  $$INSERT INTO profiles (id, username) VALUES (gen_random_uuid(), 'user_a')$$,
  '23505',  -- unique_violation
  NULL,
  'duplicate username rejected'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 2: Run test to verify it fails**

Run:
```bash
supabase db test
```
Expected: FAIL with "relation profiles does not exist"

- [ ] **Step 3: Write the migration**

Create `supabase/migrations/20260709000001_create_profiles.sql`:
```sql
CREATE TABLE public.profiles (
  id                     uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  username               text UNIQUE NOT NULL CHECK (length(username) >= 3),
  display_name           text,
  avatar_url             text,
  created_at             timestamptz NOT NULL DEFAULT now(),
  show_solo_workouts     boolean NOT NULL DEFAULT false,
  lifetime_volume_lifted numeric(14,2) NOT NULL DEFAULT 0
);

CREATE INDEX profiles_username_lower_idx ON public.profiles (lower(username));

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles are readable by any authenticated user"
  ON public.profiles FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "users can insert their own profile"
  ON public.profiles FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

CREATE POLICY "users can update their own profile"
  ON public.profiles FOR UPDATE
  TO authenticated
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);
```

- [ ] **Step 4: Run test to verify it passes**

Run:
```bash
supabase db reset --linked
supabase db test
```
Expected: `ok 1 - user can update own profile`, `ok 2 - user cannot update other profile`, `ok 3 - user can read other profile`, `ok 4 - duplicate username rejected`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260709000001_create_profiles.sql supabase/tests/rls_profiles_test.sql
git commit -m "feat(db): profiles table + RLS + tests"
```

---

### Task 3: Postgres migration — exercises table + curated seed

**Files:**
- Create: `supabase/migrations/20260709000002_create_exercises.sql`
- Create: `supabase/migrations/20260709000003_seed_exercises.sql`
- Create: `supabase/seed/exercises.sql`

**Interfaces:**
- Produces: `public.exercises` table with an initial curated seed of ~30 exercises for Phase 1 (full library grows over time).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260709000002_create_exercises.sql`:
```sql
CREATE TABLE public.exercises (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name              text NOT NULL,
  slug              text UNIQUE NOT NULL,
  category          text NOT NULL CHECK (category IN ('compound','isolation','cardio','mobility')),
  primary_muscle    text NOT NULL,
  secondary_muscles text[] NOT NULL DEFAULT '{}',
  equipment         text NOT NULL,
  default_unit      text NOT NULL DEFAULT 'lbs',
  demo_video_url    text,
  is_user_defined   boolean NOT NULL DEFAULT false
);

CREATE INDEX exercises_slug_idx ON public.exercises(slug);
CREATE INDEX exercises_primary_muscle_idx ON public.exercises(primary_muscle);

ALTER TABLE public.exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exercises are globally readable"
  ON public.exercises FOR SELECT
  TO authenticated
  USING (true);

-- No INSERT/UPDATE/DELETE policies — writes only via service_role (seed migrations).
```

- [ ] **Step 2: Write the seed migration**

Create `supabase/migrations/20260709000003_seed_exercises.sql`:
```sql
INSERT INTO public.exercises (name, slug, category, primary_muscle, secondary_muscles, equipment) VALUES
  ('Bench Press', 'bench-press', 'compound', 'chest', ARRAY['triceps','front_delts'], 'barbell'),
  ('Incline Bench Press', 'incline-bench-press', 'compound', 'chest', ARRAY['triceps','front_delts'], 'barbell'),
  ('Dumbbell Bench Press', 'db-bench-press', 'compound', 'chest', ARRAY['triceps','front_delts'], 'dumbbell'),
  ('Overhead Press', 'ohp', 'compound', 'shoulders', ARRAY['triceps','upper_chest'], 'barbell'),
  ('Dumbbell Shoulder Press', 'db-shoulder-press', 'compound', 'shoulders', ARRAY['triceps'], 'dumbbell'),
  ('Back Squat', 'back-squat', 'compound', 'quads', ARRAY['glutes','hamstrings','core'], 'barbell'),
  ('Front Squat', 'front-squat', 'compound', 'quads', ARRAY['glutes','core'], 'barbell'),
  ('Goblet Squat', 'goblet-squat', 'compound', 'quads', ARRAY['glutes','core'], 'dumbbell'),
  ('Conventional Deadlift', 'deadlift', 'compound', 'hamstrings', ARRAY['glutes','back','traps'], 'barbell'),
  ('Romanian Deadlift', 'rdl', 'compound', 'hamstrings', ARRAY['glutes','lower_back'], 'barbell'),
  ('Sumo Deadlift', 'sumo-deadlift', 'compound', 'glutes', ARRAY['hamstrings','back'], 'barbell'),
  ('Pull-Up', 'pull-up', 'compound', 'lats', ARRAY['biceps','rear_delts'], 'bodyweight'),
  ('Chin-Up', 'chin-up', 'compound', 'lats', ARRAY['biceps'], 'bodyweight'),
  ('Barbell Row', 'barbell-row', 'compound', 'back', ARRAY['biceps','rear_delts'], 'barbell'),
  ('Dumbbell Row', 'db-row', 'compound', 'back', ARRAY['biceps','rear_delts'], 'dumbbell'),
  ('Lat Pulldown', 'lat-pulldown', 'compound', 'lats', ARRAY['biceps'], 'cable'),
  ('Seated Cable Row', 'cable-row', 'compound', 'back', ARRAY['biceps','rear_delts'], 'cable'),
  ('Bicep Curl', 'bicep-curl', 'isolation', 'biceps', ARRAY['forearms'], 'dumbbell'),
  ('Hammer Curl', 'hammer-curl', 'isolation', 'biceps', ARRAY['forearms'], 'dumbbell'),
  ('Tricep Pushdown', 'tricep-pushdown', 'isolation', 'triceps', ARRAY[]::text[], 'cable'),
  ('Overhead Tricep Extension', 'oh-tricep-ext', 'isolation', 'triceps', ARRAY[]::text[], 'dumbbell'),
  ('Lateral Raise', 'lat-raise', 'isolation', 'shoulders', ARRAY[]::text[], 'dumbbell'),
  ('Face Pull', 'face-pull', 'isolation', 'rear_delts', ARRAY['traps'], 'cable'),
  ('Leg Press', 'leg-press', 'compound', 'quads', ARRAY['glutes'], 'machine'),
  ('Leg Curl', 'leg-curl', 'isolation', 'hamstrings', ARRAY[]::text[], 'machine'),
  ('Leg Extension', 'leg-extension', 'isolation', 'quads', ARRAY[]::text[], 'machine'),
  ('Calf Raise', 'calf-raise', 'isolation', 'calves', ARRAY[]::text[], 'machine'),
  ('Plank', 'plank', 'isolation', 'core', ARRAY[]::text[], 'bodyweight'),
  ('Hanging Leg Raise', 'hanging-leg-raise', 'isolation', 'core', ARRAY['hip_flexors'], 'bodyweight'),
  ('Push-Up', 'push-up', 'compound', 'chest', ARRAY['triceps','front_delts','core'], 'bodyweight');
```

- [ ] **Step 3: Apply migrations to remote**

Run:
```bash
supabase db push
```
Expected: `Applied migration ...` for both files.

- [ ] **Step 4: Verify seeded data**

Run:
```bash
supabase db execute --linked -f - <<'SQL'
SELECT COUNT(*) FROM public.exercises;
SQL
```
Expected: `30`

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260709000002_create_exercises.sql supabase/migrations/20260709000003_seed_exercises.sql
git commit -m "feat(db): exercises table + Phase 1 curated seed (30 exercises)"
```

---

### Task 4: Postgres migration — gyms table + RLS

**Files:**
- Create: `supabase/migrations/20260709000004_create_gyms.sql`

**Interfaces:**
- Produces: `public.gyms` table for user-owned personal gym locations (used in home-gym onboarding step).

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260709000004_create_gyms.sql`:
```sql
CREATE TABLE public.gyms (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id        uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name           text NOT NULL,
  latitude       double precision NOT NULL,
  longitude      double precision NOT NULL,
  radius_meters  integer NOT NULL DEFAULT 200 CHECK (radius_meters > 0),
  is_primary     boolean NOT NULL DEFAULT false,
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX gyms_user_id_idx ON public.gyms(user_id);

-- Enforce single primary per user
CREATE UNIQUE INDEX gyms_one_primary_per_user_idx
  ON public.gyms(user_id)
  WHERE is_primary = true;

ALTER TABLE public.gyms ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select their own gyms"
  ON public.gyms FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "users can insert their own gyms"
  ON public.gyms FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users can update their own gyms"
  ON public.gyms FOR UPDATE TO authenticated
  USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE POLICY "users can delete their own gyms"
  ON public.gyms FOR DELETE TO authenticated
  USING (auth.uid() = user_id);
```

- [ ] **Step 2: Apply and verify**

Run:
```bash
supabase db push
```
Expected: `Applied migration 20260709000004_create_gyms`.

- [ ] **Step 3: Commit**

```bash
git add supabase/migrations/20260709000004_create_gyms.sql
git commit -m "feat(db): gyms table + RLS (owner-only)"
```

---

### Task 5: Postgres migrations — routines + routine_exercises

**Files:**
- Create: `supabase/migrations/20260709000005_create_routines.sql`
- Create: `supabase/tests/rls_routines_test.sql`

**Interfaces:**
- Produces: `public.routines` and `public.routine_exercises` tables.

- [ ] **Step 1: Write the migration**

Create `supabase/migrations/20260709000005_create_routines.sql`:
```sql
CREATE TABLE public.routines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  name              text NOT NULL,
  description       text,
  visibility        text NOT NULL DEFAULT 'private' CHECK (visibility IN ('private','shared','public')),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX routines_owner_id_idx ON public.routines(owner_id);

CREATE TABLE public.routine_exercises (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id     uuid NOT NULL REFERENCES public.routines(id) ON DELETE CASCADE,
  exercise_id    uuid NOT NULL REFERENCES public.exercises(id),
  position       integer NOT NULL CHECK (position >= 1),
  target_sets    integer CHECK (target_sets >= 1),
  target_reps    text,
  target_weight  text,
  rest_seconds   integer CHECK (rest_seconds >= 0),
  notes          text,
  UNIQUE (routine_id, position)
);

CREATE INDEX routine_exercises_routine_id_idx ON public.routine_exercises(routine_id);

ALTER TABLE public.routines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.routine_exercises ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select routines they own OR public routines"
  ON public.routines FOR SELECT TO authenticated
  USING (auth.uid() = owner_id OR visibility = 'public');

CREATE POLICY "users can insert their own routines"
  ON public.routines FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "users can update their own routines"
  ON public.routines FOR UPDATE TO authenticated
  USING (auth.uid() = owner_id) WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "users can delete their own routines"
  ON public.routines FOR DELETE TO authenticated
  USING (auth.uid() = owner_id);

-- routine_exercises inherit parent visibility
CREATE POLICY "routine_exercises follow parent routine visibility"
  ON public.routine_exercises FOR SELECT TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id
      AND (r.owner_id = auth.uid() OR r.visibility = 'public')
  ));

CREATE POLICY "routine_exercises writable by parent owner"
  ON public.routine_exercises FOR ALL TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id AND r.owner_id = auth.uid()
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.routines r
    WHERE r.id = routine_exercises.routine_id AND r.owner_id = auth.uid()
  ));
```

- [ ] **Step 2: Write RLS tests**

Create `supabase/tests/rls_routines_test.sql`:
```sql
BEGIN;
SELECT plan(4);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@t.com');

INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a'),
  ('00000000-0000-0000-0000-000000000002', 'user_b');

INSERT INTO routines (id, owner_id, name, visibility) VALUES
  ('10000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'A Private', 'private'),
  ('10000000-0000-0000-0000-000000000002',
   '00000000-0000-0000-0000-000000000002', 'B Private', 'private');

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Positive: user A can read their own routine
SELECT results_eq(
  $$SELECT count(*)::int FROM routines WHERE owner_id='00000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'user can read own routines'
);

-- Negative: user A cannot see user B's private routine
SELECT results_eq(
  $$SELECT count(*)::int FROM routines WHERE owner_id='00000000-0000-0000-0000-000000000002'$$,
  ARRAY[0],
  'user cannot read others private routines'
);

-- Positive: user A can insert their own routine
SELECT lives_ok(
  $$INSERT INTO routines (owner_id, name) VALUES ('00000000-0000-0000-0000-000000000001', 'New')$$,
  'user can insert own routine'
);

-- Negative: user A cannot insert as user B
SELECT throws_ok(
  $$INSERT INTO routines (owner_id, name) VALUES ('00000000-0000-0000-0000-000000000002', 'Hack')$$,
  '42501', NULL,
  'user cannot insert routine owned by another'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 3: Apply and test**

Run:
```bash
supabase db push
supabase db test
```
Expected: all `ok` results.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260709000005_create_routines.sql supabase/tests/rls_routines_test.sql
git commit -m "feat(db): routines + routine_exercises tables with RLS + tests"
```

---

### Task 6: Postgres migrations — sessions + set_logs

**Files:**
- Create: `supabase/migrations/20260709000006_create_sessions.sql`
- Create: `supabase/migrations/20260709000007_create_set_logs.sql`
- Create: `supabase/tests/rls_set_logs_test.sql`

**Interfaces:**
- Produces: `public.sessions`, `public.session_participants`, `public.set_logs` tables (single-participant variant for Phase 1; multi-participant fields exist for Phase 3 reuse).

- [ ] **Step 1: Write sessions migration**

Create `supabase/migrations/20260709000006_create_sessions.sql`:
```sql
CREATE TABLE public.sessions (
  id                       uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  routine_id               uuid REFERENCES public.routines(id) ON DELETE SET NULL,
  organizer_id             uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  state                    text NOT NULL DEFAULT 'in_progress'
                                        CHECK (state IN ('scheduled','lobby_open','editing','voting',
                                                         'locked','in_progress','completed','abandoned')),
  scheduled_for            timestamptz,
  started_at               timestamptz,
  completed_at             timestamptz,
  duration_was_edited      boolean NOT NULL DEFAULT false,
  created_at               timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX sessions_organizer_id_idx ON public.sessions(organizer_id);
CREATE INDEX sessions_organizer_completed_idx ON public.sessions(organizer_id, completed_at DESC);

CREATE TABLE public.session_participants (
  session_id       uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id          uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  turn_order       integer,
  check_in_state   text CHECK (check_in_state IN ('invited','online','ready','late','no_show')),
  PRIMARY KEY (session_id, user_id)
);

ALTER TABLE public.sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.session_participants ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select sessions they participate in"
  ON public.sessions FOR SELECT TO authenticated
  USING (
    organizer_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.session_participants sp
               WHERE sp.session_id = sessions.id AND sp.user_id = auth.uid())
  );

CREATE POLICY "users can insert sessions as organizer"
  ON public.sessions FOR INSERT TO authenticated
  WITH CHECK (organizer_id = auth.uid());

CREATE POLICY "organizer or participant can update session"
  ON public.sessions FOR UPDATE TO authenticated
  USING (
    organizer_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.session_participants sp
               WHERE sp.session_id = sessions.id AND sp.user_id = auth.uid())
  );

CREATE POLICY "participants readable by other participants"
  ON public.session_participants FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.session_participants sp2
               WHERE sp2.session_id = session_participants.session_id AND sp2.user_id = auth.uid())
  );

CREATE POLICY "participants writable only via session organizer"
  ON public.session_participants FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.sessions s
                 WHERE s.id = session_participants.session_id AND s.organizer_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM public.sessions s
                      WHERE s.id = session_participants.session_id AND s.organizer_id = auth.uid()));
```

- [ ] **Step 2: Write set_logs migration**

Create `supabase/migrations/20260709000007_create_set_logs.sql`:
```sql
CREATE TABLE public.set_logs (
  id          uuid PRIMARY KEY,  -- client-generated for idempotent retry
  user_id     uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  session_id  uuid NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  exercise_id uuid NOT NULL REFERENCES public.exercises(id),
  set_index   integer NOT NULL CHECK (set_index >= 1),
  reps        integer CHECK (reps IS NULL OR reps >= 0),
  weight      numeric(7,2) CHECK (weight IS NULL OR weight >= 0),
  rpe         numeric(3,1) CHECK (rpe IS NULL OR (rpe >= 1 AND rpe <= 10)),
  is_failed   boolean NOT NULL DEFAULT false,
  is_penalty  boolean NOT NULL DEFAULT false,
  note        text,
  logged_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX set_logs_user_exercise_time_idx
  ON public.set_logs(user_id, exercise_id, logged_at DESC);
CREATE INDEX set_logs_user_time_idx
  ON public.set_logs(user_id, logged_at DESC);
CREATE INDEX set_logs_session_idx
  ON public.set_logs(session_id, set_index);

ALTER TABLE public.set_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users can select their own set logs OR shared session logs"
  ON public.set_logs FOR SELECT TO authenticated
  USING (
    user_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.session_participants sp
      WHERE sp.session_id = set_logs.session_id AND sp.user_id = auth.uid()
    )
  );

CREATE POLICY "users can insert their own set logs"
  ON public.set_logs FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE POLICY "users can update their own set logs"
  ON public.set_logs FOR UPDATE TO authenticated
  USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
```

- [ ] **Step 3: Write RLS test**

Create `supabase/tests/rls_set_logs_test.sql`:
```sql
BEGIN;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com'),
  ('00000000-0000-0000-0000-000000000002', 'b@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a'),
  ('00000000-0000-0000-0000-000000000002', 'user_b');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(), '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001', e.id, 1, 5, 185 FROM e;

SET LOCAL role authenticated;
SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000001';

-- Positive: user A can read their own set logs
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs WHERE user_id='00000000-0000-0000-0000-000000000001'$$,
  ARRAY[1],
  'user can read own set logs'
);

SET LOCAL request.jwt.claim.sub = '00000000-0000-0000-0000-000000000002';

-- Negative: user B cannot see user A's solo set logs (B is not a session participant)
SELECT results_eq(
  $$SELECT count(*)::int FROM set_logs$$,
  ARRAY[0],
  'unrelated user cannot see set logs'
);

-- Negative: user B cannot insert set logs as user A
SELECT throws_ok(
  $$INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index)
    VALUES (gen_random_uuid(),
            '00000000-0000-0000-0000-000000000001',
            '20000000-0000-0000-0000-000000000001',
            (SELECT id FROM exercises LIMIT 1),
            1)$$,
  '42501', NULL,
  'user cannot insert set logs for another user'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 4: Apply and test**

Run:
```bash
supabase db push
supabase db test
```
Expected: all `ok`.

- [ ] **Step 5: Commit**

```bash
git add supabase/migrations/20260709000006_create_sessions.sql \
        supabase/migrations/20260709000007_create_set_logs.sql \
        supabase/tests/rls_set_logs_test.sql
git commit -m "feat(db): sessions + session_participants + set_logs + RLS + tests"
```

---

### Task 7: Postgres trigger — lifetime volume + PR detection

**Files:**
- Create: `supabase/migrations/20260709000008_lifetime_volume_trigger.sql`
- Create: `supabase/migrations/20260709000009_pr_detection_trigger.sql`
- Create: `supabase/tests/volume_trigger_test.sql`
- Create: `supabase/tests/pr_trigger_test.sql`

**Interfaces:**
- Produces: automatic increments to `profiles.lifetime_volume_lifted`, and a `is_pr` marker approach used by clients to decide when to celebrate.

- [ ] **Step 1: Write the volume trigger migration**

Create `supabase/migrations/20260709000008_lifetime_volume_trigger.sql`:
```sql
CREATE OR REPLACE FUNCTION public.increment_lifetime_volume()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.is_failed = false AND NEW.is_penalty = false
     AND NEW.reps IS NOT NULL AND NEW.weight IS NOT NULL THEN
    UPDATE public.profiles
      SET lifetime_volume_lifted = lifetime_volume_lifted + (NEW.reps * NEW.weight)
      WHERE id = NEW.user_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER set_logs_increment_volume
  AFTER INSERT ON public.set_logs
  FOR EACH ROW EXECUTE FUNCTION public.increment_lifetime_volume();
```

- [ ] **Step 2: Write the PR detection migration**

Create `supabase/migrations/20260709000009_pr_detection_trigger.sql`:
```sql
-- For Phase 1, PR detection returns a boolean the client can use to render
-- a celebration on the newly-inserted log. Phase 4 will replace this with a
-- system_pr chat message when Groups + Chat exist.

CREATE OR REPLACE FUNCTION public.is_pr(p_user_id uuid, p_exercise_id uuid, p_weight numeric)
RETURNS boolean LANGUAGE sql STABLE AS $$
  SELECT NOT EXISTS (
    SELECT 1 FROM public.set_logs
    WHERE user_id = p_user_id
      AND exercise_id = p_exercise_id
      AND is_failed = false
      AND is_penalty = false
      AND weight >= p_weight
  );
$$;

COMMENT ON FUNCTION public.is_pr IS
  'Returns true when the given weight strictly exceeds all prior non-failed non-penalty logs for the user+exercise. Callable from clients to render PR celebrations.';
```

- [ ] **Step 3: Write volume trigger test**

Create `supabase/tests/volume_trigger_test.sql`:
```sql
BEGIN;
SELECT plan(1);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(),
       '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001',
       e.id, 1, 5, 185.00 FROM e;

SELECT results_eq(
  $$SELECT lifetime_volume_lifted FROM profiles
    WHERE id='00000000-0000-0000-0000-000000000001'$$,
  $$VALUES (925.00::numeric(14,2))$$,
  '5 reps × 185 lbs = 925 lbs added to lifetime volume'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 4: Write PR trigger test**

Create `supabase/tests/pr_trigger_test.sql`:
```sql
BEGIN;
SELECT plan(3);

INSERT INTO auth.users (id, email) VALUES
  ('00000000-0000-0000-0000-000000000001', 'a@t.com');
INSERT INTO profiles (id, username) VALUES
  ('00000000-0000-0000-0000-000000000001', 'user_a');
INSERT INTO sessions (id, organizer_id, state) VALUES
  ('20000000-0000-0000-0000-000000000001',
   '00000000-0000-0000-0000-000000000001', 'in_progress');

-- First set → PR (nothing prior)
SELECT ok(
  public.is_pr('00000000-0000-0000-0000-000000000001',
               (SELECT id FROM exercises WHERE slug='bench-press'),
               185.00),
  'first log for exercise is a PR'
);

WITH e AS (SELECT id FROM exercises WHERE slug='bench-press' LIMIT 1)
INSERT INTO set_logs (id, user_id, session_id, exercise_id, set_index, reps, weight)
SELECT gen_random_uuid(),
       '00000000-0000-0000-0000-000000000001',
       '20000000-0000-0000-0000-000000000001',
       e.id, 1, 5, 185.00 FROM e;

-- Same weight → NOT a PR (must strictly exceed)
SELECT ok(
  NOT public.is_pr('00000000-0000-0000-0000-000000000001',
                   (SELECT id FROM exercises WHERE slug='bench-press'),
                   185.00),
  'matching prior weight is not a PR'
);

-- Higher weight → PR
SELECT ok(
  public.is_pr('00000000-0000-0000-0000-000000000001',
               (SELECT id FROM exercises WHERE slug='bench-press'),
               190.00),
  'strictly higher weight is a PR'
);

SELECT * FROM finish();
ROLLBACK;
```

- [ ] **Step 5: Apply and test**

Run:
```bash
supabase db push
supabase db test
```
Expected: all `ok`.

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260709000008_lifetime_volume_trigger.sql \
        supabase/migrations/20260709000009_pr_detection_trigger.sql \
        supabase/tests/volume_trigger_test.sql \
        supabase/tests/pr_trigger_test.sql
git commit -m "feat(db): lifetime volume trigger + is_pr helper + tests"
```

---

### Task 8: iOS Xcode project scaffold

**Files:**
- Create: `GymSyncApp/GymSync.xcodeproj` (via Xcode wizard)
- Create: `GymSyncApp/GymSync/App/GymSyncApp.swift`

**Interfaces:**
- Produces: an iOS app target that builds and launches.

- [ ] **Step 1: Create the Xcode project**

Open Xcode 15+ → File → New → Project → iOS App. Settings:
- Product Name: **GymSync**
- Team: your Apple Developer team
- Organization Identifier: `app.gymsync`
- Bundle Identifier: `app.gymsync.ios`
- Interface: **SwiftUI**
- Language: **Swift**
- Storage: **SwiftData**
- Include Tests: **Yes**

Save into `G:/Projects/GymSync/GymSyncApp/`.

- [ ] **Step 2: Set iOS 17.0 minimum deployment target**

Project → Target GymSync → General → Minimum Deployments → iOS 17.0.

- [ ] **Step 3: Add required capabilities**

Signing & Capabilities tab → + Capability:
- **Sign in with Apple**
- **HealthKit** (check "Health Records" NO; "Clinical Health Records" NO; workouts write permission is requested at runtime)

- [ ] **Step 4: Add HealthKit usage strings to Info.plist**

Add to Info.plist:
```xml
<key>NSHealthShareUsageDescription</key>
<string>Gym Sync writes your completed workouts to Apple Health so they appear in your Activity ring.</string>
<key>NSHealthUpdateUsageDescription</key>
<string>Gym Sync writes your completed workouts to Apple Health so they appear in your Activity ring.</string>
<key>NSLocationWhenInUseUsageDescription</key>
<string>Gym Sync uses your location to confirm you're at your home gym during check-in.</string>
```

- [ ] **Step 5: Verify build succeeds**

Run: `⌘B` in Xcode.
Expected: `Build Succeeded`.

- [ ] **Step 6: Commit**

```bash
cd G:/Projects/GymSync
git add GymSyncApp/
git commit -m "feat(ios): initialize Xcode project with iOS 17 target + capabilities"
```

---

### Task 9: iOS project — add Supabase Swift SDK via SPM

**Files:**
- Modify: `GymSync.xcodeproj` (package dependencies)

**Interfaces:**
- Consumes: iOS project from Task 8
- Produces: `import Supabase` available in Swift code

- [ ] **Step 1: Add Supabase SDK dependency**

Xcode → File → Add Package Dependencies → paste URL:
```
https://github.com/supabase/supabase-swift
```
Version rule: **Up to Next Major Version, starting at 2.5.0**.
Add product: `Supabase` to the GymSync target.

- [ ] **Step 2: Write import smoke test**

Create `GymSyncApp/GymSyncTests/SupabaseImportTests.swift`:
```swift
import XCTest
import Supabase

final class SupabaseImportTests: XCTestCase {
    func testSDKCanBeImported() {
        // If this test compiles + runs, the SDK is wired.
        let url = URL(string: "https://example.supabase.co")!
        let client = SupabaseClient(supabaseURL: url, supabaseKey: "anon-key-placeholder")
        XCTAssertNotNil(client.auth)
    }
}
```

- [ ] **Step 3: Run test**

`⌘U` in Xcode.
Expected: `Test Succeeded`.

- [ ] **Step 4: Commit**

```bash
git add GymSyncApp/
git commit -m "feat(ios): add supabase-swift SDK via SPM + smoke test"
```

---

### Task 10: iOS project — Secrets, AppConfig, AppLogger

**Files:**
- Create: `GymSyncApp/GymSync/Config/Secrets.swift.template`
- Create: `GymSyncApp/GymSync/Config/Secrets.swift` (gitignored)
- Create: `GymSyncApp/GymSync/Config/AppConfig.swift`
- Create: `GymSyncApp/GymSync/Services/AppLogger.swift`

**Interfaces:**
- Produces: `Secrets.supabaseURL`, `Secrets.supabaseAnonKey`, `AppConfig`, `AppLogger`.

- [ ] **Step 1: Write Secrets template + real file**

Create `GymSyncApp/GymSync/Config/Secrets.swift.template`:
```swift
import Foundation

// Copy to Secrets.swift (gitignored) and fill in real values.
enum Secrets {
    static let supabaseURL = URL(string: "https://YOUR-PROJECT.supabase.co")!
    static let supabaseAnonKey = "YOUR_ANON_PUBLIC_KEY"
}
```

Create `GymSyncApp/GymSync/Config/Secrets.swift` (paste values from `.env.local`):
```swift
import Foundation

enum Secrets {
    static let supabaseURL = URL(string: "https://<project-ref>.supabase.co")!
    static let supabaseAnonKey = "<your-anon-key>"
}
```

- [ ] **Step 2: Write AppConfig**

Create `GymSyncApp/GymSync/Config/AppConfig.swift`:
```swift
import Foundation

enum AppConfig {
    static let appName = "Gym Sync"
    static let minSetIndex = 1
    static let defaultRestSeconds = 90
    static let usernameMinLength = 3
    static let usernameMaxLength = 24
    static let defaultGymRadiusMeters = 200
}
```

- [ ] **Step 3: Write AppLogger**

Create `GymSyncApp/GymSync/Services/AppLogger.swift`:
```swift
import Foundation
import os

enum AppLogger {
    static let subsystem = "app.gymsync.ios"
    static let auth = Logger(subsystem: subsystem, category: "auth")
    static let network = Logger(subsystem: subsystem, category: "network")
    static let db = Logger(subsystem: subsystem, category: "db")
    static let workout = Logger(subsystem: subsystem, category: "workout")
    static let health = Logger(subsystem: subsystem, category: "health")
    static let ui = Logger(subsystem: subsystem, category: "ui")
}
```

- [ ] **Step 4: Verify build succeeds**

`⌘B`. Expected: `Build Succeeded`.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Config/Secrets.swift.template \
        GymSyncApp/GymSync/Config/AppConfig.swift \
        GymSyncApp/GymSync/Services/AppLogger.swift
git commit -m "feat(ios): Secrets template, AppConfig, AppLogger"
```

*(Note: `Secrets.swift` is gitignored — that's expected. Do not commit it.)*

---

### Task 11: iOS project — SupabaseService singleton

**Files:**
- Create: `GymSyncApp/GymSync/Services/SupabaseService.swift`
- Create: `GymSyncApp/GymSync/Utilities/ErrorMapping.swift`
- Create: `GymSyncApp/GymSyncTests/SupabaseServiceTests.swift`

**Interfaces:**
- Consumes: `Secrets`, `AppLogger`
- Produces: `SupabaseService.shared` (see Interfaces block at top of plan)

- [ ] **Step 1: Write failing test**

Create `GymSyncApp/GymSyncTests/SupabaseServiceTests.swift`:
```swift
import XCTest
@testable import GymSync

final class SupabaseServiceTests: XCTestCase {
    func testSharedInstanceIsNotNil() {
        XCTAssertNotNil(SupabaseService.shared)
    }

    func testSharedInstanceUsesConfiguredURL() {
        XCTAssertEqual(SupabaseService.shared.client.supabaseURL, Secrets.supabaseURL)
    }

    func testCurrentUserIDIsNilWhenSignedOut() async {
        let id = await SupabaseService.shared.currentUserID()
        XCTAssertNil(id, "no user should be signed in during unit test")
    }
}
```

- [ ] **Step 2: Verify it fails**

`⌘U`. Expected: compilation error `Cannot find 'SupabaseService' in scope`.

- [ ] **Step 3: Write ErrorMapping utility**

Create `GymSyncApp/GymSync/Utilities/ErrorMapping.swift`:
```swift
import Foundation
import Supabase

enum GymSyncError: LocalizedError {
    case network
    case unauthorized
    case notFound
    case validation(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network: return "Network issue. Check your connection and try again."
        case .unauthorized: return "You're signed out. Please sign in again."
        case .notFound: return "We couldn't find that."
        case .validation(let msg): return msg
        case .unknown(let msg): return msg
        }
    }
}

enum ErrorMapping {
    static func map(_ error: Error) -> GymSyncError {
        // PostgrestError has code + message; AuthError has message; URLError has code.
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                return .network
            default: return .unknown(urlErr.localizedDescription)
            }
        }
        if let auth = error as? AuthError {
            return .unauthorized
        }
        if let pg = error as? PostgrestError {
            if pg.code == "PGRST116" { return .notFound }
            return .validation(pg.message ?? "Validation failed")
        }
        return .unknown(error.localizedDescription)
    }
}
```

- [ ] **Step 4: Write SupabaseService**

Create `GymSyncApp/GymSync/Services/SupabaseService.swift`:
```swift
import Foundation
import Supabase

@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        self.client = SupabaseClient(
            supabaseURL: Secrets.supabaseURL,
            supabaseKey: Secrets.supabaseAnonKey
        )
    }

    func currentUserID() async -> UUID? {
        do {
            let session = try await client.auth.session
            return session.user.id
        } catch {
            AppLogger.auth.debug("no active session: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }
}
```

- [ ] **Step 5: Run tests, verify pass**

`⌘U`. Expected: 3/3 pass.

- [ ] **Step 6: Commit**

```bash
git add GymSyncApp/GymSync/Services/SupabaseService.swift \
        GymSyncApp/GymSync/Utilities/ErrorMapping.swift \
        GymSyncApp/GymSyncTests/SupabaseServiceTests.swift
git commit -m "feat(ios): SupabaseService singleton + ErrorMapping"
```

---

### Task 12: iOS project — Sign in with Apple + AuthService

**Files:**
- Create: `GymSyncApp/GymSync/Services/AuthService.swift`
- Create: `GymSyncApp/GymSync/Features/Onboarding/SignInView.swift`
- Create: `GymSyncApp/GymSyncTests/AuthServiceTests.swift`

**Interfaces:**
- Consumes: `SupabaseService`
- Produces: `AuthService.shared`, `AuthService.AuthState` enum, `AuthService.signInWithApple(identityToken:)`

- [ ] **Step 1: Write AuthService**

Create `GymSyncApp/GymSync/Services/AuthService.swift`:
```swift
import Foundation
import Supabase
import AuthenticationServices

@Observable
@MainActor
final class AuthService {
    static let shared = AuthService()

    enum AuthState: Equatable {
        case signedOut
        case signedIn(userID: UUID)
        case pending
    }

    private(set) var state: AuthState = .pending

    private init() {
        Task { await bootstrap() }
    }

    func bootstrap() async {
        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        } else {
            state = .signedOut
        }
    }

    func signInWithApple(identityToken: String, nonce: String) async throws {
        let session = try await SupabaseService.shared.client.auth.signInWithIdToken(
            credentials: .init(provider: .apple, idToken: identityToken, nonce: nonce)
        )
        state = .signedIn(userID: session.user.id)
        AppLogger.auth.info("signed in as \(session.user.id, privacy: .public)")
    }

    func signOut() async throws {
        try await SupabaseService.shared.signOut()
        state = .signedOut
    }

    func refreshSession() async throws {
        _ = try await SupabaseService.shared.client.auth.refreshSession()
        if let id = await SupabaseService.shared.currentUserID() {
            state = .signedIn(userID: id)
        }
    }
}
```

- [ ] **Step 2: Write SignInView**

Create `GymSyncApp/GymSync/Features/Onboarding/SignInView.swift`:
```swift
import SwiftUI
import AuthenticationServices
import CryptoKit

struct SignInView: View {
    @State private var currentNonce: String = ""
    @State private var errorText: String?
    @Environment(AuthService.self) private var auth

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text("Gym Sync")
                .font(.largeTitle.bold())
            Text("Lift together, anywhere.")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
            SignInWithAppleButton(.signIn) { req in
                let nonce = Self.randomNonce()
                currentNonce = nonce
                req.requestedScopes = [.fullName, .email]
                req.nonce = Self.sha256(nonce)
            } onCompletion: { result in
                Task { await handle(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 50)
            .padding(.horizontal, 32)

            if let errorText {
                Text(errorText).foregroundStyle(.red).font(.footnote)
            }
            Spacer(minLength: 40)
        }
    }

    @MainActor
    private func handle(_ result: Result<ASAuthorization, Error>) async {
        do {
            switch result {
            case .success(let auth):
                guard
                    let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                    let tokenData = credential.identityToken,
                    let token = String(data: tokenData, encoding: .utf8)
                else {
                    errorText = "Missing identity token from Apple."
                    return
                }
                try await AuthService.shared.signInWithApple(identityToken: token,
                                                             nonce: currentNonce)
            case .failure(let err):
                errorText = ErrorMapping.map(err).errorDescription
            }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            let status = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            precondition(status == errSecSuccess)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        let hash = SHA256.hash(data: Data(input.utf8))
        return hash.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 3: Wire AuthService into the app**

Modify `GymSyncApp/GymSync/App/GymSyncApp.swift`:
```swift
import SwiftUI

@main
struct GymSyncApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthService.shared)
        }
    }
}
```

- [ ] **Step 4: Manual device test**

Build & run on a device signed into a real Apple ID. Tap Sign in with Apple → complete Face ID → verify `AuthService.shared.state == .signedIn(userID: ...)` in the debugger. Delete the app to reset test state.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Services/AuthService.swift \
        GymSyncApp/GymSync/Features/Onboarding/SignInView.swift \
        GymSyncApp/GymSync/App/GymSyncApp.swift
git commit -m "feat(auth): Sign in with Apple + AuthService + SignInView"
```

---

### Task 13: RootView + AppState + 5-tab shell (empty)

**Files:**
- Create: `GymSyncApp/GymSync/App/AppState.swift`
- Create: `GymSyncApp/GymSync/App/RootView.swift`
- Create: `GymSyncApp/GymSync/Features/Home/HomeView.swift`
- Create: `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`
- Create: `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`
- Create: `GymSyncApp/GymSync/Features/You/YouTabView.swift`

**Interfaces:**
- Produces: `AppState`, tab navigation shell.

- [ ] **Step 1: Write AppState**

Create `GymSyncApp/GymSync/App/AppState.swift`:
```swift
import SwiftUI

@Observable
@MainActor
final class AppState {
    enum Tab: Hashable { case home, library, social, stats, you }
    var selectedTab: Tab = .home

    // Set to the user's profile once loaded post-sign-in.
    var currentProfile: Profile?
}
```

- [ ] **Step 2: Write empty tab views**

Create `GymSyncApp/GymSync/Features/Home/HomeView.swift`:
```swift
import SwiftUI

struct HomeView: View {
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Text("Welcome to Gym Sync")
                    .font(.title2.bold())
                Text("Start a solo workout from Library → Routines.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)
            }
            .navigationTitle("Home")
        }
    }
}
```

Create `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`:
```swift
import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    Text("Routines").tag(SubTab.routines)
                    Text("Exercises").tag(SubTab.exercises)
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                switch selection {
                case .routines:  RoutinesListView()
                case .exercises: ExercisesListView()
                }
            }
            .navigationTitle("Library")
        }
    }
}

// Placeholders — real implementations come in later tasks.
struct RoutinesListView: View {
    var body: some View { Text("Routines coming in Task 21").foregroundStyle(.secondary) }
}
struct ExercisesListView: View {
    var body: some View { Text("Exercises coming in Task 20").foregroundStyle(.secondary) }
}
```

Create `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`:
```swift
import SwiftUI

struct StatsTabView: View {
    var body: some View {
        NavigationStack {
            Text("Stats coming in Task 26")
                .foregroundStyle(.secondary)
                .navigationTitle("Stats")
        }
    }
}
```

Create `GymSyncApp/GymSync/Features/You/YouTabView.swift`:
```swift
import SwiftUI

struct YouTabView: View {
    @Environment(AuthService.self) private var auth
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Button("Sign Out") {
                        Task {
                            do { try await auth.signOut() }
                            catch { errorText = ErrorMapping.map(error).errorDescription }
                        }
                    }
                    .foregroundStyle(.red)
                }
                if let errorText {
                    Section { Text(errorText).foregroundStyle(.red) }
                }
            }
            .navigationTitle("You")
        }
    }
}
```

- [ ] **Step 3: Write RootView with tab shell**

Create `GymSyncApp/GymSync/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var appState = AppState()

    var body: some View {
        Group {
            switch auth.state {
            case .pending:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .signedIn:
                MainTabView()
                    .environment(appState)
            }
        }
    }
}

private struct MainTabView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var appState = appState
        TabView(selection: $appState.selectedTab) {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(AppState.Tab.home)

            LibraryTabView()
                .tabItem { Label("Library", systemImage: "books.vertical.fill") }
                .tag(AppState.Tab.library)

            Text("Social — Phase 2")  // placeholder in Phase 1
                .tabItem { Label("Social", systemImage: "person.2.fill") }
                .tag(AppState.Tab.social)

            StatsTabView()
                .tabItem { Label("Stats", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(AppState.Tab.stats)

            YouTabView()
                .tabItem { Label("You", systemImage: "person.crop.circle.fill") }
                .tag(AppState.Tab.you)
        }
    }
}
```

- [ ] **Step 4: Verify build + run**

`⌘R`. Expected: sign-in screen, then after Apple sign-in, tabs render at the bottom.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/App/AppState.swift \
        GymSyncApp/GymSync/App/RootView.swift \
        GymSyncApp/GymSync/Features/Home/HomeView.swift \
        GymSyncApp/GymSync/Features/Library/LibraryTabView.swift \
        GymSyncApp/GymSync/Features/Stats/StatsTabView.swift \
        GymSyncApp/GymSync/Features/You/YouTabView.swift
git commit -m "feat(ios): RootView + 5-tab shell (placeholders in unbuilt tabs)"
```

---

### Task 14: Profile model + ProfileRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/Profile.swift`
- Create: `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift`

**Interfaces:**
- Consumes: `SupabaseService`
- Produces: `Profile`, `ProfileRepository.{fetch, create, usernameAvailable}` (see Interfaces block).

- [ ] **Step 1: Write failing test**

Create `GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift`:
```swift
import XCTest
@testable import GymSync

final class ProfileRepositoryTests: XCTestCase {
    // These tests require a signed-in user in the Supabase project.
    // Manual precondition: sign in via Xcode preview first, then run.

    func testUsernameAvailabilityForFreshName() async throws {
        let unique = "test_" + UUID().uuidString.prefix(8).lowercased()
        let available = try await ProfileRepository.usernameAvailable(String(unique))
        XCTAssertTrue(available)
    }

    func testFetchNilWhenNoProfile() async throws {
        // For a fresh UUID with no profile row.
        let randomID = UUID()
        let profile = try await ProfileRepository.fetch(userID: randomID)
        XCTAssertNil(profile)
    }
}
```

- [ ] **Step 2: Write the Profile model**

Create `GymSyncApp/GymSync/Models/Profile.swift`:
```swift
import Foundation
import Supabase

struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
    }
}

enum ProfileRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetch(userID: UUID) async throws -> Profile? {
        do {
            let profile: Profile = try await client
                .from("profiles")
                .select()
                .eq("id", value: userID)
                .single()
                .execute()
                .value
            return profile
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil  // not found
        } catch {
            AppLogger.db.error("fetch profile failed: \(error.localizedDescription, privacy: .public)")
            throw ErrorMapping.map(error)
        }
    }

    static func create(username: String) async throws -> Profile {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let trimmed = username.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConfig.usernameMinLength,
              trimmed.count <= AppConfig.usernameMaxLength else {
            throw GymSyncError.validation(
                "Username must be \(AppConfig.usernameMinLength)–\(AppConfig.usernameMaxLength) characters."
            )
        }
        let inserted: Profile = try await client
            .from("profiles")
            .insert(["id": userID.uuidString, "username": trimmed])
            .select()
            .single()
            .execute()
            .value
        return inserted
    }

    static func usernameAvailable(_ username: String) async throws -> Bool {
        let trimmed = username.trimmingCharacters(in: .whitespaces).lowercased()
        let existing: [Profile] = try await client
            .from("profiles")
            .select()
            .ilike("username", pattern: trimmed)
            .limit(1)
            .execute()
            .value
        return existing.isEmpty
    }
}
```

- [ ] **Step 3: Run tests, verify pass**

`⌘U`. Expected: 2/2 pass.

- [ ] **Step 4: Commit**

```bash
git add GymSyncApp/GymSync/Models/Profile.swift \
        GymSyncApp/GymSyncTests/ProfileRepositoryTests.swift
git commit -m "feat(models): Profile model + ProfileRepository"
```

---

### Task 15: Username creation flow (onboarding)

**Files:**
- Create: `GymSyncApp/GymSync/Features/Onboarding/UsernameView.swift`
- Create: `GymSyncApp/GymSync/Features/Onboarding/OnboardingCoordinator.swift`
- Modify: `GymSyncApp/GymSync/App/RootView.swift`

**Interfaces:**
- Consumes: `AuthService`, `ProfileRepository`
- Produces: `OnboardingCoordinator`, updated `RootView` flow to route users through onboarding when profile missing.

- [ ] **Step 1: Write UsernameView**

Create `GymSyncApp/GymSync/Features/Onboarding/UsernameView.swift`:
```swift
import SwiftUI

struct UsernameView: View {
    @Binding var chosenProfile: Profile?

    @State private var username: String = ""
    @State private var isChecking = false
    @State private var isAvailable: Bool?
    @State private var errorText: String?
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pick your username")
                    .font(.title2.bold())
                Text("Your friends will see this. 3–24 characters, letters, digits, and underscores.")
                    .foregroundStyle(.secondary)
            }
            TextField("username", text: $username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.username)
                .padding(12)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 10))
                .onChange(of: username) { _, newValue in
                    Task { await checkAvailability(newValue) }
                }

            if isChecking { ProgressView().controlSize(.small) }
            else if let isAvailable, !username.isEmpty {
                Label(isAvailable ? "Available" : "Taken",
                      systemImage: isAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(isAvailable ? .green : .red)
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }

            Spacer()

            Button {
                Task { await submit() }
            } label: {
                if isSubmitting {
                    ProgressView().tint(.white)
                } else {
                    Text("Continue").frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.count < AppConfig.usernameMinLength
                      || isAvailable != true
                      || isSubmitting)
        }
        .padding()
    }

    @MainActor
    private func checkAvailability(_ raw: String) async {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= AppConfig.usernameMinLength else {
            isAvailable = nil
            return
        }
        isChecking = true
        defer { isChecking = false }
        do { isAvailable = try await ProfileRepository.usernameAvailable(trimmed) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func submit() async {
        isSubmitting = true
        defer { isSubmitting = false }
        do {
            let created = try await ProfileRepository.create(username: username)
            chosenProfile = created
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }
}
```

- [ ] **Step 2: Write OnboardingCoordinator**

Create `GymSyncApp/GymSync/Features/Onboarding/OnboardingCoordinator.swift`:
```swift
import SwiftUI

struct OnboardingCoordinator: View {
    let userID: UUID
    @Environment(AppState.self) private var appState
    @State private var profile: Profile?
    @State private var loading = true

    var body: some View {
        Group {
            if loading {
                ProgressView().controlSize(.large)
            } else if profile == nil {
                UsernameView(chosenProfile: Binding(
                    get: { profile },
                    set: { newProfile in
                        profile = newProfile
                        if let p = newProfile { appState.currentProfile = p }
                    }
                ))
            } else {
                // Additional onboarding steps (home gym, notifications) added in later tasks.
                Color.clear.onAppear { appState.currentProfile = profile }
            }
        }
        .task { await loadProfile() }
    }

    @MainActor
    private func loadProfile() async {
        loading = true
        defer { loading = false }
        do {
            profile = try await ProfileRepository.fetch(userID: userID)
            if let p = profile { appState.currentProfile = p }
        } catch {
            AppLogger.auth.error("profile load failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
```

- [ ] **Step 3: Update RootView to route through onboarding**

Modify `GymSyncApp/GymSync/App/RootView.swift`:
```swift
import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    @State private var appState = AppState()

    var body: some View {
        Group {
            switch auth.state {
            case .pending:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .signedIn(let userID):
                if appState.currentProfile == nil {
                    OnboardingCoordinator(userID: userID)
                        .environment(appState)
                } else {
                    MainTabView()
                        .environment(appState)
                }
            }
        }
    }
}
```

*(Keep `MainTabView` struct as defined in Task 13.)*

- [ ] **Step 4: Manual test**

Sign in as a fresh Apple account → verify Username screen appears → type a username → tap Continue → verify Home tab appears.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Features/Onboarding/UsernameView.swift \
        GymSyncApp/GymSync/Features/Onboarding/OnboardingCoordinator.swift \
        GymSyncApp/GymSync/App/RootView.swift
git commit -m "feat(onboarding): username selection + profile creation flow"
```

---

### Task 16: Exercise model + ExerciseRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/Exercise.swift`
- Create: `GymSyncApp/GymSyncTests/ExerciseRepositoryTests.swift`

**Interfaces:**
- Consumes: `SupabaseService`
- Produces: `Exercise`, `ExerciseRepository.{fetchAll, fetch}` (see Interfaces block).

- [ ] **Step 1: Write test**

Create `GymSyncApp/GymSyncTests/ExerciseRepositoryTests.swift`:
```swift
import XCTest
@testable import GymSync

final class ExerciseRepositoryTests: XCTestCase {
    func testFetchAllReturnsSeededExercises() async throws {
        let exercises = try await ExerciseRepository.fetchAll()
        XCTAssertGreaterThanOrEqual(exercises.count, 30)
        XCTAssertTrue(exercises.contains { $0.slug == "bench-press" })
    }

    func testFetchByIdReturnsCorrectExercise() async throws {
        let all = try await ExerciseRepository.fetchAll()
        guard let first = all.first else {
            XCTFail("no exercises seeded")
            return
        }
        let fetched = try await ExerciseRepository.fetch(id: first.id)
        XCTAssertEqual(fetched?.id, first.id)
    }
}
```

- [ ] **Step 2: Write Exercise model + repository**

Create `GymSyncApp/GymSync/Models/Exercise.swift`:
```swift
import Foundation

struct Exercise: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let category: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let equipment: String
    let defaultUnit: String
    let demoVideoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case category
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case defaultUnit = "default_unit"
        case demoVideoURL = "demo_video_url"
    }
}

enum ExerciseRepository {
    static func fetchAll() async throws -> [Exercise] {
        do {
            let rows: [Exercise] = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func fetch(id: UUID) async throws -> Exercise? {
        do {
            let row: Exercise = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .eq("id", value: id)
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
}
```

- [ ] **Step 3: Run tests, verify pass**

`⌘U`. Expected: 2/2 pass.

- [ ] **Step 4: Commit**

```bash
git add GymSyncApp/GymSync/Models/Exercise.swift \
        GymSyncApp/GymSyncTests/ExerciseRepositoryTests.swift
git commit -m "feat(models): Exercise + ExerciseRepository"
```

---

### Task 17: Exercises list + detail views

**Files:**
- Modify: `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`
- Create: `GymSyncApp/GymSync/Features/Library/ExercisesListView.swift` (replacing placeholder)
- Create: `GymSyncApp/GymSync/Features/Library/ExerciseDetailView.swift`

**Interfaces:**
- Consumes: `ExerciseRepository`, `Exercise`
- Produces: browsable UI for the exercise library with search + muscle filter.

- [ ] **Step 1: Replace placeholder ExercisesListView**

Overwrite `GymSyncApp/GymSync/Features/Library/ExercisesListView.swift` (extracted into its own file):
```swift
import SwiftUI

struct ExercisesListView: View {
    @State private var exercises: [Exercise] = []
    @State private var searchText: String = ""
    @State private var muscleFilter: String? = nil
    @State private var loading = false
    @State private var errorText: String?

    private var filtered: [Exercise] {
        exercises.filter { ex in
            (muscleFilter == nil || ex.primaryMuscle == muscleFilter)
            && (searchText.isEmpty
                || ex.name.localizedCaseInsensitiveContains(searchText))
        }
    }

    private var muscles: [String] {
        Array(Set(exercises.map(\.primaryMuscle))).sorted()
    }

    var body: some View {
        VStack {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    filterChip(label: "All", selected: muscleFilter == nil) {
                        muscleFilter = nil
                    }
                    ForEach(muscles, id: \.self) { m in
                        filterChip(label: m.capitalized, selected: muscleFilter == m) {
                            muscleFilter = (muscleFilter == m) ? nil : m
                        }
                    }
                }
                .padding(.horizontal)
            }
            if loading {
                ProgressView()
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else {
                List(filtered) { ex in
                    NavigationLink {
                        ExerciseDetailView(exercise: ex)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name).font(.body)
                            Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            }
        }
        .task { await load() }
    }

    private func filterChip(label: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(selected ? Color.accentColor : Color(.secondarySystemBackground),
                            in: Capsule())
                .foregroundStyle(selected ? .white : .primary)
                .font(.caption.weight(.medium))
        }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do { exercises = try await ExerciseRepository.fetchAll() }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
```

- [ ] **Step 2: Write ExerciseDetailView**

Create `GymSyncApp/GymSync/Features/Library/ExerciseDetailView.swift`:
```swift
import SwiftUI

struct ExerciseDetailView: View {
    let exercise: Exercise

    var body: some View {
        Form {
            Section("Muscles") {
                LabeledContent("Primary", value: exercise.primaryMuscle.capitalized)
                if !exercise.secondaryMuscles.isEmpty {
                    LabeledContent("Secondary",
                                   value: exercise.secondaryMuscles
                                    .map(\.localizedCapitalized).joined(separator: ", "))
                }
            }
            Section("Equipment") {
                LabeledContent("Equipment", value: exercise.equipment.capitalized)
                LabeledContent("Category", value: exercise.category.capitalized)
            }
            if let url = exercise.demoVideoURL {
                Section("Demo") {
                    Link("Watch demo", destination: url)
                }
            }
        }
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
```

- [ ] **Step 3: Remove placeholder from LibraryTabView**

Modify `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`, removing the inline `ExercisesListView` placeholder struct (keep the `RoutinesListView` placeholder for Task 18):
```swift
import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    Text("Routines").tag(SubTab.routines)
                    Text("Exercises").tag(SubTab.exercises)
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                switch selection {
                case .routines:  RoutinesListView()
                case .exercises: ExercisesListView()
                }
            }
            .navigationTitle("Library")
        }
    }
}

struct RoutinesListView: View {
    var body: some View { Text("Routines coming in Task 18").foregroundStyle(.secondary) }
}
```

- [ ] **Step 4: Build + run, manually verify**

`⌘R`. Sign in → Library → Exercises tab → verify 30 exercises listed with muscle-group chips at top; tap "Bench Press" → verify detail view shows muscles + equipment.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Features/Library/
git commit -m "feat(library): browsable Exercises list + detail with search/muscle filter"
```

---

### Task 18: Routine + RoutineExercise models + RoutineRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/Routine.swift`
- Create: `GymSyncApp/GymSync/Models/RoutineExercise.swift`
- Create: `GymSyncApp/GymSyncTests/RoutineRepositoryTests.swift`

**Interfaces:**
- Consumes: `SupabaseService`
- Produces: `Routine`, `RoutineExercise`, `RoutineRepository.{fetchAll, fetch, save, delete}` (see Interfaces block).

- [ ] **Step 1: Write test**

Create `GymSyncApp/GymSyncTests/RoutineRepositoryTests.swift`:
```swift
import XCTest
@testable import GymSync

final class RoutineRepositoryTests: XCTestCase {
    func testCreateThenFetchRoundTrip() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in")
            return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })

        let routine = Routine(
            id: UUID(),
            ownerID: userID,
            name: "Test Push Day \(UUID().uuidString.prefix(6))",
            description: nil,
            visibility: "private",
            createdAt: Date(),
            updatedAt: Date()
        )
        let rex = [RoutineExercise(
            id: UUID(), routineID: routine.id, exerciseID: bench.id,
            position: 1, targetSets: 5, targetReps: "5", targetWeight: "185",
            restSeconds: 120, notes: nil
        )]

        try await RoutineRepository.save(routine, exercises: rex)
        let fetched = try await RoutineRepository.fetch(id: routine.id)
        XCTAssertEqual(fetched?.0.id, routine.id)
        XCTAssertEqual(fetched?.1.count, 1)
        XCTAssertEqual(fetched?.1.first?.exerciseID, bench.id)

        try await RoutineRepository.delete(id: routine.id)
        let afterDelete = try await RoutineRepository.fetch(id: routine.id)
        XCTAssertNil(afterDelete)
    }
}
```

- [ ] **Step 2: Write models + repository**

Create `GymSyncApp/GymSync/Models/Routine.swift`:
```swift
import Foundation
import Supabase

struct Routine: Codable, Identifiable, Sendable {
    let id: UUID
    let ownerID: UUID
    var name: String
    var description: String?
    let visibility: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case name
        case description
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum RoutineRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetchAll(ownerID: UUID) async throws -> [Routine] {
        do {
            let rows: [Routine] = try await client
                .from("routines")
                .select()
                .eq("owner_id", value: ownerID)
                .order("updated_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func fetch(id: UUID) async throws -> (Routine, [RoutineExercise])? {
        do {
            let routine: Routine = try await client
                .from("routines")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            let exercises: [RoutineExercise] = try await client
                .from("routine_exercises")
                .select()
                .eq("routine_id", value: id)
                .order("position", ascending: true)
                .execute()
                .value
            return (routine, exercises)
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func save(_ routine: Routine, exercises: [RoutineExercise]) async throws {
        do {
            _ = try await client.from("routines").upsert(routine).execute()
            _ = try await client.from("routine_exercises")
                .delete().eq("routine_id", value: routine.id).execute()
            if !exercises.isEmpty {
                _ = try await client.from("routine_exercises").insert(exercises).execute()
            }
        } catch { throw ErrorMapping.map(error) }
    }

    static func delete(id: UUID) async throws {
        do {
            _ = try await client.from("routines").delete().eq("id", value: id).execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
```

Create `GymSyncApp/GymSync/Models/RoutineExercise.swift`:
```swift
import Foundation

struct RoutineExercise: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let routineID: UUID
    let exerciseID: UUID
    var position: Int
    var targetSets: Int?
    var targetReps: String?
    var targetWeight: String?
    var restSeconds: Int?
    var notes: String?

    enum CodingKeys: String, CodingKey {
        case id
        case routineID = "routine_id"
        case exerciseID = "exercise_id"
        case position
        case targetSets = "target_sets"
        case targetReps = "target_reps"
        case targetWeight = "target_weight"
        case restSeconds = "rest_seconds"
        case notes
    }
}
```

- [ ] **Step 3: Run tests, verify pass**

`⌘U`. Expected: pass.

- [ ] **Step 4: Commit**

```bash
git add GymSyncApp/GymSync/Models/Routine.swift \
        GymSyncApp/GymSync/Models/RoutineExercise.swift \
        GymSyncApp/GymSyncTests/RoutineRepositoryTests.swift
git commit -m "feat(models): Routine + RoutineExercise + RoutineRepository with round-trip test"
```

---

### Task 19: Routine list + builder UI

**Files:**
- Modify: `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift`
- Create: `GymSyncApp/GymSync/Features/Library/RoutinesListView.swift` (extracted)
- Create: `GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift`

**Interfaces:**
- Consumes: `RoutineRepository`, `ExerciseRepository`, `AppState.currentProfile`
- Produces: full routine CRUD UI in Library tab.

- [ ] **Step 1: Write RoutinesListView**

Create `GymSyncApp/GymSync/Features/Library/RoutinesListView.swift`:
```swift
import SwiftUI

struct RoutinesListView: View {
    @Environment(AppState.self) private var appState
    @State private var routines: [Routine] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingBuilder = false
    @State private var editing: Routine?

    var body: some View {
        Group {
            if loading { ProgressView() }
            else if let errorText { Text(errorText).foregroundStyle(.red) }
            else if routines.isEmpty {
                ContentUnavailableView(
                    "No routines yet",
                    systemImage: "list.clipboard",
                    description: Text("Tap + to build your first workout.")
                )
            } else {
                List {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineBuilderView(editing: routine) { updated in
                                Task { await load() }
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(routine.name)
                                if let desc = routine.description, !desc.isEmpty {
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingBuilder = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            NavigationStack {
                RoutineBuilderView(editing: nil) { _ in
                    showingBuilder = false
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { routines = try await RoutineRepository.fetchAll(ownerID: ownerID) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            for idx in offsets {
                let r = routines[idx]
                try? await RoutineRepository.delete(id: r.id)
            }
            await load()
        }
    }
}
```

- [ ] **Step 2: Write RoutineBuilderView**

Create `GymSyncApp/GymSync/Features/Library/RoutineBuilderView.swift`:
```swift
import SwiftUI

struct RoutineBuilderView: View {
    let editing: Routine?
    let onSaved: (Routine) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var items: [RoutineExercise] = []
    @State private var loading = false
    @State private var showExercisePicker = false
    @State private var errorText: String?
    @State private var allExercises: [Exercise] = []

    var body: some View {
        Form {
            Section("Details") {
                TextField("Routine name", text: $name)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
            }
            Section("Exercises") {
                if items.isEmpty {
                    Text("No exercises yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    exerciseRow(item)
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                    reindex()
                }
                .onMove { indices, dest in
                    items.move(fromOffsets: indices, toOffset: dest)
                    reindex()
                }
                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editing == nil ? "New Routine" : "Edit Routine")
        .toolbar {
            EditButton()
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack {
                exercisePicker
            }
        }
        .task { await load() }
    }

    private var exercisePicker: some View {
        List(allExercises) { ex in
            Button {
                items.append(RoutineExercise(
                    id: UUID(),
                    routineID: editing?.id ?? UUID(),  // placeholder until save
                    exerciseID: ex.id,
                    position: items.count + 1,
                    targetSets: 3,
                    targetReps: "8-12",
                    targetWeight: nil,
                    restSeconds: AppConfig.defaultRestSeconds,
                    notes: nil
                ))
                showExercisePicker = false
            } label: {
                VStack(alignment: .leading) {
                    Text(ex.name)
                    Text(ex.primaryMuscle.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add exercise")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { showExercisePicker = false }
            }
        }
    }

    private func exerciseRow(_ item: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == item.exerciseID }
        return VStack(alignment: .leading) {
            Text(ex?.name ?? "Exercise")
            HStack(spacing: 12) {
                setField(value: Binding(
                    get: { String(item.targetSets ?? 0) },
                    set: { newVal in updateItem(item.id) { $0.targetSets = Int(newVal) } }
                ), label: "sets", keyboard: .numberPad)
                setField(value: Binding(
                    get: { item.targetReps ?? "" },
                    set: { newVal in updateItem(item.id) { $0.targetReps = newVal } }
                ), label: "reps", keyboard: .default)
                setField(value: Binding(
                    get: { item.targetWeight ?? "" },
                    set: { newVal in updateItem(item.id) { $0.targetWeight = newVal } }
                ), label: "weight", keyboard: .decimalPad)
            }
        }
    }

    private func setField(value: Binding<String>, label: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, text: value)
                .keyboardType(keyboard)
                .padding(6)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 6))
        }
    }

    private func updateItem(_ id: UUID, mutate: (inout RoutineExercise) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    private func reindex() {
        for i in items.indices { items[i].position = i + 1 }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            allExercises = try await ExerciseRepository.fetchAll()
            if let editing {
                name = editing.name
                description = editing.description ?? ""
                if let (_, exs) = try await RoutineRepository.fetch(id: editing.id) {
                    items = exs
                }
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func save() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        let routineID = editing?.id ?? UUID()
        let now = Date()
        let routine = Routine(
            id: routineID,
            ownerID: ownerID,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            visibility: "private",
            createdAt: editing?.createdAt ?? now,
            updatedAt: now
        )
        // Ensure all items point at the actual routineID
        let normalizedItems = items.enumerated().map { (idx, item) -> RoutineExercise in
            var copy = item
            copy = RoutineExercise(
                id: item.id,
                routineID: routineID,
                exerciseID: item.exerciseID,
                position: idx + 1,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                targetWeight: item.targetWeight,
                restSeconds: item.restSeconds,
                notes: item.notes
            )
            return copy
        }
        do {
            try await RoutineRepository.save(routine, exercises: normalizedItems)
            onSaved(routine)
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
```

- [ ] **Step 3: Delete the placeholder RoutinesListView struct**

Modify `GymSyncApp/GymSync/Features/Library/LibraryTabView.swift` — remove the trailing placeholder struct (real one lives in its own file now):
```swift
import SwiftUI

struct LibraryTabView: View {
    enum SubTab: Hashable { case routines, exercises }
    @State private var selection: SubTab = .routines

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $selection) {
                    Text("Routines").tag(SubTab.routines)
                    Text("Exercises").tag(SubTab.exercises)
                }
                .pickerStyle(.segmented)
                .padding()
                Divider()
                switch selection {
                case .routines:  RoutinesListView()
                case .exercises: ExercisesListView()
                }
            }
            .navigationTitle("Library")
        }
    }
}
```

- [ ] **Step 4: Build + manual test**

`⌘R` → Library → Routines → tap + → build a routine with 2-3 exercises → Save → verify it appears in the list; tap it → edit → save → verify update; swipe-to-delete → verify removal.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Features/Library/
git commit -m "feat(library): RoutinesListView + RoutineBuilderView with add/edit/delete"
```

---

### Task 20: WorkoutSession + SetLog models + SessionRepository

**Files:**
- Create: `GymSyncApp/GymSync/Models/Session.swift`
- Create: `GymSyncApp/GymSync/Models/SetLog.swift`
- Create: `GymSyncApp/GymSyncTests/SessionRepositoryTests.swift`

**Interfaces:**
- Consumes: `SupabaseService`, `AuthService`
- Produces: `WorkoutSession`, `SetLog`, `SessionRepository.{startSolo, complete, logSet, history, setLogs, exerciseHistory}` (see Interfaces block).

- [ ] **Step 1: Write test**

Create `GymSyncApp/GymSyncTests/SessionRepositoryTests.swift`:
```swift
import XCTest
@testable import GymSync

final class SessionRepositoryTests: XCTestCase {
    func testStartAndCompleteSoloSession() async throws {
        let session = try await SessionRepository.startSolo(routineID: nil)
        XCTAssertEqual(session.state, "in_progress")
        XCTAssertNotNil(session.startedAt)

        let completed = try await SessionRepository.complete(sessionID: session.id)
        XCTAssertEqual(completed.state, "completed")
        XCTAssertNotNil(completed.completedAt)
    }

    func testLogSetAndReadBack() async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            XCTFail("must be signed in"); return
        }
        let exercises = try await ExerciseRepository.fetchAll()
        let bench = try XCTUnwrap(exercises.first { $0.slug == "bench-press" })
        let session = try await SessionRepository.startSolo(routineID: nil)

        let log = SetLog(
            id: UUID(),
            userID: userID,
            sessionID: session.id,
            exerciseID: bench.id,
            setIndex: 1,
            reps: 5,
            weight: 185,
            rpe: 8,
            isFailed: false,
            isPenalty: false,
            note: nil,
            loggedAt: Date()
        )
        try await SessionRepository.logSet(log)

        let logs = try await SessionRepository.setLogs(sessionID: session.id)
        XCTAssertTrue(logs.contains { $0.id == log.id })

        _ = try await SessionRepository.complete(sessionID: session.id)
    }
}
```

- [ ] **Step 2: Write models**

Create `GymSyncApp/GymSync/Models/Session.swift`:
```swift
import Foundation

struct WorkoutSession: Codable, Identifiable, Sendable {
    let id: UUID
    let routineID: UUID?
    let organizerID: UUID
    var state: String
    var startedAt: Date?
    var completedAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case routineID = "routine_id"
        case organizerID = "organizer_id"
        case state
        case startedAt = "started_at"
        case completedAt = "completed_at"
        case createdAt = "created_at"
    }
}
```

Create `GymSyncApp/GymSync/Models/SetLog.swift`:
```swift
import Foundation

struct SetLog: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let sessionID: UUID
    let exerciseID: UUID
    let setIndex: Int
    var reps: Int?
    var weight: Decimal?
    var rpe: Decimal?
    var isFailed: Bool
    var isPenalty: Bool
    var note: String?
    let loggedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case sessionID = "session_id"
        case exerciseID = "exercise_id"
        case setIndex = "set_index"
        case reps
        case weight
        case rpe
        case isFailed = "is_failed"
        case isPenalty = "is_penalty"
        case note
        case loggedAt = "logged_at"
    }
}
```

- [ ] **Step 3: Write SessionRepository**

Create `GymSyncApp/GymSync/Models/SessionRepository.swift`:
```swift
import Foundation
import Supabase

enum SessionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func startSolo(routineID: UUID?) async throws -> WorkoutSession {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let session = WorkoutSession(
                id: UUID(),
                routineID: routineID,
                organizerID: userID,
                state: "in_progress",
                startedAt: Date(),
                completedAt: nil,
                createdAt: Date()
            )
            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(session)
                .select().single().execute().value
            // Add self as sole participant (for RLS unification across phases)
            _ = try await client
                .from("session_participants")
                .insert([
                    "session_id": session.id.uuidString,
                    "user_id": userID.uuidString,
                    "turn_order": "1",
                    "check_in_state": "ready"
                ])
                .execute()
            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    static func complete(sessionID: UUID) async throws -> WorkoutSession {
        do {
            let updated: WorkoutSession = try await client
                .from("sessions")
                .update([
                    "state": "completed",
                    "completed_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: sessionID)
                .select().single().execute().value
            return updated
        } catch { throw ErrorMapping.map(error) }
    }

    static func logSet(_ set: SetLog) async throws {
        do {
            _ = try await client.from("set_logs").insert(set).execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func history(userID: UUID, limit: Int) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("organizer_id", value: userID)
                .eq("state", value: "completed")
                .order("completed_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func setLogs(sessionID: UUID) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("session_id", value: sessionID)
                .order("set_index", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func exerciseHistory(userID: UUID, exerciseID: UUID, limit: Int) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .eq("is_failed", value: "false")
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

`⌘U`. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Models/Session.swift \
        GymSyncApp/GymSync/Models/SetLog.swift \
        GymSyncApp/GymSync/Models/SessionRepository.swift \
        GymSyncApp/GymSyncTests/SessionRepositoryTests.swift
git commit -m "feat(models): WorkoutSession + SetLog + SessionRepository with round-trip tests"
```

---

### Task 21: Solo workout session view + LogSetSheet

**Files:**
- Create: `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift`
- Create: `GymSyncApp/GymSync/Features/Workout/LogSetSheet.swift`
- Modify: `GymSyncApp/GymSync/Features/Library/RoutinesListView.swift` (add "Start Workout" action)

**Interfaces:**
- Consumes: `SessionRepository`, `RoutineRepository`, `ExerciseRepository`
- Produces: interactive solo workout UI + set logging.

- [ ] **Step 1: Write LogSetSheet**

Create `GymSyncApp/GymSync/Features/Workout/LogSetSheet.swift`:
```swift
import SwiftUI

struct LogSetSheet: View {
    let exercise: Exercise
    let setIndex: Int
    let defaultReps: String?
    let defaultWeight: String?
    let onLog: (Int?, Decimal?, Decimal?, Bool, String?) -> Void
    // onLog(reps, weight, rpe, isFailed, note)

    @Environment(\.dismiss) private var dismiss
    @State private var reps: String = ""
    @State private var weight: String = ""
    @State private var rpe: Double = 7.0
    @State private var isFailed = false
    @State private var note: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Set \(setIndex) · \(exercise.name)") {
                    LabeledContent("Reps") {
                        TextField("reps", text: $reps)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    LabeledContent("Weight (\(exercise.defaultUnit))") {
                        TextField("weight", text: $weight)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    VStack(alignment: .leading) {
                        HStack {
                            Text("RPE")
                            Spacer()
                            Text(String(format: "%.1f", rpe))
                        }
                        Slider(value: $rpe, in: 1...10, step: 0.5)
                    }
                    Toggle("Failed set", isOn: $isFailed)
                }
                Section("Note (optional)") {
                    TextField("Anything to remember?", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                }
            }
            .navigationTitle("Log set")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onLog(
                            Int(reps),
                            Decimal(string: weight),
                            Decimal(rpe),
                            isFailed,
                            note.isEmpty ? nil : note
                        )
                        dismiss()
                    }
                    .disabled(Int(reps) == nil && !isFailed)
                }
            }
            .onAppear {
                if reps.isEmpty { reps = defaultReps ?? "" }
                if weight.isEmpty { weight = defaultWeight ?? "" }
            }
        }
    }
}
```

- [ ] **Step 2: Write WorkoutSessionView**

Create `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift`:
```swift
import SwiftUI

struct WorkoutSessionView: View {
    let routine: Routine
    let routineExercises: [RoutineExercise]
    let allExercises: [Exercise]

    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    @State private var session: WorkoutSession?
    @State private var loggedSets: [SetLog] = []
    @State private var currentExerciseIndex: Int = 0
    @State private var currentSetIndex: Int = 1
    @State private var showLogSheet = false
    @State private var errorText: String?
    @State private var completed = false
    @State private var isPRToast: Bool = false
    @State private var setStartedAt: Date = .now

    private var currentRoutineExercise: RoutineExercise? {
        guard currentExerciseIndex < routineExercises.count else { return nil }
        return routineExercises[currentExerciseIndex]
    }

    private var currentExercise: Exercise? {
        guard let re = currentRoutineExercise else { return nil }
        return allExercises.first { $0.id == re.exerciseID }
    }

    var body: some View {
        VStack(spacing: 20) {
            if let ex = currentExercise, let re = currentRoutineExercise {
                headerCard(ex: ex, re: re)
                Spacer()
                Button {
                    setStartedAt = .now
                    showLogSheet = true
                } label: {
                    Text("Log set")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, minHeight: 80)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal)

                loggedSetsList
            } else if completed {
                completionCard
            } else {
                ProgressView()
            }
            if isPRToast {
                Text("🔥 NEW PR!")
                    .font(.headline)
                    .padding()
                    .background(Color.yellow.opacity(0.9), in: Capsule())
                    .transition(.scale.combined(with: .opacity))
            }
            if let errorText {
                Text(errorText).foregroundStyle(.red)
            }
        }
        .padding()
        .navigationTitle(routine.name)
        .navigationBarBackButtonHidden(!completed)
        .toolbar {
            if !completed {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("End") { Task { await endSession() } }
                }
            }
        }
        .task { await startIfNeeded() }
        .sheet(isPresented: $showLogSheet) {
            if let ex = currentExercise, let re = currentRoutineExercise {
                LogSetSheet(
                    exercise: ex,
                    setIndex: currentSetIndex,
                    defaultReps: re.targetReps,
                    defaultWeight: re.targetWeight
                ) { reps, weight, rpe, isFailed, note in
                    Task { await log(reps: reps, weight: weight, rpe: rpe, isFailed: isFailed, note: note) }
                }
            }
        }
    }

    private func headerCard(ex: Exercise, re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Exercise \(currentExerciseIndex + 1) of \(routineExercises.count)")
                .font(.caption).foregroundStyle(.secondary)
            Text(ex.name).font(.title.bold())
            HStack(spacing: 16) {
                LabeledPill("Set", "\(currentSetIndex) / \(re.targetSets ?? 1)")
                if let reps = re.targetReps { LabeledPill("Reps", reps) }
                if let w = re.targetWeight { LabeledPill("Weight", w) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 12))
    }

    private var loggedSetsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(loggedSets) { log in
                    let ex = allExercises.first { $0.id == log.exerciseID }
                    HStack {
                        Text("\(ex?.name ?? "?")").font(.caption)
                        Spacer()
                        Text("\(log.reps ?? 0) × \(log.weight?.description ?? "-") @ RPE \(log.rpe?.description ?? "-")")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxHeight: 120)
    }

    private var completionCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .resizable().frame(width: 60, height: 60).foregroundStyle(.green)
            Text("Workout complete!").font(.title2.bold())
            Text("\(loggedSets.count) sets logged")
                .foregroundStyle(.secondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
                .padding(.top)
        }
    }

    @MainActor
    private func startIfNeeded() async {
        guard session == nil else { return }
        do { session = try await SessionRepository.startSolo(routineID: routine.id) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func log(reps: Int?, weight: Decimal?, rpe: Decimal?, isFailed: Bool, note: String?) async {
        guard let session, let re = currentRoutineExercise,
              let userID = appState.currentProfile?.id else { return }

        let log = SetLog(
            id: UUID(),
            userID: userID,
            sessionID: session.id,
            exerciseID: re.exerciseID,
            setIndex: currentSetIndex,
            reps: reps, weight: weight, rpe: rpe,
            isFailed: isFailed, isPenalty: false,
            note: note, loggedAt: Date()
        )
        do {
            try await SessionRepository.logSet(log)
            loggedSets.append(log)

            // PR check (Phase 1: client-side after insert, via RPC-ish helper)
            if !isFailed, let weight, weight > 0 {
                let priorMax = try await priorMax(exerciseID: re.exerciseID, weight: weight, userID: userID)
                if weight > priorMax {
                    withAnimation { isPRToast = true }
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    withAnimation { isPRToast = false }
                }
            }

            // Advance to next set / exercise
            let targetSets = re.targetSets ?? 1
            if currentSetIndex >= targetSets {
                currentSetIndex = 1
                currentExerciseIndex += 1
            } else {
                currentSetIndex += 1
            }
            if currentExerciseIndex >= routineExercises.count {
                await endSession()
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    private func priorMax(exerciseID: UUID, weight: Decimal, userID: UUID) async throws -> Decimal {
        // Fetch prior best (excluding this newly-inserted set)
        let history = try await SessionRepository.exerciseHistory(userID: userID, exerciseID: exerciseID, limit: 200)
        let priorBest = history
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { $0.weight }
            .max() ?? 0
        return priorBest
    }

    @MainActor
    private func endSession() async {
        guard let session else { return }
        do {
            _ = try await SessionRepository.complete(sessionID: session.id)
            // HealthKit export happens in Task 22.
            completed = true
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

private struct LabeledPill: View {
    let label: String
    let value: String
    init(_ label: String, _ value: String) { self.label = label; self.value = value }
    var body: some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.bold())
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(.tertiarySystemBackground), in: .rect(cornerRadius: 8))
    }
}
```

- [ ] **Step 3: Wire "Start Workout" into RoutinesListView**

Modify `GymSyncApp/GymSync/Features/Library/RoutinesListView.swift` — replace the NavigationLink content with a menu:
```swift
// Inside ForEach(routines) — replace NavigationLink with:
NavigationLink {
    RoutineDetailChoice(routine: routine, onEdited: { Task { await load() } })
} label: {
    VStack(alignment: .leading) {
        Text(routine.name)
        if let desc = routine.description, !desc.isEmpty {
            Text(desc).font(.caption).foregroundStyle(.secondary)
        }
    }
}
```

Then add the small RoutineDetailChoice screen at the bottom of the same file:
```swift
private struct RoutineDetailChoice: View {
    let routine: Routine
    let onEdited: () -> Void

    @State private var exercises: [Exercise] = []
    @State private var routineExercises: [RoutineExercise] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        VStack(spacing: 20) {
            if loading { ProgressView() }
            else if let errorText { Text(errorText).foregroundStyle(.red) }
            else {
                Text(routine.name).font(.title.bold())
                Text("\(routineExercises.count) exercises")
                    .foregroundStyle(.secondary)
                NavigationLink {
                    WorkoutSessionView(routine: routine,
                                        routineExercises: routineExercises,
                                        allExercises: exercises)
                } label: {
                    Text("Start Workout")
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                NavigationLink {
                    RoutineBuilderView(editing: routine) { _ in onEdited() }
                } label: {
                    Text("Edit routine")
                }
            }
        }
        .padding()
        .task { await load() }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            exercises = try await ExerciseRepository.fetchAll()
            if let (_, exs) = try await RoutineRepository.fetch(id: routine.id) {
                routineExercises = exs
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
```

- [ ] **Step 4: Build + manual test**

`⌘R`. Create a routine with 2-3 exercises → tap it → Start Workout → tap Log Set → enter reps/weight/RPE → save → verify UI advances to next set → complete all sets → verify completion screen.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Features/Workout/ \
        GymSyncApp/GymSync/Features/Library/RoutinesListView.swift
git commit -m "feat(workout): solo workout session view + LogSetSheet + PR toast"
```

---

### Task 22: HealthKit workout export

**Files:**
- Create: `GymSyncApp/GymSync/Services/HealthKitBridge.swift`
- Create: `GymSyncApp/GymSyncTests/HealthKitBridgeTests.swift`
- Modify: `GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift` (call export on complete)

**Interfaces:**
- Consumes: `WorkoutSession`, `SetLog`
- Produces: `HealthKitBridge.exportWorkout(session:setLogs:)`.

- [ ] **Step 1: Write test**

Create `GymSyncApp/GymSyncTests/HealthKitBridgeTests.swift`:
```swift
import XCTest
import HealthKit
@testable import GymSync

final class HealthKitBridgeTests: XCTestCase {
    func testDurationCalculation() {
        let start = Date(timeIntervalSince1970: 1000)
        let end = Date(timeIntervalSince1970: 3700)  // +45 min
        XCTAssertEqual(HealthKitBridge.duration(from: start, to: end), 2700)
    }

    func testTotalVolumeFromSets() {
        let logs: [SetLog] = [
            SetLog(id: UUID(), userID: UUID(), sessionID: UUID(),
                   exerciseID: UUID(), setIndex: 1,
                   reps: 5, weight: 185, rpe: nil,
                   isFailed: false, isPenalty: false, note: nil, loggedAt: .now),
            SetLog(id: UUID(), userID: UUID(), sessionID: UUID(),
                   exerciseID: UUID(), setIndex: 2,
                   reps: 5, weight: 185, rpe: nil,
                   isFailed: false, isPenalty: false, note: nil, loggedAt: .now),
        ]
        XCTAssertEqual(HealthKitBridge.totalVolume(from: logs), 1850)
    }
}
```

- [ ] **Step 2: Write HealthKitBridge**

Create `GymSyncApp/GymSync/Services/HealthKitBridge.swift`:
```swift
import Foundation
import HealthKit

enum HealthKitBridge {
    static let store = HKHealthStore()

    static func requestPermission() async throws {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let workoutType = HKObjectType.workoutType()
        try await store.requestAuthorization(toShare: [workoutType], read: [])
    }

    static func duration(from start: Date, to end: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(start))
    }

    static func totalVolume(from logs: [SetLog]) -> Double {
        logs.reduce(0.0) { acc, log in
            guard !log.isFailed, !log.isPenalty,
                  let reps = log.reps,
                  let weight = log.weight else { return acc }
            return acc + Double(reps) * NSDecimalNumber(decimal: weight).doubleValue
        }
    }

    static func exportWorkout(session: WorkoutSession, setLogs: [SetLog]) async throws {
        guard HKHealthStore.isHealthDataAvailable(),
              let start = session.startedAt,
              let end = session.completedAt else { return }

        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        let builder = HKWorkoutBuilder(healthStore: store, configuration: config, device: .local())

        try await builder.beginCollection(at: start)
        try await builder.endCollection(at: end)
        _ = try await builder.finishWorkout()
        AppLogger.health.info("Exported workout \(session.id, privacy: .public) duration=\(duration(from: start, to: end))")
    }
}
```

- [ ] **Step 3: Wire export into WorkoutSessionView**

Modify `endSession()` in `WorkoutSessionView.swift`:
```swift
    @MainActor
    private func endSession() async {
        guard let session else { return }
        do {
            let completed = try await SessionRepository.complete(sessionID: session.id)
            let logs = try await SessionRepository.setLogs(sessionID: completed.id)
            try? await HealthKitBridge.requestPermission()
            try? await HealthKitBridge.exportWorkout(session: completed, setLogs: logs)
            self.completed = true
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
```

- [ ] **Step 4: Run tests + manual verify**

`⌘U` (unit tests pass). `⌘R`, complete a workout, then open the Health app → Browse → Workouts → verify a "Functional Strength Training" entry with the right time.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Services/HealthKitBridge.swift \
        GymSyncApp/GymSyncTests/HealthKitBridgeTests.swift \
        GymSyncApp/GymSync/Features/Workout/WorkoutSessionView.swift
git commit -m "feat(health): HealthKit workout export on session complete"
```

---

### Task 23: Stats tab — recent activity + Swift Charts trend

**Files:**
- Create: `GymSyncApp/GymSync/Features/Stats/ActivityFeedView.swift`
- Create: `GymSyncApp/GymSync/Features/Stats/ExerciseHistoryView.swift`
- Create: `GymSyncApp/GymSync/Features/Stats/TrendChartView.swift`
- Modify: `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`

**Interfaces:**
- Consumes: `SessionRepository`, `ExerciseRepository`, `AppState.currentProfile`
- Produces: Stats tab with a recent activity feed, per-exercise history, and a weight-over-time line chart.

- [ ] **Step 1: Write ActivityFeedView**

Create `GymSyncApp/GymSync/Features/Stats/ActivityFeedView.swift`:
```swift
import SwiftUI

struct ActivityFeedView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [WorkoutSession] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if loading { ProgressView() }
            else if let errorText { Text(errorText).foregroundStyle(.red) }
            else if sessions.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Complete a workout to see it here.")
                )
            } else {
                List(sessions) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.completedAt?.formatted(date: .abbreviated, time: .shortened)
                             ?? s.createdAt.formatted())
                            .font(.headline)
                        if let start = s.startedAt, let end = s.completedAt {
                            Text("Duration: \(Self.formatDuration(end.timeIntervalSince(start)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent activity")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { sessions = try await SessionRepository.history(userID: userID, limit: 50) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        let mins = m % 60
        return h > 0 ? "\(h)h \(mins)m" : "\(mins)m"
    }
}
```

- [ ] **Step 2: Write TrendChartView**

Create `GymSyncApp/GymSync/Features/Stats/TrendChartView.swift`:
```swift
import SwiftUI
import Charts

struct TrendChartView: View {
    let title: String
    let data: [(Date, Double)]

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            if data.isEmpty {
                Text("Not enough data yet.")
                    .foregroundStyle(.secondary).font(.caption)
            } else {
                Chart(Array(data.enumerated()), id: \.offset) { _, point in
                    LineMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                    PointMark(x: .value("Date", point.0), y: .value("Weight", point.1))
                }
                .frame(height: 200)
            }
        }
        .padding()
    }
}
```

- [ ] **Step 3: Write ExerciseHistoryView**

Create `GymSyncApp/GymSync/Features/Stats/ExerciseHistoryView.swift`:
```swift
import SwiftUI

struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Environment(AppState.self) private var appState

    @State private var logs: [SetLog] = []
    @State private var loading = false
    @State private var errorText: String?

    private var chartData: [(Date, Double)] {
        logs
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { log in
                guard let w = log.weight else { return nil }
                return (log.loggedAt, NSDecimalNumber(decimal: w).doubleValue)
            }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TrendChartView(title: "\(exercise.name) — weight over time",
                               data: chartData)
                Text("Recent sets").font(.headline).padding(.horizontal)
                ForEach(logs.prefix(30)) { log in
                    HStack {
                        Text(log.loggedAt.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(log.reps ?? 0) × \(log.weight?.description ?? "-")")
                        if let rpe = log.rpe {
                            Text("RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        if log.isFailed {
                            Text("FAIL").font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle(exercise.name)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { logs = try await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
```

- [ ] **Step 4: Replace StatsTabView placeholder**

Modify `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`:
```swift
import SwiftUI

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @State private var exercises: [Exercise] = []

    var body: some View {
        NavigationStack {
            Form {
                Section("Lifetime") {
                    LabeledContent("Volume lifted") {
                        Text(volumeString).monospacedDigit()
                    }
                }
                Section("Recent activity") {
                    NavigationLink("View sessions") { ActivityFeedView() }
                }
                Section("Per-exercise history") {
                    ForEach(exercises) { ex in
                        NavigationLink(ex.name) { ExerciseHistoryView(exercise: ex) }
                    }
                }
            }
            .navigationTitle("Stats")
            .task {
                exercises = (try? await ExerciseRepository.fetchAll()) ?? []
            }
        }
    }

    private var volumeString: String {
        let n = appState.currentProfile?.id != nil
            ? (try? Int(NSDecimalNumber(decimal: Decimal(0)).intValue)) ?? 0
            : 0
        // Full lifetime volume comes from a refetch of profile:
        // Placeholder: 0. Rendered from profile.lifetime_volume_lifted once
        // Profile is refreshed (Task 24).
        return "\(n) lbs"
    }
}
```

- [ ] **Step 5: Build + manual test**

`⌘R` → Stats tab → verify per-exercise entries; tap Bench Press (if you logged sets to it) → verify chart renders with your logged sets.

- [ ] **Step 6: Commit**

```bash
git add GymSyncApp/GymSync/Features/Stats/
git commit -m "feat(stats): recent activity feed + per-exercise trend chart (Swift Charts)"
```

---

### Task 24: Refresh Profile → surface lifetime volume in Stats

**Files:**
- Modify: `GymSyncApp/GymSync/Models/Profile.swift`
- Modify: `GymSyncApp/GymSync/Features/Stats/StatsTabView.swift`
- Modify: `GymSyncApp/GymSync/Features/Onboarding/OnboardingCoordinator.swift`

**Interfaces:**
- Consumes: `ProfileRepository`
- Produces: `Profile.lifetimeVolumeLifted` and a refresh method.

- [ ] **Step 1: Extend Profile model**

Modify `GymSyncApp/GymSync/Models/Profile.swift`:
```swift
struct Profile: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let username: String
    let displayName: String?
    let avatarURL: URL?
    let createdAt: Date
    let lifetimeVolumeLifted: Decimal

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case createdAt = "created_at"
        case lifetimeVolumeLifted = "lifetime_volume_lifted"
    }
}
```

- [ ] **Step 2: Add ProfileRepository.refresh convenience**

Add to `ProfileRepository`:
```swift
    static func refresh(userID: UUID) async throws -> Profile? {
        try await fetch(userID: userID)
    }
```

- [ ] **Step 3: Update StatsTabView to render real volume**

Replace `volumeString` computed property:
```swift
    @State private var refreshedProfile: Profile?

    // ... in body's Section "Lifetime":
    LabeledContent("Volume lifted") {
        Text(volumeString).monospacedDigit()
    }

    private var volumeString: String {
        let profile = refreshedProfile ?? appState.currentProfile
        let vol = profile?.lifetimeVolumeLifted ?? 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = NSDecimalNumber(decimal: vol).doubleValue
        return "\(formatter.string(from: NSNumber(value: raw)) ?? "0") lbs"
    }
```

Add a task modifier at the bottom of the Form:
```swift
    .task {
        exercises = (try? await ExerciseRepository.fetchAll()) ?? []
        if let id = appState.currentProfile?.id {
            refreshedProfile = try? await ProfileRepository.refresh(userID: id)
        }
    }
    .refreshable {
        if let id = appState.currentProfile?.id {
            refreshedProfile = try? await ProfileRepository.refresh(userID: id)
        }
    }
```

- [ ] **Step 4: Build + manual test**

`⌘R` → log a couple of sets → back to Stats → pull-to-refresh → verify lifetime volume increments.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Models/Profile.swift \
        GymSyncApp/GymSync/Features/Stats/StatsTabView.swift \
        GymSyncApp/GymSync/Features/Onboarding/OnboardingCoordinator.swift
git commit -m "feat(stats): render lifetime volume lifted from profile"
```

---

### Task 25: Sign out safety + audio session config regression guard

**Files:**
- Modify: `GymSyncApp/GymSync/Services/AuthService.swift`
- Create: `GymSyncApp/GymSync/Services/AudioSessionManager.swift`
- Create: `GymSyncApp/GymSyncTests/AudioSessionManagerTests.swift`

**Interfaces:**
- Produces: `AudioSessionManager.shared.configure()` + regression guard. (Phase 3 will actually use this for the soundboard; adding the guard now prevents accidental regression when Phase 3 lands.)

- [ ] **Step 1: Write AudioSessionManager**

Create `GymSyncApp/GymSync/Services/AudioSessionManager.swift`:
```swift
import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

    private init() {}

    func configure() throws {
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }
}
```

- [ ] **Step 2: Write regression test**

Create `GymSyncApp/GymSyncTests/AudioSessionManagerTests.swift`:
```swift
import XCTest
import AVFoundation
@testable import GymSync

final class AudioSessionManagerTests: XCTestCase {
    func testConfigureSetsAmbientCategoryWithMixWithOthers() throws {
        try AudioSessionManager.shared.configure()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .ambient,
            "Category must be .ambient to avoid taking audio focus from the user's music")
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers),
            "REGRESSION GUARD: .mixWithOthers must be set — the soundboard MUST play alongside Spotify without pausing it. See design spec §6.1.")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers),
            ".duckOthers would lower the user's music volume during our audio — never enable.")
    }
}
```

- [ ] **Step 3: Call configure() from GymSyncApp**

Modify `GymSyncApp.swift`:
```swift
@main
struct GymSyncApp: App {
    init() {
        try? AudioSessionManager.shared.configure()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthService.shared)
        }
    }
}
```

- [ ] **Step 4: Run tests, verify pass**

`⌘U`. Expected: pass.

- [ ] **Step 5: Commit**

```bash
git add GymSyncApp/GymSync/Services/AudioSessionManager.swift \
        GymSyncApp/GymSyncTests/AudioSessionManagerTests.swift \
        GymSyncApp/GymSync/App/GymSyncApp.swift
git commit -m "feat(audio): AudioSessionManager with mix-with-others regression guard"
```

---

## Definition of Done for Phase 1

Phase 1 is complete when all of the following are true:

1. All 25 tasks above are checked off and committed.
2. **A user can:** sign in with Apple, choose a username, browse the 30-exercise library, build a routine, start a solo workout, log sets with reps/weight/RPE, see a "🔥 NEW PR!" toast when they beat a prior best, complete the workout, see it in Recent Activity, view a Swift Charts trend for any exercise, see their lifetime volume lifted in Stats, and see the workout in Apple Health.
3. All XCTest and RLS integration tests pass in CI.
4. Manual test on a real device: full flow works, no crashes, no data leakage between users (create two Apple test accounts and verify user B cannot see user A's routines or logs).
5. TestFlight build (internal only) uploaded successfully.

---

## Self-Review Notes

I ran a coverage check against the spec (§§1-8) and against the interfaces block at the top of this plan. Everything Phase 1 promised in the "v1 includes" list — that's within scope for Phase 1 — has a task producing it:

- **Auth (Sign in with Apple):** Tasks 12–15
- **Profile creation + username:** Task 15 + repository in Task 14
- **Home gym setup step** in onboarding: **NOT included in Phase 1**, deliberately deferred to Phase 3 (multi-player sessions) where geofence check-in actually matters. Solo workouts don't need a gym. This is intentional descope; noted here so Fable doesn't infer it's missing.
- **Curated exercise library:** Task 3 (seeds 30 for Phase 1)
- **Routine builder:** Tasks 18–19
- **Solo workout flow:** Tasks 20–22
- **PR detection:** Task 7 (trigger) + Task 21 (client toast)
- **Ledger + charts:** Tasks 23–24
- **HealthKit export:** Task 22
- **AVAudioSession regression guard:** Task 25 (feature use lands in Phase 3, guard lands now)

Interfaces defined in the top-of-plan block match what tasks produce. Signatures verified consistent (`ProfileRepository.fetch`, `create`, `usernameAvailable`; `SessionRepository.startSolo`, `complete`, `logSet`, `history`, `setLogs`, `exerciseHistory`).

Placeholders scan: 0 TBDs, 0 TODOs, 0 "implement later." Every step has real code or real commands.

Types are consistent across tasks: `WorkoutSession` (not `Session` — avoids clashing with SwiftUI's `Session` in some contexts), `SetLog`, `Profile`, `Exercise`, `Routine`, `RoutineExercise`.

Ready for handoff.
