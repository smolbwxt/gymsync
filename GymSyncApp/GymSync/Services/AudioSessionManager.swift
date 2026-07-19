import AVFoundation
import os

final class AudioSessionManager {
    static let shared = AudioSessionManager()
    private let session = AVAudioSession.sharedInstance()

    /// True while the session is scoped for live voice (push-to-talk) mode.
    /// Readable by other services (e.g. VoiceRecorder, VoiceRoomService) to
    /// gate against stepping on an active voice room's audio session.
    ///
    /// Lock-protected rather than a plain `var` — `AudioSessionManager` itself
    /// isn't actor-isolated, and its callers now span two independent
    /// `@MainActor` classes (`VoiceRecorder`, `VoiceRoomService`); a future
    /// caller off the main actor isn't ruled out either. Flagged by T2 review
    /// during Phase 3e Task 3 as unsynchronized — fixed here without changing
    /// the public `Bool` surface, so existing callers/tests are unaffected.
    private let voiceModeFlag = OSAllocatedUnfairLock(initialState: false)

    var isInVoiceMode: Bool { voiceModeFlag.withLock { $0 } }

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
        restoreAmbientBaseline(logPrefix: "AudioSessionManager.exitRecordMode")
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
        // Manual audio-session mode (LiveKit's `isAutomaticConfigurationEnabled
        // = false`, set once by `LiveKitRoomConnection` before its first
        // connect) means WE are responsible for the buffer tuning LiveKit's
        // automatic path otherwise applies internally — match WebRTC's 20ms
        // frame size (Dossier §B.3.3.4).
        try session.setPreferredIOBufferDuration(0.02)
        try session.setActive(true)
        voiceModeFlag.withLock { $0 = true }
    }

    /// Restore the ambient + mixWithOthers state that `configure()` establishes.
    /// Best-effort — never throws out; errors are swallowed and logged. Idempotent —
    /// calling this repeatedly, or without a prior `enterVoiceMode()`, is harmless.
    func exitVoiceMode() {
        restoreAmbientBaseline(logPrefix: "AudioSessionManager.exitVoiceMode")
        voiceModeFlag.withLock { $0 = false }
    }

    /// Shared restore step `exitRecordMode()`/`exitVoiceMode()` both used to
    /// carry as an identical verbatim 5-line try/catch (Phase O Task 5, 3e
    /// follow-up queue item 7, "restore-helper DRY" — flagged at the Phase
    /// 3e Task 3 final review). Byte-equivalent behavior to before: same
    /// category/mode/options, same best-effort swallow-and-log on failure,
    /// same per-caller log-message prefix (passed in rather than hardcoded,
    /// so `exitRecordMode`'s and `exitVoiceMode`'s log lines are unchanged).
    private func restoreAmbientBaseline(logPrefix: StaticString) {
        do {
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            AppLogger.audio.error("\(logPrefix) failed: \(error)")
        }
    }
}
