import SwiftUI

/// What is recovered and what is not, as a STRIP (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// Two chips and one sentence: the chips are scannable, the sentence says
/// the same thing in Coach's plain voice for anyone who reads rather than
/// scans. Green on the fresh chip is design language rule 2's own second
/// meaning of green — "recovered" is listed there beside done and present —
/// and the tender chip is deliberately NOT red: red is for errors, and a
/// sore chest is not an error. It takes the muted pill the `{n} UPCOMING`
/// count already wears.
///
/// A strip (rule 1): `surface` fill, 14 pt radius, no extrusion. Not
/// tappable — there is no recovery page to open yet, and a chevron that
/// leads nowhere is a lie.
struct HomeRecoveryStrip: View {
    @Environment(\.gsTheme) private var theme

    /// Muscles that are recovered, e.g. `BACK · LEGS`.
    let fresh: String
    /// Muscles that are not, e.g. `CHEST`.
    let tender: String
    /// The same read as a sentence, e.g. `Back and legs are fresh. Chest is
    /// still tender.`
    let sentence: String

    /// The one green this codebase uses (`HomeStreakTile`, `HomeWeekStrip`,
    /// `HomeCalendarCard`'s `IN` chip).
    private static let green = Color.gsHex(0x2FA45C)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                chip(muscles: fresh, state: "FRESH", tint: Self.green, filled: true)
                chip(muscles: tender, state: "TENDER", tint: theme.neutral700, filled: false)
                Spacer(minLength: 0)
            }

            Text(sentence)
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(sentence)
    }

    /// `HomeCalendarCard.chip`'s shape, verbatim (bold 10, 1.1 kerning, 9/5
    /// padding, a capsule at 0.16 of the tint) — with the muscles and the
    /// state word in one capsule so the pair reads as a single fact.
    /// `filled: false` swaps the tinted capsule for the neutral pill, which
    /// is what "muted" means everywhere else in this kit.
    private func chip(muscles: String, state: String, tint: Color, filled: Bool) -> some View {
        HStack(spacing: 6) {
            Text(muscles)
            Text(state)
                .opacity(0.75)
        }
        .font(GSFont.bold(10, relativeTo: .caption2))
        .kerning(1.1)
        .lineLimit(1)
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Capsule().fill(filled ? tint.opacity(0.16) : theme.neutral300))
    }
}
