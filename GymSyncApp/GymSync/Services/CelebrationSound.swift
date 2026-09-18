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

    /// The one player, held so a second PR inside the clip RESTARTS the sound
    /// rather than layering a second copy over the first.
    private static var player: AVAudioPlayer?

    /// The PR moment's sound. NEVER sets the AVAudioSession category (the
    /// AUDIO SACRED RULE — see VoiceBubblePlayer). Silent, not interrupting,
    /// while a voice room holds the session.
    static func playPR() {
        // A crewmate mid-sentence is not interrupted by someone else's PR
        // (owner decision 4). `ensureMixablePlayback()` would refuse to touch
        // the session here anyway; this returns before the player is even
        // built, so push-to-talk hears nothing at all.
        guard !AudioSessionManager.shared.isInVoiceMode else { return }

        // Field report #39 ("the PR sound pauses Spotify"): iOS's default
        // .soloAmbient pauses other apps' audio the moment a player
        // implicitly activates the session, so the mixable baseline is the
        // invariant every overlay sound depends on. This is
        // ensureMixablePlayback()'s first caller since B1's S11 — it was
        // written for exactly this and kept callerless on purpose.
        AudioSessionManager.shared.ensureMixablePlayback()

        guard let url = Bundle.main.url(forResource: "lightweight-baby", withExtension: "mp3") else {
            // THE CELEBRATION MUST NEVER FAIL TO APPEAR BECAUSE A SOUND DID
            // NOT LOAD. Log and leave; the caller has already set its overlay
            // flag, and the haptic fired on the logged set regardless.
            AppLogger.audio.error("CelebrationSound: lightweight-baby.mp3 missing from the bundle")
            return
        }

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            // AUDIO SACRED RULE: do NOT set audio session category here.
            player?.stop()
            player = p
            p.play()
        } catch {
            AppLogger.audio.error("CelebrationSound: \(error, privacy: .public)")
        }
    }
}
