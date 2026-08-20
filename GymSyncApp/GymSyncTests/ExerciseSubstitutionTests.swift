import XCTest
@testable import GymSync

/// Pure coverage for the substitution graph — no network. The ranking is the
/// load-bearing part: a bad swap silently changes what a lifter trains, so
/// closest-equivalence must win and corroboration must break ties.
final class ExerciseSubstitutionTests: XCTestCase {

    private func edge(_ from: String, _ to: String,
                      equivalence: String = "partial",
                      trigger: String = "equipment",
                      basis: String = "mechanistic",
                      sources: Int = 1) -> ExerciseSubstitution {
        let json = """
        {"from_slug":"\(from)","to_slug":"\(to)","equivalence":"\(equivalence)",
         "trigger":"\(trigger)","reason":"r","basis":"\(basis)",
         "confidence":"moderate","sources":\(sources)}
        """
        return try! JSONDecoder().decode(ExerciseSubstitution.self,
                                         from: json.data(using: .utf8)!)
    }

    func testDecodesSnakeCaseFromServer() {
        let e = edge("back-squat", "leg-press")
        XCTAssertEqual(e.fromSlug, "back-squat")
        XCTAssertEqual(e.toSlug, "leg-press")
        XCTAssertEqual(e.id, "back-squat->leg-press")
    }

    func testFullEquivalenceOutranksPartial() {
        let index = SubstitutionGraph.index([
            edge("t-bar-row", "db-row", equivalence: "partial"),
            edge("t-bar-row", "chest-supported-row", equivalence: "full"),
        ])
        XCTAssertEqual(SubstitutionGraph.bestSwap(for: "t-bar-row", in: index)?.toSlug,
                       "chest-supported-row", "closest equivalence wins")
    }

    func testCorroborationBreaksTiesThenEvidenceQuality() {
        let index = SubstitutionGraph.index([
            edge("dip", "close-grip-bench", equivalence: "full", sources: 1),
            edge("dip", "jm-press", equivalence: "full", sources: 3),
        ])
        XCTAssertEqual(SubstitutionGraph.bestSwap(for: "dip", in: index)?.toSlug,
                       "jm-press", "more independent sources wins at equal equivalence")

        let byBasis = SubstitutionGraph.index([
            edge("curl", "hammer-curl", equivalence: "full", basis: "experience"),
            edge("curl", "incline-curl", equivalence: "full", basis: "cited_study"),
        ])
        XCTAssertEqual(SubstitutionGraph.bestSwap(for: "curl", in: byBasis)?.toSlug,
                       "incline-curl", "cited research beats coaching opinion")
    }

    func testRespectsWhatTheGymActuallyHas() {
        let index = SubstitutionGraph.index([
            edge("hack-squat", "leg-press", equivalence: "full"),
            edge("hack-squat", "goblet-squat", equivalence: "partial"),
        ])
        let swap = SubstitutionGraph.bestSwap(for: "hack-squat", in: index,
                                              availableSlugs: ["goblet-squat"])
        XCTAssertEqual(swap?.toSlug, "goblet-squat",
                       "the best swap you cannot perform is not a swap")
    }

    func testSituationalFilterExcludesProgrammingPreferences() {
        let index = SubstitutionGraph.index([
            edge("bench", "floor-press", equivalence: "full", trigger: "preference"),
            edge("bench", "db-press", equivalence: "partial", trigger: "crowding"),
        ])
        // Reacting to a taken machine: a preference edge is not an answer.
        let swap = SubstitutionGraph.bestSwap(for: "bench", in: index,
                                              situationalOnly: true)
        XCTAssertEqual(swap?.toSlug, "db-press")
        XCTAssertTrue(swap!.isSituational)
        // Without the filter, closest equivalence wins again.
        XCTAssertEqual(SubstitutionGraph.bestSwap(for: "bench", in: index)?.toSlug,
                       "floor-press")
    }

    func testUnknownExerciseYieldsNoSwap() {
        let index = SubstitutionGraph.index([edge("a", "b")])
        XCTAssertNil(SubstitutionGraph.bestSwap(for: "never-seen", in: index))
    }
}
