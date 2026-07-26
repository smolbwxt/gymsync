import SwiftUI

// MARK: - Just-in-time spotlight
//
// Design: docs/superpowers/specs/2026-07-25-first-run-guidance-design.md.
// A semi-transparent scrim with a CUTOUT around the control being taught,
// plus a copy card. Fires the first time you land on a screen.
//
// The architectural rule that keeps this maintainable: a spotlight NEVER
// drives navigation and knows nothing about any other screen. Each one is
// self-contained — screen announces itself, tip fires, done. A tour that
// walks between screens becomes a cross-screen state machine that breaks
// every time a layout moves; this cannot, because there is no sequence.

/// Publishes target rects up the view tree so a screen root can cut its
/// scrim around a control living several layers down (e.g. LibraryTabView's
/// spotlight targeting a button inside RoutinesListView).
struct GSSpotlightAnchorKey: PreferenceKey {
    static let defaultValue: [String: Anchor<CGRect>] = [:]
    static func reduce(value: inout [String: Anchor<CGRect>],
                       nextValue: () -> [String: Anchor<CGRect>]) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marks this view as the thing a tip points at.
    func gsSpotlightTarget(_ tip: GuidanceTip) -> some View {
        anchorPreference(key: GSSpotlightAnchorKey.self, value: .bounds) {
            [tip.rawValue: $0]
        }
    }

    /// Attach to a screen root. Shows `tip` once, on first appearance.
    func gsSpotlight(_ tip: GuidanceTip) -> some View {
        modifier(GSSpotlightModifier(tip: tip))
    }
}

struct GSSpotlightModifier: ViewModifier {
    let tip: GuidanceTip

    @Environment(\.gsTheme) private var theme
    @State private var visible = false

    func body(content: Content) -> some View {
        content
            .overlayPreferenceValue(GSSpotlightAnchorKey.self) { anchors in
                GeometryReader { proxy in
                    if visible {
                        GSSpotlightOverlay(
                            // A missing anchor is NOT a failure: the target
                            // may be absent for this user's data (an empty
                            // list has no first row). The overlay degrades
                            // to a plain centered card rather than cutting
                            // a hole around nothing.
                            targetRect: anchors[tip.rawValue].map { proxy[$0] },
                            title: tip.title,
                            message: tip.message,
                            onDismiss: dismiss
                        )
                        .transition(.opacity)
                    }
                }
                .ignoresSafeArea()
            }
            .task { await presentIfNeeded() }
    }

    private func presentIfNeeded() async {
        guard GuidanceTip.tipsEnabled, !tip.hasBeenSeen else { return }
        // Let layout settle so the anchor exists before the cutout is drawn
        // — without this the first frame can render a hole in the wrong
        // place (or none at all) and visibly jump.
        try? await Task.sleep(for: .milliseconds(450))
        guard !Task.isCancelled else { return }
        withAnimation(.easeOut(duration: 0.25)) { visible = true }
    }

    private func dismiss() {
        // Marked seen on DISMISS, not on show: a tip the user never actually
        // got to read (backgrounded the app, navigated away) should still be
        // waiting for them next time.
        tip.markSeen()
        withAnimation(.easeIn(duration: 0.2)) { visible = false }
    }
}

/// The scrim + cutout + copy card.
struct GSSpotlightOverlay: View {
    @Environment(\.gsTheme) private var theme

    let targetRect: CGRect?
    let title: String
    let message: String
    let onDismiss: () -> Void

    /// Breathing room around the highlighted control.
    private let padding: CGFloat = 8
    private let cornerRadius: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let hole = targetRect?.insetBy(dx: -padding, dy: -padding)

            ZStack(alignment: .topLeading) {
                // Even-odd fill cuts the hole in a single shape — simpler
                // and more predictable than a destination-out blend group,
                // which needs a compositingGroup and misbehaves inside some
                // scroll containers.
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let hole {
                        path.addRoundedRect(in: hole,
                                            cornerSize: CGSize(width: cornerRadius, height: cornerRadius))
                    }
                }
                .fill(Color.black.opacity(0.72), style: FillStyle(eoFill: true))
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

                if let hole {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(theme.accent.opacity(0.9), lineWidth: 2)
                        .frame(width: hole.width, height: hole.height)
                        .offset(x: hole.minX, y: hole.minY)
                        .allowsHitTesting(false)
                }

                card(in: proxy.size, hole: hole)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    @ViewBuilder
    private func card(in size: CGSize, hole: CGRect?) -> some View {
        let cardWidth = min(size.width - 40, 340)
        // Sit under the target when there's room below it, above it when the
        // target is low on screen; centered when there's no target at all.
        let below = (hole?.maxY ?? size.height / 2) + 16
        let placeBelow = below + 190 < size.height
        let y = hole == nil
            ? max(80, size.height / 2 - 100)
            : (placeBelow ? below : max(60, (hole!.minY) - 190))

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GSFont.bold(17, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text(message)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onDismiss) {
                Text("Got it")
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 10)
                    .background(theme.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(16)
        .frame(width: cardWidth, alignment: .leading)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusMd)
        .offset(x: (size.width - cardWidth) / 2, y: y)
    }
}
