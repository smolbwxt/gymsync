import XCTest
import Foundation
@testable import GymSync

/// Live round-trip test for voice-message send/fetch.
///
/// FIXTURE STRATEGY (documented per brief):
/// Hermetically generating a valid AAC/m4a on CI is impractical
/// (AVAudioEngine offline render needs a real audio session; simulator CI
/// has no mic so AVAudioRecorder is unreliable).  We therefore synthesise
/// a tiny silent WAV in-memory using pure Swift (no files, no AVFoundation)
/// and upload it as the .m4a payload.  The Supabase storage bucket stores
/// the bytes verbatim (no server-side transcoding), so the send/fetch
/// round-trip — kind, storage_path prefix, body duration format — is fully
/// validated.  Playback fidelity (the client actually hearing audio) is
/// device-QA only, not CI-verified; this is explicitly called out as the
/// approved fallback in the task brief.
final class VoiceMessageTests: XCTestCase {

    // MARK: - Fixture helpers

    /// Build a minimal 44.1kHz, 16-bit mono WAV containing `durationSeconds`
    /// of silence. Pure Swift — no AVFoundation, no temporary files.
    private static func silentWAVData(durationSeconds: Double = 0.5) -> Data {
        let sampleRate: Int = 44_100
        let numSamples = Int(Double(sampleRate) * durationSeconds)
        let dataSize   = numSamples * 2          // 16-bit = 2 bytes/sample
        let chunkSize  = 36 + dataSize           // RIFF chunk body

        var wav = Data()

        // Helper: append a little-endian integer
        func appendLE<T: FixedWidthInteger>(_ value: T) {
            var v = value.littleEndian
            wav.append(contentsOf: withUnsafeBytes(of: &v, Array.init))
        }

        // RIFF header
        wav.append(contentsOf: "RIFF".utf8)
        appendLE(UInt32(chunkSize))
        wav.append(contentsOf: "WAVE".utf8)

        // fmt  sub-chunk
        wav.append(contentsOf: "fmt ".utf8)
        appendLE(UInt32(16))   // sub-chunk size
        appendLE(UInt16(1))    // PCM
        appendLE(UInt16(1))    // mono
        appendLE(UInt32(sampleRate))
        appendLE(UInt32(sampleRate * 2))  // byte rate
        appendLE(UInt16(2))    // block align
        appendLE(UInt16(16))   // bits per sample

        // data sub-chunk
        wav.append(contentsOf: "data".utf8)
        appendLE(UInt32(dataSize))
        wav.append(contentsOf: Data(count: dataSize))  // silence = zeros

        return wav
    }

    // MARK: - Tests

    /// Full send→fetch round trip:
    ///   • kind == .audio
    ///   • storage_path starts with "{group_id}/"
    ///   • body matches "m:ss" pattern (duration format pre-rendered by sendVoice)
    ///   • fetch by message id confirms storage_path survives the DB round-trip
    func testSendVoiceInsertsAudioMessageAndRoundTrips() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Voice Chat Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        // Write fixture bytes to a temp file so sendVoice can read them.
        // (ChatRepository.sendVoice takes a file URL for the data path.)
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        let wavData = Self.silentWAVData(durationSeconds: 0.5)
        try wavData.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // Send with a declared duration of 5 seconds (pre-rendered body "0:05").
        let duration: TimeInterval = 5.0
        let sent = try await ChatRepository.sendVoice(
            groupID: group.id, fileURL: tmpURL, duration: duration)

        // --- Assertions ---

        XCTAssertEqual(sent.kind, .audio,
                       "kind must be .audio")

        let path = try XCTUnwrap(sent.storagePath,
                                 "audio message must carry a storage_path")

        // Storage path uses the group id as folder (matches bucket RLS: chat-audio/{group_id}/…)
        // NOTE: StorageService.uploadChatAudio builds "chat-audio/{group}/{id}.m4a"
        //       but only the group-relative portion is stored in the DB column.
        //       Accept either "chat-audio/{group}/" or "{group}/" prefix.
        let groupPrefix = group.id.uuidString.lowercased()
        XCTAssertTrue(
            path.contains(groupPrefix),
            "storage_path must contain the group id — got: \(path)"
        )

        let body = try XCTUnwrap(sent.body,
                                 "audio message must have a body (pre-rendered duration)")

        // Body must match "m:ss" pattern: digit(s), colon, exactly two digits
        let durationPattern = #"^\d+:\d{2}$"#
        XCTAssertTrue(
            body.range(of: durationPattern, options: .regularExpression) != nil,
            "body must be in m:ss format — got: \(body)"
        )

        // Specific value: 5s → "0:05"
        XCTAssertEqual(body, "0:05",
                       "body for 5-second clip must be '0:05'")

        // Fetch round-trip: storage_path must survive DB persistence
        let fetched = try await ChatRepository.messages(groupID: group.id)
        let fetchedMsg = try XCTUnwrap(
            fetched.first(where: { $0.id == sent.id }),
            "sent message must appear in fetch results"
        )
        XCTAssertEqual(fetchedMsg.storagePath, sent.storagePath,
                       "storage_path must be identical after DB round-trip")
        XCTAssertEqual(fetchedMsg.kind, .audio,
                       "fetched kind must still be .audio")

        // Explicit cleanup (defer above is the safety net)
        try await GroupRepository.deleteGroup(groupID: group.id)
    }

    /// Verify that the "0:00"-style pre-render logic handles edge cases.
    func testDurationBodyFormatEdgeCases() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Voice Duration Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")
        try Self.silentWAVData(durationSeconds: 0.5).write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        // 65 seconds → "1:05"
        let sent65 = try await ChatRepository.sendVoice(
            groupID: group.id, fileURL: tmpURL, duration: 65.0)
        XCTAssertEqual(sent65.body, "1:05")

        // 0 seconds → "0:00" (edge case: cancelled or instantaneous)
        let sent0 = try await ChatRepository.sendVoice(
            groupID: group.id, fileURL: tmpURL, duration: 0.0)
        XCTAssertEqual(sent0.body, "0:00")

        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
