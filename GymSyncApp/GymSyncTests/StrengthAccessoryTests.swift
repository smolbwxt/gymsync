import XCTest
@testable import GymSync

/// The strength-accessory reversal (owner challenge + corpus pass
/// 2026-08-21): strength days carry up to TWO supportive isolations
/// from the assistance canon - never zero on an uncapped day, never
/// the full hypertrophy spread, never off-canon fluff.
final class StrengthAccessoryTests: XCTestCase {

    private func isolations(_ kind: GeneratorScience.DayKind) -> [String] {
        ProgramGenerator.slots(for: kind, focus: .strength).compactMap { slot in
            if case .isolation(let m) = slot { return m }
            return nil
        }
    }

    private func patterns(_ kind: GeneratorScience.DayKind) -> Int {
        ProgramGenerator.slots(for: kind, focus: .strength).filter { slot in
            if case .pattern = slot { return true }
            return false
        }.count
    }

    func testLowerDayCarriesHamstringsAndCoreNotCalves() {
        // The reported 3-exercise leg day: squat + hinge + lunge and
        // nothing else. Now: + hamstrings (biarticular cancellation in
        // squats) + core (the posterior-dominant weak point).
        XCTAssertEqual(isolations(.lower), ["hamstrings", "core"])
        XCTAssertEqual(patterns(.lower), 3, "mains untouched")
        XCTAssertEqual(isolations(.legs), ["hamstrings", "core"],
                       "calves and quads isolation stay hypertrophy's")
    }

    func testUpperDayCarriesTricepsNotBiceps() {
        // The owner's canonical example: triceps in isolation for the
        // lockout. Biceps stays a hypertrophy slot.
        XCTAssertEqual(isolations(.upper), ["triceps"])
    }

    func testSupportiveCapIsTwo() {
        for kind in [GeneratorScience.DayKind.lower, .legs, .upper, .push, .pull, .fullBody] {
            XCTAssertLessThanOrEqual(isolations(kind).count, 2,
                                     "\(kind): dose discipline, not exclusion")
        }
    }

    func testStrengthStillLeanerThanHypertrophy() {
        // The bar-first identity survives: strength trims relative to
        // hypertrophy, it just no longer amputates.
        for kind in [GeneratorScience.DayKind.lower, .legs, .upper] {
            let strength = ProgramGenerator.slots(for: kind, focus: .strength).count
            let hyper = ProgramGenerator.slots(for: kind, focus: .hypertrophy).count
            XCTAssertLessThan(strength, hyper, "\(kind)")
        }
    }
}
