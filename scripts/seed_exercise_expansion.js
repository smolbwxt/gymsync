#!/usr/bin/env node
// Seed the exercise-catalog expansion (2026-08): 144 swarm-curated common
// movements with verified YouTube demo IDs, plus demo backfills for 9
// existing rows. Idempotent: inserts skip existing slugs, backfills only
// fill NULL demo_youtube_id. Data: scripts/data/exercise_expansion_2026_08.json
// Usage: node scripts/seed_exercise_expansion.js [--dry-run]
const fs = require('fs');
const path = require('path');
const { Client } = require('pg');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const url = /SUPABASE_DB_URL=(.+)/.exec(env)[1].trim();
const dryRun = process.argv.includes('--dry-run');

const data = JSON.parse(fs.readFileSync(path.join(__dirname, 'data', 'exercise_expansion_2026_08.json'), 'utf8'));

const CATEGORIES = new Set(['compound', 'isolation']);
const EQUIPMENT = new Set(['barbell', 'dumbbell', 'cable', 'machine', 'bodyweight', 'kettlebell']);
const MUSCLES = new Set(['back', 'biceps', 'calves', 'chest', 'core', 'glutes', 'hamstrings', 'lats',
  'quads', 'rear_delts', 'shoulders', 'triceps', 'forearms', 'traps', 'obliques', 'lower_back']);
const YT_ID = /^[A-Za-z0-9_-]{11}$/;

(async () => {
  const client = new Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  await client.connect();
  let inserted = 0, skippedExisting = 0, rejected = 0, backfilled = 0;
  try {
    for (const ex of data.newExercises) {
      const problems = [];
      if (!CATEGORIES.has(ex.category)) problems.push(`category ${ex.category}`);
      if (!EQUIPMENT.has(ex.equipment)) problems.push(`equipment ${ex.equipment}`);
      if (!MUSCLES.has(ex.primary_muscle)) problems.push(`primary_muscle ${ex.primary_muscle}`);
      const secondaries = (ex.secondary_muscles || []).filter(m => MUSCLES.has(m));
      if (!/^[a-z0-9-]+$/.test(ex.slug)) problems.push(`slug ${ex.slug}`);
      if (problems.length) { console.log(`REJECT ${ex.name}: ${problems.join(', ')}`); rejected++; continue; }
      const ytid = ex.youtubeId && YT_ID.test(ex.youtubeId) ? ex.youtubeId : null;
      if (dryRun) { inserted++; continue; }
      const res = await client.query(
        `INSERT INTO exercises (id, name, slug, category, primary_muscle, secondary_muscles, equipment, default_unit, is_user_defined, demo_youtube_id)
         SELECT gen_random_uuid(), $1, $2, $3, $4, $5, $6, 'lbs', false, $7
         WHERE NOT EXISTS (SELECT 1 FROM exercises WHERE slug = $2 OR lower(name) = lower($1))`,
        [ex.name, ex.slug, ex.category, ex.primary_muscle, secondaries, ex.equipment, ytid]);
      if (res.rowCount === 1) inserted++; else { skippedExisting++; console.log(`SKIP (exists) ${ex.slug}`); }
    }
    for (const b of data.backfill) {
      if (!b.youtubeId || !YT_ID.test(b.youtubeId)) continue;
      if (dryRun) { backfilled++; continue; }
      const res = await client.query(
        `UPDATE exercises SET demo_youtube_id = $1 WHERE slug = $2 AND demo_youtube_id IS NULL`,
        [b.youtubeId, b.slug]);
      backfilled += res.rowCount;
    }
    console.log(`${dryRun ? '[DRY RUN] ' : ''}inserted ${inserted}, skipped-existing ${skippedExisting}, rejected ${rejected}, backfilled ${backfilled}`);
  } finally {
    await client.end();
  }
})().catch(e => { console.error(e.message); process.exit(1); });
