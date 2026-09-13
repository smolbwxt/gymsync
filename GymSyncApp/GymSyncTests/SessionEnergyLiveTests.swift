import XCTest
@testable import GymSync

/// `session_participants.energy` through the client, against the live project
/// — plan task S5, migration 20260912000101 (applied 2026-09-12 23:27 UTC).
///
/// The column round-trips here so the lobby's energy widget has a value behind
/// it before it has a pixel. What is proved: the write reaches my own row, the
/// clamp is real rather than assumed, and an unanswered row decodes as nil —
/// never 0, because an absence is not a reading of one.
///
/// **2099, and `TestSession`** (global constraint 16). These run as the shared
/// CI account, in parallel with the screenshot job; a current-week session
/// would fight `scripts/seed_qa_fixtures.js` and could reach a frozen frame.
/// The factory registers `deleteSession` with `addTeardownBlock` BEFORE it
/// returns, so every exit path from these tests cleans up — XCTest awaits
/// teardown blocks, which `defer { Task { … } }` does not.
final class SessionEnergyLiveTests: XCTestCase {

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
    }

    /// A scheduled session in 2099, with this account as its only
    /// participant. `makeTempScheduledSession` writes the organizer as an
    /// `online` participant, which is the row every test below updates.
    private func makeSession() async throws -> WorkoutSession {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        let when = calendar.date(from: DateComponents(year: 2099, month: 3, day: 1,
                                                      hour: 12)) ?? Date()
        return try await makeTempScheduledSession(scheduledFor: when)
    }

    /// My own row, by user id. `participants(sessionID:)` is what the lobby
    /// reads, so the assertion goes through the same door the screen does.
    private func myRow(sessionID: UUID) async throws -> SessionParticipant {
        let me = await SupabaseService.shared.currentUserID()
        let userID = try XCTUnwrap(me)
        let rows = try await SessionRepository.participants(sessionID: sessionID)
        let mine = rows.first { $0.participant.userID == userID }
        return try XCTUnwrap(mine).participant
    }

    // MARK: - 1: the round trip

    func testEnergyWrittenByTheClientReadsBack() async throws {
        let session = try await makeSession()
        try await SessionRepository.setEnergy(sessionID: session.id, value: 4)
        let row = try await myRow(sessionID: session.id)
        XCTAssertEqual(row.energy, 4)
    }

    // MARK: - 2: the clamp is proved, not assumed

    /// A UI that can only send 1-5 still must not be the only guard. Without
    /// the clamp this write is a 23514 the lobby would have to render as an
    /// error, for a number no lifter could have chosen.
    func testAnOutOfRangeValueIsClampedRatherThanRejected() async throws {
        let session = try await makeSession()
        try await SessionRepository.setEnergy(sessionID: session.id, value: 9)
        let high = try await myRow(sessionID: session.id)
        XCTAssertEqual(high.energy, 5)

        try await SessionRepository.setEnergy(sessionID: session.id, value: 0)
        let low = try await myRow(sessionID: session.id)
        XCTAssertEqual(low.energy, 1, "0 is not a reading — the floor is 1")
    }

    // MARK: - 3: unanswered is nil, never 0

    func testAFreshParticipantRowHasNoEnergy() async throws {
        let session = try await makeSession()
        let row = try await myRow(sessionID: session.id)
        XCTAssertNil(row.energy,
                     "a lifter who has not answered has not reported energy 0")
    }
}
