import Foundation
import LiveKit

// ASSUMPTIONS — not independently verified against the vendored SDK source
// (no Mac/Xcode available this session; per the task's process contract, iOS
// CI's SPM resolution + build is the actual verifier). Everything else in
// this file's API usage is cited to a specific line in Dossier §B.4 and is
// high-confidence; these three are not:
//
//   1. `LocalTrackPublication.mute()` / `.unmute()` are the correct symbols
//      for driving hold-to-talk mute semantics. Dossier §B.4 flags this
//      exact uncertainty verbatim: "the correct symbol is almost certainly
//      a mute()/unmute() on the microphone LocalTrackPublication itself...
//      flagged, not independently confirmed this session."
//   2. `Participant.identity` exposes a `.stringValue` (a typed-ID newtype
//      wrapper, matching other LiveKit Swift SDK ID conventions) rather than
//      being a plain `String` already.
//   3. `Room.add(delegate:)` is the multicast-delegate registration method
//      (supporting more than one observer) rather than a single `delegate`
//      settable property.
//
// If CI's build-test job fails to compile, these three lines are the first
// place to look — the fix is contained to this one file. Nothing in
// VoiceRoomService.swift or VoiceRoomServiceTests.swift depends on the exact
// symbol names; they only see the `VoiceRoomConnecting` protocol.

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
        let identities = Set(participants.map { $0.identity.stringValue })
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
