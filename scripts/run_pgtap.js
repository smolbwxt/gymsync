#!/usr/bin/env node
// pgTAP runner: executes supabase/tests/*.sql against SUPABASE_DB_URL and reports TAP output.
// Usage: node scripts/run_pgtap.js [testfile ...]
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

function dbUrl() {
  if (process.env.SUPABASE_DB_URL) return process.env.SUPABASE_DB_URL;
  const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
  const m = /SUPABASE_DB_URL=(.+)/.exec(env);
  if (!m) throw new Error('SUPABASE_DB_URL not found in .env.local');
  return m[1].trim();
}

async function runFile(url, file) {
  const sql = fs.readFileSync(file, 'utf8');
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();
  let failures = 0;
  console.log(`\n=== ${path.basename(file)} ===`);
  try {
    const results = await client.query(sql);
    const arr = Array.isArray(results) ? results : [results];
    for (const r of arr) {
      for (const row of r.rows || []) {
        const line = Object.values(row).join(' ');
        console.log(line);
        if (/^not ok/.test(line) || /Looks like you failed/.test(line)) failures++;
      }
    }
  } catch (e) {
    console.error(`ERROR: ${e.message}`);
    failures++;
  } finally {
    await client.end();
  }
  return failures;
}

async function main() {
  const url = dbUrl();
  const testsDir = path.join(__dirname, '..', 'supabase', 'tests');
  const files = process.argv.length > 2
    ? process.argv.slice(2)
    : fs.readdirSync(testsDir).filter(f => f.endsWith('.sql')).sort().map(f => path.join(testsDir, f));
  let failures = 0;
  for (const f of files) failures += await runFile(url, f);
  console.log(failures ? `\nFAILED: ${failures} problem(s)` : '\nALL TESTS PASSED');
  process.exit(failures ? 1 : 0);
}

main().catch(e => { console.error(e); process.exit(1); });
