// Phase 2.5 QA driver: acts as ci_test_user_2 (RLS-faithful password auth).
// Usage: node scripts/qa_p25.js <react|image|friend-reset|friend-request>
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
  const action = process.argv[2];
  const { uid, H } = await signIn();
  const get = (path) => fetch(`${BASE}/rest/v1/${path}`, { headers: H }).then((r) => r.json());

  const memberships = await get(`group_members?user_id=eq.${uid}&select=group_id`);
  const groupID = memberships[0]?.group_id;

  if (action === 'react') {
    const latest = await get(
      `chat_messages?group_id=eq.${groupID}&author_id=neq.${uid}&deleted_at=is.null&order=created_at.desc&limit=1&select=id,body,kind`);
    if (!latest.length) throw new Error('no message from the other user to react to');
    const res = await fetch(`${BASE}/rest/v1/chat_message_reactions`, {
      method: 'POST',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({ message_id: latest[0].id, user_id: uid, emoji: '🔥' }),
    }).then((r) => r.json());
    console.log(`reacted 🔥 to [${latest[0].kind}] "${latest[0].body ?? '(image)'}":`, JSON.stringify(res));

  } else if (action === 'image') {
    const jpeg = fs.readFileSync('.superpowers/qa_test_image.jpg');
    const messageID = crypto.randomUUID();
    const path = `${groupID.toLowerCase()}/${messageID.toLowerCase()}.jpg`;
    const up = await fetch(`${BASE}/storage/v1/object/chat-images/${path}`, {
      method: 'POST',
      headers: { apikey: KEY, Authorization: H.Authorization, 'Content-Type': 'image/jpeg' },
      body: jpeg,
    });
    if (!up.ok) throw new Error('upload failed: ' + (await up.text()));
    const row = await fetch(`${BASE}/rest/v1/chat_messages`, {
      method: 'POST',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({
        id: messageID, group_id: groupID, author_id: uid,
        kind: 'image', storage_path: path,
      }),
    }).then((r) => r.json());
    console.log('image message sent:', JSON.stringify(row));

  } else if (action === 'friend-reset') {
    // Remove the existing friendship so a fresh request can be sent
    const del = await fetch(
      `${BASE}/rest/v1/friendships?or=(user_id.eq.${uid},friend_id.eq.${uid})`, {
        method: 'DELETE', headers: { ...H, Prefer: 'return=representation' },
      }).then((r) => r.json());
    console.log('removed friendships:', JSON.stringify(del));

  } else if (action === 'friend-request') {
    const smola = await get(`profiles?username=ilike.smola&select=id,username`);
    if (!smola.length) throw new Error('smola profile not found');
    const res = await fetch(`${BASE}/rest/v1/friendships`, {
      method: 'POST',
      headers: { ...H, Prefer: 'return=representation' },
      body: JSON.stringify({ user_id: uid, friend_id: smola[0].id, status: 'pending' }),
    }).then((r) => r.json());
    console.log('sent friend request to', smola[0].username, ':', JSON.stringify(res));

  } else {
    throw new Error('usage: node scripts/qa_p25.js <react|image|friend-reset|friend-request>');
  }
}

main().catch((e) => { console.error(e); process.exit(1); });
