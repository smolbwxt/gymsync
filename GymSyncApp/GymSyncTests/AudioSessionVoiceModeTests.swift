import XCTest
import AVFoundation
@testable import GymSync

/// Hermetic test for the live-voice (push-to-talk) audio-session scope introduced in
/// Task 2 of Phase 3e.
///
/// Contract:
///   1. `enterVoiceMode()` switches the session to `.playAndRecord` category /
///      `.voiceChat` mode and sets `isInVoiceMode`.
///   2. `exitVoiceMode()` restores EXACTLY `configure()`'s state: category `.ambient`
///      AND options containing `.mixWithOthers`, and clears `isInVoiceMode`.
///   3. Both calls are idempotent — double enter/exit must not throw or leave the
///      session in an unexpected state.
///
/// The EXISTING `AudioSessionManagerTests`/`AudioSessionRestoreTests` regression guards
/// are NOT modified by this file — they must stay green, proving Phase 1's `configure()`
/// behavior is untouched.
final class AudioSessionVoiceModeTests: XCTestCase {

    private let manager = AudioSessionManager.shared
    private let avSession = AVAudioSession.sharedInstance()

    override func setUp() async throws {
        try await super.setUp()
        // Put the session into a known state before each test.
        try manager.configure()
    }

    func testEnterVoiceModeSwitchesToPlayAndRecord() throws {
        try manager.enterVoiceMode()
        XCTAssertEqual(
            avSession.category, .playAndRecord,
            "enterVoiceMode must switch category to .playAndRecord so the mic is active."
        )
        XCTAssertEqual(
            avSession.mode, .voiceChat,
            "enterVoiceMode must use .voiceChat mode for live voice PTT."
        )
    }

    func testEnterVoiceModeSetsIsInVoiceModeFlag() throws {
        try manager.enterVoiceMode()
        XCTAssertTrue(
            manager.isInVoiceMode,
            "isInVoiceMode must be true once voice mode is entered, for VoiceRecorder gating."
        )
    }

    func testExitVoiceModeRestoresAmbientCategory() throws {
        try manager.enterVoiceMode()
        manager.exitVoiceMode()
        XCTAssertEqual(
            avSession.category, .ambient,
            "exitVoiceMode must restore category to .ambient (matches configure())."
        )
    }

    func testExitVoiceModeRestoresMixWithOthers() throws {
        try manager.enterVoiceMode()
        manager.exitVoiceMode()
        XCTAssertTrue(
            avSession.categoryOptions.contains(.mixWithOthers),
            "exitVoiceMode must re-enable .mixWithOthers so playback mixes with Spotify."
        )
    }

    func testExitVoiceModeClearsIsInVoiceModeFlag() throws {
        try manager.enterVoiceMode()
        manager.exitVoiceMode()
        XCTAssertFalse(
            manager.isInVoiceMode,
            "isInVoiceMode must be false once voice mode is exited."
        )
    }

    func testDoubleEnterVoiceModeIsIdempotent() throws {
        try manager.enterVoiceMode()
        try manager.enterVoiceMode()
        XCTAssertEqual(avSession.category, .playAndRecord)
        XCTAssertEqual(avSession.mode, .voiceChat)
        XCTAssertTrue(manager.isInVoiceMode)
    }

    func testDoubleExitVoiceModeIsHarmless() throws {
        try manager.enterVoiceMode()
        manager.exitVoiceMode()
        manager.exitVoiceMode()
        XCTAssertEqual(
            avSession.category, .ambient,
            "A second exitVoiceMode() call must remain harmless and stay at .ambient."
        )
        XCTAssertTrue(avSession.categoryOptions.contains(.mixWithOthers))
        XCTAssertFalse(manager.isInVoiceMode)
    }

    func testExitVoiceModeWithoutEnterIsHarmless() {
        // Exiting voice mode without ever entering it must not crash — covers the
        // path VoiceRecorder or an early lifecycle event might hit before any
        // enterVoiceMode() call has occurred.
        manager.exitVoiceMode()
        XCTAssertEqual(avSession.category, .ambient)
        XCTAssertTrue(avSession.categoryOptions.contains(.mixWithOthers))
        XCTAssertFalse(manager.isInVoiceMode)
    }
}
