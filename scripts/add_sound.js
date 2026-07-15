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

// Argument parsing. A `--flag`'s value is the following token UNLESS that
// token is itself a flag (or absent) — otherwise `--icon --category hype`
// reads "--category" as the icon AND swallows a positional (final-review
// follow-up f). The positional stripper and flag() below share this rule.
const argv = process.argv.slice(2);
const hasValue = (i) => argv[i + 1] !== undefined && !argv[i + 1].startsWith('--');
const positional = [];
for (let i = 0; i < argv.length; i++) {
  if (argv[i].startsWith('--')) { if (hasValue(i)) i++; continue; }
  positional.push(argv[i]);
}
const [filePath, displayName, slugArg] = positional;
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

const flag = (name) => {
  const i = argv.indexOf(`--${name}`);
  return i >= 0 && hasValue(i) ? argv[i + 1] : undefined;
};
const icon = flag('icon') ?? null;          // e.g. --icon 🥁
const category = flag('category') ?? null;  // hype|funny|fx
if (category && !['hype', 'funny', 'fx'].includes(category)) {
  console.error(`--category must be hype|funny|fx, got "${category}"`);
  process.exit(1);
}

// Real duration for PCM WAVs (replaces the hardcoded 1000; non-WAV → null):
function wavDurationMs(buf) {
  try {
    if (buf.toString('ascii', 0, 4) !== 'RIFF' || buf.toString('ascii', 8, 12) !== 'WAVE') return null;
    let off = 12, byteRate = null;
    while (off + 8 <= buf.length) {
      const id = buf.toString('ascii', off, off + 4);
      const size = buf.readUInt32LE(off + 4);
      if (id === 'fmt ') byteRate = buf.readUInt32LE(off + 16);
      if (id === 'data' && byteRate) return Math.round((size / byteRate) * 1000);
      off += 8 + size + (size % 2);
    }
    return null;
  } catch { return null; }
}

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
    body: JSON.stringify({
      slug, display_name: displayName, storage_path: storagePath,
      duration_ms: ext === '.wav' ? wavDurationMs(fs.readFileSync(filePath)) : null,
      icon, category,
    }),
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
