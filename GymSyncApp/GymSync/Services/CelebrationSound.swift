import AVFoundation
import Foundation

// MARK: - CelebrationSound
//
// The PR moment's sound, back as a BUNDLED resource (owner 2026-09-18: "keep
// the sound effect"). Ronnie left with the soundboard (ruling R-B8, B1 plan
// task S11) and took the celebration's sound with him; this returns the sound
// alone — no board, no bucket, no download, no per-sound picker.
//
// THE AUDIO SACRED RULE (ChatView.swift:9, VoiceBubblePlayer: "NEVER touches
// AVAudioSession category"). This type sets NO category. It calls
// AudioSessionManager.shared.ensureMixablePlayback(), which restores the
// documented .playback + .mixWithOthers baseline ONLY when mixWithOthers has
// been lost, and never while a voice room holds the session. It never calls
// configure(), setCategory, setActive, enterVoiceMode or exitVoiceMode.
//
// .playback, NOT .ambient — and the plan records this as a deliberate
// departure from spec 2026-06-28 §"must mix with… never interrupt", which
// names .ambient. The owner overruled that on 2026-08-14 and
// AudioSessionManager.configure() (:24-35) records it in his words: "it
// should not go silent when the phone is silenced — Spotify plays through
// silent mode". .ambient obeys the ringer switch by definition; .playback
// ignores it. .mixWithOthers keeps the sacred half: we layer OVER the
// lifter's music, never replace it.
//
// NO NEW SETTING, and this is the answer to the reader who goes looking:
// there is no user-facing sound or haptics toggle anywhere in this app.
// Every `isMuted` in the codebase is VoiceRoomService's per-participant VOICE
// mute, and LaunchLoadingOverlay's `player.isMuted` is a video. The silent
// switch is honoured by the category the app deliberately chose not to obey
// on 2026-08-14.
@MainActor
enum CelebrationSound {

    /// The one player, built ONCE and held — so a second PR inside the clip
    /// RESTARTS the sound rather than layering a second copy over the first,
    /// and so the file is never decoded on the celebration's critical path.
    private static var player: AVAudioPlayer?

    /// Whether `prepare()` has already run. A missing or unreadable resource
    /// is a permanent condition, not a transient one: without this the
    /// warm-up call on every exercise change would re-log the same failure
    /// for the length of the session.
    private static var didPrepare = false

    /// Build and decode the player AHEAD OF THE MOMENT (ruling R-OD-4).
    ///
    /// `AVAudioPlayer(contentsOf:)` does synchronous file I/O and a header
    /// decode; doing that inside `showPROverlay`'s `withAnimation` turn put a
    /// hitch on the one frame the whole feature exists for. Both session
    /// bodies call this when the exercise changes — long before any set of it
    /// can be a record.
    ///
    /// Idempotent, silent, and non-throwing: a missing resource leaves
    /// `player` nil and the celebration still appears, soundlessly. It writes
    /// NO audio-session category (the AUDIO SACRED RULE) and does not play.
    static func prepare() {
        guard !didPrepare else { return }
        didPrepare = true
        guard let url = Bundle.main.url(forResource: "lightweight-baby", withExtension: "mp3") else {
            // THE CELEBRATION MUST NEVER FAIL TO APPEAR BECAUSE A SOUND DID
            // NOT LOAD. Log and leave; the caller has already set its overlay
            // flag, and the haptic fired on the logged set regardless.
            AppLogger.audio.error("CelebrationSound: lightweight-baby.mp3 missing from the bundle")
            return
        }
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            // Buffers the clip so `play()` starts on the next frame rather
            // than after a decode. AUDIO SACRED RULE: no category is set
            // here, and preparing a player activates nothing.
            _ = p.prepareToPlay()
            player = p
        } catch {
            AppLogger.audio.error("CelebrationSound: \(error, privacy: .public)")
        }
    }

    /// The PR moment's sound — PLAYING and nothing else (ruling R-OD-4).
    /// NEVER sets the AVAudioSession category (the AUDIO SACRED RULE — see
    /// VoiceBubblePlayer). Silent, not interrupting, while a voice room holds
    /// the session.
    static func playPR() {
        // A crewmate mid-sentence is not interrupted by someone else's PR
        // (owner decision 4). `ensureMixablePlayback()` would refuse to touch
        // the session here anyway; this returns before the player is even
        // reached, so push-to-talk hears nothing at all.
        guard !AudioSessionManager.shared.isInVoiceMode else { return }

        // Field report #39 ("the PR sound pauses Spotify"): iOS's default
        // .soloAmbient pauses other apps' audio the moment a player
        // implicitly activates the session, so the mixable baseline is the
        // invariant every overlay sound depends on. This is
        // ensureMixablePlayback()'s first caller since B1's S11 — it was
        // written for exactly this and kept callerless on purpose.
        AudioSessionManager.shared.ensureMixablePlayback()

        // The cold path, for a celebration that arrives before any exercise
        // change warmed it (an ad-hoc lift, a relaunch mid-set). A no-op once
        // prepared, which is the ordinary case.
        prepare()

        guard let player else { return }
        // A second PR inside the clip restarts it: `play()` alone would
        // resume a finished player at its end and sound like nothing at all.
        if player.isPlaying { player.stop() }
        player.currentTime = 0
        player.play()
    }
}
