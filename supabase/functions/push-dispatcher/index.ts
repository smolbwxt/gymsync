// index.ts — push-dispatcher Edge Function. Single entry point for draining
// push_queue and delivering via APNs. Called by the pg_cron drain schedule
// (push_drain_dispatch, 20260716000003_push_cron.sql) and by manual
// service-role invocations.
//
// Design: the actual dispatch logic (dispatchBatch) and the HTTP handler
// (handleRequest) take their dependencies as plain parameters (QueueClient /
// ApnsClient / fetch), never touching Deno.env or the network directly.
// Only the `if (import.meta.main)` block at the bottom wires those
// dependencies to the real world (supabase-js, real env vars, global
// fetch) and calls Deno.serve. This is what makes test.ts possible without
// any network access: it imports dispatchBatch/handleRequest and passes in
// fakes, never triggering the Deno.serve wiring at all.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { ApnsClient, type ApnsAlertPayload } from "./apns.ts";
import { buildNotificationPayload } from "./payloads.ts";

export interface PushQueueRow {
  id: number;
  user_id: string;
  event: string;
  payload: Record<string, unknown>;
  sent_at: string | null;
  attempts: number;
}

export interface PushDeviceRow {
  id: string;
  apns_token: string;
}

/**
 * The minimal surface push-dispatcher needs from Postgres/PostgREST. Kept
 * as our own interface (rather than typing against SupabaseClient directly)
 * so test.ts can supply a plain-object fake with zero supabase-js
 * dependency — mirrors the apns.ts injectable-fetch pattern one layer up.
 */
export interface QueueClient {
  claimBatch(limit: number): Promise<PushQueueRow[]>;
  devicesForUser(userId: string): Promise<PushDeviceRow[]>;
  deleteDevice(id: string): Promise<void>;
  markSent(id: number): Promise<void>;
}

export class SupabaseQueueClient implements QueueClient {
  constructor(private client: SupabaseClient) {}

  async claimBatch(limit: number): Promise<PushQueueRow[]> {
    const { data, error } = await this.client.rpc("claim_push_batch", { p_limit: limit });
    if (error) throw error;
    return (data ?? []) as PushQueueRow[];
  }

  async devicesForUser(userId: string): Promise<PushDeviceRow[]> {
    const { data, error } = await this.client
      .from("push_devices")
      .select("id, apns_token")
      .eq("user_id", userId);
    if (error) throw error;
    return (data ?? []) as PushDeviceRow[];
  }

  async deleteDevice(id: string): Promise<void> {
    const { error } = await this.client.from("push_devices").delete().eq("id", id);
    if (error) throw error;
  }

  async markSent(id: number): Promise<void> {
    const { error } = await this.client
      .from("push_queue")
      .update({ sent_at: new Date().toISOString() })
      .eq("id", id);
    if (error) throw error;
  }
}

export interface DispatchDeps {
  queue: QueueClient;
  apns: ApnsClient;
  fetchImpl: typeof fetch;
}

export interface DispatchResult {
  claimed: number;
  sent: number;
  retried: number;
  devicesDeleted: number;
  noDevice: number;
  /** Rows whose processing threw (e.g. a QueueClient call rejected) — left unsent, distinct from a normal APNs-driven retry. */
  failed: number;
}

const CLAIM_LIMIT = 100;

/** Renders any thrown value to a log-safe string. Never touches payload/token contents — callers only pass row/device identifiers alongside this. */
function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/**
 * Drains up to `limit` rows from push_queue and delivers each to every
 * registered device for that row's user. Does NOT re-check
 * notification_prefs — enqueue_push (20260716000001_push_schema.sql) already
 * filtered on the recipient's prefs at enqueue time; re-checking here would
 * only be correct if prefs can never change between enqueue and drain, which
 * they can, but re-filtering post-hoc is out of scope for this task (prefs
 * are a point-in-time gate at enqueue, matching the brief).
 *
 * Error isolation: a rejecting fetchImpl/QueueClient call must never abort
 * the rest of the claimed batch. Each per-device APNs send is individually
 * try/catch'd (a rejection is treated like a 5xx — row stays unsent for
 * retry). Each row's entire processing block (including its mark-sent /
 * device-delete DB calls) is also try/catch'd, so one row's unexpected
 * exception can't strand the rest of the batch — that row is simply left
 * unsent and counted under `failed`.
 */
export async function dispatchBatch(deps: DispatchDeps, limit: number = CLAIM_LIMIT): Promise<DispatchResult> {
  const { queue, apns, fetchImpl } = deps;
  const result: DispatchResult = { claimed: 0, sent: 0, retried: 0, devicesDeleted: 0, noDevice: 0, failed: 0 };

  const rows = await queue.claimBatch(limit);
  result.claimed = rows.length;

  for (const row of rows) {
    try {
      const devices = await queue.devicesForUser(row.user_id);

      if (devices.length === 0) {
        await queue.markSent(row.id);
        result.sent++;
        result.noDevice++;
        continue;
      }

      const content = buildNotificationPayload(row.event, row.payload ?? {});
      if (!content) {
        // Unknown event name — nothing sensible to render. Mark sent rather
        // than retrying forever on a payload shape this dispatcher will never
        // understand; an unrecognized event is a code/schema drift bug to fix
        // upstream, not something a retry will resolve.
        console.warn(`push-dispatcher: unknown event "${row.event}" for row ${row.id}; marking sent`);
        await queue.markSent(row.id);
        result.sent++;
        continue;
      }

      const apnsPayload: ApnsAlertPayload = {
        aps: {
          alert: { title: content.title, body: content.body },
          ...(content.category ? { category: content.category } : {}),
          ...(content.threadId ? { "thread-id": content.threadId } : {}),
        },
      };

      let shouldRetry = false;
      for (const device of devices) {
        let sendResult;
        try {
          sendResult = await apns.send(device.apns_token, apnsPayload, fetchImpl);
        } catch (err) {
          // Network failure or other rejection out of apns.send (which
          // normally resolves even for APNs error responses) — treat like a
          // 5xx: leave the row unsent for retry, don't let it take the rest
          // of the batch down with it.
          console.error(
            `push-dispatcher: send threw for row ${row.id} (event=${row.event}, device=${device.id}): ${errMessage(err)}`,
          );
          shouldRetry = true;
          continue;
        }
        if (sendResult.ok) continue;

        if (sendResult.status === 410 || sendResult.reason === "BadDeviceToken") {
          await queue.deleteDevice(device.id);
          result.devicesDeleted++;
          console.warn(
            `push-dispatcher: deleted device ${device.id} for row ${row.id} (status=${sendResult.status}, reason=${
              sendResult.reason ?? "n/a"
            })`,
          );
          continue;
        }

        if (sendResult.status === 429 || sendResult.status >= 500) {
          shouldRetry = true;
          continue;
        }

        // Any other non-ok status (e.g. a malformed-payload 400 that isn't
        // BadDeviceToken) is unexpected — leave the row unsent so it surfaces
        // in logs on retry rather than silently disappearing.
        shouldRetry = true;
      }

      if (shouldRetry) {
        result.retried++;
        continue;
      }

      await queue.markSent(row.id);
      result.sent++;
    } catch (err) {
      // Anything else that threw while processing this row (devicesForUser,
      // markSent, deleteDevice, ...) — log it, leave the row unsent, move on
      // to the next row rather than aborting the whole claimed batch.
      console.error(`push-dispatcher: row ${row.id} (event=${row.event}) failed: ${errMessage(err)}`);
      result.failed++;
    }
  }

  console.log(
    `push-dispatcher: drain complete — claimed=${result.claimed} delivered=${result.sent} retried=${result.retried} failed=${result.failed} devicesDeleted=${result.devicesDeleted} noDevice=${result.noDevice}`,
  );

  return result;
}

/**
 * Auth: exact-match bearer token against SUPABASE_SERVICE_ROLE_KEY. Both the
 * pg_cron drain (push_drain_dispatch, reading the Vault secret) and manual
 * invocations authenticate this way — there is no other caller.
 */
export async function handleRequest(
  req: Request,
  deps: DispatchDeps,
  serviceRoleKey: string,
): Promise<Response> {
  const auth = req.headers.get("Authorization");
  if (auth !== `Bearer ${serviceRoleKey}`) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { "content-type": "application/json" },
    });
  }

  try {
    const result = await dispatchBatch(deps);
    return new Response(JSON.stringify(result), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  } catch (err) {
    console.error(`push-dispatcher: handler failed: ${errMessage(err)}`);
    return new Response(JSON.stringify({ error: "internal_error" }), {
      status: 500,
      headers: { "content-type": "application/json" },
    });
  }
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  const deps: DispatchDeps = {
    queue: new SupabaseQueueClient(supabase),
    apns: new ApnsClient({
      keyId: Deno.env.get("APNS_KEY_ID")!,
      teamId: Deno.env.get("APNS_TEAM_ID")!,
      privateKeyPem: Deno.env.get("APNS_PRIVATE_KEY")!,
      topic: Deno.env.get("APNS_TOPIC")!,
    }),
    fetchImpl: fetch,
  };

  Deno.serve((req) => handleRequest(req, deps, serviceRoleKey));
}
