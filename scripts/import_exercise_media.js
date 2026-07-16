#!/usr/bin/env node
/**
 * Imports the Task 3 expansion pack into the live `exercises` catalog and
 * mirrors media (two JPEGs per exercise) into the `exercise-media` storage
 * bucket (GymSync Phase E, Task 4).
 *
 * Source: free-exercise-db (github.com/yuhonas/free-exercise-db), per the
 * pack's own `_meta` block (dataset dump URL + image base URL + license).
 * Media shape: TWO JPEGs per exercise (start/end position), uploaded to
 * `exercise-media/<slug>/0.jpg` and `<slug>/1.jpg`. `demo_video_url` is set
 * to frame 0's public URL only after BOTH frames are confirmed uploaded —
 * frame 1 is derived by convention in the app.
 *
 * Pass 1 (expand): insert pack exercises whose slug is not yet in the live
 * catalog. Never touches identity fields of existing rows.
 *
 * Pass 2 (backfill): for every `exercises` row with demo_video_url IS NULL,
 * resolve a dataset entry — pack rows via their pre-verified `match_key`;
 * the original 30 rows via `bestMatch` against the full dataset dump (Task
 * 2 helper). ALL original-30 resolutions (not just the ones needing work
 * this run) are written to scripts/exercise_media_map.json for human
 * review — near-tie / low-confidence matches are flagged `needsReview` and
 * skipped (left NULL) rather than silently auto-accepted.
 *
 * Usage:
 *   node scripts/import_exercise_media.js [--dry-run] [--pack <path>]
 *
 * Requires SUPABASE_URL + SUPABASE_SECRET_KEY (service role) in .env.local.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');
const { bestMatch, scoreMatch, normalizeName } = require('./lib/exercise_match.js');

// --- env + REST helpers (mirrors scripts/seed_qa_fixtures.js) --------------
const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = (k) => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const SUPABASE_URL = get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = get('SUPABASE_SECRET_KEY');
if (!SUPABASE_URL || !SUPABASE_SECRET_KEY) {
  console.error('Missing SUPABASE_URL or SUPABASE_SECRET_KEY in .env.local'); process.exit(1);
}
const headers = {
  apikey: SUPABASE_SECRET_KEY, Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  'Content-Type': 'application/json',
};
async function rest(pathAndQuery, opts = {}) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${pathAndQuery}`, {
    ...opts, headers: { ...headers, ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error(`${pathAndQuery}: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}
const rep = { Prefer: 'return=representation' };

async function storageUpload(objectPath, buffer, contentType) {
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/exercise-media/${objectPath}`, {
    method: 'POST',
    headers: {
      apikey: SUPABASE_SECRET_KEY,
      Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
      'Content-Type': contentType,
      'x-upsert': 'true',
    },
    body: buffer,
  });
  if (!res.ok) throw new Error(`upload ${objectPath}: ${res.status} ${await res.text()}`);
}

function publicUrl(slug) {
  return `${SUPABASE_URL}/storage/v1/object/public/exercise-media/${slug}/0.jpg`;
}

// --- tiny concurrency limiter (no deps): caps real in-flight I/O at N,
// with a small stagger between dispatches to stay polite to the CDN. -------
function createLimiter(concurrency, staggerMs = 60) {
  let active = 0;
  const queue = [];
  function pump() {
    if (active >= concurrency || queue.length === 0) return;
    active++;
    const { fn, resolve, reject } = queue.shift();
    fn().then(resolve, reject).finally(() => {
      active--;
      setTimeout(pump, staggerMs);
    });
  }
  return function limit(fn) {
    return new Promise((resolve, reject) => { queue.push({ fn, resolve, reject }); pump(); });
  };
}

// --- equipment vocabulary bridge (free-exercise-db -> our catalog vocab) ---
// exercise_match.js's equipmentEquals is a straight string-equality check;
// the two vocabularies use different words for the same thing, so we
// normalize the dataset side before scoring (same mapping Task 3 used when
// authoring the pack by hand).
function mapDatasetEquipment(raw) {
  const n = normalizeName(raw);
  if (n === 'body only') return 'bodyweight';
  if (n === 'e z curl bar') return 'barbell';
  return n;
}

function buildCandidates(datasetList) {
  return datasetList.map((entry) => ({
    name: entry.name,
    equipment: mapDatasetEquipment(entry.equipment),
    target: (entry.primaryMuscles && entry.primaryMuscles[0]) || '',
    _entry: entry,
  }));
}

/** Resolve one "original" catalog row against the full dataset via bestMatch,
 * additionally computing the runner-up score (bestMatch itself only returns
 * the winner) so near-ties can be flagged for human review. */
function resolveOriginal(row, candidates) {
  const ours = { name: row.name, equipment: row.equipment, primaryMuscle: row.primary_muscle };
  const primary = bestMatch(ours, candidates);
  if (!primary) return { match_key: null, score: null, unmatched: true };

  let runnerUp = null;
  for (const c of candidates) {
    if (c === primary.candidate) continue;
    const s = scoreMatch(ours, c);
    if (!runnerUp || s > runnerUp.score) runnerUp = { candidate: c, score: s };
  }
  const round = (n) => Math.round(n * 10000) / 10000;
  const needsReview = primary.score < 0.9 || (runnerUp && (primary.score - runnerUp.score) <= 0.05);
  const result = {
    match_key: primary.candidate._entry.id,
    score: round(primary.score),
    needsReview: !!needsReview,
  };
  if (needsReview && runnerUp) {
    result.runnerUp = { match_key: runnerUp.candidate._entry.id, score: round(runnerUp.score) };
  }
  return result;
}

async function main() {
  const { values } = parseArgs({
    options: {
      'dry-run': { type: 'boolean', default: false },
      pack: { type: 'string', default: 'scripts/exercise_packs/expansion_v1.json' },
    },
  });
  const dryRun = values['dry-run'];
  const packPath = path.resolve(values.pack);
  console.log(`Import run starting${dryRun ? ' (--dry-run: zero writes)' : ' (LIVE)'}`);
  console.log(`  pack: ${packPath}`);

  // --- load pack + dataset -------------------------------------------------
  const packRaw = JSON.parse(fs.readFileSync(packPath, 'utf8'));
  const meta = packRaw.find((e) => e && e._meta)._meta;
  const packEntries = packRaw.filter((e) => !(e && e._meta));
  console.log(`  pack entries: ${packEntries.length} (+_meta: dataset=${meta.dataset})`);

  console.log(`  fetching dataset dump...`);
  const datasetRes = await fetch(meta.dataset);
  if (!datasetRes.ok) throw new Error(`dataset fetch failed: ${datasetRes.status}`);
  const datasetList = await datasetRes.json();
  const datasetById = new Map(datasetList.map((e) => [e.id, e]));
  console.log(`  dataset: ${datasetList.length} exercises loaded`);
  const imageBaseUrl = meta.image_base_url;

  const packSlugSet = new Set(packEntries.map((e) => e.slug));
  const packBySlug = new Map(packEntries.map((e) => [e.slug, e]));

  // --- Pass 1: expand -------------------------------------------------------
  const existing = await rest('exercises?select=id,slug,name,category,primary_muscle,secondary_muscles,equipment,demo_video_url');
  const existingSlugSet = new Set(existing.map((e) => e.slug));
  const newPackRows = packEntries.filter((e) => !existingSlugSet.has(e.slug));
  const alreadyInCatalog = packEntries.length - newPackRows.length;
  console.log(`\n--- Pass 1: expand ---`);
  console.log(`  ${newPackRows.length} new, ${alreadyInCatalog} already in catalog (skipped, no identity update)`);

  let insertedRows = [];
  for (let i = 0; i < newPackRows.length; i++) {
    const e = newPackRows[i];
    const body = {
      name: e.name,
      slug: e.slug,
      category: e.category,
      primary_muscle: e.primary_muscle,
      secondary_muscles: e.secondary_muscles || [],
      equipment: e.equipment,
      default_unit: 'lbs',
      is_user_defined: false,
    };
    console.log(`  [insert ${i + 1}/${newPackRows.length}] ${e.slug} (${e.name})`);
    if (!dryRun) {
      const [created] = await rest('exercises', { method: 'POST', headers: rep, body: JSON.stringify(body) });
      insertedRows.push(created);
    } else {
      insertedRows.push({ id: null, slug: e.slug, name: e.name, category: e.category,
        primary_muscle: e.primary_muscle, secondary_muscles: e.secondary_muscles || [],
        equipment: e.equipment, demo_video_url: null });
    }
  }
  const expandedCount = newPackRows.length;
  console.log(`  expanded: ${expandedCount}`);

  // Full post-expand row set (re-query live to get authoritative state; in
  // dry-run there's nothing new in the DB, so splice in the simulated rows).
  const allRows = dryRun ? existing.concat(insertedRows) : await rest('exercises?select=id,slug,name,category,primary_muscle,secondary_muscles,equipment,demo_video_url');

  // --- resolve ALL original-30 rows against the dataset (for the human-
  // reviewed map file — independent of whether they still need backfill
  // this run, so the file stays a complete, stable audit trail). Rows a
  // human has already adjudicated (`adjudicated: true` + `match_key` in the
  // existing map file) are carried forward as-is — no bestMatch recompute,
  // no needsReview gating — so a controller's decision can't be silently
  // overwritten by the next automated run. -----------------------------------
  console.log(`\n--- resolving original catalog rows (bestMatch vs dataset) ---`);
  const candidates = buildCandidates(datasetList);
  const originalRows = allRows.filter((r) => !packSlugSet.has(r.slug));
  const mapPath = path.join(__dirname, 'exercise_media_map.json');
  let existingMap = {};
  if (fs.existsSync(mapPath)) {
    try { existingMap = JSON.parse(fs.readFileSync(mapPath, 'utf8')); } catch { existingMap = {}; }
  }
  const map = {};
  for (const row of originalRows) {
    const existing = existingMap[row.slug];
    let resolution;
    let flag;
    if (existing && existing.adjudicated === true && existing.match_key) {
      resolution = existing;
      flag = 'adjudicated';
    } else {
      resolution = resolveOriginal(row, candidates);
      flag = resolution.unmatched ? 'UNMATCHED' : resolution.needsReview ? 'needsReview' : 'ok';
    }
    map[row.slug] = resolution;
    console.log(`  ${row.slug} -> ${resolution.match_key || '(none)'} score=${resolution.score} [${flag}]`);
  }
  fs.writeFileSync(mapPath, JSON.stringify(map, null, 2) + '\n');
  console.log(`  wrote ${mapPath} (${originalRows.length} entries)`);

  // --- Pass 2: backfill -----------------------------------------------------
  console.log(`\n--- Pass 2: backfill ---`);
  const toBackfill = allRows.filter((r) => r.demo_video_url == null);
  const alreadyPopulated = allRows.length - toBackfill.length;
  console.log(`  ${toBackfill.length} rows need media, ${alreadyPopulated} already populated (skip)`);

  const limit = createLimiter(5);
  let matched = 0;
  let uploadedFiles = 0;
  const needsReviewSlugs = [];
  const unmatchedSlugs = [];

  async function downloadImage(url) {
    const res = await fetch(url);
    if (!res.ok) throw new Error(`download ${url}: ${res.status}`);
    return Buffer.from(await res.arrayBuffer());
  }

  async function processRow(row, idx, total) {
    let entry;
    if (packSlugSet.has(row.slug)) {
      const packEntry = packBySlug.get(row.slug);
      entry = datasetById.get(packEntry.match_key);
      if (!entry) {
        console.log(`  [${idx}/${total}] ${row.slug}: UNMATCHED (pack match_key '${packEntry.match_key}' not found in dataset)`);
        unmatchedSlugs.push(row.slug);
        return;
      }
    } else {
      const resolution = map[row.slug];
      if (!resolution || resolution.unmatched) {
        console.log(`  [${idx}/${total}] ${row.slug}: UNMATCHED (no bestMatch candidate cleared threshold)`);
        unmatchedSlugs.push(row.slug);
        return;
      }
      if (resolution.needsReview) {
        console.log(`  [${idx}/${total}] ${row.slug}: needsReview (score ${resolution.score}${resolution.runnerUp ? `, runner-up ${resolution.runnerUp.match_key}=${resolution.runnerUp.score}` : ''}) — skipped, left NULL`);
        needsReviewSlugs.push(row.slug);
        return;
      }
      entry = datasetById.get(resolution.match_key);
      if (!entry) {
        console.log(`  [${idx}/${total}] ${row.slug}: UNMATCHED (resolved match_key '${resolution.match_key}' not found in dataset)`);
        unmatchedSlugs.push(row.slug);
        return;
      }
    }

    if (!entry.images || entry.images.length < 2) {
      console.log(`  [${idx}/${total}] ${row.slug}: UNMATCHED (dataset entry '${entry.id}' does not have 2 images)`);
      unmatchedSlugs.push(row.slug);
      return;
    }

    console.log(`  [${idx}/${total}] ${row.slug}: resolved -> ${entry.id}`);
    try {
      for (let i = 0; i < 2; i++) {
        const url = imageBaseUrl + entry.images[i];
        const buf = await limit(() => downloadImage(url));
        console.log(`    ${row.slug}/${i}.jpg: downloaded ${buf.length}B${dryRun ? ' (dry-run, not uploading)' : ''}`);
        if (!dryRun) {
          await limit(() => storageUpload(`${row.slug}/${i}.jpg`, buf, 'image/jpeg'));
          console.log(`    ${row.slug}/${i}.jpg: uploaded`);
        }
      }
    } catch (err) {
      console.log(`  [${idx}/${total}] ${row.slug}: UNMATCHED (download/upload failed: ${err.message})`);
      unmatchedSlugs.push(row.slug);
      return;
    }

    if (!dryRun) {
      await rest(`exercises?slug=eq.${encodeURIComponent(row.slug)}`, {
        method: 'PATCH', body: JSON.stringify({ demo_video_url: publicUrl(row.slug) }),
      });
      console.log(`  [${idx}/${total}] ${row.slug}: demo_video_url set`);
      uploadedFiles += 2;
    } else {
      console.log(`  [${idx}/${total}] ${row.slug}: (dry-run) would set demo_video_url`);
    }
    matched++;
  }

  await Promise.all(toBackfill.map((row, i) => processRow(row, i + 1, toBackfill.length)));

  const skipped = alreadyPopulated + needsReviewSlugs.length;
  const summary = `expanded ${expandedCount} · matched ${matched} · uploaded ${uploadedFiles}(files) · skipped ${skipped} · needsReview: [${needsReviewSlugs.join(', ')}] · UNMATCHED: [${unmatchedSlugs.join(', ')}]`;
  console.log(`\n${summary}`);
}

main().catch((e) => { console.error('Fatal:', e.message); process.exit(1); });
