#!/usr/bin/env node
// Ad-hoc query helper: node scripts/db_query.js "SELECT ..."
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const url = /SUPABASE_DB_URL=(.+)/.exec(env)[1].trim();

(async () => {
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();
  try {
    const res = await client.query(process.argv[2]);
    console.table(res.rows);
  } finally {
    await client.end();
  }
})().catch(e => { console.error(e.message); process.exit(1); });
