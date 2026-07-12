#!/usr/bin/env node
/**
 * Uploads soundboard WAV assets to Supabase storage and seeds soundboard_sounds table.
 *
 * Uses .env.local for SUPABASE_URL and SUPABASE_SECRET_KEY.
 * Idempotent: upserts storage files and database rows.
 *
 * Usage: node scripts/seed_soundboard.js
 */

const fs = require('fs');
const path = require('path');

// Parse .env.local
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
};

const soundDefinitions = [
  {
    slug: 'airhorn',
    display_name: 'Airhorn',
    filename: 'airhorn.wav',
    duration_ms: 1200,
  },
  {
    slug: 'lets-go',
    display_name: "Let's go",
    filename: 'lets-go.wav',
    duration_ms: 800,
  },
  {
    slug: 'ding',
    display_name: 'Ding',
    filename: 'ding.wav',
    duration_ms: 1000,
  },
  {
    slug: 'boo',
    display_name: 'Boo',
    filename: 'boo.wav',
    duration_ms: 1000,
  },
];

(async () => {
  console.log('Seeding soundboard assets...\n');

  for (const sound of soundDefinitions) {
    try {
      const wavPath = path.join(__dirname, '..', '.superpowers', 'soundboard', sound.filename);
      if (!fs.existsSync(wavPath)) {
        throw new Error(`WAV file not found: ${wavPath}`);
      }

      const wavBuffer = fs.readFileSync(wavPath);

      // Step 1: Upload WAV to storage
      console.log(`  [${sound.slug}] Uploading to storage...`, '');
      const storageUrl = `${SUPABASE_URL}/storage/v1/object/soundboard/${sound.slug}.wav`;
      const storageRes = await fetch(storageUrl, {
        method: 'PUT',
        headers: {
          ...headers,
          'Content-Type': 'audio/wav',
          'x-upsert': 'true',
        },
        body: wavBuffer,
      });

      if (!storageRes.ok) {
        const errBody = await storageRes.text();
        throw new Error(`Storage upload failed: ${storageRes.status} ${errBody}`);
      }
      console.log('OK');

      // Step 2: Upsert soundboard_sounds row
      console.log(`  [${sound.slug}] Upserting row in soundboard_sounds...`, '');
      const dbUrl = `${SUPABASE_URL}/rest/v1/soundboard_sounds?on_conflict=slug`;
      const dbRes = await fetch(dbUrl, {
        method: 'POST',
        headers: {
          ...headers,
          'Content-Type': 'application/json',
          Prefer: 'resolution=merge-duplicates',
        },
        body: JSON.stringify({
          slug: sound.slug,
          display_name: sound.display_name,
          storage_path: `${sound.slug}.wav`,
          duration_ms: sound.duration_ms,
        }),
      });

      if (!dbRes.ok) {
        const errBody = await dbRes.text();
        throw new Error(`DB upsert failed: ${dbRes.status} ${errBody}`);
      }
      console.log('OK');
    } catch (err) {
      console.error(`ERROR [${sound.slug}]:`, err.message);
      process.exit(1);
    }
  }

  console.log('\nVerifying soundboard_sounds table...');
  try {
    const verifyRes = await fetch(
      `${SUPABASE_URL}/rest/v1/soundboard_sounds?select=slug,storage_path,duration_ms&order=slug`,
      {
        method: 'GET',
        headers: {
          ...headers,
          Accept: 'application/json',
        },
      }
    );

    if (!verifyRes.ok) {
      throw new Error(`Verification query failed: ${verifyRes.status}`);
    }

    const rows = await verifyRes.json();
    console.log(`  Found ${rows.length} rows:`);
    for (const row of rows) {
      console.log(`    - ${row.slug}: storage_path=${row.storage_path}, duration=${row.duration_ms}ms`);
    }

    if (rows.length !== 4) {
      throw new Error(`Expected 4 rows, got ${rows.length}`);
    }
  } catch (err) {
    console.error('Verification failed:', err.message);
    process.exit(1);
  }

  console.log('\nSeeding complete!');
})().catch(e => {
  console.error('Fatal error:', e.message);
  process.exit(1);
});
