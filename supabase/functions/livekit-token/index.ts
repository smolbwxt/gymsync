// index.ts — livekit-token Edge Function. Mints a short-lived, room-scoped
// LiveKit access token for a Supabase-authenticated user who is a
// participant in a session whose state currently permits voice (Dossier
// §A.1/§B.2).
//
// Design mirrors push-dispatcher/index.ts: handleRequest() takes its
// dependencies as plain parameters and never touches Deno.env or the
// network directly — only the `if (import.meta.main)` block at the bottom
// wires real dependencies (supabase-js, real env vars, global fetch) and
// calls Deno.serve. Unlike push-dispatcher (one trusted service-role
// caller), this function authenticates an arbitrary end user: the caller's
// own Supabase JWT (forwarded automatically by supabase-swift's
// `functions.invoke`) is verified locally against the project's JWKS
// (jwt.ts) rather than via a service-role bearer match.
//
// The crypto-heavy pieces (JWT verification, LiveKit token minting) are
// real jwt.ts code in both production and tests — only the Postgrest calls
// (Gateway) are faked in tests, same split as push-dispatcher's
// QueueClient vs. its real ApnsClient.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { JwksCache, mintLiveKitToken, verifySupabaseJwt } from "./jwt.ts";

/**
 * The minimal Postgrest surface livekit-token needs. Kept as our own
 * interface (rather than typing against SupabaseClient directly) so
 * test.ts can supply a plain-object fake with zero supabase-js dependency —
 * mirrors push-dispatcher/index.ts's QueueClient.
 */
export interface Gateway {
  isParticipant(sessionId: string, userId: string): Promise<boolean>;
  /** Returns null if the session doesn't exist. */
  getSessionState(sessionId: string): Promise<string | null>;
  /** Returns null if no profile row exists (shouldn't happen once isParticipant is true — profiles(id) is a FK on session_participants.user_id — but never assumed). */
  getUsername(userId: string): Promise<string | null>;
}

export class SupabaseGateway implements Gateway {
  constructor(private client: SupabaseClient) {}

  async isParticipant(sessionId: string, userId: string): Promise<boolean> {
    const { data, error } = await this.client.rpc("is_session_participant", {
      p_session_id: sessionId,
      p_user_id: userId,
    });
    if (error) throw error;
    return Boolean(data);
  }

  async getSessionState(sessionId: string): Promise<string | null> {
    const { data, error } = await this.client
      .from("sessions")
      .select("state")
      .eq("id", sessionId)
      .maybeSingle();
    if (error) throw error;
    return data?.state ?? null;
  }

  async getUsername(userId: string): Promise<string | null> {
    const { data, error } = await this.client
      .from("profiles")
      .select("username")
      .eq("id", userId)
      .maybeSingle();
    if (error) throw error;
    return data?.username ?? null;
  }
}

export interface HandleRequestDeps {
  gateway: Gateway;
  jwksCache: JwksCache;
  liveKitApiKey: string;
  liveKitApiSecret: string;
  liveKitUrl: string;
  /** Defaults to 900s (15 min) inside mintLiveKitToken when omitted. */
  ttlSeconds?: number;
}

/**
 * The 5 voice-eligible session states (Dossier §A.1, verified against the
 * `sessions.state` check constraint, 20260709000006_create_sessions.sql:
 * 'scheduled'|'lobby_open'|'editing'|'voting'|'locked'|'in_progress'|
 * 'completed'|'abandoned' — voice is scoped to the 5 listed here; the other
 * 3 are pre-session/terminal states where no room should exist).
 */
export const VOICE_ELIGIBLE_STATES = ["lobby_open", "editing", "voting", "locked", "in_progress"] as const;
type VoiceEligibleState = (typeof VOICE_ELIGIBLE_STATES)[number];

function isVoiceEligibleState(state: string): state is VoiceEligibleState {
  return (VOICE_ELIGIBLE_STATES as readonly string[]).includes(state);
}

function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function extractBearerToken(header: string | null): string | null {
  if (!header) return null;
  const match = /^Bearer (.+)$/.exec(header);
  return match ? match[1] : null;
}

export async function handleRequest(req: Request, deps: HandleRequestDeps): Promise<Response> {
  const bearerToken = extractBearerToken(req.headers.get("Authorization"));
  if (!bearerToken) {
    return jsonResponse(401, { error: "unauthorized", reason: "missing_token" });
  }

  let userId: string;
  try {
    const verified = await verifySupabaseJwt(bearerToken, {
      jwksCache: deps.jwksCache,
      audience: "authenticated",
    });
    userId = verified.sub;
  } catch (err) {
    console.warn(`livekit-token: JWT verification failed: ${errMessage(err)}`);
    return jsonResponse(401, { error: "unauthorized", reason: "invalid_token" });
  }

  let sessionId: string;
  try {
    const body = await req.json();
    if (typeof body?.session_id !== "string" || body.session_id.length === 0) {
      return jsonResponse(400, { error: "bad_request", reason: "missing_session_id" });
    }
    sessionId = body.session_id;
  } catch {
    return jsonResponse(400, { error: "bad_request", reason: "invalid_json" });
  }

  try {
    const isParticipant = await deps.gateway.isParticipant(sessionId, userId);
    if (!isParticipant) {
      return jsonResponse(403, { error: "forbidden", reason: "not_participant" });
    }

    const state = await deps.gateway.getSessionState(sessionId);
    if (!state || !isVoiceEligibleState(state)) {
      return jsonResponse(403, { error: "forbidden", reason: "ineligible_state" });
    }

    // Guaranteed to resolve once isParticipant is true (session_participants.user_id
    // FKs to profiles(id)) — the userId fallback is defense-in-depth, not an
    // expected path.
    const username = (await deps.gateway.getUsername(userId)) ?? userId;
    // Canonicalize casing: iOS sends UUID.uuidString (UPPERCASE), the DB and
    // web clients use lowercase. The room name must be identical for every
    // caller or clients silently land in different rooms (final-review I1).
    const room = `session:${sessionId.toLowerCase()}`;

    const token = await mintLiveKitToken({
      apiKey: deps.liveKitApiKey,
      apiSecret: deps.liveKitApiSecret,
      identity: userId,
      name: username,
      grant: { room, roomJoin: true, canPublish: true, canSubscribe: true },
      ttlSeconds: deps.ttlSeconds,
    });

    return jsonResponse(200, { token, url: deps.liveKitUrl });
  } catch (err) {
    console.error(`livekit-token: handler failed for session ${sessionId}: ${errMessage(err)}`);
    return jsonResponse(500, { error: "internal_error" });
  }
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // SUPABASE_JWKS_URL may not be provisioned in every environment — fall
  // back to constructing it from SUPABASE_URL, which is always set.
  const jwksUrl = Deno.env.get("SUPABASE_JWKS_URL") ?? `${supabaseUrl}/auth/v1/.well-known/jwks.json`;

  const deps: HandleRequestDeps = {
    gateway: new SupabaseGateway(supabase),
    jwksCache: new JwksCache(jwksUrl, fetch),
    liveKitApiKey: Deno.env.get("LIVEKIT_API_KEY")!,
    liveKitApiSecret: Deno.env.get("LIVEKIT_API_SECRET")!,
    liveKitUrl: Deno.env.get("LIVEKIT_URL")!,
  };

  Deno.serve((req) => handleRequest(req, deps));
}
