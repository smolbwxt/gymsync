import Foundation

// MARK: - The Crews tab's fixture world
//
// Plan: docs/superpowers/plans/2026-09-11-social-cards-plan.md, task S1.6.
// HERMETIC (global constraint 7): integers, strings and two fixed dates, no
// AppState, no repository, no `Date.now`.
//
// FIXED GROUP IDS, because `GSGroupColor.color(for:)` and `.onColor(for:)`
// hash the group's id into the avatar's identity colour
// (`GSGroupColor.swift:33,44`) — a fresh UUID per run would repaint two tiles
// in every screenshot diff.
//
// TWO CREWS, and the difference between them is the whole frame: Push Crew
// has trained (a plate bar, a next lift, a crown), Sunday Squad has not (an
// empty sleeve, no lift scheduled, and NO honor line at all — spec §3's
// decay is the line's absence, never a line reading zero).
enum CrewsTabFixtures {

    static let pushCrewID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d1") ?? UUID()
    static let sundaySquadID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d2") ?? UUID()
    static let creatorID = UUID(uuidString: "00000000-0000-0000-0000-0000000000d3") ?? UUID()

    /// A calendar date at noon UTC from its COMPONENTS, the idiom
    /// `StubBlockGoalRepository.utcDate` records: an epoch literal is
    /// unreadable and therefore unreviewable, and noon survives a simulator
    /// anywhere from UTC-11 to UTC+11 printing the same weekday.
    private static func utcDate(year: Int, month: Int, day: Int, hour: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar.date(from: DateComponents(year: year, month: month,
                                                  day: day, hour: hour))
            ?? Date(timeIntervalSince1970: 0)
    }

    /// Thursday 2026-09-10, 18:30 UTC — the next lift the meta line names.
    static let nextLift = utcDate(year: 2026, month: 9, day: 10, hour: 18)
    static let createdAt = utcDate(year: 2026, month: 6, day: 1, hour: 12)

    static let groups: [GymGroup] = [
        GymGroup(id: pushCrewID, name: "Push Crew", avatarURL: nil,
                 createdBy: creatorID, createdAt: createdAt, kind: "crew"),
        GymGroup(id: sundaySquadID, name: "Sunday Squad", avatarURL: nil,
                 createdBy: creatorID, createdAt: createdAt, kind: "crew"),
    ]

    static let bars: [UUID: SocialTabView.CrewBarMeta] = [
        pushCrewID: .init(completedThisWeek: 4, plannedThisWeek: 5, nextLift: nextLift),
        sundaySquadID: .init(completedThisWeek: 0, plannedThisWeek: 0, nextLift: nil),
    ]

    /// Spec §3's own line, on the crew that has one.
    static let honors: [UUID: CrewHonor] = [
        pushCrewID: CrewHonor(username: "sam", sessions: 9),
    ]
}
