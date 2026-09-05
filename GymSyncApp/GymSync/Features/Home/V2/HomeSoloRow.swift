import SwiftUI

/// The quiet solo escape that sits under the one button whenever the primary
/// is a crew state (design language rule 5), with the burpee counter beside it
/// when debt exists — exactly production's current row (`HomeView
/// .soloSecondaryButton`, :422, and `burpeeOwedWidget`, :488), re-created here
/// because both are `private` to `HomeView` and this build does not edit it.
///
/// Two deliberate differences from production, both from the plan/proof:
///   * the pill's face is 48 pt, not 55 — Home v2 spends the freed height on
///     the one button above it (57 pt);
///   * the label is caps with no `plus` glyph (rule 9: caps for buttons; the
///     v7 proof's Home A shows `START SOLO WORKOUT` bare).
///
/// The pill is a `GS3DButtonStyle` (it presses); the counter is a STATIC
/// `.gs3DCard` on the accent face — it is a status widget, not a CTA, so it
/// does not sink. Accent, never gold: gold is the check-in signal and nothing
/// else wears it (rule 2).
struct HomeSoloRow: View {
    @Environment(\.gsTheme) private var theme

    let burpeesOwed: Int
    /// Tap → the routine picker (`RoutinePickerSheet` in production).
    var onStartSolo: () -> Void = {}
    /// Tap → the burpee ledger of the group carrying the most debt.
    var onOpenLedger: () -> Void = {}

    private var rowHeight: CGFloat { HomeV2Metrics.soloPillFace + HomeV2Metrics.lip }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onStartSolo) {
                Text("START SOLO WORKOUT")
                    .font(GSFont.bold(15, relativeTo: .subheadline))
                    .tracking(0.9)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity)
                    .frame(height: HomeV2Metrics.soloPillFace)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                               cornerRadius: GSMetrics.radiusMd,
                               lipHeight: HomeV2Metrics.lip))

            if burpeesOwed > 0 {
                burpeeWidget
            }
        }
        // One fixed row height so the pill and the counter stand
        // shoulder-to-shoulder, both seams on the same line.
        .frame(height: rowHeight)
    }

    /// Fixed width so the pill's concession is a predictable amount rather
    /// than a text-length-dependent jitter (production's own note).
    private var burpeeWidget: some View {
        Button(action: onOpenLedger) {
            VStack(spacing: 1) {
                Text("\(burpeesOwed)")
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.bg)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Text("BURPEES")
                    .font(GSFont.bold(9.5, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.bg.opacity(0.8))
            }
            .frame(width: 96)
            .frame(maxHeight: .infinity)
            .gs3DCard(cornerRadius: GSMetrics.radiusMd,
                      lipHeight: HomeV2Metrics.lip,
                      face: theme.accent)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("You owe \(burpeesOwed) burpees. Open the burpee ledger.")
    }
}
