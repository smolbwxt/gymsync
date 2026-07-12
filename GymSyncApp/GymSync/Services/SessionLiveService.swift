import Foundation
import Supabase

/// Drives live-session realtime updates via a single channel `session:{id}:live`.
/// Three postgres_changes streams:
///   - sessions UPDATE (filter id)         → decoded WorkoutSession → onSessionChange
///   - session_participants ALL (filter session_id) → coarse onParticipantsChange
///   - set_logs INSERT (filter session_id)  → decoded SetLog        → onSetLogged
///
/// Pattern mirrors ChatRealtimeService / LobbyRealtimeService:
///   stream-before-subscribe, task lifecycle, full teardown.
@MainActor
final class SessionLiveService {
    private var channel: RealtimeChannelV2?
    private var streamTask: Task<Void, Never>?

    // Postgrest timestamps: fractional or plain ISO 8601.
    // Identical decoder shared across all realtime services.
    nonisolated static let postgresDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { dec in
            let value = try dec.singleValueContainer().decode(String.self)
            if let date = fractional.date(from: value) ?? plain.date(from: value) {
                return date
            }
            throw DecodingError.dataCorrupted(.init(
                codingPath: dec.codingPath,
                debugDescription: "unparseable timestamp: \(value)"))
        }
        return decoder
    }()

    /// Subscribe to live-session streams.
    ///
    /// - Parameters:
    ///   - sessionID:            Session to watch.
    ///   - onSessionChange:      Called on any sessions UPDATE with the decoded row.
    ///   - onParticipantsChange: Called on any session_participants change (coarse — caller refetches).
    ///   - onSetLogged:          Called on each set_logs INSERT with the decoded SetLog.
    func subscribe(
        sessionID: UUID,
        onSessionChange: @escaping @MainActor (WorkoutSession) -> Void,
        onParticipantsChange: @escaping @MainActor () -> Void,
        onSetLogged: @escaping @MainActor (SetLog) -> Void
    ) async {
        // Tear down any previous subscription first.
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel("session:\(sessionID.uuidString):live")

        // ── Stream registrations (must happen BEFORE subscribe) ──────────
        let sessionUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "sessions",
            filter: "id=eq.\(sessionID.uuidString)"
        )

        let participantInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let participantUpdates = ch.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let participantDeletes = ch.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )

        let setLogInserts = ch.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "set_logs",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )

        channel = ch
        await ch.subscribe()

        // ── Consume all streams in one structured task group ─────────────
        streamTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await action in sessionUpdates {
                        do {
                            let session = try action.decodeRecord(
                                decoder: SessionLiveService.postgresDecoder) as WorkoutSession
                            onSessionChange(session)
                        } catch {
                            AppLogger.sessions.error(
                                "live: sessions decode failed: \(error, privacy: .public)")
                        }
                    }
                }
                group.addTask { @MainActor in
                    for await _ in participantInserts { onParticipantsChange() }
                }
                group.addTask { @MainActor in
                    for await _ in participantUpdates { onParticipantsChange() }
                }
                group.addTask { @MainActor in
                    for await _ in participantDeletes { onParticipantsChange() }
                }
                group.addTask { @MainActor in
                    for await action in setLogInserts {
                        do {
                            let setLog = try action.decodeRecord(
                                decoder: SessionLiveService.postgresDecoder) as SetLog
                            onSetLogged(setLog)
                        } catch {
                            AppLogger.sessions.error(
                                "live: set_logs decode failed: \(error, privacy: .public)")
                        }
                    }
                }
            }
        }
    }

    /// Cancel all stream tasks and remove the realtime channel.
    func unsubscribe() async {
        streamTask?.cancel()
        streamTask = nil
        if let channel {
            await SupabaseService.shared.client.removeChannel(channel)
        }
        channel = nil
    }
}
