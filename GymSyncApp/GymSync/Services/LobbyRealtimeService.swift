import Foundation
import Supabase

// SDK drift note (supabase-swift 2.51):
//   - presenceChange() yields PresenceAction with .joins/.leaves diffs keyed by presence key.
//     There is NO presenceState() method; we maintain a local [key → payload] map instead.
//   - track(state:) takes a labeled `state:` parameter of type JSONObject ([String: AnyJSON]).
//   - AnyAction does not exist; use separate InsertAction / UpdateAction / DeleteAction streams.

@MainActor
final class LobbyRealtimeService {
    // MARK: - Presence channel (lobby:{sessionID})
    private var presenceChannel: RealtimeChannelV2?
    private var presenceTask: Task<Void, Never>?

    // MARK: - DB channel (session:{sessionID}:db)
    private var dbChannel: RealtimeChannelV2?
    private var dbTask: Task<Void, Never>?

    // Postgrest timestamps: "2026-07-10T19:00:00.123456+00:00" (fractional) or without.
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

    /// Subscribe to presence and DB change streams for a lobby session.
    ///
    /// - Parameters:
    ///   - sessionID: The session being watched.
    ///   - selfID:    The current user's UUID (tracked into presence).
    ///   - username:  The current user's display name (tracked into presence).
    ///   - onPresence: Called on MainActor whenever the presence set changes.
    ///                 Receives ALL UUIDs currently in the lobby, including self.
    ///   - onChange:  Called on MainActor on ANY postgres_changes event.
    ///                Caller is expected to refetch sessions, participants, and proposals.
    func subscribe(
        sessionID: UUID,
        selfID: UUID,
        username: String,
        onPresence: @escaping @MainActor (Set<UUID>) -> Void,
        onChange: @escaping @MainActor () -> Void
    ) async {
        // Always clean up any previous subscription first.
        await unsubscribe()

        // ── Presence channel ────────────────────────────────────────────────
        let pChannel = SupabaseService.shared.client
            .channel("lobby:\(sessionID.uuidString)")
        let presenceDiff = pChannel.presenceChange()
        presenceChannel = pChannel
        await pChannel.subscribe()

        // Track self with spec wire shape.
        await pChannel.track(state: [
            "user_id":        .string(selfID.uuidString),
            "username":       .string(username),
            "app_state":      .string("active"),
            "check_in_state": .string("")
        ])

        presenceTask = Task { @MainActor in
            // Local map from presence key → user UUID; mutated on each diff.
            var tracked: [String: UUID] = [:]
            for await action in presenceDiff {
                for (key, pv) in action.joins {
                    // Parse user_id from the presence payload; ignore entries without it.
                    if let raw = pv.state["user_id"]?.stringValue,
                       let uid = UUID(uuidString: raw) {
                        tracked[key] = uid
                    }
                }
                for key in action.leaves.keys {
                    tracked.removeValue(forKey: key)
                }
                onPresence(Set(tracked.values))
            }
        }

        // ── DB channel ───────────────────────────────────────────────────────
        let dChannel = SupabaseService.shared.client
            .channel("session:\(sessionID.uuidString):db")

        // sessions UPDATE — filter by session id
        let sessionUpdates = dChannel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "sessions",
            filter: "id=eq.\(sessionID.uuidString)"
        )

        // session_participants — Insert, Update, Delete scoped to this session
        let participantInserts = dChannel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let participantUpdates = dChannel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let participantDeletes = dChannel.postgresChange(
            DeleteAction.self,
            schema: "public",
            table: "session_participants",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )

        // routine_proposals — Insert + Update scoped to this session
        let proposalInserts = dChannel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "routine_proposals",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )
        let proposalUpdates = dChannel.postgresChange(
            UpdateAction.self,
            schema: "public",
            table: "routine_proposals",
            filter: "session_id=eq.\(sessionID.uuidString)"
        )

        // routine_proposal_votes — Insert UNFILTERED (no session_id column; RLS/WALRUS scopes)
        let voteInserts = dChannel.postgresChange(
            InsertAction.self,
            schema: "public",
            table: "routine_proposal_votes"
        )

        dbChannel = dChannel
        await dChannel.subscribe()

        dbTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { @MainActor in
                    for await _ in sessionUpdates    { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in participantInserts { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in participantUpdates { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in participantDeletes { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in proposalInserts   { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in proposalUpdates   { onChange() }
                }
                group.addTask { @MainActor in
                    for await _ in voteInserts       { onChange() }
                }
            }
        }
    }

    /// Remove both channels and cancel all stream tasks.
    func unsubscribe() async {
        presenceTask?.cancel()
        presenceTask = nil
        dbTask?.cancel()
        dbTask = nil

        if let presenceChannel {
            // Untrack self before removing the channel.
            await presenceChannel.untrack()
            await SupabaseService.shared.client.removeChannel(presenceChannel)
        }
        presenceChannel = nil

        if let dbChannel {
            await SupabaseService.shared.client.removeChannel(dbChannel)
        }
        dbChannel = nil
    }
}
