import XCTest
@testable import GymSync

/// `SessionStyle`, its copy and its default law — plan task S1.
///
/// Nothing here renders. These are the values every later task in Phase B
/// types against, so the spellings are asserted as strings: a style whose
/// title drifts between the lobby card and the live body is a style the crew
/// cannot recognise as the one they chose.
final class SessionStyleTests: XCTestCase {

    // MARK: - The raw values
    //
    // These three strings ARE `sessions.style`'s CHECK
    // (`20260913000101_session_style_stations_round.sql`, plan task D1:
    // `CHECK (style IN ('rounds','freestyle','together'))`). A rename here is
    // a migration, not a refactor — which is exactly why the test spells them
    // out rather than deriving them from the cases.
    func testTheRawValuesAreTheColumnsCheck() {
        XCTAssertEqual(SessionStyle.rounds.rawValue, "rounds")
        XCTAssertEqual(SessionStyle.freestyle.rawValue, "freestyle")
        XCTAssertEqual(SessionStyle.together.rawValue, "together")
    }

    func testEveryStyleIsCaseIterableInTheOrderTheLobbyOffersThem() {
        XCTAssertEqual(SessionStyle.allCases, [.rounds, .freestyle, .together])
    }

    func testAStyleRoundTripsThroughItsRawValue() {
        for style in SessionStyle.allCases {
            XCTAssertEqual(SessionStyle(rawValue: style.rawValue), style)
        }
        XCTAssertNil(SessionStyle(rawValue: "sprints"))
    }

    // MARK: - The copy (design rule 9: sentence case for sentences)

    func testEachStyleCarriesItsTitle() {
        XCTAssertEqual(SessionStyle.rounds.copy.title, "Rounds")
        XCTAssertEqual(SessionStyle.freestyle.copy.title, "Freestyle")
        XCTAssertEqual(SessionStyle.together.copy.title, "Together")
    }

    /// The consequence line, one per style — what the crew is agreeing to,
    /// not what the feature is called. Spec §1's own sentences.
    func testEachStyleCarriesItsConsequenceLine() {
        XCTAssertEqual(SessionStyle.rounds.copy.line,
                       "One set each. The round closes when the last lifter logs.")
        XCTAssertEqual(SessionStyle.freestyle.copy.line,
                       "Own pace, one shared rail — you finish together.")
        XCTAssertEqual(SessionStyle.together.copy.line,
                       "One clock for everyone. No turns.")
    }

    /// SF Symbols, never emoji (design rule 9).
    func testEachStyleCarriesADistinctGlyph() {
        XCTAssertEqual(SessionStyle.rounds.copy.glyph, "arrow.triangle.2.circlepath")
        XCTAssertEqual(SessionStyle.freestyle.copy.glyph, "arrow.left.and.right")
        XCTAssertEqual(SessionStyle.together.copy.glyph, "timer")
        XCTAssertEqual(Set(SessionStyle.allCases.map { $0.copy.glyph }).count, 3)
    }

    /// `SessionStyleCopy.of` and `SessionStyle.copy` must not become two
    /// vocabularies. One spelling, reachable two ways.
    func testTheConvenienceReadsTheSameCopy() {
        for style in SessionStyle.allCases {
            XCTAssertEqual(style.copy, SessionStyleCopy.of(style))
        }
    }

    // MARK: - The default law (the five data decisions, decision 2)
    //
    // There is no routine-type column (`20260709000005_create_routines.sql`
    // has none), so the default is derived from the routine's own rows:
    // `exercises.category` and `routine_exercises.cardio_minutes`.

    private func row(_ category: String, _ cardioMinutes: Int? = nil) -> (category: String, cardioMinutes: Int?) {
        (category: category, cardioMinutes: cardioMinutes)
    }

    func testAnAllCardioRoutineDefaultsToTogether() {
        XCTAssertEqual(SessionStyleDefault.style(forExercises: [row("cardio"), row("cardio")]), .together)
    }

    /// One prescribed cardio interval is enough — a routine that names
    /// minutes is a routine with a clock in it.
    func testAnyCardioMinutesDefaultsToTogether() {
        XCTAssertEqual(
            SessionStyleDefault.style(forExercises: [row("compound"), row("isolation", 12)]),
            .together
        )
    }

    func testAStrengthRoutineDefaultsToRounds() {
        XCTAssertEqual(
            SessionStyleDefault.style(forExercises: [row("compound"), row("compound"), row("isolation")]),
            .rounds
        )
    }

    /// Mobility rows are ignored, not counted against the cardio test — a
    /// warm-up hip opener must not stop an all-cardio routine defaulting to
    /// Together.
    func testMobilityRowsAreIgnored() {
        XCTAssertEqual(
            SessionStyleDefault.style(forExercises: [row("mobility"), row("cardio"), row("cardio")]),
            .together
        )
        XCTAssertEqual(
            SessionStyleDefault.style(forExercises: [row("mobility"), row("compound")]),
            .rounds
        )
    }

    /// Ignoring every row is not the same as "every row is cardio". A
    /// mobility-only routine has no cardio in it at all, so it is Rounds —
    /// the vacuous-truth reading would have made it Together.
    func testAMobilityOnlyRoutineIsRoundsNotTogether() {
        XCTAssertEqual(SessionStyleDefault.style(forExercises: [row("mobility"), row("mobility")]), .rounds)
    }

    /// A crew with no plan is a rack crew.
    func testAnEmptyRoutineDefaultsToRounds() {
        XCTAssertEqual(SessionStyleDefault.style(forExercises: []), .rounds)
    }

    /// Freestyle is never a default (owner decision 1 names defaults for
    /// strength and for cardio only). It is a choice the crew makes.
    func testFreestyleIsNeverADefault() {
        let inputs: [[(category: String, cardioMinutes: Int?)]] = [
            [],
            [row("compound")],
            [row("cardio")],
            [row("mobility")],
            [row("isolation", 20)],
            [row("cardio"), row("compound")]
        ]
        for input in inputs {
            XCTAssertNotEqual(SessionStyleDefault.style(forExercises: input), .freestyle)
        }
    }
}
