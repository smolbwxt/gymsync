import SwiftUI

// MARK: - CalendarSchedulingView
//
// Design: docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly
// -goal-design.md §C. Plan: docs/superpowers/plans/2026-09-06-home-v3
// -production-plan.md, task 0.4 (the scaffold) and Stream D (this page).
//
// The page `HomeCalendarCard` is a door onto. Design language rule 4:
// anything that lives on a timeline is visible on Home, or ONE TAP from the
// page where it is editable — this is that page, and the card's whole
// surface, its `+` and its status chips all land here.
//
// The type name and the init are FIXED (task 0.4): Stream B builds its push
// against `CalendarSchedulingView(completedSessions:upcomingSessions:groups:)`
// and Stream D fills the body in without touching either. The two properties
// this task adds (`today`, `world`) carry defaults, so that three-label call
// site is exactly as it was — they exist for the catalog, which cannot read a
// clock or a repository and still produce the same frame twice.
//
// No new data model (design §C is explicit). The page is a COMPOSITION of
// what already exists: `SessionRepository.upcoming()` / `.history(userID:
// limit:)`, `SeriesRepository`, `ProgramRepository.active()`,
// `CampaignRepository`, and the editors those rows open.

struct CalendarSchedulingView: View {
    /// The sessions the caller already fetched, so the page paints instantly
    /// from Home's `refresh()` results and re-fetches in the background.
    let completedSessions: [WorkoutSession]
    let upcomingSessions: [WorkoutSession]
    let groups: [GymGroup]

    /// The day the page is anchored on — which month opens, which week the
    /// agenda shows, which cell wears today's halo.
    ///
    /// Injected rather than read from the clock. The scaffold's `monthLine`
    /// read `Date.now` and the task 0 review flagged it: a catalog frame that
    /// reads a clock renders a different month every month, so its capture
    /// can never be compared against itself. Production takes the default and
    /// behaves exactly as a clock read would.
    var today: Date = .now

    /// A pre-resolved world, for the `calendar-scheduling` catalog frame.
    ///
    /// When present the page renders it and touches NO repository — see
    /// `refresh()`. Production leaves it nil and the page derives the same
    /// shape from `today` and the sessions it holds.
    var world: CalendarWorld? = nil

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var showScheduleSheet = false
    /// Months away from `today`'s month — the swipe's whole state.
    @State private var monthOffset = 0
    /// Background re-fetches. `nil` until one lands, so the page paints from
    /// the caller's arrays first and never blanks while it re-reads.
    @State private var refreshedUpcoming: [WorkoutSession]?
    @State private var refreshedCompleted: [WorkoutSession]?

    private var completed: [WorkoutSession] { refreshedCompleted ?? completedSessions }
    private var upcoming: [WorkoutSession] { refreshedUpcoming ?? upcomingSessions }

    /// What the page draws: the injected world, or the one derived from the
    /// sessions in hand. One render path, two sources.
    private var resolved: CalendarWorld { world ?? derivedWorld }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(resolved.month.label)
                    .font(GSFont.bold(11, relativeTo: .caption))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)

                CalendarMonthGrid(month: resolved.month,
                                  legendCrewColor: resolved.legendCrewColor)
                    .gesture(monthSwipe)

                thisWeekHeader

                // Stream D — D3: the selected week's agenda, one row per item
                // with day / routine / crew or Solo / status pill / chevron,
                // and the swipe actions the header above advertises.
                // Stream D — D4: the block's days and campaign deadlines on
                // the same timeline.

                scheduleButton
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showScheduleSheet = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(theme.neutral300))
                }
                .accessibilityLabel("Schedule a session")
            }
        }
        .sheet(isPresented: $showScheduleSheet) {
            // The existing scheduler, unchanged — the design's §C says the
            // page's primary opens `ScheduleSessionView`, not a new one.
            ScheduleSessionView { _ in
                Task { await refresh() }
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
    }

    // MARK: This week

    /// `THIS WEEK` and, on the right, what you can do to a row in it. The
    /// hint names the gesture the agenda rows carry (task D3) — it is here
    /// because it belongs to the SECTION, not to any one row, and a hint
    /// printed once above a list is the only place it does not repeat.
    private var thisWeekHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            GSSectionHeader("This week")
            Text("SWIPE A ROW TO MOVE OR CANCEL")
                .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.trailing)
        }
        .padding(.top, 4)
    }

    // MARK: The primary

    /// The page's ONE primary (design language rule 4). The toolbar `+` is
    /// the same act as a 32 pt affordance rather than a second primary — it
    /// rides the accent glyph the calendar card already uses for it
    /// (`HomeCalendarCard`:134-138), so the door and the room agree.
    ///
    /// Extruded exactly like the sheet it opens
    /// (`ScheduleSessionView`:175-179): `.gs3D` on an accent face at
    /// `radiusSm`, label in `theme.bg`, 16/14 padding. Deliberately NOT
    /// `HomeV2Metrics`' 57/48 pt faces — those are Home's own row geometry,
    /// and a calendar page borrowing them would be the first cross-feature
    /// reader of that enum for no reason.
    private var scheduleButton: some View {
        Button {
            showScheduleSheet = true
        } label: {
            Text("SCHEDULE A SESSION")
                .font(GSFont.heading(16, relativeTo: .headline))
                .tracking(0.6)
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
    }

    // MARK: Months

    /// Swipe left for the next month, right for the previous one.
    ///
    /// A `DragGesture` rather than a `TabView(.page)` of months (the plan
    /// allows either): the page is already a `ScrollView`, and a paging
    /// TabView inside one needs a fixed height it would have to be told,
    /// which the grid's own row count changes month to month.
    private var monthSwipe: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                if value.translation.width < -40 {
                    withAnimation(.easeOut(duration: 0.2)) { monthOffset += 1 }
                } else if value.translation.width > 40 {
                    withAnimation(.easeOut(duration: 0.2)) { monthOffset -= 1 }
                }
            }
    }

    /// The page's own read of the sessions it holds, projected onto the
    /// grid's integers. Same rules `TrainingMonthField` applies on Home, one
    /// month wide and with the crew split out: a day booked with a crew
    /// wears that crew's ring, a solo booking wears the accent.
    private var derivedWorld: CalendarWorld {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: todayStart)) ?? todayStart
        let monthStart = cal.date(byAdding: .month, value: monthOffset, to: thisMonthStart) ?? thisMonthStart
        let dayCount = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 30

        var trained: Set<Int> = []
        for session in completed {
            guard let when = session.completedAt ?? session.startedAt ?? session.scheduledFor,
                  let day = dayNumber(of: when, inMonthOf: monthStart, cal: cal) else { continue }
            trained.insert(day)
        }

        var scheduled: Set<Int> = []
        var crew: [Int: Color] = [:]
        for session in upcoming {
            guard let when = session.scheduledFor,
                  let day = dayNumber(of: when, inMonthOf: monthStart, cal: cal) else { continue }
            if let groupID = session.groupID {
                crew[day] = GSGroupColor.color(for: groupID)
            } else {
                scheduled.insert(day)
            }
        }

        // The legend describes THIS month: the first crew actually on the
        // grid, read at the lowest day number so the pick is stable (a
        // dictionary's own order is not).
        let legendCrew = crew.keys.min().flatMap { crew[$0] } ?? GSGroupColor.palette[2]

        let month = CalendarMonthGrid.Month(
            label: monthStart.formatted(.dateTime.month(.wide).year()).uppercased(),
            weekdayLabels: Self.weekdayLabels(cal),
            dayCount: dayCount,
            leadingBlanks: (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7,
            trained: trained,
            scheduled: scheduled,
            crew: crew,
            today: dayNumber(of: todayStart, inMonthOf: monthStart, cal: cal),
            selectedWeek: selectedWeekDays(todayStart: todayStart, monthStart: monthStart, cal: cal)
        )
        return CalendarWorld(month: month, legendCrewColor: legendCrew)
    }

    /// The day-of-month, but only when the date falls in `monthStart`'s
    /// month — the guard that stops August's sessions marking September's
    /// cells.
    private func dayNumber(of date: Date, inMonthOf monthStart: Date, cal: Calendar) -> Int? {
        guard cal.isDate(date, equalTo: monthStart, toGranularity: .month) else { return nil }
        return cal.component(.day, from: date)
    }

    /// The days of today's week that fall in the displayed month. Browsing
    /// to another month simply finds none, and nothing is boxed — which is
    /// correct: the agenda under the grid is always THIS week.
    private func selectedWeekDays(todayStart: Date, monthStart: Date, cal: Calendar) -> Set<Int> {
        guard let week = cal.dateInterval(of: .weekOfYear, for: todayStart) else { return [] }
        var days: Set<Int> = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: week.start),
                  day < week.end,
                  let number = dayNumber(of: day, inMonthOf: monthStart, cal: cal) else { continue }
            days.insert(number)
        }
        return days
    }

    /// `M T W T F S S`, rotated to the locale's first weekday — the same
    /// rotation `TrainingMonthField`'s leading-blank arithmetic assumes.
    private static func weekdayLabels(_ cal: Calendar) -> [String] {
        let symbols = cal.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        let first = cal.firstWeekday - 1
        return (0..<7).map { symbols[(first + $0) % 7].uppercased() }
    }

    // MARK: Refresh

    /// Best-effort, `try?` like every other screen. The catalog's world is
    /// already resolved, so a fixture render never opens a socket — which is
    /// what keeps `calendar-scheduling` hermetic and fast.
    @MainActor
    private func refresh() async {
        guard world == nil else { return }
        if let rows = try? await SessionRepository.upcoming() {
            refreshedUpcoming = rows
        }
        if let userID = appState.currentProfile?.id,
           let rows = try? await SessionRepository.history(userID: userID, limit: 60) {
            // 60 is what `HomeView` already passes for the same widget's
            // history (:1458) — the page and the card it opens read the same
            // window, so they cannot disagree about which days are filled.
            refreshedCompleted = rows
        }
    }
}

// MARK: - CalendarWorld
//
// Everything the page renders, resolved. Production builds one per layout
// pass from repositories and the clock; the catalog hands one in whole.
// Splitting the render from the resolution is what makes a hermetic frame
// possible without a second implementation of the page.

struct CalendarWorld {
    var month: CalendarMonthGrid.Month
    /// The swatch the grid's legend wears for `Crew`.
    var legendCrewColor: Color
}
