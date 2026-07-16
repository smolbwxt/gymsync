#!/usr/bin/env node
/**
 * Seeds a deterministic, screenshot-stable world for the CI test account so
 * the app's real internal fetches return known data on every screen: a group
 * (with the account as admin member), sessions in every lifecycle state, a
 * mixed chat thread, friends (one accepted, one incoming pending request),
 * a small routine library with exercises, personal records, and one
 * published/featured routine for the Library "Featured" shelf.
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
 */
const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');

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

// Real second CI account (id/username only — Swift tests never sign in as
// it) used as the friend counterpart. Not managed by this script.
const ACCEPTED_FRIEND_USERNAME = 'ci_test_user';

// Third profile, created here if missing, used as the *pending* friend
// counterpart. `ci_test_user` is already spoken for as the accepted friend,
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
  // Publishing visibility='public' is curator-gated by RLS (routines
  // INSERT/UPDATE policies require profiles.is_curator); the service-role
  // key bypasses RLS entirely so this isn't strictly required for the
  // write to succeed, but we still flip the flag for realism and in case
  // any other code path keys off it. profiles_guard_is_curator only blocks
  // the authenticated/anon Postgres roles, not service_role, so this PATCH
  // is unaffected by that trigger.
  await rest(`profiles?id=eq.${me.id}`, { method: 'PATCH', body: JSON.stringify({ is_curator: true }) });
  await rest(`routines?owner_id=eq.${me.id}&visibility=eq.public&name=ilike.${encodeURIComponent(MARK + '%')}`, { method: 'DELETE' });
  const [featured] = await rest('routines', { method: 'POST', headers: rep,
    body: JSON.stringify({ owner_id: me.id, name: FEATURED_ROUTINE.name, visibility: 'public' }) });
  const featuredRows = FEATURED_ROUTINE.exercises.map((e, i) => ({
    routine_id: featured.id, exercise_id: bySlug[e.slug], position: i + 1,
    target_sets: e.sets, target_reps: String(e.reps),
  }));
  await rest('routine_exercises', { method: 'POST', body: JSON.stringify(featuredRows) });
  console.log(`  featured routine: ${FEATURED_ROUTINE.name}`);

  console.log('\ndone — QA fixture world seeded (idempotent).');
}
main().catch((e) => { console.error('Fatal:', e.message); process.exit(1); });
