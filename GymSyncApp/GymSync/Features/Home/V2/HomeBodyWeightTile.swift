import SwiftUI

/// Body weight, as a TILE (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// Kicker `BODY WEIGHT`, the current weight at 22 pt, the change under it.
/// The change line stays in the default muted copy colour rather than going
/// green on a loss or red on a gain: rule 2 gives green to done/present and
/// red to errors, and a body-weight direction is neither — which way is good
/// depends on the lifter, and Home is not the place to have an opinion about
/// it.
///
/// Same v2 tile styling as `HomeLastLiftTile`; tap opens the log sheet the
/// `body-weight-log` catalog id already shows.
struct HomeBodyWeightTile: View {
    @Environment(\.gsTheme) private var theme

    /// Current weight, already formatted, e.g. `180.4 lb`.
    let weight: String
    /// The change line, e.g. `−5.8 since July`.
    let change: String
    /// Tap → `BodyWeightLogSheet`.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("BODY WEIGHT")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(1.6)
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(weight)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)

                Text(change)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)
            }
            .frame(maxWidth: .infinity, minHeight: HomeV3Metrics.tileMinHeight,
                   maxHeight: .infinity, alignment: .topLeading)
            .padding(HomeV3Metrics.tilePadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Body weight \(weight). \(change).")
    }
}
