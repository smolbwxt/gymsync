import XCTest
@testable import GymSync

/// ADOPT, OR BEGIN — AND CLOSE WHAT WAS LEFT OPEN (fix round 1 / N6).
///
/// The law under test is the 2026-08-22 one ("weight not carrying forward":
/// swipe-down + Start again minted a brand-new session with an empty carry),
/// moved out of `WorkoutSessionView.startIfNeeded()` when Phase C1 moved the
/// capability. These pin the two things the move lost — the organizer check
/// the old law had by construction, and the stale row nothing ever ended.
final class AdHocSessionAdoptionTests: XCTestCase {

    private let me = UUID()
    private let someoneElse = UUID()
    private let pushDay = UUID()
    private let pullDay = UUID()

    /// Fixed, built from components — never `Date()`, or this suite answers a
    /// different question tomorrow.
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func row(_ id: UUID = UUID(),
                     routine: UUID? = nil,
                     organizer: UUID? = nil,
                     group: UUID? = nil,
                     roomCode: String? = nil,
                     scheduledFor: Date? = nil,
                     minutesAgo: Double) -> AdHocSessionAdoption.Candidate {
        AdHocSessionAdoption.Candidate(
            id: id, routineID: routine, organizerID: organizer ?? me,
            groupID: group, roomCode: roomCode, scheduledFor: scheduledFor,
            startedAt: now.addingTimeInterval(-minutesAgo * 60))
    }

    private func decide(_ rows: [AdHocSessionAdoption.Candidate],
                        routineID: UUID?) -> AdHocSessionAdoption.Decision {
        AdHocSessionAdoption.decide(rows: rows, routineID: routineID, me: me, now: now)
    }

    // MARK: - The shipped law: adopt rather than mint

    func testAFreshAdHocSessionForTheSameRoutineIsAdopted() {
        let running = UUID()
        let decision = decide([row(running, routine: pushDay, minutesAgo: 20)],
                              routineID: pushDay)
        XCTAssertEqual(decision.adopt, running)
        XCTAssertEqual(decision.end, [])
    }

    func testAFRESHSessionForADIFFERENTRoutineIsNeitherAdoptedNorEnded() {
        // The 2026-08-22 bug from the other direction: resuming yesterday's
        // push day because the lifter tapped pull would fragment the history
        // just as badly. And the lifter may genuinely be running two things
        // this hour, so it is left alone rather than closed.
        let decision = decide([row(routine: pushDay, minutesAgo: 20)],
                              routineID: pullDay)
        XCTAssertNil(decision.adopt)
        XCTAssertEqual(decision.end, [])
    }

    func testAFreeformStartAdoptsOnlyAnotherFreeformSession() {
        let freeform = UUID()
        let decision = decide([row(routine: pushDay, minutesAgo: 10),
                               row(freeform, routine: nil, minutesAgo: 30)],
                              routineID: nil)
        XCTAssertEqual(decision.adopt, freeform)
    }

    func testTheNEWESTMatchingSessionIsTheOneOffered() {
        // `liveForCurrentUser` orders this way and the reasoning is its own:
        // when two are live, the one that just started is worth resuming.
        let newest = UUID()
        let decision = decide([row(routine: pushDay, minutesAgo: 200),
                               row(newest, routine: pushDay, minutesAgo: 5)],
                              routineID: pushDay)
        XCTAssertEqual(decision.adopt, newest)
    }

    func testNoRowsAtAllStartsANewOne() {
        let decision = decide([], routineID: pushDay)
        XCTAssertNil(decision.adopt)
        XCTAssertEqual(decision.end, [])
    }

    // MARK: - N6(a): only a session I ORGANIZE

    func testSomebodyElsesAdHocSessionIsNeitherAdoptedNorEnded() {
        // The old law read a handle this device had written, so this was true
        // by construction; the moved version asked only "is it ad-hoc and for
        // this routine", and its safety was incidental. Stated now.
        let theirs = row(routine: pushDay, organizer: someoneElse, minutesAgo: 20)
        let stale = row(routine: pushDay, organizer: someoneElse, minutesAgo: 60 * 24)
        let decision = decide([theirs, stale], routineID: pushDay)
        XCTAssertNil(decision.adopt)
        XCTAssertEqual(decision.end, [], "ending somebody else's session is not a thing START may do")
    }

    func testACREWSessionIsNeverAdoptedAndNeverEnded() {
        // Even one I organize. Three shapes, each disqualifying on its own.
        let group = row(routine: pushDay, group: UUID(), minutesAgo: 60 * 24)
        let code = row(routine: pushDay, roomCode: "PX4K9Z", minutesAgo: 60 * 24)
        let booked = row(routine: pushDay,
                         scheduledFor: now.addingTimeInterval(-3600), minutesAgo: 60 * 24)
        let decision = decide([group, code, booked], routineID: pushDay)
        XCTAssertNil(decision.adopt)
        XCTAssertEqual(decision.end, [])
    }

    // MARK: - N6(b): the stale row is CLOSED, not left running

    func testAStaleAdHocSessionIsEndedAndANewOneIsStarted() {
        // Before B1 a Freestyle session could not be ended at all, so this
        // was the ORDINARY outcome of every ad-hoc workout: a row left
        // `in_progress` forever, because nothing in this app ever ends a
        // session on its own.
        let abandoned = UUID()
        let decision = decide([row(abandoned, routine: pushDay, minutesAgo: 60 * 9)],
                              routineID: pushDay)
        XCTAssertNil(decision.adopt, "too old to resume")
        XCTAssertEqual(decision.end, [abandoned], "and therefore old enough to close")
    }

    func testEveryStaleAdHocRowIsClosedWhateverItsRoutine() {
        let a = UUID(), b = UUID()
        let decision = decide([row(a, routine: pushDay, minutesAgo: 60 * 9),
                               row(b, routine: pullDay, minutesAgo: 60 * 30),
                               row(routine: pushDay, minutesAgo: 5)],
                              routineID: pushDay)
        XCTAssertEqual(Set(decision.end), Set([a, b]))
    }

    func testTheADOPTEDRowIsNeverAlsoEnded() {
        let running = UUID()
        let decision = decide([row(running, routine: pushDay, minutesAgo: 20),
                               row(routine: pushDay, minutesAgo: 60 * 9)],
                              routineID: pushDay)
        XCTAssertEqual(decision.adopt, running)
        XCTAssertFalse(decision.end.contains(running))
        XCTAssertEqual(decision.end.count, 1)
    }

    func testTheBoundaryIsSixHoursAndIsNotOffByOne() {
        let justInside = UUID(), justOutside = UUID()
        let inside = decide([row(justInside, routine: pushDay,
                                 minutesAgo: (6 * 60) - 1)], routineID: pushDay)
        XCTAssertEqual(inside.adopt, justInside)
        XCTAssertEqual(inside.end, [])

        let outside = decide([row(justOutside, routine: pushDay,
                                  minutesAgo: (6 * 60) + 1)], routineID: pushDay)
        XCTAssertNil(outside.adopt)
        XCTAssertEqual(outside.end, [justOutside])
    }

    func testARowThatCannotSayWhenItBeganIsLeftALONE() {
        // `in_progress` with a NULL `started_at` is a data anomaly, not a
        // live session — it cannot be aged out, so it is neither resumed nor
        // closed. The same reading `liveForCurrentUser`'s floor already takes.
        let anomaly = AdHocSessionAdoption.Candidate(
            id: UUID(), routineID: pushDay, organizerID: me, groupID: nil,
            roomCode: nil, scheduledFor: nil, startedAt: nil)
        let decision = decide([anomaly], routineID: pushDay)
        XCTAssertNil(decision.adopt)
        XCTAssertEqual(decision.end, [])
    }
}
