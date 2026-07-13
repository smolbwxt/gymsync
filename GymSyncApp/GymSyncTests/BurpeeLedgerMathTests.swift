import XCTest
@testable import GymSync

// Pure-function coverage for `BurpeeLedgerMath` — no network/auth dependency.
// Mirrors StatDerivationTests' shape (see that file for the established
// pattern this one follows).
final class BurpeeLedgerMathTests: XCTestCase {

    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        return utc.date(from: components)!
    }

    private func makeRow(
        userID: UUID,
        checkInState: String?,
        lateMinutes: Int = 0,
        burpeesOwed: Int = 0,
        sessionID: UUID = UUID(),
        sessionState: String = "completed",
        scheduledFor: Date? = nil,
        perMinute: Int? = 5
    ) -> BurpeeLedgerRow {
        BurpeeLedgerRow(
            userID: userID,
            checkInState: checkInState,
            lateMinutes: lateMinutes,
            burpeesOwed: burpeesOwed,
            session: BurpeeLedgerRow.SessionInfo(
                id: sessionID,
                state: sessionState,
                scheduledFor: scheduledFor,
                startedAt: nil,
                latePenalty: perMinute.map { BurpeeLedgerRow.SessionInfo.LatePenalty(perMinute: $0) }
            )
        )
    }

    // MARK: - crewDebts

    func testCrewDebts_sumsOwedAcrossMultipleSessions() {
        let sarah = UUID()
        let rows = [
            makeRow(userID: sarah, checkInState: "late", burpeesOwed: 10),
            makeRow(userID: sarah, checkInState: "late", burpeesOwed: 25)
        ]
        let debts = BurpeeLedgerMath.crewDebts(rows: rows)
        XCTAssertEqual(debts.count, 1)
        XCTAssertEqual(debts[0].totalOwed, 35)
        XCTAssertEqual(debts[0].lateCount, 2)
    }

    func testCrewDebts_countsNoShowsAndLateSeparately() {
        let sarah = UUID()
        let rows = [
            makeRow(userID: sarah, checkInState: "no_show", burpeesOwed: 0),
            makeRow(userID: sarah, checkInState: "no_show", burpeesOwed: 0),
            makeRow(userID: sarah, checkInState: "no_show", burpeesOwed: 0),
            makeRow(userID: sarah, checkInState: "late", burpeesOwed: 5),
            makeRow(userID: sarah, checkInState: "late", burpeesOwed: 5)
        ]
        let debts = BurpeeLedgerMath.crewDebts(rows: rows)
        XCTAssertEqual(debts[0].noShowCount, 3)
        XCTAssertEqual(debts[0].lateCount, 2)
        XCTAssertEqual(debts[0].summaryText, "3 no-shows · 2 late")
    }

    func testCrewDebts_summaryText_singularNoShowAndAllClear() {
        let a = UUID(); let b = UUID()
        let rows = [
            makeRow(userID: a, checkInState: "no_show", burpeesOwed: 0),
            makeRow(userID: b, checkInState: "online", burpeesOwed: 0)
        ]
        let debts = BurpeeLedgerMath.crewDebts(rows: rows)
        let aDebt = debts.first { $0.userID == a }!
        let bDebt = debts.first { $0.userID == b }!
        XCTAssertEqual(aDebt.summaryText, "1 no-show")
        XCTAssertEqual(bDebt.summaryText, "all clear")
    }

    func testCrewDebts_sortedByTotalOwedDescending() {
        let low = UUID(); let high = UUID(); let zero = UUID()
        let rows = [
            makeRow(userID: low, checkInState: "late", burpeesOwed: 15),
            makeRow(userID: high, checkInState: "late", burpeesOwed: 35),
            makeRow(userID: zero, checkInState: "online", burpeesOwed: 0)
        ]
        let debts = BurpeeLedgerMath.crewDebts(rows: rows)
        XCTAssertEqual(debts.map(\.userID), [high, low, zero])
    }

    func testCrewDebts_settledParticipantReadsIdenticalToNeverLate() {
        // Schema gap: burpees_owed is never decremented, so a user who was
        // late in the past but whose current summed total happens to be 0
        // (e.g. the row simply isn't in this fetch) is indistinguishable
        // from one who was never late. Both surface as "all clear", 0 owed.
        let neverLate = UUID(); let settledElsewhere = UUID()
        let rows = [
            makeRow(userID: neverLate, checkInState: "online", burpeesOwed: 0),
            makeRow(userID: settledElsewhere, checkInState: "ready", burpeesOwed: 0)
        ]
        let debts = BurpeeLedgerMath.crewDebts(rows: rows)
        XCTAssertEqual(Set(debts.map(\.summaryText)), ["all clear"])
        XCTAssertTrue(debts.allSatisfy { $0.totalOwed == 0 })
    }

    // MARK: - youOweSummary

    func testYouOweSummary_totalsOnlyTheGivenUser() {
        let me = UUID(); let other = UUID()
        let rows = [
            makeRow(userID: me, checkInState: "late", burpeesOwed: 10),
            makeRow(userID: me, checkInState: "late", burpeesOwed: 5),
            makeRow(userID: other, checkInState: "late", burpeesOwed: 100)
        ]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertEqual(summary.total, 15)
    }

    func testYouOweSummary_mostRecentContributingSessionDetails() {
        let me = UUID()
        let olderSessionID = UUID()
        let newerSessionID = UUID()
        let rows = [
            makeRow(userID: me, checkInState: "late", lateMinutes: 1, burpeesOwed: 5,
                    sessionID: olderSessionID, scheduledFor: date(2026, 7, 1), perMinute: 5),
            makeRow(userID: me, checkInState: "late", lateMinutes: 2, burpeesOwed: 10,
                    sessionID: newerSessionID, scheduledFor: date(2026, 7, 10), perMinute: 5)
        ]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertEqual(summary.total, 15)
        XCTAssertEqual(summary.mostRecentSessionID, newerSessionID)
        XCTAssertEqual(summary.mostRecentLateMinutes, 2)
        XCTAssertEqual(summary.mostRecentDate, date(2026, 7, 10))
        XCTAssertEqual(summary.mostRecentPerMinute, 5)
    }

    func testYouOweSummary_ignoresZeroOwedRowsWhenPickingMostRecent() {
        // A session where the user checked in on time (burpees_owed = 0) but
        // scheduled AFTER their last actual debt must not be picked as "most
        // recent" — it contributed nothing to what's owed.
        let me = UUID()
        let debtSessionID = UUID()
        let rows = [
            makeRow(userID: me, checkInState: "late", lateMinutes: 3, burpeesOwed: 15,
                    sessionID: debtSessionID, scheduledFor: date(2026, 7, 1), perMinute: 5),
            makeRow(userID: me, checkInState: "ready", lateMinutes: 0, burpeesOwed: 0,
                    sessionID: UUID(), scheduledFor: date(2026, 7, 12), perMinute: 5)
        ]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertEqual(summary.total, 15)
        XCTAssertEqual(summary.mostRecentSessionID, debtSessionID)
    }

    func testYouOweSummary_zeroTotalHasNilDetailFields() {
        let me = UUID()
        let rows = [makeRow(userID: me, checkInState: "ready", burpeesOwed: 0)]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertEqual(summary.total, 0)
        XCTAssertNil(summary.mostRecentLateMinutes)
        XCTAssertNil(summary.mostRecentDate)
        XCTAssertNil(summary.mostRecentSessionID)
    }

    func testYouOweSummary_mostRecentSessionIsLiveReflectsSessionState() {
        let me = UUID()
        let rows = [
            makeRow(userID: me, checkInState: "late", lateMinutes: 2, burpeesOwed: 10,
                    sessionState: "in_progress", scheduledFor: date(2026, 7, 10))
        ]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertTrue(summary.mostRecentSessionIsLive)
    }

    func testYouOweSummary_completedSessionIsNotLive() {
        let me = UUID()
        let rows = [
            makeRow(userID: me, checkInState: "late", lateMinutes: 2, burpeesOwed: 10,
                    sessionState: "completed", scheduledFor: date(2026, 7, 10))
        ]
        let summary = BurpeeLedgerMath.youOweSummary(rows: rows, userID: me)
        XCTAssertFalse(summary.mostRecentSessionIsLive)
    }
}
