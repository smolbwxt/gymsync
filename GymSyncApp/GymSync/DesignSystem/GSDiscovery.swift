import SwiftUI

// MARK: - Discovery depth treatment
//
// A never-pressed control reads as RAISED: lit along its top edge, with one
// gentle settle on appearance. Raised things look pressable — which is
// exactly the message an undiscovered feature needs, and a quieter way to
// say it than a badge.
//
// Onyx does elevation through surface contrast and edge light, never drop
// shadows (a black shadow is invisible on #0A0B0D) and never color washes
// (see DiscoveryStore's header for why those fail on this ground). So the
// depth here is: a top-lit hairline border + a one-time lift.

extension View {
    /// Marks this control as "not pressed yet". Renders the depth treatment
    /// while that's true, and clears it on first tap.
    func gsDiscovery(_ target: DiscoveryTarget,
                     cornerRadius: CGFloat = GSMetrics.radiusMd) -> some View {
        modifier(GSDiscoveryModifier(target: target, cornerRadius: cornerRadius))
    }
}

struct GSDiscoveryModifier: ViewModifier {
    let target: DiscoveryTarget
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var store = DiscoveryStore.shared
    @State private var lifted = false

    private var isNew: Bool {
        // Honors the same "Show tips" switch as the spotlights: one control
        // for all first-run guidance, not two.
        store.isNew(target) && GuidanceTip.tipsEnabled
    }

    func body(content: Content) -> some View {
        content
            .overlay {
                if isNew {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(
                            // Brighter at the top, fading down: the whole
                            // illusion of "lit from above", hence raised.
                            LinearGradient(
                                colors: [Color.white.opacity(0.30), Color.white.opacity(0.04)],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 1
                        )
                        .allowsHitTesting(false)
                }
            }
            // Static depth alone is easy to miss (the opposite failure of a
            // too-loud dot). A single settle on arrival is what makes it
            // read as NEW rather than as just another button.
            .scaleEffect(isNew && lifted ? 1.014 : 1.0)
            .animation(.spring(response: 0.55, dampingFraction: 0.62), value: lifted)
            .task {
                guard isNew, !reduceMotion else { return }
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                lifted = true
                try? await Task.sleep(for: .milliseconds(520))
                lifted = false
            }
            // simultaneousGesture, not onTapGesture: the control keeps its
            // own action untouched — this only observes the press.
            .simultaneousGesture(TapGesture().onEnded {
                store.markPressed(target)
            })
            // Depth is invisible to VoiceOver, so the state has to be said
            // out loud or this feature simply doesn't exist for those users.
            .accessibilityHint(isNew ? "New — not opened yet" : "")
    }
}

// MARK: - Tab-bar rollup dot
//
// The one place a dot survives: at 21pt an icon has no room to read as
// raised. Deliberately a STROKED ring in `theme.text`, never an accent fill
// — accent-filled indicators already mean "something is waiting for you"
// (unread messages, pending friend requests), and blurring that line
// teaches people to ignore the badges that matter.

struct GSDiscoveryDot: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Circle()
            .strokeBorder(theme.text.opacity(0.85), lineWidth: 1.5)
            .frame(width: 7, height: 7)
            .allowsHitTesting(false)
    }
}
