import SwiftUI

/// The streak as a TILE — arrangement A's left-hand slot.
///
/// Kicker `STREAK`, the number in gold at 40 pt (design language rule 2: the
/// week-streak number is one of gold's only two jobs), the slot grid, and the
/// weekly fraction under it. The number is the all-time streak; the slots and
/// the fraction are the week that protects it — the same split production's
/// `weeklyGoalWidget` (HomeView.swift:961) already makes.
///
/// Two deliberate differences from that widget, both from the v7 proof's
/// Home A:
///   * the kicker sits ABOVE the number rather than under it, so the tile
///     reads top-down: what this is → the number → the week → the fraction;
///   * the slots run left-to-right, wrapping every 5, rather than filling
///     bottom-up in columns — production's shape suits a wide card beside a
///     tall number; a tile wants the row.
/// The slot itself is unchanged: the same 17 × 14 pt rounded rect on the same
/// theme tokens.
///
/// The number stays GOLD even when the goal is met. Production turns it green
/// there; rule 2 gives the streak number to gold unconditionally, and green's
/// job (done / goal met) is carried by the slots and the fraction line.
struct HomeStreakTile: View {
    @Environment(\.gsTheme) private var theme

    /// All-time session streak — the number that never resets on the week.
    let streak: Int
    /// Distinct training DAYS this week (two sessions in a day fill one slot).
    let daysDone: Int
    /// The effective weekly goal — an edit lands next week, never this one.
    let goal: Int
    /// Tap → the weekly-goal editor.
    var action: () -> Void = {}

    private var met: Bool { daysDone >= goal }
    private static let green = Color.gsHex(0x2FA45C)

    /// Rows of slot indexes, wrapping every 5 so a 14-day goal never becomes
    /// one long line (production wraps at the same 5, in the other axis).
    private var rows: [[Int]] {
        let total = max(goal, 1)
        return stride(from: 0, to: total, by: 5).map { Array($0..<min($0 + 5, total)) }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                Text("STREAK")
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .kerning(1.6)
                    .foregroundStyle(theme.neutral500)

                Text("\(streak)")
                    .font(GSFont.heading(40, relativeTo: .largeTitle))
                    .foregroundStyle(HomeV2Gold.top)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.top, 2)

                slotGrid
                    .padding(.top, 10)

                Text("\(daysDone)/\(goal) DAYS THIS WEEK")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .kerning(0.6)
                    .foregroundStyle(met ? Self.green : theme.neutral700)
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.horizontal, 15)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(streak). \(daysDone) of \(goal) days this week.")
    }

    private var slotGrid: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: 4) {
                    ForEach(rows[row], id: \.self) { index in
                        slot(index)
                    }
                }
            }
        }
    }

    /// Filled = done (green once the goal is met, otherwise plain text
    /// colour). The NEXT slot is an accent ring — the invitation — and the
    /// rest are the recessed neutral. Production breathes the next slot with
    /// an animation; a screenshot cannot show a breath, so the ring carries it.
    @ViewBuilder
    private func slot(_ index: Int) -> some View {
        let filled = index < daysDone
        let isNext = !filled && index == daysDone && !met
        RoundedRectangle(cornerRadius: 3)
            .fill(filled ? (met ? Self.green : theme.text) : theme.neutral300)
            .frame(width: 17, height: 14)
            .overlay(
                isNext
                    ? RoundedRectangle(cornerRadius: 3).strokeBorder(theme.accent, lineWidth: 2)
                    : nil
            )
    }
}
