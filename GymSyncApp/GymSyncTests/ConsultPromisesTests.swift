import XCTest
@testable import GymSync

/// Two promises the consult made and the app then broke. Both were on the
/// DEFAULT path — the consult pushes straight into the wizard now — and
/// both were invisible, because each half of the code looked correct on
/// its own.
final class ConsultPromisesTests: XCTestCase {

    // MARK: - "The work will take N days a week"

    /// The number the athlete READ, from the same source the question was
    /// rendered from.
    private func renderedDays(logged: Double, stated: Int) -> String {
        var context = ConsultProbe.Context()
        context.hasLog = true
        context.loggedDaysPerWeek = logged
        context.statedDaysPerWeek = stated
        context.recommendedDaysPerWeek = stated
        let probe = ConsultProbe.bank.first { $0.id == "commitment" }!
        return ConsultProbe.ask(probe, in: context)
    }

    func testTheCommitmentRecordsTheNumberTheAthleteWasShown() {
        // The defect: the question rendered from context (5), the applier
        // read the view's stored property (the profile default, 3), and
        // the athlete agreed to one number while another was written down.
        let shown = renderedDays(logged: 2, stated: 5)
        XCTAssertTrue(shown.contains("5 days a week"), shown)

        let after = ConsultAnswers(["commitment": ["commit", "5"]])
            .apply(to: TrainingProfile())
        XCTAssertEqual(after.daysPerWeek, 5,
                       "wrote a different number than the sentence promised")
    }

    func testTheDaysAnswerAndTheCommitmentCannotDisagree() {
        // Both probes write daysPerWeek and the applier runs days first,
        // so a mismatch would silently resolve in the commitment's favour.
        // With both sourced from the same number, order stops mattering.
        let after = ConsultAnswers([
            "days": ["5"],
            "commitment": ["commit", "5"],
        ]).apply(to: TrainingProfile())
        XCTAssertEqual(after.daysPerWeek, 5)
    }

    func testKeepingTheCurrentCadenceStillChangesNothing() {
        var before = TrainingProfile()
        before.daysPerWeek = 2
        let after = ConsultAnswers(["commitment": ["current"]]).apply(to: before)
        XCTAssertEqual(after.daysPerWeek, 2, "the honest trade is a longer block")
    }

    func testAMalformedCommitmentIsIgnoredRatherThanGuessed() {
        // No number alongside the choice means we do not know what they
        // were shown, so we must not write one.
        var before = TrainingProfile()
        before.daysPerWeek = 3
        XCTAssertEqual(ConsultAnswers(["commitment": ["commit"]])
                        .apply(to: before).daysPerWeek, 3)
    }

    // MARK: - "Dumbbells only"

    func testTheEquipmentAnswerSurvivesOntoTheProfile() {
        let after = ConsultAnswers(["equipment": ["dumbbell"]]).apply(to: TrainingProfile())
        XCTAssertEqual(after.equipment, ["dumbbell"])
        XCTAssertEqual(after.provenance["equipment"], .stated)
    }

    func testAConstrainedProfileActuallyConstrainsTheGenerator() {
        // The end of the chain the wizard used to break: the answer has to
        // reach ProgramGenerator.Inputs, or the athlete gets barbell lifts
        // they cannot perform.
        var profile = TrainingProfile()
        profile.equipment = ["dumbbell"]
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.equipment, ["dumbbell"])
    }

    func testAnAllOnAnswerReadsAsNoConstraint() {
        // nil and "everything" mean the same thing to the generator, and
        // this equivalence is exactly why a dropped hydration was
        // destructive rather than merely lossy: the dial defaults to
        // all-on, so failing to restore the answer WROTE all-on back.
        var profile = TrainingProfile()
        profile.equipment = Set(Venue.equipmentClasses)
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.equipment, Set(Venue.equipmentClasses))

        var unset = TrainingProfile()
        unset.equipment = nil
        XCTAssertNil(unset.generatorInputs(durationWeeks: 8).equipment)
    }

    func testEveryEquipmentChipIsAClassTheCatalogFiltersOn() {
        // A chip offering something outside Venue.equipmentClasses would
        // be silently dropped by the applier and the athlete would never
        // know their constraint was ignored.
        let probe = ConsultProbe.bank.first { $0.id == "equipment" }!
        let ids = ConsultVocabulary.options(for: probe, catalog: []).map(\.id)
        XCTAssertEqual(ids, Venue.equipmentClasses)
        XCTAssertFalse(ids.isEmpty)
    }
}
