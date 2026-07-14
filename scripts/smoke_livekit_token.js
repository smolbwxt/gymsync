#!/usr/bin/env node
// T5 smoke for the deployed livekit-token Edge Function (Phase 3e).
// Proves against PRODUCTION: happy path mints a correctly-shaped LiveKit
// token for a participant in a voice-eligible session; non-participant → 403;
// bad JWT → 401. RLS-faithful: users authenticate via password grant, no
// service key on the request path.
//
//   node scripts/smoke_livekit_token.js
const fs = require('fs');

const env = {};
for (const line of fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2];
}
const BASE = env.SUPABASE_URL;
const KEY = env.SUPABASE_PUBLISHABLE_KEY;

async function signIn(email) {
  const auth = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password: env.SUPABASE_DB_PASSWORD }),
  }).then((r) => r.json());
  if (!auth.access_token) throw new Error(`sign-in failed for ${email}: ${JSON.stringify(auth)}`);
  return auth;
}

function decodeJwtPayload(jwt) {
  const b64 = jwt.split('.')[1].replace(/-/g, '+').replace(/_/g, '/');
  return JSON.parse(Buffer.from(b64, 'base64').toString('utf8'));
}

const results = [];
function check(name, cond, detail) {
  results.push({ name, ok: !!cond, detail });
  console.log(`${cond ? 'PASS' : 'FAIL'}  ${name}${detail ? ` — ${detail}` : ''}`);
}

(async () => {
  const u2 = await signIn('ci-tests-2@gymsync.app');
  const H2 = { apikey: KEY, Authorization: `Bearer ${u2.access_token}`, 'Content-Type': 'application/json' };
  const uid2 = u2.user.id;
  console.log(`signed in as ci_test_user_2 (${uid2})`);

  // Fixture: a group + lobby_open session organized by user_2 (organizer is
  // auto-participant via the app's create flow; we insert the participant row
  // explicitly to be schema-faithful). Cleaned up at the end.
  const grp = await fetch(`${BASE}/rest/v1/groups`, {
    method: 'POST',
    headers: { ...H2, Prefer: 'return=representation' },
    body: JSON.stringify({ name: 'Voice Smoke Group', created_by: uid2 }),
  }).then((r) => r.json());
  if (!Array.isArray(grp) || !grp[0]) throw new Error('group create failed: ' + JSON.stringify(grp));
  const groupID = grp[0].id;

  const ses = await fetch(`${BASE}/rest/v1/sessions`, {
    method: 'POST',
    headers: { ...H2, Prefer: 'return=representation' },
    body: JSON.stringify({
      organizer_id: uid2,
      group_id: groupID,
      state: 'lobby_open',
      scheduled_for: new Date().toISOString(),
    }),
  }).then((r) => r.json());
  if (!Array.isArray(ses) || !ses[0]) throw new Error('session create failed: ' + JSON.stringify(ses));
  const sessionID = ses[0].id;

  await fetch(`${BASE}/rest/v1/session_participants`, {
    method: 'POST',
    headers: H2,
    body: JSON.stringify({ session_id: sessionID, user_id: uid2 }),
  });
  console.log(`fixture session ${sessionID} (lobby_open)`);

  const invoke = (token, body) =>
    fetch(`${BASE}/functions/v1/livekit-token`, {
      method: 'POST',
      headers: { apikey: KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });

  try {
    // 1. Happy path
    const ok = await invoke(u2.access_token, { session_id: sessionID });
    check('participant + lobby_open → 200', ok.status === 200, `status ${ok.status}`);
    const payload = await ok.json();
    check('response has token + url', !!payload.token && !!payload.url, JSON.stringify(Object.keys(payload)));
    if (payload.token) {
      const claims = decodeJwtPayload(payload.token);
      check('iss = LIVEKIT_API_KEY', claims.iss === env.LIVEKIT_API_KEY, claims.iss);
      check('sub = caller uuid', claims.sub === uid2, claims.sub);
      check('room = session:{id}', claims.video?.room === `session:${sessionID}`, claims.video?.room);
      check('roomJoin/canPublish/canSubscribe', claims.video?.roomJoin === true && claims.video?.canPublish === true && claims.video?.canSubscribe === true);
      check('TTL = 900s', claims.exp - (claims.nbf ?? claims.iat) === 900, `${claims.exp - (claims.nbf ?? claims.iat)}s`);
      check('url = LIVEKIT_URL', payload.url === env.LIVEKIT_URL, payload.url);
    }

    // 2. Non-participant → 403. The gate is is_session_participant, which
    // checks session_participants ONLY — organizers get no implicit access —
    // so a second session with no participant row is a true 403 case
    // without needing a second login (ci_test_user's password isn't in
    // .env.local).
    const ses2 = await fetch(`${BASE}/rest/v1/sessions`, {
      method: 'POST',
      headers: { ...H2, Prefer: 'return=representation' },
      body: JSON.stringify({
        organizer_id: uid2,
        group_id: groupID,
        state: 'lobby_open',
        scheduled_for: new Date().toISOString(),
      }),
    }).then((r) => r.json());
    const session2ID = ses2[0]?.id;
    if (session2ID) {
      const nonPart = await invoke(u2.access_token, { session_id: session2ID });
      check('non-participant (organizer w/o row) → 403', nonPart.status === 403, `status ${nonPart.status}`);
      await fetch(`${BASE}/rest/v1/sessions?id=eq.${session2ID}`, { method: 'DELETE', headers: H2 });
    } else {
      check('non-participant fixture created', false, JSON.stringify(ses2));
    }

    // 3. Ineligible state → 403 (organizer flips own session to completed)
    await fetch(`${BASE}/rest/v1/sessions?id=eq.${sessionID}`, {
      method: 'PATCH',
      headers: H2,
      body: JSON.stringify({ state: 'completed' }),
    });
    const ineligible = await invoke(u2.access_token, { session_id: sessionID });
    check('completed session → 403', ineligible.status === 403, `status ${ineligible.status}`);

    // 4. Bad JWT → 401
    const bad = await invoke('garbage.jwt.value', { session_id: sessionID });
    check('bad JWT → 401', bad.status === 401, `status ${bad.status}`);
  } finally {
    // Cleanup fixture rows (participants cascade with session; session then group)
    await fetch(`${BASE}/rest/v1/sessions?id=eq.${sessionID}`, { method: 'DELETE', headers: H2 });
    await fetch(`${BASE}/rest/v1/groups?id=eq.${groupID}`, { method: 'DELETE', headers: H2 });
    console.log('fixture cleaned up');
  }

  const failed = results.filter((r) => !r.ok);
  console.log(`\n${results.length - failed.length}/${results.length} checks passed`);
  process.exit(failed.length ? 1 : 0);
})().catch((e) => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
