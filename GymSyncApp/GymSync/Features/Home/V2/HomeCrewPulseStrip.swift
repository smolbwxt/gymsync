import SwiftUI

/// Who from your crew is in the gym right now, as a STRIP (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// An avatar wearing a green presence ring — rule 2's other meaning of
/// green, "present" — then who and what, then the chevron into the crew
/// room. A strip (rule 1): `surface` fill, 14 pt radius, no extrusion,
/// because it belongs to the button above it on a crew night.
///
/// The ring is drawn on the avatar itself rather than as a separate dot: a
/// dot is one more object on a line that already has three, and the ring
/// says the same thing without adding one.
struct HomeCrewPulseStrip: View {
    @Environment(\.gsTheme) private var theme

    /// Two-letter avatar, e.g. `DA` — the same glyph-tile idiom the calendar
    /// rows and `HomeCoachLine` use.
    let initials: String
    /// Who and what, e.g. `Dana is lifting now`.
    let headline: String
    /// Which crew and when, e.g. `Push Crew · tonight 5:00 PM`.
    let detail: String
    /// Tap → the crew room.
    var action: () -> Void = {}

    /// The one green this codebase uses — here in its "present" job.
    private static let green = Color.gsHex(0x2FA45C)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Circle()
                    .fill(theme.neutral300)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(initials)
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(0.6)
                            .foregroundStyle(theme.neutral800)
                    )
                    .overlay(Circle().strokeBorder(Self.green, lineWidth: 2))

                VStack(alignment: .leading, spacing: 3) {
                    Text(headline)
                        .font(GSFont.bold(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(GSFont.body(11.5, relativeTo: .caption))
                        .monospacedDigit()
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 6)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(headline). \(detail). Opens the crew room.")
    }
}
