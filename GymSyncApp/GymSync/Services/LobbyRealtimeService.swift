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

    // MARK: - What this device publishes about ITSELF (plan task S3)
    //
    // `track(state:)` REPLACES the whole payload, so re-publishing one key
    // means re-publishing all of them. These three are what `subscribe` sent,
    // held so `publishStage(_:)` can send the same envelope with one field
    // changed rather than a truncated one.
    private var trackedSelfID: UUID?
    private var trackedUsername: String?
    private var publishedStage: ArrivalStage = .onTheWay

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
    ///                 Receives every user id currently in the lobby, including
    ///                 self, mapped to the arrival stage that device published
    ///                 for ITSELF (plan task S3). A key with no published stage
    ///                 is absent from the map's VALUES, never from its keys:
    ///                 presence still means "this device has the lobby open".
    ///   - onChange:  Called on MainActor on ANY postgres_changes event.
    ///                Caller is expected to refetch sessions and participants.
    ///
    /// THREE SUBSCRIPTIONS, exactly as spec §3.1 counts them: `sessions` and
    /// `session_participants` (insert, update, delete). The two
    /// `routine_proposals` streams and the `routine_proposal_votes` stream
    /// left with the proposal-and-vote flow (plan task S8).
    func subscribe(
        sessionID: UUID,
        selfID: UUID,
        username: String,
        onPresence: @escaping @MainActor ([UUID: String]) -> Void,
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
        //
        // `stage` REPLACES the `check_in_state` key this used to publish, which
        // was always the empty string and therefore told every other device
        // nothing (plan task S3). `check_in_state` is a COLUMN, read from
        // `session_participants`; what a device alone can know is whether it is
        // standing inside the gym's geofence, and that is what it publishes.
        // `.onTheWay` is the honest opening claim: the geofence has not been
        // evaluated yet, and `publishStage(_:)` below sends the answer when it
        // has been.
        trackedSelfID = selfID
        trackedUsername = username
        publishedStage = .onTheWay
        await pChannel.track(state: [
            "user_id":   .string(selfID.uuidString),
            "username":  .string(username),
            "app_state": .string("active"),
            "stage":     .string(ArrivalStage.onTheWay.rawValue)
        ])

        presenceTask = Task { @MainActor in
            // Local map from presence key → (user UUID, published stage);
            // mutated on each diff. The stage is the payload's own `stage`
            // key, which every GymSync client publishes from `track(state:)`
            // above — an older build that publishes none reads as ON THE WAY
            // through `ArrivalLaw.stage`, which is the honest default.
            var tracked: [String: (id: UUID, stage: String)] = [:]
            for await action in presenceDiff {
                for (key, pv) in action.joins {
                    // Parse user_id from the presence payload; ignore entries without it.
                    if let raw = pv.state["user_id"]?.stringValue,
                       let uid = UUID(uuidString: raw) {
                        tracked[key] = (id: uid,
                                        stage: pv.state["stage"]?.stringValue
                                            ?? ArrivalStage.onTheWay.rawValue)
                    }
                }
                for key in action.leaves.keys {
                    tracked.removeValue(forKey: key)
                }
                // Keyed by USER, not by presence key: one lifter with the app
                // open on two devices is ONE row in the track. Which device
                // wins is decided by the FURTHER-ALONG stage, never by
                // arrival order — `tracked.values` iterates a Dictionary,
                // whose order is unspecified, so "last join wins" made a
                // two-device lifter's column oscillate between renders
                // (review finding F5). Further along is also the right
                // answer: a phone that has reached the gym knows something
                // the one left in the car does not.
                var byUser: [UUID: String] = [:]
                for entry in tracked.values {
                    let incoming = ArrivalStage(rawValue: entry.stage) ?? .onTheWay
                    let standing = byUser[entry.id].flatMap(ArrivalStage.init(rawValue:))
                    if let standing, Self.rank(standing) >= Self.rank(incoming) { continue }
                    byUser[entry.id] = incoming.rawValue
                }
                onPresence(byUser)
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
            }
        }
    }

    /// How far along an arrival stage is. `checkedIn` outranks both even
    /// though a device may not publish it — a payload from an older build
    /// could still carry it, and ranking it correctly costs one line.
    private static func rank(_ stage: ArrivalStage) -> Int {
        switch stage {
        case .onTheWay:  return 0
        case .atTheGym:  return 1
        case .checkedIn: return 2
        }
    }

    /// Republish this device's arrival stage (plan task S3).
    ///
    /// The lobby calls this when its own geofence answer changes — and only
    /// then: a device that publishes on every tick is a device every other
    /// device's presence stream wakes for. A no-op when the stage has not
    /// moved, and a no-op before `subscribe`, so a caller does not have to
    /// know which.
    ///
    /// **`.checkedIn` IS NOT PUBLISHABLE.** That stage is
    /// `session_participants.check_in_state`'s to say (`ArrivalLaw.stage`), and
    /// a device claiming it in presence would be a second source of truth for
    /// the one fact the lobby's Start counts.
    func publishStage(_ stage: ArrivalStage) async {
        guard stage != .checkedIn,
              stage != publishedStage,
              let channel = presenceChannel,
              let selfID = trackedSelfID,
              let username = trackedUsername else { return }
        publishedStage = stage
        await channel.track(state: [
            "user_id":   .string(selfID.uuidString),
            "username":  .string(username),
            "app_state": .string("active"),
            "stage":     .string(stage.rawValue)
        ])
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

        trackedSelfID = nil
        trackedUsername = nil
        publishedStage = .onTheWay
    }
}
