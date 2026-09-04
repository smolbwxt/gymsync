import SwiftUI

// MARK: - WalkthroughView (redesign, 2026-07-23 — user-requested)
//
// First-time walkthrough: a four-page full-screen pager shown ONCE after the
// user first lands on the main app. RootView gates it on
// `OneShotFlags.walkthroughSeen(userID:)` (RootView.swift:92), which is
// per-ACCOUNT — the key is `hasSeenWalkthroughV1.<uuid>`, so a second account
// on the same phone gets its own first run. The bare device-wide
// `hasSeenWalkthroughV1` only counts in the LAUNCH-ARGUMENT domain, the
// QA/UI-test override (`-hasSeenWalkthroughV1 YES`); nothing persists it.
// Onyx language throughout; the accent follows the user's live `\.gsTheme`
// accent like everything else.
//
// Deliberately content-only pages (SF Symbol art + title + copy) — no live
// data, no network, so it can never block or fail. Skip is always available;
// both Skip and the final CTA mark the flag via `onDone`.
struct WalkthroughView: View {
    @Environment(\.gsTheme) private var theme
    let onDone: () -> Void

    @State private var page = 0

    private struct Page {
        let icon: String
        let title: String
        let body: String
    }

    private let pages: [Page] = [
        Page(icon: "flame.fill",
             title: "Welcome to GymSync",
             body: "Train with your crew, log every lift, and keep the streak alive. Here's the two-minute tour."),
        Page(icon: "person.3.fill",
             title: "Lift together",
             body: "Join a crew, schedule sessions, and take turns on the bar. Check-in opens 20 minutes before start — show up late and the crew decides your burpees."),
        Page(icon: "chart.line.uptrend.xyaxis",
             title: "Log everything",
             body: "Solo or with the crew — every set builds your calendar, streaks, PRs, and projections. Your next working weight is estimated from your best lifts."),
        Page(icon: "paintpalette.fill",
             title: "Make it yours",
             body: "Pick your accent color in You → Appearance — the whole app follows it. Watch for the gold card on Home: that means check-in is open."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Skip — always available, top-trailing.
            HStack {
                Spacer()
                if page < pages.count - 1 {
                    Button("Skip") { onDone() }
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                        .padding(.trailing, 20)
                        .padding(.top, 12)
                }
            }
            .frame(height: 44)

            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                    pageView(item)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            // Custom page dots — accent for the current page.
            HStack(spacing: 7) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Circle()
                        .fill(index == page ? theme.accent : theme.neutral400)
                        .frame(width: index == page ? 8 : 6, height: index == page ? 8 : 6)
                }
            }
            .padding(.bottom, 22)
            .animation(.easeInOut(duration: 0.2), value: page)

            Button {
                if page < pages.count - 1 {
                    withAnimation { page += 1 }
                } else {
                    onDone()
                }
            } label: {
                Text(page < pages.count - 1 ? "Continue" : "Get started")
                    .font(GSFont.bold(16, relativeTo: .body))
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    // 12.5pt vertical (was 16): content + 25 + the gs3D
                    // style's 7pt lip keeps the CTA's exact prior footprint.
                    .padding(.vertical, 12.5)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .background(theme.bg.ignoresSafeArea())
        .interactiveDismissDisabled()
    }

    private func pageView(_ item: Page) -> some View {
        VStack(spacing: 0) {
            Spacer()
            RoundedRectangle(cornerRadius: 28)
                .fill(theme.surface)
                .frame(width: 108, height: 108)
                .overlay(
                    Image(systemName: item.icon)
                        .font(.system(size: 46, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )
            Text(item.title)
                .font(GSFont.heading(26, relativeTo: .title))
                .foregroundStyle(theme.text)
                .multilineTextAlignment(.center)
                .padding(.top, 26)
            Text(item.body)
                .font(GSFont.body(15, relativeTo: .body))
                .foregroundStyle(theme.neutral700)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .padding(.top, 10)
                .padding(.horizontal, 34)
            Spacer()
            Spacer()
        }
    }
}
