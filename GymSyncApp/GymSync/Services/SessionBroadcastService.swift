import Foundation
import Supabase

// ── SessionBroadcastService ───────────────────────────────────────────────────
//
// Manages ephemeral broadcast messaging on the `session:{id}` realtime channel.
//
// Wire shapes (spec §5):
//   soundboard event: { "user_id": uuid-string, "sound_slug": slug, "ts": ms }
//   reaction  event:  { "user_id": uuid-string, "emoji": string,    "ts": ms }
//
// Broadcast is a DIFFERENT primitive from postgres_changes:
//   • Receive: channel.broadcastStream(event:) -> AsyncStream<JSONObject>
//     (supabase-swift 2.51 API — JSONObject = [String: AnyJSON])
//   • Send:    channel.broadcast(event:message:) async throws
//
// SDK drift note (mirrors the presence adaptation in LobbyRealtimeService):
//   - broadcastStream(event:) is the async-stream API introduced in supabase-swift 2.x.
//     It replaces the older callback-based onBroadcast(event:callback:).
//   - Broadcast channels do NOT require a postgres publication or table filter;
//     they need no postgresChange() registration — pure pub/sub via the realtime server.
//   - Same register-before-subscribe ordering rule as postgres_changes applies:
//     call broadcastStream(event:) before await channel.subscribe().
//   - channel.broadcast(event:message:) is async throws in 2.51; send errors are
//     swallowed (ephemeral semantics — missed events lost by design).
//
// Rate limit: 1 send per second shared across all sends from this instance.
// Drops silently (spec: "drop, don't queue").
//
// Sound echo (removed 2026-08-11): sendSound no longer inserts chat rows —
// sounds are durable as message REACTIONS ('snd:{slug}' in
// chat_message_reactions); the broadcast here stays ephemeral by design.

@MainActor
final class SessionBroadcastService {

    // MARK: - Channel

    private var channel: RealtimeChannelV2?
    private var broadcastTask: Task<Void, Never>?

    // MARK: - Rate limit (1/s, shared across sounds + reactions)

    private var lastSentAt: Date = .distantPast

    // MARK: - Swap events (group hot-swap, owner rulings 2026-08-21)

    /// One hot-swap wire event. `kind`: "self" (quiet member-local scale,
    /// shown on their set, never announced), "propose" (opens a squad
    /// vote), "vote" (yes/no toward UNANIMOUS), "apply" (proposer's
    /// client observed unanimity - everyone applies).
    struct SwapEvent: Sendable {
        let userID: UUID
        let kind: String
        let proposalID: UUID?
        let exerciseID: UUID
        let replacementID: UUID
        let replacementName: String
        let vote: Bool?
    }

    // MARK: - Subscribe

    /// Subscribe to soundboard + reaction broadcast events for a session.
    ///
    /// - Parameters:
    ///   - sessionID:     The session to subscribe to (channel: `session:{id}`).
    ///   - onSoundboard:  Called on MainActor with (userID, soundSlug) when a soundboard broadcast arrives.
    ///   - onReaction:    Called on MainActor with (userID, emoji) when a reaction broadcast arrives.
    func subscribe(
        sessionID: UUID,
        onSoundboard: @escaping @MainActor (UUID, String) -> Void,
        onReaction:   @escaping @MainActor (UUID, String) -> Void,
        onSwap:       @escaping @MainActor (SwapEvent) -> Void = { _ in }
    ) async {
        await unsubscribe()

        let ch = SupabaseService.shared.client
            .channel("session:\(sessionID.uuidString)")

        // Register broadcast stream iterators BEFORE subscribing.
        // (Same ordering rule as postgres_changes — SDK wires filters during subscribe.)
        let soundboardStream = ch.broadcastStream(event: "soundboard")
        let reactionStream   = ch.broadcastStream(event: "reaction")
        let swapStream       = ch.broadcastStream(event: "swap")

        self.channel = ch
        await ch.subscribe()

        broadcastTask = Task { @MainActor in
            await withTaskGroup(of: Void.self) { group in

                // ── soundboard ────────────────────────────────────────────
                group.addTask { @MainActor in
                    for await payload in soundboardStream {
                        guard
                            let rawUID = payload["user_id"]?.stringValue,
                            let uid    = UUID(uuidString: rawUID),
                            let slug   = payload["sound_slug"]?.stringValue
                        else {
                            AppLogger.soundboard.error(
                                "broadcast: malformed soundboard payload")
                            continue
                        }
                        onSoundboard(uid, slug)
                    }
                }

                // ── swap (hot-swap wire) ──────────────────────────────────
                group.addTask { @MainActor in
                    for await payload in swapStream {
                        guard
                            let rawUID = payload["user_id"]?.stringValue,
                            let uid    = UUID(uuidString: rawUID),
                            let kind   = payload["kind"]?.stringValue,
                            let rawEx  = payload["exercise_id"]?.stringValue,
                            let exID   = UUID(uuidString: rawEx),
                            let rawRep = payload["replacement_id"]?.stringValue,
                            let repID  = UUID(uuidString: rawRep),
                            let repName = payload["replacement_name"]?.stringValue
                        else {
                            AppLogger.soundboard.error("broadcast: malformed swap payload")
                            continue
                        }
                        let proposalID = payload["proposal_id"]?.stringValue.flatMap(UUID.init)
                        let vote = payload["vote"]?.boolValue
                        onSwap(SwapEvent(userID: uid, kind: kind,
                                         proposalID: proposalID, exerciseID: exID,
                                         replacementID: repID, replacementName: repName,
                                         vote: vote))
                    }
                }

                // ── reaction ──────────────────────────────────────────────
                group.addTask { @MainActor in
                    for await payload in reactionStream {
                        guard
                            let rawUID = payload["user_id"]?.stringValue,
                            let uid    = UUID(uuidString: rawUID),
                            let emoji  = payload["emoji"]?.stringValue
                        else {
                            AppLogger.soundboard.error(
                                "broadcast: malformed reaction payload")
                            continue
                        }
                        onReaction(uid, emoji)
                    }
                }
            }
        }
    }

    // MARK: - Unsubscribe

    func unsubscribe() async {
        broadcastTask?.cancel()
        broadcastTask = nil
        if let ch = channel {
            await SupabaseService.shared.client.removeChannel(ch)
        }
        channel = nil
    }

    // MARK: - Send (with shared rate limit)

    /// Broadcast a soundboard event and (if groupID provided) insert a chat echo.
    ///
    /// - Parameters:
    ///   - sessionID:   The active session.
    ///   - groupID:     The session's group chat; echo inserted only when non-nil.
    ///   - slug:        Sound slug (e.g. "airhorn").
    func sendSound(sessionID: UUID, groupID: UUID?, slug: String) async {
        guard rateAllowed() else { return }
        guard let me = await SupabaseService.shared.currentUserID() else { return }

        await broadcastRaw(
            sessionID: sessionID,
            event: "soundboard",
            message: [
                "user_id":    .string(me.uuidString),
                "sound_slug": .string(slug),
                "ts":         .double(Date().timeIntervalSince1970 * 1000)
            ]
        )

        // Owner decision 2026-08-11: no more per-play chat echoes — sounds
        // live as message REACTIONS now (ChatView sound chips). The ephemeral
        // broadcast above is the whole in-session story; groupID is kept in
        // the signature for call-site stability.
        _ = groupID
    }

    /// Broadcast a reaction event (no chat echo per spec).
    ///
    /// - Parameters:
    ///   - sessionID: The active session.
    ///   - emoji:     The reaction emoji (e.g. "🔥").
    func sendReaction(sessionID: UUID, emoji: String) async {
        guard rateAllowed() else { return }
        guard let me = await SupabaseService.shared.currentUserID() else { return }

        await broadcastRaw(
            sessionID: sessionID,
            event: "reaction",
            message: [
                "user_id": .string(me.uuidString),
                "emoji":   .string(emoji),
                "ts":      .double(Date().timeIntervalSince1970 * 1000)
            ]
        )
    }

    /// Broadcast a hot-swap event. Deliberately NOT behind the shared
    /// 1/s rate limit: a vote landing inside the cooldown would be
    /// silently dropped, and unanimity math cannot survive dropped votes.
    func sendSwap(sessionID: UUID, kind: String, proposalID: UUID?,
                  exerciseID: UUID, replacementID: UUID,
                  replacementName: String, vote: Bool? = nil) async {
        guard let me = await SupabaseService.shared.currentUserID() else { return }
        var message: [String: AnyJSON] = [
            "user_id":          .string(me.uuidString),
            "kind":             .string(kind),
            "exercise_id":      .string(exerciseID.uuidString),
            "replacement_id":   .string(replacementID.uuidString),
            "replacement_name": .string(replacementName),
            "ts":               .double(Date().timeIntervalSince1970 * 1000)
        ]
        if let proposalID { message["proposal_id"] = .string(proposalID.uuidString) }
        if let vote { message["vote"] = .bool(vote) }
        await broadcastRaw(sessionID: sessionID, event: "swap", message: message)
    }

    // MARK: - Private helpers

    /// Returns true and records the timestamp when ≥1s has elapsed since last send.
    private func rateAllowed() -> Bool {
        let now = Date()
        guard now.timeIntervalSince(lastSentAt) >= 1.0 else { return false }
        lastSentAt = now
        return true
    }

    /// Send a broadcast message.  Uses the subscribed channel when
    /// available; falls back to a disposable channel for
    /// send-without-subscribe callers — but only when the client-wide
    /// topic registry shows nobody else already holds this exact topic.
    ///
    /// CHANNEL-COLLISION GUARD (debt-zero sprint, gate finding I-1 sibling
    /// path): `WatchConnectivityBridge` owns a SEPARATE, send-only
    /// `SessionBroadcastService` instance for the watch `soundboardTap`
    /// relay (`Services/WatchConnectivityBridge.swift:129`,
    /// `LiveSoundboardBroadcasting(broadcastService: SessionBroadcastService())`)
    /// whose `channel` stays `nil` forever — every one of ITS sends used
    /// to take the `else` branch below unconditionally, on the SAME
    /// `session:{id}` topic `GroupSessionLiveView`'s own subscribed
    /// instance already holds for the whole session. See
    /// `BroadcastChannelDecision`'s doc comment
    /// (`Services/BroadcastChannelDecision.swift`) for the full SDK-quote
    /// writeup (hazard, fix, and residual-risk note) —
    /// `HeartRateBroadcastService.publish` applies the identical fix to
    /// its own topic.
    private func broadcastRaw(
        sessionID: UUID,
        event: String,
        message: JSONObject
    ) async {
        let topic = "session:\(sessionID.uuidString)"
        let client = SupabaseService.shared.client
        let registryEntry = client.realtimeV2.channels["realtime:\(topic)"]

        let decision = BroadcastChannelDecision.decide(
            hasHeldChannel: channel != nil,
            topicRegistered: registryEntry != nil
        )

        // Force-unwraps below are safe by construction — see
        // `HeartRateBroadcastService.publish`'s identical comment
        // (`Services/HeartRateBroadcastService.swift`) for the full
        // reasoning; the same synchronous-no-await argument applies here.
        let ch: RealtimeChannelV2
        switch decision {
        case .reuseHeld:
            ch = channel!
        case .reuseRegistry:
            ch = registryEntry!
        case .createDisposable:
            ch = client.channel(topic)
            await ch.subscribe()
        }

        do {
            try await ch.broadcast(event: event, message: message)
        } catch {
            AppLogger.soundboard.error(
                "broadcast send failed (\(event, privacy: .public)): \(error, privacy: .public)")
        }

        if decision == .createDisposable {
            // RIDER: disposable-channel fallback — remove it immediately
            // after sending so we don't leak a dangling Realtime
            // subscription. Only reached when the registry check above
            // found no existing holder for this topic at call time.
            Task { await client.removeChannel(ch) }
        }
    }

}
