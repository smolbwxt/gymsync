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
        let identities = Set(participants.compactMap { $0.identity?.stringValue })
        onSpeakingParticipantsChanged?(identities)
    }
}

/// `RoomDelegate` is a plain (non-`@MainActor`) protocol invoked by LiveKit's
/// internal engine off the main actor. This tiny forwarder implements the
/// one callback `VoiceRoomService` needs — active speakers, Dossier §B.4's
/// confirmed `RoomDelegate.room(_:didUpdateSpeakingParticipants:)` — and
/// hops back to the owning `LiveKitRoomConnection` on the main actor, so the
/// adapter itself stays simply `@MainActor` with no `nonisolated` methods of
/// its own.
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
}
