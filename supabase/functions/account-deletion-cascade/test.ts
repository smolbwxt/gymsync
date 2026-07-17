// test.ts — pure `deno test`. No network: every caller JWT is signed
// in-process against a throwaway EC key pair (mirrors
// livekit-token/test.ts's makeCallerAuth/cacheFor helpers, reused
// verbatim below), and all DB/Storage/Admin-API interaction is a plain
// in-memory FakeDeletionGateway (mirrors push-dispatcher's FakeQueueClient
// / livekit-token's FakeGateway). SupabaseDeletionGateway itself (the real
// supabase-js-backed implementation) is intentionally NOT unit-tested here
// — same precedent as SupabaseQueueClient/SupabaseGateway in the other two
// functions' test.ts files, which also only exercise their fakes.

import { assertEquals, assertExists, assertRejects } from "@std/assert";
import { type Jwk, type Jwks, JwksCache, verifySupabaseJwt } from "./jwt.ts";
import {
  type DeletionGateway,
  type HandleRequestDeps,
  handleRequest,
  type OrganizedSeries,
  type OrganizedSession,
  type OwnedGroup,
  runAccountDeletion,
} from "./index.ts";

// ============================================================
// Helpers (JWT signing) — verbatim pattern from livekit-token/test.ts
// ============================================================

function base64url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function generateTestEcKeyPair(kid: string): Promise<{ privateKey: CryptoKey; jwk: Jwk }> {
  const keyPair = await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, ["sign", "verify"]);
  const publicJwk = (await crypto.subtle.exportKey("jwk", keyPair.publicKey)) as JsonWebKey;
  return { privateKey: keyPair.privateKey, jwk: { ...publicJwk, kid, alg: "ES256" } };
}

async function signTestJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  privateKey: CryptoKey,
): Promise<string> {
  const headerB64 = base64url(new TextEncoder().encode(JSON.stringify(header)));
  const claimsB64 = base64url(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${headerB64}.${claimsB64}`;
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

interface CallerAuthOverrides {
  aud?: string;
  exp?: number;
}

/** Builds a valid (unless overridden) caller JWT + the matching JWKS document a JwksCache would fetch for it. */
async function makeCallerAuth(sub: string, overrides: CallerAuthOverrides = {}): Promise<{ token: string; jwks: Jwks }> {
  const kid = "test-kid-1";
  const { privateKey, jwk } = await generateTestEcKeyPair(kid);
  const nowSec = Math.floor(Date.now() / 1000);
  const claims = {
    sub,
    aud: overrides.aud ?? "authenticated",
    exp: overrides.exp ?? nowSec + 3600,
    iat: nowSec,
  };
  const token = await signTestJwt({ alg: "ES256", kid }, claims, privateKey);
  return { token, jwks: { keys: [jwk] } };
}

function jwksFetch(jwks: Jwks): typeof fetch {
  return () => Promise.resolve(new Response(JSON.stringify(jwks), { status: 200 }));
}

function cacheFor(jwks: Jwks): JwksCache {
  return new JwksCache("https://fake.local/auth/v1/.well-known/jwks.json", jwksFetch(jwks));
}

function req(authorization?: string): Request {
  const headers: Record<string, string> = {};
  if (authorization !== undefined) headers["Authorization"] = authorization;
  return new Request("https://fn.local/account-deletion-cascade", { method: "POST", headers });
}

// ============================================================
// FakeDeletionGateway — records every call for assertions, and can model
// a mutating store (state removed as it's "reassigned"/"deleted") so
// idempotency can be exercised across two full runAccountDeletion() calls.
// ============================================================

class FakeDeletionGateway implements DeletionGateway {
  calls: string[] = [];
  groupReassignments: Array<{ groupId: string; newOwnerId: string }> = [];
  sessionReassignments: Array<{ sessionId: string; newOrganizerId: string }> = [];
  seriesReassignments: Array<{ seriesId: string; newOrganizerId: string }> = [];
  avatarRemovedFor: string[] = [];
  authUsersDeleted: string[] = [];

  constructor(
    private groups: OwnedGroup[] = [],
    private sessions: OrganizedSession[] = [],
    private series: OrganizedSeries[] = [],
  ) {}

  ownedGroups(userId: string): Promise<OwnedGroup[]> {
    this.calls.push(`ownedGroups:${userId}`);
    return Promise.resolve(this.groups);
  }

  reassignGroupOwner(groupId: string, newOwnerId: string): Promise<void> {
    this.calls.push(`reassignGroupOwner:${groupId}:${newOwnerId}`);
    this.groupReassignments.push({ groupId, newOwnerId });
    // Mutate the store so a second orchestrator pass sees nothing left to reassign.
    this.groups = this.groups.filter((g) => g.groupId !== groupId);
    return Promise.resolve();
  }

  organizedSessions(userId: string): Promise<OrganizedSession[]> {
    this.calls.push(`organizedSessions:${userId}`);
    return Promise.resolve(this.sessions);
  }

  reassignSessionOrganizer(sessionId: string, newOrganizerId: string): Promise<void> {
    this.calls.push(`reassignSessionOrganizer:${sessionId}:${newOrganizerId}`);
    this.sessionReassignments.push({ sessionId, newOrganizerId });
    this.sessions = this.sessions.filter((s) => s.sessionId !== sessionId);
    return Promise.resolve();
  }

  organizedSeries(userId: string): Promise<OrganizedSeries[]> {
    this.calls.push(`organizedSeries:${userId}`);
    return Promise.resolve(this.series);
  }

  reassignSeriesOrganizer(seriesId: string, newOrganizerId: string): Promise<void> {
    this.calls.push(`reassignSeriesOrganizer:${seriesId}:${newOrganizerId}`);
    this.seriesReassignments.push({ seriesId, newOrganizerId });
    this.series = this.series.filter((s) => s.seriesId !== seriesId);
    return Promise.resolve();
  }

  removeAvatar(userId: string): Promise<void> {
    this.calls.push(`removeAvatar:${userId}`);
    this.avatarRemovedFor.push(userId);
    return Promise.resolve();
  }

  deleteAuthUser(userId: string): Promise<void> {
    this.calls.push(`deleteAuthUser:${userId}`);
    this.authUsersDeleted.push(userId);
    return Promise.resolve();
  }
}

function baseDeps(overrides: Partial<HandleRequestDeps> = {}): HandleRequestDeps {
  return {
    gateway: new FakeDeletionGateway(),
    jwksCache: cacheFor({ keys: [] }),
    ...overrides,
  };
}

// ============================================================
// runAccountDeletion — ownership-handoff decisions
// ============================================================

Deno.test("runAccountDeletion: a group with another member is reassigned, not left to cascade", async () => {
  const gateway = new FakeDeletionGateway([{ groupId: "g1", replacementOwnerId: "other-user" }]);
  const result = await runAccountDeletion(gateway, "deleting-user");

  assertEquals(gateway.groupReassignments, [{ groupId: "g1", newOwnerId: "other-user" }]);
  assertEquals(result.groupsReassigned, 1);
});

Deno.test("runAccountDeletion: a group with no other member (sole member) is left alone — natural CASCADE is correct", async () => {
  const gateway = new FakeDeletionGateway([{ groupId: "g-solo", replacementOwnerId: null }]);
  const result = await runAccountDeletion(gateway, "deleting-user");

  assertEquals(gateway.groupReassignments, []);
  assertEquals(result.groupsReassigned, 0);
});

Deno.test("runAccountDeletion: sessions follow the same reassign-iff-other-participant rule", async () => {
  const gateway = new FakeDeletionGateway(
    [],
    [
      { sessionId: "s-shared", replacementOrganizerId: "other-participant" },
      { sessionId: "s-solo", replacementOrganizerId: null },
    ],
  );
  const result = await runAccountDeletion(gateway, "deleting-user");

  assertEquals(gateway.sessionReassignments, [{ sessionId: "s-shared", newOrganizerId: "other-participant" }]);
  assertEquals(result.sessionsReassigned, 1);
});

Deno.test("runAccountDeletion: session_series follows the same rule", async () => {
  const gateway = new FakeDeletionGateway([], [], [
    { seriesId: "sr-shared", replacementOrganizerId: "other-member" },
    { seriesId: "sr-solo", replacementOrganizerId: null },
  ]);
  const result = await runAccountDeletion(gateway, "deleting-user");

  assertEquals(gateway.seriesReassignments, [{ seriesId: "sr-shared", newOrganizerId: "other-member" }]);
  assertEquals(result.seriesReassigned, 1);
});

Deno.test("runAccountDeletion: multiple owned groups/sessions/series each resolve independently", async () => {
  const gateway = new FakeDeletionGateway(
    [
      { groupId: "g1", replacementOwnerId: "a" },
      { groupId: "g2", replacementOwnerId: null },
      { groupId: "g3", replacementOwnerId: "b" },
    ],
    [{ sessionId: "s1", replacementOrganizerId: "c" }],
    [{ seriesId: "sr1", replacementOrganizerId: null }],
  );
  const result = await runAccountDeletion(gateway, "u1");

  assertEquals(result.groupsReassigned, 2);
  assertEquals(result.sessionsReassigned, 1);
  assertEquals(result.seriesReassigned, 0);
});

// ============================================================
// runAccountDeletion — ordering, avatar, terminal delete, idempotency
// ============================================================

Deno.test("runAccountDeletion: ownership handoff completes before the terminal deleteAuthUser call", async () => {
  const gateway = new FakeDeletionGateway(
    [{ groupId: "g1", replacementOwnerId: "other" }],
    [{ sessionId: "s1", replacementOrganizerId: "other" }],
    [{ seriesId: "sr1", replacementOrganizerId: "other" }],
  );
  await runAccountDeletion(gateway, "u1");

  const deleteIdx = gateway.calls.indexOf("deleteAuthUser:u1");
  assertExists(gateway.calls.find((c) => c === "deleteAuthUser:u1"));
  for (const call of gateway.calls) {
    if (call.startsWith("reassign")) {
      assertEquals(gateway.calls.indexOf(call) < deleteIdx, true, `${call} must run before deleteAuthUser`);
    }
  }
});

Deno.test("runAccountDeletion: avatar removal and the terminal delete always run, even with nothing to reassign", async () => {
  const gateway = new FakeDeletionGateway();
  const result = await runAccountDeletion(gateway, "u-plain");

  assertEquals(gateway.avatarRemovedFor, ["u-plain"]);
  assertEquals(gateway.authUsersDeleted, ["u-plain"]);
  assertEquals(result, { userId: "u-plain", groupsReassigned: 0, sessionsReassigned: 0, seriesReassigned: 0 });
});

Deno.test("runAccountDeletion: a second invocation after a partially-completed first run is a clean no-op for what already ran (idempotent, WHERE-scoped)", async () => {
  // Models a crash-and-retry: the fake mutates its own store as calls
  // succeed (see reassignGroupOwner etc. above), exactly like real
  // WHERE-scoped Postgres UPDATEs would leave nothing left to match on a
  // retry.
  const gateway = new FakeDeletionGateway([{ groupId: "g1", replacementOwnerId: "other" }]);

  const first = await runAccountDeletion(gateway, "u1");
  assertEquals(first.groupsReassigned, 1);

  gateway.calls = []; // reset call log only, not the underlying store
  const second = await runAccountDeletion(gateway, "u1");

  assertEquals(second.groupsReassigned, 0, "nothing left to reassign — already done");
  assertEquals(gateway.groupReassignments.length, 1, "reassignGroupOwner was never called a second time");
  assertEquals(gateway.authUsersDeleted, ["u1", "u1"], "deleteAuthUser is safe to call again (real gateway treats 'already deleted' as success)");
});

// ============================================================
// handleRequest — auth (never a service-role bearer match, never a
// user-id request parameter — identity comes ONLY from the verified JWT)
// ============================================================

Deno.test("handleRequest: missing Authorization header is rejected (401)", async () => {
  const res = await handleRequest(req(), baseDeps());
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.reason, "missing_token");
});

Deno.test("handleRequest: malformed/garbage JWT is rejected (401)", async () => {
  const res = await handleRequest(req("Bearer not-a-real-jwt"), baseDeps());
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.reason, "invalid_token");
});

Deno.test("handleRequest: expired JWT (valid signature) is rejected (401)", async () => {
  const nowSec = Math.floor(Date.now() / 1000);
  const { token, jwks } = await makeCallerAuth("user-1", { exp: nowSec - 10 });
  const res = await handleRequest(req(`Bearer ${token}`), baseDeps({ jwksCache: cacheFor(jwks) }));
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: wrong audience is rejected (401)", async () => {
  const { token, jwks } = await makeCallerAuth("user-1", { aud: "anon" });
  const res = await handleRequest(req(`Bearer ${token}`), baseDeps({ jwksCache: cacheFor(jwks) }));
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: valid caller JWT — 200, deletes exactly the caller's own id, no other id is ever consulted", async () => {
  const { token, jwks } = await makeCallerAuth("user-self");
  const gateway = new FakeDeletionGateway();
  const res = await handleRequest(req(`Bearer ${token}`), baseDeps({ gateway, jwksCache: cacheFor(jwks) }));

  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.userId, "user-self");
  assertEquals(gateway.authUsersDeleted, ["user-self"]);
});

Deno.test("handleRequest: a gateway failure surfaces as 500, not a silent 200", async () => {
  const { token, jwks } = await makeCallerAuth("user-1");
  const gateway = new FakeDeletionGateway();
  gateway.deleteAuthUser = () => Promise.reject(new Error("simulated DB failure"));
  const res = await handleRequest(req(`Bearer ${token}`), baseDeps({ gateway, jwksCache: cacheFor(jwks) }));
  assertEquals(res.status, 500);
});

Deno.test("handleRequest: request body is never read for a user id — POST with no body still deletes the JWT's own sub", async () => {
  // Structural + behavioral proof this function has no user-id parameter:
  // req() above sends no body at all, and the deleted id still traces back
  // to the token's sub exclusively (see the 200 test above). This test
  // additionally confirms a body, if a caller sent one, is simply never
  // consulted.
  const { token, jwks } = await makeCallerAuth("caller-id");
  const gateway = new FakeDeletionGateway();
  const withBody = new Request("https://fn.local/account-deletion-cascade", {
    method: "POST",
    headers: { Authorization: `Bearer ${token}`, "content-type": "application/json" },
    body: JSON.stringify({ userId: "someone-elses-id", user_id: "someone-elses-id" }),
  });
  const res = await handleRequest(withBody, baseDeps({ gateway, jwksCache: cacheFor(jwks) }));
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.userId, "caller-id", "the caller's own JWT sub is used, never a body field");
  assertEquals(gateway.authUsersDeleted, ["caller-id"]);
});

// ============================================================
// jwt.ts — sanity check that the verify-only trim still round-trips
// (the full alg/expiry/audience/signature matrix is livekit-token's own
// test.ts; this just confirms the duplicated module works standalone)
// ============================================================

Deno.test("verifySupabaseJwt: valid token verifies and returns sub", async () => {
  const { token, jwks } = await makeCallerAuth("user-abc");
  const cache = cacheFor(jwks);
  const result = await verifySupabaseJwt(token, { jwksCache: cache, audience: "authenticated" });
  assertEquals(result.sub, "user-abc");
});

Deno.test("verifySupabaseJwt: tampered claims fail signature verification", async () => {
  const { token, jwks } = await makeCallerAuth("user-abc");
  const [headerB64, , sigB64] = token.split(".");
  const forgedClaimsB64 = base64url(
    new TextEncoder().encode(JSON.stringify({
      sub: "attacker",
      aud: "authenticated",
      exp: Math.floor(Date.now() / 1000) + 3600,
    })),
  );
  const tampered = `${headerB64}.${forgedClaimsB64}.${sigB64}`;
  await assertRejects(() => verifySupabaseJwt(tampered, { jwksCache: cacheFor(jwks), audience: "authenticated" }));
});

// ============================================================
// FK-graph documentation test — NOT a live-database proof.
// ============================================================
// Deno tests, by this repo's own idiom (push-dispatcher/livekit-token),
// never touch a real network or a live Supabase instance. The actual FK
// CASCADE/SET NULL behavior index.ts's top-of-file comment documents is
// enforced by Postgres itself the moment `auth.admin.deleteUser()` issues a
// real `DELETE FROM auth.users` — it cannot be hermetically exercised
// without a live migrated database (this repo has no `supabase start` +
// `deno test --allow-net` harness, and no pgTAP file for this yet — see
// task-3-report.md's "concerns" section for that gap and the recommended
// follow-up).
//
// What follows is a small in-memory model of exactly the FK actions cited
// in index.ts's top comment (each row below cites its migration), applied
// to the fixture task-3's brief specifies: a profile + a friendship + a
// gym + a push_device + an owned routine + set_logs + an authored
// chat_message in a shared group + a group membership, where the group has
// ANOTHER member (so it survives via ownership handoff, not raw CASCADE).
// This proves the derived graph is internally consistent with itself and
// catches drift if a future migration changes one of these ON DELETE
// actions without this test being updated — it does NOT prove Postgres
// behaves this way today; that requires a real database.

Deno.test("FK graph fixture (documentation, not a live DB proof): owned rows gone, chat tombstoned not deleted, shared group survives, second pass is a no-op", () => {
  const USER = "u-fixture";
  const OTHER = "u-other-member";
  const GROUP = "g-shared";

  const state = {
    profiles: new Set([USER, OTHER]),
    friendships: [{ id: "f1", user_id: USER, friend_id: OTHER }], // CASCADE both sides — 20260710000001_create_friendships.sql:2-3
    gyms: [{ id: "gym1", user_id: USER }], // CASCADE — 20260709000004_create_gyms.sql:3
    push_devices: [{ id: "pd1", user_id: USER }], // CASCADE — 20260716000001_push_schema.sql:11
    routines: [{ id: "r1", owner_id: USER }], // CASCADE — 20260709000005_create_routines.sql:3
    set_logs: [{ id: "sl1", user_id: USER }], // CASCADE — 20260709000007_create_set_logs.sql:3
    group_members: [
      { group_id: GROUP, user_id: USER },
      { group_id: GROUP, user_id: OTHER },
    ], // CASCADE — 20260710000002_create_groups.sql:13
    chat_messages: [
      { id: "m1", group_id: GROUP, author_id: USER as string | null, body: "hello crew" },
    ], // author_id SET NULL — 20260710000003_create_chat.sql:5
    groups: [{ id: GROUP, created_by: USER }], // CASCADE, but reassigned first below — 20260710000002_create_groups.sql:5
  };

  // 1. This function's ownership-handoff step (runAccountDeletion's
  // group-reassignment branch): GROUP has another group_members row besides
  // USER, so created_by is handed off instead of left to cascade.
  const otherMember = state.group_members.find((m) => m.group_id === GROUP && m.user_id !== USER);
  if (otherMember) {
    state.groups = state.groups.map((g) =>
      g.id === GROUP && g.created_by === USER ? { ...g, created_by: otherMember.user_id } : g
    );
  }

  // 2. The terminal `DELETE FROM auth.users` — apply each cited ON DELETE action.
  function applyTerminalDelete() {
    state.profiles.delete(USER);
    state.friendships = state.friendships.filter((f) => f.user_id !== USER && f.friend_id !== USER);
    state.gyms = state.gyms.filter((g) => g.user_id !== USER);
    state.push_devices = state.push_devices.filter((d) => d.user_id !== USER);
    state.routines = state.routines.filter((r) => r.owner_id !== USER);
    state.set_logs = state.set_logs.filter((s) => s.user_id !== USER);
    state.group_members = state.group_members.filter((m) => m.user_id !== USER);
    state.chat_messages = state.chat_messages.map((m) => (m.author_id === USER ? { ...m, author_id: null } : m));
  }
  applyTerminalDelete();

  assertEquals(state.friendships.length, 0, "friendship gone");
  assertEquals(state.gyms.length, 0, "gym gone");
  assertEquals(state.push_devices.length, 0, "push device gone");
  assertEquals(state.routines.length, 0, "owned routine gone");
  assertEquals(state.set_logs.length, 0, "set_logs gone");
  assertEquals(
    state.groups.find((g) => g.id === GROUP),
    { id: GROUP, created_by: OTHER },
    "shared group survives, ownership handed to the other member",
  );
  assertEquals(state.chat_messages[0].author_id, null, "chat message tombstoned (author_id -> NULL)");
  assertEquals(state.chat_messages[0].body, "hello crew", "tombstoned message body/content survives intact");
  assertEquals(state.group_members.some((m) => m.user_id === USER), false, "user's own membership row gone");
  assertEquals(state.group_members.some((m) => m.user_id === OTHER), true, "other member's membership untouched");
  assertEquals(state.profiles.has(USER), false, "auth user (and cascaded profile) removed");

  // 3. Idempotent re-invocation: applying the same WHERE-scoped filters
  // again to already-empty/already-nulled state is a no-op, not an error.
  const before = JSON.stringify({ ...state, profiles: [...state.profiles] });
  applyTerminalDelete();
  const after = JSON.stringify({ ...state, profiles: [...state.profiles] });
  assertEquals(after, before, "second pass over already-deleted/already-NULL state changes nothing");
});
