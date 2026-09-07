import SwiftUI

/// The streak as a STRIP — arrangement B's form of the same idea.
///
/// Gold streak number at the head (design language rule 2), seven day chips in
/// the middle, the weekly fraction at the tail. A strip, not a card (rule 1):
/// `surface` fill, 14 pt radius, no extrusion — it belongs to the today card
/// above it.
struct HomeWeekStrip: View {
    @Environment(\.gsTheme) private var theme

    /// One day of the training week.
    struct Day: Identifiable {
        enum State {
            /// Trained. Filled in the text colour.
            case done
            /// Today. An accent ring, and the letter goes accent with it.
            case today
            /// Something is scheduled. A quieter accent ring.
            case planned
            /// Nothing yet.
            case empty
        }
        /// Stable id — the weekday letter repeats (T, T and S, S), so the
        /// letter alone cannot key a `ForEach`.
        let id: Int
        let letter: String
        let state: State
    }

    /// All-time session streak — the number that never resets on the week.
    let streak: Int
    let days: [Day]
    let daysDone: Int
    let goal: Int

    private var met: Bool { daysDone >= goal }
    private static let green = Color.gsHex(0x2FA45C)

    var body: some View {
        HStack(spacing: 12) {
            head
            rule
            chips
            rule
            tail
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Streak \(streak). \(daysDone) of \(goal) days this week.")
    }

    private var head: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(streak)")
                .font(GSFont.heading(26, relativeTo: .title2))
                .foregroundStyle(HomeV2Gold.top)
                .monospacedDigit()
                .lineLimit(1)
            Text("WK STREAK")
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
        }
    }

    private var rule: some View {
        Rectangle()
            .fill(theme.divider)
            .frame(width: 1, height: 34)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            ForEach(days) { day in
                HomeWeekDayChip(letter: day.letter, state: day.state)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var tail: some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text("\(daysDone)/\(goal)")
                .font(GSFont.bold(16, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(met ? Self.green : theme.text)
                .lineLimit(1)
            // The plan names the goal-met tail (`4/4 · GOAL MET`); the
            // not-yet tail says what the fraction is instead of claiming a
            // goal that hasn't been met.
            Text(met ? "GOAL MET" : "THIS WEEK")
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(met ? Self.green : theme.neutral500)
                .lineLimit(1)
        }
    }
}

// MARK: - One day

/// ONE day of the training week, exactly as `HomeWeekStrip` has always drawn
/// it: a 10 × 24 chip with the weekday letter under it.
///
/// Extracted from `HomeWeekStrip.chips` / `chip(_:)` in task C2, because the
/// weekly goal's `days` kind renders the same seven chips
/// (`HomeWeeklyGoalStrip.daysBody`) and the plan asks for Home's two week
/// readouts to be "literally the same view". The alternative — a second copy
/// built on the same constants — is the exact mistake `HomeCalendarCard`'s
/// own doc comment records against itself (:14-26) and that Stream D's D1
/// exists to unwind; making it a second time, in the same week, on the same
/// screen, would be a choice rather than a constraint.
///
/// A pure move. Same `RoundedRectangle(cornerRadius: 5)`, same 10 × 24 frame,
/// same fills and strokes, same `VStack(spacing: 4)`, same 9 pt letter in the
/// same two colours. `HomeWeekStrip`'s rendering does not change, which is
/// what keeps every v2/v3 frame carrying it byte-identical.
struct HomeWeekDayChip: View {
    @Environment(\.gsTheme) private var theme

    /// The weekday's letter — `M`, `T`, … The letters repeat, so this is
    /// never an identity; `HomeWeekStrip.Day.id` still keys the `ForEach`.
    let letter: String
    let state: HomeWeekStrip.Day.State

    var body: some View {
        VStack(spacing: 4) {
            chip
            Text(letter)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .foregroundStyle(state.isToday ? theme.accent : theme.neutral500)
        }
    }

    @ViewBuilder
    private var chip: some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        switch state {
        case .done:
            // Deliberately NOT green when the goal is met: green belongs to
            // the tail (`4/4` and `GOAL MET`) alone. Turning the chips green
            // as well made the difference between the two B frames read as a
            // state change rather than as the arrangement being judged.
            shape.fill(theme.text)
                .frame(width: 10, height: 24)
        case .today:
            shape.strokeBorder(theme.accent, lineWidth: 2)
                .frame(width: 10, height: 24)
        case .planned:
            shape.strokeBorder(theme.accent.opacity(0.55), lineWidth: 1.5)
                .frame(width: 10, height: 24)
        case .empty:
            shape.fill(theme.neutral300)
                .frame(width: 10, height: 24)
        }
    }
}

/// Still file-private: `HomeWeekDayChip` is declared in this file, so the
/// extraction costs the app no new public surface.
private extension HomeWeekStrip.Day.State {
    var isToday: Bool {
        if case .today = self { return true }
        return false
    }
}
