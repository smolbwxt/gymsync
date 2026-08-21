import XCTest
@testable import GymSync

/// The attestation soft prior (owner ruling: an exercise nobody in the
/// research corpus teaches never outranks one everybody teaches). Each
/// law pinned: silence loses to any attestation regardless of score,
/// silent rows still fill a slot alone, and the 2-channel consensus bar
/// splits only the tiebreak below the score.
final class CorpusAttestationTests: XCTestCase {

    private func cat(_ rank: Int, _ name: String,
                     score: Int = 7, equip: String = "barbell")
        -> ProgramGenerator.CatalogExercise {
        var c = ProgramGenerator.CatalogExercise(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0004-%012d", rank))!,
            name: name, primaryMuscle: "quads", secondaryMuscles: [],
            category: "compound", equipment: equip, movementPattern: "squat",
            rank: rank)
        c.focusScores = ["strength": score, "hypertrophy": score]
        c.complexity = 2
        return c
    }

    private let slot = ProgramGenerator.Slot.pattern("squat", main: true)

    func testTableLoadedAndTiered() {
        XCTAssertGreaterThan(CorpusAttestation.channelCounts.count, 300)
        XCTAssertGreaterThanOrEqual(CorpusAttestation.channels(name: "Bench Press"), 2)
        XCTAssertEqual(CorpusAttestation.channels(name: "Sissy Squat"), 1)
        XCTAssertEqual(CorpusAttestation.channels(name: "Made Up Movement 9000"), 0)
    }

    func testSilentNeverOutranksAttestedWhateverTheScore() {
        // The failure this prior exists for: a silent row wearing an
        // inflated heuristic score outranking a corpus-vouched lift.
        let silent = cat(1, "Frankenstein Quad Blaster", score: 10)
        let attested = cat(2, "Back Squat", score: 6)
        let pick = ProgramGenerator.select(
            slot: slot, from: [silent, attested], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(pick?.name, "Back Squat",
                       "corpus silence must lose to attestation, score be damned")
    }

    func testSilentRowsStillFillASlotAlone() {
        // Soft prior, never a filter — same never-leave-a-hole law as
        // the complexity gate.
        let silent = cat(1, "Frankenstein Quad Blaster", score: 4)
        let pick = ProgramGenerator.select(
            slot: slot, from: [silent], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(pick?.name, "Frankenstein Quad Blaster")
    }

    func testConsensusBarSplitsTiesNotRankings() {
        // Equal scores: strong (2+ channels) beats weak (1 channel)...
        let strong = cat(1, "Hack Squat", score: 7)
        let weak = cat(2, "Sissy Squat", score: 7)
        let tie = ProgramGenerator.select(
            slot: slot, from: [weak, strong], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(tie?.name, "Hack Squat",
                       "at equal score the consensus bar decides")
        // ...but a better-scoring weak row still wins: title mining
        // under-counts, so 1-vs-2 channels never overrides the score.
        let weakBetter = cat(3, "Sissy Squat", score: 9)
        let ranked = ProgramGenerator.select(
            slot: slot, from: [weakBetter, strong], excluding: [],
            focus: .strength, focusMuscles: nil, experience: .intermediate)
        XCTAssertEqual(ranked?.name, "Sissy Squat",
                       "the consensus bar is a tiebreak, not a ranking")
    }
}
