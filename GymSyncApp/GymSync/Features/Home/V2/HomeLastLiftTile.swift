import SwiftUI

/// What you did last, as a TILE — Home v3's readout for the session behind
/// you (plan: `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`,
/// "New pieces").
///
/// Kicker `LAST LIFT`, the routine's name at 22 pt, and one line of what it
/// weighed. A readout, not a question, so it sits BELOW the one button
/// (design language rule 4) — but it is still extruded and tappable, because
/// the recap of that session is a real page one tap away.
///
/// Styling is Home v2's tile, verbatim: `.gs3DCardStyle` at `radiusMd` (it
/// sinks), `HomeStreakTile`'s kicker (bold 11, 1.6 kerning, `neutral500`),
/// and `HomeCoachTile`'s body line (12 pt, `neutral700`). The 12 pt inner
/// padding and 104 pt minimum height are the plan's own numbers for the v3
/// tiles — a v3 tile carries three short lines where v2's carried a number
/// and a grid, so it is allowed to be tighter and shorter than
/// `HomeStreakTile`'s 15/13. Both still stretch to the taller of the pair
/// inside the v3 tile row.
struct HomeLastLiftTile: View {
    @Environment(\.gsTheme) private var theme

    /// The routine that was run, e.g. `Push A`.
    let routine: String
    /// The one line under it, e.g. `Wed · 7,240 lb · 1 PR`.
    let detail: String
    /// Tap → that session's recap.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("LAST LIFT")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(1.6)
                    .foregroundStyle(theme.neutral500)

                Text(routine)
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 6)

                Text(detail)
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
        .accessibilityLabel("Last lift, \(routine). \(detail).")
    }
}
