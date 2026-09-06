import SwiftUI

/// The lift that is one session from a record, as a TILE (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// Kicker `PR WATCH`, the current best at 22 pt, and under it the number
/// that is in reach. That last line is the one place accent is spent here:
/// design language rule 3 — "the line goes accent only when it is an
/// invitation" — and `210 is within reach` is an invitation, not a readout.
/// It is the only accent on the tile, and no v3 composition puts this tile
/// on a screen whose one button is also accent-and-inviting at the same
/// time... except by way of the one button itself, which is the screen's
/// single primary (rule 4) and outranks a 12 pt line by three type sizes.
///
/// Same v2 tile styling as `HomeLastLiftTile` — see that file's note on the
/// 12 pt / 104 pt geometry.
struct HomePRWatchTile: View {
    @Environment(\.gsTheme) private var theme

    /// The standing best, e.g. `Bench 205`.
    let lift: String
    /// The invitation, e.g. `210 is within reach`.
    let invitation: String
    /// Tap → that exercise's history.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("PR WATCH")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(1.6)
                    .foregroundStyle(theme.neutral500)

                Text(lift)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)

                Text(invitation)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .monospacedDigit()
                    .foregroundStyle(theme.accent)
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
        .accessibilityLabel("PR watch. \(lift). \(invitation).")
    }
}
