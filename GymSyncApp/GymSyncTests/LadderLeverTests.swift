import XCTest
@testable import GymSync

// MARK: - LadderLeverTests
//
// FINAL REVIEW F2: three of the ladder page's four levers were enabled,
// tappable and inert. `onEditMilestone` and `onEditRung` were closures
// defaulted to `{}`, every one of the seven production constructions omitted
// both, and two doc comments claimed I1 had wired them. Nothing could catch it:
// a defaulted closure cannot be asserted from a call site, and a frame of a
// raised face with a chevron looks identical whether it goes anywhere or not.
//
// So the page owns its editors now, and these hold the wiring as VALUES — the
// same shape `LadderRepositoryWiringTests` uses, and for the same reason: a
// lever that stops reaching its editor has to fail a test rather than look
// correct.
final class LadderLeverTests: XCTestCase {

    /// Recognisable, and answers nothing — a test that accidentally rendered a
    /// view holding one gets the empty state rather than fixture data.
    private struct MarkerWeeklyGoalRepository: WeeklyGoalRepository {
        func goal(weekStart: String) async -> WeeklyGoal? { nil }
        func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress { WeeklyGoalProgress() }
        @discardableResult func save(_ goal: WeeklyGoal) async -> Bool { false }
        func clearToCoach(weekStart: String) async -> WeeklyGoal? { nil }
    }

    private let goalID = StubBlockGoalRepository.fixtureGoalID

    private func page(_ repository: any WeeklyGoalRepository
                        = MarkerWeeklyGoalRepository()) -> LadderPageView {
        LadderPageView(goalID: goalID, repository: StubBlockGoalRepository(),
                       weeklyGoalRepository: repository)
    }

    // MARK: - EDIT THE MILESTONE / EDIT THE DATE

    /// The card opens on THE GOAL, not on a fresh seed derived from where the
    /// athlete is today — they came here to move 225, not to be shown 210.
    func testTheMilestoneLeverOpensTheGoalsOwnCard() {
        let goal = StubBlockGoalRepository.fixtureGoal
        let editor = page().milestoneEditor(goal: goal, preset: .strength)

        XCTAssertEqual(editor.editing?.id, goal.id)
        XCTAssertEqual(editor.preset, .strength,
                       "the card is the GOAL's preset, not the tile last tapped")
    }

    /// The draft the card opens on is the milestone itself — target, date and
    /// preset — stamped `user`, because opening this editor is the athlete
    /// taking the milestone back (owner decision 8).
    func testTheEditableDraftIsTheMilestoneItself() {
        let goal = StubBlockGoalRepository.fixtureGoal
        let draft = GoalMilestoneCopy.editableDraft(goal)

        XCTAssertEqual(draft.metric, goal.metric)
        XCTAssertEqual(draft.target, goal.target)
        XCTAssertEqual(draft.byDate, goal.byDate)
        XCTAssertEqual(draft.preset, goal.preset)
        XCTAssertEqual(draft.source, .user)
    }

    /// The edit screen does not claim the write. Spec §6 gives the ladder page
    /// the one accent primary and it is the save; a second button saying "save"
    /// is how an athlete comes to believe a thing is stored when it is not.
    func testTheEditScreensPrimaryHandsBackRatherThanSaves() {
        XCTAssertEqual(GoalMilestoneCopy.primaryTitle(editing: false), "BUILD MY BLOCK")
        XCTAssertEqual(GoalMilestoneCopy.primaryTitle(editing: true), "USE THIS MILESTONE")
    }

    /// The door is untouched by the edit mode: no `editing`, the same seed it
    /// always had. The frames 94-96 render this construction.
    func testTheDoorsCardIsUnchanged() {
        let door = GoalMilestoneView(preset: .strength, current: GoalTarget(),
                                     today: StubBlockGoalRepository.fixtureCreatedAt,
                                     onBuild: { _ in })
        XCTAssertNil(door.editing)
    }

    // MARK: - EDIT THIS WEEK'S RUNG

    /// Task D3's header context, built from the page model — so the editor's
    /// header and the ladder's own headline name ONE milestone in one spelling,
    /// which is what `WeeklyGoalEditorSheet.rungLine` is a contract about.
    func testTheRungContextIsTheLaddersOwnStanding() {
        let context = LadderPageView.rungContext(StubBlockGoalRepository.fixturePage)

        XCTAssertEqual(context.weekNumber, 3)
        XCTAssertEqual(context.weekCount, 8)
        XCTAssertEqual(context.milestone, "Bench 225 by Oct 18")
        XCTAssertEqual(
            WeeklyGoalEditorSheet.rungLine(context),
            "Week 3 of 8 of \"Bench 225 by Oct 18\". "
            + "Change this week and Coach ladders from where you actually are.",
            "the rung-scoped header D3 shipped and nothing constructed")
    }

    /// The rung editor is the SHIPPED editor, carrying the rung context — the
    /// `RungContext` that was never constructed in production before this.
    func testTheRungLeverOpensTheShippedEditorScopedToTheRung() {
        let context = LadderPageView.rungContext(StubBlockGoalRepository.fixturePage)
        let editor = page().rungEditor(userID: UUID(), weekStart: "2026-09-06",
                                       weekly: nil, context: context,
                                       weeklySessionGoal: 4)

        XCTAssertEqual(editor.rung, context)
        XCTAssertEqual(editor.weekStart, "2026-09-06")
        XCTAssertEqual(editor.weeklySessionGoal, 4,
                       "the profile's STANDING goal seeds the days stepper, never a default")
    }

    /// The editor writes through the page's OWN weekly repository. A dropped
    /// injection here would mean an edit made from Home writing somewhere Home
    /// does not read — the silent mismatch `LadderRepositoryWiringTests` exists
    /// for, one surface further down.
    func testTheRungEditorCarriesThePagesWeeklyRepository() {
        let editor = page().rungEditor(
            userID: UUID(), weekStart: "2026-09-06", weekly: nil,
            context: LadderPageView.rungContext(StubBlockGoalRepository.fixturePage),
            weeklySessionGoal: 3)
        XCTAssertTrue(editor.repository is MarkerWeeklyGoalRepository)
    }

    /// And Home hands its own down, so the strip and the rung editor one tap
    /// away are the same repository.
    func testHomePassesItsWeeklyRepositoryToTheLadderPage() {
        let home = HomeView(goalRepository: MarkerWeeklyGoalRepository())
        XCTAssertTrue(home.ladderPage(for: UUID()).weeklyGoalRepository
                        is MarkerWeeklyGoalRepository)
    }

    /// The uninjected default is live, like every other binding I1 swapped.
    func testTheUninjectedWeeklyRepositoryIsLive() {
        XCTAssertTrue(LadderPageView(goalID: UUID()).weeklyGoalRepository
                        is LiveWeeklyGoalRepository)
    }
}
