import XCTest
import AVFoundation
@testable import GymSync

/// The PR celebration's sound (owner 2026-09-18: "keep the sound effect").
///
/// Two things a test can actually prove about it: the resource is really in
/// the app bundle (a `project.yml` `resources:` entry that did not take is a
/// silent failure — the app builds, the celebration appears, and nothing ever
/// plays), and `playPR()` touches no audio-session category on its way past
/// (the AUDIO SACRED RULE). What it cannot prove, and what I2 checks by hand
/// on a device, is that the clip does not pause Spotify and is silent during
/// push-to-talk.
final class CelebrationSoundTests: XCTestCase {

    /// The bundle that actually ships the app's resources. `Bundle.main` under
    /// a hosted unit-test bundle IS the host app; the `allBundles` sweep is
    /// the belt to that braces, so a failure here means the resource is
    /// missing from every loaded bundle — i.e. the `resources:` entry did not
    /// take — rather than that the test guessed the wrong bundle.
    private func bundledSoundURL() -> URL? {
        if let url = Bundle.main.url(forResource: "lightweight-baby", withExtension: "mp3") {
            return url
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "lightweight-baby", withExtension: "mp3") {
                return url
            }
        }
        return nil
    }

    func testTheCelebrationSoundIsBundled() throws {
        let url = try XCTUnwrap(
            bundledSoundURL(),
            "lightweight-baby.mp3 is not in the app bundle. `sources:` is a directory glob, so GymSync/Resources/Sounds must be listed under the GymSync target's `resources:` in project.yml or xcodegen compiles the folder instead of copying it.")
        // And it is a real, playable clip rather than a truncated or
        // placeholder file that happens to carry the right name.
        let player = try AVAudioPlayer(contentsOf: url)
        XCTAssertGreaterThan(player.duration, 0,
            "The bundled clip decodes to zero length — a truncated copy.")
    }

    func testAMissingResourceResolvesToNilRatherThanTrapping() {
        // The `guard let url = … else { log; return }` arm in playPR() is
        // reachable code, not a crash: a name the bundle does not carry
        // answers nil, which is what that guard reads.
        XCTAssertNil(Bundle.main.url(forResource: "lightweight-baby-not-here", withExtension: "mp3"))
    }

    @MainActor
    func testPrepareIsIdempotentAndWritesNoAudioSessionCategory() throws {
        // Ruling R-OD-4: the player is built and decoded AHEAD of the moment,
        // by the session bodies, on every exercise change — so preparing must
        // be free to call repeatedly and must touch the session no more than
        // playing does. It plays nothing, which is why this test can assert
        // the category is still the baseline afterwards.
        try AudioSessionManager.shared.configure()
        let session = AVAudioSession.sharedInstance()

        CelebrationSound.prepare()
        CelebrationSound.prepare()

        XCTAssertEqual(session.category, .playback)
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers))
    }

    @MainActor
    func testPlayPRNeverTouchesTheAudioSessionCategory() throws {
        // THE AUDIO SACRED RULE (ChatView.swift:9, VoiceBubblePlayer): a
        // player never sets the category. playPR() may only call
        // ensureMixablePlayback(), which RESTORES this exact baseline — so
        // starting from the baseline, playing must leave it untouched.
        try AudioSessionManager.shared.configure()
        let session = AVAudioSession.sharedInstance()

        CelebrationSound.playPR()

        XCTAssertEqual(session.category, .playback,
            "playPR() changed the category. It must set none: .playback is the owner's 2026-08-14 ruling (the sound plays through the silent switch, like Spotify) and belongs to AudioSessionManager, not to a player.")
        XCTAssertTrue(session.categoryOptions.contains(.mixWithOthers),
            "REGRESSION GUARD (field report #39, 'the PR sound pauses Spotify'): the celebration layers OVER the lifter's music and never replaces it.")
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers),
            ".duckOthers would lower the lifter's music under the celebration — never enable.")
    }
}
