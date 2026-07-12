import XCTest
import AVFoundation
@testable import GymSync

/// Hermetic test for the scoped audio-category swap introduced in Task 5.
///
/// Contract:
///   1. `enterRecordMode()` switches the session to `.playAndRecord`.
///   2. `exitRecordMode()` restores EXACTLY `configure()`'s state:
///      category `.ambient` AND options containing `.mixWithOthers`.
///
/// The EXISTING `AudioSessionManagerTests` regression guard (ambient+mixWithOthers
/// after `configure()`) is NOT modified — it must stay green.
final class AudioSessionRestoreTests: XCTestCase {

    private let manager = AudioSessionManager.shared
    private let avSession = AVAudioSession.sharedInstance()

    override func setUp() async throws {
        try await super.setUp()
        // Put the session into a known state before each test.
        try manager.configure()
    }

    func testEnterRecordModeSwitchesToPlayAndRecord() throws {
        try manager.enterRecordMode()
        XCTAssertEqual(
            avSession.category, .playAndRecord,
            "enterRecordMode must switch category to .playAndRecord so the mic is active."
        )
    }

    func testExitRecordModeRestoresAmbientCategory() throws {
        try manager.enterRecordMode()
        manager.exitRecordMode()
        XCTAssertEqual(
            avSession.category, .ambient,
            "exitRecordMode must restore category to .ambient (matches configure())."
        )
    }

    func testExitRecordModeRestoresMixWithOthers() throws {
        try manager.enterRecordMode()
        manager.exitRecordMode()
        XCTAssertTrue(
            avSession.categoryOptions.contains(.mixWithOthers),
            "exitRecordMode must re-enable .mixWithOthers so playback mixes with Spotify."
        )
    }
}
