import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

    /// True while the session is scoped for live voice (push-to-talk) mode.
    /// Readable by other services (e.g. VoiceRecorder) to gate against stepping
    /// on an active voice room's audio session.
    private(set) var isInVoiceMode = false

    private init() {}

    func configure() throws {
        try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
    }

    /// Swap to `.playAndRecord` for active voice recording.
    /// Caller (VoiceRecorder) must pair every call with `exitRecordMode()`.
    func enterRecordMode() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .default,
            options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
    }

    /// Restore the ambient + mixWithOthers state that `configure()` establishes.
    /// Best-effort — never throws out; errors are swallowed and logged.
    func exitRecordMode() {
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AppLogger.audio.error("AudioSessionManager.exitRecordMode failed: \(error)")
        }
    }

    /// Swap to `.playAndRecord` / `.voiceChat` for a live voice (push-to-talk) room.
    /// Caller (VoiceRoomService) must pair every call with `exitVoiceMode()`.
    /// Idempotent — calling this while already in voice mode simply re-applies the
    /// same category/mode/options.
    func enterVoiceMode() throws {
        try session.setCategory(
            .playAndRecord,
            mode: .voiceChat,
            options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker]
        )
        try session.setActive(true)
        isInVoiceMode = true
    }

    /// Restore the ambient + mixWithOthers state that `configure()` establishes.
    /// Best-effort — never throws out; errors are swallowed and logged. Idempotent —
    /// calling this repeatedly, or without a prior `enterVoiceMode()`, is harmless.
    func exitVoiceMode() {
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AppLogger.audio.error("AudioSessionManager.exitVoiceMode failed: \(error)")
        }
        isInVoiceMode = false
    }
}
