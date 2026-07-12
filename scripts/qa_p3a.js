// Phase 3a QA driver: acts as ci_test_user_2 (RLS-faithful password auth).
// Usage:
//   node scripts/qa_p3a.js sessions                      # list my sessions + states
//   node scripts/qa_p3a.js join <ROOMCODE>               # join session by code
//   node scripts/qa_p3a.js checkin <SESSION_ID>          # check in (traveling_override)
//   node scripts/qa_p3a.js proposals <SESSION_ID>        # list proposals
//   node scripts/qa_p3a.js vote <PROPOSAL_ID> <approve|veto>
const fs = require('fs');

const env = {};
for (const line of fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2];
}
const BASE = env.SUPABASE_URL;
const KEY = env.SUPABASE_PUBLISHABLE_KEY;

async function signIn() {
  const auth = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: 'ci-tests-2@gymsync.app',
      password: env.SUPABASE_DB_PASSWORD,
    }),
  }).then((r) => r.json());
  if (!auth.access_token) throw new Error('sign-in failed: ' + JSON.stringify(auth));
  return {
    uid: auth.user.id,
    H: { apikey: KEY, Authorization: `Bearer ${auth.access_token}`, 'Content-Type': 'application/json' },
  };
}

async function main() {
  const [action, arg1, arg2] = process.argv.slice(2);
  const { uid, H } = await signIn();
  const get = (p) => fetch(`${BASE}/rest/v1/${p}`, { headers: H }).then((r) => r.json());

  if (action === 'sessions') {
    const mine = await get(`session_participants?user_id=eq.${uid}&select=session_id,check_in_state,late_minutes,burpees_owed`);
    for (const p of mine) {
      const [s] = await get(`sessions?id=eq.${p.session_id}&select=id,state,scheduled_for,room_code`);
      console.log(`${p.session_id} state=${s?.state} sched=${s?.scheduled_for} code=${s?.room_code ?? '-'} me=${p.check_in_state} late=${p.late_minutes} burpees=${p.burpees_owed}`);
    }

  } else if (action === 'join') {
    const res = await fetch(`${BASE}/rest/v1/rpc/join_session_by_code`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ p_code: arg1.toUpperCase() }),
    });
    const body = await res.text();
    if (!res.ok) throw new Error('join failed: ' + body);
    console.log('joined session:', body);

  } else if (action === 'checkin') {
    const res = await fetch(
      `${BASE}/rest/v1/session_participants?session_id=eq.${arg1}&user_id=eq.${uid}`, {
        method: 'PATCH',
        headers: { ...H, Prefer: 'return=representation' },
        body: JSON.stringify({
          check_in_state: 'ready',
          check_in_at: new Date().toISOString(),
          check_in_method: 'traveling_override',
        }),
      }).then((r) => r.json());
    console.log('checked in:', JSON.stringify(res));

  } else if (action === 'proposals') {
    const rows = await get(`routine_proposals?session_id=eq.${arg1}&order=created_at.asc&select=id,proposal_type,status,payload,proposer_id`);
    for (const p of rows) {
      console.log(`${p.id} [${p.status}] ${p.proposal_type} by ${p.proposer_id === uid ? 'me' : 'them'} payload=${JSON.stringify(p.payload)}`);
    }

  } else if (action === 'vote') {
    const res = await fetch(`${BASE}/rest/v1/routine_proposal_votes`, {
      method: 'POST',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({ proposal_id: arg1, user_id: uid, vote: arg2 }),
    }).then((r) => r.json());
    console.log('voted:', JSON.stringify(res));

  } else if (action === 'advance') {
    // advance the turn (as current lifter or organizer): node qa_p3a.js advance SESSION_ID
    const res = await fetch(`${BASE}/rest/v1/rpc/advance_turn`, {
      method: 'POST', headers: H,
      body: JSON.stringify({ p_session_id: arg1 }),
    });
    const body = await res.text();
    if (!res.ok) throw new Error('advance failed: ' + body);
    console.log('turn advanced; new current lifter:', body);

  } else if (action === 'logset') {
    // log a set in a session: node qa_p3a.js logset SESSION_ID REPS WEIGHT [penalty]
    const exercises = await get(`exercises?select=id,name&order=name.asc&limit=1`);
    const isPenalty = process.argv[6] === 'penalty';
    const row = await fetch(`${BASE}/rest/v1/set_logs`, {
      method: 'POST', headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({
        id: crypto.randomUUID(), session_id: arg1, user_id: uid,
        exercise_id: exercises[0].id, set_index: 1,
        reps: parseInt(arg2 ?? '5', 10), weight: parseFloat(process.argv[5] ?? '100'),
        is_penalty: isPenalty, is_failed: false,
      }),
    }).then((r) => r.json());
    console.log(`logged ${isPenalty ? 'PENALTY ' : ''}set:`, JSON.stringify(row));

  } else if (action === 'cheat') {
    // attempt to zero own burpees (should be BLOCKED by guard): node qa_p3a.js cheat SESSION_ID
    const res = await fetch(
      `${BASE}/rest/v1/session_participants?session_id=eq.${arg1}&user_id=eq.${uid}`, {
        method: 'PATCH', headers: { ...H, Prefer: 'return=representation' },
        body: JSON.stringify({ burpees_owed: 0 }),
      });
    const body = await res.text();
    console.log(res.ok ? '⚠️ CHEAT SUCCEEDED (guard failed!): ' + body
                       : '✅ cheat blocked: ' + body);

  } else {
    throw new Error('usage: sessions | join CODE | advance SID | logset SID REPS WT [penalty] | cheat SID | checkin SESSION_ID | proposals SESSION_ID | vote PROPOSAL_ID approve|veto');
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
