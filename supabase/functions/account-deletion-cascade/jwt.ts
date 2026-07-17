// jwt.ts — verifies the CALLER's Supabase-issued JWT locally against the
// project's JWKS, so index.ts can trust `sub` as the caller's own user id
// without a network round-trip to Supabase Auth for every request.
//
// This is the verify-only half of supabase/functions/livekit-token/jwt.ts
// (decodeJwt + JwksCache + verifySupabaseJwt, byte-for-byte the same
// algorithm/validation), duplicated rather than imported. Precedent for
// per-function self-containment: this repo has no `_shared` functions
// folder — push-dispatcher hand-rolls its own ES256 JWT signing in apns.ts,
// and livekit-token hand-rolls its own JWT verification here, rather than
// either importing from the other. account-deletion-cascade is DESTRUCTIVE;
// a cross-function import would mean a future edit to livekit-token/jwt.ts
// (a function with a completely different purpose) could silently change
// this function's auth behavior. mintLiveKitToken() (the other half of the
// source file) is dropped — this function never mints anything.
//
// Every function here takes its clock as an injectable optional `now` (ms
// epoch) so tests never depend on real time.

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
 * signature. Throws on anything that isn't three dot-separated base64url
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

export interface Jwk extends JsonWebKey {
  kid?: string;
}

export interface Jwks {
  keys: Jwk[];
}

const DEFAULT_JWKS_TTL_MS = 10 * 60 * 1000;

/**
 * Caches the JWKS document in module/instance scope so repeated calls don't
 * hit `/auth/v1/.well-known/jwks.json` on every request. `fetchImpl` is
 * injectable so tests never touch the network; `ttlMs` and the `now` passed
 * to getJwks() are both parameters (not Date.now() calls inside the class)
 * so cache-expiry tests never need real sleeps.
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
 * checks `aud`, fetches (or reuses the cached) JWKS, finds the matching key
 * by `kid`, and verifies the signature over the exact bytes that were
 * signed. Throws on any failure — callers (index.ts) catch and map to 401,
 * never distinguishing failure reasons to the client beyond "unauthorized".
 *
 * This is the ONLY source of `userId` this function ever trusts — there is
 * no request-body user-id parameter anywhere in this function (deliberate:
 * a caller must never be able to delete someone else's account by passing
 * a different id).
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
