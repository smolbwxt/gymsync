import XCTest
@testable import GymSync

// Pure-function coverage for `StatMath` — no network/auth dependency.
// Shared with Task 6 (which appends its own cases below this file's tests).
final class StatDerivationTests: XCTestCase {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int,
                       _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.hour = hour; components.minute = minute; components.second = second
        return utc.date(from: components)!
    }

    private func makeSession(completedAt: Date?, routineID: UUID? = nil) -> WorkoutSession {
        WorkoutSession(
            id: UUID(),
            routineID: routineID,
            organizerID: UUID(),
            state: "completed",
            startedAt: completedAt,
            completedAt: completedAt,
            createdAt: completedAt ?? .now,
            groupID: nil,
            roomCode: nil,
            scheduledFor: nil,
            seriesID: nil,
            currentTurnUserID: nil,
            currentTurnStartedAt: nil
        )
    }

    // MARK: - Week boundary edges
    // 2024-01-01 is a known Monday; "now" is pinned to Wednesday of that week
    // (2024-01-03) so the Monday-start/Sunday-end boundaries are fixed and
    // independent of the function under test.

    func testIsInCurrentWeek_mondayStartIsIncluded() {
        let now = date(2024, 1, 3, 12)
        let mondayStart = date(2024, 1, 1, 0, 0, 0)
        XCTAssertTrue(StatMath.isInCurrentWeek(mondayStart, now: now, calendar: utc))
    }

    func testIsInCurrentWeek_sundayEndOfWeekIsIncluded() {
        let now = date(2024, 1, 3, 12)
        let sundayEndOfWeek = date(2024, 1, 7, 23, 59, 59)
        XCTAssertTrue(StatMath.isInCurrentWeek(sundayEndOfWeek, now: now, calendar: utc))
    }

    func testIsInCurrentWeek_priorSundayIsExcluded() {
        let now = date(2024, 1, 3, 12)
        let priorSunday = date(2023, 12, 31, 23, 59, 59)
        XCTAssertFalse(StatMath.isInCurrentWeek(priorSunday, now: now, calendar: utc))
    }

    func testIsInCurrentWeek_nextMondayIsExcluded() {
        let now = date(2024, 1, 3, 12)
        let nextMonday = date(2024, 1, 8, 0, 0, 0)
        XCTAssertFalse(StatMath.isInCurrentWeek(nextMonday, now: now, calendar: utc))
    }

    func testWorkoutsThisWeek_countsOnlyCurrentWeekCompletions() {
        let now = date(2024, 1, 3, 12)
        let sessions = [
            makeSession(completedAt: date(2024, 1, 1, 0, 0, 0)),   // in week (Monday start)
            makeSession(completedAt: date(2024, 1, 7, 23, 59, 59)), // in week (Sunday end)
            makeSession(completedAt: date(2023, 12, 31, 23, 59, 59)), // prior week
            makeSession(completedAt: date(2024, 1, 8, 0, 0, 0)),   // next week
            makeSession(completedAt: nil)                          // not yet completed
        ]
        XCTAssertEqual(StatMath.workoutsThisWeek(sessions: sessions, now: now, calendar: utc), 2)
    }

    // MARK: - Compact number formatting (cases from the brief, verbatim)

    func testCompactNumber_belowThousandIsUnformatted() {
        XCTAssertEqual(StatMath.compactNumber(999), "999")
    }

    func testCompactNumber_thousandsFormatAsK() {
        XCTAssertEqual(StatMath.compactNumber(48_120), "48.1k")
    }

    func testCompactNumber_millionsFormatAsM() {
        XCTAssertEqual(StatMath.compactNumber(1_200_000), "1.2M")
    }

    // MARK: - weeklyVolumes (Task 6)
    // "now" is pinned to Wednesday 2024-01-03 (same anchor as the week-boundary
    // tests above), so week 6 (index 5, current/last) is Mon 2024-01-01 -> Sun
    // 2024-01-07, and week 1 (index 0, oldest) is Mon 2023-11-27 -> Sun 2023-12-03.

    private func makeSetLog(loggedAt: Date, reps: Int? = 5, weight: Decimal? = 100,
                             isFailed: Bool = false, isPenalty: Bool = false) -> SetLog {
        SetLog(
            id: UUID(),
            userID: UUID(),
            sessionID: UUID(),
            exerciseID: UUID(),
            setIndex: 0,
            reps: reps,
            weight: weight,
            rpe: nil,
            isFailed: isFailed,
            isPenalty: isPenalty,
            note: nil,
            loggedAt: loggedAt
        )
    }

    func testWeeklyVolumes_emptyLogsReturnsAllZeros() {
        let now = date(2024, 1, 3, 12)
        let result = StatMath.weeklyVolumes(logs: [], weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result, Array(repeating: 0, count: 6))
    }

    func testWeeklyVolumes_currentWeekIsLastBucket() {
        let now = date(2024, 1, 3, 12)
        let logs = [makeSetLog(loggedAt: date(2024, 1, 2, 10), reps: 5, weight: 100)] // 500, current week
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result.count, 6)
        XCTAssertEqual(result[5], 500)
        XCTAssertEqual(result[0..<5], ArraySlice(Array(repeating: Decimal(0), count: 5)))
    }

    func testWeeklyVolumes_mondayStartBoundaryIsIncludedInCurrentWeek() {
        let now = date(2024, 1, 3, 12)
        let logs = [makeSetLog(loggedAt: date(2024, 1, 1, 0, 0, 0), reps: 10, weight: 50)] // 500, Monday start
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[5], 500)
    }

    func testWeeklyVolumes_priorSundayFallsIntoPreviousWeekBucket() {
        let now = date(2024, 1, 3, 12)
        // 2023-12-31 23:59:59 is the last instant of the week BEFORE current (index 4).
        let logs = [makeSetLog(loggedAt: date(2023, 12, 31, 23, 59, 59), reps: 4, weight: 25)] // 100
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[4], 100)
        XCTAssertEqual(result[5], 0)
    }

    func testWeeklyVolumes_oldestWeekBoundary() {
        let now = date(2024, 1, 3, 12)
        // Week 1 (index 0) is Mon 2023-11-27 -> Sun 2023-12-03.
        let logs = [makeSetLog(loggedAt: date(2023, 11, 27, 0, 0, 0), reps: 2, weight: 200)] // 400
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[0], 400)
    }

    func testWeeklyVolumes_logsBeforeWindowAreExcluded() {
        let now = date(2024, 1, 3, 12)
        // One day before week 1's start (2023-11-26 23:59:59) — outside the 6-week window entirely.
        let logs = [makeSetLog(loggedAt: date(2023, 11, 26, 23, 59, 59), reps: 10, weight: 100)]
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result, Array(repeating: 0, count: 6))
    }

    func testWeeklyVolumes_emptyWeeksInterspersedAreZero() {
        let now = date(2024, 1, 3, 12)
        let logs = [
            makeSetLog(loggedAt: date(2023, 11, 27, 10), reps: 5, weight: 40),  // week 0: 200
            makeSetLog(loggedAt: date(2024, 1, 2, 10), reps: 5, weight: 20)     // week 5 (current): 100
        ]
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result, [200, 0, 0, 0, 0, 100])
    }

    func testWeeklyVolumes_sumsMultipleSetsWithinSameWeek() {
        let now = date(2024, 1, 3, 12)
        let logs = [
            makeSetLog(loggedAt: date(2024, 1, 1, 9), reps: 5, weight: 100),  // 500
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 3, weight: 100)   // 300
        ]
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[5], 800)
    }

    func testWeeklyVolumes_countsFailedSetsAtCompletedReps() {
        // Failure doctrine (owner 2026-08-13): "5 + FAIL" moved 100 lb four
        // times — 400 counts. Penalty sets and missed singles still don't.
        let now = date(2024, 1, 3, 12)
        let logs = [
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 5, weight: 100, isFailed: true),   // 4×100
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 1, weight: 500, isFailed: true),   // missed single: 0
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 5, weight: 100, isPenalty: true),  // 0
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 5, weight: 100)                    // 500
        ]
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[5], 900)
    }

    func testWeeklyVolumes_excludesSetsMissingRepsOrWeight() {
        let now = date(2024, 1, 3, 12)
        let logs = [
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: nil, weight: 100),
            makeSetLog(loggedAt: date(2024, 1, 2, 9), reps: 5, weight: nil)
        ]
        let result = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: utc, now: now)
        XCTAssertEqual(result[5], 0)
    }

    // MARK: - Body weight trend (Phase H Task 3)

    private func makeBodyWeightLog(loggedAt: Date, weight: Decimal, unit: String = "lbs") -> BodyWeightLog {
        BodyWeightLog(id: UUID(), userID: UUID(), weight: weight, unit: unit, loggedAt: loggedAt)
    }

    func testBodyWeightTrendPoints_emptyLogsReturnsEmpty() {
        XCTAssertTrue(StatMath.bodyWeightTrendPoints(logs: []).isEmpty)
    }

    func testBodyWeightTrendPoints_sortsChronologicallyOldestFirst() {
        // Deliberately fed newest-first (BodyWeightLogRepository.recent's own
        // order) — the mapper must re-sort, not assume caller order.
        let logs = [
            makeBodyWeightLog(loggedAt: date(2024, 1, 3), weight: 181),
            makeBodyWeightLog(loggedAt: date(2024, 1, 1), weight: 183),
            makeBodyWeightLog(loggedAt: date(2024, 1, 2), weight: 182)
        ]
        let result = StatMath.bodyWeightTrendPoints(logs: logs)
        XCTAssertEqual(result.map(\.0), [date(2024, 1, 1), date(2024, 1, 2), date(2024, 1, 3)])
    }

    func testBodyWeightTrendPoints_mapsDecimalWeightToDouble() {
        let logs = [makeBodyWeightLog(loggedAt: date(2024, 1, 1), weight: 182.4)]
        let result = StatMath.bodyWeightTrendPoints(logs: logs)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].1, 182.4, accuracy: 0.0001)
    }

    func testFormattedBodyWeight_wholeNumberTrimsTrailingDecimal() {
        XCTAssertEqual(StatMath.formattedBodyWeight(185, unit: "lbs"), "185 lbs")
    }

    func testFormattedBodyWeight_fractionalKeepsOneDecimal() {
        XCTAssertEqual(StatMath.formattedBodyWeight(182.4, unit: "lbs"), "182.4 lbs")
    }

    func testFormattedBodyWeight_kgUnitIsPassedThroughVerbatim() {
        XCTAssertEqual(StatMath.formattedBodyWeight(81, unit: "kg"), "81 kg")
    }
}
