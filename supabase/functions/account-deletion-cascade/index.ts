// index.ts — account-deletion-cascade Edge Function. App Store 5.1.1:
// permanently deletes the CALLING user's own account and all data FK'd to
// it. DESTRUCTIVE — see the FK-graph citations below and
// .superpowers/sdd/task-3-report.md for the full table-by-table map.
//
// Design mirrors push-dispatcher/index.ts and livekit-token/index.ts:
// handleRequest() takes its dependencies as plain parameters and never
// touches Deno.env or the network directly — only the `if
// (import.meta.main)` block at the bottom wires real dependencies
// (supabase-js, real env vars, global fetch) and calls Deno.serve.
//
// Auth model (livekit-token's pattern, NOT push-dispatcher's): the caller
// is an arbitrary end user, authenticated via their own Supabase JWT
// (jwt.ts, verified locally against the project's JWKS). `userId` is taken
// ONLY from the verified token's `sub` claim — there is no user-id request
// parameter anywhere in this function, so a caller can never delete anyone
// but themselves. The actual deletes run through a service-role
// SupabaseClient (bypasses RLS, required to touch every table regardless of
// ownership policy), but WHO gets deleted is decided exclusively by the
// verified identity, before the service-role client is ever consulted.
//
// ============================================================
// The FK graph, and why this function is short
// ============================================================
// Every table in this schema that references `profiles(id)` does so with
// either ON DELETE CASCADE or ON DELETE SET NULL — grepped exhaustively
// across supabase/migrations/ (`REFERENCES profiles`, `REFERENCES
// auth.users`); there is not one RESTRICT/NO ACTION FK into profiles in
// this schema, and not one BEFORE/AFTER DELETE trigger anywhere in
// supabase/migrations/ that could block or alter a cascading delete.
// `profiles.id REFERENCES auth.users(id) ON DELETE CASCADE`
// (20260709000001_create_profiles.sql:2) means a single
// `auth.admin.deleteUser(userId)` call cascades the profiles row, which in
// turn CASCADEs/SET NULLs through literally everything else:
//
//   ON DELETE CASCADE (deleted outright — this user's own data):
//     friendships.user_id/friend_id, gyms.user_id, set_logs.user_id,
//     routines.owner_id (+ routine_exercises via routine_id CASCADE),
//     routine_proposals.proposer_id, routine_proposal_votes.user_id,
//     chat_message_reactions.user_id, chat_read_state.user_id,
//     group_members.user_id, session_participants.user_id,
//     personal_records.user_id, session_duration_edits.edited_by,
//     push_devices.user_id, notification_prefs.user_id, push_queue.user_id,
//     user_settings.user_id, soundboard_favorites.user_id,
//     user_streaks.user_id, session_kudos.sender_id/recipient_id,
//     user_reports.reporter_id/reported_user_id,
//     blocked_users.blocker_id/blocked_id.
//
//   ON DELETE SET NULL (survives, reference cleared):
//     chat_messages.author_id — THE tombstone. "NULL = system" is the
//     existing convention (create_chat.sql:5 comment; reaffirmed by
//     is_blocked's NULL-author handling, 20260721000001 lines 124-134) —
//     the client's ChatMessage.isSystem == (authorID == nil)
//     (GymSyncApp/GymSync/Models/ChatMessage.swift:74) already renders any
//     NULL-author row without crashing. IMPORTANT CAVEAT (flagged, not
//     silently papered over — out of this function's scope to fix, Swift
//     UI work belongs to Task 4): there is no "Deleted User" string
//     anywhere in the client. A tombstoned row (real body text, author_id
//     now NULL) renders via ChatView.systemMessageView
//     (Features/Social/ChatView.swift:568-602) as a centered, unattributed
//     system-style notice — visually indistinguishable from a genuine
//     system announcement, not a labeled "Deleted User" bubble. The body
//     text and message itself survive intact either way, which is what
//     this function is responsible for.
//     sessions.current_turn_user_id, sessions.edited_by.
//
// None of the above needs a single explicit DELETE/UPDATE statement here —
// Postgres performs all of it atomically as part of the one
// deleteAuthUser() call. Writing them out again in this function would be
// redundant with (and a drift risk against) the FK constraints that are
// the actual source of truth.
//
// ============================================================
// What this function DOES have to do explicitly
// ============================================================
// 1. Storage avatar object — not a SQL row, Storage API needs an explicit
//    remove() call. Deterministic path (StorageService.uploadUserAvatar,
//    GymSyncApp/GymSync/Services/StorageService.swift:81-82):
//    `users/{lowercased user id}.jpg`.
//
// 2. Ownership handoff for groups.created_by / sessions.organizer_id /
//    session_series.organizer_id — the one place the FK graph above would
//    do the WRONG thing. All three are NOT NULL + ON DELETE CASCADE with no
//    tombstone/system profile in this schema (verified: no `ON DELETE SET
//    NULL` variant exists for any of the three — contrast with
//    chat_messages.author_id above, which does). Left alone, deleting a
//    group's creator or a session's organizer would CASCADE-delete the
//    ENTIRE group/session — its chat_messages (group_id NOT NULL + CASCADE,
//    create_chat.sql:3), its session_kudos, its routine_proposals — even
//    though other members/participants are still actively using it. That
//    directly violates the product law this function exists to satisfy
//    (master spec §6.2: "Sessions/groups the user was a member of get
//    tombstoned deleted_user references ... preserving shared records").
//    So: before the terminal delete, hand ownership of any such
//    group/session/series to another remaining member/participant, IF one
//    exists. If none exists (the user is the sole member/participant), the
//    resource is exclusively theirs — nothing shared to preserve, and the
//    natural CASCADE is correct and desired (matches the spec's explicit
//    "owned routines" cascade-and-delete treatment).
//
//    CLOSED GAP: an earlier version of this function reassigned
//    groups.created_by without checking group_members.role — since admin
//    powers key off role='admin' (20260710000002_create_groups.sql:68-100
//    — is_group_admin(), "admin updates roles", "admin can update/delete
//    group"), NOT created_by, a departing sole-admin could leave the
//    handed-off group permanently unmanageable. Fixed: ownedGroups() now
//    prefers an existing admin among the remaining members when picking a
//    replacement (falling back to any member), and reassignGroupOwner()
//    unconditionally promotes the new owner to role='admin' after the
//    created_by handoff (idempotent no-op if they already are one). This
//    is orthogonal to, and does not touch, the pre-existing "self-leave or
//    admin removes" DELETE policy on group_members, which still lets a
//    sole admin voluntarily leave (not delete their account) with no
//    reassignment — that is unrelated user-initiated behavior, not this
//    function's concern.
//
//    Sessions and session_series have no group_members-style role concept
//    (session_participants: session_id, user_id, turn_order, check_in_state,
//    check_in_at, check_in_method, late_minutes, burpees_owed — no `role`
//    column, 20260709000006_create_sessions.sql:18-24 +
//    20260712000001_sessions_phase3_columns.sql:9-13; session_series has no
//    membership table of its own at all, only group_id) — organizer_id
//    reassignment alone is sufficient for both.

import { createClient, type SupabaseClient } from "@supabase/supabase-js";
import { JwksCache, verifySupabaseJwt } from "./jwt.ts";

export interface OwnedGroup {
  groupId: string;
  /** Another group_members row's user_id, or null if the user is the sole member. */
  replacementOwnerId: string | null;
}

export interface OrganizedSession {
  sessionId: string;
  /** Another session_participants row's user_id, or null if the user is the sole participant. */
  replacementOrganizerId: string | null;
}

export interface OrganizedSeries {
  seriesId: string;
  /** Another member of the series' group, or null if the user is the sole member. */
  replacementOrganizerId: string | null;
}

/**
 * The minimal Postgrest/Storage/Admin surface this function needs. Kept as
 * our own interface (rather than typing against SupabaseClient directly) so
 * test.ts can supply a plain-object fake with zero supabase-js dependency —
 * mirrors push-dispatcher/index.ts's QueueClient and livekit-token's
 * Gateway.
 */
export interface DeletionGateway {
  ownedGroups(userId: string): Promise<OwnedGroup[]>;
  reassignGroupOwner(groupId: string, newOwnerId: string): Promise<void>;
  organizedSessions(userId: string): Promise<OrganizedSession[]>;
  reassignSessionOrganizer(sessionId: string, newOrganizerId: string): Promise<void>;
  organizedSeries(userId: string): Promise<OrganizedSeries[]>;
  reassignSeriesOrganizer(seriesId: string, newOrganizerId: string): Promise<void>;
  /** No-op (not an error) if the user never uploaded an avatar — WHERE-scoped, idempotent. */
  removeAvatar(userId: string): Promise<void>;
  /**
   * Cascades everything else in the FK graph documented above. Must be a
   * no-op (not an error) if the user was already deleted by a prior,
   * partially-completed invocation — see the idempotency note below.
   */
  deleteAuthUser(userId: string): Promise<void>;
}

export class SupabaseDeletionGateway implements DeletionGateway {
  constructor(private client: SupabaseClient) {}

  async ownedGroups(userId: string): Promise<OwnedGroup[]> {
    const { data, error } = await this.client.from("groups").select("id").eq("created_by", userId);
    if (error) throw error;

    const out: OwnedGroup[] = [];
    for (const row of data ?? []) {
      // Prefer an existing admin over a plain member: group admin powers key
      // off group_members.role='admin' (20260710000002_create_groups.sql:68-100
      // — is_group_admin(), "admin updates roles", "admin can update/delete
      // group"), NOT groups.created_by. If an admin is available among the
      // remaining members, pick them first so the handoff never needs the
      // promotion below in the common case; 'admin' < 'member' lexically, so
      // ascending order on role already sorts any admin first.
      const { data: member, error: mErr } = await this.client
        .from("group_members")
        .select("user_id, role")
        .eq("group_id", row.id)
        .neq("user_id", userId)
        .order("role", { ascending: true }) // 'admin' sorts before 'member'
        .order("joined_at", { ascending: true })
        .limit(1)
        .maybeSingle();
      if (mErr) throw mErr;
      out.push({ groupId: row.id, replacementOwnerId: member?.user_id ?? null });
    }
    return out;
  }

  async reassignGroupOwner(groupId: string, newOwnerId: string): Promise<void> {
    const { error } = await this.client.from("groups").update({ created_by: newOwnerId }).eq("id", groupId);
    if (error) throw error;

    // Ensure the new owner can actually administer the group they just
    // inherited — created_by alone confers no privileges (see
    // ownedGroups' comment above). Idempotent no-op if newOwnerId is
    // already an admin (e.g. they were the preferred pick above).
    const { error: roleError } = await this.client
      .from("group_members")
      .update({ role: "admin" })
      .eq("group_id", groupId)
      .eq("user_id", newOwnerId);
    if (roleError) throw roleError;
  }

  async organizedSessions(userId: string): Promise<OrganizedSession[]> {
    const { data, error } = await this.client.from("sessions").select("id").eq("organizer_id", userId);
    if (error) throw error;

    const out: OrganizedSession[] = [];
    for (const row of data ?? []) {
      // turn_order ascending — Postgres sorts NULLs last on ASC by default,
      // so an unset turn_order never wins over a real one; any deterministic
      // pick is correct here (sessions have no "admin" concept to preserve).
      const { data: participant, error: pErr } = await this.client
        .from("session_participants")
        .select("user_id")
        .eq("session_id", row.id)
        .neq("user_id", userId)
        .order("turn_order", { ascending: true })
        .limit(1)
        .maybeSingle();
      if (pErr) throw pErr;
      out.push({ sessionId: row.id, replacementOrganizerId: participant?.user_id ?? null });
    }
    return out;
  }

  async reassignSessionOrganizer(sessionId: string, newOrganizerId: string): Promise<void> {
    const { error } = await this.client.from("sessions").update({ organizer_id: newOrganizerId }).eq(
      "id",
      sessionId,
    );
    if (error) throw error;
  }

  async organizedSeries(userId: string): Promise<OrganizedSeries[]> {
    const { data, error } = await this.client.from("session_series").select("id, group_id").eq(
      "organizer_id",
      userId,
    );
    if (error) throw error;

    const out: OrganizedSeries[] = [];
    for (const row of data ?? []) {
      const { data: member, error: mErr } = await this.client
        .from("group_members")
        .select("user_id")
        .eq("group_id", row.group_id)
        .neq("user_id", userId)
        .order("joined_at", { ascending: true })
        .limit(1)
        .maybeSingle();
      if (mErr) throw mErr;
      out.push({ seriesId: row.id, replacementOrganizerId: member?.user_id ?? null });
    }
    return out;
  }

  async reassignSeriesOrganizer(seriesId: string, newOrganizerId: string): Promise<void> {
    const { error } = await this.client.from("session_series").update({ organizer_id: newOrganizerId }).eq(
      "id",
      seriesId,
    );
    if (error) throw error;
  }

  async removeAvatar(userId: string): Promise<void> {
    const path = `users/${userId.toLowerCase()}.jpg`;
    const { error } = await this.client.storage.from("avatars").remove([path]);
    // Storage's remove() does not error on a path that never existed (a
    // user who never set an avatar) — but log-and-continue defensively
    // rather than let a transient Storage-API hiccup block the far more
    // important auth-user deletion below. Not fatal to the overall request.
    if (error) {
      console.warn(`account-deletion-cascade: avatar removal failed for ${userId}: ${errMessage(error)}`);
    }
  }

  async deleteAuthUser(userId: string): Promise<void> {
    const { error } = await this.client.auth.admin.deleteUser(userId);
    if (error) {
      // Idempotency: a retry after a crash between deleteAuthUser()
      // succeeding and the HTTP response reaching the caller would find the
      // auth user already gone. Every other step in this function is
      // naturally WHERE-scoped/no-op on a missing row; the admin API is the
      // one call that errors instead, so that's normalized here rather than
      // surfaced as a failure.
      const status = (error as { status?: number }).status;
      if (status === 404 || /not.?found/i.test(error.message ?? "")) {
        console.warn(`account-deletion-cascade: auth user ${userId} already deleted (idempotent no-op)`);
        return;
      }
      throw error;
    }
  }
}

export interface DeletionResult {
  userId: string;
  groupsReassigned: number;
  sessionsReassigned: number;
  seriesReassigned: number;
}

function errMessage(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}

/**
 * The orchestration core, deps-injected so test.ts never touches a network
 * or a live Supabase project — mirrors push-dispatcher's dispatchBatch.
 * Order matters: ownership handoff MUST happen before deleteAuthUser (the
 * whole point is to keep groups.created_by/sessions.organizer_id/
 * session_series.organizer_id pointed at a surviving user before the CASCADE
 * that would otherwise fire on the current owner fires). Avatar removal has
 * no ordering dependency on anything else and could move freely, but runs
 * last-before-delete so a Storage hiccup (logged, non-fatal — see
 * removeAvatar above) never prevents the ownership handoff from completing
 * on a retry.
 */
export async function runAccountDeletion(gateway: DeletionGateway, userId: string): Promise<DeletionResult> {
  const result: DeletionResult = { userId, groupsReassigned: 0, sessionsReassigned: 0, seriesReassigned: 0 };

  for (const g of await gateway.ownedGroups(userId)) {
    if (g.replacementOwnerId) {
      await gateway.reassignGroupOwner(g.groupId, g.replacementOwnerId);
      result.groupsReassigned++;
    }
    // else: sole member — no other group to preserve; the group CASCADEs
    // away naturally when deleteAuthUser() runs below.
  }

  for (const s of await gateway.organizedSessions(userId)) {
    if (s.replacementOrganizerId) {
      await gateway.reassignSessionOrganizer(s.sessionId, s.replacementOrganizerId);
      result.sessionsReassigned++;
    }
  }

  for (const sr of await gateway.organizedSeries(userId)) {
    if (sr.replacementOrganizerId) {
      await gateway.reassignSeriesOrganizer(sr.seriesId, sr.replacementOrganizerId);
      result.seriesReassigned++;
    }
  }

  await gateway.removeAvatar(userId);

  // The terminal delete — cascades everything documented in the FK-graph
  // comment at the top of this file.
  await gateway.deleteAuthUser(userId);

  return result;
}

export interface HandleRequestDeps {
  gateway: DeletionGateway;
  jwksCache: JwksCache;
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

/**
 * Auth: the caller's own Supabase JWT, verified locally (jwt.ts) — never a
 * service-role bearer match (push-dispatcher's model) and never a
 * client-supplied user-id parameter. `verified.sub` is the ONLY source of
 * the id that gets deleted.
 */
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
    console.warn(`account-deletion-cascade: JWT verification failed: ${errMessage(err)}`);
    return jsonResponse(401, { error: "unauthorized", reason: "invalid_token" });
  }

  console.log(`account-deletion-cascade: starting deletion for user ${userId}`);

  try {
    const result = await runAccountDeletion(deps.gateway, userId);
    console.log(
      `account-deletion-cascade: complete for ${userId} — groupsReassigned=${result.groupsReassigned} ` +
        `sessionsReassigned=${result.sessionsReassigned} seriesReassigned=${result.seriesReassigned}`,
    );
    return jsonResponse(200, result);
  } catch (err) {
    console.error(`account-deletion-cascade: deletion failed for ${userId}: ${errMessage(err)}`);
    return jsonResponse(500, { error: "internal_error" });
  }
}

if (import.meta.main) {
  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceRoleKey);

  // SUPABASE_JWKS_URL may not be provisioned in every environment — fall
  // back to constructing it from SUPABASE_URL, which is always set (same
  // fallback as livekit-token/index.ts).
  const jwksUrl = Deno.env.get("SUPABASE_JWKS_URL") ?? `${supabaseUrl}/auth/v1/.well-known/jwks.json`;

  const deps: HandleRequestDeps = {
    gateway: new SupabaseDeletionGateway(supabase),
    jwksCache: new JwksCache(jwksUrl, fetch),
  };

  Deno.serve((req) => handleRequest(req, deps));
}
