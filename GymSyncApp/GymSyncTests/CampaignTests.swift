import XCTest
@testable import GymSync

// Hermetic coverage for the pure campaign-progress math (`CampaignProgressMath`,
// Models/Campaign.swift) and the date-window state machine (`Campaign.
// windowState(now:)`/`daysUntilStart(now:)`) — no network/auth dependency,
// same "hermetic derivation" idiom as `PlateMathTests`/`BurpeeLedgerMathTests`.
// The Phase C Task 2 brief names these two cases explicitly: "progress %,
// date-window state machine."
final class CampaignTests: XCTestCase {

    // MARK: - Fixtures

    private static let campaignID = UUID()
    private static let userID = UUID()

    private func progress(sessions: Int, workouts: Int, volume: Decimal = 0) -> CampaignProgress {
        CampaignProgress(
            campaignID: Self.campaignID, userID: Self.userID,
            sessionsCompleted: sessions, workoutsCompleted: workouts,
            volumeLifted: volume, updatedAt: .now
        )
    }

    // MARK: - CampaignProgressMath.achievedCount

    func testAchievedCount_sessionsTarget_readsSessionsCompleted() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let result = CampaignProgressMath.achievedCount(progress: progress(sessions: 7, workouts: 7), target: target)
        XCTAssertEqual(result, 7)
    }

    func testAchievedCount_workoutsTarget_readsWorkoutsCompleted() {
        let target = CampaignIndividualTarget(sessions: nil, workoutsCompleted: 4)
        let result = CampaignProgressMath.achievedCount(progress: progress(sessions: 9, workouts: 3), target: target)
        XCTAssertEqual(result, 3)
    }

    func testAchievedCount_nilProgress_isZero_notNil() {
        // A participant with no campaign_progress row yet (no qualifying
        // session completed) — the trigger's own insert-on-first-touch idiom
        // (20260728000002_campaign_progress_trigger.sql:272-274) means this
        // is a real, common state, not an edge case.
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let result = CampaignProgressMath.achievedCount(progress: nil, target: target)
        XCTAssertEqual(result, 0)
    }

    func testAchievedCount_noTarget_isNil() {
        // No individual_target key recognized (nil target, or a campaign
        // whose individual_target is nil entirely) — nothing to count
        // toward; distinct from 0.
        let result = CampaignProgressMath.achievedCount(progress: progress(sessions: 7, workouts: 7), target: nil)
        XCTAssertNil(result)
    }

    func testAchievedCount_emptyTargetKeys_isNil() {
        let target = CampaignIndividualTarget(sessions: nil, workoutsCompleted: nil)
        let result = CampaignProgressMath.achievedCount(progress: progress(sessions: 7, workouts: 7), target: target)
        XCTAssertNil(result)
    }

    // MARK: - CampaignProgressMath.fractionComplete (progress %)

    func testFractionComplete_partialProgress() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let fraction = CampaignProgressMath.fractionComplete(progress: progress(sessions: 3, workouts: 3), target: target)
        XCTAssertEqual(fraction, 0.25, accuracy: 0.0001)
    }

    func testFractionComplete_zeroProgress_isZero() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let fraction = CampaignProgressMath.fractionComplete(progress: nil, target: target)
        XCTAssertEqual(fraction, 0.0, accuracy: 0.0001)
    }

    func testFractionComplete_exactlyAtTarget_isOne() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let fraction = CampaignProgressMath.fractionComplete(progress: progress(sessions: 12, workouts: 12), target: target)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    func testFractionComplete_pastTarget_clampsToOne() {
        // A late duration-edit or a campaign whose window re-triggers can
        // never actually push counters past the target in this schema (the
        // trigger only ever increments), but the math itself must not
        // render a >100% bar if it somehow did.
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let fraction = CampaignProgressMath.fractionComplete(progress: progress(sessions: 15, workouts: 15), target: target)
        XCTAssertEqual(fraction, 1.0, accuracy: 0.0001)
    }

    func testFractionComplete_noRecognizedTarget_isNil() {
        let fraction = CampaignProgressMath.fractionComplete(progress: progress(sessions: 3, workouts: 3), target: nil)
        XCTAssertNil(fraction)
    }

    // MARK: - CampaignProgressMath.isComplete (completion badge state)

    func testIsComplete_belowTarget_isFalse() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        XCTAssertFalse(CampaignProgressMath.isComplete(progress: progress(sessions: 11, workouts: 11), target: target))
    }

    func testIsComplete_atTarget_isTrue() {
        // Mirrors the trigger's own crossing check (`v_new_count >=
        // v_target_n`, 20260728000002_campaign_progress_trigger.sql:318) —
        // the exact session that lands ON the target already counts as
        // complete server-side (that's what fires the completion chat
        // message), so the client badge must agree.
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        XCTAssertTrue(CampaignProgressMath.isComplete(progress: progress(sessions: 12, workouts: 12), target: target))
    }

    func testIsComplete_pastTarget_isTrue() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        XCTAssertTrue(CampaignProgressMath.isComplete(progress: progress(sessions: 20, workouts: 20), target: target))
    }

    func testIsComplete_noProgressRowYet_isFalse() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        XCTAssertFalse(CampaignProgressMath.isComplete(progress: nil, target: target))
    }

    func testIsComplete_noTarget_isFalse() {
        XCTAssertFalse(CampaignProgressMath.isComplete(progress: progress(sessions: 999, workouts: 999), target: nil))
    }

    // MARK: - Campaign.windowState (date-window state machine)

    private func campaign(startsAt: Date, endsAt: Date) -> Campaign {
        Campaign(
            id: UUID(), name: "Test Campaign", description: nil,
            startsAt: startsAt, endsAt: endsAt, bannerURL: nil,
            globalTarget: nil, individualTarget: nil, curatedRoutineIDs: [],
            isFeatured: false, isDraft: false, createdAt: .now
        )
    }

    func testWindowState_beforeStart_isUpcoming() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = campaign(startsAt: now.addingTimeInterval(3600), endsAt: now.addingTimeInterval(7200))
        XCTAssertEqual(c.windowState(now: now), .upcoming)
    }

    func testWindowState_withinWindow_isActive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = campaign(startsAt: now.addingTimeInterval(-3600), endsAt: now.addingTimeInterval(3600))
        XCTAssertEqual(c.windowState(now: now), .active)
    }

    func testWindowState_atExactStart_isActive() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = campaign(startsAt: now, endsAt: now.addingTimeInterval(3600))
        XCTAssertEqual(c.windowState(now: now), .active)
    }

    func testWindowState_atExactEnd_isActive() {
        // Inclusive end — mirrors the trigger's own BETWEEN predicate
        // (`completed_at BETWEEN starts_at AND ends_at`,
        // 20260728000002_campaign_progress_trigger.sql:229/251), which is
        // inclusive on both bounds.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = campaign(startsAt: now.addingTimeInterval(-3600), endsAt: now)
        XCTAssertEqual(c.windowState(now: now), .active)
    }

    func testWindowState_afterEnd_isEnded() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let c = campaign(startsAt: now.addingTimeInterval(-7200), endsAt: now.addingTimeInterval(-3600))
        XCTAssertEqual(c.windowState(now: now), .ended)
    }

    // MARK: - Campaign.daysUntilStart

    func testDaysUntilStart_futureCampaign_countsWholeDays() {
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let starts = calendar.date(byAdding: .day, value: 5, to: now)!
        let c = campaign(startsAt: starts, endsAt: calendar.date(byAdding: .day, value: 20, to: now)!)
        XCTAssertEqual(c.daysUntilStart(now: now), 5)
    }

    func testDaysUntilStart_startsToday_isZero() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let c = campaign(startsAt: now, endsAt: now.addingTimeInterval(86400 * 10))
        XCTAssertEqual(c.daysUntilStart(now: now), 0)
    }

    func testDaysUntilStart_alreadyStarted_neverNegative() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let c = campaign(startsAt: now.addingTimeInterval(-86400 * 3), endsAt: now.addingTimeInterval(86400 * 10))
        XCTAssertEqual(c.daysUntilStart(now: now), 0)
    }

    // MARK: - CampaignIndividualTarget.resolvedTarget

    func testResolvedTarget_sessionsKey() {
        let target = CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil)
        let resolved = target.resolvedTarget
        XCTAssertEqual(resolved?.count, 12)
        XCTAssertEqual(resolved?.unitLabel, "sessions")
    }

    func testResolvedTarget_workoutsKey() {
        let target = CampaignIndividualTarget(sessions: nil, workoutsCompleted: 4)
        let resolved = target.resolvedTarget
        XCTAssertEqual(resolved?.count, 4)
        XCTAssertEqual(resolved?.unitLabel, "workouts")
    }

    func testResolvedTarget_neitherKey_isNil() {
        let target = CampaignIndividualTarget(sessions: nil, workoutsCompleted: nil)
        XCTAssertNil(target.resolvedTarget)
    }
}
