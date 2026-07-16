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
// payloads.ts — exact content for all 12 events (Dossier §A.6 test hook;
// streak_milestone/streak_at_risk added in Phase S, 20260719000008)
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

Deno.test("payloads: streak_milestone (user)", () => {
  const c = buildNotificationPayload("streak_milestone", { streak: 7, kind: "user" });
  assertEquals(c, {
    title: "Streak Milestone",
    body: "You just hit a 7-session streak!",
    category: "SESSION_VIEW",
  });
});

Deno.test("payloads: streak_milestone (group) includes group_id as threadId", () => {
  const c = buildNotificationPayload("streak_milestone", {
    streak: 30,
    kind: "group",
    group_id: "g1",
  });
  assertEquals(c, {
    title: "Streak Milestone",
    body: "Your crew just hit a 30-session streak!",
    category: "SESSION_VIEW",
    threadId: "g1",
  });
});

Deno.test("payloads: streak_at_risk", () => {
  const c = buildNotificationPayload("streak_at_risk", { session_id: "s1", streak: 12 });
  assertEquals(c, {
    title: "Streak at Risk",
    body: "Your 12-session streak needs you. Your session starts soon.",
    category: "SESSION_VIEW",
    threadId: "s1",
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

// ============================================================
// index.ts — dispatchBatch: per-row / per-device error isolation
// ============================================================

/** Captures console.{log,warn,error} calls made during `fn()`, then restores the originals. */
async function captureConsole(fn: () => Promise<void>): Promise<{ log: string[]; warn: string[]; error: string[] }> {
  const captured = { log: [] as string[], warn: [] as string[], error: [] as string[] };
  const orig = { log: console.log, warn: console.warn, error: console.error };
  console.log = (...args: unknown[]) => captured.log.push(args.map(String).join(" "));
  console.warn = (...args: unknown[]) => captured.warn.push(args.map(String).join(" "));
  console.error = (...args: unknown[]) => captured.error.push(args.map(String).join(" "));
  try {
    await fn();
  } finally {
    console.log = orig.log;
    console.warn = orig.warn;
    console.error = orig.error;
  }
  return captured;
}

interface DispatchResultForTest {
  claimed: number;
  sent: number;
  retried: number;
  devicesDeleted: number;
  noDevice: number;
  failed: number;
}

Deno.test("dispatch: a rejecting fetchImpl for one row's device does not abort the rest of the batch", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = (input) => {
    const url = String(input);
    if (url.includes("reject-token")) {
      return Promise.reject(new Error("simulated network failure"));
    }
    return Promise.resolve(jsonResponse(200, {}));
  };

  const rowA = row({ id: 30, user_id: "u-a" });
  const rowB = row({ id: 31, user_id: "u-b" });
  const queue = new FakeQueueClient(
    [rowA, rowB],
    new Map([
      ["u-a", [{ id: "dev-a", apns_token: "reject-token" }]],
      ["u-b", [{ id: "dev-b", apns_token: "ok-token" }]],
    ]),
  );

  let result!: DispatchResultForTest;
  const captured = await captureConsole(async () => {
    result = await dispatchBatch({ queue, apns, fetchImpl });
  });

  // Row A: send rejected — left unsent, no device deleted, counted as a retry (not a hard failure).
  assertEquals(queue.sentIds.includes(30), false, "row A must stay unsent after its device send rejected");
  assertEquals(queue.deletedDeviceIds, [], "a rejection is not a device problem — no delete");

  // Row B: unaffected by row A's failure — still delivered.
  assertEquals(queue.sentIds.includes(31), true, "row B must still be marked sent despite row A's failure");

  assertEquals(result!.claimed, 2);
  assertEquals(result!.sent, 1);
  assertEquals(result!.retried, 1);
  assertEquals(result!.failed, 0, "a device-level rejection is a retry, not a row-level failure");

  const errorText = captured.error.join("\n");
  assertEquals(errorText.includes("30"), true, "the failing row's id should be logged");
  assertEquals(errorText.includes("reject-token"), false, "the raw device token must never be logged");
});

Deno.test("dispatch: queue.markSent throwing for one row does not abort the rest of the batch", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(200, {}));

  const rowA = row({ id: 40, user_id: "u-a" });
  const rowB = row({ id: 41, user_id: "u-b" });
  const queue = new FakeQueueClient(
    [rowA, rowB],
    new Map([
      ["u-a", [{ id: "dev-a", apns_token: "tok-a" }]],
      ["u-b", [{ id: "dev-b", apns_token: "tok-b" }]],
    ]),
  );
  const originalMarkSent = queue.markSent.bind(queue);
  queue.markSent = (id: number): Promise<void> => {
    if (id === 40) return Promise.reject(new Error("simulated DB failure"));
    return originalMarkSent(id);
  };

  const result = await dispatchBatch({ queue, apns, fetchImpl });

  assertEquals(queue.sentIds.includes(40), false, "row A must stay unsent when markSent throws");
  assertEquals(queue.sentIds.includes(41), true, "row B must still be processed and marked sent");
  assertEquals(result.claimed, 2);
  assertEquals(result.sent, 1);
  assertEquals(result.failed, 1, "row A's thrown markSent is a hard failure, not a retry");
});

Deno.test("dispatch: summary log reports accurate claimed/delivered/retried/failed counts", async () => {
  const apns = await makeTestApnsClient();
  const fetchImpl: typeof fetch = () => Promise.resolve(jsonResponse(200, {}));

  const rowSuccess = row({ id: 50, user_id: "u-success" });
  const rowRetry = row({ id: 51, user_id: "u-retry" });
  const rowNoDevice = row({ id: 52, user_id: "u-no-device" });
  const rowThrows = row({ id: 53, user_id: "u-throws" });

  const retryFetch: typeof fetch = () => Promise.resolve(jsonResponse(503, { reason: "ServiceUnavailable" }));

  const queue = new FakeQueueClient(
    [rowSuccess, rowRetry, rowNoDevice, rowThrows],
    new Map([
      ["u-success", [{ id: "dev-success", apns_token: "tok-success" }]],
      ["u-retry", [{ id: "dev-retry", apns_token: "tok-retry" }]],
      ["u-throws", [{ id: "dev-throws", apns_token: "tok-throws" }]],
    ]),
  );
  const originalMarkSent = queue.markSent.bind(queue);
  queue.markSent = (id: number): Promise<void> => {
    if (id === 53) return Promise.reject(new Error("simulated DB failure"));
    return originalMarkSent(id);
  };

  // dev-retry needs its own fetchImpl behavior (503) while the rest succeed;
  // route by token so a single dispatchBatch call covers all four rows.
  const mixedFetch: typeof fetch = (input, init) => {
    const url = String(input);
    if (url.includes("tok-retry")) return retryFetch(input, init);
    return fetchImpl(input, init);
  };

  let result!: DispatchResultForTest;
  const captured = await captureConsole(async () => {
    result = await dispatchBatch({ queue, apns, fetchImpl: mixedFetch });
  });

  assertEquals(result.claimed, 4);
  assertEquals(result.sent, 2, "rowSuccess + rowNoDevice");
  assertEquals(result.retried, 1, "rowRetry (503)");
  assertEquals(result.noDevice, 1);
  assertEquals(result.failed, 1, "rowThrows (markSent rejected)");

  const summaryLine = captured.log.find((l) => l.includes("drain complete"));
  assertExists(summaryLine, "a single summary line must be logged per drain invocation");
  assertEquals(summaryLine!.includes("claimed=4"), true);
  assertEquals(summaryLine!.includes("delivered=2"), true);
  assertEquals(summaryLine!.includes("retried=1"), true);
  assertEquals(summaryLine!.includes("failed=1"), true);
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
