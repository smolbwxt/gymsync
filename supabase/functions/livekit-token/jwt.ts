// jwt.ts — two independent JWT concerns for livekit-token, both hand-rolled
// WebCrypto (no external JWT library — mirrors this repo's own apns.ts,
// which signs its own ES256 JWTs rather than pulling in a dependency):
//
//   1. verifySupabaseJwt(): verifies the CALLER's Supabase-issued JWT
//      locally against the project's JWKS (RS256 or ES256, whichever this
//      project's signing keys use) instead of round-tripping to Supabase
//      Auth. JWK public keys import directly via
//      crypto.subtle.importKey("jwk", ...) — no PEM/DER step needed here
//      (unlike apns.ts's PKCS8 PEM import), since JWKS already hands us
//      the key in the format WebCrypto wants.
//   2. mintLiveKitToken(): mints the short-lived LiveKit access token
//      (HS256) this function hands back to the caller, per the shape
//      verified against livekit/node-sdks' AccessToken.toJwt() (Dossier
//      §B.2): header {alg:"HS256"}, claims iss/sub/nbf/exp/video, HMAC-
//      SHA256 over header.claims with LIVEKIT_API_SECRET.
//
// Every function here takes its clock as an injectable optional `now`
// (ms epoch) so tests never depend on real time.

export interface JwtHeader {
  alg: string;
  kid?: string;
  typ?: string;
  [key: string]: unknown;
}

export type JwtClaims = Record<string, unknown>;

export interface DecodedJwt {
  header: JwtHeader;
  claims: JwtClaims;
  /** `${headerB64}.${claimsB64}` — exactly the bytes that were signed. */
  signingInput: string;
  signature: Uint8Array<ArrayBuffer>;
}

function base64urlFromBytes(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64urlToBytes(segment: string): Uint8Array<ArrayBuffer> {
  const b64 = segment.replace(/-/g, "+").replace(/_/g, "/");
  const padded = b64.padEnd(b64.length + ((4 - (b64.length % 4)) % 4), "=");
  const binary = atob(padded);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function base64urlToString(segment: string): string {
  return new TextDecoder().decode(base64urlToBytes(segment));
}

/**
 * Splits a JWT into header/claims/signature without verifying the
 * signature — used both to inspect the caller's token before verification
 * (read `alg`/`kid` to pick a key) and by tests to decode a minted LiveKit
 * token. Throws on anything that isn't three dot-separated base64url
 * segments of valid JSON, so a malformed/garbage token surfaces as a
 * rejected Promise (mapped to 401 by index.ts) rather than a crash deeper
 * in the verify path.
 */
export function decodeJwt(token: string): DecodedJwt {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("malformed_jwt: expected 3 dot-separated segments");
  }
  const [headerB64, claimsB64, sigB64] = parts;

  let header: JwtHeader;
  let claims: JwtClaims;
  try {
    header = JSON.parse(base64urlToString(headerB64));
    claims = JSON.parse(base64urlToString(claimsB64));
  } catch {
    throw new Error("malformed_jwt: header/claims are not valid JSON");
  }

  return {
    header,
    claims,
    signingInput: `${headerB64}.${claimsB64}`,
    signature: base64urlToBytes(sigB64),
  };
}

// ============================================================
// 1. Caller JWT verification against the project's JWKS
// ============================================================

export interface Jwk extends JsonWebKey {
  kid?: string;
}

export interface Jwks {
  keys: Jwk[];
}

const DEFAULT_JWKS_TTL_MS = 10 * 60 * 1000;

/**
 * Caches the JWKS document in module/instance scope so a busy voice room
 * (many token mints) doesn't hit `/auth/v1/.well-known/jwks.json` on every
 * request. `fetchImpl` is injectable so tests never touch the network;
 * `ttlMs` and the `now` passed to getJwks() are both parameters (not
 * Date.now() calls inside the class) so cache-expiry tests never need real
 * sleeps.
 */
export class JwksCache {
  private cached: { jwks: Jwks; fetchedAt: number } | null = null;

  constructor(
    private readonly jwksUrl: string,
    private readonly fetchImpl: typeof fetch,
    private readonly ttlMs: number = DEFAULT_JWKS_TTL_MS,
  ) {}

  async getJwks(now: number = Date.now()): Promise<Jwks> {
    if (this.cached && now - this.cached.fetchedAt < this.ttlMs) {
      return this.cached.jwks;
    }
    const res = await this.fetchImpl(this.jwksUrl);
    if (!res.ok) {
      throw new Error(`jwks_fetch_failed: status ${res.status}`);
    }
    const jwks = (await res.json()) as Jwks;
    this.cached = { jwks, fetchedAt: now };
    return jwks;
  }
}

type SupportedAlg = "ES256" | "RS256";

function isSupportedAlg(alg: unknown): alg is SupportedAlg {
  return alg === "ES256" || alg === "RS256";
}

async function importVerifyKey(jwk: JsonWebKey, alg: SupportedAlg): Promise<CryptoKey> {
  if (alg === "ES256") {
    return await crypto.subtle.importKey("jwk", jwk, { name: "ECDSA", namedCurve: "P-256" }, false, ["verify"]);
  }
  return await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"]);
}

async function verifySignature(
  alg: SupportedAlg,
  key: CryptoKey,
  signature: Uint8Array<ArrayBuffer>,
  data: Uint8Array<ArrayBuffer>,
): Promise<boolean> {
  if (alg === "ES256") {
    return await crypto.subtle.verify({ name: "ECDSA", hash: "SHA-256" }, key, signature, data);
  }
  return await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, data);
}

export interface VerifySupabaseJwtOptions {
  jwksCache: JwksCache;
  /** Checked against `claims.aud` when provided; Supabase user JWTs carry `"authenticated"`. */
  audience?: string;
  /** Injectable clock (ms epoch) for expiry tests. */
  now?: number;
}

/**
 * Verifies a Supabase-issued user JWT locally: decodes it, rejects
 * unsupported/missing alg or kid, rejects an expired token, optionally
 * checks `aud`, fetches (or reuses the cached) JWKS, finds the matching
 * key by `kid`, and verifies the signature over the exact bytes that were
 * signed. Throws on any failure — callers (index.ts) catch and map to 401,
 * never distinguishing failure reasons to the client beyond "unauthorized".
 */
export async function verifySupabaseJwt(
  token: string,
  opts: VerifySupabaseJwtOptions,
): Promise<{ sub: string; claims: JwtClaims }> {
  const decoded = decodeJwt(token);

  const alg = decoded.header.alg;
  if (!isSupportedAlg(alg)) {
    throw new Error(`unsupported_alg: ${String(alg)}`);
  }

  const kid = decoded.header.kid;
  if (typeof kid !== "string" || kid.length === 0) {
    throw new Error("missing_kid");
  }

  const now = opts.now ?? Date.now();
  const nowSec = Math.floor(now / 1000);
  const exp = decoded.claims.exp;
  if (typeof exp !== "number" || exp <= nowSec) {
    throw new Error("token_expired");
  }

  if (opts.audience !== undefined && decoded.claims.aud !== opts.audience) {
    throw new Error("audience_mismatch");
  }

  const jwks = await opts.jwksCache.getJwks(now);
  const jwk = jwks.keys.find((k) => k.kid === kid);
  if (!jwk) {
    throw new Error("signing_key_not_found");
  }

  const key = await importVerifyKey(jwk, alg);
  const valid = await verifySignature(
    alg,
    key,
    decoded.signature,
    new TextEncoder().encode(decoded.signingInput),
  );
  if (!valid) {
    throw new Error("invalid_signature");
  }

  const sub = decoded.claims.sub;
  if (typeof sub !== "string" || sub.length === 0) {
    throw new Error("missing_sub");
  }

  return { sub, claims: decoded.claims };
}

// ============================================================
// 2. LiveKit access-token minting
// ============================================================

export interface LiveKitVideoGrant {
  room: string;
  roomJoin: boolean;
  canPublish: boolean;
  canSubscribe: boolean;
}

export interface MintLiveKitTokenParams {
  apiKey: string;
  apiSecret: string;
  /** Participant identity — required whenever video.roomJoin is set. */
  identity: string;
  /** Participant display label (Dossier: "name = username"). Omitted if not provided. */
  name?: string;
  grant: LiveKitVideoGrant;
  /** Defaults to 900 (15 min), per the spec's TTL. */
  ttlSeconds?: number;
  /** Injectable clock (ms epoch) for tests. */
  now?: number;
}

const DEFAULT_TTL_SECONDS = 15 * 60;

/**
 * Mints a LiveKit access token: HS256 JWT signed with LIVEKIT_API_SECRET,
 * shape verified against livekit/node-sdks' AccessToken.toJwt() (Dossier
 * §B.2) — iss = api key, sub = identity, nbf = now, exp = now + ttl,
 * video = grant. No `jti` (the reference implementation doesn't set one).
 */
export async function mintLiveKitToken(params: MintLiveKitTokenParams): Promise<string> {
  const now = params.now ?? Date.now();
  const nowSec = Math.floor(now / 1000);
  const ttlSeconds = params.ttlSeconds ?? DEFAULT_TTL_SECONDS;

  const header: JwtHeader = { alg: "HS256", typ: "JWT" };
  const claims: JwtClaims = {
    iss: params.apiKey,
    sub: params.identity,
    nbf: nowSec,
    exp: nowSec + ttlSeconds,
    video: params.grant,
    ...(params.name ? { name: params.name } : {}),
  };

  const headerB64 = base64urlFromBytes(new TextEncoder().encode(JSON.stringify(header)));
  const claimsB64 = base64urlFromBytes(new TextEncoder().encode(JSON.stringify(claims)));
  const signingInput = `${headerB64}.${claimsB64}`;

  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(params.apiSecret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(signingInput));

  return `${signingInput}.${base64urlFromBytes(new Uint8Array(signature))}`;
}
