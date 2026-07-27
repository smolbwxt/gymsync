import XCTest
@testable import GymSync

/// Pure-function coverage for `ProgramMath` + bundled `ProgramTemplate`
/// integrity — no network/live-DB setUp (the BurpeeLedgerMathTests /
/// StatDerivationTests pattern). Spec: 2026-07-24-training-programs-design
/// .md "Testing" section.
final class ProgramMathTests: XCTestCase {

    private let cal = Calendar.current
    private func day(_ offset: Int, from start: Date) -> Date {
        cal.date(byAdding: .day, value: offset, to: start)!
    }
    private var start: Date { cal.startOfDay(for: Date(timeIntervalSince1970: 1_784_000_000)) }

    // MARK: - Week derivation

    func testCurrentWeekDerivation() {
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: start, calendar: cal), 1)
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: day(6, from: start), calendar: cal), 1)
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: day(7, from: start), calendar: cal), 2)
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: day(55, from: start), calendar: cal), 8)
        // Clamped at the final week even after the program has elapsed.
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: day(90, from: start), calendar: cal), 8)
        // A start date in the future still reads week 1, never 0/negative.
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: day(-3, from: start), calendar: cal), 1)
    }

    func testIsCompleteFlipsAfterFinalWeek() {
        XCTAssertFalse(ProgramMath.isComplete(startedOn: start, weeks: 8, now: day(55, from: start), calendar: cal))
        XCTAssertTrue(ProgramMath.isComplete(startedOn: start, weeks: 8, now: day(56, from: start), calendar: cal))
    }

    func testRepeatWeekShiftLowersDerivedWeek() {
        // The repeat-week action shifts started_on forward 7 days; the same
        // "now" then derives one week earlier — the whole mechanism.
        let now = day(21, from: start)  // week 4 of the original start
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: start, weeks: 8, now: now, calendar: cal), 4)
        let shifted = day(7, from: start)
        XCTAssertEqual(ProgramMath.currentWeek(startedOn: shifted, weeks: 8, now: now, calendar: cal), 3)
    }

    // MARK: - Week window + session counting

    func testWeekWindowAndSessionCounting() {
        let window = ProgramMath.weekWindow(startedOn: start, week: 3, calendar: cal)
        XCTAssertEqual(window.start, day(14, from: start))
        XCTAssertEqual(window.end, day(21, from: start))

        let completions = [
            day(14, from: start),            // in (window start is inclusive)
            day(20, from: start),            // in
            day(21, from: start),            // out (end exclusive)
            day(2, from: start),             // out (earlier week)
        ]
        XCTAssertEqual(ProgramMath.sessionsCompleted(completionDates: completions, window: window), 2)
    }

    // MARK: - Target weight (percent × frozen baseline, 5-lb rounding)

    func testTargetWeightRounding() {
        XCTAssertEqual(ProgramMath.targetWeight(percentOfBaseline: 80, baseline: 225), 180)
        // 87.5% × 225 = 196.875 → nearest 5 → 195
        XCTAssertEqual(ProgramMath.targetWeight(percentOfBaseline: 87.5, baseline: 225), 195)
        XCTAssertEqual(ProgramMath.targetWeight(percentOfBaseline: 60, baseline: 225), 135)
        XCTAssertNil(ProgramMath.targetWeight(percentOfBaseline: 80, baseline: 0))
    }

    // MARK: - Baseline from history (max Epley over qualifying sets)

    private func log(reps: Int?, weight: Decimal?, failed: Bool = false, penalty: Bool = false) -> SetLog {
        SetLog(id: UUID(), userID: UUID(), sessionID: UUID(), exerciseID: UUID(),
               setIndex: 1, reps: reps, weight: weight, rpe: nil,
               isFailed: failed, isPenalty: penalty, note: nil, loggedAt: .now)
    }

    /// Decimal division in Epley (reps/30) is non-terminating for most rep
    /// counts, so exact Decimal equality is fragile — compare through
    /// doubleValue with an accuracy window instead.
    private func assertDecimal(_ value: Decimal?, equals expected: Double,
                               file: StaticString = #filePath, line: UInt = #line) {
        guard let value else {
            XCTFail("expected \(expected), got nil", file: file, line: line)
            return
        }
        XCTAssertEqual(NSDecimalNumber(decimal: value).doubleValue, expected,
                       accuracy: 0.001, file: file, line: line)
    }

    func testBaselineFromHistoryPicksBestEpley() {
        let logs = [
            log(reps: 5, weight: 225),   // Epley 262.5 — the best
            log(reps: 1, weight: 245),   // Epley ≈ 253.2
            log(reps: 10, weight: 135),  // Epley 180
        ]
        assertDecimal(ProgramMath.baseline(fromHistory: logs), equals: 262.5)
    }

    func testBaselineExcludesDisqualifiedSets() {
        let logs = [
            log(reps: 1, weight: 500, failed: true),    // failed — excluded
            log(reps: 1, weight: 500, penalty: true),   // penalty — excluded
            log(reps: nil, weight: 500),                // no reps — excluded
            log(reps: 5, weight: nil),                  // no weight — excluded
            log(reps: 3, weight: 200),                  // Epley 220 — the only qualifier
        ]
        assertDecimal(ProgramMath.baseline(fromHistory: logs), equals: 220)
        XCTAssertNil(ProgramMath.baseline(fromHistory: []))
    }

    // MARK: - Prescription copy (the transparency doctrine's one-liner)

    func testPrescriptionText() {
        let percentWeek = ProgramWeek(percentOfBaseline: 82.5, sets: 3, reps: 5)
        XCTAssertEqual(ProgramMath.prescriptionText(week: percentWeek, baseline: 225),
                       "3×5 @ 82.5% → 185 lb")
        XCTAssertEqual(ProgramMath.prescriptionText(week: percentWeek, baseline: nil),
                       "3×5 @ 82.5%")
        let volumeWeek = ProgramWeek(sets: 4, reps: 10, note: "leave ~2 reps in reserve")
        XCTAssertEqual(ProgramMath.prescriptionText(week: volumeWeek, baseline: nil),
                       "4×10 · leave ~2 reps in reserve")
        let bareWeek = ProgramWeek(sets: 5, reps: 5)
        XCTAssertEqual(ProgramMath.prescriptionText(week: bareWeek, baseline: nil), "5×5")
    }

    func testTrimmedPercent() {
        XCTAssertEqual(ProgramMath.trimmedPercent(80), "80")
        XCTAssertEqual(ProgramMath.trimmedPercent(87.5), "87.5")
    }

    /// Units sweep: kg targets round in the KG grid (2.5 kg steps), not a
    /// converted 5 lb number — 82.5% of a 225 lb baseline is 84.2 kg raw,
    /// honest prescription 85 kg. (Converting the lbs-rounded 185 would
    /// print 83.9 kg — a number nobody programs.)
    func testPrescriptionTextKilograms() {
        let percentWeek = ProgramWeek(percentOfBaseline: 82.5, sets: 3, reps: 5)
        XCTAssertEqual(ProgramMath.prescriptionText(week: percentWeek, baseline: 225, unit: .kg),
                       "3×5 @ 82.5% → 85 kg")
        XCTAssertEqual(ProgramMath.prescriptionText(week: percentWeek, baseline: nil, unit: .kg),
                       "3×5 @ 82.5%")
    }

    // MARK: - Bundled template integrity (spec "Testing": every bundled
    // template's declared shape holds — a typo'd percent or a second
    // deload week fails here, not on a user's phone)

    func testTemplateIntegrity() {
        XCTAssertEqual(ProgramTemplate.all.count, 3)
        XCTAssertEqual(Set(ProgramTemplate.all.map(\.slug)).count, 3, "slugs must be unique")

        for template in ProgramTemplate.all {
            XCTAssertFalse(template.weeks.isEmpty, "\(template.slug): no weeks")
            XCTAssertGreaterThan(template.sessionsPerWeek, 0, "\(template.slug): sessionsPerWeek")
            for (i, week) in template.weeks.enumerated() {
                XCTAssertGreaterThan(week.sets, 0, "\(template.slug) week \(i + 1): sets")
                XCTAssertGreaterThan(week.reps, 0, "\(template.slug) week \(i + 1): reps")
                if let percent = week.percentOfBaseline {
                    XCTAssertTrue((40...100).contains(percent),
                                  "\(template.slug) week \(i + 1): percent \(percent) out of sane range")
                }
            }
            XCTAssertEqual(template.weeks.filter(\.isDeload).count, 1,
                           "\(template.slug): exactly one deload week")
        }

        XCTAssertEqual(ProgramTemplate.bySlug("march-to-1rm")?.weeks.count, 8)
        XCTAssertEqual(ProgramTemplate.bySlug("leg-strength-block")?.weeks.count, 6)
        XCTAssertEqual(ProgramTemplate.bySlug("hypertrophy-block")?.weeks.count, 8)
        XCTAssertNil(ProgramTemplate.bySlug("nope"))

        // The march's focus is a single lift and its test week has no
        // percent (note-driven); hypertrophy is entirely volume-driven.
        XCTAssertNil(ProgramTemplate.bySlug("march-to-1rm")?.weeks.last?.percentOfBaseline)
        XCTAssertTrue(ProgramTemplate.bySlug("hypertrophy-block")!.weeks.allSatisfy { $0.percentOfBaseline == nil })
    }
}
