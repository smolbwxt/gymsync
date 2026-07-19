import Foundation
import Supabase

enum GymSyncError: LocalizedError {
    case network
    case unauthorized
    case notFound
    case validation(String)
    case unknown(String)
    /// Phase O Task 3 — duplicate-PK insert (Postgres SQLSTATE 23505 on
    /// `set_logs_pkey`). Distinguished from `.validation` specifically so
    /// `OfflineSetLogQueue.replay()` can tell "this exact row already landed
    /// server-side in a prior partial replay" (idempotent-retry success, per
    /// master spec §6.4 — client-generated UUID PKs make INSERTs idempotent)
    /// apart from a genuine, non-retryable validation failure. Live-probed
    /// against the actual PostgREST HTTP layer (not just raw Postgres) —
    /// see task-3-report.md's discovery section for the transcript: a
    /// duplicate insert returns HTTP 409 with JSON body
    /// `{"code":"23505", "message":"duplicate key value violates unique
    /// constraint \"set_logs_pkey\"", ...}`, which `PostgrestError.code`
    /// decodes verbatim.
    case conflict

    var errorDescription: String? {
        switch self {
        case .network: return "Network issue. Check your connection and try again."
        case .unauthorized: return "You're signed out. Please sign in again."
        case .notFound: return "We couldn't find that."
        case .validation(let msg): return msg
        case .unknown(let msg): return msg
        case .conflict: return "That was already saved."
        }
    }
}

enum ErrorMapping {
    static func map(_ error: Error) -> GymSyncError {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .notConnectedToInternet, .timedOut, .networkConnectionLost:
                return .network
            default: return .unknown(urlErr.localizedDescription)
            }
        }
        if error is AuthError {
            return .unauthorized
        }
        if let pg = error as? PostgrestError {
            if pg.code == "PGRST116" { return .notFound }
            // Phase O Task 3 — unique-violation on a client-generated PK means
            // this exact row (same id) already exists server-side, not a real
            // validation problem. Checked BEFORE the generic `.validation`
            // fallback below so callers (OfflineSetLogQueue.replay()) can
            // treat it as "already landed" rather than a permanent failure.
            if pg.code == "23505" { return .conflict }
            return .validation(pg.message)
        }
        return .unknown(error.localizedDescription)
    }
}
