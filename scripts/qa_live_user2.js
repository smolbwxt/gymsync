// QA driver: acts as ci_test_user_2 via real password auth (RLS-faithful, no service key).
// Usage: node scripts/qa_live_user2.js [message text to send to first group]
const fs = require('fs');

const env = {};
for (const line of fs.readFileSync('.env.local', 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2];
}
const BASE = env.SUPABASE_URL;
const KEY = env.SUPABASE_PUBLISHABLE_KEY;

async function main() {
  const msg = process.argv.slice(2).join(' ');

  const auth = await fetch(`${BASE}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: KEY, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      email: 'ci-tests-2@gymsync.app',
      password: env.SUPABASE_DB_PASSWORD,
    }),
  }).then((r) => r.json());
  if (!auth.access_token) throw new Error('sign-in failed: ' + JSON.stringify(auth));
  const uid = auth.user.id;
  const H = { apikey: KEY, Authorization: `Bearer ${auth.access_token}`, 'Content-Type': 'application/json' };
  const get = (path) => fetch(`${BASE}/rest/v1/${path}`, { headers: H }).then((r) => r.json());

  const pending = await get(`friendships?friend_id=eq.${uid}&status=eq.pending&select=*`);
  for (const p of pending) {
    const res = await fetch(`${BASE}/rest/v1/friendships?user_id=eq.${p.user_id}&friend_id=eq.${uid}`, {
      method: 'PATCH',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({ status: 'accepted' }),
    }).then((r) => r.json());
    console.log('accepted friend request from', p.user_id, '->', JSON.stringify(res));
  }

  const friends = await get(`friendships?status=eq.accepted&or=(user_id.eq.${uid},friend_id.eq.${uid})&select=*`);
  console.log('accepted friendships:', friends.length);

  const memberships = await get(`group_members?user_id=eq.${uid}&select=group_id`);
  console.log('member of', memberships.length, 'group(s):', memberships.map((m) => m.group_id).join(', '));

  if (memberships.length && msg) {
    const sent = await fetch(`${BASE}/rest/v1/chat_messages`, {
      method: 'POST',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({
        group_id: memberships[0].group_id,
        author_id: uid,
        kind: 'text',
        body: msg,
      }),
    }).then((r) => r.json());
    console.log('sent message:', JSON.stringify(sent));
  }

  const recent = memberships.length
    ? await get(`chat_messages?group_id=eq.${memberships[0].group_id}&order=created_at.desc&limit=5&select=kind,body,author_id,created_at`)
    : [];
  console.log('last messages in group:');
  for (const m of recent.reverse()) {
    console.log(` [${m.kind}] ${m.author_id === uid ? 'me' : (m.author_id ? 'them' : 'system')}: ${m.body}`);
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
