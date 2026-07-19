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
 *   node scripts/cleanup_storage_orphans.js [--apply] [--bucket <name>]
 *
 * Default is a dry run (report only, zero deletes) — pass --apply to
 * actually remove orphans. --bucket restricts to one bucket (chat-images,
 * chat-audio, or avatars); omit to scan all three.
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
 * full paths relative to the bucket root. Folders are entries whose `id` is
 * null (Supabase Storage's convention for a pseudo-directory listing). */
async function listAllFiles(bucket) {
  const files = [];
  async function walk(prefix) {
    const entries = await listLevel(bucket, prefix);
    for (const entry of entries) {
      const fullPath = prefix ? `${prefix}/${entry.name}` : entry.name;
      if (entry.id === null) {
        await walk(fullPath);
      } else {
        files.push(fullPath);
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
    },
  });
  const apply = values.apply;
  const bucketFilter = values.bucket;
  console.log(`Storage orphan scan starting${apply ? ' (--apply: WILL DELETE)' : ' (dry run: report only)'}`);

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

    for (const plan of plans) {
      const files = await listAllFiles(plan.bucket);
      const orphans = files.filter(plan.isOrphan);
      console.log(`\n${plan.bucket}: ${files.length} object(s), ${orphans.length} orphan(s)`);
      for (const o of orphans) console.log(`  ORPHAN  ${plan.bucket}/${o}`);
      totalOrphans += orphans.length;
      if (apply && orphans.length > 0) {
        await deleteObjects(plan.bucket, orphans);
        console.log(`  deleted ${orphans.length} object(s) from ${plan.bucket}`);
      }
    }
  } finally {
    await db.end();
  }

  console.log(`\nDone. ${totalOrphans} orphan(s) found${apply ? ' and deleted' : ' (dry run — pass --apply to delete)'}.`);
}

main().catch(e => { console.error(e.message); process.exit(1); });
