#!/usr/bin/env node
// Seeds the second CI test account used as the counterpart in friend/group tests.
// Swift tests never sign in as this user; they only target its username/id.
// Usage: node scripts/create_second_test_user.js
const fs = require('fs');
const path = require('path');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = k => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const url = get('SUPABASE_URL');
const serviceKey = get('SUPABASE_SECRET_KEY');
const password = get('SUPABASE_DB_PASSWORD');

const headers = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
  'Content-Type': 'application/json',
};

(async () => {
  // Step 1: create the auth user via admin API
  const res = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      email: 'ci-tests-2@gymsync.app',
      password,
      email_confirm: true,
    }),
  });
  const body = await res.json();
  if (!res.ok) {
    if (body.message && body.message.includes('already been registered')) {
      console.log('User ci-tests-2@gymsync.app already exists — skipping auth creation.');
      // Look up the existing user to get their ID
      const listRes = await fetch(`${url}/auth/v1/admin/users?email=ci-tests-2%40gymsync.app`, {
        headers,
      });
      const listBody = await listRes.json();
      if (!listRes.ok) throw new Error(`${listRes.status}: ${JSON.stringify(listBody)}`);
      const users = listBody.users || listBody;
      const existing = Array.isArray(users) ? users.find(u => u.email === 'ci-tests-2@gymsync.app') : null;
      if (!existing) throw new Error('Could not find existing user by email');
      const userId = existing.id;
      console.log('Existing ci_test_user_2 id:', userId);

      // Upsert the profile row
      const profRes = await fetch(`${url}/rest/v1/profiles`, {
        method: 'POST',
        headers: {
          ...headers,
          Prefer: 'resolution=ignore-duplicates',
        },
        body: JSON.stringify({ id: userId, username: 'ci_test_user_2' }),
      });
      if (!profRes.ok) {
        const profBody = await profRes.json();
        throw new Error(`Profile insert failed: ${profRes.status}: ${JSON.stringify(profBody)}`);
      }
      console.log('Profile row ensured for ci_test_user_2');
      return;
    }
    throw new Error(`${res.status}: ${JSON.stringify(body)}`);
  }

  const userId = body.id;
  console.log('ci_test_user_2 id:', userId);

  // Step 2: insert the profile row
  const profRes = await fetch(`${url}/rest/v1/profiles`, {
    method: 'POST',
    headers: {
      ...headers,
      Prefer: 'resolution=ignore-duplicates',
    },
    body: JSON.stringify({ id: userId, username: 'ci_test_user_2' }),
  });
  if (!profRes.ok) {
    const profBody = await profRes.json();
    throw new Error(`Profile insert failed: ${profRes.status}: ${JSON.stringify(profBody)}`);
  }
  console.log('Profile row created for ci_test_user_2');
})().catch(e => { console.error(e.message); process.exit(1); });
