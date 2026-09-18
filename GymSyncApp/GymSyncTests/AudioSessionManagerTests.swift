import XCTest
import AVFoundation
@testable import GymSync

final class AudioSessionManagerTests: XCTestCase {
    func testConfigureSetsPlaybackCategoryWithMixWithOthers() throws {
        try AudioSessionManager.shared.configure()
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .playback,
            "Category must be .playback (owner 2026-08-14: app audio plays through the silent switch, like Spotify); .mixWithOthers still protects the user's music")
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers),
            "REGRESSION GUARD: .mixWithOthers must be set — app audio (voice, celebrations) MUST play alongside Spotify without pausing it. The soundboard this guard was written for left the app in plan task S11; the baseline itself stays (design spec §6.1) — VoiceRecorder/VoiceRoomService rest on it too.")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers),
            ".duckOthers would lower the user's music volume during our audio — never enable.")
    }
}
