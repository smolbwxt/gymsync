import XCTest
@testable import GymSync

/// The focus probes, end to end. Both of them were promising something
/// nothing could deliver: `focusMuscles` lived only on
/// ProgramGenerator.Inputs, so an answer collected in the consult had
/// nowhere to sit between the screen that gathered it and the wizard that
/// builds. "Pick two and I'll give them the volume" was a promise no code
/// could keep, and "which lift is the number on?" was recorded and
/// dropped outright.
final class ConsultFocusTests: XCTestCase {

    private func exercise(_ name: String, muscle: String) -> Exercise {
        Exercise(id: UUID(), name: name, slug: name.lowercased(),
                 category: "compound", primaryMuscle: muscle,
                 secondaryMuscles: [], equipment: "barbell",
                 defaultUnit: "lbs", demoVideoURL: nil)
    }

    private var catalog: [Exercise] {
        [
            exercise("Bench Press", muscle: "chest"),
            exercise("Incline Bench Press", muscle: "chest"),
            exercise("Close-Grip Bench Press", muscle: "triceps"),
            exercise("Back Squat", muscle: "quads"),
            exercise("Barbell Row", muscle: "back"),
        ]
    }

    // MARK: - Naming a lift

    func testAnExactNameResolves() {
        let answers = ConsultAnswers(["focus_lift": ["Back Squat"]])
        XCTAssertEqual(answers.focusLift(in: catalog)?.name, "Back Squat")
    }

    func testPeopleTypeBenchNotBarbellBenchPress() {
        // "bench" contains-matches three rows; the plainest name wins.
        let answers = ConsultAnswers(["focus_lift": ["bench"]])
        XCTAssertEqual(answers.focusLift(in: catalog)?.name, "Bench Press")
    }

    func testAnAnswerThatMatchesNothingResolvesToNothing() {
        // Silently focusing the wrong lift is worse than focusing none,
        // because the athlete would never see it happen.
        XCTAssertNil(ConsultAnswers(["focus_lift": ["kettlebell juggling"]])
                        .focusLift(in: catalog))
    }

    func testATwoLetterAnswerIsNotEnoughToGuessFrom() {
        XCTAssertNil(ConsultAnswers(["focus_lift": ["sq"]]).focusLift(in: catalog))
    }

    func testAnAmbiguousShortestMatchResolvesToNothing() {
        // Two equally-plain candidates means we would be guessing.
        let ties = [exercise("Cable Fly", muscle: "chest"),
                    exercise("Cable Row", muscle: "back")]
        XCTAssertNil(ConsultAnswers(["focus_lift": ["cable"]]).focusLift(in: ties))
    }

    func testTheLiftsMuscleBecomesTheFocus() {
        let answers = ConsultAnswers(["focus_lift": ["Back Squat"]])
        XCTAssertEqual(answers.focusMuscles(in: catalog), ["quads"])
    }

    func testAnUnresolvableLiftAddsNoFocus() {
        XCTAssertNil(ConsultAnswers(["focus_lift": ["dragon flag"]])
                        .focusMuscles(in: catalog))
    }

    // MARK: - Focus survives to the program

    func testFocusAreasLandOnTheProfile() {
        let after = ConsultAnswers(["focus_areas": ["chest", "back"]]).apply(to: TrainingProfile())
        XCTAssertEqual(Set(after.focusMuscles ?? []), ["chest", "back"])
        XCTAssertEqual(after.provenance["focusMuscles"], .stated)
    }

    func testTheProfilesFocusReachesTheGenerator() {
        // The whole point: set once in the consult, still applying when
        // the wizard builds.
        var profile = TrainingProfile()
        profile.focusMuscles = ["glutes", "hamstrings"]
        let inputs = profile.generatorInputs(durationWeeks: 8)
        XCTAssertEqual(inputs.focusMuscles, ["glutes", "hamstrings"])
    }

    func testAnExplicitArgumentStillWins() {
        // A caller asking for a specific focus is not overridden by a
        // stored one.
        var profile = TrainingProfile()
        profile.focusMuscles = ["glutes"]
        let inputs = profile.generatorInputs(durationWeeks: 8, focusMuscles: ["chest"])
        XCTAssertEqual(inputs.focusMuscles, ["chest"])
    }

    func testNoFocusAnywhereStaysNil() {
        // nil and empty differ downstream: nil is "no preference", empty
        // would zero the standing bonus for every exercise.
        XCTAssertNil(TrainingProfile().generatorInputs(durationWeeks: 8).focusMuscles)
    }

    func testAConsultWithoutFocusDoesNotClearAnExistingOne() {
        var profile = TrainingProfile()
        profile.focusMuscles = ["chest"]
        let after = ConsultAnswers(["opener": ["size"]]).apply(to: profile)
        XCTAssertEqual(after.focusMuscles ?? [], ["chest"])
    }

    func testTheLiftAndTheAreasCombine() {
        // Someone chasing a bench number who also wants their back to look
        // different gets both, and the two-area cap still holds on the
        // areas themselves.
        let answers = ConsultAnswers([
            "focus_areas": ["back", "biceps", "calves"],
            "focus_lift": ["Back Squat"],
        ])
        let focus = answers.focusMuscles(in: catalog)
        XCTAssertEqual(focus, ["back", "biceps", "quads"])
    }

    func testTheSameMuscleIsNotCountedTwice() {
        let answers = ConsultAnswers([
            "focus_areas": ["chest"],
            "focus_lift": ["Bench Press"],
        ])
        XCTAssertEqual(answers.focusMuscles(in: catalog), ["chest"])
    }

    // MARK: - Old payloads

    func testAProfileSavedBeforeFocusExistedStillDecodes() throws {
        // Verifying the claim rather than asserting it in a comment:
        // TrainingProfile is stored as a JSON payload, and Swift's
        // synthesized decoder throws on a missing key for a NON-optional
        // property even when it has a default. focusMuscles is optional
        // for exactly this reason — strip the key and it must still load.
        let encoded = try JSONEncoder().encode(TrainingProfile())
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        // Give the profile a focus so the key is definitely present, then
        // prove its absence is survivable.
        var withFocus = TrainingProfile()
        withFocus.focusMuscles = ["chest"]
        let full = try JSONSerialization.jsonObject(
            with: try JSONEncoder().encode(withFocus)) as? [String: Any]
        XCTAssertNotNil(full?["focusMuscles"], "the key name changed; this test is now vacuous")

        object.removeValue(forKey: "focusMuscles")
        let stripped = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(TrainingProfile.self, from: stripped)
        XCTAssertNil(decoded.focusMuscles)
    }

    // MARK: - Truthful tunes

    func testNoProbeClaimsToWriteAFieldTheApplierIgnores() {
        // The audit that produced this file: focus_lift claimed
        // starredExerciseIDs and selectionTilt and wrote neither, `days`
        // claimed `split`, and two constraint probes claimed `exclusions`.
        // Downstream derivations are not writes.
        let ghosts: Set<String> = ["starredExerciseIDs", "selectionTilt", "split",
                                   "exclusions", "generatorFocus", "bandOverride"]
        for probe in [ConsultProbe.opener] + ConsultProbe.bank {
            let claimed = Set(probe.tunes).intersection(ghosts)
            XCTAssertTrue(claimed.isEmpty,
                          "\(probe.id) claims \(claimed.sorted()), which nothing writes")
        }
    }

    // MARK: - Multiple focus lifts by id (picker, 2026-08-27)

    func testFocusLiftsResolveByIDAndKeepOrder() {
        // Pin the fixture: `catalog` is computed and mints fresh ids on
        // every access, so two reads never share an id.
        let catalog = self.catalog
        let squat = catalog.first { $0.name == "Back Squat" }!
        let bench = catalog.first { $0.name == "Bench Press" }!
        let answers = ConsultAnswers(["focus_lift": [squat.id.uuidString, bench.id.uuidString]])
        XCTAssertEqual(answers.focusLifts(in: catalog).map(\.name), ["Back Squat", "Bench Press"])
        XCTAssertEqual(answers.focusLift(in: catalog)?.name, "Back Squat")
    }

    func testFocusLiftsLandOnTheProfileAsExerciseIDs() {
        let catalog = self.catalog
        let squat = catalog.first { $0.name == "Back Squat" }!
        let bench = catalog.first { $0.name == "Bench Press" }!
        let answers = ConsultAnswers(["focus_lift": [squat.id.uuidString, bench.id.uuidString]])
        let profile = answers.apply(to: TrainingProfile(), catalog: catalog)
        XCTAssertEqual(profile.focusExerciseIDs, [squat.id, bench.id])
        XCTAssertEqual(profile.provenance["focusExerciseIDs"], .stated)
        // Both muscles feed the focus set, not just the first lift's.
        XCTAssertEqual(Set(profile.focusMuscles ?? []),
                       Set([squat.primaryMuscle, bench.primaryMuscle]))
    }

    func testAnUnknownIDResolvesToNothingNotToAGuess() {
        let answers = ConsultAnswers(["focus_lift": [UUID().uuidString]])
        XCTAssertTrue(answers.focusLifts(in: catalog).isEmpty)
    }

    // MARK: - Injury severity (2026-08-27)

    func testAnInjuredJointLandsAsInjuredAndACautionStaysACaution() {
        let answers = ConsultAnswers([
            "cautions": ["hip", "knee"],
            "injury_severity": ["hip=severe"],
        ])
        let profile = answers.apply(to: TrainingProfile(), catalog: catalog)
        XCTAssertEqual(profile.cautionJoints, ["hip", "knee"])
        XCTAssertEqual(profile.injuredJoints, ["hip"])
        XCTAssertEqual(profile.provenance["injuredJoints"], .stated)
    }

    func testAJointNoLongerNamedIsNoLongerInjured() {
        // The probe is asked every consult with the known list
        // pre-selected; unticking a joint is the athlete saying it is
        // fine, and a joint that is fine cannot still be injured.
        var before = TrainingProfile()
        before.cautionJoints = ["hip", "knee"]
        before.injuredJoints = ["hip"]
        let answers = ConsultAnswers(["cautions": ["knee"]])
        let after = answers.apply(to: before, catalog: catalog)
        XCTAssertEqual(after.cautionJoints, ["knee"])
        XCTAssertTrue(after.injuredJoints.isEmpty)
    }
}
