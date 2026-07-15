#!/usr/bin/env node
/**
 * Seeds custom/seasonal routines for a user from a JSON pack — no app build.
 * Routines are user-owned rows; this inserts them for the given @username.
 *
 * Usage:
 *   node scripts/seed_routines.js <pack.json> <username>
 *
 * Pack format (see scripts/routine_packs/example.json):
 * [
 *   {
 *     "name": "12 Days of Liftmas",
 *     "exercises": [
 *       { "slug": "barbell-bench-press", "sets": 4, "reps": "8-10", "weight": "185" },
 *       { "slug": "overhead-press",      "sets": 3, "reps": "10" }
 *     ]
 *   }
 * ]
 * Exercise `slug` must match a row in the exercises table
 * (list them: node scripts/seed_routines.js --list-exercises).
 * Requires SUPABASE_URL + SUPABASE_SECRET_KEY in .env.local.
 */

const fs = require('fs');
const path = require('path');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = k => {
  const m = new RegExp(`${k}=(.+)`).exec(env);
  return m && m[1].trim();
};
const SUPABASE_URL = get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = get('SUPABASE_SECRET_KEY');
if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('Error: SUPABASE_URL or SUPABASE_SECRET_KEY not found in .env.local');
  process.exit(1);
}
const headers = {
  apikey: SUPABASE_SECRET_KEY,
  Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  'Content-Type': 'application/json',
};

async function rest(pathAndQuery, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, { headers, ...opts, headers: { ...headers, ...(opts.headers || {}) } });
  if (!res.ok) throw new Error(`${pathAndQuery}: ${res.status} ${await res.text()}`);
  // Inserts without Prefer: return=representation come back 201 with an
  // EMPTY body — res.json() on that throws "Unexpected end of JSON input"
  // (bit us mid-seed: routine 1 landed fully, the loop died before 2).
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

(async () => {
  const [, , packPath, username] = process.argv;

  if (packPath === '--list-exercises') {
    const exercises = await rest('exercises?select=slug,name,category&order=name');
    for (const e of exercises) console.log(`${e.slug}\t${e.name} (${e.category})`);
    return;
  }

  if (!packPath || !username) {
    console.error('Usage: node scripts/seed_routines.js <pack.json> <username>   (or --list-exercises)');
    process.exit(1);
  }

  const pack = JSON.parse(fs.readFileSync(packPath, 'utf8'));

  // Resolve owner (case-insensitive username lookup, matching app behavior)
  const profiles = await rest(`profiles?select=id,username&username=ilike.${encodeURIComponent(username)}`);
  if (!profiles.length) {
    console.error(`No profile found for username "${username}"`);
    process.exit(1);
  }
  const owner = profiles[0];
  console.log(`Seeding ${pack.length} routine(s) for @${owner.username} (${owner.id})\n`);

  // Resolve all referenced exercise slugs in one query
  const slugs = [...new Set(pack.flatMap(r => r.exercises.map(e => e.slug)))];
  const exercises = await rest(`exercises?select=id,slug&slug=in.(${slugs.map(encodeURIComponent).join(',')})`);
  const bySlug = Object.fromEntries(exercises.map(e => [e.slug, e.id]));
  const missing = slugs.filter(s => !bySlug[s]);
  if (missing.length) {
    console.error(`Unknown exercise slugs (check --list-exercises): ${missing.join(', ')}`);
    process.exit(1);
  }

  for (const routine of pack) {
    console.log(`  Creating "${routine.name}" (${routine.exercises.length} exercises)...`);
    const [created] = await rest('routines', {
      method: 'POST',
      headers: { Prefer: 'return=representation' },
      body: JSON.stringify({ owner_id: owner.id, name: routine.name }),
    });
    const rows = routine.exercises.map((e, i) => ({
      routine_id: created.id,
      exercise_id: bySlug[e.slug],
      position: i + 1, // 1-based (DB CHECK position >= 1)
      target_sets: e.sets ?? null,
      target_reps: e.reps != null ? String(e.reps) : null,
      target_weight: e.weight != null ? String(e.weight) : null,
    }));
    await rest('routine_exercises', { method: 'POST', body: JSON.stringify(rows) });
  }

  console.log('\nDone — routines appear in the Library on next refresh.');
})().catch(e => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
