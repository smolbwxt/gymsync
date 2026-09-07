import SwiftUI

// MARK: - HomeCalendarCardModel
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, task
// B5. The mapping from the three arrays Home already fetched — history,
// upcoming, groups — onto the fixture-shaped values `HomeCalendarCard` takes.
//
// WHY THE CARD TAKES FIXTURE SHAPES AT ALL. `HomeCalendarCard` was built for
// the catalog, where a frame has to render identically whatever day CI runs
// on, so its `Month` carries a day COUNT, a leading-blank count and sets of
// day NUMBERS rather than `Date`s (`HomeCalendarCard.swift:14-26` says so).
// Production has real dates. This is the one place they are flattened, and
// it is a pure function of its inputs so it can be tested without a view —
// `HomeCompositionTests` (task B7) does exactly that.
//
// THE CALENDAR PAGE DOES NOT CALL THIS (final review finding 9 — this
// comment used to claim it did). `CalendarSchedulingView.derivedWorld` builds
// its own `CalendarMonthGrid.Month` from its own trained / scheduled / crew
// loops, because the page needs one month with the crew split out where the
// card needs three with them merged. What task D1 actually extracted and
// shared is `TrainingMonthField`, which the page does not use either.
//
// So two mappings DO exist, and they agree today only because both date a
// trained day by the same `completedAt ?? startedAt ?? scheduledFor` chain.
// That is the invariant to hold if either side is edited; the plan's own
// "does not decide" list carries the merge as a follow-up.
enum HomeCalendarCardModel {

    /// Previous / current / next month, the three the card renders.
    ///
    /// Dot semantics are the production dot field's, unchanged: trained =
    /// bright, scheduled = accent, past untrained = neutral400, future =
    /// dimmer, today haloed. A trained day is dated by `completedAt`, else
    /// `startedAt`, else `scheduledFor` — the same fallback chain
    /// `TrainingCalendarWidget.trainedDays` walked.
    static func months(completed: [WorkoutSession],
                       upcoming: [WorkoutSession],
                       now: Date = .now,
                       calendar: Calendar = .current) -> [HomeCalendarCard.Month] {
        let today = calendar.startOfDay(for: now)
        guard let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: today))
        else { return [] }

        let trainedDays = Set(completed.compactMap { session -> Date? in
            guard let when = session.completedAt ?? session.startedAt ?? session.scheduledFor else { return nil }
            return calendar.startOfDay(for: when)
        })
        let plannedDays = Set(upcoming.compactMap { session -> Date? in
            session.scheduledFor.map { calendar.startOfDay(for: $0) }
        })

        return [-1, 0, 1].compactMap { offset -> HomeCalendarCard.Month? in
            guard let monthStart = calendar.date(byAdding: .month, value: offset, to: thisMonthStart)
            else { return nil }
            let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
            // Blanks before day 1, relative to the LOCALE's week start —
            // `firstWeekday` is honoured, exactly as the old field did.
            let leading = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
            var trained: Set<Int> = []
            var planned: Set<Int> = []
            for dayIndex in 0..<dayCount {
                guard let day = calendar.date(byAdding: .day, value: dayIndex, to: monthStart) else { continue }
                if trainedDays.contains(day) { trained.insert(dayIndex + 1) }
                if plannedDays.contains(day) { planned.insert(dayIndex + 1) }
            }
            let parts = calendar.dateComponents([.year, .month], from: monthStart)
            return HomeCalendarCard.Month(
                id: "\(parts.year ?? 0)-\(parts.month ?? 0)",
                label: monthStart.formatted(.dateTime.month(.abbreviated)).uppercased(),
                dayCount: dayCount,
                leadingBlanks: leading,
                trained: trained,
                planned: planned,
                today: offset == 0 ? calendar.component(.day, from: today) : nil,
                position: offset < 0 ? .past : (offset == 0 ? .current : .future)
            )
        }
    }

    /// EVERY upcoming session, so the header's `{n} UPCOMING` count is the
    /// same number the old widget showed. On Home the rows these describe do
    /// not render (`showsAppointments: false`) — the itinerary moved to the
    /// page — but the card still counts them, and Stream D renders them.
    ///
    /// `status` is deliberately `nil`. Home fetches a commitment only for
    /// the NEXT group session (`nextCommitStatus`); a per-row IN/COMMIT chip
    /// built from that one answer would be a guess about every other row.
    static func appointments(upcoming: [WorkoutSession],
                             groups: [GymGroup],
                             title: (WorkoutSession) -> String,
                             now: Date = .now,
                             calendar: Calendar = .current) -> [HomeCalendarCard.Appointment] {
        upcoming.enumerated().map { index, session in
            let group = session.groupID.flatMap { gid in groups.first(where: { $0.id == gid }) }
            let day: String
            if let when = session.scheduledFor {
                day = calendar.isDate(when, inSameDayAs: now)
                    ? "Today"
                    : when.formatted(.dateTime.weekday(.abbreviated))
            } else {
                day = session.state.replacingOccurrences(of: "_", with: " ").capitalized
            }
            return HomeCalendarCard.Appointment(
                id: index,
                day: day,
                time: session.scheduledFor.map { $0.formatted(.dateTime.hour().minute()) } ?? "No time set",
                initials: group.map { initials(of: $0.name) } ?? "You",
                // nil tint/ink = your own solo session, which the card
                // resolves to the accent on the page ground at render.
                tint: group.map { GSGroupColor.color(for: $0.id) },
                ink: group.map { GSGroupColor.onColor(for: $0.id) },
                title: title(session),
                subtitle: group?.name ?? "Solo",
                repeats: session.seriesID != nil,
                status: nil
            )
        }
    }

    /// Two-letter crew tile — `TrainingCalendarWidget.initials`' idiom.
    static func initials(of name: String) -> String {
        name.split(separator: " ").prefix(2)
            .map { String($0.prefix(1)).uppercased() }
            .joined()
    }
}
