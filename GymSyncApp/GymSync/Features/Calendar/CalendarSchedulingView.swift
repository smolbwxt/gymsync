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
    /// Months away from `today`'s month — which month the GRID shows.
    @State private var monthOffset = 0
    /// Start-of-week for the week the page is TALKING about: the agenda, the
    /// boxed days on the grid, the block row's `week n of m`.
    ///
    /// `nil` means "the current week", which is the state on first appear —
    /// stored as an absence rather than written in an `onAppear` so the page
    /// has one correct answer from its very first layout pass. Tapping a day
    /// selects that day's week; swiping to another month selects that
    /// month's first week, and swiping back to the current month returns
    /// here.
    @State private var selectedWeekStart: Date?
    /// Background re-fetches. `nil` until one lands, so the page paints from
    /// the caller's arrays first and never blanks while it re-reads.
    @State private var refreshedUpcoming: [WorkoutSession]?
    @State private var refreshedCompleted: [WorkoutSession]?
    /// Your own routines, for the agenda's titles — the same list and the
    /// same `"Workout"` fallback `HomeView.routineLabel(for:)` uses (:1599).
    @State private var routinesByID: [UUID: Routine] = [:]
    /// Your answer on each of this week's crew sessions, so a row says `IN`
    /// or `COMMIT` because it was READ, never because it was assumed.
    @State private var commitmentBySession: [UUID: SessionCommitment.Status] = [:]
    /// The tapped row — pushes the lobby. Keyed by id rather than by the
    /// session, because `navigationDestination(item:)` wants a `Hashable`
    /// and `WorkoutSession` is not one.
    @State private var lobbySessionID: UUID?
    /// The row being MOVED — opens the shared change-time sheet.
    @State private var moveTarget: WorkoutSession?
    /// The new time being picked in that sheet.
    @State private var moveDate: Date = .now
    /// A failed reschedule. Surfaced, never swallowed: MOVE is the one act
    /// on this page that writes to a session other people are standing in.
    @State private var errorText: String?
    /// The active block, for the `Coach block · week n of m` row.
    @State private var activeEnrollment: ProgramEnrollment?
    /// One row per JOINED active campaign. Built in `refresh()` rather than
    /// derived, because the percentage needs an await.
    @State private var campaignRows: [CalendarCampaignRow] = []

    private var completed: [WorkoutSession] { refreshedCompleted ?? completedSessions }
    private var upcoming: [WorkoutSession] { refreshedUpcoming ?? upcomingSessions }

    /// What the page draws: the injected world, or the one derived from the
    /// sessions in hand. One render path, two sources.
    private var resolved: CalendarWorld { world ?? derivedWorld }

    var body: some View {
        // Resolved ONCE per layout pass. `resolved` recomputes
        // `derivedWorld` on every read, and that walks up to 60 completed
        // and 200 upcoming sessions twice, re-filters and re-sorts the week,
        // and calls `Date.formatted` twice per agenda row plus once for the
        // month label and once per campaign. Read seven times from `body`,
        // as it was, that is scroll jank rather than a theoretical cost.
        let painted = resolved
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // The `{Month} {Year}` SUBTITLE the proof draws under the
                // title — not a kicker. It sits directly beneath the large
                // `Calendar` the nav bar renders, which is why the nav title
                // is `.large` here and the type is sentence-case body rather
                // than tracked all-caps.
                Text(painted.month.label)
                    .font(GSFont.body(15, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .accessibilityAddTraits(.isHeader)

                CalendarMonthGrid(month: painted.month,
                                  legendCrewColor: painted.legendCrewColor,
                                  onSelectDay: daySelection)
                    // SIMULTANEOUS, not exclusive: this sits inside a
                    // vertical `ScrollView`, and a plain `.gesture` here can
                    // swallow the drag that should have scrolled the page —
                    // including the swipe the second catalog capture needs.
                    // `monthSwipe` acts only on a mostly-horizontal drag, so
                    // sharing costs nothing.
                    .simultaneousGesture(monthSwipe)

                agendaCard(painted)

                if let block = painted.block {
                    CalendarBlockRowView(row: block)
                }
                ForEach(painted.campaigns) { campaign in
                    CalendarCampaignRowView(row: campaign)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        // The one primary is PINNED, not appended. On a page whose grid and
        // agenda already fill a screen it would otherwise sit below the fold
        // — unreachable without a scroll, and absent from the capture that
        // is supposed to prove it exists (plan constraint 7).
        .safeAreaInset(edge: .bottom) {
            scheduleButton
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 8)
                .background(theme.bg)
        }
        .navigationTitle("Calendar")
        // `.large`, so the page opens under the big left-aligned `Calendar`
        // the v7 proof draws, with the month line as its subtitle. It
        // collapses to inline on scroll and keeps the trailing `+` in both
        // states. The scaffold's `.inline` was the narrower reading; the
        // proof and plan D2 item 1 both want the header block.
        .navigationBarTitleDisplayMode(.large)
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
        .sheet(item: $moveTarget) { session in
            // MOVE is a real move: the shared `SessionTimeSheet` over
            // `SessionRepository.reschedule`, one `UPDATE sessions SET
            // scheduled_for` on the SAME row.
            //
            // It used to book a replacement through `ScheduleSessionView`
            // and delete the original. That is a destroy-and-recreate, and
            // on a crew session it wipes exactly what this page renders:
            // every `session_commitments` row (the `IN` / `COMMIT` pill),
            // every participant's check-in state, the proposals and votes,
            // the chat thread, the room code, and the `series_id` that makes
            // a `↻` row a `↻` row. It also re-homes `organizer_id` onto
            // whoever swiped. Deleted, not softened.
            SessionTimeSheet(
                date: $moveDate,
                onCancel: { moveTarget = nil },
                onSave: { Task { await applyMove(session) } }
            )
        }
        .alert("Couldn't move that session",
               isPresented: Binding(get: { errorText != nil },
                                    set: { if !$0 { errorText = nil } })) {
            Button("OK", role: .cancel) { errorText = nil }
        } message: {
            Text(errorText ?? "")
        }
        .navigationDestination(item: $lobbySessionID) { id in
            if let session = upcoming.first(where: { $0.id == id }) {
                // `.id` — session-identity pin, the rule every lobby push in
                // this app follows (`HomeView.navigateToJoined`'s destination
                // comment has the field-bug story).
                LobbyView(session: session)
                    .id(session.id)
            }
        }
        .task { await refresh() }
        .refreshable { await refresh() }
        // The pills belong to the week on screen, so they are re-read when
        // the selection moves — a bounded handful of crew sessions, the same
        // call `refresh()` makes.
        .onChange(of: effectiveWeekStart) {
            Task { await loadCommitments() }
        }
    }

    // MARK: This week

    /// The agenda: `THIS WEEK`, the swipe hint, and one row per thing on the
    /// week's timeline. ONE raised card with flat furniture inside it
    /// (design language rule 1) — the rows are full-bleed inside it so a
    /// swipe can carry a row all the way to the card's edge.
    private func agendaCard(_ painted: CalendarWorld) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                GSSectionHeader(painted.weekTitle)
                Text("SWIPE A ROW TO MOVE OR CANCEL")
                    .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
                    .multilineTextAlignment(.trailing)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if painted.agenda.isEmpty {
                Text("Nothing on the books this week.")
                    .font(GSFont.body(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(Array(painted.agenda.enumerated()), id: \.element.id) { index, item in
                    // BETWEEN rows only. The proof draws no hairline under
                    // the section header, and one there reads as a rule
                    // under a title rather than as a list separator.
                    if index > 0 {
                        Rectangle().fill(theme.divider).frame(height: 1)
                    }
                    agendaRow(item)
                    if index == painted.agenda.count - 1 {
                        Color.clear.frame(height: 4)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    /// One agenda row, with its edit paths attached when there is a live
    /// session behind it. A fixture row has none, so the swipe is not
    /// installed and the tap goes nowhere — a catalog frame must not be able
    /// to open a lobby or delete anything.
    private func agendaRow(_ item: CalendarAgendaItem) -> some View {
        CalendarSwipeRow(onMove: moveAction(for: item),
                         onCancel: cancelAction(for: item)) {
            Button {
                if let session = item.session { lobbySessionID = session.id }
            } label: {
                CalendarAgendaRowView(item: item)
            }
            .buttonStyle(.plain)
            .disabled(item.session == nil)
        }
    }

    /// MOVE is offered exactly where the lobby offers Manage → *Change
    /// time*: `isOrganizer && (state == "scheduled" || state ==
    /// "lobby_open")` — `LobbyView.isManageVisible` (:93-96), mirrored, not
    /// approximated. `reschedule` is organizer-only by DB policy, and a
    /// PostgREST `UPDATE` that RLS filters to zero rows returns SUCCESS, so
    /// offering MOVE to a participant would be an affordance that silently
    /// does nothing.
    private func canMove(_ session: WorkoutSession) -> Bool {
        session.organizerID == selfID
            && (session.state == "scheduled" || session.state == "lobby_open")
    }

    private var selfID: UUID? { appState.currentProfile?.id }

    private func moveAction(for item: CalendarAgendaItem) -> (() -> Void)? {
        guard let session = item.session, canMove(session) else { return nil }
        return {
            moveDate = session.scheduledFor ?? Date()
            moveTarget = session
        }
    }

    /// Reschedule the row in place, then re-read the week.
    ///
    /// No `try?`. A failed move is surfaced the way the lobby surfaces its
    /// own (`LobbyView.applyReschedule`, :1688-1712): the `GymSyncError`'s
    /// description, in front of the user. The EventKit sync mirrors that
    /// method too — gated on the same You-tab toggle, run AFTER the refresh
    /// so it reads the server-confirmed `scheduledFor` rather than a
    /// hand-built snapshot, and `syncEvent` updates the mapped event in
    /// place rather than creating a second one.
    @MainActor
    private func applyMove(_ session: WorkoutSession) async {
        let newDate = moveDate
        moveTarget = nil
        do {
            try await SessionRepository.reschedule(sessionID: session.id, to: newDate)
            await refresh()
            if CalendarSyncPrefsStore.isEnabled(),
               let moved = upcoming.first(where: { $0.id == session.id }) {
                await EventKitBridge.syncEvent(
                    session: moved,
                    routineName: moved.routineID.flatMap { routinesByID[$0] }?.name,
                    exerciseCount: nil
                )
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    /// CANCEL is gated on the same rule as MOVE, and for the same reason:
    /// the lobby offers *Cancel session* under exactly that condition
    /// (`LobbyView.manageMenu` behind `isManageVisible`), and both delete
    /// paths are owner-scoped by RLS — a participant's DELETE filters to
    /// zero rows and returns success, so the row would appear to vanish and
    /// come straight back on the next refresh.
    private func cancelAction(for item: CalendarAgendaItem) -> (() -> Void)? {
        guard let session = item.session, canMove(session) else { return nil }
        return {
            Task {
                await retire(session)
                await refresh()
            }
        }
    }

    /// Take a session off the books — the branch `WeekBooker.book` already
    /// makes (`Models/WeekBooker.swift:48-59`): an occurrence that belongs to
    /// a series is cancelled THROUGH the series so the series stays
    /// consistent; a plain session is deleted. No new repository method.
    ///
    /// CANCEL only. MOVE no longer passes through here — it reschedules the
    /// row in place and nothing is destroyed.
    private func retire(_ session: WorkoutSession) async {
        if session.seriesID != nil {
            try? await SeriesRepository.cancelOccurrence(sessionID: session.id)
        } else {
            try? await SessionRepository.deleteSession(id: session.id)
        }
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

    // MARK: Months and the selected week

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
                    changeMonth(by: 1)
                } else if value.translation.width > 40 {
                    changeMonth(by: -1)
                }
            }
    }

    /// Changing month changes the SELECTION too. A grid showing October over
    /// an agenda headed `THIS WEEK` and listing September is the page
    /// contradicting itself; worse, it offers a month it will not talk
    /// about, on the page design §C names as the home of "anything on a
    /// timeline is editable from here".
    private func changeMonth(by delta: Int) {
        let cal = Calendar.current
        let target = monthOffset + delta
        withAnimation(.easeOut(duration: 0.2)) {
            monthOffset = target
            // Back at the current month → back to the current week, not to
            // the 1st. That is where you were when you left.
            selectedWeekStart = target == 0
                ? nil
                : weekStart(containing: monthStart(offset: target, cal: cal), cal: cal)
        }
    }

    /// `nil` for the catalog, whose world is fixed and whose cells must not
    /// be pressable. Written out rather than inlined as a ternary against
    /// `nil`, which gives a closure literal nothing to infer from.
    private var daySelection: ((Int) -> Void)? {
        guard world == nil else { return nil }
        return { day in selectWeek(ofDay: day) }
    }

    /// Tapping a day selects its week — the selection mechanism design §C's
    /// "the SELECTED week's agenda below" implies and the grid's boxed row
    /// makes visible.
    private func selectWeek(ofDay day: Int) {
        let cal = Calendar.current
        let month = monthStart(offset: monthOffset, cal: cal)
        guard let date = cal.date(byAdding: .day, value: day - 1, to: month) else { return }
        withAnimation(.easeOut(duration: 0.15)) {
            let start = weekStart(containing: date, cal: cal)
            // Selecting a day in the current week clears back to nil rather
            // than pinning an equal date, so "am I on this week?" stays one
            // question with one answer.
            selectedWeekStart = start == currentWeekStart ? nil : start
        }
    }

    /// The week the page is about — the selection, or the current week.
    private var effectiveWeekStart: Date {
        selectedWeekStart ?? currentWeekStart
    }

    private var currentWeekStart: Date {
        let cal = Calendar.current
        return weekStart(containing: cal.startOfDay(for: today), cal: cal)
    }

    private func weekStart(containing date: Date, cal: Calendar) -> Date {
        cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }

    private func monthStart(offset: Int, cal: Calendar) -> Date {
        let todayStart = cal.startOfDay(for: today)
        let thisMonthStart = cal.date(from: cal.dateComponents([.year, .month], from: todayStart)) ?? todayStart
        return cal.date(byAdding: .month, value: offset, to: thisMonthStart) ?? thisMonthStart
    }

    /// The page's own read of the sessions it holds, projected onto the
    /// grid's integers. Same rules `TrainingMonthField` applies on Home, one
    /// month wide and with the crew split out: a day booked with a crew
    /// wears that crew's ring, a solo booking wears the accent.
    private var derivedWorld: CalendarWorld {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: today)
        let monthStart = monthStart(offset: monthOffset, cal: cal)
        let weekStart = effectiveWeekStart
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
            label: monthStart.formatted(.dateTime.month(.wide).year()),
            weekdayLabels: CalendarMonthMath.weekdayLabels(cal),
            dayCount: dayCount,
            leadingBlanks: CalendarMonthMath.leadingBlanks(monthStart: monthStart, cal: cal),
            trained: trained,
            scheduled: scheduled,
            crew: crew,
            today: dayNumber(of: todayStart, inMonthOf: monthStart, cal: cal),
            selectedWeek: selectedWeekDays(weekStart: weekStart, monthStart: monthStart, cal: cal)
        )
        return CalendarWorld(month: month,
                             legendCrewColor: legendCrew,
                             weekTitle: weekStart == currentWeekStart
                                 ? "This week"
                                 : "Week of \(weekStart.formatted(.dateTime.month(.abbreviated).day()))",
                             agenda: agendaItems(weekStart: weekStart, cal: cal),
                             block: blockRow(weekStart: weekStart, cal: cal),
                             campaigns: campaignRows)
    }

    // MARK: The block

    /// `Coach block · week 2 of 6 · Tue, Thu, Sat`, or nothing at all when
    /// there is no active enrollment (design §C: absent, not empty).
    ///
    /// `n` of `m` from the enrollment's own start date and its template's
    /// week count, through `ProgramMath.currentWeek` — the same call
    /// `ProgramScheduleView.load()` makes (:592-594), so the page and the
    /// program screen can never disagree about which week you are in.
    private func blockRow(weekStart: Date, cal: Calendar) -> CalendarBlockRow? {
        guard let enrollment = activeEnrollment,
              let weeks = enrollment.template?.weeks, !weeks.isEmpty else { return nil }
        // `now:` is the SELECTED week's start, not today's: browse to a week
        // three weeks out and the row says which block week that is, which is
        // the only reading that makes the row worth having on a page you can
        // navigate.
        let week = ProgramMath.currentWeek(startedOn: enrollment.startedOn,
                                           weeks: weeks.count,
                                           now: weekStart)
        var parts = ["Coach block", "week \(week) of \(weeks.count)"]
        let days = blockWeekdays(weekStart: weekStart, cal: cal)
        if !days.isEmpty { parts.append(days.joined(separator: ", ")) }
        return CalendarBlockRow(text: parts.joined(separator: " · "),
                                enrollment: enrollment,
                                weeks: weeks)
    }

    /// The block's training days, READ from the sessions it actually booked
    /// this week rather than assumed — the rule `BlockCalendarView`'s own
    /// header states ("the app does not guess which weekdays you train").
    /// `WeekBooker` books a block's days as solo sessions against the
    /// `Coach · …` routines (WeekBooker.swift:41-44), which is the signal.
    private func blockWeekdays(weekStart: Date, cal: Calendar) -> [String] {
        guard let week = cal.dateInterval(of: .weekOfYear, for: weekStart) else { return [] }
        var byColumn: [Int: String] = [:]
        for session in upcoming {
            guard session.groupID == nil,
                  let when = session.scheduledFor, when >= week.start, when < week.end,
                  let name = session.routineID.flatMap({ routinesByID[$0] })?.name,
                  name.hasPrefix("Coach · ") else { continue }
            let column = (cal.component(.weekday, from: when) - cal.firstWeekday + 7) % 7
            byColumn[column] = when.formatted(.dateTime.weekday(.abbreviated))
        }
        return byColumn.keys.sorted().compactMap { byColumn[$0] }
    }

    // MARK: The week's agenda
    //
    // Scheduled sessions only — history is not editable from here, and this
    // list's whole promise (design rule 4) is that everything on it opens
    // where it can be changed.

    private func agendaItems(weekStart: Date, cal: Calendar) -> [CalendarAgendaItem] {
        guard let week = cal.dateInterval(of: .weekOfYear, for: weekStart) else { return [] }
        let inWeek: [(session: WorkoutSession, when: Date)] = upcoming.compactMap { session in
            guard let when = session.scheduledFor, when >= week.start, when < week.end else { return nil }
            return (session, when)
        }
        return inWeek
            .sorted { $0.when < $1.when }
            .map { agendaItem(session: $0.session, when: $0.when, cal: cal) }
    }

    private func agendaItem(session: WorkoutSession, when: Date, cal: Calendar) -> CalendarAgendaItem {
        let routine = session.routineID.flatMap { routinesByID[$0] }
        let group = session.groupID.flatMap { id in groups.first { $0.id == id } }
        let repeats = session.seriesID != nil

        // The subtitle says only what was read. `from your block` is not a
        // guess: `WeekBooker` books a block's days against the routines named
        // `Coach · …` (`Models/WeekBooker.swift:41-44`,
        // `ProgramScheduleView.load()`), so that prefix IS the signal, and a
        // solo session without it simply reads `Solo`.
        var details: [String] = [group?.name ?? "Solo"]
        if repeats {
            details.append("repeats weekly")
        } else if group == nil, let name = routine?.name, name.hasPrefix("Coach · ") {
            details.append("from your block")
        }

        // Ternary by design (`SessionCommitment`'s own header): no row means
        // you have not said, which is the COMMIT state; an explicit OUT is
        // not a pill, because there is nothing to show up to.
        var status: CalendarAgendaItem.Status?
        if group != nil {
            let mine = commitmentBySession[session.id]
            if mine == .committed {
                status = .checkedIn
                details.append("you're in")
            } else if mine == .out {
                status = nil
            } else {
                status = .commit
            }
        }

        return CalendarAgendaItem(
            id: session.id,
            dayNumber: cal.component(.day, from: when),
            weekday: when.formatted(.dateTime.weekday(.abbreviated)).uppercased(),
            title: "\(routine?.name ?? "Workout") · \(when.formatted(date: .omitted, time: .shortened))",
            repeats: repeats,
            subtitle: details.joined(separator: " · "),
            status: status,
            session: session
        )
    }

    /// The day-of-month, but only when the date falls in `monthStart`'s
    /// month — the guard that stops August's sessions marking September's
    /// cells.
    private func dayNumber(of date: Date, inMonthOf monthStart: Date, cal: Calendar) -> Int? {
        guard cal.isDate(date, equalTo: monthStart, toGranularity: .month) else { return nil }
        return cal.component(.day, from: date)
    }

    /// The selected week's days that fall in the displayed month. A week
    /// that straddles a month boundary boxes only the half on screen, which
    /// is honest: the other half is a swipe away, and selecting a day there
    /// keeps the same week.
    private func selectedWeekDays(weekStart: Date, monthStart: Date, cal: Calendar) -> Set<Int> {
        guard let week = cal.dateInterval(of: .weekOfYear, for: weekStart) else { return [] }
        var days: Set<Int> = []
        for offset in 0..<7 {
            guard let day = cal.date(byAdding: .day, value: offset, to: week.start),
                  day < week.end,
                  let number = dayNumber(of: day, inMonthOf: monthStart, cal: cal) else { continue }
            days.insert(number)
        }
        return days
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
        if let userID = appState.currentProfile?.id {
            // 60 is what `HomeView` already passes for the same widget's
            // history (:1458) — the page and the card it opens read the same
            // window, so they cannot disagree about which days are filled.
            if let rows = try? await SessionRepository.history(userID: userID, limit: 60) {
                refreshedCompleted = rows
            }
            if let routines = try? await RoutineRepository.fetchAll(ownerID: userID) {
                routinesByID = Dictionary(routines.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            }
        }
        await loadCommitments()
        activeEnrollment = try? await ProgramRepository.active()
        await loadCampaigns()
    }

    /// One row per JOINED active campaign — the same two calls
    /// `HomeView.fetchActiveCampaigns` (:1488) and `loadCampaignJoinState`
    /// (:1501) already make, and the same bound on them (the campaign
    /// design's own scale note: one or two active campaigns at a time).
    /// Unjoined discovery stays on Home's carousel.
    @MainActor
    private func loadCampaigns() async {
        guard let result = try? await CampaignRepository.activeAndUpcoming() else { return }
        let active = result.active
        guard !active.isEmpty else {
            campaignRows = []
            return
        }
        let joined = (try? await CampaignRepository.myParticipations(campaignIDs: active.map(\.id))) ?? []
        var rows: [CalendarCampaignRow] = []
        for campaign in active where joined.contains(campaign.id) {
            let progress = try? await CampaignRepository.myProgress(campaignID: campaign.id)
            var parts = ["\(campaign.name) campaign",
                         "ends \(campaign.endsAt.formatted(.dateTime.month(.abbreviated).day()))"]
            // Silent when the campaign has no recognized individual target —
            // `fractionComplete` returns nil there, which is distinct from 0
            // and must not be printed as "you're at 0%".
            if let fraction = CampaignProgressMath.fractionComplete(progress: progress,
                                                                    target: campaign.individualTarget) {
                parts.append("you're at \(Int((fraction * 100).rounded()))%")
            }
            rows.append(CalendarCampaignRow(id: campaign.id,
                                            text: parts.joined(separator: " · "),
                                            campaign: campaign))
        }
        campaignRows = rows
    }

    /// Your answer on each of THIS WEEK's crew sessions.
    ///
    /// Sequential per-session awaits rather than a `TaskGroup`, and only for
    /// the sessions actually on screen: a week holds a handful of crew
    /// sessions, which bounds this to a couple of round trips — the same
    /// call `HomeView` already makes for the one session it shows
    /// (`CommitmentRepository.commitments(sessionID:)`, HomeView:1361), and
    /// the same reasoning `loadCampaignJoinState` (:1501) writes down.
    @MainActor
    private func loadCommitments() async {
        guard world == nil, let userID = selfID else { return }
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: effectiveWeekStart) else { return }
        var found: [UUID: SessionCommitment.Status] = [:]
        for session in upcoming {
            guard session.groupID != nil,
                  let when = session.scheduledFor, when >= week.start, when < week.end,
                  let rows = try? await CommitmentRepository.commitments(sessionID: session.id) else { continue }
            if let mine = rows.first(where: { $0.userID == userID }) {
                found[session.id] = mine.status
            }
        }
        commitmentBySession = found
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
    /// The agenda's section header — `This week`, or `Week of Sep 21` once
    /// the selection has moved off it. The page must never head another
    /// week's list with `THIS WEEK`.
    var weekTitle: String = "This week"
    /// The selected week's timeline, in time order.
    var agenda: [CalendarAgendaItem] = []
    /// The active block's row, absent when there is no active enrollment.
    var block: CalendarBlockRow? = nil
    /// One row per joined active campaign.
    var campaigns: [CalendarCampaignRow] = []
}
