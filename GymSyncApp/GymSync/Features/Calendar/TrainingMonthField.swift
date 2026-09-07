import SwiftUI

// MARK: - TrainingMonthField
//
// The three-month dot field, extracted (plan task D1). It existed twice:
// production `TrainingCalendarWidget.monthGroupedField` (:139-216, all
// `private`) and `HomeCalendarCard`'s fixture-driven copy (:155-231), whose
// own doc comment said it was rebuilt "on the same constants" ONLY because
// the production field could not be edited from that build. That constraint
// is gone, so there is one field now and both callers render it.
//
// The constants live here, once: 12 pt gutters, a 21-column unit
// `(width - 2*gutter)/21` floored at 8, `unit * 0.42` row spacing, dots at
// `unit * 0.68` (trained/planned) and `unit * 0.52` (otherwise), cells
// `unit × unit * 0.7`, today haloed at `unit * 0.95` with a 1.2 pt accent
// stroke at 0.8 opacity. Every one is copied from the two implementations,
// which agreed on all of them — that agreement is what makes this
// extraction safe, and the proof is that `app-tab-home` and
// `app-home-v3-08a-targets-above-calendar` do not move.
//
// The MODEL is `HomeCalendarCard.Month`'s — fixture INTEGERS (month length,
// leading blanks, day-of-month sets, today's day number, and where the
// month sits relative to today) rather than `Date`s. Two reasons, both the
// card's originals: a catalog capture must render identically whatever day
// CI runs on, and the arithmetic a grid actually needs is integer
// arithmetic. `TrainingCalendarWidget` keeps its `Calendar`-derived truth
// and projects it onto this shape at the boundary (`fieldMonths`), which is
// the only new code that extraction added to production.

struct TrainingMonthField: View {
    @Environment(\.gsTheme) private var theme

    /// One month of the field. Positions are values, not dates.
    struct Month: Identifiable {
        /// Where this month sits relative to today — decides whether an
        /// untrained day reads as past (neutral400) or future (neutral300).
        enum Position { case past, current, future }

        let id: String
        /// Short month label, e.g. `AUG` (the catalog's fixtures) or `Sep`
        /// (production's `.dateTime.month(.abbreviated)`). The caller owns
        /// the casing — the two disagree today and neither is being changed
        /// by this extraction.
        let label: String
        let dayCount: Int
        /// Blank cells before day 1, 0-6 (day 1's weekday column).
        let leadingBlanks: Int
        /// Days trained — bright.
        let trained: Set<Int>
        /// Days with something scheduled — accent.
        let planned: Set<Int>
        /// Today's day-of-month, when this is the current month.
        let today: Int?
        let position: Position
    }

    let months: [Month]
    /// The field's laid-out width, which drives dot sizing so the month
    /// grids FILL their container (on-device feedback: fixed-size dots
    /// centered in equal-flex thirds left large dead gaps). 326 is the
    /// production widget's own seed value and the exact inner width of a
    /// Home card at the page's 16 pt margins on a standard iPhone — a
    /// caller that measures (`TrainingCalendarWidget`) passes its measured
    /// width; a caller that must stay hermetic takes the default.
    var fieldWidth: CGFloat = 326

    private var gutter: CGFloat { 12 }
    /// Per-weekday column slot: three months × 7 columns + two gutters.
    private var unit: CGFloat { max(8, (fieldWidth - 2 * gutter) / 21) }

    var body: some View {
        HStack(alignment: .top, spacing: gutter) {
            ForEach(months) { month in
                VStack(alignment: .center, spacing: 10) {
                    Text(month.label)
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                    grid(month)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Training calendar — last month, this month, next month")
    }

    /// One month as a true mini-calendar: 7 weekday columns × week rows, day
    /// 1 offset to its weekday column.
    private func grid(_ month: Month) -> some View {
        let cellCount = month.leadingBlanks + month.dayCount
        let weekRows = Int(ceil(Double(cellCount) / 7.0))
        return VStack(alignment: .leading, spacing: unit * 0.42) {
            ForEach(0..<weekRows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = row * 7 + column - month.leadingBlanks + 1
                        Group {
                            if day >= 1 && day <= month.dayCount {
                                dot(day, in: month)
                            } else {
                                Color.clear
                            }
                        }
                        .frame(width: unit, height: unit * 0.7)
                    }
                }
            }
        }
    }

    /// Dot semantics, unchanged from both originals: trained = bright ·
    /// scheduled = accent · past untrained = neutral400 · future =
    /// neutral300 (dimmer) · today = accent halo.
    private func dot(_ day: Int, in month: Month) -> some View {
        let isTrained = month.trained.contains(day)
        let isPlanned = month.planned.contains(day)
        let isToday = month.today == day
        let isFuture: Bool
        switch month.position {
        case .past:    isFuture = false
        case .current: isFuture = month.today.map { day > $0 } ?? false
        case .future:  isFuture = true
        }
        let fill: Color = isTrained ? theme.text
            : isPlanned ? theme.accent
            : isFuture ? theme.neutral300
            : theme.neutral400
        let size: CGFloat = (isTrained || isPlanned) ? unit * 0.68 : unit * 0.52
        return Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                isToday
                    ? Circle().strokeBorder(theme.accent.opacity(0.8), lineWidth: 1.2)
                        .frame(width: unit * 0.95, height: unit * 0.95)
                    : nil
            )
    }
}
