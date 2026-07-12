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
}
