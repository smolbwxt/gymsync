#!/usr/bin/env node
/**
 * Adds ONE sound to the soundboard without an app build:
 * uploads the audio file to the `soundboard` storage bucket and upserts its
 * `soundboard_sounds` row. Clients pick it up on next launch (catalog is
 * fetched at runtime — nothing is shipped in the app binary).
 *
 * Usage:
 *   node scripts/add_sound.js <path-to-audio> "<Display Name>" [slug]
 *
 * Examples:
 *   node scripts/add_sound.js ~/Downloads/bell.wav "Bell"
 *   node scripts/add_sound.js sounds/hohoho.m4a "Ho Ho Ho" hohoho
 *
 * Slug defaults to the display name lowercased/kebab-cased. Re-running with
 * the same slug replaces the file and row (upsert).
 * Supported: .wav, .m4a, .mp3 (players use AVAudioPlayer — all fine).
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

const [, , filePath, displayName, slugArg] = process.argv;
if (!filePath || !displayName) {
  console.error('Usage: node scripts/add_sound.js <path-to-audio> "<Display Name>" [slug]');
  process.exit(1);
}
if (!fs.existsSync(filePath)) {
  console.error(`File not found: ${filePath}`);
  process.exit(1);
}

const ext = path.extname(filePath).toLowerCase();
const contentTypes = { '.wav': 'audio/wav', '.m4a': 'audio/mp4', '.mp3': 'audio/mpeg' };
if (!contentTypes[ext]) {
  console.error(`Unsupported extension "${ext}" — use .wav, .m4a, or .mp3`);
  process.exit(1);
}

const slug = (slugArg || displayName)
  .toLowerCase()
  .replace(/[^a-z0-9]+/g, '-')
  .replace(/^-+|-+$/g, '');
const storagePath = `${slug}${ext}`;

const headers = {
  apikey: SUPABASE_SECRET_KEY,
  Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
};

(async () => {
  console.log(`Adding sound "${displayName}" (slug: ${slug})`);

  console.log('  Uploading audio to soundboard bucket...');
  const up = await fetch(`${SUPABASE_URL}/storage/v1/object/soundboard/${storagePath}`, {
    method: 'PUT',
    headers: { ...headers, 'Content-Type': contentTypes[ext], 'x-upsert': 'true' },
    body: fs.readFileSync(filePath),
  });
  if (!up.ok) {
    console.error(`  Upload failed: ${up.status} ${await up.text()}`);
    process.exit(1);
  }

  console.log('  Upserting soundboard_sounds row...');
  const db = await fetch(`${SUPABASE_URL}/rest/v1/soundboard_sounds?on_conflict=slug`, {
    method: 'POST',
    headers: { ...headers, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' },
    body: JSON.stringify({ slug, display_name: displayName, storage_path: storagePath, duration_ms: 1000 }),
  });
  if (!db.ok) {
    console.error(`  DB upsert failed: ${db.status} ${await db.text()}`);
    process.exit(1);
  }

  console.log(`Done — "${displayName}" is live. Clients see it on next app launch.`);
})().catch(e => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
