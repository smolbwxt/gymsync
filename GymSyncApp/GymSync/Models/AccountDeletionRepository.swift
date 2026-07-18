import Foundation
import Supabase

// ============================================================
// Phase M / Task 4: Delete Account — Edge Function invoke wrapper
// ============================================================
// `account-deletion-cascade` (supabase/functions/account-deletion-cascade/
// index.ts, Task 3) permanently deletes the CALLING user's own account.
// Auth model per that function's own header comment: the caller is
// identified ONLY by their own Supabase JWT (verified server-side against
// the project's JWKS) — there is no user-id request parameter anywhere in
// the function, so this client never sends one either. `client.functions.
// invoke` forwards the signed-in user's JWT automatically (same
// no-manual-Authorization-header behavior VoiceRoomService.swift's
// SupabaseVoiceTokenFetcher documents for `livekit-token`), so this call
// needs no body and no explicit auth header.
enum AccountDeletionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Response shape `account-deletion-cascade` returns on success
    /// (index.ts's `DeletionResult` interface, lines 310-315: userId +
    /// 3 reassignment counters). Only decoded to confirm a well-formed 2xx
    /// JSON body came back — the UI has no use for any of these fields, so
    /// only `userId` is declared (matches VoiceTokenResponse's "decode
    /// exactly what the caller needs" idiom, not the function's full
    /// shape).
    private struct DeletionResponse: Decodable {
        let userId: String
    }

    /// Invokes `account-deletion-cascade` for the current signed-in user.
    /// Throws on any non-2xx response — 401 (`unauthorized`/missing or
    /// invalid token, shouldn't happen for an already-authenticated caller
    /// but handled the same as any other error) or 500 (`internal_error`,
    /// the function's own catch-all) — which the caller maps through
    /// `ErrorMapping.map(_:)` like every other repository call in this
    /// codebase. Does NOT sign the user out itself — that stays the
    /// caller's job (`DeleteAccountSheet` calls
    /// `AuthService.forceSignedOutAfterDeletion()` only after this returns
    /// without throwing), so a network hiccup here can never leave the app
    /// showing a signed-out UI for an account that was never actually
    /// deleted — and conversely, once the cascade succeeds the user is
    /// always forced signed-out even if the local session revoke fails.
    ///
    /// ASSUMPTION (same caveat VoiceRoomService.swift's
    /// SupabaseVoiceTokenFetcher documents — no Mac/Xcode this session to
    /// compile-check against the vendored `Supabase` package source):
    /// `client.functions.invoke(_:)` has a body-less overload (no
    /// `options:` argument needed) for a request with no payload, decoding
    /// the response generically from the inferred return type. If CI's
    /// build-test job fails to compile here, this is the first place to
    /// check.
    static func deleteAccount() async throws {
        do {
            let _: DeletionResponse = try await client.functions.invoke("account-deletion-cascade")
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
