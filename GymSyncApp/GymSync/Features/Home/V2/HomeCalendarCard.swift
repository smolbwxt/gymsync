import SwiftUI

/// The training calendar, folded: the month dot fields with the next few
/// appointments underneath, in one card.
///
/// Design language rule 4: anything that lives on a timeline is visible on
/// Home, or one tap from the page where it is editable. So the WHOLE card is
/// one tap target onto the calendar & scheduling page — the `+` circle and the
/// per-row status chips are affordances riding that one navigation, not nested
/// buttons (the same call production's `commitControl` already makes,
/// HomeView.swift:856-862, and for the same reason: a `Button` inside a
/// `Button`'s label is a gesture-conflict hazard).
///
/// The dot field is `TrainingCalendarWidget.monthGroupedField` (:139) rebuilt
/// on the same constants — 12 pt gutters, a 21-column unit, `unit * 0.42` row
/// spacing, dots at `unit * 0.68` (trained/planned) and `unit * 0.52`
/// (otherwise), today haloed at `unit * 0.95` — because that widget's field is
/// `private` and this build does not edit it. Two differences, both to keep a
/// catalog capture hermetic:
///   * days are fixture INTEGERS (month length + leading blanks + the trained
///     / planned sets) rather than `Calendar`-derived `Date`s, so the field
///     renders identically whatever day CI runs on;
///   * `fieldWidth` is the constant 326 — the same value the production widget
///     SEEDS its measured width with, and the exact inner width of this card at
///     the page's 16 pt margins on a standard iPhone — rather than being
///     measured, so no geometry observation is needed.
struct HomeCalendarCard: View {
    @Environment(\.gsTheme) private var theme

    /// One month of the field. Positions are fixture values, not dates.
    struct Month: Identifiable {
        /// Where this month sits relative to today — decides whether an
        /// untrained day reads as past (neutral400) or future (neutral300).
        enum Position { case past, current, future }

        let id: String
        /// Short month label, e.g. `AUG`.
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

    /// One folded appointment row: `Today 5:00 PM · PC · Push A · Push Crew ·
    /// IN ›`, 44 pt tall.
    struct Appointment: Identifiable {
        enum Status {
            /// You have checked in. Green means present (rule 2).
            case checkedIn
            /// You haven't said yet — committing happens on the crew board.
            case commit
        }

        let id: Int
        /// `Today`, `Sat`, `Tue` …
        let day: String
        let time: String
        /// Two-letter tile: a crew's initials, or `You` for a solo lift.
        let initials: String
        /// The tile's identity colour — a `GSGroupColor` for a crew. `nil` is
        /// your own solo session, which wears the accent on the page ground
        /// (`TrainingCalendarWidget.avatarTile`'s rule), resolved at render
        /// because a fixture cannot know the user's accent.
        let tint: Color?
        let ink: Color?
        let title: String
        let subtitle: String
        /// Repeats — the series glyph the production row also shows.
        let repeats: Bool
        let status: Status?
    }

    let months: [Month]
    let appointments: [Appointment]
    /// Tap → the calendar & scheduling page.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                header
                monthField.padding(.top, 14)
                if !appointments.isEmpty {
                    appointmentList.padding(.top, 16)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            GSSectionHeader("Training calendar")
            if !appointments.isEmpty {
                Text("\(appointments.count) UPCOMING")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(theme.neutral300))
            }
            // Schedule affordance — rides the card's own navigation.
            Image(systemName: "plus")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(theme.neutral300))
        }
    }

    // MARK: Month dot field

    private static let gutter: CGFloat = 12
    /// See the type's doc comment: the production widget's own seed value, and
    /// this card's inner width at the page's 16 pt margins.
    private static let fieldWidth: CGFloat = 326
    /// Per-weekday column slot: three months × 7 columns + two gutters.
    private static var unit: CGFloat { max(8, (fieldWidth - 2 * gutter) / 21) }

    private var monthField: some View {
        HStack(alignment: .top, spacing: Self.gutter) {
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

    /// One month as a true mini-calendar: 7 weekday columns × week rows, day 1
    /// offset to its weekday column.
    private func grid(_ month: Month) -> some View {
        let cellCount = month.leadingBlanks + month.dayCount
        let weekRows = Int(ceil(Double(cellCount) / 7.0))
        return VStack(alignment: .leading, spacing: Self.unit * 0.42) {
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
                        .frame(width: Self.unit, height: Self.unit * 0.7)
                    }
                }
            }
        }
    }

    /// Dot semantics, unchanged from the production field: trained = bright ·
    /// scheduled = accent · past untrained = neutral400 · future = neutral300
    /// (dimmer) · today = accent halo.
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
        let size: CGFloat = (isTrained || isPlanned) ? Self.unit * 0.68 : Self.unit * 0.52
        return Circle()
            .fill(fill)
            .frame(width: size, height: size)
            .overlay(
                isToday
                    ? Circle().strokeBorder(theme.accent.opacity(0.8), lineWidth: 1.2)
                        .frame(width: Self.unit * 0.95, height: Self.unit * 0.95)
                    : nil
            )
    }

    // MARK: Folded appointments

    private var appointmentList: some View {
        VStack(spacing: 0) {
            Rectangle().fill(theme.divider).frame(height: 1)
            ForEach(Array(appointments.prefix(3).enumerated()), id: \.element.id) { index, appointment in
                row(appointment)
                if index < min(appointments.count, 3) - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    private func row(_ appointment: Appointment) -> some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 1) {
                Text(appointment.day)
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(appointment.time)
                    .font(GSFont.body(10.5, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
            }
            .frame(width: 58, alignment: .leading)

            RoundedRectangle(cornerRadius: 9)
                .fill(appointment.tint ?? theme.accent)
                .frame(width: 30, height: 30)
                .overlay(
                    Text(appointment.initials)
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(appointment.ink ?? theme.bg)
                )

            HStack(spacing: 5) {
                Text(appointment.title)
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if appointment.repeats {
                    Image(systemName: "repeat")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(theme.accent)
                }
                Text(appointment.subtitle)
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(1)
                    .layoutPriority(-1)
            }

            Spacer(minLength: 6)

            if let status = appointment.status {
                chip(status)
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
        .frame(height: 44)
    }

    @ViewBuilder
    private func chip(_ status: Appointment.Status) -> some View {
        switch status {
        case .checkedIn:
            Text("IN")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(Color.gsHex(0x2FA45C))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(Color.gsHex(0x2FA45C).opacity(0.16)))
        case .commit:
            Text("COMMIT")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .kerning(1.1)
                .foregroundStyle(theme.accent)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(theme.accent.opacity(0.16)))
        }
    }
}
