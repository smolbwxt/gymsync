import Foundation
import LiveKit

// ASSUMPTIONS — not independently verified against the vendored SDK source
// before first CI run (no Mac/Xcode available this session; per the task's
// process contract, iOS CI's SPM resolution + build is the actual verifier).
// Everything else in this file's API usage is cited to a specific line in
// Dossier §B.4 and is high-confidence. Three were originally flagged
// unconfirmed; CI round 2 confirmed #1 and #3 compile clean as written, and
// corrected #2:
//
//   1. `LocalTrackPublication.mute()` / `.unmute()` for hold-to-talk mute
//      semantics — CONFIRMED correct by CI (compiled with zero errors).
//   2. `Participant.identity` — CI corrected this: it's `Participant.Identity?`
//      (OPTIONAL), not the non-optional type originally assumed. Fixed in
//      `speakingParticipantsDidChange` below via `compactMap` rather than
//      force-unwrap or an empty-string fallback.
//   3. `Room.add(delegate:)` as the multicast-delegate registration method —
//      CONFIRMED correct by CI (compiled with zero errors).
//
// If CI's build-test job fails to compile here again, these are still the
// first three symbols to check — the fix is contained to this one file.
// Nothing in VoiceRoomService.swift or VoiceRoomServiceTests.swift depends on
// the exact symbol names; they only see the `VoiceRoomConnecting` protocol.
//
// Phase O Task 5 (3e follow-up queue items 4/5 — roster, remote mute state,
// per-participant local volume) adds THREE more unconfirmed symbols, same
// "flag it, let CI verify" discipline as #1-3 above (no Mac/Xcode this
// session either):
//
//   4. `RoomDelegate.room(_:participantDidConnect:)` /
//      `room(_:participantDidDisconnect:)` for roster tracking — the
//      participant-join/leave pair mirrored after the already-CONFIRMED
//      `room(_:didUpdateSpeakingParticipants:)` shape. (Both since confirmed
//      present in the live SDK source, `RoomDelegate.swift:98/:102`, fetched
//      during fix wave 2's selector verification.)
//   5. `RoomDelegate.room(_:participant:didUpdatePublication:muted:)` for a
//      remote participant's OWN mic mute state (distinct from #6 — this is
//      a fact ABOUT them, visible to everyone in the room). Phase O Task 5
//      fix wave 1 (reviewer Finding F2, verified against the live SDK
//      source): WRONG — this selector compiles (RoomDelegate is @objc
//      optional, so a near-miss signature silently never fires) but doesn't
//      exist on `RoomDelegate`. The real, current signature is
//      `room(_:participant:trackPublication:didUpdateIsMuted:)`
//      (`RoomDelegate.swift:181` in the live SDK source). Fixed below.
//   6. `RemoteAudioTrack.set(volume:)` for LOCAL-only playback volume
//      (`setLocalVolume` below) — the mixer sheet's per-person "tap to
//      mute"/level control never touches what the participant publishes,
//      only how loud WE play it back. Ledger precedent (Task 4 round
//      research, .superpowers/sdd/progress.md line 330: "per-person volume
//      + mute — LiveKit supports client-side") is why this method was
//      assumed to exist rather than invented from nothing. Phase O Task 5
//      fix wave 1 (reviewer Finding F1, verified against the live SDK
//      source): WRONG — no such method exists. `RemoteAudioTrack.volume` is
//      a settable `public var volume: Double` (clamped 0...10) instead.
//      Fixed below.
//   7. `RoomDelegate.room(_:didDisconnectWithError:)` for unexpected
//      transport death (Phase O Task 5 fix wave 2) — unlike #4-6 this one
//      was VERIFIED against the live SDK source BEFORE being written
//      (the F2 lesson: near-miss @objc-optional selectors compile and die
//      silently). Exact declaration, `Sources/LiveKit/Protocols/
//      RoomDelegate.swift:76-78` (fetched via `gh api` 2026-07-19):
//
//          /// Client disconnected from the room unexpectedly after a
//          /// successful connection.
//          @objc optional
//          func room(_ room: Room, didDisconnectWithError error: LiveKitError?)
//
//      `LiveKitError` is `public class LiveKitError: NSError` (SDK
//      `Errors.swift:140`) — an `Error`, forwarded as `Error?` through the
//      protocol seam.
//
// FIX WAVE 2 — per-connection Room generations. The re-review verified
// against the live SDK source (`Sources/LiveKit/Core/Room.swift`, fetched
// via `gh api` 2026-07-19) that the shared-Room residual flagged in fix
// wave 1 was a REAL gap:
//   - `Room.disconnect()` (Room.swift:506) no-ops when connectionState is
//     already `.disconnecting`/`.disconnected` (:509-511), otherwise sets
//     `.disconnecting` and runs `await cleanUp()` (:528);
//   - `Room.connect()` (Room.swift:357) runs an UNCONDITIONAL
//     `await cleanUp()` at its top (:386);
//   - so a hung/late first `disconnect()` that eventually unblocks runs its
//     own unconditional `cleanUp()` with zero generation awareness —
//     tearing down whatever transport is CURRENTLY live on that Room
//     object, i.e. a newer session's.
// The fix is structural: this class now creates a fresh `Room` PER
// CONNECTION (`connectAndPublishMuted`), and `disconnect()` detaches the
// current generation synchronously before awaiting its teardown — an
// abandoned late disconnect therefore tears down only ITS OWN room object
// and cannot touch a successor generation's transport. Delegate forwarders
// are created and attached per Room instance; every callback carries its
// originating `Room` and is identity-gated against the CURRENT generation
// on delivery, so stale-generation events (including the intentional-
// teardown room's own `didDisconnectWithError`) are dropped at this
// boundary and never reach `VoiceRoomService`.

/// Production `VoiceRoomConnecting` conformer — the one file that talks
/// directly to the LiveKit SDK. `VoiceRoomService` never imports LiveKit or
/// touches `Room`/`LocalParticipant` itself.
@MainActor
final class LiveKitRoomConnection: VoiceRoomConnecting {
    /// `AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false`
    /// must be set once, process-wide, before the first `room.connect(...)`
    /// (Dossier §B.3.2: "recommended to set this value before connecting to
    /// a room"). A static flag rather than call-site discipline so it's
    /// correct regardless of which session/view triggers the very first
    /// join, and regardless of when a `LiveKitRoomConnection` instance
    /// happens to be constructed relative to the first real `connect()`.
    private static var didDisableAutomaticAudioConfiguration = false

    var onSpeakingParticipantsChanged: ((Set<String>) -> Void)?
    var onRosterChanged: ((Set<String>) -> Void)?
    var onRemoteMuteChanged: ((String, Bool) -> Void)?
    var onUnexpectedDisconnect: ((Error?) -> Void)?

    /// The CURRENT connection generation's Room — `nil` while disconnected.
    /// Fix wave 2: was `private let room = Room()` (one shared instance for
    /// this object's whole lifetime); now created fresh per
    /// `connectAndPublishMuted` call and detached (set `nil`) synchronously
    /// at the top of `disconnect()`, BEFORE the teardown await — so an
    /// interleaving connect starts a new generation instead of touching the
    /// one being torn down, and identity checks against this property are
    /// the single generation gate for every delegate callback.
    private var room: Room?
    private var micPublication: LocalTrackPublication?
    /// Retained per generation alongside `room` — LiveKit's multicast
    /// delegate storage is commonly weak-referenced, so an unretained
    /// forwarder would be deallocated immediately and events would silently
    /// never fire. Replaced together with `room`: dropping the old
    /// generation's strong reference lets its forwarder deallocate, which
    /// stops stale events at the source; any already-in-flight hop is
    /// caught by the identity gate in the owner methods below.
    private var delegateForwarder: SpeakingParticipantsForwarder?

    func connectAndPublishMuted(url: String, token: String) async throws {
        if !Self.didDisableAutomaticAudioConfiguration {
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            Self.didDisableAutomaticAudioConfiguration = true
        }
        // Defensive: a previous generation can still be owned here if a
        // half-successful join left it behind (e.g. `connect` + `setMicrophone`
        // succeeded but the initial `mute()` threw — the service goes
        // `.unavailable` without ever calling `disconnect()`). Detach it and
        // tear it down in the background so it can't linger as an orphaned
        // live transport; per-generation Rooms make the background teardown
        // safe (it touches only its own object). In the normal flow
        // (`leave()` always precedes a fresh join) this is a no-op.
        if let staleRoom = room {
            room = nil
            micPublication = nil
            delegateForwarder = nil
            Task { await staleRoom.disconnect() }
        }

        // AUDIO SACRED RULE note: creating the Room here — after the
        // automatic-audio-configuration flag above, before `connect` below —
        // does not reorder anything relative to `AudioSessionManager`:
        // `configure()` ran at app start and `enterVoiceMode()` already ran
        // in `VoiceRoomService.join()` before this method was ever called.
        // (The pre-wave-2 shared Room was actually constructed in `init`,
        // BEFORE the flag was first set; construction here is strictly
        // later, never earlier.)
        let newRoom = Room()
        let forwarder = SpeakingParticipantsForwarder(owner: self)
        newRoom.add(delegate: forwarder)
        // Ownership assigned BEFORE the connect await so (a) a `disconnect()`
        // that interleaves while we're parked on `connect` finds and tears
        // down THIS generation, and (b) delegate events arriving mid-connect
        // already pass the identity gate.
        room = newRoom
        micPublication = nil
        delegateForwarder = forwarder

        try await newRoom.connect(url: url, token: token)
        guard room === newRoom else {
            // disconnect() interleaved while we were parked on connect and
            // already detached this generation — but our in-flight connect
            // may have raced past its cleanUp and landed anyway. Undo it
            // (idempotent: Room.disconnect() no-ops if the teardown's own
            // disconnect already won) and report failure; the caller's
            // epoch guard recognizes this flight as stale and ignores it.
            await newRoom.disconnect()
            throw CancellationError()
        }
        let publication = try await newRoom.localParticipant.setMicrophone(enabled: true)
        guard room === newRoom else {
            await newRoom.disconnect()
            throw CancellationError()
        }
        micPublication = publication
        try await publication?.mute()
    }

    func setMicrophoneMuted(_ muted: Bool) async throws {
        guard let micPublication else { return }
        if muted {
            try await micPublication.mute()
        } else {
            try await micPublication.unmute()
        }
    }

    /// See ASSUMPTION #6 at the top of this file — Phase O Task 5 fix wave 1
    /// (reviewer Finding F1, verified against the live SDK source):
    /// `RemoteAudioTrack` has no `set(volume:)` method; `volume` is a
    /// settable `public var volume: Double` (clamped 0...10) instead. Looks
    /// the participant up by matching `identity?.stringValue.lowercased()`
    /// (same canonicalization boundary as `speakingParticipantsDidChange`
    /// below) rather than reconstructing a `Participant.Identity` directly —
    /// this file has no confirmed public initializer for that type to build
    /// one from a raw `String`. No-op (silently) if disconnected, if the
    /// identity isn't currently in `room.remoteParticipants`, or if it has
    /// no audio track yet — matches this method's documented "best-effort,
    /// never throws" protocol contract.
    func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {
        guard let room else { return }
        guard let participant = room.remoteParticipants.values.first(where: {
            $0.identity?.stringValue.lowercased() == identity
        }) else { return }
        for publication in participant.audioTracks {
            guard let audioTrack = publication.track as? RemoteAudioTrack else { continue }
            audioTrack.volume = volume
        }
    }

    func disconnect() async {
        // Fix wave 2: detach the current generation SYNCHRONOUSLY before the
        // teardown await, so (a) a connect that interleaves while this
        // teardown is parked creates a fresh generation instead of reusing
        // (or being clobbered by) this one — the structural fix for the
        // shared-Room `cleanUp()` hazard documented in the header — and
        // (b) this room's own `didDisconnectWithError` event fails the
        // identity gate below (an INTENTIONAL teardown must never surface
        // as an unexpected disconnect). SOURCE-VERIFIED (wave-2 re-review,
        // Room+EngineDelegate.swift:58-66): the SDK fires that event on
        // EVERY entry into .disconnected except from .connecting —
        // including intentional disconnects — so the detach-before-first-
        // await ordering here is LOAD-BEARING, not defensive. Weakening it
        // makes every normal leave() surface as a spurious .unavailable.
        guard let roomToTearDown = room else { return }
        room = nil
        micPublication = nil
        delegateForwarder = nil
        await roomToTearDown.disconnect()
    }

    fileprivate func speakingParticipantsDidChange(_ participants: [Participant], in callbackRoom: Room) {
        guard callbackRoom === room else { return } // stale generation
        // `Participant.identity` is `Participant.Identity?` (confirmed by CI —
        // optional, not the non-optional type this file originally assumed).
        // `compactMap` rather than defaulting to "" on nil: a participant
        // with no identity yet (e.g. mid-handshake) shouldn't be conflated
        // with another identity-less participant under the same empty key.
        //
        // Lowercased at the boundary: identities are the token's `sub` claim
        // — a LOWERCASE Supabase UUID — while Swift's UUID.uuidString is
        // uppercase. Without canonicalizing, every speaking-indicator
        // compare in the views is silently false (final-review C1).
        let identities = Set(participants.compactMap { $0.identity?.stringValue.lowercased() })
        onSpeakingParticipantsChanged?(identities)
    }

    /// Recomputes the FULL current roster from the callback room's
    /// `remoteParticipants` (same "full current set, not a delta" shape as
    /// `speakingParticipantsDidChange` above) — simpler and more robust
    /// than tracking an incremental add/remove from the connect/disconnect
    /// delegate callbacks individually, and self-correcting if either
    /// callback's exact firing semantics turn out to differ from assumed.
    fileprivate func rosterDidChange(in callbackRoom: Room) {
        guard callbackRoom === room else { return } // stale generation
        let identities = Set(callbackRoom.remoteParticipants.keys.map { $0.stringValue.lowercased() })
        onRosterChanged?(identities)
    }

    fileprivate func remoteMuteDidChange(participant: Participant, isMuted: Bool, in callbackRoom: Room) {
        guard callbackRoom === room else { return } // stale generation
        guard let identity = participant.identity?.stringValue.lowercased() else { return }
        onRemoteMuteChanged?(identity, isMuted)
    }

    /// Fix wave 2 (ASSUMPTION #7 above — selector source-verified): the
    /// CURRENT generation's transport died out from under a successfully
    /// established connection. The identity gate makes the two
    /// non-unexpected cases structurally unreachable here: an INTENTIONAL
    /// teardown detached `room` before its Room ever fired this event, and
    /// a STALE generation's late event carries a Room that no longer
    /// matches. Disowns the dead generation (its transport is gone — there
    /// is nothing left to tear down or talk to) before forwarding, so a
    /// subsequent `leave()`/`retry()` starts from a clean slate.
    fileprivate func roomDidDisconnect(_ callbackRoom: Room, error: Error?) {
        guard callbackRoom === room else { return } // stale generation or intentional teardown
        room = nil
        micPublication = nil
        delegateForwarder = nil
        onUnexpectedDisconnect?(error)
    }
}

/// `RoomDelegate` is a plain (non-`@MainActor`) protocol invoked by LiveKit's
/// internal engine off the main actor. This tiny forwarder implements the
/// callbacks `VoiceRoomService` needs — active speakers (Dossier §B.4's
/// confirmed `RoomDelegate.room(_:didUpdateSpeakingParticipants:)`), roster
/// join/leave and remote mute-state (Phase O Task 5 items 4/5 — ASSUMPTIONS
/// #4/#5 at the top of this file), and unexpected transport death (fix wave
/// 2 — ASSUMPTION #7) — and hops back to the owning `LiveKitRoomConnection`
/// on the main actor, so the adapter itself stays simply `@MainActor` with
/// no `nonisolated` methods of its own. One forwarder instance is created
/// PER Room generation (fix wave 2); every hop passes the originating
/// `room` through so the owner can identity-gate stale generations at
/// delivery time. Kept as one forwarder type (not split per callback) since
/// it's a single tiny multicast-delegate registration, matching the
/// existing shape rather than multiplying near-identical boilerplate types.
private final class SpeakingParticipantsForwarder: RoomDelegate {
    private weak var owner: LiveKitRoomConnection?

    init(owner: LiveKitRoomConnection) {
        self.owner = owner
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor [weak owner] in
            owner?.speakingParticipantsDidChange(participants, in: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in
            owner?.rosterDidChange(in: room)
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in
            owner?.rosterDidChange(in: room)
        }
    }

    /// Forwards a REMOTE participant's own publish-mute state (Phase O Task
    /// 5 item 4's "muted themselves" case). Phase O Task 5 fix wave 1
    /// (reviewer Finding F2, verified against the live SDK source): the
    /// original `room(_:participant:didUpdatePublication:muted:)` selector
    /// is a near-miss that COMPILES (`RoomDelegate` is `@objc optional`, so
    /// a method that merely resembles a protocol requirement is silently
    /// accepted as an unrelated extra method) but is never invoked by
    /// LiveKit — the real, current requirement is
    /// `room(_:participant:trackPublication:didUpdateIsMuted:)`. Fixed to
    /// that exact signature; the body's logic is unchanged.
    /// `participant is RemoteParticipant` guards against also picking up our
    /// own local mic's mute callback (if LiveKit fires this same delegate
    /// method for the local participant too) — our own mute state is
    /// already driven explicitly via `setMicrophoneMuted(_:)` and doesn't
    /// need an echo through this path. `trackPublication.kind == .audio`
    /// scopes to mic mute only — this app never publishes video, but a
    /// non-audio publication's mute state isn't a concept the roster/mixer
    /// UI has any use for either way.
    nonisolated func room(
        _ room: Room,
        participant: Participant,
        trackPublication: TrackPublication,
        didUpdateIsMuted isMuted: Bool
    ) {
        guard participant is RemoteParticipant, trackPublication.kind == .audio else { return }
        Task { @MainActor [weak owner] in
            owner?.remoteMuteDidChange(participant: participant, isMuted: isMuted, in: room)
        }
    }

    /// Fix wave 2 (ASSUMPTION #7 — declaration quoted there, verified
    /// against live SDK source before writing; SDK doc: "Client disconnected
    /// from the room unexpectedly after a successful connection").
    nonisolated func room(_ room: Room, didDisconnectWithError error: LiveKitError?) {
        Task { @MainActor [weak owner] in
            owner?.roomDidDisconnect(room, error: error)
        }
    }
}
