import Foundation
import Supabase

enum GymSyncError: LocalizedError {
    case network
    case unauthorized
    case notFound
    case validation(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .network: return "Network issue. Check your connection and try again."
        case .unauthorized: return "You're signed out. Please sign in again."
        case .notFound: return "We couldn't find that."
        case .validation(let msg): return msg
        case .unknown(let msg): return msg
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
            return .validation(pg.message)
        }
        return .unknown(error.localizedDescription)
    }
}
