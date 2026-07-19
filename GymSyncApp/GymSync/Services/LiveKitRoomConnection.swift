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
//      `room(_:didUpdateSpeakingParticipants:)` shape.
//   5. `RoomDelegate.room(_:participant:didUpdatePublication:muted:)` for a
//      remote participant's OWN mic mute state (distinct from #6 — this is
//      a fact ABOUT them, visible to everyone in the room).
//   6. `RemoteAudioTrack.set(volume:)` for LOCAL-only playback volume
//      (`setLocalVolume` below) — the mixer sheet's per-person "tap to
//      mute"/level control never touches what the participant publishes,
//      only how loud WE play it back. Ledger precedent (Task 4 round
//      research, .superpowers/sdd/progress.md line 330: "per-person volume
//      + mute — LiveKit supports client-side") is why this method was
//      assumed to exist rather than invented from nothing, but the exact
//      symbol/type (`RemoteAudioTrack` vs some other `AudioTrack`-
//      conforming type) is unverified.
//
// These three touch `Room`/`RemoteParticipant`/track-publication surface
// this file didn't previously reach, and — like #1-3 — are contained
// entirely to this one file; `VoiceRoomService.swift` only sees them through
// the `VoiceRoomConnecting` protocol's `onRosterChanged`/
// `onRemoteMuteChanged`/`setLocalVolume` members, which are guaranteed
// correct Swift regardless of the underlying LiveKit symbol names.

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

    private let room = Room()
    private var micPublication: LocalTrackPublication?
    private lazy var delegateForwarder = SpeakingParticipantsForwarder(owner: self)

    init() {
        // Registering the forwarder as a stored (lazy) property — not a
        // throwaway local — matters: LiveKit's multicast delegate storage is
        // commonly weak-referenced, so an unretained forwarder would be
        // deallocated immediately and active-speaker events would silently
        // never fire.
        room.add(delegate: delegateForwarder)
    }

    func connectAndPublishMuted(url: String, token: String) async throws {
        if !Self.didDisableAutomaticAudioConfiguration {
            AudioManager.shared.audioSession.isAutomaticConfigurationEnabled = false
            Self.didDisableAutomaticAudioConfiguration = true
        }
        try await room.connect(url: url, token: token)
        let publication = try await room.localParticipant.setMicrophone(enabled: true)
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

    /// See ASSUMPTION #6 at the top of this file — `RemoteAudioTrack.set
    /// (volume:)` is unverified against SDK source. Looks the participant
    /// up by matching `identity?.stringValue.lowercased()` (same
    /// canonicalization boundary as `speakingParticipantsDidChange` below)
    /// rather than reconstructing a `Participant.Identity` directly — this
    /// file has no confirmed public initializer for that type to build one
    /// from a raw `String`. No-op (silently) if the identity isn't
    /// currently in `room.remoteParticipants` or has no audio track yet —
    /// matches this method's documented "best-effort, never throws"
    /// protocol contract.
    func setLocalVolume(_ volume: Double, forParticipantIdentity identity: String) async {
        guard let participant = room.remoteParticipants.values.first(where: {
            $0.identity?.stringValue.lowercased() == identity
        }) else { return }
        for publication in participant.audioTracks {
            guard let audioTrack = publication.track as? RemoteAudioTrack else { continue }
            audioTrack.set(volume: volume)
        }
    }

    func disconnect() async {
        await room.disconnect()
        micPublication = nil
    }

    fileprivate func speakingParticipantsDidChange(_ participants: [Participant]) {
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

    /// Recomputes the FULL current roster from `room.remoteParticipants`
    /// (same "full current set, not a delta" shape as
    /// `speakingParticipantsDidChange` above) — simpler and more robust
    /// than tracking an incremental add/remove from the connect/disconnect
    /// delegate callbacks individually, and self-correcting if either
    /// callback's exact firing semantics turn out to differ from assumed.
    fileprivate func rosterDidChange() {
        let identities = Set(room.remoteParticipants.keys.map { $0.stringValue.lowercased() })
        onRosterChanged?(identities)
    }

    fileprivate func remoteMuteDidChange(participant: Participant, isMuted: Bool) {
        guard let identity = participant.identity?.stringValue.lowercased() else { return }
        onRemoteMuteChanged?(identity, isMuted)
    }
}

/// `RoomDelegate` is a plain (non-`@MainActor`) protocol invoked by LiveKit's
/// internal engine off the main actor. This tiny forwarder implements the
/// callbacks `VoiceRoomService` needs — active speakers (Dossier §B.4's
/// confirmed `RoomDelegate.room(_:didUpdateSpeakingParticipants:)`), plus
/// roster join/leave and remote mute-state (Phase O Task 5 items 4/5 —
/// ASSUMPTIONS #4/#5 at the top of this file) — and hops back to the owning
/// `LiveKitRoomConnection` on the main actor, so the adapter itself stays
/// simply `@MainActor` with no `nonisolated` methods of its own. Kept as one
/// forwarder type (not split per callback) since it's a single tiny
/// multicast-delegate registration, matching the existing shape rather than
/// multiplying near-identical boilerplate types.
private final class SpeakingParticipantsForwarder: RoomDelegate {
    private weak var owner: LiveKitRoomConnection?

    init(owner: LiveKitRoomConnection) {
        self.owner = owner
    }

    nonisolated func room(_ room: Room, didUpdateSpeakingParticipants participants: [Participant]) {
        Task { @MainActor [weak owner] in
            owner?.speakingParticipantsDidChange(participants)
        }
    }

    nonisolated func room(_ room: Room, participantDidConnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in
            owner?.rosterDidChange()
        }
    }

    nonisolated func room(_ room: Room, participantDidDisconnect participant: RemoteParticipant) {
        Task { @MainActor [weak owner] in
            owner?.rosterDidChange()
        }
    }

    /// Forwards a REMOTE participant's own publish-mute state (Phase O Task
    /// 5 item 4's "muted themselves" case). `participant is RemoteParticipant`
    /// guards against also picking up our own local mic's mute callback (if
    /// LiveKit fires this same delegate method for the local participant
    /// too) — our own mute state is already driven explicitly via
    /// `setMicrophoneMuted(_:)` and doesn't need an echo through this path.
    /// `publication.kind == .audio` scopes to mic mute only — this app never
    /// publishes video, but a non-audio publication's mute state isn't a
    /// concept the roster/mixer UI has any use for either way.
    nonisolated func room(
        _ room: Room,
        participant: Participant,
        didUpdatePublication publication: TrackPublication,
        muted: Bool
    ) {
        guard participant is RemoteParticipant, publication.kind == .audio else { return }
        Task { @MainActor [weak owner] in
            owner?.remoteMuteDidChange(participant: participant, isMuted: muted)
        }
    }
}
