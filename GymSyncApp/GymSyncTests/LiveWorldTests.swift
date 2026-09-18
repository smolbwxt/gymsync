import XCTest
@testable import GymSync

/// The live body's catalog world — plan task S4, global constraint 11.
///
/// The frame is proved by a screenshot. What a screenshot cannot prove is
/// that it will be the SAME screenshot tomorrow: `SessionLiveView` renders
/// two `Text(date, style: .timer)` counters — the header rail's session clock
/// and the entry card's turn clock — and either one, handed a real date,
/// makes the capture differ from itself between runs. Both are suppressed by
/// the world's own shape, and that shape is what these assertions pin.
final class LiveWorldTests: XCTestCase {

    private var world: LiveWorld { LiveFixtures.yourTurn }

    // MARK: - No clock

    /// `turnHeaderRail`'s clock renders only `if selfHeartRate != nil, let
    /// startedAt = liveSession.startedAt` — a nil start takes it off the rail
    /// rather than counting up inside the frame.
    func testTheWorldHasNoSessionStart() {
        XCTAssertNil(world.session.startedAt)
    }

    /// `turnEntryCard` prints `Text(ts, style: .timer)` for a turn stamp and
    /// an em dash without one. The em dash is the deterministic half.
    func testTheWorldHasNoTurnStamp() {
        XCTAssertNil(world.session.currentTurnStartedAt)
    }

    /// The round wait and Together both measure from lifting start; the
    /// my-turn page reads it not at all, and a value here would be a clock
    /// for no reader.
    func testTheWorldHasNoLiftingStart() {
        XCTAssertNil(world.session.liftingStartedAt)
        XCTAssertNil(world.session.completedAt)
    }

    // MARK: - It is the my-turn page, and it is live

    /// `showsCrewPage` needs `.rounds`, a turn holder, a turn that is NOT
    /// mine, and a non-empty roster. This world holds the turn itself, so
    /// the my-turn page is what renders — which is the frame.
    func testTheTurnIsMine() {
        XCTAssertEqual(world.session.style, .rounds)
        XCTAssertEqual(world.session.currentTurnUserID, world.selfID)
    }

    /// `commitInlineLog` refuses outright unless the session is live, and
    /// `logControlFoot` is what the frame exists to show enabled.
    func testTheSessionIsInProgress() {
        XCTAssertEqual(world.session.state, "in_progress")
        XCTAssertEqual(world.session.round, 2)
    }

    /// The entry card's LOG control is disabled without parseable reps. A
    /// frame of a dead button proves nothing.
    func testTheEntryIsPrefilledSoTheLogControlEnables() {
        XCTAssertNotNil(leadingInt(world.logReps))
        XCTAssertFalse(world.logWeight.isEmpty)
    }

    // MARK: - Every name the page prints is resolvable

    /// The live body looks EVERY exercise name up in `allExercises`; a
    /// routine row pointing at an id the world does not carry renders as a
    /// blank card.
    func testEveryRoutineRowNamesAnExerciseTheWorldCarries() {
        let known = Set(world.allExercises.map(\.id))
        for row in world.routineExercises {
            XCTAssertTrue(known.contains(row.exerciseID),
                          "routine row \(row.position) names an exercise the world does not carry")
        }
    }

    /// `turnVitalsRow`'s second slot is LOAD THE BAR for barbell work and
    /// LAST TIME otherwise — and LAST TIME's meta line ("6 DAYS AGO") is
    /// computed against `Date()`. The current exercise must be barbell, or
    /// the frame grows a clock.
    func testTheCurrentExerciseIsBarbell() {
        let current = RoutineProgression.currentExercise(
            routine: world.routineExercises,
            completedSets: { id in
                world.sets.filter { $0.exerciseID == id && !$0.isPenalty }.count
            })
        let exercise = world.allExercises.first { $0.id == current?.exerciseID }
        XCTAssertEqual(exercise?.equipment, "barbell")
    }

    /// Every logged set is MINE and non-penalty: `myTurnSets` filters on
    /// both, and a fixture set belonging to somebody else would silently
    /// vanish from the SETS page instead of failing loudly here.
    func testTheLoggedSetsAreMine() {
        XCTAssertFalse(world.sets.isEmpty)
        XCTAssertTrue(world.sets.allSatisfy { $0.userID == world.selfID })
        XCTAssertTrue(world.sets.allSatisfy { !$0.isPenalty })
        XCTAssertTrue(world.sets.allSatisfy { $0.sessionID == world.session.id })
    }

    /// The roster is a count, not an array: `SessionParticipant` and
    /// `Profile` are decode-only types no fixture can build, so the world
    /// names what the header rail prints and leaves `participants` empty —
    /// which is also what keeps the crew page off the screen.
    func testTheRosterIsACountTheHeaderRailCanPrint() {
        XCTAssertGreaterThan(world.participantCount, 1)
    }
}
