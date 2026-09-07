#!/usr/bin/env node
/**
 * Seeds a deterministic, screenshot-stable world for the CI test account so
 * the app's real internal fetches return known data on every screen: a group
 * (with the account as admin member), sessions in every lifecycle state, a
 * mixed chat thread, friends (one accepted, one incoming pending request),
 * a small routine library with exercises, personal records, one
 * published/featured routine for the Library "Featured" shelf, a featured
 * public workouts pack (Discover), and one draft seasonal campaign (Phase C
 * Task 3) with the CI account joined and a completed fixture session proving
 * live progress accrual.
 *
 * Idempotent: every block deletes this account's own prior fixture rows
 * (keyed on a stable marker — a `[QA]` name prefix, or — for the group,
 * whose id other fixture rows point at — a stable id found via natural key
 * rather than re-generated every run) then re-inserts, so re-running
 * converges to the same state instead of duplicating. The personal_records
 * block is the exception: that table is append-only with no fixture marker,
 * so it inserts-if-absent instead of deleting, and never touches a
 * pre-existing row.
 *
 * Usage:  node scripts/seed_qa_fixtures.js --username <ci_test_user>
 * Requires SUPABASE_URL + SUPABASE_SECRET_KEY (+ SUPABASE_DB_PASSWORD, only
 * needed the first time to create the fixture-friend auth user) in .env.local
 * (service role).
 *
 * NOTE on production visibility (Task 7 item 2, pre-GA ledger): this script
 * runs against the SAME Supabase project CI and production share (one
 * project total — see .github/workflows/ios.yml's Seed QA fixture world
 * step) — every row it writes is genuinely live in production, not an
 * isolated test copy. Every fixture below is scoped to be inert for real
 * users EXCEPT the "The Murph" attempt fixture, which used to set
 * `is_opt_in_leaderboard: true` and therefore put the CI account's row on
 * the real, public "The Murph" leaderboard next to genuine users — see that
 * block's own comment for the full adjudication (why `false` now, why not
 * env-scoped seeding or a separate cleanup script).
 */
const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');
const { randomUUID } = require('node:crypto');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = (k) => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const SUPABASE_URL = get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = get('SUPABASE_SECRET_KEY');
const SUPABASE_DB_PASSWORD = get('SUPABASE_DB_PASSWORD');
if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SECRET_KEY in .env.local'); process.exit(1);
}
const headers = {
  apikey: SUPABASE_SECRET_KEY, Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  'Content-Type': 'application/json',
};
async function rest(pathAndQuery, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
    ...opts, headers: { ...headers, ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error(`${pathAndQuery}: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}
const rep = { Prefer: 'return=representation' };
const MARK = '[QA]'; // stable marker: name-prefix for fixture rows we own

// Mirrors the deny-list in `set_logs_reject_prelive`, the BEFORE INSERT
// trigger on set_logs (20260803000002_set_logs_reject_prelive.sql:19). It
// raises P0001 "session has not started" for a log written against a session
// in any of these states. Keep this list identical to the migration's.
const PRELIVE_STATES = ['scheduled', 'lobby_open', 'editing', 'voting', 'locked'];

// Walks a fixture session live so the set_logs written into it are accepted:
// start -> log -> complete, the same order a real client produces. Two
// fixture blocks below (the Murph attempt and the campaign-progress sessions)
// create their session as `scheduled`, and CI run 33990257726 died on exactly
// that, at the first set_logs insert.
//
// Idempotent by state, which is what makes a rerun safe in both directions:
// a session already `in_progress` is left alone, and a `completed` one — what
// a finished prior run leaves behind — is never re-opened. `session.state` is
// updated in place so the completion PATCH that follows can filter on the
// state it will actually find.
async function ensureSessionLive(session, startedAt) {
  if (!PRELIVE_STATES.includes(session.state)) return;
  await rest(`sessions?id=eq.${session.id}`, { method: 'PATCH',
    body: JSON.stringify({ state: 'in_progress', started_at: startedAt }) });
  session.state = 'in_progress';
}

// I2 (home-v3-production plan / brief-integration.md): the same week rule
// `WeekMath.startOfWeek` uses in Swift — the DEVICE calendar's week, not
// ISO — mirrored in UTC, since Node has no Foundation `Calendar`. The CI
// simulator's locale is en_US, whose first day is SUNDAY (`firstWeekday`
// 1), so this walks `now` back to the most recent UTC Sunday midnight.
// `getUTCDay()`: 0 = Sunday already, so no rotation is needed the way a
// Monday-first week would require.
function currentWeekStartSunday(now = new Date()) {
  const d = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  d.setUTCDate(d.getUTCDate() - d.getUTCDay());
  return d.toISOString().slice(0, 10); // yyyy-MM-dd, weekly_goals.week_start's shape
}

// WHO IS WHO (corrected 2026-09-05, from the DB and the repo secrets):
// the seeded world's OWNER is whoever `--username` names — supplied by the
// CI_TEST_USERNAME secret as `ci_test_user`, which is the account CI
// actually signs in as. Its email (ci-tests@gymsync.app) is TEST_USER_EMAIL,
// which the screenshot job forwards as UITEST_EMAIL, and its username is the
// greeting rendered on the Home capture. The GymSyncTests unit target signs
// in as the same account.
//
// `ci_test_user_2` is the real SECOND CI account (id/username only — nothing
// signs in as it here) used solely as the accepted-friend counterpart. That
// matches the Swift tests, which also treat `_2` as the counterpart:
// FriendRepositoryTests sends its requests TO `ci_test_user_2`, and
// GroupRepositoryTests invites it. Not managed by this script.
const ACCEPTED_FRIEND_USERNAME = 'ci_test_user_2';

// Third profile, created here if missing, used as the *pending* friend
// counterpart. `ci_test_user_2` is already spoken for as the accepted friend,
// and the only other existing profile in the project is a real dev account
// ("Smola") — seeding a fake pending request onto a real person's account
// would pollute their data, so we mint a dedicated fixture profile instead.
const PENDING_FRIEND_USERNAME = 'qa_fixture_friend';
const PENDING_FRIEND_EMAIL = 'qa-fixture-friend@gymsync.app';

const ROUTINE_PACK = [
  { name: `${MARK} Push Day`, exercises: [
    { slug: 'bench-press', sets: 4, reps: '8-10' },
    { slug: 'db-shoulder-press', sets: 3, reps: '10' },
    { slug: 'face-pull', sets: 3, reps: '15' },
  ] },
  { name: `${MARK} Pull Day`, exercises: [
    { slug: 'barbell-row', sets: 4, reps: '8-10' },
    { slug: 'chin-up', sets: 3, reps: 'AMRAP' },
    { slug: 'bicep-curl', sets: 3, reps: '12' },
  ] },
  { name: `${MARK} Leg Day`, exercises: [
    { slug: 'back-squat', sets: 4, reps: '6-8', weight: '185' },
    { slug: 'deadlift', sets: 3, reps: '5', weight: '225' },
    { slug: 'calf-raise', sets: 3, reps: '15' },
  ] },
];
const FEATURED_ROUTINE = { name: `${MARK} Featured Full Body`, exercises: [
  { slug: 'back-squat', sets: 3, reps: '5' },
  { slug: 'bench-press', sets: 3, reps: '5' },
  { slug: 'barbell-row', sets: 3, reps: '8' },
] };
const PR_EXERCISES = [
  { slug: 'back-squat', weight: 225, reps: 3, previous_best: 205 },
  { slug: 'bench-press', weight: 185, reps: 5, previous_best: 175 },
  { slug: 'deadlift', weight: 315, reps: 1, previous_best: 295 },
];

// Phase L Task 4: featured workouts pack ("The Murph" + 2 strength
// templates) — extends the curator-publish idiom just below (single
// FEATURED_ROUTINE, pre-existing) to the 4 Phase L columns Task 1 added
// fix-forward to `routines` (is_featured/default_sort/scoring_metrics/
// scoring_top_set_exercise_id, `supabase/migrations/20260723000001_
// public_workout_repository.sql:29-35`).
//
// "The Murph" HONEST ADAPTATION: the canonical workout is 1-mile run, 100
// pull-ups, 200 push-ups, 300 squats, 1-mile run (often with a 20lb vest).
// This schema has NO way to represent a run or a weighted vest — grepped the
// full exercise catalog (`node scripts/seed_routines.js --list-exercises`,
// 200+ entries) for any distance/cardio/timed-interval category: none
// exists (every entry is a discrete weight-room movement). This seed keeps
// ONLY the representable middle three movements and drops both runs and the
// vest — not faked as a 4th "exercise," just omitted, and documented both
// here and in the routine's own `description` (shown in the app).
const FEATURED_WORKOUTS = [
  {
    name: 'The Murph',
    description: "Murph — adapted. The two bookend 1-mile runs (and the " +
      "20lb vest) aren't representable in this app's set-log model (no " +
      "distance/cardio exercise exists in the catalog), so this seed keeps " +
      "only the representable middle: 100 pull-ups, 200 push-ups, 300 squats.",
    isFeatured: true,
    defaultSort: 'time',
    scoringMetrics: ['time', 'volume'],
    topSetExerciseSlug: null,
    exercises: [
      { slug: 'pull-up', sets: 1, reps: '100' },
      { slug: 'push-up', sets: 1, reps: '200' },
      { slug: 'bodyweight-squat', sets: 1, reps: '300' },
    ],
  },
  {
    name: 'StrongLifts 5x5 — Workout A',
    description: 'Classic novice linear-progression day A: Squat, Bench Press, Barbell Row — 5 sets of 5.',
    isFeatured: false,
    defaultSort: 'volume',
    scoringMetrics: ['volume', 'top_set'],
    topSetExerciseSlug: 'back-squat',
    exercises: [
      { slug: 'back-squat', sets: 5, reps: '5', weight: '135' },
      { slug: 'bench-press', sets: 5, reps: '5', weight: '95' },
      { slug: 'barbell-row', sets: 5, reps: '5', weight: '95' },
    ],
  },
  {
    name: 'Hypertrophy Push Day',
    description: 'Chest/shoulders/triceps volume day — moderate weight, higher reps.',
    isFeatured: false,
    defaultSort: 'volume',
    scoringMetrics: ['volume', 'top_set'],
    topSetExerciseSlug: 'bench-press',
    exercises: [
      { slug: 'bench-press', sets: 4, reps: '8-10', weight: '135' },
      { slug: 'incline-db-press', sets: 3, reps: '10', weight: '55' },
      { slug: 'ohp', sets: 3, reps: '10', weight: '65' },
      { slug: 'lateral-raise', sets: 3, reps: '15', weight: '15' },
      { slug: 'tricep-pushdown', sets: 3, reps: '12', weight: '40' },
    ],
  },
];

// Creates the auth user + profile for the pending-friend fixture if it
// doesn't already exist (mirrors scripts/create_second_test_user.js). Safe
// to call every run — short-circuits once the profile exists.
async function ensurePendingFriendProfile() {
  const [existing] = await rest(`profiles?select=id,username&username=eq.${PENDING_FRIEND_USERNAME}`);
  if (existing) return existing;

  if (!SUPABASE_DB_PASSWORD) {
    console.error('Missing SUPABASE_DB_PASSWORD in .env.local (needed to create the fixture-friend auth user)');
    process.exit(1);
  }

  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/users`, {
    method: 'POST', headers,
    body: JSON.stringify({ email: PENDING_FRIEND_EMAIL, password: SUPABASE_DB_PASSWORD, email_confirm: true }),
  });
  const body = await res.json();
  let userId;
  if (!res.ok) {
    if (body.message && body.message.includes('already been registered')) {
      const listRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users?email=${encodeURIComponent(PENDING_FRIEND_EMAIL)}`, { headers });
      const listBody = await listRes.json();
      const users = listBody.users || listBody;
      const found = Array.isArray(users) ? users.find((u) => u.email === PENDING_FRIEND_EMAIL) : null;
      if (!found) throw new Error(`Could not find existing auth user for ${PENDING_FRIEND_EMAIL}`);
      userId = found.id;
    } else {
      throw new Error(`auth admin create failed: ${res.status} ${JSON.stringify(body)}`);
    }
  } else {
    userId = body.id;
  }
  const [created] = await rest('profiles', { method: 'POST', headers: rep,
    body: JSON.stringify({ id: userId, username: PENDING_FRIEND_USERNAME }) });
  return created || { id: userId, username: PENDING_FRIEND_USERNAME };
}

async function main() {
  const { values } = parseArgs({ options: { username: { type: 'string' } } });
  if (!values.username) { console.error('Usage: --username <ci_test_user>'); process.exit(1); }

  const [me] = await rest(`profiles?select=id,username&username=ilike.${encodeURIComponent(values.username)}`);
  if (!me) { console.error(`No profile for "${values.username}"`); process.exit(1); }
  console.log(`Seeding QA world for @${me.username} (${me.id})`);

  // --- pollution guard (Opus pre-GA closeout, 2026-07-20) -----------------
  // Every group the CI account belongs to receives its fan-out system
  // messages (PR / streak / campaign-completion — the trigger loops ALL of
  // the achiever's groups, draft-blind). A CI-account membership in a REAL
  // user's group therefore silently posts test chatter into that chat: it
  // happened once (ci_test_user was a member of "Men for Christ", leaking
  // system_pr + system_campaign rows — cleaned + membership removed live).
  // Every fixture below deliberately uses only the `[QA]`-prefixed group,
  // so any membership OUTSIDE that marker is unwanted by construction. This
  // guard makes the invariant self-healing: on every run, strip the CI
  // account out of any non-`[QA]` group before a single fixture fires, and
  // warn loudly so a stray membership surfaces instead of polluting in
  // silence.
  const myGroups = await rest(`group_members?user_id=eq.${me.id}&select=group_id,groups(name)`);
  for (const gm of myGroups) {
    const gname = gm.groups && gm.groups.name;
    if (!gname || !gname.startsWith(MARK)) {
      console.warn(`  ⚠ POLLUTION GUARD: @${me.username} is in non-QA group "${gname ?? gm.group_id}" — removing (fan-out system messages would leak into it).`);
      await rest(`group_members?group_id=eq.${gm.group_id}&user_id=eq.${me.id}`, { method: 'DELETE' });
    }
  }

  // --- group + membership -------------------------------------------------
  // Find-or-create by natural key (created_by, name) rather than
  // delete-then-recreate: sessions.group_id is ON DELETE SET NULL (not
  // CASCADE), so re-minting the group with a fresh id every run would orphan
  // last run's sessions (group_id -> null) instead of replacing them, and
  // the orphans would silently fall out of any query that joins through
  // groups. Keeping the group's id stable across runs lets every child
  // block below clean up by group_id reliably.
  const GROUP_NAME = `${MARK} Push Crew`;
  let [group] = await rest(`groups?select=id&created_by=eq.${me.id}&name=eq.${encodeURIComponent(GROUP_NAME)}`);
  if (!group) {
    [group] = await rest('groups', { method: 'POST', headers: rep,
      body: JSON.stringify({ created_by: me.id, name: GROUP_NAME }) });
  }
  await rest(`group_members?group_id=eq.${group.id}&user_id=eq.${me.id}`, { method: 'DELETE' });
  await rest('group_members', { method: 'POST',
    body: JSON.stringify({ group_id: group.id, user_id: me.id, role: 'admin' }) });
  console.log(`  group ${group.id}`);

  // --- sessions in each state (group_id is stable, so this always finds
  //     and replaces last run's rows) --------------------------------------
  await rest(`sessions?group_id=eq.${group.id}`, { method: 'DELETE' });
  const states = ['scheduled', 'lobby_open', 'voting', 'locked', 'in_progress', 'completed'];
  const now = new Date().toISOString();
  for (const state of states) {
    const row = { group_id: group.id, organizer_id: me.id, state, scheduled_for: now };
    if (state === 'in_progress') row.started_at = now;
    if (state === 'completed') { row.started_at = now; row.completed_at = now; }
    await rest('sessions', { method: 'POST', body: JSON.stringify(row) });
  }
  console.log(`  sessions: ${states.join(', ')}`);

  // --- streak fixture: a real live current_streak for the Stats screen ----
  // (Phase S Task 5). `user_streaks` is populated ONLY by DB triggers
  // (streak_bump_user / streak_break_user, 20260719000006_streaks.sql) that
  // fire on a genuine `sessions.state` UPDATE into 'completed' (never a
  // direct INSERT-as-completed like the lifecycle-state block just above)
  // for a session with `scheduled_for IS NOT NULL`, crediting only
  // participants whose row is `check_in_state = 'ready'` at that moment. So
  // unlike every other fixture in this file, these sessions have to be
  // walked through scheduled -> ready-checked-in -> completed for real,
  // not synthesized already in their terminal state.
  //
  // Sessions have no name/title column at all (20260709000006_create_
  // sessions.sql) — there's no literal "[QA]" prefix to stamp on a session
  // row the way routines/groups get one. The fixed, deterministic
  // `scheduled_for` timestamps below (never `now()`) are this block's
  // equivalent natural-key marker: idempotent detection queries against
  // them directly instead.
  //
  // Deliberately NOT placed in the "[QA] Push Crew" group: that group's
  // sessions are unconditionally deleted and reinserted-as-already-completed
  // every run (line ~157 above), which would mint a fresh session id each
  // time — streak_bump_user's guard only blocks re-crediting the exact same
  // session id, not "a session in the same group," so reusing that group
  // would re-increment current_streak on every single run. group_id/
  // routine_id are left null (both nullable — an ad-hoc scheduled solo
  // session, same shape `SessionRepository.schedule(routineID: nil, ...)`
  // already produces); the individual-streak trigger doesn't require a
  // group at all, only the group-streak bump does.
  const STREAK_DATES = [
    '2026-07-10T09:00:00.000Z',
    '2026-07-11T09:00:00.000Z',
    '2026-07-12T09:00:00.000Z',
  ];
  let streakCreated = 0, streakSkipped = 0;
  for (const iso of STREAK_DATES) {
    const [existing] = await rest(
      `sessions?select=id,state&organizer_id=eq.${me.id}&group_id=is.null&scheduled_for=eq.${encodeURIComponent(iso)}`);

    if (existing && existing.state === 'completed') { streakSkipped++; continue; }

    let session = existing;
    if (!session) {
      const [created] = await rest('sessions', { method: 'POST', headers: rep,
        body: JSON.stringify({ organizer_id: me.id, state: 'scheduled', scheduled_for: iso }) });
      session = created;
    }

    // Upsert-by-natural-key (PK is session_id+user_id) so a resumed
    // partial run (e.g. a crash between this insert and the completion
    // PATCH below) can safely re-POST without a 409.
    await rest('session_participants', { method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify({
        session_id: session.id, user_id: me.id,
        check_in_state: 'ready', check_in_at: iso,
      }) });

    // scheduled -> completed: the exact transition streak_on_session_state_
    // change() listens for (AFTER UPDATE OF state). The `state=eq.scheduled`
    // filter makes this a no-op (0 rows) if some other process already
    // completed it between the existence check above and here.
    await rest(`sessions?id=eq.${session.id}&state=eq.scheduled`, { method: 'PATCH',
      body: JSON.stringify({ state: 'completed', completed_at: iso }) });
    streakCreated++;
  }
  const [streak] = await rest(`user_streaks?select=current_streak,longest_streak&user_id=eq.${me.id}`);
  console.log(`  streak chain: ${streakCreated} completed this run, ${streakSkipped} already done — ` +
    `current_streak=${streak?.current_streak ?? 0}, longest_streak=${streak?.longest_streak ?? 0}`);

  // --- body weight log series: a real trend for the Stats "Body Weight"
  //     card (Phase H Task 3) -----------------------------------------------
  // `body_weight_logs` (20260724000001_body_weight_logs.sql) is a plain
  // client-writable, owner-only table — unlike the streak block above, no
  // trigger walk-through is needed, a direct insert suffices. Same
  // insert-if-absent-by-fixed-timestamp idiom as STREAK_DATES/
  // MURPH_ATTEMPT_SCHEDULED_FOR above (never `now()`): `logged_at` has no
  // fixture marker column to delete-by (same shape gap sessions has), so a
  // fixed weekly-Friday series is this block's natural key — a resumed or
  // repeated run only inserts whatever timestamps are still missing, never
  // duplicates, and never touches a row this account may have logged for
  // real outside this script (a blanket delete-by-user_id would risk that).
  // Ten points, mildly trending down (186.2 -> 180.4 lbs) so the trend line
  // actually slopes instead of rendering as a flat series.
  const WEIGHT_LOG_SERIES = [
    { loggedAt: '2026-05-15T08:00:00.000Z', weight: 186.2 },
    { loggedAt: '2026-05-22T08:00:00.000Z', weight: 185.4 },
    { loggedAt: '2026-05-29T08:00:00.000Z', weight: 185.0 },
    { loggedAt: '2026-06-05T08:00:00.000Z', weight: 184.1 },
    { loggedAt: '2026-06-12T08:00:00.000Z', weight: 183.6 },
    { loggedAt: '2026-06-19T08:00:00.000Z', weight: 183.0 },
    { loggedAt: '2026-06-26T08:00:00.000Z', weight: 182.2 },
    { loggedAt: '2026-07-03T08:00:00.000Z', weight: 181.8 },
    { loggedAt: '2026-07-10T08:00:00.000Z', weight: 181.0 },
    { loggedAt: '2026-07-17T08:00:00.000Z', weight: 180.4 },
  ];
  let weightCreated = 0, weightSkipped = 0;
  for (const point of WEIGHT_LOG_SERIES) {
    const [existing] = await rest(
      `body_weight_logs?select=id&user_id=eq.${me.id}&logged_at=eq.${encodeURIComponent(point.loggedAt)}`);
    if (existing) { weightSkipped++; continue; }
    await rest('body_weight_logs', { method: 'POST', body: JSON.stringify({
      user_id: me.id, weight: point.weight, unit: 'lbs', logged_at: point.loggedAt,
    }) });
    weightCreated++;
  }
  console.log(`  body weight log series: ${weightCreated} inserted this run, ${weightSkipped} already present ` +
    `(${WEIGHT_LOG_SERIES[0].weight} -> ${WEIGHT_LOG_SERIES[WEIGHT_LOG_SERIES.length - 1].weight} lbs)`);

  // --- chat thread: text + soundboard echo + voice-note row ---------------
  await rest(`chat_messages?group_id=eq.${group.id}`, { method: 'DELETE' });
  const messages = [
    { group_id: group.id, author_id: me.id, kind: 'text', body: `${MARK} great lift today, who's in for Thursday?` },
    { group_id: group.id, author_id: me.id, kind: 'soundboard_echo', body: '🔊 Airhorn', payload: { sound_slug: 'airhorn' } },
    { group_id: group.id, author_id: me.id, kind: 'audio', body: '0:07', storage_path: `${group.id}/qa-fixture-voice-note.m4a`, payload: { duration_seconds: 7 } },
  ];
  for (const m of messages) await rest('chat_messages', { method: 'POST', body: JSON.stringify(m) });
  console.log(`  chat messages: ${messages.map((m) => m.kind).join(', ')}`);

  // --- friends: one accepted, one pending (incoming) -----------------------
  const [acceptedFriend] = await rest(`profiles?select=id,username&username=ilike.${ACCEPTED_FRIEND_USERNAME}`);
  if (!acceptedFriend) { console.error(`No profile for "${ACCEPTED_FRIEND_USERNAME}" (expected accepted-friend counterpart)`); process.exit(1); }
  const pendingFriend = await ensurePendingFriendProfile();

  const friendFilter = `or=(and(user_id.eq.${me.id},friend_id.eq.${acceptedFriend.id}),` +
    `and(user_id.eq.${acceptedFriend.id},friend_id.eq.${me.id}),` +
    `and(user_id.eq.${me.id},friend_id.eq.${pendingFriend.id}),` +
    `and(user_id.eq.${pendingFriend.id},friend_id.eq.${me.id}))`;
  await rest(`friendships?${friendFilter}`, { method: 'DELETE' });
  await rest('friendships', { method: 'POST', body: JSON.stringify([
    { user_id: me.id, friend_id: acceptedFriend.id, status: 'accepted' },
    // Incoming request: friend_id = me, so it surfaces in FriendRepository.incomingRequests().
    { user_id: pendingFriend.id, friend_id: me.id, status: 'pending' },
  ]) });
  console.log(`  friends: accepted=@${acceptedFriend.username}, pending=@${pendingFriend.username}`);

  // --- resolve exercise slugs used by routines + PRs in one query ---------
  const allSlugs = [...new Set([
    ...ROUTINE_PACK.flatMap((r) => r.exercises.map((e) => e.slug)),
    ...FEATURED_ROUTINE.exercises.map((e) => e.slug),
    ...PR_EXERCISES.map((p) => p.slug),
    ...FEATURED_WORKOUTS.flatMap((w) => w.exercises.map((e) => e.slug)),
  ])];
  const exerciseRows = await rest(`exercises?select=id,slug&slug=in.(${allSlugs.map(encodeURIComponent).join(',')})`);
  const bySlug = Object.fromEntries(exerciseRows.map((e) => [e.slug, e.id]));
  const missing = allSlugs.filter((s) => !bySlug[s]);
  if (missing.length) { console.error(`Unknown exercise slugs: ${missing.join(', ')}`); process.exit(1); }

  // --- routines (2-3) with exercises ---------------------------------------
  // Broad delete-by-prefix also removes a prior run's featured routine
  // (recreated fresh in its own block below) — harmless since both blocks
  // fully re-populate what they own every run.
  await rest(`routines?owner_id=eq.${me.id}&name=ilike.${encodeURIComponent(MARK + '%')}`, { method: 'DELETE' });
  for (const routine of ROUTINE_PACK) {
    const [created] = await rest('routines', { method: 'POST', headers: rep,
      body: JSON.stringify({ owner_id: me.id, name: routine.name }) });
    const rows = routine.exercises.map((e, i) => ({
      routine_id: created.id, exercise_id: bySlug[e.slug], position: i + 1,
      target_sets: e.sets ?? null, target_reps: e.reps != null ? String(e.reps) : null,
      target_weight: e.weight != null ? String(e.weight) : null,
    }));
    await rest('routine_exercises', { method: 'POST', body: JSON.stringify(rows) });
  }
  console.log(`  routines: ${ROUTINE_PACK.map((r) => r.name).join(', ')}`);

  // --- personal_records for the Stats hero + Recent PRs table -------------
  // personal_records is append-only with no fixture-marker column and no
  // unique constraint on (user_id, exercise_id) — a real PR the CI account
  // set on one of these exercises outside this script would live in the
  // same rows a delete-by-(user_id, exercise_id) would target, so deleting
  // here would destroy real history, not just fixture rows. Insert-if-absent
  // instead: find which fixture exercises already have a row for this user
  // and only insert the ones that don't. A pre-existing real PR is left in
  // place — the Stats screen still renders a populated PR row either way.
  const prExerciseIds = PR_EXERCISES.map((p) => bySlug[p.slug]);
  const existingPRs = await rest(`personal_records?select=exercise_id&user_id=eq.${me.id}&exercise_id=in.(${prExerciseIds.join(',')})`);
  const existingPRExerciseIds = new Set(existingPRs.map((r) => r.exercise_id));
  const missingPRs = PR_EXERCISES.filter((p) => !existingPRExerciseIds.has(bySlug[p.slug]));
  if (missingPRs.length) {
    await rest('personal_records', { method: 'POST', body: JSON.stringify(
      missingPRs.map((p) => ({
        user_id: me.id, exercise_id: bySlug[p.slug],
        weight: p.weight, reps: p.reps, previous_best: p.previous_best,
      })),
    ) });
  }
  const skipped = PR_EXERCISES.length - missingPRs.length;
  console.log(`  personal records: ${PR_EXERCISES.map((p) => p.slug).join(', ')}${skipped ? ` (${skipped} already existed, left as-is)` : ''}`);

  // --- one published/featured routine for the Library Featured shelf ------
  // THE CURATOR GRANT IS SCOPED AND ALWAYS REVOKED (2026-09-05).
  //
  // Why it exists: setting `is_featured = true` on a routine is curator-gated
  // by RLS (`20260728000008_open_publishing_and_stars.sql:12-29` — publishing
  // `visibility='public'` opened to every owner; the FEATURED spotlight did
  // not), and the featured-workouts pack below writes exactly that. The
  // service-role key bypasses RLS entirely, so the grant is not strictly
  // required for these writes to land — it is here for realism, so the seed
  // exercises the same shape a real curator would. `profiles_guard_is_curator`
  // (20260717000004) only blocks the authenticated/anon roles, not
  // service_role, so this PATCH is unaffected by that trigger.
  //
  // Why it is REVOKED, in a `finally`: the seeded account is `ci_test_user`,
  // the same account the GymSyncTests unit target signs in as, and
  // `CurationRepositoryTests.testOpenPublishingButFeaturedIsCuratorGated`
  // requires it to be a NON-curator at rest — it asserts that a self-feature
  // is rejected by RLS ("non-curator self-feature must be rejected by RLS",
  // CurationRepositoryTests.swift:52, with the file's own header at :4-6
  // stating the CI user is deliberately not a curator). The previous version
  // of this block granted the flag and never revoked it, which turned that
  // test red on CI run 33990996813. `finally`, not a trailing statement, so a
  // throw anywhere in the span below still revokes.
  //
  // The rows created under the grant stay valid after it: RLS gates the
  // WRITE, not the row's existence, so the featured shelf keeps rendering.
  //
  // SPAN: the two blocks that write `routines` — this featured routine and
  // the featured-workouts pack. Everything after them (Murph attempt,
  // campaign, progress sessions) writes sessions / session_participants /
  // set_logs / workout_attempts / campaigns, none of which consults
  // is_curator (campaigns has no client write policy at all —
  // 20260728000001_campaigns_schema.sql:250), so the span ends here rather
  // than being re-granted later.
  await rest(`profiles?id=eq.${me.id}`, { method: 'PATCH', body: JSON.stringify({ is_curator: true }) });
  const featuredWorkoutIDs = {};   // declared outside the try: read by the Murph/campaign blocks below
  try {
    await rest(`routines?owner_id=eq.${me.id}&visibility=eq.public&name=ilike.${encodeURIComponent(MARK + '%')}`, { method: 'DELETE' });
    const [featured] = await rest('routines', { method: 'POST', headers: rep,
      body: JSON.stringify({ owner_id: me.id, name: FEATURED_ROUTINE.name, visibility: 'public' }) });
    const featuredRows = FEATURED_ROUTINE.exercises.map((e, i) => ({
      routine_id: featured.id, exercise_id: bySlug[e.slug], position: i + 1,
      target_sets: e.sets, target_reps: String(e.reps),
    }));
    await rest('routine_exercises', { method: 'POST', body: JSON.stringify(featuredRows) });
    console.log(`  featured routine: ${FEATURED_ROUTINE.name}`);

    // --- Phase L Task 4: featured workouts pack (find-or-create by natural
    //     key, NOT delete-then-recreate) ------------------------------------
    // Deliberately NOT this file's usual "delete-by-marker then re-insert"
    // idiom (ROUTINE_PACK/FEATURED_ROUTINE above): those routines are never
    // referenced by another table across a re-run, but these 3 ARE — "The
    // Murph"'s id is what the attempt fixture below points at
    // (workout_attempts.routine_id / leaderboard_entries.routine_id, both
    // `ON DELETE SET NULL`, `20260723000001_public_workout_repository.
    // sql:72,93`). Deleting and recreating it every run would silently orphan
    // the CI attempt fixture's leaderboard row (routine_id -> NULL) on the
    // SECOND run — the exact "group_id ON DELETE SET NULL orphaning" lesson
    // this file's own group block already learned (see that block's comment,
    // above), applied here to a new table. Find-or-create by (owner_id, name)
    // instead — same natural-key idiom the group block uses — and PATCH the
    // publish fields in place on every run so a pack-definition edit still
    // takes effect without minting a new id.
    for (const w of FEATURED_WORKOUTS) {
      let [routine] = await rest(
        `routines?select=id&owner_id=eq.${me.id}&name=eq.${encodeURIComponent(w.name)}`);
      const publishFields = {
        visibility: 'public',
        is_featured: w.isFeatured,
        default_sort: w.defaultSort,
        scoring_metrics: w.scoringMetrics,
        scoring_top_set_exercise_id: w.topSetExerciseSlug ? bySlug[w.topSetExerciseSlug] : null,
        description: w.description,
      };
      if (!routine) {
        [routine] = await rest('routines', { method: 'POST', headers: rep,
          body: JSON.stringify({ owner_id: me.id, name: w.name, ...publishFields }) });
      } else {
        await rest(`routines?id=eq.${routine.id}`, { method: 'PATCH', body: JSON.stringify(publishFields) });
      }
      featuredWorkoutIDs[w.name] = routine.id;

      // routine_exercises carry no cross-run stable reference (nothing else
      // points at a specific routine_exercises row) — safe to delete-and-
      // reinsert every run, same idiom as ROUTINE_PACK above.
      await rest(`routine_exercises?routine_id=eq.${routine.id}`, { method: 'DELETE' });
      const rows = w.exercises.map((e, i) => ({
        routine_id: routine.id, exercise_id: bySlug[e.slug], position: i + 1,
        target_sets: e.sets ?? null, target_reps: e.reps != null ? String(e.reps) : null,
        target_weight: e.weight != null ? String(e.weight) : null,
      }));
      await rest('routine_exercises', { method: 'POST', body: JSON.stringify(rows) });
    }
    console.log(`  featured workouts pack: ${FEATURED_WORKOUTS.map((w) => w.name).join(', ')}`);
  } finally {
    // Unconditional: the account must be a non-curator at rest, whether or
    // not the span above succeeded. A failed run that left the flag ON is
    // what red-lit build-test; this revoke also self-heals that state on the
    // next run, because it runs even when the span throws.
    await rest(`profiles?id=eq.${me.id}`, { method: 'PATCH', body: JSON.stringify({ is_curator: false }) });
    console.log('  curator grant revoked (ci_test_user is a non-curator at rest)');
  }

  // --- Phase L Task 4: CI-account "The Murph" attempt fixture -------------
  // workout_attempts/leaderboard_entries are written EXCLUSIVELY by DEFINER
  // triggers (no `authenticated` INSERT policy on either table at all,
  // `20260723000001_public_workout_repository.sql:145-160`) and the normal
  // client entry point, `start_attempt`, is SECURITY DEFINER keyed on
  // `auth.uid()` — meaningless from this service-role script (no user JWT,
  // `auth.uid()` reads NULL server-side). The honest seed, mirroring this
  // file's OWN streak fixture above ("walk it through for real, don't
  // synthesize the terminal state"): use the service-role key's RLS bypass
  // (the same bypass this whole script already relies on for
  // sessions/session_participants/set_logs elsewhere) to write a real
  // session_participants row, a real workout_attempts row, and real
  // set_logs, then let the REAL
  // `leaderboard_recompute_on_session_completion` trigger compute
  // time_seconds/total_volume/top_sets itself — never hand-written into
  // leaderboard_entries directly.
  //
  // THREE steps, in this order, and the order is not cosmetic:
  //   1. `scheduled` -> `in_progress` (`ensureSessionLive`), because
  //      `set_logs_reject_prelive` — a BEFORE INSERT trigger ON set_logs
  //      (20260803000002) — raises P0001 "session has not started" for a log
  //      written into any pre-live session. This is the step CI run
  //      33990257726 was missing.
  //   2. insert the set_logs.
  //   3. `in_progress` -> `completed` in ONE PATCH, which is the transition
  //      the leaderboard recompute (AFTER UPDATE OF state) listens for.
  // It is also the order a real client produces, which is the point: the
  // fixture walks the same path a lifter does rather than synthesising a
  // terminal state the triggers never saw.
  //
  // Fixed, deterministic `scheduled_for` (never `now()`) is this block's
  // natural key, same idiom as STREAK_DATES above — sessions has no name
  // column to stamp a `[QA]` marker on. `MURPH_ATTEMPT_COMPLETED_AT` is
  // deliberately 42:13 after `started_at` — the exact time the master
  // spec's own Flow 4 worked example uses for its system-message copy
  // ("attempted The Murph — 42:13, #187",
  // `docs/superpowers/specs/2026-06-28-gymsync-design.md:790-797`).
  const MURPH_ATTEMPT_SCHEDULED_FOR = '2026-07-18T09:00:00.000Z';
  const MURPH_ATTEMPT_COMPLETED_AT = '2026-07-18T09:42:13.000Z';
  const murphID = featuredWorkoutIDs['The Murph'];

  let [murphSession] = await rest(
    `sessions?select=id,state&organizer_id=eq.${me.id}&routine_id=eq.${murphID}` +
    `&scheduled_for=eq.${encodeURIComponent(MURPH_ATTEMPT_SCHEDULED_FOR)}`);
  if (!murphSession) {
    [murphSession] = await rest('sessions', { method: 'POST', headers: rep,
      body: JSON.stringify({
        organizer_id: me.id, routine_id: murphID, state: 'scheduled',
        scheduled_for: MURPH_ATTEMPT_SCHEDULED_FOR,
      }) });
  }

  // Self as sole participant — same idiom `SessionRepository.startSolo`
  // uses client-side for every real solo session ("Add self as sole
  // participant, for RLS unification across phases"). Upsert-by-natural-key
  // (PK is session_id+user_id) so a resumed partial run can safely re-POST.
  await rest('session_participants', { method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({
      session_id: murphSession.id, user_id: me.id,
      check_in_state: 'ready', check_in_at: MURPH_ATTEMPT_SCHEDULED_FOR,
    }) });

  // workout_attempts: find-or-create by the table's own UNIQUE(session_id,
  // user_id) index (`workout_attempts_session_user_idx`) — never a second
  // row for a re-run, same idempotency key `start_attempt` itself relies on.
  //
  // Task 7 item 2 (pre-GA ledger, .superpowers/sdd/task-7-brief.md item 2)
  // ADJUDICATION — is_opt_in_leaderboard hardcoded FALSE (was `true`):
  // this CI fixture attempt was live in production with opt-in TRUE, which
  // put ci_test_user's "42:13" row on the REAL public "The Murph"
  // leaderboard next to genuine users — the pre-GA blocker
  // (.superpowers/sdd/progress.md's "PRE-GA LEDGER: ... (2) scope QA seeding
  // off prod / remove CI Murph entry before GA").
  //
  // Considered and rejected: (b) env-scoped seeding — this repo has ONE
  // Supabase project for both CI and production (no separate CI database to
  // scope into; confirmed by this script's own single SUPABASE_URL and the
  // ios.yml workflow seeding the same project every run,
  // .github/workflows/ios.yml:139,151) — nothing to scope into.
  // (c) a standalone cleanup script + re-seed cadence — heavier: it would
  // need to run on some cadence forever to keep re-hiding a value THIS
  // script itself keeps re-creating as visible; that's fixing the symptom
  // on a timer instead of the cause.
  //
  // Chosen: (a) is_opt_in_leaderboard=false at the source. Verified this
  // doesn't cost anything CI actually exercises, by reading BOTH consumers:
  //   - The Discover/leaderboard SCREENSHOTS (`testCatalogDiscover`,
  //     `testCatalogDiscoverDetail`, `testCatalogTopLifters`,
  //     GymSyncUITests/ScreenshotTests.swift:221-223) never touch the
  //     network at all — they launch straight into `CatalogHostView`'s
  //     `#if DEBUG` fixture screens with `UITEST_CATALOG=<id>`, which use
  //     HARDCODED `PublicWorkout`/`LeaderboardEntryRow` literals
  //     (`discoverFixtureMurph` et al, GymSyncApp/GymSync/App/
  //     CatalogHostView.swift:559-645) via each view's `catalogFixture*`
  //     init + `catalogSkipLoad = true` — the live DB is never queried, so
  //     none of these captures can depend on this row's visibility either
  //     way. No screenshot test in the repo drives the REAL
  //     `PublicWorkoutRepository.leaderboard()` fetch at all (grepped
  //     GymSyncUITests/ + GymSyncTests/ for it — zero hits).
  //   - This block's OWN verification below (console.log of time_seconds/
  //     total_volume/is_complete, :~600) reads `leaderboard_entries`
  //     directly with the service-role key, which bypasses RLS entirely —
  //     unaffected by is_opt_in_leaderboard either way.
  // The RLS policy itself (`"opt-in or owner can read workout attempts"` /
  // `"...leaderboard entries"`, 20260723000001_public_workout_repository.
  // sql:141-153: `USING (is_opt_in_leaderboard = true OR user_id =
  // auth.uid())`) keeps this row readable by the CI account itself (owner
  // path) even at opt-in=false — only OTHER real users lose visibility,
  // which is exactly the fix: the row stops appearing on the PUBLIC board
  // while remaining a fully real, trigger-computed attempt for CI's own
  // purposes.
  //
  // Applies on EVERY run, not just first creation (`false` is now baked
  // into the create body below AND enforced by an unconditional PATCH right
  // after find-or-create) — a bare "only set at INSERT" fix would leave
  // this exact regression live for anyone who already has a pre-existing
  // row from before this fix (which is precisely how the row got exposed:
  // this script previously only wrote opt-in=true at creation and never
  // revisited it on later runs).
  let [murphAttempt] = await rest(
    `workout_attempts?select=id,is_complete,is_opt_in_leaderboard&session_id=eq.${murphSession.id}&user_id=eq.${me.id}`);
  if (!murphAttempt) {
    [murphAttempt] = await rest('workout_attempts', { method: 'POST', headers: rep,
      body: JSON.stringify({
        routine_id: murphID, user_id: me.id, session_id: murphSession.id,
        is_opt_in_leaderboard: false, started_at: MURPH_ATTEMPT_SCHEDULED_FOR,
        is_complete: false,
      }) });
  } else if (murphAttempt.is_opt_in_leaderboard !== false) {
    // Self-heals a pre-existing row seeded before this fix (the live
    // production case this adjudication exists to close).
    await rest(`workout_attempts?id=eq.${murphAttempt.id}`, { method: 'PATCH',
      body: JSON.stringify({ is_opt_in_leaderboard: false }) });
    console.log(`  Murph attempt fixture: pre-existing row ${murphAttempt.id} had ` +
      `is_opt_in_leaderboard=true — corrected to false (Task 7 item 2 fix)`);
  }

  if (murphAttempt.is_complete) {
    console.log('  Murph attempt fixture: already completed, skipping');
  } else {
    // set_logs: 3 rows, one per Murph movement (100 pull-ups / 200 push-ups
    // / 300 squats logged as one unbroken set each — a seed simplification,
    // not a claim about how Murph is actually performed rep-by-rep).
    // weight=0, EXPLICIT not NULL: set_logs.weight represents ADDED load,
    // not bodyweight — these are bodyweight movements with no added load,
    // so total_volume/top_sets both honestly compute to 0 for this attempt
    // (the recompute's SUM/MAX both filter `weight IS NOT NULL`, and 0
    // satisfies that — a NULL would produce the identical 0 result, but 0
    // states "no added weight" rather than "not logged"). Documented here
    // for the same reason as the run/vest omission above: an honest
    // limitation of an added-load volume metric applied to a bodyweight
    // benchmark, not a bug.

    // START before logging — set_logs_reject_prelive rejects a log written
    // into a `scheduled` session (see the helper). `started_at` matches the
    // attempt row's own value above, so the session and the attempt agree on
    // when this workout began.
    await ensureSessionLive(murphSession, MURPH_ATTEMPT_SCHEDULED_FOR);

    const existingLogs = await rest(
      `set_logs?select=id&session_id=eq.${murphSession.id}&user_id=eq.${me.id}`);
    if (!existingLogs.length) {
      const murphExercises = FEATURED_WORKOUTS.find((w) => w.name === 'The Murph').exercises;
      const logRows = murphExercises.map((e) => ({
        id: randomUUID(), user_id: me.id, session_id: murphSession.id,
        exercise_id: bySlug[e.slug], set_index: 1,
        reps: Number(e.reps), weight: 0,
      }));
      await rest('set_logs', { method: 'POST', body: JSON.stringify(logRows) });
    }

    // in_progress -> completed: the exact transition
    // leaderboard_recompute_on_session_completion listens for (AFTER UPDATE
    // OF state), same guard shape as the streak block's own completion PATCH
    // above. The state filter still makes this a no-op (0 rows) if a prior
    // run already completed it — it just names `in_progress` now, because
    // `ensureSessionLive` above is what this session is coming from.
    await rest(`sessions?id=eq.${murphSession.id}&state=eq.in_progress`, { method: 'PATCH',
      body: JSON.stringify({ state: 'completed', completed_at: MURPH_ATTEMPT_COMPLETED_AT }) });

    const [entry] = await rest(
      `leaderboard_entries?select=time_seconds,total_volume,is_complete&attempt_id=eq.${murphAttempt.id}`);
    console.log(`  Murph attempt fixture: session ${murphSession.id}, ` +
      `time_seconds=${entry?.time_seconds ?? '?'}, total_volume=${entry?.total_volume ?? '?'}, ` +
      `is_complete=${entry?.is_complete ?? '?'}`);
  }

  // --- Phase C Task 3: seeded test campaign + CI-account join + live
  //     progress-accrual proof ------------------------------------------
  // Flow 8 (spec :862-884) + phase spec (`docs/superpowers/specs/2026-07-19-
  // campaigns-design.md:14`, "isolation mechanism per spec §3... a test
  // campaign must NOT pollute real users' active-campaign surfaces") +
  // Task 1's own Adjudication 3 (`supabase/migrations/20260728000001_
  // campaigns_schema.sql:91-111`): `is_draft=true` is the shipped isolation
  // mechanism — a draft campaign is invisible to everyone except its own
  // participants (RLS: "campaigns are globally readable unless draft"), so
  // this fixture can exist without ever surfacing on a real user's Library/
  // Home carousel query.
  //
  // Find-or-create by name (never delete-then-recreate): `campaign_
  // participants`/`campaign_progress` both carry `ON DELETE CASCADE` on
  // `campaign_id` (`20260728000001_campaigns_schema.sql:171,201`) — deleting
  // this row on every run would erase the join + any accrued progress, the
  // exact "orphan a stable cross-run reference" mistake this file's own
  // group/Murph-pack blocks above already learned to avoid. Dates are
  // recomputed and PATCHed on EVERY run (unlike the group/Murph-pack finds,
  // which only PATCH content fields) so "a real date window spanning now"
  // stays true no matter how long after the initial seed this script is
  // re-run — same "PATCH fields in place on every run" idiom as the
  // FEATURED_WORKOUTS block above, just extended to the date columns too
  // because staying "active" IS this fixture's whole point.
  //
  // `campaigns` has NO client INSERT/UPDATE/DELETE policy at all (v1 team
  // curation is service-role/SQL-only, Adjudication 1 in the same
  // migration) — this script already writes with the service-role key for
  // everything, so this insert/PATCH is exactly the shipped curation path,
  // not a bypass of anything.
  const CAMPAIGN_NAME = 'QA Test Campaign';
  const campaignCuratedIDs = [
    featuredWorkoutIDs['The Murph'],
    featuredWorkoutIDs['StrongLifts 5x5 — Workout A'],
    featuredWorkoutIDs['Hypertrophy Push Day'],
  ];
  const campaignNowWindow = {
    starts_at: new Date(Date.now() - 5 * 86400_000).toISOString(),
    ends_at: new Date(Date.now() + 20 * 86400_000).toISOString(),
  };
  let [campaign] = await rest(`campaigns?select=id&name=eq.${encodeURIComponent(CAMPAIGN_NAME)}`);
  const campaignFields = {
    name: CAMPAIGN_NAME,
    description: '[QA] Seeded test campaign — Phase C live-proof fixture. Not real content.',
    ...campaignNowWindow,
    // {"sessions":1}: the trigger's own supported keys are "sessions" or
    // "workouts_completed" (20260728000002_campaign_progress_trigger.sql:
    // 298-309) — target=1 so ONE fixture session completion below both
    // increments campaign_progress AND crosses the individual_target in the
    // same run, proving both halves of the acceptance bar (progress
    // increment + the completion system_campaign chat message) from a
    // single completed session, per this task's own "target met vs every
    // increment" reading of the trigger.
    individual_target: { sessions: 1 },
    curated_routine_ids: campaignCuratedIDs,
    is_featured: false,
    is_draft: true,
  };
  if (!campaign) {
    [campaign] = await rest('campaigns', { method: 'POST', headers: rep, body: JSON.stringify(campaignFields) });
  } else {
    await rest(`campaigns?id=eq.${campaign.id}`, { method: 'PATCH', body: JSON.stringify(campaignFields) });
  }
  console.log(`  campaign: ${CAMPAIGN_NAME} (${campaign.id}), window ${campaignNowWindow.starts_at} -> ${campaignNowWindow.ends_at}`);

  // CI-account join via SERVICE-ROLE insert. The client INSERT path is
  // correctly blocked for a draft campaign (`campaign_participants`'
  // "user joins a campaign as themselves" policy, fixed-forward twice —
  // `20260728000003` then, correctly, `20260728000004_campaign_
  // participants_draft_join_fix_v2.sql`'s header: "WITH CHECK (user_id =
  // auth.uid() AND NOT private.is_campaign_draft(campaign_id))" — closing
  // the exact bypass IMPORTANT-1 was opened for). Service-role bypasses RLS
  // entirely (same posture as every other write in this script), which is
  // the documented seeding route that migration's header points to for a
  // draft campaign's own fixture participant. Idempotent via a pre-check
  // (the table's own composite PK would 409 on a raw re-POST otherwise).
  const [existingParticipant] = await rest(
    `campaign_participants?select=campaign_id&campaign_id=eq.${campaign.id}&user_id=eq.${me.id}`);
  if (!existingParticipant) {
    await rest('campaign_participants', { method: 'POST',
      body: JSON.stringify({ campaign_id: campaign.id, user_id: me.id }) });
  }
  console.log(`  campaign_participants: ${me.username} joined (${existingParticipant ? 'already' : 'this run'})`);

  // Fixture session completions — same "walk it through for real via a
  // genuine scheduled -> completed transition" idiom as the streak/Murph
  // blocks above, so the REAL `campaign_progress_on_session_completion`
  // trigger computes campaign_progress itself (never hand-written).
  // `routine_id` = The Murph (a member of `campaignCuratedIDs` above) so the
  // trigger's `NEW.routine_id = ANY(c.curated_routine_ids)` predicate
  // matches. Fixed, deterministic timestamps (never `now()`) as each
  // session's natural key, same reasoning as MURPH_ATTEMPT_SCHEDULED_FOR
  // above — the state filter on the completion PATCH (`in_progress`, per the
  // three-step start -> log -> complete order the Murph block above
  // documents) makes every run after the first a no-op (0 rows), because a
  // completed session is neither re-started nor re-completed, so the trigger
  // fires EXACTLY once per session regardless of how many times this script
  // re-runs, even if a much later re-run has since PATCHed the campaign's
  // own starts_at/ends_at window forward past these fixed completed_ats —
  // the accrual already happened and is not re-derived from the campaign's
  // current window on every read (same "this session's own completed_at
  // decided membership once, at the one moment the trigger runs" contract
  // the trigger's own header documents, `20260728000002:77-87`).
  //
  // TWO sessions (Fix wave 1): the second exists for the post-
  // 20260728000005 live re-proof — the draft gate migration needed a
  // FRESH trigger firing to verify against (session 1's completion had
  // already fired, pre-fix, and can never re-fire). On a fresh database
  // both complete in order; on the live database session 2 provided the
  // post-fix crossing (after a one-time, ad-hoc service-role reset of the
  // QA campaign's own campaign_progress row — our test artifact — so the
  // completion genuinely re-crossed the {"sessions":1} target; documented
  // in task-3-report.md's Fix wave 1 transcript, deliberately NOT part of
  // this script: an in-script progress reset would re-cross the target on
  // every run, which is exactly the repeated-firing shape idempotency
  // exists to prevent).
  const CAMPAIGN_FIXTURE_SESSIONS = [
    { scheduledFor: '2026-07-19T15:00:00.000Z', completedAt: '2026-07-19T15:45:00.000Z' },
    { scheduledFor: '2026-07-19T18:00:00.000Z', completedAt: '2026-07-19T18:45:00.000Z' },
  ];
  const murphRoutineID = featuredWorkoutIDs['The Murph'];

  for (const fx of CAMPAIGN_FIXTURE_SESSIONS) {
    let [progressSession] = await rest(
      `sessions?select=id,state&organizer_id=eq.${me.id}&routine_id=eq.${murphRoutineID}` +
      `&scheduled_for=eq.${encodeURIComponent(fx.scheduledFor)}`);
    if (!progressSession) {
      [progressSession] = await rest('sessions', { method: 'POST', headers: rep,
        body: JSON.stringify({
          organizer_id: me.id, routine_id: murphRoutineID, state: 'scheduled',
          scheduled_for: fx.scheduledFor,
        }) });
    }

    await rest('session_participants', { method: 'POST',
      headers: { Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify({
        session_id: progressSession.id, user_id: me.id,
        check_in_state: 'ready', check_in_at: fx.scheduledFor,
      }) });

    // One real set_log per session so volume_lifted accrues a nonzero,
    // honest number (back-squat, 5 reps @ 135 lbs = 675) rather than 0 —
    // same "weight IS NOT NULL" shape the trigger's own volume SUM
    // requires (20260728000002_campaign_progress_trigger.sql:256-261).
    // START before logging, same trigger, same reason as the Murph block.
    await ensureSessionLive(progressSession, fx.scheduledFor);

    const existingProgressLogs = await rest(
      `set_logs?select=id&session_id=eq.${progressSession.id}&user_id=eq.${me.id}`);
    if (!existingProgressLogs.length) {
      await rest('set_logs', { method: 'POST', body: JSON.stringify([{
        id: randomUUID(), user_id: me.id, session_id: progressSession.id,
        exercise_id: bySlug['back-squat'], set_index: 1, reps: 5, weight: 135,
      }]) });
    }

    await rest(`sessions?id=eq.${progressSession.id}&state=eq.in_progress`, { method: 'PATCH',
      body: JSON.stringify({ state: 'completed', completed_at: fx.completedAt }) });
  }

  const [progressRow] = await rest(
    `campaign_progress?select=sessions_completed,workouts_completed,volume_lifted&campaign_id=eq.${campaign.id}&user_id=eq.${me.id}`);
  console.log(`  campaign_progress: sessions_completed=${progressRow?.sessions_completed ?? '?'}, ` +
    `workouts_completed=${progressRow?.workouts_completed ?? '?'}, volume_lifted=${progressRow?.volume_lifted ?? '?'}`);

  // --- weekly goal: I2, home-v3-production plan/brief-integration.md ------
  // `app-tab-home` renders the goal strip's INVITATION when `me` (the
  // account CI actually signs in as and unit-tests as) has no
  // `weekly_goals` row for the current week — this block gives it a real
  // one so the capture shows a genuine muscle-sets reading instead.
  //
  // NOTE on production visibility, per this file's own header (:27-36):
  // this row is genuinely live in the shared Supabase project, not an
  // isolated test copy — and it is inert for real users the same way every
  // other fixture above is: scoped to one account by `user_id`, and RLS
  // ("owner reads own weekly goal", `20260906000001_weekly_goals.sql`)
  // means nobody else can read it.
  //
  // week_start, computed at RUN TIME (this step runs on every screenshot
  // job, and the week rolls) with the SAME rule `WeekMath.startOfWeek` uses
  // in Swift — the device calendar's week, honouring `firstWeekday` — not
  // ISO. The CI simulator's locale is en_US, whose first day is SUNDAY, so
  // `currentWeekStartSunday` below mirrors that in UTC (Node has no
  // Foundation `Calendar`); this can skew by a few hours right at a
  // Saturday/Sunday-midnight boundary, the same honestly-accepted skew
  // every other UTC-stamped fixture in this file already carries, and it
  // does not cross a week boundary any other time.
  //
  // Upserts on `(user_id, week_start)` — the table's own PK — rather than
  // this file's usual delete-then-insert: every OTHER week's row is real
  // goal history this script must not touch (unlike every table above,
  // which this account owns exclusively). A mid-week re-run converges to
  // the same row.
  //
  // `kind`/`params` match `HomeV2Fixtures.coachTargets` (CHEST/BACK/LEGS
  // 12, ARMS 8, `targetSource: "routines"`) — the same four targets the
  // catalog's own muscle-sets fixture renders — so this account's shape
  // agrees with the catalog frames. `done` is deliberately NOT written
  // here: `LiveWeeklyGoalRepository.progress(for:)` computes it from this
  // account's real completed sessions, which is the whole point of a LIVE
  // repository read rather than a second fixture.
  const weekStart = currentWeekStartSunday();
  await rest('weekly_goals', { method: 'POST',
    headers: { Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({
      user_id: me.id,
      week_start: weekStart,
      kind: 'muscle_sets',
      source: 'coach',
      params: { muscleTargets: { chest: 12, back: 12, legs: 12, arms: 8 },
               targetSource: 'routines' },
    }) });
  console.log(`  weekly goal: muscle_sets for week ${weekStart}`);

  console.log('\ndone — QA fixture world seeded (idempotent).');
}
main().catch((e) => { console.error('Fatal:', e.message); process.exit(1); });
