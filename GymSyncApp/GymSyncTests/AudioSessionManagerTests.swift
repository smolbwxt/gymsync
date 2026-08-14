import XCTest
import AVFoundation
@testable import GymSync

final class AudioSessionManagerTests: XCTestCase {
    func testConfigureSetsPlaybackCategoryWithMixWithOthers() throws {
        try AudioSessionManager.shared.configure()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback,
            "Category must be .playback (owner 2026-08-14: the board plays through the silent switch, like Spotify); .mixWithOthers still protects the user's music")
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers),
            "REGRESSION GUARD: .mixWithOthers must be set — the soundboard MUST play alongside Spotify without pausing it. See design spec §6.1.")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers),
            ".duckOthers would lower the user's music volume during our audio — never enable.")
    }
}
