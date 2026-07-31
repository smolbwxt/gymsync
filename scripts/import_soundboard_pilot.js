#!/usr/bin/env node
/**
 * Batch-imports the pilot soundboard catalog (composite v5 plate tokens):
 * for every .mp3 in a folder — clip to the 5-second cap (0.4s fade-out),
 * extract a 22-bucket RMS envelope from the CLIPPED audio, upload to the
 * `soundboard` storage bucket, and upsert its soundboard_sounds row with
 * honest durations (duration_ms = clipped, original_duration_ms = source).
 *
 * Display names come from the folder's _manifest.csv (filename,title,...)
 * when present; otherwise the filename base.
 *
 * Usage:
 *   node scripts/import_soundboard_pilot.js <folder> [--category funny]
 *
 * Requires ffmpeg + ffprobe on PATH, and SUPABASE_URL + SUPABASE_SECRET_KEY
 * in .env.local (same contract as add_sound.js). Idempotent: re-running
 * replaces files and rows by slug. Files whose name yields an empty slug
 * (non-Latin titles) are skipped with a warning rather than mangled.
 */

const fs = require('fs');
const path = require('path');
const { spawnSync } = require('child_process');

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

const argv = process.argv.slice(2);
const folder = argv.find(a => !a.startsWith('--'));
if (!folder || !fs.existsSync(folder)) {
  console.error('Usage: node scripts/import_soundboard_pilot.js <folder> [--category funny]');
  process.exit(1);
}
const catIdx = argv.indexOf('--category');
const category = catIdx >= 0 ? argv[catIdx + 1] : 'funny';

const CAP_SECONDS = 5.0;
const FADE_SECONDS = 0.4;
const ENVELOPE_BUCKETS = 22;

// ── manifest titles (minimal quoted-CSV field splitter) ─────────────────────
function csvFields(line) {
  const out = [];
  let cur = '', inQ = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (inQ) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') inQ = false;
      else cur += c;
    } else if (c === '"') inQ = true;
    else if (c === ',') { out.push(cur); cur = ''; }
    else cur += c;
  }
  out.push(cur);
  return out;
}
const titles = {};
const manifestPath = path.join(folder, '_manifest.csv');
if (fs.existsSync(manifestPath)) {
  const lines = fs.readFileSync(manifestPath, 'utf8').split(/\r?\n/).slice(1);
  for (const line of lines) {
    if (!line.trim()) continue;
    const [filename, title] = csvFields(line);
    if (filename && title) titles[filename] = title;
  }
}

// ── ffmpeg helpers ──────────────────────────────────────────────────────────
function probeSeconds(file) {
  const r = spawnSync('ffprobe', ['-v', 'quiet', '-show_entries', 'format=duration',
                                  '-of', 'csv=p=0', file], { encoding: 'utf8' });
  const s = parseFloat((r.stdout || '').trim());
  return Number.isFinite(s) ? s : null;
}

function clipTo5s(src, dest) {
  const fadeStart = CAP_SECONDS - FADE_SECONDS;
  const r = spawnSync('ffmpeg', ['-y', '-v', 'quiet', '-t', String(CAP_SECONDS), '-i', src,
                                 '-af', `afade=t=out:st=${fadeStart}:d=${FADE_SECONDS}`,
                                 '-c:a', 'libmp3lame', '-b:a', '96k', dest]);
  return r.status === 0 && fs.existsSync(dest);
}

function envelope(file) {
  const r = spawnSync('ffmpeg', ['-v', 'quiet', '-t', String(CAP_SECONDS), '-i', file,
                                 '-f', 's16le', '-ac', '1', '-ar', '8000', '-'],
                      { maxBuffer: 64 * 1024 * 1024 });
  if (r.status !== 0 || !r.stdout || r.stdout.length < 2) return null;
  const buf = r.stdout;
  const n = Math.floor(buf.length / 2);
  const per = Math.max(1, Math.floor(n / ENVELOPE_BUCKETS));
  const bars = [];
  let maxRms = 0;
  for (let b = 0; b < ENVELOPE_BUCKETS; b++) {
    const start = b * per;
    const end = b === ENVELOPE_BUCKETS - 1 ? n : Math.min(n, start + per);
    let sum = 0, count = 0;
    for (let i = start; i < end; i++) {
      const v = buf.readInt16LE(i * 2) / 32768;
      sum += v * v;
      count++;
    }
    const rms = count ? Math.sqrt(sum / count) : 0;
    bars.push(rms);
    if (rms > maxRms) maxRms = rms;
  }
  return bars.map(v => Math.max(1, Math.round(8 * Math.sqrt(v / (maxRms || 1)))));
}

// ── import loop ─────────────────────────────────────────────────────────────
const headers = {
  apikey: SUPABASE_SECRET_KEY,
  Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
};

(async () => {
  const files = fs.readdirSync(folder).filter(f => f.toLowerCase().endsWith('.mp3'));
  console.log(`Importing ${files.length} sounds from ${folder}\n`);
  const tmpDir = fs.mkdtempSync(path.join(require('os').tmpdir(), 'sbimport-'));
  let ok = 0, skipped = 0, failed = 0;

  for (const f of files) {
    const src = path.join(folder, f);
    const base = path.basename(f, '.mp3');
    const slug = base.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '');
    if (!slug) {
      console.warn(`  SKIP (non-Latin name, no slug): ${f}`);
      skipped++;
      continue;
    }
    const displayName = titles[f] || base;
    const origSeconds = probeSeconds(src);
    if (origSeconds == null) {
      console.warn(`  SKIP (unreadable): ${f}`);
      skipped++;
      continue;
    }

    // Clip only when over the cap — short sounds keep their original bytes.
    let uploadFile = src;
    const needsClip = origSeconds > CAP_SECONDS + 0.05;
    if (needsClip) {
      const dest = path.join(tmpDir, `${slug}.mp3`);
      if (!clipTo5s(src, dest)) {
        console.warn(`  FAIL (clip): ${f}`);
        failed++;
        continue;
      }
      uploadFile = dest;
    }
    const clippedSeconds = needsClip ? (probeSeconds(uploadFile) ?? CAP_SECONDS) : origSeconds;
    const bars = envelope(uploadFile);
    if (!bars) {
      console.warn(`  FAIL (envelope): ${f}`);
      failed++;
      continue;
    }

    const storagePath = `${slug}.mp3`;
    const up = await fetch(`${SUPABASE_URL}/storage/v1/object/soundboard/${storagePath}`, {
      method: 'PUT',
      headers: { ...headers, 'Content-Type': 'audio/mpeg', 'x-upsert': 'true' },
      body: fs.readFileSync(uploadFile),
    });
    if (!up.ok) {
      console.warn(`  FAIL (upload ${up.status}): ${f} ${await up.text()}`);
      failed++;
      continue;
    }

    const row = {
      slug,
      display_name: displayName,
      storage_path: storagePath,
      duration_ms: Math.round(clippedSeconds * 1000),
      original_duration_ms: Math.round(origSeconds * 1000),
      envelope: bars,
      category,
      icon: null,
    };
    const db = await fetch(`${SUPABASE_URL}/rest/v1/soundboard_sounds?on_conflict=slug`, {
      method: 'POST',
      headers: { ...headers, 'Content-Type': 'application/json', Prefer: 'resolution=merge-duplicates' },
      body: JSON.stringify(row),
    });
    if (!db.ok) {
      console.warn(`  FAIL (db ${db.status}): ${f} ${await db.text()}`);
      failed++;
      continue;
    }
    const clipNote = needsClip ? ` (clipped ${origSeconds.toFixed(1)}s → ${clippedSeconds.toFixed(1)}s)` : '';
    console.log(`  OK ${slug}${clipNote}`);
    ok++;
  }

  console.log(`\nDone: ${ok} imported, ${skipped} skipped, ${failed} failed.`);
  process.exit(failed > 0 ? 1 : 0);
})().catch(e => {
  console.error('Fatal:', e.message);
  process.exit(1);
});
