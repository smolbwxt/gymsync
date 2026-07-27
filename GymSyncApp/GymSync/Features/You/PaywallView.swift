import SwiftUI

// MARK: - PaywallView (dormant until Monetization.paywallEnabled)
//
// The Pro pitch. StoreKit 2 purchase wiring lands when products exist in
// App Store Connect (a user-side setup step: paid-apps agreement, banking,
// tax, product IDs) — until then the CTA is disabled with honest copy, so
// this screen can be designed, captured in CI, and reviewed long before it
// can charge anyone.
//
// Also the recap interstitial's upsell content: one screen, two entrances.

struct PaywallView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// Which gate sent the user here — leads the pitch with the thing they
    /// just tried to do, not a generic list.
    var highlight: Monetization.Feature? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("GymSync Pro")
                    .font(GSFont.heading(28, relativeTo: .largeTitle))
                    .foregroundStyle(theme.text)
                Text("Your crew stays free, forever. Pro is for your own training depth.")
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.neutral500)

                VStack(alignment: .leading, spacing: 12) {
                    featureRow(.programs, icon: "flag.checkered",
                               title: "Training programs",
                               detail: "Multi-week blocks with weekly targets from your real est. 1RM.")
                    featureRow(.deepHistory, icon: "chart.line.uptrend.xyaxis",
                               title: "Full history & trends",
                               detail: "Every set you've ever logged, per-exercise trends without the \(Monetization.freeHistoryDays)-day window.")
                    featureRow(.unlimitedRoutines, icon: "square.stack.3d.up",
                               title: "Unlimited routines",
                               detail: "Past the free \(Monetization.freeRoutineLimit), build as many as you train.")
                    featureRow(.export, icon: "square.and.arrow.up",
                               title: "Export your data",
                               detail: "Your training log is yours — take it anywhere.")
                }
                .padding(16)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusMd)

                Button {
                    // StoreKit 2 purchase lands with App Store Connect
                    // products; until then this screen is design-only.
                } label: {
                    Text("Coming soon")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
                .disabled(true)
                .opacity(0.6)

                Text("Groups, live sessions, voice, logging, PRs and streaks are free for everyone — that never changes.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)

                Button("Not now") { dismiss() }
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .background(theme.bg)
    }

    private func featureRow(_ feature: Monetization.Feature, icon: String,
                            title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(theme.accent)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(highlight == feature ? theme.accent700 : theme.text)
                Text(detail)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

// MARK: - Completion interstitial hook
//
// The Duolingo-placement slot: fires AFTER the recap renders, never
// between "workout complete" and the celebration. Today it shows nothing
// (paywall dormant); when the flag flips it becomes the Pro upsell for
// free users; if ads are ever revisited, this is where they'd go — a
// config decision, not a rework.
struct CompletionInterstitial: ViewModifier {
    let profile: Profile?
    @State private var show = false

    func body(content: Content) -> some View {
        content
            .task {
                guard Monetization.paywallEnabled,
                      !Monetization.isPro(profile) else { return }
                // Let the recap land first — the celebration is the point.
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                show = true
            }
            .sheet(isPresented: $show) {
                PaywallView()
            }
    }
}

extension View {
    /// Attach to the recap screen root.
    func completionInterstitial(profile: Profile?) -> some View {
        modifier(CompletionInterstitial(profile: profile))
    }
}
