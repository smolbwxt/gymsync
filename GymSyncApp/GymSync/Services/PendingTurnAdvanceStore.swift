import Foundation

// MARK: - PendingTurnAdvanceStore
//
// The other half of the rotation guard (migration 20260801000001).
//
// When a set is logged in a group session and the write fails with
// `.network`, the set itself is queued (`OfflineSetLogQueue`) but the TURN
// ADVANCE was historically dropped on the floor and never retried — so one
// lifter's dead signal froze the rotation for everyone until somebody
// advanced it by hand. This records the advance that was owed, along with
// the `turn_version` observed at the time, and replays it once the network
// is back.
//
// WHY NOT SwiftData, where `PendingSetLog` lives: `PendingSetLog` is an
// already-shipped `@Model` and this repo has no versioned-schema migration
// plan, so adding a second entity to that container risks the very data the
// offline queue exists to protect. A pending advance is one small, ephemeral
// fact per session — UserDefaults is the honest fit, and it survives a
// relaunch, which is the only durability this needs.
//
// SAFETY: replay is safe BECAUSE of the server-side version guard, not
// because this store is careful. `advance_turn(p_session_id, p_expected_version)`
// no-ops when the rotation has already moved on, so a stale or duplicated
// entry here can never double-advance a session.
@MainActor
final class PendingTurnAdvanceStore {
    static let shared = PendingTurnAdvanceStore()

    private let key = "pendingTurnAdvances.v1"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// sessionID (uuid string, lowercased) -> the turn_version observed when
    /// the advance became owed. At most ONE entry per session: a lifter can
    /// only owe the rotation one advance at a time, and a newer observation
    /// supersedes an older one.
    private var entries: [String: Int] {
        get { (defaults.dictionary(forKey: key) as? [String: Int]) ?? [:] }
        set {
            if newValue.isEmpty {
                defaults.removeObject(forKey: key)
            } else {
                defaults.set(newValue, forKey: key)
            }
        }
    }

    var isEmpty: Bool { entries.isEmpty }

    func record(sessionID: UUID, observedVersion: Int) {
        var current = entries
        current[sessionID.uuidString.lowercased()] = observedVersion
        entries = current
    }

    func clear(sessionID: UUID) {
        var current = entries
        current.removeValue(forKey: sessionID.uuidString.lowercased())
        entries = current
    }

    func pendingVersion(for sessionID: UUID) -> Int? {
        entries[sessionID.uuidString.lowercased()]
    }

    /// Replay every owed advance. Best-effort by design: an entry is cleared
    /// when the RPC returns — including when it no-ops because the rotation
    /// already moved, which IS success — and left in place on a network
    /// failure so the next drain retries it. A non-network failure also
    /// clears, because retrying a rejected advance forever would be worse
    /// than dropping it (the organizer can always advance manually).
    func replay() async {
        let owed = entries
        guard !owed.isEmpty else { return }
        for (sessionKey, version) in owed {
            guard let sessionID = UUID(uuidString: sessionKey) else {
                clearRaw(sessionKey)
                continue
            }
            do {
                try await SessionRepository.advanceTurn(sessionID: sessionID,
                                                        expectedVersion: version)
                clear(sessionID: sessionID)
                AppLogger.sessions.info("Replayed queued turn advance for session \(sessionID, privacy: .public)")
            } catch let error as GymSyncError {
                if case .network = error {
                    // Still offline — keep it for the next drain.
                    continue
                }
                clearRaw(sessionKey)
                AppLogger.sessions.error("Dropped queued turn advance for session \(sessionID, privacy: .public): \(error.localizedDescription, privacy: .public)")
            } catch {
                clearRaw(sessionKey)
            }
        }
    }

    private func clearRaw(_ sessionKey: String) {
        var current = entries
        current.removeValue(forKey: sessionKey)
        entries = current
    }
}
