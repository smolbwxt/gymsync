// index.ts — clip-sweeper Edge Function (storage v1.5, 2026-08-22).
//
// The retention promise's enforcement arm: called hourly by pg_cron
// (clip_sweep_dispatch, 20260822000002_clip_retention.sql), it deletes
// form clips whose retain_until has passed — storage objects FIRST
// through the storage API (the only path that actually removes the S3
// blobs; a bare SQL delete of storage.objects orphans them), then the
// set_log_clips rows. Batch-capped; an hourly tick clears any realistic
// backlog. Auth: exact-match bearer against SUPABASE_SERVICE_ROLE_KEY,
// the same contract push-dispatcher documents — the 'push_drain_auth'
// Vault secret IS the service-role key, so reusing it needs no new
// seeding step and no new env var.
//
// Same testability shape as push-dispatcher: sweepBatch takes its
// dependencies as parameters; only the import.meta.main block wires the
// real world.

import { createClient } from "@supabase/supabase-js";

const BATCH = 200;

export interface ExpiredClipRow {
  id: string;
  storage_path: string;
}

export interface SweeperDeps {
  listExpired: (limit: number) => Promise<ExpiredClipRow[]>;
  removeObjects: (paths: string[]) => Promise<void>;
  deleteRows: (ids: string[]) => Promise<void>;
}

export async function sweepBatch(deps: SweeperDeps): Promise<{ swept: number }> {
  const expired = await deps.listExpired(BATCH);
  if (expired.length === 0) return { swept: 0 };
  // Objects first: if removal throws we keep the rows, so the next tick
  // retries — a row without a blob is a broken playback link, a blob
  // without a row is invisible garbage. Prefer retrying toward neither.
  await deps.removeObjects(expired.map((c) => c.storage_path));
  await deps.deleteRows(expired.map((c) => c.id));
  return { swept: expired.length };
}

export function authorized(req: Request, secret: string | undefined): boolean {
  if (!secret) return false;
  const header = req.headers.get("Authorization") ?? "";
  return header === `Bearer ${secret}`;
}

if (import.meta.main) {
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const secret = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

  Deno.serve(async (req) => {
    if (!authorized(req, secret)) {
      return new Response("unauthorized", { status: 401 });
    }
    const result = await sweepBatch({
      listExpired: async (limit) => {
        const { data, error } = await supabase
          .from("set_log_clips")
          .select("id, storage_path")
          .lt("retain_until", new Date().toISOString())
          .limit(limit);
        if (error) throw error;
        return (data ?? []) as ExpiredClipRow[];
      },
      removeObjects: async (paths) => {
        const { error } = await supabase.storage.from("form-clips").remove(paths);
        if (error) throw error;
      },
      deleteRows: async (ids) => {
        const { error } = await supabase.from("set_log_clips").delete().in("id", ids);
        if (error) throw error;
      },
    });
    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json" },
    });
  });
}
