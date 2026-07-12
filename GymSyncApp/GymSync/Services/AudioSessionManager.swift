import AVFoundation

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

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
}
