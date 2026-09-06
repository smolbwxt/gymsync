import SwiftUI

// MARK: - CalendarMonthGrid
//
// The calendar page's month, at DAY-NUMBER scale — the v7 proof's grid
// (`04-calendar-scheduling-new-page.png`), not Home's dot field. The two are
// deliberately different objects: Home's `TrainingMonthField` is a texture
// three months wide, where a habit reads as a vertical line and no single day
// needs to be nameable; this is one month at the scale where you point at a
// day and say "move that one". Same facts, different question.
//
// Ring semantics (design §C, plan D2):
//   * trained      — the cell is FILLED in `theme.text`, number in `theme.bg`
//   * you          — an accent ring
//   * crew         — a ring in that crew's `GSGroupColor`
//   * today        — a distinct halo, one size up, in `theme.text`
//
// Today's halo is drawn OUTSIDE whatever the day already wears rather than
// replacing it, which is exactly the rule `TrainingMonthField.dot` has always
// applied to its own today (an overlay stroke at `unit * 0.95`, on top of the
// dot's fill). A day can be both today and booked, and the page must say so.
// The halo is `theme.text` because the other two colours are taken: accent
// means "you", and every `GSGroupColor` means "a crew".
//
// Every input is a value — day NUMBERS, not `Date`s. The page projects its
// `Calendar` truth onto this at the boundary, which is what lets the catalog
// render the frame hermetically (`calendar-scheduling`, plan D5).

struct CalendarMonthGrid: View {
    @Environment(\.gsTheme) private var theme

    struct Month {
        /// `SEPTEMBER 2026` — already cased for display; the grid does not
        /// format dates.
        let label: String
        /// Column headings, first-weekday first (`M T W T F S S`).
        let weekdayLabels: [String]
        let dayCount: Int
        /// Blank cells before day 1, 0-6 (day 1's weekday column).
        let leadingBlanks: Int
        /// Days trained — filled cells.
        var trained: Set<Int> = []
        /// Days you have a session booked on — accent ring.
        var scheduled: Set<Int> = []
        /// Days a crew has a session on, and that crew's identity colour.
        /// A day booked with a crew wears the CREW's ring, not the accent:
        /// the page's whole job is telling you who you are training with.
        var crew: [Int: Color] = [:]
        /// Today's day-of-month, when today falls in this month.
        var today: Int? = nil
        /// The days of the week the agenda below is showing — boxed, so the
        /// grid and the `THIS WEEK` list are visibly the same week.
        var selectedWeek: Set<Int> = []
    }

    let month: Month
    /// The swatch the legend's `Crew` entry wears. The page passes the first
    /// crew colour actually on the grid so the legend describes THIS month
    /// rather than a generic one.
    let legendCrewColor: Color

    /// Cell face; the column slot is whatever the row's width divides into
    /// seven, so the grid fills its card at any width without measuring.
    private let cell: CGFloat = 40
    private let cellRadius: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            weekdayHeader
            grid
            legend
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(month.label)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(month.weekdayLabels.enumerated()), id: \.offset) { _, label in
                Text(label)
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekRows: Int {
        Int(ceil(Double(month.leadingBlanks + month.dayCount) / 7.0))
    }

    private var grid: some View {
        VStack(spacing: 6) {
            ForEach(0..<weekRows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<7, id: \.self) { column in
                        let day = row * 7 + column - month.leadingBlanks + 1
                        Group {
                            if day >= 1 && day <= month.dayCount {
                                dayCell(day)
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: Int) -> some View {
        let isTrained = month.trained.contains(day)
        let crewColor = month.crew[day]
        let isYours = month.scheduled.contains(day)
        let isToday = month.today == day
        let inWeek = month.selectedWeek.contains(day)
        // The ring says WHO. A crew booking outranks a solo one on the same
        // day for the same reason the agenda row leads with the crew's name:
        // the crew is the part of the day you cannot move by yourself.
        let ring: Color? = crewColor ?? (isYours ? theme.accent : nil)
        let fill: Color = isTrained ? theme.text : (inWeek ? theme.neutral100 : .clear)
        let ink: Color = isTrained ? theme.bg
            : (ring != nil || isToday || inWeek) ? theme.text
            : theme.neutral500

        Text("\(day)")
            .font(GSFont.bold(15, relativeTo: .body))
            .monospacedDigit()
            .foregroundStyle(ink)
            .frame(width: cell, height: cell)
            .background(RoundedRectangle(cornerRadius: cellRadius).fill(fill))
            .overlay {
                if let ring {
                    RoundedRectangle(cornerRadius: cellRadius)
                        .strokeBorder(ring, lineWidth: 2)
                }
            }
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: cellRadius + 2)
                        .strokeBorder(theme.text, lineWidth: 1.5)
                        .padding(-2)
                }
            }
            .accessibilityLabel(accessibilityLabel(day: day, trained: isTrained,
                                                   crew: crewColor != nil,
                                                   yours: isYours, today: isToday))
    }

    private func accessibilityLabel(day: Int, trained: Bool, crew: Bool,
                                    yours: Bool, today: Bool) -> String {
        var parts = ["\(day)"]
        if today { parts.append("today") }
        if trained { parts.append("trained") }
        if crew { parts.append("crew session") }
        else if yours { parts.append("your session") }
        return parts.joined(separator: ", ")
    }

    /// `Trained · You · Crew` — the three things a ring or a fill can mean,
    /// named once under the grid so nothing on it has to be guessed.
    private var legend: some View {
        HStack(spacing: 14) {
            legendEntry(swatch: filledSwatch, "Trained")
            legendEntry(swatch: ringSwatch(theme.accent), "You")
            legendEntry(swatch: ringSwatch(legendCrewColor), "Crew")
        }
        .accessibilityElement(children: .combine)
    }

    private func legendEntry(swatch: some View, _ label: String) -> some View {
        HStack(spacing: 6) {
            swatch
            Text(label)
                .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    private var filledSwatch: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(theme.text)
            .frame(width: 12, height: 12)
    }

    private func ringSwatch(_ color: Color) -> some View {
        RoundedRectangle(cornerRadius: 4)
            .strokeBorder(color, lineWidth: 2)
            .frame(width: 12, height: 12)
    }
}
