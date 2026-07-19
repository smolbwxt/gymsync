#!/usr/bin/env node
/**
 * Reliability/debt roll-up, Task 6 item 1 (docs/superpowers/specs/
 * 2026-07-18-reliability-debt-design.md §6; ledger origin:
 * .superpowers/sdd/progress.md:33 "orphaned storage object if row insert
 * fails after upload" + :43 "Follow-up candidates: storage orphan lifecycle
 * cleanup (avatars + chat images), signed-URL re-resolution for long-dwell
 * chats.").
 *
 * Finds and (with --apply) deletes storage.objects that no live DB row
 * references, in the three buckets that can accumulate them:
 *
 *   - chat-images  (path `{group_id}/{message_id}.jpg`, referenced by
 *     chat_messages.storage_path where kind='image')
 *   - chat-audio   (path `{group_id}/{message_id}.m4a`, referenced by
 *     chat_messages.storage_path where kind='audio')
 *   - avatars      (path `groups/{group_id}.jpg` or `users/{user_id}.jpg`)
 *
 * Why objects go orphaned (three real, verified sources — not speculative):
 *   1. StorageService.uploadChatImage/uploadChatAudio upload BEFORE the
 *      chat_messages row is inserted (ChatMessage.swift:254-280,
 *      282-...) — a failed/interrupted insert after a successful upload
 *      leaves the object with no referencing row, forever (no
 *      storage.objects DELETE policy exists — client-side cleanup is
 *      structurally impossible, service-role only).
 *   2. GroupRepository.deleteGroup() deletes the `groups` row, which
 *      CASCADEs chat_messages (create_chat.sql: group_id ... ON DELETE
 *      CASCADE) — every chat-images/chat-audio object for that group
 *      outlives the rows that referenced it. The group's own avatar
 *      object (avatars/groups/{id}.jpg) outlives it too.
 *   3. account-deletion-cascade/index.ts's sole-member-group path: when a
 *      deleted user was a group's only member, that group is left to
 *      CASCADE away naturally (index.ts's own comment: "the group
 *      CASCADEs away naturally when deleteAuthUser() runs below") — same
 *      orphaning as (2). account-deletion-cascade already explicitly
 *      removes the deleted USER's own avatar (removeAvatar()); it does
 *      NOT walk the group's chat-images/chat-audio/avatar objects, which
 *      is the gap this script covers.
 *
 * Deliberately NOT a cron subsystem or trigger (Task 6 brief: "do NOT
 * build a cron subsystem") — this is a manual/scheduled-externally
 * maintenance script, run the same way add_sound.js / seed_soundboard.js
 * are: by a human (or an external scheduler the ops runbook wires up
 * later) invoking it with service-role creds from .env.local.
 *
 * Usage:
 *   node scripts/cleanup_storage_orphans.js [--apply] [--bucket <name>] [--min-age-hours <n>]
 *
 * Default is a dry run (report only, zero deletes) — pass --apply to
 * actually remove orphans. --bucket restricts to one bucket (chat-images,
 * chat-audio, or avatars); omit to scan all three.
 *
 * Fix wave 1 (Task 6 review, IMPORTANT 1 — TOCTOU age guard): uploads
 * happen BEFORE the chat_messages insert (source 1 above), so an object
 * from a message that's mid-send right now — upload done, insert not yet
 * committed — looks identical to a genuine orphan at scan time. Without an
 * age floor, `--apply` racing a live send could delete a real user's
 * in-flight image/audio out from under them. Every object returned by the
 * Storage list API carries `created_at`; objects younger than
 * `--min-age-hours` (default 1 — comfortably longer than any realistic
 * insert-after-upload delay, matching the signed-URL TTL elsewhere in this
 * codebase) are excluded from the orphan set and separately counted/
 * reported as "skipped as too-recent", never deleted.
 *
 * Requires SUPABASE_URL + SUPABASE_SECRET_KEY (service role, for the
 * Storage API) + SUPABASE_DB_URL (session pooler, for the live-row query)
 * in .env.local — same trio db_query.js / seed_qa_fixtures.js use.
 */
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const { parseArgs } = require('node:util');
const { Client } = require('pg');

const env = fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8');
const get = (k) => { const m = new RegExp(`${k}=(.+)`).exec(env); return m && m[1].trim(); };
const SUPABASE_URL = get('SUPABASE_URL');
const SUPABASE_SECRET_KEY = get('SUPABASE_SECRET_KEY');
const SUPABASE_DB_URL = get('SUPABASE_DB_URL');
if (!SUPABASE_URL || !SUPABASE_SECRET_KEY || !SUPABASE_DB_URL) {
  console.error('Missing SUPABASE_URL, SUPABASE_SECRET_KEY, or SUPABASE_DB_URL in .env.local');
  process.exit(1);
}
const headers = {
  apikey: SUPABASE_SECRET_KEY, Authorization: `Bearer ${SUPABASE_SECRET_KEY}`,
  'Content-Type': 'application/json',
};

/** Lists ALL objects directly under `prefix` in `bucket` (one level — the
 * Storage list API returns folders as pseudo-entries with id===null, which
 * the caller recurses into). Paginates in case a bucket ever exceeds 1000
 * entries at one level (none do today, but this is a maintenance script
 * meant to keep working as the buckets grow). */
async function listLevel(bucket, prefix) {
  const out = [];
  let offset = 0;
  const limit = 1000;
  for (;;) {
    const res = await fetch(`${SUPABASE_URL}/storage/v1/object/list/${bucket}`, {
      method: 'POST',
      headers,
      body: JSON.stringify({
        prefix, limit, offset,
        sortBy: { column: 'name', order: 'asc' },
      }),
    });
    if (!res.ok) throw new Error(`list ${bucket}/${prefix}: ${res.status} ${await res.text()}`);
    const page = await res.json();
    out.push(...page);
    if (page.length < limit) break;
    offset += limit;
  }
  return out;
}

/** Recursively lists every FILE (not folder) object in `bucket`, returning
 * `{ path, createdAt }` pairs relative to the bucket root (`createdAt` a
 * `Date`, from the list API's `created_at` — needed for the age guard, see
 * this file's header comment). Folders are entries whose `id` is null
 * (Supabase Storage's convention for a pseudo-directory listing). */
async function listAllFiles(bucket) {
  const files = [];
  async function walk(prefix) {
    const entries = await listLevel(bucket, prefix);
    for (const entry of entries) {
      const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        await walk(fullPath);
      } else {
        files.push({ path: fullPath, createdAt: new Date(entry.created_at) });
      }
    }
  }
  await walk('');
  return files;
}

async function deleteObjects(bucket, objectPaths) {
  if (objectPaths.length === 0) return;
  const res = await fetch(`${SUPABASE_URL}/storage/v1/object/${bucket}`, {
    method: 'DELETE',
    headers,
    body: JSON.stringify({ prefixes: objectPaths }),
  });
  if (!res.ok) throw new Error(`delete ${bucket}: ${res.status} ${await res.text()}`);
}

async function main() {
  const { values } = parseArgs({
    options: {
      apply: { type: 'boolean', default: false },
      bucket: { type: 'string' },
      'min-age-hours': { type: 'string', default: '1' },
    },
  });
  const apply = values.apply;
  const bucketFilter = values.bucket;
  const minAgeHours = Number(values['min-age-hours']);
  if (!Number.isFinite(minAgeHours) || minAgeHours < 0) {
    console.error(`--min-age-hours must be a non-negative number, got: ${values['min-age-hours']}`);
    process.exit(1);
  }
  const minAgeMs = minAgeHours * 60 * 60 * 1000;
  console.log(`Storage orphan scan starting${apply ? ' (--apply: WILL DELETE)' : ' (dry run: report only)'} (min age: ${minAgeHours}h)`);

  const db = new Client({ connectionString: SUPABASE_DB_URL, ssl: { rejectUnauthorized: false } });
  await db.connect();

  let totalOrphans = 0;
  try {
    const [chatRows, groupRows, profileRows] = await Promise.all([
      db.query(`SELECT storage_path, kind FROM chat_messages WHERE storage_path IS NOT NULL`),
      db.query(`SELECT id FROM groups`),
      db.query(`SELECT id FROM profiles`),
    ]);
    const referencedImagePaths = new Set(
      chatRows.rows.filter(r => r.kind === 'image').map(r => r.storage_path));
    const referencedAudioPaths = new Set(
      chatRows.rows.filter(r => r.kind === 'audio').map(r => r.storage_path));
    const liveGroupIds = new Set(groupRows.rows.map(r => r.id));
    const liveProfileIds = new Set(profileRows.rows.map(r => r.id));

    const plans = [
      {
        bucket: 'chat-images',
        isOrphan: (objPath) => !referencedImagePaths.has(objPath),
      },
      {
        bucket: 'chat-audio',
        isOrphan: (objPath) => !referencedAudioPaths.has(objPath),
      },
      {
        bucket: 'avatars',
        isOrphan: (objPath) => {
          const m = /^groups\/([0-9a-f-]{36})\.jpg$/i.exec(objPath);
          if (m) return !liveGroupIds.has(m[1].toLowerCase());
          const u = /^users\/([0-9a-f-]{36})\.jpg$/i.exec(objPath);
          if (u) return !liveProfileIds.has(u[1].toLowerCase());
          // Unrecognized shape — do NOT treat as orphan (report, never delete
          // something this script doesn't understand).
          return false;
        },
      },
    ].filter(p => !bucketFilter || p.bucket === bucketFilter);

    const now = Date.now();
    let totalSkippedRecent = 0;

    for (const plan of plans) {
      const files = await listAllFiles(plan.bucket);
      const candidates = files.filter((f) => plan.isOrphan(f.path));
      // Age guard (Fix wave 1, IMPORTANT 1): an object that looks orphaned
      // but was created within the last `--min-age-hours` might just be
      // mid-send — upload landed, the chat_messages insert hasn't (or a
      // read-replica lag). Never treat those as orphans; count them
      // separately instead of silently dropping them from the report.
      const orphans = [];
      const skippedRecent = [];
      for (const f of candidates) {
        const ageMs = now - f.createdAt.getTime();
        // Missing/unparseable created_at (NaN) fails safe as "too-recent"
        // rather than as an orphan — an unknown age must never be treated
        // as proof of staleness when the whole point is not deleting a
        // live object.
        if (!Number.isFinite(ageMs) || ageMs < minAgeMs) {
          skippedRecent.push(f);
        } else {
          orphans.push(f);
        }
      }
      console.log(`\n${plan.bucket}: ${files.length} object(s), ${orphans.length} orphan(s), ${skippedRecent.length} skipped as too-recent`);
      for (const o of orphans) console.log(`  ORPHAN  ${plan.bucket}/${o.path}  (created ${o.createdAt.toISOString()})`);
      for (const s of skippedRecent) console.log(`  SKIP (too-recent)  ${plan.bucket}/${s.path}  (created ${s.createdAt.toISOString()})`);
      totalOrphans += orphans.length;
      totalSkippedRecent += skippedRecent.length;
      if (apply && orphans.length > 0) {
        await deleteObjects(plan.bucket, orphans.map((o) => o.path));
        console.log(`  deleted ${orphans.length} object(s) from ${plan.bucket}`);
      }
    }
    console.log(`\nDone. ${totalOrphans} orphan(s) found${apply ? ' and deleted' : ' (dry run — pass --apply to delete)'}, ${totalSkippedRecent} skipped as too-recent (< ${minAgeHours}h old).`);
  } finally {
    await db.end();
  }
}

main().catch(e => { console.error(e.message); process.exit(1); });
