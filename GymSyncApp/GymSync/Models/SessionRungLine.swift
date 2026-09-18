import Foundation

// MARK: - Today's rung, on the session screens (spec §2, §3.1)
//
// The lobby's plan card and the warm-up's both carried the same deferral in
// their own comments — "the routine's own name until the block's rung reaches
// this screen" — and this is the arrival. One resolver, so the two screens
// cannot word the same rung two ways.
//
// WHOSE RUNG: THE VIEWER'S OWN, on both screens. A crewmate's block goal is
// not readable (`block_goals` is owner-scoped), and the spec's line is "today's
// rung" on the card the viewer is reading, not a per-lifter column. Nobody
// should go looking for the crew's rungs here; there is no such read.
//
// THE READ ALREADY EXISTS in both callers: `BlockGoalRepository.activeGoal()`
// then `.page(goalID:)`, which is what `BlockLadderStrip` is already fed from
// on the warm-up. This adds no round trip to the warm-up and one to the lobby.
enum SessionRungLine {

    /// What a plan card prints above its rows: the rung as a line, and the
    /// implication under it when the rung has one.
    ///
    /// `detail` is `""` rather than nil because both cards branch on
    /// `isEmpty` — `SessionPlanCard` takes one string and `SessionPlanCard
    /// WithSuggestion` takes two, and neither has a nil case to render.
    struct Resolved: Equatable, Sendable {
        let line: String
        let detail: String
    }

    /// The ladder's own words for the week the page is on.
    ///
    /// `LadderRow.targetText` ("3 × 5 at 190") and `.implication`
    /// ("≈ 214 e1RM") are already worded by `LadderReadout`, which is what
    /// keeps a rung spelled identically on the ladder page, on the schedule
    /// card and here.
    ///
    /// THE FALLBACK IS TODAY'S BEHAVIOUR, UNCHANGED: no page, or a page with
    /// no row for its own week number, prints the routine's name and no
    /// detail — exactly what both screens printed before this existed. An
    /// empty routine name with no page gives `""`, which both cards already
    /// render as no line at all.
    static func resolve(page: LadderPageModel?, routineName: String) -> Resolved {
        guard let page,
              let row = page.rows.first(where: { $0.weekNumber == page.weekNumber })
        else {
            return Resolved(line: routineName, detail: "")
        }
        return Resolved(line: "Week \(row.weekNumber) · \(row.targetText)",
                        detail: row.implication ?? "")
    }
}
