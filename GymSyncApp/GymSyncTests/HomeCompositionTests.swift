import XCTest
@testable import GymSync

// MARK: - HomeCompositionTests
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, task
// B7. Pure tests of the two helpers Home v3's composition was extracted
// into. SwiftUI bodies are not unit-testable here — the `app-tab-home`
// capture is the visual proof — so what is tested is the two things that
// CAN be wrong without a screenshot showing it: which of the one button's
// five states a given world resolves to, and how real dates flatten onto
// the calendar card's fixture-shaped values.
final class HomeCompositionTests: XCTestCase {

    // MARK: - The one button's five states

    /// `HomeOneButtonState.Face` and the state itself carry no `Equatable`
    /// conformance, so assertions go through the strings and this switch —
    /// which is also what a lifter actually sees.
    private func faceName(_ state: HomeOneButtonState) -> String {
        switch state.face {
        case .accent: return "accent"
        case .raised: return "raised"
        case .gold:   return "gold"
        }
    }

    func testNothingScheduledAndNoRoutineIsStartWorkout() {
        let state = HomeOneButtonResolver.state(next: nil, todaysRoutineName: nil)
        XCTAssertEqual(state.line1, "START A WORKOUT")
        XCTAssertEqual(state.line2, "ROUTINES · FREESTYLE · BUILD ONE")
        XCTAssertEqual(faceName(state), "accent")
        XCTAssertFalse(state.isCrewState, "a solo primary must not keep the solo pill under it")
    }

    func testTodaysRoutineIsStartRoutine() {
        let state = HomeOneButtonResolver.state(next: nil, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "START · PULL A")
        XCTAssertEqual(faceName(state), "accent")
        XCTAssertFalse(state.isCrewState)
    }

    /// An empty routine name is not a routine — it must not produce
    /// `START · ` with nothing after it.
    func testEmptyRoutineNameFallsBackToStartWorkout() {
        let state = HomeOneButtonResolver.state(next: nil, todaysRoutineName: "")
        XCTAssertEqual(state.line1, "START A WORKOUT")
    }

    func testLiveAndStartedSessionIsJoinSession() {
        let input = HomeOneButtonInput(isInProgress: true,
                                       startedAtLabel: "5:12 PM",
                                       isGroupSession: true,
                                       checkInAvailable: true,
                                       crewName: "Push Crew",
                                       routineName: "Push A",
                                       timeLabel: "5:00 PM")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "JOIN THE SESSION")
        XCTAssertEqual(state.line2, "STARTED 5:12 PM · YOU'RE LATE")
        XCTAssertEqual(faceName(state), "accent")
        XCTAssertTrue(state.isCrewState, "a crew primary keeps the solo escape under it")
    }

    /// `.joinSession` needs BOTH a live session and a start stamp — its copy
    /// reads "STARTED {time} · YOU'RE LATE", and there is no honest time to
    /// put there without one. A live session with no stamp is still a
    /// check-in.
    func testInProgressWithoutAStartStampFallsThroughToCheckIn() {
        let input = HomeOneButtonInput(isInProgress: true,
                                       startedAtLabel: nil,
                                       isGroupSession: true,
                                       checkInAvailable: true,
                                       crewName: "Push Crew",
                                       routineName: "Push A",
                                       timeLabel: "5:00 PM")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: nil)
        XCTAssertEqual(state.line1, "CHECK IN")
    }

    func testOpenWindowOnACrewSessionIsGoldCheckIn() {
        let input = HomeOneButtonInput(isGroupSession: true,
                                       checkInAvailable: true,
                                       crewName: "Push Crew",
                                       routineName: "Push A",
                                       timeLabel: "5:00 PM")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "CHECK IN")
        XCTAssertEqual(state.line2, "PUSH CREW · PUSH A · 5:00 PM · OPEN NOW")
        XCTAssertEqual(faceName(state), "gold", "gold's second job: the window is open, act now")
        XCTAssertTrue(state.isCrewState)
    }

    /// A SOLO session inside its own check-in window is not a check-in:
    /// `.checkIn`'s copy is a crew sentence and there is nobody to check in
    /// with, so the button offers the start screen instead.
    func testOpenWindowOnASoloSessionIsNotACheckIn() {
        let input = HomeOneButtonInput(isGroupSession: false,
                                       checkInAvailable: true,
                                       routineName: "Pull A")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "START · PULL A")
        XCTAssertFalse(state.isCrewState)
    }

    func testWindowNotYetOpenIsTheQuietCountdown() {
        let input = HomeOneButtonInput(isGroupSession: true,
                                       checkInAvailable: false,
                                       opensInLabel: "45m",
                                       crewName: "Push Crew",
                                       routineName: "Push A",
                                       timeLabel: "5:00 PM")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "CHECK-IN OPENS 45m")
        // `ON THE BOOKS`, not the old `YOU'RE IN`: the state's own subtitle
        // makes no claim about commitment, because the commit chip beside it
        // is the only thing on that button allowed to speak about that.
        // `testCheckInOpensSubtitleMakesNoClaimAboutCommitment` owns the
        // reasoning; this line keeps the countdown's two lines asserted
        // together.
        XCTAssertEqual(state.line2, "ON THE BOOKS")
        XCTAssertEqual(faceName(state), "raised", "the countdown is quiet — it is not an act-now signal")
        XCTAssertTrue(state.isCrewState)
    }

    /// A session with no scheduled time produces no countdown label, so it
    /// cannot sit in `.checkInOpens` forever — it falls through.
    func testSessionWithNoWindowAndNoAvailabilityFallsThrough() {
        let input = HomeOneButtonInput(isGroupSession: true,
                                       checkInAvailable: false,
                                       opensInLabel: nil,
                                       crewName: "Push Crew",
                                       routineName: "Push A")
        let state = HomeOneButtonResolver.state(next: input, todaysRoutineName: "Pull A")
        XCTAssertEqual(state.line1, "START · PULL A")
    }

    // MARK: - The button's own copy

    /// The subtitle must make NO claim about commitment: the commit chip
    /// beside it is the only thing on that button allowed to speak about it,
    /// and the old `YOU'RE IN` literal contradicted a `COMMIT ›` or
    /// `YOU'RE OUT` chip outright.
    func testCheckInOpensSubtitleMakesNoClaimAboutCommitment() {
        XCTAssertEqual(HomeOneButtonState.checkInOpens("45m").line2, "ON THE BOOKS")
    }

    /// The approved 08a/08b frames render this exact string
    /// (`HomeV2Fixtures.crewNight.primary`). Pinned so the non-empty join
    /// below can never redraw them.
    func testCheckInSubtitleIsUnchangedForTheFixtureWorld() {
        let state = HomeOneButtonState.checkIn(crew: "Push Crew", routine: "Push A", time: "5:00 PM")
        XCTAssertEqual(state.line2, "PUSH CREW · PUSH A · 5:00 PM · OPEN NOW")
    }

    /// A live crew session can carry a NULL `scheduled_for`. The subtitle
    /// must close the gap rather than render
    /// `PUSH CREW · PUSH A ·  · OPEN NOW`.
    func testCheckInSubtitleDropsAnEmptyComponent() {
        let noTime = HomeOneButtonState.checkIn(crew: "Push Crew", routine: "Push A", time: "")
        XCTAssertEqual(noTime.line2, "PUSH CREW · PUSH A · OPEN NOW")
        let blank = HomeOneButtonState.checkIn(crew: "Push Crew", routine: "Push A", time: "   ")
        XCTAssertEqual(blank.line2, "PUSH CREW · PUSH A · OPEN NOW")
    }

    // MARK: - The calendar card's mapping

    /// Pinned so the assertions below are arithmetic, not a coin flip on the
    /// day CI runs. Gregorian, UTC, `firstWeekday` 1 (Sunday).
    ///
    /// September 2026 starts on a Tuesday (Foundation weekday 3) and has 30
    /// days; August starts on a Saturday (7) with 31; October on a Thursday
    /// (5) with 31.
    private var pinnedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        calendar.firstWeekday = 1
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                      hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return pinnedCalendar.date(from: components) ?? .distantPast
    }

    private func session(id: UUID = UUID(),
                         state: String = "scheduled",
                         scheduledFor: Date? = nil,
                         completedAt: Date? = nil,
                         startedAt: Date? = nil,
                         groupID: UUID? = nil,
                         seriesID: UUID? = nil,
                         routineID: UUID? = nil) -> WorkoutSession {
        WorkoutSession(id: id,
                       routineID: routineID,
                       organizerID: UUID(),
                       state: state,
                       startedAt: startedAt,
                       completedAt: completedAt,
                       createdAt: date(2026, 9, 1),
                       groupID: groupID,
                       roomCode: nil,
                       scheduledFor: scheduledFor,
                       seriesID: seriesID,
                       currentTurnUserID: nil,
                       currentTurnStartedAt: nil)
    }

    private func group(_ name: String) -> GymGroup {
        GymGroup(id: UUID(),
                 name: name,
                 avatarURL: nil,
                 createdBy: UUID(),
                 createdAt: date(2026, 1, 1))
    }

    func testMonthsArePreviousCurrentNext() {
        let months = HomeCalendarCardModel.months(completed: [],
                                                  upcoming: [],
                                                  now: date(2026, 9, 15),
                                                  calendar: pinnedCalendar)
        XCTAssertEqual(months.count, 3)
        // The label is `Date.formatted`, which follows `Locale.current`, so
        // only its SHAPE is asserted unconditionally — caps, and three
        // distinct months. The exact strings are checked where they are
        // knowable, which is an English simulator.
        XCTAssertEqual(months.map(\.label), months.map { $0.label.uppercased() },
                       "month labels are caps, like every other kicker on the card")
        XCTAssertEqual(Set(months.map(\.label)).count, 3)
        if Locale.current.language.languageCode?.identifier == "en" {
            XCTAssertEqual(months.map(\.label), ["AUG", "SEP", "OCT"])
        }
        XCTAssertEqual(months.map(\.dayCount), [31, 30, 31])
        // (weekday of day 1) - firstWeekday, wrapped: Sat 7 -> 6, Tue 3 -> 2,
        // Thu 5 -> 4.
        XCTAssertEqual(months.map(\.leadingBlanks), [6, 2, 4])
    }

    func testOnlyTheCurrentMonthCarriesTodayAndItIsTheRightDay() {
        let months = HomeCalendarCardModel.months(completed: [],
                                                  upcoming: [],
                                                  now: date(2026, 9, 15),
                                                  calendar: pinnedCalendar)
        XCTAssertNil(months[0].today)
        XCTAssertEqual(months[1].today, 15)
        XCTAssertNil(months[2].today)
    }

    /// Position decides whether an untrained day reads as past or future, so
    /// getting it wrong dims the wrong half of the field.
    func testPositionsRunPastCurrentFuture() {
        let months = HomeCalendarCardModel.months(completed: [],
                                                  upcoming: [],
                                                  now: date(2026, 9, 15),
                                                  calendar: pinnedCalendar)
        let names = months.map { month -> String in
            switch month.position {
            case .past:    return "past"
            case .current: return "current"
            case .future:  return "future"
            }
        }
        XCTAssertEqual(names, ["past", "current", "future"])
    }

    func testTrainedAndPlannedDaysLandOnTheirOwnMonths() {
        let completed = [
            session(state: "completed", completedAt: date(2026, 9, 3)),
            session(state: "completed", completedAt: date(2026, 8, 28)),
        ]
        let upcoming = [
            session(scheduledFor: date(2026, 9, 18)),
            session(scheduledFor: date(2026, 10, 2)),
        ]
        let months = HomeCalendarCardModel.months(completed: completed,
                                                  upcoming: upcoming,
                                                  now: date(2026, 9, 15),
                                                  calendar: pinnedCalendar)
        XCTAssertEqual(months[0].trained, [28])
        XCTAssertEqual(months[1].trained, [3])
        XCTAssertEqual(months[2].trained, [])
        XCTAssertEqual(months[1].planned, [18])
        XCTAssertEqual(months[2].planned, [2])
    }

    /// The production dot field dated a trained day by `completedAt`, else
    /// `startedAt`, else `scheduledFor`. A session that was started and
    /// abandoned still marks its day.
    func testTrainedDayFallsBackThroughStartedThenScheduled() {
        let completed = [
            session(state: "in_progress", startedAt: date(2026, 9, 5)),
            session(state: "scheduled", scheduledFor: date(2026, 9, 7)),
        ]
        let months = HomeCalendarCardModel.months(completed: completed,
                                                  upcoming: [],
                                                  now: date(2026, 9, 15),
                                                  calendar: pinnedCalendar)
        XCTAssertEqual(months[1].trained, [5, 7])
    }

    /// EVERY upcoming session, not a prefix: the card's `{n} UPCOMING` pill
    /// counts this array, and it has to be the number the old widget showed.
    func testAppointmentsCountEveryUpcomingSession() {
        let upcoming = (1...5).map { session(scheduledFor: date(2026, 9, 15 + $0)) }
        let rows = HomeCalendarCardModel.appointments(upcoming: upcoming,
                                                      groups: [],
                                                      title: { _ in "Workout" },
                                                      now: date(2026, 9, 15),
                                                      calendar: pinnedCalendar)
        XCTAssertEqual(rows.count, 5)
        XCTAssertEqual(rows.map(\.id), [0, 1, 2, 3, 4])
    }

    func testCrewAppointmentCarriesItsCrewsIdentity() {
        let crew = group("Push Crew")
        let rows = HomeCalendarCardModel.appointments(
            upcoming: [session(scheduledFor: date(2026, 9, 19, hour: 17),
                               groupID: crew.id,
                               seriesID: UUID())],
            groups: [crew],
            title: { _ in "Push A" },
            now: date(2026, 9, 15),
            calendar: pinnedCalendar)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows.first?.initials, "PC")
        XCTAssertEqual(rows.first?.subtitle, "Push Crew")
        XCTAssertEqual(rows.first?.title, "Push A")
        XCTAssertEqual(rows.first?.repeats, true)
        XCTAssertNotNil(rows.first?.tint)
        XCTAssertNotNil(rows.first?.ink)
        XCTAssertNil(rows.first?.status, "Home knows one session's commitment, not every session's")
    }

    func testSoloAppointmentWearsYouAndNoTint() {
        let rows = HomeCalendarCardModel.appointments(
            upcoming: [session(scheduledFor: date(2026, 9, 19, hour: 17))],
            groups: [],
            title: { _ in "Pull A" },
            now: date(2026, 9, 15),
            calendar: pinnedCalendar)
        XCTAssertEqual(rows.first?.initials, "You")
        XCTAssertEqual(rows.first?.subtitle, "Solo")
        XCTAssertNil(rows.first?.tint, "nil tint = the card resolves the accent at render")
        XCTAssertNil(rows.first?.ink)
        XCTAssertEqual(rows.first?.repeats, false)
    }

    func testTodaysAppointmentSaysToday() {
        let rows = HomeCalendarCardModel.appointments(
            upcoming: [session(scheduledFor: date(2026, 9, 15, hour: 18))],
            groups: [],
            title: { _ in "Pull A" },
            now: date(2026, 9, 15, hour: 9),
            calendar: pinnedCalendar)
        XCTAssertEqual(rows.first?.day, "Today")
    }

    /// A session with no scheduled time must not render a blank time column
    /// or claim a weekday it does not have.
    func testUnscheduledAppointmentIsHonestAboutHavingNoTime() {
        let rows = HomeCalendarCardModel.appointments(
            upcoming: [session(state: "lobby_open", scheduledFor: nil)],
            groups: [],
            title: { _ in "Workout" },
            now: date(2026, 9, 15),
            calendar: pinnedCalendar)
        XCTAssertEqual(rows.first?.time, "No time set")
        XCTAssertEqual(rows.first?.day, "Lobby Open")
    }

    func testInitialsTakeTwoWordsAtMost() {
        XCTAssertEqual(HomeCalendarCardModel.initials(of: "Push Crew"), "PC")
        XCTAssertEqual(HomeCalendarCardModel.initials(of: "The Iron Church"), "TI")
        XCTAssertEqual(HomeCalendarCardModel.initials(of: "Solo"), "S")
        XCTAssertEqual(HomeCalendarCardModel.initials(of: ""), "")
    }

    // MARK: - The week both the streak tile and the goal strip count

    /// The agreement law's arithmetic half: two sessions on one day fill one
    /// slot, and a session in another week does not count at all.
    func testDaysThisWeekCountsDistinctDaysInsideTheWeek() {
        let now = date(2026, 9, 16)          // Wednesday
        let sessions = [
            session(state: "completed", completedAt: date(2026, 9, 14, hour: 7)),
            session(state: "completed", completedAt: date(2026, 9, 14, hour: 19)),
            session(state: "completed", completedAt: date(2026, 9, 16, hour: 7)),
            session(state: "completed", completedAt: date(2026, 9, 7)),   // last week
            session(state: "scheduled", scheduledFor: date(2026, 9, 15)), // not completed
        ]
        XCTAssertEqual(WeeklyGoalProgressMath.daysThisWeek(completed: sessions,
                                                          now: now,
                                                          calendar: pinnedCalendar),
                       2)
    }
}
