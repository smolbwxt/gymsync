// apns.ts — APNs HTTP/2 provider delivery, token-based (ES256 JWT) auth.
// Deno's built-in fetch speaks HTTP/2 automatically, so no separate client
// library is needed for the transport; this module only needs to build the
// JWT (WebCrypto) and the per-device POST.

export interface ApnsConfig {
  keyId: string;
  teamId: string;
  /** Contents of the .p8 file (PKCS8 PEM), as-is. */
  privateKeyPem: string;
  topic: string;
  /** Overridable for tests; defaults to the production APNs host. */
  host?: string;
}

export interface ApnsAlertPayload {
  aps: {
    alert: { title: string; body: string };
    category?: string;
    "thread-id"?: string;
  };
  [key: string]: unknown;
}

export interface ApnsSendResult {
  status: number;
  ok: boolean;
  /** The `reason` field from APNs' JSON error body, e.g. "BadDeviceToken". */
  reason?: string;
}

// Apple's tokens are valid up to 1h; refresh well before that so a
// straddling request never gets caught with an expired token.
const TOKEN_TTL_MS = 50 * 60 * 1000;

function base64url(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

/** Strips PEM armor/whitespace and decodes the base64 body to raw DER bytes. */
function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN [^-]+-----/, "")
    .replace(/-----END [^-]+-----/, "")
    .replace(/\s+/g, "");
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export class ApnsClient {
  private config: ApnsConfig;
  private cachedToken: string | null = null;
  private cachedAt = 0;
  private cryptoKey: CryptoKey | null = null;

  constructor(config: ApnsConfig) {
    this.config = config;
  }

  private async importKey(): Promise<CryptoKey> {
    if (this.cryptoKey) return this.cryptoKey;
    const der = pemToDer(this.config.privateKeyPem);
    this.cryptoKey = await crypto.subtle.importKey(
      "pkcs8",
      der,
      { name: "ECDSA", namedCurve: "P-256" },
      false,
      ["sign"],
    );
    return this.cryptoKey;
  }

  /**
   * Returns a cached JWT if it's under TOKEN_TTL_MS old, otherwise mints a
   * fresh one. `now` is injectable (defaults to Date.now()) so tests can
   * exercise the cache/expiry boundary without real sleeps.
   */
  async getToken(now: number = Date.now()): Promise<string> {
    if (this.cachedToken && now - this.cachedAt < TOKEN_TTL_MS) {
      return this.cachedToken;
    }
    const token = await this.signToken(now);
    this.cachedToken = token;
    this.cachedAt = now;
    return token;
  }

  private async signToken(now: number): Promise<string> {
    const header = { alg: "ES256", kid: this.config.keyId };
    const claims = { iss: this.config.teamId, iat: Math.floor(now / 1000) };
    const headerB64 = base64url(new TextEncoder().encode(JSON.stringify(header)));
    const claimsB64 = base64url(new TextEncoder().encode(JSON.stringify(claims)));
    const signingInput = `${headerB64}.${claimsB64}`;

    const key = await this.importKey();
    // WebCrypto's ECDSA signatures are the raw IEEE-P1363 r||s concatenation
    // (no ASN.1/DER wrapping) — this is exactly the format JWS ES256
    // (RFC 7518 §3.4) requires, so no conversion step is needed here.
    const signature = await crypto.subtle.sign(
      { name: "ECDSA", hash: "SHA-256" },
      key,
      new TextEncoder().encode(signingInput),
    );

    return `${signingInput}.${base64url(signature)}`;
  }

  /**
   * Sends one alert push to one device token. `fetchImpl` is injectable so
   * tests never touch the network — production code (index.ts) passes the
   * real global `fetch`.
   */
  async send(
    deviceToken: string,
    payload: ApnsAlertPayload,
    fetchImpl: typeof fetch = fetch,
  ): Promise<ApnsSendResult> {
    const host = this.config.host ?? "https://api.push.apple.com";
    const token = await this.getToken();

    const res = await fetchImpl(`${host}/3/device/${deviceToken}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${token}`,
        "apns-topic": this.config.topic,
        "apns-push-type": "alert",
        "content-type": "application/json",
      },
      body: JSON.stringify(payload),
    });

    if (res.ok) {
      return { status: res.status, ok: true };
    }

    let reason: string | undefined;
    try {
      const body = await res.json();
      if (body && typeof body.reason === "string") reason = body.reason;
    } catch {
      // Non-JSON or empty error body — reason stays undefined, caller falls
      // back to status-code-only handling.
    }
    return { status: res.status, ok: false, reason };
  }
}

/** Decodes a JWT's header/claims without verifying the signature — for tests. */
export function decodeJwt(token: string): { header: Record<string, unknown>; claims: Record<string, unknown> } {
  const [headerB64, claimsB64] = token.split(".");
  const pad = (s: string) => s.replace(/-/g, "+").replace(/_/g, "/").padEnd(s.length + ((4 - (s.length % 4)) % 4), "=");
  const header = JSON.parse(atob(pad(headerB64)));
  const claims = JSON.parse(atob(pad(claimsB64)));
  return { header, claims };
}
