import SwiftUI

/// The next session on the calendar, as a STRIP (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// The v3 calendar card no longer carries its itinerary (`HomeCalendarCard
/// .showsAppointments`), so the one row that still earns a place on Home —
/// the very next thing — comes back as a line of its own. A strip, not a
/// card (design language rule 1): `surface` fill, 14 pt radius, no
/// extrusion, because it belongs to the calendar card it sits beside.
///
/// Tappable, with the trailing chevron the calendar's own rows used to
/// carry: one tap opens that session.
struct HomeUpNextStrip: View {
    @Environment(\.gsTheme) private var theme

    /// Kicker — carries the when, e.g. `NEXT · SAT 9:00 AM`.
    let kicker: String
    /// The session itself, e.g. `Lower B with Legs Crew`.
    let title: String
    /// Tap → that session's page.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(kicker)
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .monospacedDigit()
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(title)
                        .font(GSFont.bold(15, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
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
        .accessibilityLabel("\(kicker). \(title). Opens the session.")
    }
}
