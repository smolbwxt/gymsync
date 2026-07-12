import AVFoundation
import Foundation

/// Records short voice clips (.m4a, AAC 64kbps mono, 60s hard cap) while
/// scoping the audio session to .playAndRecord.  The session is ALWAYS
/// restored to .ambient + .mixWithOthers when recording ends, regardless of
/// how it ends (stop, cancel, 60 s auto-stop, or error path).
@MainActor
final class VoiceRecorder: NSObject {

    // MARK: - Private state

    private var recorder: AVAudioRecorder?
    private var currentURL: URL?
    private var autoStopTask: Task<Void, Never>?

    // MARK: - Public API

    /// Request microphone permission, swap the audio session to .playAndRecord,
    /// and start recording to a temporary .m4a file.
    ///
    /// - Throws: `GymSyncError.validation` if the user denies microphone access.
    ///           Any other AVFoundation or file-system error propagates directly.
    func startRecording() async throws {
        // iOS 17+ permission API
        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            throw GymSyncError.validation("Microphone access needed for voice messages")
        }

        // Swap session category BEFORE creating the recorder
        try AudioSessionManager.shared.enterRecordMode()

        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("m4a")

            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderBitRateKey: 64_000,
                AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
            ]

            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.delegate = self
            rec.record()

            recorder = rec
            currentURL = url

            // 60 s hard cap — use a Task instead of a repeating Timer.
            // @MainActor so the call to autoStop() stays on the actor.
            autoStopTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 60_000_000_000)
                guard !Task.isCancelled else { return }
                self?.autoStop()
            }
        } catch {
            restoreSession()
            throw error
        }
    }

    /// Stop recording and restore the audio session.
    ///
    /// - Returns: `(url, duration)` of the recorded clip, or `nil` if no
    ///   recording was active.  The session is restored even on nil return.
    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        defer { restoreSession() }

        guard let rec = recorder, let url = currentURL else { return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        currentURL = nil
        autoStopTask?.cancel()
        autoStopTask = nil
        return (url, duration)
    }

    /// Cancel the recording in progress: stop, delete the temp file, and
    /// restore the audio session.
    func cancelRecording() {
        defer { restoreSession() }

        autoStopTask?.cancel()
        autoStopTask = nil

        guard let rec = recorder, let url = currentURL else { return }
        rec.stop()
        try? FileManager.default.removeItem(at: url)
        recorder = nil
        currentURL = nil
    }

    // MARK: - Private helpers

    private func autoStop() {
        // Called from within the Task after 60 s
        _ = stopRecording()
    }

    private func restoreSession() {
        AudioSessionManager.shared.exitRecordMode()
    }
}

// MARK: - AVAudioRecorderDelegate

extension VoiceRecorder: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder, successfully flag: Bool
    ) {
        // Delegate fires after stop() — nothing extra needed here.
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder, error: Error?
    ) {
        AppLogger.audio.error(
            "AVAudioRecorder encode error: \(error?.localizedDescription ?? "unknown")")
    }
}
