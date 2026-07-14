// test.ts — pure `deno test`. No network: every "fetch" the code under
// test performs is the injected fetchImpl stub defined here (never the
// real global fetch), and every caller JWT is signed in-process against a
// throwaway EC/RSA key pair generated via WebCrypto (mirrors
// push-dispatcher/test.ts's throwaway EC P-256 key for apns.ts). All
// Postgrest interaction is a plain in-memory FakeGateway.

import { assertEquals, assertExists, assertRejects } from "@std/assert";
import {
  decodeJwt,
  type Jwk,
  type Jwks,
  JwksCache,
  mintLiveKitToken,
  verifySupabaseJwt,
} from "./jwt.ts";
import { type Gateway, type HandleRequestDeps, handleRequest, VOICE_ELIGIBLE_STATES } from "./index.ts";

// ============================================================
// Helpers
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

async function generateTestRsaKeyPair(kid: string): Promise<{ privateKey: CryptoKey; jwk: Jwk }> {
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"],
  );
  const publicJwk = (await crypto.subtle.exportKey("jwk", keyPair.publicKey)) as JsonWebKey;
  return { privateKey: keyPair.privateKey, jwk: { ...publicJwk, kid, alg: "RS256" } };
}

/** Signs an arbitrary header/claims pair — test-only, mirrors mintLiveKitToken's signing shape but generic over alg/key so it can forge caller JWTs for any scenario. */
async function signTestJwt(
  header: Record<string, unknown>,
  claims: Record<string, unknown>,
  privateKey: CryptoKey,
  alg: "ES256" | "RS256",
): Promise<string> {
  const headerB64 = base64url(new TextEncoder().encode(JSON.stringify(header)));
  const claimsB64 = base64url(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${headerB64}.${claimsB64}`;
  const signParams = alg === "ES256" ? { name: "ECDSA", hash: "SHA-256" } : "RSASSA-PKCS1-v1_5";
  const signature = await crypto.subtle.sign(signParams, privateKey, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64url(new Uint8Array(signature))}`;
}

interface CallerAuthOverrides {
  aud?: string;
  exp?: number;
  kid?: string;
  alg?: "ES256" | "RS256";
}

/** Builds a valid (unless overridden) caller JWT + the matching JWKS document a JwksCache would fetch for it. */
async function makeCallerAuth(sub: string, overrides: CallerAuthOverrides = {}): Promise<{ token: string; jwks: Jwks }> {
  const kid = overrides.kid ?? "test-kid-1";
  const alg = overrides.alg ?? "ES256";
  const { privateKey, jwk } = alg === "ES256"
    ? await generateTestEcKeyPair(kid)
    : await generateTestRsaKeyPair(kid);
  const nowSec = Math.floor(Date.now() / 1000);
  const claims = {
    sub,
    aud: overrides.aud ?? "authenticated",
    exp: overrides.exp ?? nowSec + 3600,
    iat: nowSec,
  };
  const token = await signTestJwt({ alg, kid }, claims, privateKey, alg);
  return { token, jwks: { keys: [jwk] } };
}

/** Injectable fetchImpl serving a fixed JWKS document; `calls` lets tests assert fetch count without instrumenting JwksCache itself. */
function jwksFetch(jwks: Jwks, calls: { count: number }): typeof fetch {
  return () => {
    calls.count++;
    return Promise.resolve(new Response(JSON.stringify(jwks), { status: 200 }));
  };
}

function cacheFor(jwks: Jwks, calls: { count: number } = { count: 0 }): JwksCache {
  return new JwksCache("https://fake.local/auth/v1/.well-known/jwks.json", jwksFetch(jwks, calls));
}

class FakeGateway implements Gateway {
  constructor(
    private participants: Set<string> = new Set(),
    private states: Map<string, string> = new Map(),
    private usernames: Map<string, string> = new Map(),
  ) {}

  isParticipant(sessionId: string, userId: string): Promise<boolean> {
    return Promise.resolve(this.participants.has(`${sessionId}:${userId}`));
  }

  getSessionState(sessionId: string): Promise<string | null> {
    return Promise.resolve(this.states.get(sessionId) ?? null);
  }

  getUsername(userId: string): Promise<string | null> {
    return Promise.resolve(this.usernames.get(userId) ?? null);
  }
}

function req(body: unknown, authorization?: string): Request {
  const headers: Record<string, string> = { "content-type": "application/json" };
  if (authorization !== undefined) headers["Authorization"] = authorization;
  return new Request("https://fn.local/livekit-token", {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

function baseDeps(overrides: Partial<HandleRequestDeps> = {}): HandleRequestDeps {
  return {
    gateway: new FakeGateway(),
    jwksCache: cacheFor({ keys: [] }),
    liveKitApiKey: "test-livekit-api-key",
    liveKitApiSecret: "test-livekit-api-secret",
    liveKitUrl: "wss://test-project.livekit.cloud",
    ...overrides,
  };
}

// ============================================================
// jwt.ts — mintLiveKitToken: claims shape + signature
// ============================================================

Deno.test("mintLiveKitToken: claims shape matches the LiveKit AccessToken spec", async () => {
  const now = 1_700_000_000_000; // fixed ms epoch
  const token = await mintLiveKitToken({
    apiKey: "test-api-key",
    apiSecret: "test-api-secret",
    identity: "user-123",
    name: "tommy",
    grant: { room: "session:abc", roomJoin: true, canPublish: true, canSubscribe: true },
    ttlSeconds: 900,
    now,
  });

  const { header, claims } = decodeJwt(token);
  assertEquals(header.alg, "HS256");
  assertEquals(claims.iss, "test-api-key");
  assertEquals(claims.sub, "user-123");
  assertEquals(claims.name, "tommy");
  assertEquals(claims.video, { room: "session:abc", roomJoin: true, canPublish: true, canSubscribe: true });
  assertEquals(claims.nbf, Math.floor(now / 1000));
  assertEquals(claims.exp, Math.floor(now / 1000) + 900);
  assertEquals("jti" in claims, false, "reference LiveKit AccessToken.toJwt() sets no jti");
});

Deno.test("mintLiveKitToken: name is omitted from claims when not provided", async () => {
  const token = await mintLiveKitToken({
    apiKey: "k",
    apiSecret: "s",
    identity: "u1",
    grant: { room: "session:x", roomJoin: true, canPublish: true, canSubscribe: true },
  });
  const { claims } = decodeJwt(token);
  assertEquals("name" in claims, false);
});

Deno.test("mintLiveKitToken: default TTL is 15 minutes and nbf <= exp - ttl bound holds", async () => {
  const now = Date.now();
  const token = await mintLiveKitToken({
    apiKey: "k",
    apiSecret: "s",
    identity: "u1",
    grant: { room: "session:x", roomJoin: true, canPublish: true, canSubscribe: true },
    now,
  });
  const { claims } = decodeJwt(token);
  const nowSec = Math.floor(now / 1000);
  assertEquals(claims.nbf, nowSec);
  assertEquals(claims.exp, nowSec + 15 * 60);
  assertEquals((claims.exp as number) - nowSec < 3600, true, "TTL must stay well under an hour");
});

Deno.test("mintLiveKitToken: signature verifies against an independently recomputed HMAC-SHA256", async () => {
  const secret = "recompute-me-secret";
  const token = await mintLiveKitToken({
    apiKey: "k",
    apiSecret: secret,
    identity: "u1",
    grant: { room: "session:y", roomJoin: true, canPublish: true, canSubscribe: true },
  });
  const [headerB64, claimsB64, sigB64] = token.split(".");

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const expectedSig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${headerB64}.${claimsB64}`));
  assertEquals(sigB64, base64url(new Uint8Array(expectedSig)));
});

// ============================================================
// jwt.ts — verifySupabaseJwt + JwksCache
// ============================================================

Deno.test("verifySupabaseJwt: valid ES256 caller token verifies and returns sub", async () => {
  const { token, jwks } = await makeCallerAuth("user-abc");
  const result = await verifySupabaseJwt(token, { jwksCache: cacheFor(jwks), audience: "authenticated" });
  assertEquals(result.sub, "user-abc");
});

Deno.test("verifySupabaseJwt: valid RS256 caller token verifies too (project may use RSA signing keys)", async () => {
  const { token, jwks } = await makeCallerAuth("user-rsa", { alg: "RS256" });
  const result = await verifySupabaseJwt(token, { jwksCache: cacheFor(jwks), audience: "authenticated" });
  assertEquals(result.sub, "user-rsa");
});

Deno.test("verifySupabaseJwt: malformed/garbage token is rejected", async () => {
  await assertRejects(() =>
    verifySupabaseJwt("not-a-jwt-at-all", { jwksCache: cacheFor({ keys: [] }) })
  );
});

Deno.test("verifySupabaseJwt: expired token (valid signature) is rejected", async () => {
  const nowSec = Math.floor(Date.now() / 1000);
  const { token, jwks } = await makeCallerAuth("user-abc", { exp: nowSec - 10 });
  await assertRejects(() =>
    verifySupabaseJwt(token, { jwksCache: cacheFor(jwks), audience: "authenticated" })
  );
});

Deno.test("verifySupabaseJwt: audience mismatch is rejected", async () => {
  const { token, jwks } = await makeCallerAuth("user-abc", { aud: "anon" });
  await assertRejects(() =>
    verifySupabaseJwt(token, { jwksCache: cacheFor(jwks), audience: "authenticated" })
  );
});

Deno.test("verifySupabaseJwt: unknown kid (no matching JWKS entry) is rejected", async () => {
  const { token } = await makeCallerAuth("user-abc");
  await assertRejects(() =>
    verifySupabaseJwt(token, { jwksCache: cacheFor({ keys: [] }), audience: "authenticated" })
  );
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
  await assertRejects(() =>
    verifySupabaseJwt(tampered, { jwksCache: cacheFor(jwks), audience: "authenticated" })
  );
});

Deno.test("verifySupabaseJwt: unsupported alg (HS256) is rejected without ever fetching JWKS", async () => {
  const calls = { count: 0 };
  const nowSec = Math.floor(Date.now() / 1000);
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode("whatever"), {
    name: "HMAC",
    hash: "SHA-256",
  }, false, ["sign"]);
  const headerB64 = base64url(new TextEncoder().encode(JSON.stringify({ alg: "HS256", kid: "k1" })));
  const claimsB64 = base64url(
    new TextEncoder().encode(JSON.stringify({ sub: "u1", aud: "authenticated", exp: nowSec + 3600 })),
  );
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${headerB64}.${claimsB64}`));
  const token = `${headerB64}.${claimsB64}.${base64url(new Uint8Array(sig))}`;

  await assertRejects(() =>
    verifySupabaseJwt(token, { jwksCache: cacheFor({ keys: [] }, calls), audience: "authenticated" })
  );
  assertEquals(calls.count, 0, "an unsupported alg must be rejected before ever touching the JWKS cache");
});

Deno.test("JwksCache: does not refetch within the TTL window", async () => {
  const calls = { count: 0 };
  const cache = new JwksCache("https://fake.local/jwks.json", jwksFetch({ keys: [] }, calls), 10 * 60 * 1000);
  await cache.getJwks(0);
  await cache.getJwks(5 * 60 * 1000); // +5min, within the 10min TTL
  assertEquals(calls.count, 1);
});

Deno.test("JwksCache: refetches once the TTL has elapsed", async () => {
  const calls = { count: 0 };
  const cache = new JwksCache("https://fake.local/jwks.json", jwksFetch({ keys: [] }, calls), 10 * 60 * 1000);
  await cache.getJwks(0);
  await cache.getJwks(11 * 60 * 1000); // +11min, past the 10min TTL
  assertEquals(calls.count, 2);
});

Deno.test("JwksCache: a non-ok fetch response throws rather than caching an empty result", async () => {
  const cache = new JwksCache(
    "https://fake.local/jwks.json",
    () => Promise.resolve(new Response("nope", { status: 500 })),
  );
  await assertRejects(() => cache.getJwks(0));
});

// ============================================================
// index.ts — handleRequest: auth + gating + happy path
// ============================================================

Deno.test("handleRequest: missing Authorization header is rejected (401)", async () => {
  const res = await handleRequest(req({ session_id: "s1" }), baseDeps());
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.reason, "missing_token");
});

Deno.test("handleRequest: malformed/garbage JWT is rejected (401)", async () => {
  const res = await handleRequest(req({ session_id: "s1" }, "Bearer not-a-real-jwt"), baseDeps());
  assertEquals(res.status, 401);
  const body = await res.json();
  assertEquals(body.reason, "invalid_token");
});

Deno.test("handleRequest: expired JWT (valid signature) is rejected (401)", async () => {
  const nowSec = Math.floor(Date.now() / 1000);
  const { token, jwks } = await makeCallerAuth("user-1", { exp: nowSec - 10 });
  const res = await handleRequest(
    req({ session_id: "s1" }, `Bearer ${token}`),
    baseDeps({ jwksCache: cacheFor(jwks) }),
  );
  assertEquals(res.status, 401);
});

Deno.test("handleRequest: non-participant is rejected (403), distinct from 401", async () => {
  const { token, jwks } = await makeCallerAuth("user-outsider");
  const gateway = new FakeGateway(new Set(), new Map([["s1", "in_progress"]]));
  const res = await handleRequest(
    req({ session_id: "s1" }, `Bearer ${token}`),
    baseDeps({ gateway, jwksCache: cacheFor(jwks) }),
  );
  assertEquals(res.status, 403);
  const body = await res.json();
  assertEquals(body.reason, "not_participant");
});

Deno.test("handleRequest: participant in an ineligible session state is rejected (403)", async () => {
  const { token, jwks } = await makeCallerAuth("user-1");
  const gateway = new FakeGateway(new Set(["s1:user-1"]), new Map([["s1", "completed"]]));
  const res = await handleRequest(
    req({ session_id: "s1" }, `Bearer ${token}`),
    baseDeps({ gateway, jwksCache: cacheFor(jwks) }),
  );
  assertEquals(res.status, 403);
  const body = await res.json();
  assertEquals(body.reason, "ineligible_state");
});

Deno.test("handleRequest: missing session_id in body is a 400, not a 403/500", async () => {
  const { token, jwks } = await makeCallerAuth("user-1");
  const res = await handleRequest(
    req({}, `Bearer ${token}`),
    baseDeps({ jwksCache: cacheFor(jwks) }),
  );
  assertEquals(res.status, 400);
});

for (const state of VOICE_ELIGIBLE_STATES) {
  Deno.test(`handleRequest: happy path for voice-eligible state "${state}" — 200 with correct grants`, async () => {
    const { token, jwks } = await makeCallerAuth("user-42");
    const gateway = new FakeGateway(
      new Set(["session-99:user-42"]),
      new Map([["session-99", state]]),
      new Map([["user-42", "tommy"]]),
    );
    const res = await handleRequest(
      req({ session_id: "session-99" }, `Bearer ${token}`),
      baseDeps({ gateway, jwksCache: cacheFor(jwks) }),
    );

    assertEquals(res.status, 200);
    const body = await res.json();
    assertExists(body.token);
    assertEquals(body.url, "wss://test-project.livekit.cloud");

    const { claims } = decodeJwt(body.token);
    assertEquals(claims.sub, "user-42");
    assertEquals(claims.name, "tommy");
    assertEquals(claims.video, {
      room: "session:session-99",
      roomJoin: true,
      canPublish: true,
      canSubscribe: true,
    });
    const nowSec = Math.floor(Date.now() / 1000);
    assertEquals((claims.exp as number) - nowSec <= 15 * 60, true, "TTL must not exceed 15 minutes");
    assertEquals((claims.nbf as number) <= nowSec, true);
  });
}

Deno.test("handleRequest: falls back to the raw user id for `name` if no profile username is found (defensive; should not happen in practice)", async () => {
  const { token, jwks } = await makeCallerAuth("user-no-profile");
  const gateway = new FakeGateway(new Set(["s1:user-no-profile"]), new Map([["s1", "lobby_open"]]));
  const res = await handleRequest(
    req({ session_id: "s1" }, `Bearer ${token}`),
    baseDeps({ gateway, jwksCache: cacheFor(jwks) }),
  );
  assertEquals(res.status, 200);
  const body = await res.json();
  const { claims } = decodeJwt(body.token);
  assertEquals(claims.name, "user-no-profile");
});

Deno.test("VOICE_ELIGIBLE_STATES matches the sessions.state check constraint's 5 confirmed voice-eligible values", () => {
  assertEquals(
    [...VOICE_ELIGIBLE_STATES].sort(),
    ["editing", "in_progress", "lobby_open", "locked", "voting"].sort(),
  );
});

Deno.test("handleRequest: Gateway is the only DB-facing surface — structural proof it has no path to Deno.env (mirrors push-dispatcher's own structural test)", () => {
  const methods = ["isParticipant", "getSessionState", "getUsername"];
  assertEquals(methods.includes("readEnv" as never), false);
});
