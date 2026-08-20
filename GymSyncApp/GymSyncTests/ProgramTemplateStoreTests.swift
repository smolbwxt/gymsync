import XCTest
@testable import GymSync

/// Coverage for the bridge between Coach-generated blocks and the program
/// progression machinery.
///
/// The bug this exists to prevent: `enrollment.template` used to resolve
/// against the three code-defined templates only, so an enrolled Coach block
/// returned nil and `WorkingWeight` rung 1 never fired — the block silently
/// ran as one static week for its whole duration.
final class ProgramTemplateStoreTests: XCTestCase {

    private func generatedRow(slug: String, sessions: Int = 3) -> ProgramTemplateRow {
        let json = """
        {"id":"\(UUID().uuidString)","slug":"\(slug)","name":"Coach · Strength",
         "summary":"generated","kind":"takeover","focus_kind":"strength",
         "sessions_per_week":\(sessions),"duration_weeks":8,"creator_id":null,
         "is_premium":false,"price_tier":null,"storekit_product_id":null,
         "owner_id":"\(UUID().uuidString)","created_at":"2026-08-17T00:00:00Z"}
        """
        return try! JSONDecoder().decode(ProgramTemplateRow.self,
                                         from: json.data(using: .utf8)!)
    }

    func testBundledTemplatesStillResolve() {
        XCTAssertNotNil(ProgramTemplate.bySlug("march-to-1rm"),
                        "the curated three must keep resolving through the store")
        XCTAssertNil(ProgramTemplate.bySlug("no-such-template"))
    }

    func testGeneratedTemplateResolvesAfterRegistration() {
        let slug = "coach-test-\(UUID().uuidString.prefix(8).lowercased())"
        XCTAssertNil(ProgramTemplate.bySlug(slug), "not registered yet")

        let weeks = [ProgramWeek(percentOfBaseline: 75, sets: 3, reps: 5),
                     ProgramWeek(percentOfBaseline: 80, sets: 3, reps: 5)]
        let template = ProgramTemplate(row: generatedRow(slug: slug), weeks: weeks)
        ProgramTemplateStore.shared.register([template])

        let resolved = ProgramTemplate.bySlug(slug)
        XCTAssertNotNil(resolved, "a generated block must resolve like any template")
        XCTAssertEqual(resolved?.weeks.count, 2)
        XCTAssertEqual(resolved?.sessionsPerWeek, 3)
        if case .generated = resolved!.focusRule {} else {
            XCTFail("generated blocks carry the .generated focus rule")
        }
    }

    func testRegistrationNeverOverwritesBundledTemplates() {
        let hijack = ProgramTemplate(row: generatedRow(slug: "march-to-1rm", sessions: 99),
                                     weeks: [ProgramWeek(sets: 1, reps: 1)])
        ProgramTemplateStore.shared.register([hijack])
        let bundled = ProgramTemplate.bySlug("march-to-1rm")
        XCTAssertEqual(bundled?.sessionsPerWeek, 3,
                       "code stays the source of truth for the curated three")
        XCTAssertEqual(bundled?.weeks.count, 8)
    }

    /// The payoff: an enrolled GENERATED block drives the weekly percent rung
    /// exactly like a bundled one. Before the bridge this returned nil and the
    /// suggestion fell through to plain history.
    func testGeneratedBlockDrivesWeeklyPercentSuggestion() throws {
        let slug = "coach-wave-\(UUID().uuidString.prefix(8).lowercased())"
        let liftID = UUID()
        // Week 2 asks for 80% of a 200 lb baseline -> 160 lb.
        let weeks = [ProgramWeek(percentOfBaseline: 70, sets: 3, reps: 5),
                     ProgramWeek(percentOfBaseline: 80, sets: 3, reps: 5)]
        ProgramTemplateStore.shared.register([
            ProgramTemplate(row: generatedRow(slug: slug), weeks: weeks)])

        // Enrollment started 7 days ago => currently in week 2.
        let started = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let day = ISO8601DateFormatter()
        day.formatOptions = [.withFullDate]
        let json = """
        {"id":"\(UUID().uuidString)","user_id":"\(UUID().uuidString)",
         "template_slug":"\(slug)",
         "focus":{"exercise_ids":["\(liftID.uuidString)"]},
         "baseline":{"\(liftID.uuidString.lowercased())":200},
         "started_on":"\(day.string(from: started))","weeks":2,
         "ended_at":null,"ended_reason":null,
         "created_at":"2026-08-17T00:00:00Z"}
        """
        let enrollment = try JSONDecoder().decode(
            ProgramEnrollment.self, from: json.data(using: .utf8)!)

        XCTAssertNotNil(enrollment.template,
                        "the generated template must resolve from the enrollment")

        let suggestion = WorkingWeight.suggest(
            exerciseID: liftID, targetReps: 5, routineTargetPounds: nil,
            history: [], lastSetPounds: nil, enrollment: enrollment)

        XCTAssertEqual(suggestion?.pounds, 160,
                       "week 2 of a generated block = 80% of the frozen baseline")
        if case .campaign(let percent, let week)? = suggestion?.source {
            XCTAssertEqual(percent, 80)
            XCTAssertEqual(week, 2)
        } else {
            XCTFail("the weekly-percent rung should own this suggestion")
        }
    }
}
