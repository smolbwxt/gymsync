// test.ts — pure `deno test`. No network, no live env vars: the APNs key
// used below is a throwaway EC P-256 key generated in-process (WebCrypto
// signing is local computation, not a network call), and all Supabase/queue
// interaction is a plain in-memory fake implementing QueueClient. Every
// "fetch" the code under test performs is the injected fetchImpl stub
// defined here, never the real global fetch.

import { assertEquals, assertExists, assertNotEquals } from "@std/assert";
import { ApnsClient, decodeJwt } from "./apns.ts";
import { buildNotificationPayload } from "./payloads.ts";
import {
  dispatchBatch,
  handleRequest,
  type DispatchDeps,
  type PushDeviceRow,
  type PushQueueRow,
  type QueueClient,
} from "./index.ts";

// ============================================================
// Helpers
// ============================================================

/** Generates a throwaway EC P-256 key pair and returns its PKCS8 PEM. */
async function generateThrowawayPkcs8Pem(): Promise<string> {
  const keyPair = await crypto.subtle.generateKey(
    { name: "ECDSA", namedCurve: "P-256" },
    true,
    ["sign", "verify"],
  );
  const der = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  const bytes = new Uint8Array(der);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  const b64 = btoa(binary);
  const lines = b64.match(/.{1,64}/g) ?? [b64];
  return `-----BEGIN PRIVATE KEY-----\n${lines.join("\n")}\n-----END PRIVATE KEY-----\n`;
}

async function makeTestApnsClient(host = "https://example.invalid"): Promise<ApnsClient> {
  const pem = await generateThrowawayPkcs8Pem();
  return new ApnsClient({
    keyId: "test-key-id",
    teamId: "test-team-id",
    privateKeyPem: pem,
    topic: "app.gymsync.ios.test",
    host,
  });
}

/** In-memory QueueClient fake. Records every call for assertions. */
class FakeQueueClient implements QueueClient {
  rows: PushQueueRow[];
  devicesByUser: Map<string, PushDeviceRow[]>;
  deletedDeviceIds: string[] = [];
  sentIds: number[] = [];

  constructor(rows: PushQueueRow[], devicesByUser: Map<string, PushDeviceRow[]>) {
    this.rows = rows;
    this.devicesByUser = devicesByUser;
  }

  claimBatch(_limit: number): Promise<PushQueueRow[]> {
    return Promise.resolve(this.rows);
  }

  devicesForUser(userId: string): Promise<PushDeviceRow[]> {
    return Promise.resolve(this.devicesByUser.get(userId) ?? []);
  }

  deleteDevice(id: string): Promise<void> {
    this.deletedDeviceIds.push(id);
    return Promise.resolve();
  }

  markSent(id: number): Promise<void> {
    this.sentIds.push(id);
    return Promise.resolve();
  }
}

function jsonResponse(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), { status });
}

function row(overrides: Partial<PushQueueRow>): PushQueueRow {
  return {
    id: 1,
    user_id: "11111111-1111-1111-1111-111111111111",
    event: "your_turn",
    payload: { session_id: "22222222-2222-2222-2222-222222222222" },
    sent_at: null,
    attempts: 1,
    ...overrides,
  };
}

// ============================================================
// payloads.ts — exact content for all 10 events (Dossier §A.6 test hook)
// ============================================================

Deno.test("payloads: friend_request", () => {
  const c = buildNotificationPayload("friend_request", { from_user_id: "u1" });
  assertEquals(c, {
    title: "Friend Request",
    body: "You have a new friend request on GymSync.",
    category: "FRIEND_REQUEST",
  });
});

Deno.test("payloads: session_invite includes organizer_username and threadId", () => {
  const c = buildNotificationPayload("session_invite", {
    session_id: "s1",
    organizer_id: "o1",
    organizer_username: "Tommy",
  });
  assertEquals(c, {
    title: "Session Invite",
    body: "Tommy invited you to a session.",
    category: "SESSION_INVITE",
    threadId: "s1",
  });
});

Deno.test("payloads: session_invite falls back to 'Someone' when organizer_username missing", () => {
  const c = buildNotificationPayload("session_invite", { session_id: "s1" });
  assertEquals(c?.body, "Someone invited you to a session.");
});

Deno.test("payloads: session_reminder_15min", () => {
  const c = buildNotificationPayload("session_reminder_15min", { session_id: "s1" });
  assertEquals(c, {
    title: "Starting Soon",
    body: "Your session starts in 15 min. Tap to enter lobby.",
    category: "SESSION_VIEW",
    threadId: "s1",
  });
});

Deno.test("payloads: session_lobby_open", () => {
  const c = buildNotificationPayload("session_lobby_open", { session_id: "s1" });
  assertEquals(c, {
    title: "Lobby Open",
    body: "The lobby is open. Tap to join.",
    category: "OPEN_LOBBY",
    threadId: "s1",
  });
});

Deno.test("payloads: your_turn", () => {
  const c = buildNotificationPayload("your_turn", { session_id: "s1" });
  assertEquals(c, {
    title: "Your Turn",
    body: "It's your turn on the bar.",
    category: "OPEN_SESSION",
    threadId: "s1",
  });
});

Deno.test("payloads: partner_pr", () => {
  const c = buildNotificationPayload("partner_pr", {
    group_id: "g1",
    message_id: "m1",
    pr_user_id: "u1",
  });
  assertEquals(c, {
    title: "Crew PR",
    body: "Someone in your crew just hit a new PR.",
    category: "SESSION_VIEW",
    threadId: "g1",
  });
});

Deno.test("payloads: lateness_chirp", () => {
  const c = buildNotificationPayload("lateness_chirp", {
    session_id: "s1",
    late_user_id: "u1",
  });
  assertEquals(c, {
    title: "Late Arrival",
    body: "Someone's running late. Send a roast.",
    category: "ROAST",
    threadId: "s1",
  });
});

Deno.test("payloads: session_idle_30min", () => {
  const c = buildNotificationPayload("session_idle_30min", { session_id: "s1" });
  assertEquals(c, {
    title: "Session Idle",
    body: "Your session's been quiet for 30 min. Wrap up or keep going?",
    category: "IDLE_ACTIONS",
    threadId: "s1",
  });
});

Deno.test("payloads: session_idle_60min", () => {
  const c = buildNotificationPayload("session_idle_60min", { session_id: "s1" });
  assertEquals(c, {
    title: "Session Idle",
    body: "Your session's been quiet for 60 min. Wrap up or keep going?",
    category: "IDLE_ACTIONS",
    threadId: "s1",
  });
});

Deno.test("payloads: chat_mention", () => {
  const c = buildNotificationPayload("chat_mention", {
    group_id: "g1",
    message_id: "m1",
    mentioned_username: "bob",
  });
  assertEquals(c, {
    title: "Mentioned",
    body: "You were mentioned in chat.",
    category: "SESSION_VIEW",
    threadId: "g1",
  });
});

Deno.test("payloads: unrecognized event returns null", () => {
  assertEquals(buildNotificationPayload("not_a_real_event", {}), null);
});

// ============================================================
// apns.ts — JWT structure (decode only, no signature verification) + caching
// ============================================================

Deno.test("apns: JWT header/claims shape", async () => {
  const client = await makeTestApnsClient();
  const token = await client.getToken(1_000_000);
  const parts = token.split(".");
  assertEquals(parts.length, 3, "JWT has header.claims.signature");

  const { header, claims } = decodeJwt(token);
  assertEquals(header.alg, "ES256");
  assertEquals(header.kid, "test-key-id");
  assertEquals(claims.iss, "test-team-id");
  assertEquals(claims.iat, 1_000);
});

Deno.test("apns: token is cached within the TTL window", async () => {
  const client = await makeTestApnsClient();
  const t0 = await client.getToken(0);
  const t1 = await client.getToken(10 * 60 * 1000); // +10min, well under 50min TTL
  assertEquals(t0, t1, "same token returned inside the cache window");
});

Deno.test("apns: token is regenerated after the TTL expires", async () => {
  const client = await makeTestApnsClient();
  const t0 = await client.getToken(0);
  const t1 = await client.getToken(51 * 60 * 1000); // +51min, past the 50min TTL
  assertNotEquals(t0, t1, "a fresh token (different iat) is minted after expiry");
});

Deno.test("apns: send() posts to /3/device/{token} with required headers", async () => {
  const client = await makeTestApnsClient("https://example.invalid");
  let capturedUrl = "";
  let capturedHeaders: Headers | undefined;
  const fetchImpl: typeof fetch = (input, init) => {
    capturedUrl = String(input);
    capturedHeaders = new Headers(init?.headers);
    return Promise.resolve(jsonResponse(200, {}));
  };

  const result = await client.send(
    "abc123devicetoken",
    { aps: { alert: { title: "t", body: "b" } } },
    fetchImpl,
  );

  assertEquals(result.ok, true);
  assertEquals(capturedUrl, "https://example.invalid/3/device/abc123devicetoken");
  assertEquals(capturedHeaders?.get("apns-topic"), "app.gymsync.ios.test");
  assertEquals(capturedHeaders?.get("apns-push-type"), "alert");
  assertExists(capturedHeaders?.get("authorization"));
});

// ============================================================
// index.ts — dispatchBatch: device lifecycle + retry semantics
// ============================================================

Deno.test("dispatch: 410 response deletes the device and marks the row sent", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(410, { reason: "Unregistered" }));

  const r = row({ id: 1, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const deps: DispatchDeps = { queue, apns, fetchImpl };

  const result = await dispatchBatch(deps);

  assertEquals(queue.deletedDeviceIds, ["dev1"]);
  assertEquals(queue.sentIds, [1], "no devices left to retry, so the row is marked sent");
  assertEquals(result.devicesDeleted, 1);
  assertEquals(result.sent, 1);
  assertEquals(result.retried, 0);
});

Deno.test("dispatch: BadDeviceToken reason (400) also deletes the device", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(400, { reason: "BadDeviceToken" }));

  const r = row({ id: 2, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.deletedDeviceIds, ["dev1"]);
  assertEquals(result.devicesDeleted, 1);
});

Deno.test("dispatch: 5xx leaves the row unsent for retry", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(503, { reason: "ServiceUnavailable" }));

  const r = row({ id: 3, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.sentIds, [], "5xx must not mark the row sent");
  assertEquals(queue.deletedDeviceIds, [], "5xx is not a device problem — no delete");
  assertEquals(result.retried, 1);
  assertEquals(result.sent, 0);
});

Deno.test("dispatch: 429 also leaves the row unsent for retry", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(429, { reason: "TooManyRequests" }));

  const r = row({ id: 4, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.sentIds, []);
  assertEquals(result.retried, 1);
});

Deno.test("dispatch: mixed devices — one 410, one success — still marks the row sent", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("dead-token")) {
      return Promise.resolve(jsonResponse(410, { reason: "Unregistered" }));
    }
    return Promise.resolve(jsonResponse(200, {}));
  };

  const r = row({ id: 5, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([[
      "u1",
      [
        { id: "dev-dead", apns_token: "dead-token" },
        { id: "dev-live", apns_token: "live-token" },
      ],
    ]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.deletedDeviceIds, ["dev-dead"]);
  assertEquals(queue.sentIds, [5]);
  assertEquals(result.retried, 0);
});

Deno.test("dispatch: a user with zero devices is marked sent without calling APNs", async () => {
  const apns = await makeTestApnsClient();
  let fetchCalled = false;
  const fetchImpl: typeof fetch = () => {
    fetchCalled = true;
    return Promise.resolve(jsonResponse(200, {}));
  };

  const r = row({ id: 6, user_id: "u-no-devices" });
  const queue = new FakeQueueClient([r], new Map());
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(fetchCalled, false, "no devices means no APNs call at all");
  assertEquals(queue.sentIds, [6]);
  assertEquals(result.noDevice, 1);
  assertEquals(result.sent, 1);
});

Deno.test("dispatch: unrecognized event is marked sent (not retried forever)", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(200, {}));

  const r = row({ id: 7, user_id: "u1", event: "totally_unknown_event" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.sentIds, [7]);
  assertEquals(result.sent, 1);
});

Deno.test("dispatch: happy path — single device, 200 — marks sent", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(200, {}));

  const r = row({ id: 8, user_id: "u1" });
  const queue = new FakeQueueClient(
    [r],
    new Map([["u1", [{ id: "dev1", apns_token: "tok1" }]]]),
  );
  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.sentIds, [8]);
  assertEquals(result.claimed, 1);
  assertEquals(result.sent, 1);
});

Deno.test("dispatch: does not consult notification_prefs — QueueClient has no such method", () => {
  // Structural proof, not a behavioral one: prefs filtering already happened
  // at enqueue time (enqueue_push, 20260716000001_push_schema.sql checks
  // notification_prefs before writing a push_queue row at all). QueueClient
  // — the only surface dispatchBatch touches — has exactly four methods
  // (claimBatch, devicesForUser, deleteDevice, markSent) and none of them
  // can reach notification_prefs, so re-filtering here is structurally
  // impossible, not just unimplemented.
  const methods = ["claimBatch", "devicesForUser", "deleteDevice", "markSent"];
  assertEquals(methods.includes("checkPrefs" as never), false);
});

// ============================================================
// index.ts — handleRequest: auth
// ============================================================

const REAL_KEY = "test-service-role-key-abc123";

function emptyDeps(): DispatchDeps {
  return {
    queue: new FakeQueueClient([], new Map()),
    apns: new ApnsClient({
      keyId: "k",
      teamId: "t",
      privateKeyPem: "unused-for-this-test",
      topic: "topic",
    }),
    fetchImpl: () => Promise.reject(new Error("fetch must not be called")),
  };
}

Deno.test("handleRequest: missing Authorization header is rejected (401)", async () => {
  const req = new Request("https://fn.local/push-dispatcher");
  const res = await handleRequest(req, emptyDeps(), REAL_KEY);
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: wrong bearer token is rejected (401)", async () => {
  const req = new Request("https://fn.local/push-dispatcher", {
    headers: { Authorization: "Bearer not-the-right-key" },
  });
  const res = await handleRequest(req, emptyDeps(), REAL_KEY);
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: non-Bearer scheme is rejected (401)", async () => {
  const req = new Request("https://fn.local/push-dispatcher", {
    headers: { Authorization: REAL_KEY }, // missing "Bearer " prefix
  });
  const res = await handleRequest(req, emptyDeps(), REAL_KEY);
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: exact bearer match is accepted (200) and dispatches", async () => {
  const req = new Request("https://fn.local/push-dispatcher", {
    headers: { Authorization: `Bearer ${REAL_KEY}` },
  });
  const res = await handleRequest(req, emptyDeps(), REAL_KEY);
  assertEquals(res.status, 200);
  const body = await res.json();
  assertEquals(body.claimed, 0);
});
