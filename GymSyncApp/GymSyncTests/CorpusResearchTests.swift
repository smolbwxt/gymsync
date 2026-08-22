import XCTest
@testable import GymSync

/// The research library's retrieval, pinned: relevant findings surface,
/// irrelevant questions read as misses, confidence weights the tie.
final class CorpusResearchTests: XCTestCase {

    private let findings = [
        CorpusFinding(area: "smith", topic: "strength",
                      claim: "Force built on the smith machine rail is real muscle strength; only free-squat skill erodes without practice.",
                      basis: "experience", confidence: "strong"),
        CorpusFinding(area: "smith", topic: "cautions",
                      claim: "Smith machine pressing entrapment is worse than free weights since a pinned lifter cannot dump the bar.",
                      basis: "experience", confidence: "moderate"),
        CorpusFinding(area: "strength-accessories", topic: "necessity",
                      claim: "Triceps long head is shortchanged by pressing, so direct triceps work supports the bench lockout.",
                      basis: "mechanistic", confidence: "strong"),
        CorpusFinding(area: "doc:sport-prep-parameters", topic: "Baseball",
                      claim: "Arm care is a standing dose for throwers: cuff strength must rise alongside any velocity gain.",
                      basis: "synthesis", confidence: "strong"),
    ]

    func testRelevantQuestionSurfacesTheRightFinding() {
        let hits = CorpusResearchStore.search("are smith machines good for strength", in: findings)
        XCTAssertEqual(hits.first?.area, "smith")
        XCTAssertTrue(hits.first?.claim.contains("real muscle strength") ?? false)
    }

    func testTricepsQuestionFindsAccessoryFinding() {
        let hits = CorpusResearchStore.search("should I do direct triceps work for my bench", in: findings)
        XCTAssertTrue(hits.contains { $0.area == "strength-accessories" })
    }

    func testIrrelevantQuestionScoresBelowMissThreshold() {
        let score = CorpusResearchStore.bestScore(
            "what supplements help sleep quality insomnia melatonin", in: findings)
        XCTAssertLessThan(score, CorpusResearchStore.missThreshold,
                          "off-corpus questions must read as misses, not stretches")
    }

    func testEmptyQueryReturnsNothing() {
        XCTAssertTrue(CorpusResearchStore.search("the a is", in: findings).isEmpty)
    }
}
