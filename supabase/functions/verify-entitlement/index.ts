// index.ts — verify-entitlement Edge Function (Monetization M1).
//
// The ONLY writer of profiles.pro_until (guard trigger 20260730000004
// blocks client writes — "a client-writable is_pro would be spoofable in
// an afternoon"). The client forwards its StoreKit 2 transaction as
// Apple's signed JWS; this function sanity-checks the payload and writes
// the entitlement via service role.
//
// M1 TRUST MODEL (explicit, not silently assumed):
//   - The CALLER is authenticated by the platform gateway (verify_jwt,
//     the functions default) — we read the already-verified JWT's `sub`.
//   - The JWS is Apple-signed and was verified ON-DEVICE by StoreKit 2
//     before the client ever saw it. Server-side verification of the
//     x5c chain against Apple's roots is the M1.5 hardening; until then
//     the payload checks below (bundle, product, expiry) bound the blast
//     radius of a hand-rolled JWS to "attacker grants themselves Pro",
//     which the App Store Server Notifications integration will revoke.
//
// pro_until only ever moves FORWARD here — a stale or replayed JWS can
// never shorten an entitlement someone paid for.

import { createClient } from "@supabase/supabase-js";

const BUNDLE_ID = "app.gymsync.ios";
const PRODUCT_IDS = new Set(["gymsync.pro.monthly", "gymsync.pro.yearly"]);

function b64urlJson(segment: string): Record<string, unknown> {
  const pad = segment.length % 4 === 0 ? "" : "=".repeat(4 - (segment.length % 4));
  const b64 = segment.replaceAll("-", "+").replaceAll("_", "/") + pad;
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(b64), (c) => c.charCodeAt(0))));
}

Deno.serve(async (req) => {
  try {
    const auth = req.headers.get("Authorization") ?? "";
    const jwt = auth.replace(/^Bearer\s+/i, "");
    const jwtParts = jwt.split(".");
    if (jwtParts.length !== 3) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }
    const userId = String(b64urlJson(jwtParts[1]).sub ?? "");
    if (!userId) {
      return Response.json({ error: "unauthorized" }, { status: 401 });
    }

    const { jws } = await req.json();
    const jwsParts = typeof jws === "string" ? jws.split(".") : [];
    if (jwsParts.length !== 3) {
      return Response.json({ error: "bad jws" }, { status: 400 });
    }
    const tx = b64urlJson(jwsParts[1]);

    if (tx.bundleId !== BUNDLE_ID || !PRODUCT_IDS.has(String(tx.productId))) {
      return Response.json({ error: "wrong product" }, { status: 400 });
    }
    const expiresMs = Number(tx.expiresDate ?? 0);
    if (!expiresMs || expiresMs <= Date.now()) {
      return Response.json({ error: "expired" }, { status: 400 });
    }

    const service = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Forward-only: never shorten an existing entitlement.
    const { data: profile } = await service
      .from("profiles").select("pro_until").eq("id", userId).single();
    const current = profile?.pro_until ? Date.parse(profile.pro_until) : 0;
    const next = Math.max(current, expiresMs);

    const { error } = await service
      .from("profiles")
      .update({ pro_until: new Date(next).toISOString() })
      .eq("id", userId);
    if (error) {
      return Response.json({ error: "write failed" }, { status: 500 });
    }
    return Response.json({ pro_until: new Date(next).toISOString() });
  } catch {
    return Response.json({ error: "bad request" }, { status: 400 });
  }
});
