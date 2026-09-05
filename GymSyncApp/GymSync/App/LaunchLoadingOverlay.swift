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

    // No theme environment on purpose — this surface commits to black in every
    // palette (see the floor's comment below).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// How long the overlay holds before revealing the app. Long enough to
    /// read as intentional, short enough that it never feels like a wait —
    /// and it doubles as the head start every tab's `.task` gets.
    private static let brandMoment: Duration = .milliseconds(1300)

    @State private var settled = false

    var body: some View {
        ZStack {
            // Black, not `theme.bg` (user 2026-08-02: "make sure the background
            // behind it is black). The clip's own vignette fades to black at
            // its edges, so a pure-black floor is what makes the art read as
            // full-bleed rather than as a pasted square. This is the one
            // surface in the app that deliberately ignores the palette — a
            // launch moment is a single committed image, not a themed screen.
            Color.black.ignoresSafeArea()

            VStack(spacing: 20) {
                loopArt
                Text("LOADING THE BAR")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(1.6)
                    .foregroundStyle(.white.opacity(0.55))
                    .opacity(settled ? 1 : 0)
            }
        }
        // FIRST accessibility identifier in the app, and the convention for
        // test-visible chrome from here on: any full-screen cover a UI test
        // must wait OUT gets a stable id here rather than being matched on
        // its copy ("LOADING THE BAR"), which would silently stop checking
        // the moment someone rewords the caption.
        //
        // `.contain` keeps the caption/art queryable underneath instead of
        // flattening them into one element — do NOT change it to `.combine`
        // or `.ignore`: `ScreenshotTests.waitForLaunchOverlay` reads the
        // "LOADING THE BAR" caption as an independent tripwire against this
        // identifier silently failing to match. `.contain` also makes this
        // ZStack itself surface as its own container element, which is what
        // the test waits to STOP existing — SwiftUI reports that only once
        // the 350 ms removal transition has finished (a screenshot taken any
        // earlier catches a partially-faded overlay).
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("launch-overlay")
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

    /// The looping bench-press animation. No card frame or stroke: the clip
    /// carries its own inked vignette that dissolves into the black floor, and
    /// any border we drew would cut straight through that fade.
    private var loopArt: some View {
        LaunchLoopVideo()
            .frame(width: 300, height: 300)
            .scaleEffect(settled ? 1 : 0.96)
            .opacity(settled ? 1 : 0)
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
