import XCTest
@testable import GymSync

/// ADOPT THE WORKOUT ALREADY RUNNING, OR BEGIN ONE (fix round 1 / N6, fix
/// round 2 / B3).
///
/// The law under test is the 2026-08-22 one ("weight not carrying forward":
/// swipe-down + Start again minted a brand-new session with an empty carry),
/// moved out of `WorkoutSessionView.startIfNeeded()` when Phase C1 moved the
/// capability.
///
/// THERE ARE TWO OUTCOMES AND ONLY TWO. A third — closing a stale row with
/// `complete()` — was written in fix round 1 and withdrawn in fix round 2
/// (B3): `complete()` publishes a leaderboard entry, pushes
/// `leaderboard_passed` to another user and can post a campaign message into
/// every group the lifter belongs to, none of which a tap on START WORKOUT
/// may do to a session nobody asked to close. Several cases below assert
/// `.startFresh` precisely because the tempting answer is to write something.
final class AdHocSessionAdoptionTests: XCTestCase {

    private let me = UUID()
    private let someoneElse = UUID()
    private let pushDay = UUID()
    private let pullDay = UUID()

    /// Fixed — never `Date()`, or this suite answers a different question
    /// tomorrow.
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
        XCTAssertEqual(decide([row(running, routine: pushDay, minutesAgo: 20)],
                              routineID: pushDay),
                       .adopt(running))
    }

    func testAFRESHSessionForADIFFERENTRoutineIsLeftAlone() {
        // The 2026-08-22 bug from the other direction: resuming yesterday's
        // push day because the lifter tapped pull would fragment the history
        // just as badly. And the lifter may genuinely be running two things
        // this hour, so it is left standing, untouched.
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 20)],
                              routineID: pullDay),
                       .startFresh)
    }

    func testAFreeformStartAdoptsOnlyAnotherFreeformSession() {
        let freeform = UUID()
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 10),
                               row(freeform, routine: nil, minutesAgo: 30)],
                              routineID: nil),
                       .adopt(freeform))
    }

    func testTheNEWESTMatchingSessionIsTheOneOffered() {
        // `liveForCurrentUser` orders this way and the reasoning is its own:
        // when two are live, the one that just started is worth resuming.
        let newest = UUID()
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 200),
                               row(newest, routine: pushDay, minutesAgo: 5)],
                              routineID: pushDay),
                       .adopt(newest))
    }

    func testNoRowsAtAllStartsANewOne() {
        XCTAssertEqual(decide([], routineID: pushDay), .startFresh)
    }

    // MARK: - N6(a): only a session I ORGANIZE

    func testSomebodyElsesAdHocSessionIsNeverAdopted() {
        // The old law read a handle this device had written, so this was true
        // by construction; the moved version asked only "is it ad-hoc and for
        // this routine", and its safety was incidental. Stated now.
        let theirs = row(routine: pushDay, organizer: someoneElse, minutesAgo: 20)
        let theirStale = row(routine: pushDay, organizer: someoneElse, minutesAgo: 60 * 24)
        XCTAssertEqual(decide([theirs, theirStale], routineID: pushDay), .startFresh)
    }

    func testACREWSessionIsNeverAdopted() {
        // Even one I organize. Three shapes, each disqualifying on its own.
        let group = row(routine: pushDay, group: UUID(), minutesAgo: 20)
        let code = row(routine: pushDay, roomCode: "PX4K9Z", minutesAgo: 20)
        let booked = row(routine: pushDay,
                         scheduledFor: now.addingTimeInterval(-3600), minutesAgo: 20)
        XCTAssertEqual(decide([group, code, booked], routineID: pushDay), .startFresh)
    }

    // MARK: - B3: a stale row is IGNORED, never written to

    func testAStaleAdHocSessionIsNotResumedAndANewOneIsStarted() {
        // Master's behaviour, restored. The row stays `in_progress` — nothing
        // in this app ends a session on its own — and that residual is real,
        // but the remedy is a server-side ABANDON (C2's discard/abandon
        // capability), not `complete()`, whose three completion triggers
        // publish a leaderboard entry, push to another user and can post a
        // campaign message into every group.
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 60 * 9)],
                              routineID: pushDay),
                       .startFresh)
    }

    func testSeveralStaleRowsAreALLLeftStanding() {
        let fresh = UUID()
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 60 * 9),
                               row(routine: pullDay, minutesAgo: 60 * 30),
                               row(fresh, routine: pushDay, minutesAgo: 5)],
                              routineID: pushDay),
                       .adopt(fresh),
                       "the fresh match is taken and the two stale rows are untouched")
    }

    /// THE N4 INTERACTION, PINNED. "Not now" on the refused-leaderboard dialog
    /// deliberately leaves an attempt session standing
    /// (`DiscoverWorkoutDetailView`), and `start_attempt` has already written
    /// the `workout_attempts` row the completion triggers read. Six hours
    /// later this function must not finalize it: the attempt would be
    /// published as a finished run whose `time_seconds` is the whole
    /// wall-clock gap since the lifter walked away.
    func testAStaleATTEMPTSessionIsNotFinalizedByTheNextStart() {
        let attempt = row(routine: pushDay, minutesAgo: 60 * 7)
        XCTAssertEqual(decide([attempt], routineID: pushDay), .startFresh)
        XCTAssertEqual(decide([attempt], routineID: pullDay), .startFresh)
    }

    func testTheBoundaryIsSixHoursAndIsNotOffByOne() {
        let justInside = UUID()
        XCTAssertEqual(decide([row(justInside, routine: pushDay,
                                   minutesAgo: (6 * 60) - 1)], routineID: pushDay),
                       .adopt(justInside))
        XCTAssertEqual(decide([row(routine: pushDay,
                                   minutesAgo: (6 * 60) + 1)], routineID: pushDay),
                       .startFresh)
    }

    func testAStaleRowNeverSHADOWSAFreshMatch() {
        // Ordering is newest-first, but the stale filter is what must decide
        // — a stale row sorted ahead of a fresh one must not be adopted, and
        // must not stop the fresh one being adopted either.
        let fresh = UUID()
        XCTAssertEqual(decide([row(routine: pushDay, minutesAgo: 60 * 20),
                               row(fresh, routine: pushDay, minutesAgo: 60)],
                              routineID: pushDay),
                       .adopt(fresh))
    }

    func testARowThatCannotSayWhenItBeganIsLeftALONE() {
        // `in_progress` with a NULL `started_at` is a data anomaly, not a
        // live session — it cannot be aged, so it is never resumed. The same
        // reading `liveForCurrentUser`'s own floor takes.
        let anomaly = AdHocSessionAdoption.Candidate(
            id: UUID(), routineID: pushDay, organizerID: me, groupID: nil,
            roomCode: nil, scheduledFor: nil, startedAt: nil)
        XCTAssertEqual(decide([anomaly], routineID: pushDay), .startFresh)
    }

    func testTheDecisionHasNoOutcomeTHATWRITESToARowTheLifterDidNotActOn() {
        // B3, as a statement rather than a comment: every case in this file
        // answers `.adopt` or `.startFresh`, and the type admits nothing
        // else. If a third case is ever added, this stops compiling and the
        // author has to come and read the header's trigger walk first.
        switch decide([], routineID: nil) {
        case .adopt, .startFresh: break
        }
    }
}
