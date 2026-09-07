import Foundation

// MARK: - The weekly goal's repository surface
//
// Plan: docs/superpowers/plans/2026-09-06-home-v3-production-plan.md, task
// 0.2. This file is HALF THE INTERFACE the four streams fork against:
// Stream B (Home in production) and Stream C (the editor and the strip's
// five kinds) wire to the protocol and to `WeeklyGoalProgress`; Stream A
// ships `LiveWeeklyGoalRepository` behind the same protocol, and
// integration task I1 swaps the default binding. Until then
// `StubWeeklyGoalRepository` is what everything sees — deterministic, no
// network, the design's own fixture numbers — so Home is correct and
// capturable at every point in the build rather than only at the end.

/// Reads and writes this week's goal.
///
/// `async` with no `throws`: every Home fetch in this app is best-effort and
/// returns an empty value rather than surfacing a failure into a tile (see
/// `SessionRepository`'s `try?` call sites), and the goal strip is no
/// different — a network blip must render the invitation, not an error.
protocol WeeklyGoalRepository: Sendable {
    func goal(weekStart: String) async -> WeeklyGoal?
    func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress
    @discardableResult func save(_ goal: WeeklyGoal) async -> Bool   // source = .user
    func clearToCoach(weekStart: String) async -> WeeklyGoal?        // LET COACH SET IT: delete + re-derive

    /// Detect and persist this week's goal when the read above found none
    /// (final review finding 1). Returns the goal now in effect.
    func detectIfMissing(weekStart: String) async -> WeeklyGoal?
}

/// A repository that cannot detect, does not detect.
///
/// nil is exactly the right answer for every FIXTURE binding:
/// `StubWeeklyGoalRepository` already returns a goal from
/// `goal(weekStart:)`, so Home never asks it — and if a future stub ever did
/// return nil, this default guarantees a catalog frame still cannot reach a
/// clock, a detector or a write. Only `LiveWeeklyGoalRepository` overrides
/// it.
///
/// Declared as a REQUIREMENT with a default rather than as an extension-only
/// member, so the call dispatches through the witness table: Home holds an
/// `any WeeklyGoalRepository`, and an extension-only method on an existential
/// would silently run the default even against the live repository.
extension WeeklyGoalRepository {
    func detectIfMissing(weekStart: String) async -> WeeklyGoal? { nil }
}

/// What the strip renders. Kind-agnostic on purpose: the strip switches on
/// `kind`, but the numbers are already resolved so no view does arithmetic.
///
/// This is the boundary Stream A's `WeeklyGoalProgressMath` writes and
/// Stream C's strip reads. A view that recomputed any of these would be a
/// second opinion about the same week, which is exactly what the design's
/// agreement law forbids.
struct WeeklyGoalProgress: Equatable, Sendable {
    struct Chip: Equatable, Sendable {
        let name: String        // e.g. "CHEST" — caller owns the caps
        let done: Double        // unrounded; the chip shows `Int(done.rounded())`
        let target: Double
        let isNext: Bool        // exactly one true, or none when all met
    }
    var chips: [Chip] = []              // muscleSets: up to 4 (the four LARGEST targets)
    var value: Double = 0               // distance / lift current / sessions done / days done
    var target: Double = 0
    var unitLabel: String = ""          // "mi" | "km" | "" — from ThemeStore.shared.weightUnit
    var met: Bool = false
    var rightHandRead: String = ""      // "1 SESSION LEFT" / "3 DAYS LEFT" — SAME week as the streak tile
    var kicker: String = ""             // "THIS WEEK · COACH'S GOAL" | "THIS WEEK · YOUR GOAL" | "GOAL MET · {n} DAYS LEFT"
}

// MARK: - The stub

/// The shipping default until Stream A's `LiveWeeklyGoalRepository` lands
/// (integration task I1).
///
/// Deterministic and hermetic: no `AppState`, no repository, no `Date.now`.
/// The numbers are the design's own — the addendum frames' chest 8/12, back
/// 10/12, legs 6/12 (the one furthest behind, so the one NEXT) and arms 8/8
/// (the one already met), so both states the muscle-sets chip can show are
/// on screen in one capture.
///
/// Those same four numbers also live in `HomeV2Fixtures.coachTargets`, which
/// feeds the 08a/08b catalog frames. They are deliberately two copies: the
/// approved frames must keep rendering what the owner approved even if the
/// production stub's fixture is later retuned, and coupling them would let
/// a change to one silently redraw the other.
struct StubWeeklyGoalRepository: WeeklyGoalRepository {

    /// A fixed id, so `WeeklyGoal.id` is stable across runs and a
    /// screenshot diff never trips on it. The fallback can only be reached
    /// by editing this literal into something that is not a UUID.
    static let fixtureUserID = UUID(uuidString: "00000000-0000-0000-0000-0000000000a1") ?? UUID()

    /// 2026-09-06T12:00:00Z. A fixture, not a clock.
    static let fixtureSetAt = Date(timeIntervalSince1970: 1_788_696_000)

    /// The design's four chips, in the order the strip renders them.
    static let fixtureChips: [WeeklyGoalProgress.Chip] = [
        .init(name: "CHEST", done: 8, target: 12, isNext: false),
        .init(name: "BACK", done: 10, target: 12, isNext: false),
        .init(name: "LEGS", done: 6, target: 12, isNext: true),
        .init(name: "ARMS", done: 8, target: 8, isNext: false),
    ]

    func goal(weekStart: String) async -> WeeklyGoal? {
        WeeklyGoal(userID: Self.fixtureUserID,
                   weekStartString: weekStart,
                   kind: .muscleSets,
                   params: WeeklyGoalParams(muscleTargets: ["chest": 12, "back": 12,
                                                           "legs": 12, "arms": 8],
                                            targetSource: "routines"),
                   source: .coach,
                   setAt: Self.fixtureSetAt)
    }

    func progress(for goal: WeeklyGoal) async -> WeeklyGoalProgress {
        WeeklyGoalProgress(chips: Self.fixtureChips,
                           met: false,
                           rightHandRead: "1 SESSION LEFT",
                           kicker: goal.source == .user
                               ? "THIS WEEK · YOUR GOAL"
                               : "THIS WEEK · COACH'S GOAL")
    }

    /// The stub stores nothing — a save "succeeds" so the editor's happy
    /// path is walkable, and the next `goal(weekStart:)` still returns the
    /// fixture. Persistence arrives with Stream A.
    @discardableResult
    func save(_ goal: WeeklyGoal) async -> Bool { true }

    func clearToCoach(weekStart: String) async -> WeeklyGoal? {
        await goal(weekStart: weekStart)
    }
}
