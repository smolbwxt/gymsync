#!/usr/bin/env node
// Delivered-event live proof for gate MAJOR-1 (fix wave 2): after
// 20260728000006 added campaign_progress to the supabase_realtime
// publication, prove a postgres_changes event actually ARRIVES on a
// subscribed channel — not merely that a DB row changed.
//
// Shape mirrors the production consumer exactly (CampaignLiveService.swift:
// 55-70): channel "campaign:{campaign_id}", postgres_changes INSERT +
// UPDATE on public.campaign_progress, filter "campaign_id=eq.{id}". The
// subscriber signs in as the CI account (ci_test_user_2 — a genuine
// participant of the seeded draft "QA Test Campaign"), because WALRUS
// delivery is per-subscriber RLS-filtered (campaign_progress's
// participant-scoped SELECT policy, 20260728000001:282-284): an event
// arriving HERE simultaneously proves publication membership AND the
// participant delivery path. The SDK difference (supabase-js here vs.
// supabase-swift in the app) is immaterial — the publication either ships
// the WAL row to Realtime or it doesn't; that is SDK-agnostic.
//
// Auth idiom: qa_live_user2.js / qa_p25.js (password auth as
// ci-tests-2@gymsync.app; RLS-faithful for the SUBSCRIBER). The increment
// TRIGGER side uses the service-role key and the fixture-session walk from
// seed_qa_fixtures.js's campaign block (session -> ready participant ->
// set_log -> scheduled->completed PATCH, so the REAL trigger fires — never
// a hand-written campaign_progress write, which RLS would reject anyway).
//
// DELIBERATELY NOT IDEMPOTENT: each run walks one fresh qualifying
// completion (unique now-based scheduled_for), adding +1 to the QA
// campaign's progress counters — this is a proof harness invoked on
// demand, not a seed; nothing anywhere asserts the QA campaign's progress
// numbers (task-3-report.md Fix wave 1 concerns), the campaign is a draft
// (invisible to real users), and the draft gate (20260728000005) means no
// chat message can result.
//
// Usage: node scripts/qa_campaign_realtime_proof.js
// Exit 0 = event observed; exit 1 = timeout (publication/delivery broken).
const fs = require('fs');
const path = require('path');
const { randomUUID } = require('node:crypto');
const { createClient } = require('@supabase/supabase-js');

const env = {};
for (const line of fs.readFileSync(path.join(__dirname, '..', '.env.local'), 'utf8').split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)=(.*)$/);
  if (m) env[m[1]] = m[2].trim();
}
const BASE = env.SUPABASE_URL;
const PUBLISHABLE = env.SUPABASE_PUBLISHABLE_KEY;
const SECRET = env.SUPABASE_SECRET_KEY;
if (!BASE || !PUBLISHABLE || !SECRET) {
  console.error('Missing SUPABASE_URL / SUPABASE_PUBLISHABLE_KEY / SUPABASE_SECRET_KEY in .env.local');
  process.exit(1);
}

const CAMPAIGN_NAME = 'QA Test Campaign';
const EVENT_TIMEOUT_MS = 25_000;

// Service-role REST helper (trigger side only) — same shape as
// seed_qa_fixtures.js's rest().
const serviceHeaders = {
  apikey: SECRET, Authorization: `Bearer ${SECRET}`, 'Content-Type': 'application/json',
};
async function serviceRest(pathAndQuery, opts = {}) {
  const res = await fetch(`${BASE}/rest/v1/${pathAndQuery}`, {
    ...opts, headers: { ...serviceHeaders, ...(opts.headers || {}) },
  });
  if (!res.ok) throw new Error(`${pathAndQuery}: ${res.status} ${await res.text()}`);
  const text = await res.text();
  return text ? JSON.parse(text) : null;
}

async function main() {
  // ── 1. Subscriber: sign in as the CI participant ─────────────────────
  const supabase = createClient(BASE, PUBLISHABLE);
  const { data: authData, error: authError } = await supabase.auth.signInWithPassword({
    email: 'ci-tests-2@gymsync.app',
    password: env.SUPABASE_DB_PASSWORD,
  });
  if (authError) throw new Error(`sign-in failed: ${authError.message}`);
  const uid = authData.user.id;
  console.log(`signed in as ci_test_user_2 (${uid})`);
  // Explicit realtime auth: WALRUS RLS-filters delivery per-subscriber by
  // this JWT; without it the socket rides the anon key and the
  // participant-scoped policy would deliver nothing.
  await supabase.realtime.setAuth(authData.session.access_token);

  // ── 2. Resolve the QA campaign AS the participant (RLS-faithful read:
  //      a draft campaign is visible to this account only because it is a
  //      participant — this lookup re-proves that path too) ─────────────
  const { data: campaigns, error: campError } = await supabase
    .from('campaigns').select('id, name, is_draft').eq('name', CAMPAIGN_NAME);
  if (campError) throw new Error(`campaign lookup failed: ${campError.message}`);
  if (!campaigns.length) throw new Error(`no visible campaign named "${CAMPAIGN_NAME}" — is the seed in place and the CI account joined?`);
  const campaign = campaigns[0];
  console.log(`campaign visible to participant: ${campaign.name} (${campaign.id}), is_draft=${campaign.is_draft}`);

  // ── 3. Subscribe (production shape: CampaignLiveService.swift:55-70) ──
  const events = [];
  let resolveEvent;
  const eventArrived = new Promise((resolve) => { resolveEvent = resolve; });
  const channel = supabase.channel(`campaign:${campaign.id}`);
  for (const event of ['INSERT', 'UPDATE']) {
    channel.on('postgres_changes', {
      event, schema: 'public', table: 'campaign_progress',
      filter: `campaign_id=eq.${campaign.id}`,
    }, (payload) => {
      events.push(payload);
      console.log(`>>> postgres_changes DELIVERED: eventType=${payload.eventType}, ` +
        `new=(sessions=${payload.new?.sessions_completed}, workouts=${payload.new?.workouts_completed}, ` +
        `volume=${payload.new?.volume_lifted})`);
      resolveEvent();
    });
  }

  await new Promise((resolve, reject) => {
    channel.subscribe((status, err) => {
      console.log(`channel status: ${status}`);
      if (status === 'SUBSCRIBED') resolve();
      if (status === 'CHANNEL_ERROR' || status === 'TIMED_OUT') {
        reject(new Error(`subscribe failed: ${status} ${err ?? ''}`));
      }
    });
  });
  // Small settle delay so the server-side postgres_changes registration is
  // fully active before the write it must observe.
  await new Promise((r) => setTimeout(r, 2000));

  // ── 4. Trigger: one fresh qualifying completion via the fixture walk
  //      (service role; seed_qa_fixtures.js campaign-block machinery) ────
  const [{ id: murphID }] = await serviceRest(`routines?select=id&name=eq.${encodeURIComponent('The Murph')}&owner_id=eq.${uid}`);
  const [{ id: squatID }] = await serviceRest('exercises?select=id&slug=eq.back-squat');
  const scheduledFor = new Date(Date.now() - 60 * 60_000).toISOString(); // unique per run
  const completedAt = new Date(Date.now() - 30 * 60_000).toISOString();

  const [session] = await serviceRest('sessions', {
    method: 'POST', headers: { Prefer: 'return=representation' },
    body: JSON.stringify({ organizer_id: uid, routine_id: murphID, state: 'scheduled', scheduled_for: scheduledFor }),
  });
  await serviceRest('session_participants', {
    method: 'POST',
    body: JSON.stringify({ session_id: session.id, user_id: uid, check_in_state: 'ready', check_in_at: scheduledFor }),
  });
  await serviceRest('set_logs', {
    method: 'POST',
    body: JSON.stringify([{ id: randomUUID(), user_id: uid, session_id: session.id, exercise_id: squatID, set_index: 1, reps: 5, weight: 135 }]),
  });
  console.log(`fixture session ${session.id}: completing (scheduled -> completed)...`);
  await serviceRest(`sessions?id=eq.${session.id}&state=eq.scheduled`, {
    method: 'PATCH', body: JSON.stringify({ state: 'completed', completed_at: completedAt }),
  });

  // ── 5. Assert the event ARRIVES, timeout-bounded ─────────────────────
  const timedOut = await Promise.race([
    eventArrived.then(() => false),
    new Promise((r) => setTimeout(() => r(true), EVENT_TIMEOUT_MS)),
  ]);

  await supabase.removeChannel(channel);
  if (timedOut) {
    console.error(`FAIL: no postgres_changes event within ${EVENT_TIMEOUT_MS}ms — publication/delivery broken`);
    process.exit(1);
  }
  console.log(`PASS: ${events.length} delivered event(s) observed on campaign:${campaign.id}`);
  process.exit(0);
}

main().catch((e) => { console.error('Fatal:', e.message); process.exit(1); });
