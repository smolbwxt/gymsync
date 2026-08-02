import AVFoundation
import SwiftUI
import UIKit

// MARK: - LaunchLoadingOverlay
//
// Cold-launch brand moment (user report 2026-08-02: "click a tab and then see
// all the widgets kind of push each other around and populate asynchronously").
// The fix has two halves and this file is the visible one:
//
//   1. `MainTabView` now mounts every tab at launch instead of on first visit,
//      so all four tab roots build and fetch concurrently while this overlay is
//      up (see MainTabView.mountedTabs).
//   2. This overlay covers that window, so the user never watches the layout
//      settle — they see a deliberate animation, then a fully-populated app.
//
// The reveal is time-based rather than "await the fetches": a fixed window can
// never deadlock behind a hung request, and the widget frames are fixed-height
// anyway (the GS3DCard work), so late data drops into stable slots instead of
// shoving layout around.

struct LaunchLoadingOverlay: View {
    /// Called once the brand moment has elapsed; the parent animates the
    /// overlay away.
    let onFinished: () -> Void

    @Environment(\.gsTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the overlay holds before revealing the app. Long enough to
    /// read as intentional, short enough that it never feels like a wait —
    /// and it doubles as the head start every tab's `.task` gets.
    private static let brandMoment: Duration = .milliseconds(1300)

    @State private var settled = false

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 20) {
                loopArt
                Text("LOADING THE BAR")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(1.6)
                    .foregroundStyle(theme.neutral700)
                    .opacity(settled ? 1 : 0)
            }
        }
        .task {
            // Reduce-motion users still get the hold (the mount window is the
            // functional half); they just don't get the fade-in flourish.
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) {
                settled = true
            }
            try? await Task.sleep(for: Self.brandMoment)
            onFinished()
        }
    }

    /// The looping bench-press animation, framed as a card so its own
    /// background never reads as an accidental black rectangle. Light themes
    /// invert the ink (the clip is white-on-black line art, so inverted it
    /// becomes black-on-white — right at home on the cream palettes).
    private var loopArt: some View {
        LaunchLoopVideo()
            .frame(width: 264, height: 264)
            .colorInvert(isActive: !theme.isDark)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
            )
            .scaleEffect(settled ? 1 : 0.96)
            .opacity(settled ? 1 : 0)
    }
}

private extension View {
    /// `colorInvert()` is unconditional; this keeps the call site declarative
    /// without an `if` that would change the view's identity mid-animation.
    @ViewBuilder
    func colorInvert(isActive: Bool) -> some View {
        if isActive { self.colorInvert() } else { self }
    }
}

// MARK: - LaunchLoopVideo

/// Seamless, silent video loop.
///
/// AUDIO SACRED RULE: the bundled asset is encoded with **no audio track** and
/// the player is muted besides, so playback never activates or mutates
/// `AVAudioSession`. A launch animation must never duck, pause, or steal the
/// audio session from whatever the user is already listening to on the way to
/// the gym.
struct LaunchLoopVideo: UIViewRepresentable {
    func makeUIView(context: Context) -> LoopingPlayerUIView {
        LoopingPlayerUIView()
    }

    func updateUIView(_ uiView: LoopingPlayerUIView, context: Context) {}

    static func dismantleUIView(_ uiView: LoopingPlayerUIView, coordinator: ()) {
        uiView.stop()
    }
}

/// `AVPlayerLooper` needs an `AVQueuePlayer` and a layer to render into;
/// overriding `layerClass` hands the view an `AVPlayerLayer` directly so there
/// is no manual frame bookkeeping to drift.
final class LoopingPlayerUIView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }

    private let player = AVQueuePlayer()
    private var looper: AVPlayerLooper?

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }

    init() {
        super.init(frame: .zero)
        backgroundColor = .clear
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false
        playerLayer?.videoGravity = .resizeAspectFill
        playerLayer?.player = player

        guard let url = Bundle.main.url(forResource: "launch_loop", withExtension: "mp4") else {
            // Missing asset degrades to an empty frame rather than crashing —
            // the overlay's own timing still runs and the app still reveals.
            return
        }
        looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        player.play()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LoopingPlayerUIView is created in code only")
    }

    func stop() {
        player.pause()
        looper?.disableLooping()
    }
}
