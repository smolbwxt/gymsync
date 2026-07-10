#!/usr/bin/env node
// One-off: create (or reset) the CI test user via the Supabase admin API.
// Usage: node scripts/create_test_user.js <email> <password>
const fs = require('fs');
const path = require('path');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = k => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const url = get('SUPABASE_URL');
const serviceKey = get('SUPABASE_SECRET_KEY');
const [email, password] = process.argv.slice(2);

(async () => {
  const headers = { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' };
  const res = await fetch(`${url}/auth/v1/admin/users`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ email, password, email_confirm: true }),
  });
  const body = await res.json();
  if (!res.ok) throw new Error(`${res.status}: ${JSON.stringify(body)}`);
  console.log(`created test user ${body.id} (${body.email})`);
})().catch(e => { console.error(e.message); process.exit(1); });
