import XCTest
@testable import GymSync

/// What the consult's chips say, and whether the words land.
///
/// The failure these guard against is quiet: a chip offering "lower back"
/// when the catalog labels it "low_back" produces a caution that writes
/// cleanly, reads back cleanly, and changes nothing — the athlete tells us
/// where it hurts and selection never hears it. Deriving the vocabulary
/// from the catalog is the fix; these tests are the proof it stays derived.
final class ConsultVocabularyTests: XCTestCase {

    private func exercise(_ name: String,
                          muscle: String = "chest",
                          pattern: String? = nil,
                          joints: [String]? = nil) -> Exercise {
        var e = Exercise(id: UUID(), name: name, slug: name.lowercased(),
                         category: "compound", primaryMuscle: muscle,
                         secondaryMuscles: [], equipment: "barbell",
                         defaultUnit: "lbs", demoVideoURL: nil)
        e.movementPattern = pattern
        e.jointStress = joints
        return e
    }

    private var catalog: [Exercise] {
        [
            exercise("Bench", pattern: "push_horizontal", joints: ["shoulder", "elbow"]),
            exercise("Squat", muscle: "quads", pattern: "squat", joints: ["knee"]),
            exercise("Deadlift", muscle: "hamstrings", pattern: "hinge",
                     joints: ["low_back", "knee"]),
            exercise("Curl", muscle: "biceps", pattern: "isolation"),
        ]
    }

    // MARK: - Derived vocabularies

    // The contract flipped 2026-08-27 (owner: "joints to avoid should be a
    // dropdown"). The pinned seven ARE the catalog's labels as measured
    // (shoulder 461 rows, lower_back 308, knee 240, elbow 179, wrist 170,
    // hip 115, ankle 2); anything else a loaded catalog carries appends
    // after them. Note this fixture says "low_back" - the real library
    // says "lower_back" - which is exactly the drift a derived-only list
    // would have offered as a chip on one device and not another.
    func testJointsArePinnedFirstAndTheCatalogsExtrasFollow() {
        XCTAssertEqual(ConsultVocabulary.joints(in: catalog),
                       ["shoulder", "lower_back", "knee", "elbow", "wrist", "hip", "ankle",
                        "low_back"])
    }

    func testEveryPinnedJointCarriesAPlainLanguageDetail() {
        let probe = ConsultProbe.bank.first { $0.id == "cautions" }!
        let options = ConsultVocabulary.options(for: probe, catalog: catalog)
        for joint in ConsultVocabulary.knownJoints {
            let option = options.first { $0.id == joint.id }
            XCTAssertEqual(option?.detail?.isEmpty, false,
                           "\(joint.id) has no detail - the picker replaces free text, so it must explain itself")
        }
    }

    func testJointsAreDeduplicatedAcrossExercises() {
        // "knee" appears on two lifts; the athlete should see one chip.
        XCTAssertEqual(ConsultVocabulary.joints(in: catalog).filter { $0 == "knee" }.count, 1)
    }

    func testPatternsComeFromTheCatalogToo() {
        XCTAssertEqual(ConsultVocabulary.patterns(in: catalog),
                       ["hinge", "isolation", "push_horizontal", "squat"])
    }

    func testAnUnlabelledCatalogStillOffersTheJointPickerButNoPatterns() {
        // Joints never fall to free text again: an empty or late catalog
        // used to turn the cautions probe into a text box, and a typed
        // "knees" never matched the label "knee". Patterns stay derived -
        // there is no pinned taxonomy for them.
        let bare = [exercise("Mystery")]
        XCTAssertEqual(ConsultVocabulary.joints(in: bare),
                       ConsultVocabulary.knownJoints.map(\.id))
        XCTAssertTrue(ConsultVocabulary.patterns(in: bare).isEmpty)
    }

    // MARK: - Chips vs free text

    func testEveryMultiSelectIDNamesARealProbe() {
        // A typo here would silently demote a multi-select probe to
        // single-choice, committing on the athlete's first tap.
        let ids = Set(([ConsultProbe.opener] + ConsultProbe.bank).map(\.id))
        for id in ConsultVocabulary.multiSelect {
            XCTAssertTrue(ids.contains(id), "multiSelect names '\(id)', which is not a probe")
        }
    }

    func testProbesWithoutChipsAllGetAWrittenPlaceholder() {
        // A bare cursor gets a bare answer. Every free-text probe must say
        // what shape of answer is useful.
        for probe in ConsultProbe.bank
        where ConsultVocabulary.options(for: probe, catalog: catalog).isEmpty {
            XCTAssertNotEqual(ConsultVocabulary.placeholder(for: probe.id),
                              "type your answer",
                              "\(probe.id) is free text with no example answer")
        }
    }

    func testTheClosedVocabularyProbesAllOfferChips() {
        for id in ["equipment", "focus_areas", "gym_comfort", "cautions", "wont_do", "days"] {
            guard let probe = ConsultProbe.bank.first(where: { $0.id == id }) else {
                return XCTFail("no probe named \(id)")
            }
            XCTAssertFalse(ConsultVocabulary.options(for: probe, catalog: catalog).isEmpty,
                           "\(id) fell through to free text")
        }
    }

    func testFocusChipsUseTheSameListTheCoverageCheckReads() {
        let probe = ConsultProbe.bank.first { $0.id == "focus_areas" }!
        let ids = ConsultVocabulary.options(for: probe, catalog: catalog).map(\.id)
        XCTAssertEqual(ids, GeneratorScience.majorMuscles)
    }

    func testEquipmentChipsUseTheClassesTheCatalogFiltersOn() {
        let probe = ConsultProbe.bank.first { $0.id == "equipment" }!
        let ids = ConsultVocabulary.options(for: probe, catalog: catalog).map(\.id)
        XCTAssertEqual(ids, Venue.equipmentClasses)
    }

    func testComfortChipsCarryTheirPlainLanguageDetail() {
        // These are answered by someone who may never have been in a gym.
        let probe = ConsultProbe.bank.first { $0.id == "gym_comfort" }!
        let options = ConsultVocabulary.options(for: probe, catalog: catalog)
        XCTAssertEqual(options.count, GeneratorScience.comfortProbes.count)
        XCTAssertTrue(options.allSatisfy { $0.detail?.isEmpty == false })
    }

    func testDayChipsReadAsDaysAndCoverTheWeek() {
        let probe = ConsultProbe.bank.first { $0.id == "days" }!
        let options = ConsultVocabulary.options(for: probe, catalog: catalog)
        XCTAssertEqual(options.count, 7)
        XCTAssertEqual(options.first?.label, "1 DAY")
        XCTAssertEqual(options.last?.label, "7 DAYS")
    }

    func testSlugsAreShownAsWordsNotAsSlugs() {
        XCTAssertEqual(ConsultVocabulary.display("push_horizontal"), "PUSH HORIZONTAL")
        XCTAssertEqual(ConsultVocabulary.display("low_back"), "LOW BACK")
    }

    // MARK: - Anchor parsing

    func testAnchorsParseFromHowSomeoneActuallyTypesThem() {
        XCTAssertEqual(ConsultVocabulary.parseAnchors("bench 135, squat 185"),
                       ["bench=135", "squat=185"])
    }

    func testMultiWordLiftNamesSurvive() {
        XCTAssertEqual(ConsultVocabulary.parseAnchors("overhead press 95"),
                       ["overhead_press=95"])
    }

    func testUnitsAfterTheNumberDoNotBreakIt() {
        XCTAssertEqual(ConsultVocabulary.parseAnchors("bench 135lbs"), ["bench=135"])
    }

    func testAChunkWithNoNumberIsDroppedNotStoredAtZero() {
        // The probe promises "if you've never done a lift, say so" — and a
        // zero anchor would seed the whole progression at nothing.
        XCTAssertEqual(ConsultVocabulary.parseAnchors("bench 135, never deadlifted"),
                       ["bench=135"])
        XCTAssertTrue(ConsultVocabulary.parseAnchors("I have no idea").isEmpty)
    }

    func testAZeroAnchorIsRefused() {
        XCTAssertTrue(ConsultVocabulary.parseAnchors("bench 0").isEmpty)
    }

    func testParsedAnchorsRoundTripIntoWeights() {
        // The pair form exists to be read back by ConsultAnswers; if these
        // two ever disagree the anchors silently vanish.
        let pairs = ConsultVocabulary.parseAnchors("bench 135, back squat 225")
        let anchors = ConsultAnswers(["anchor_lifts": pairs]).liftAnchors
        XCTAssertEqual(anchors["bench"], Decimal(135))
        XCTAssertEqual(anchors["back_squat"], Decimal(225))
    }
}
