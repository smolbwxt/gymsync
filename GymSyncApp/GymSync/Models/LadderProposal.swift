import Foundation

/// Coach's proposed re-ladder, before the athlete has said yes.
///
/// Spec §4 (docs/superpowers/specs/2026-09-12-group-session-and-lobby
/// -design.md): every change to weight, volume or sets is a suggestion. This
/// is the value that carries one, from `BlockGoalRepository.reLadderProposal`
/// to the consent card on Home and on the ladder page (plan task S2).
///
/// It is a VALUE, not a row. Spec §6: "the suggestion principle needs no new
/// table: proposals render from the values Coach would have written." It is
/// recomputed on every read and discarded when the athlete says Not today.
struct LadderProposal: Equatable, Sendable {
    let goalID: UUID
    /// The ladder as it stands — what "Not today" keeps.
    let current: Ladder
    /// The ladder Coach would write — what "Accept" applies.
    let proposed: Ladder
    /// Only the rungs whose target actually moved, ordered by `weekIndex`.
    /// Never empty: `reLadderProposal` returns nil rather than an empty
    /// proposal.
    let changed: [LadderRung]
    let derivedAt: Date
}

enum LadderProposalMath {

    /// The set count a rung is spelled with when the caller does not hold the
    /// block's template.
    ///
    /// **THE APP'S OWN FALLBACK, not a new number.**
    /// `LiveBlockGoalRepository.page(goalID:)` spells the whole ladder with
    /// `template?.weeks.first?.sets ?? 3` (`BlockGoalLiveRepository.swift:324`),
    /// so a card that cannot reach the template prints the same digit the page
    /// prints for a block whose template has gone missing. A caller that DOES
    /// hold the template passes `sets:` and the two surfaces agree exactly.
    static let defaultSets = 3

    /// The rungs whose **target** actually moved, ordered by `weekIndex`.
    ///
    /// **TARGET, not the whole rung** — and that is the difference between
    /// what Coach WRITES and what Coach OFFERS. `reLadder(goalID:)` persists
    /// every rung that differs in any field, status included, because a
    /// re-stamped status is a fact the ladder owes the athlete. A *proposal*
    /// is about the numbers: a card that said "Coach proposes a new ladder"
    /// because week 2 went from `current` to `met` would be proposing the
    /// calendar.
    ///
    /// Matched on `weekIndex` rather than on position, so a proposed ladder
    /// with a different rung count still diffs honestly; a proposed rung whose
    /// week has no standing counterpart is a change.
    static func changedRungs(current: Ladder, proposed: Ladder) -> [LadderRung] {
        let standing = Dictionary(current.rungs.map { ($0.weekIndex, $0.target) },
                                  uniquingKeysWith: { first, _ in first })
        return proposed.rungs
            .filter { standing[$0.weekIndex] != $0.target }
            .sorted { $0.weekIndex < $1.weekIndex }
    }

    /// The card's one sentence, in Coach's first person (design rule 7).
    ///
    /// One changed rung reads as the change; more than one reads as a count
    /// plus the nearest change, because a card that lists six weeks is a
    /// table and the ladder page is where a table belongs.
    ///
    /// The week numbers are `weekIndex + 1`, which is what `LadderRow`
    /// already prints (`LadderMath.page`, `LadderMath.swift:503`) — read, not
    /// assumed. The load carries the unit's own spelling (`WeightUnit.label`,
    /// `lbs` and not `lb`) and is converted for a kilo athlete, because a
    /// frozen "215 lbs" shown to somebody who lifts in kilos is a wrong
    /// number rather than a formatting nit.
    static func sentence(_ proposal: LadderProposal, unit: WeightUnit,
                         sets: Int = defaultSets) -> String {
        guard let nearest = proposal.changed.first,
              let last = proposal.changed.last else { return "" }
        let target = targetText(nearest.target, unit: unit, sets: sets)
        if proposal.changed.count == 1 {
            return "Week \(nearest.weekIndex + 1) becomes \(target)."
        }
        return "Weeks \(nearest.weekIndex + 1) to \(last.weekIndex + 1) move"
            + " — the next is \(target)."
    }

    /// A rung's target as the ladder page spells it, plus the unit.
    ///
    /// `LadderReadout.strengthRungText` is the app's one strength spelling —
    /// the ladder page and the schedule card both print it — so this appends
    /// the unit rather than re-deriving the phrase. It answers `—` for a
    /// target it cannot spell, which is `rungText`'s own glyph for "nothing to
    /// say", and the unit is NOT appended to that: `— lbs` is not a weight.
    ///
    /// A non-strength metric therefore reads "Week 4 becomes —." here. That is
    /// a known thin spot rather than a hidden one: the proposal carries a
    /// `GoalTarget` and no metric, and the alternative — a second copy of
    /// `LadderMath.rungText`'s eleven-way switch — is exactly the drift this
    /// task exists to remove.
    private static func targetText(_ target: GoalTarget, unit: WeightUnit,
                                   sets: Int) -> String {
        let spelled = LadderReadout.strengthRungText(target, sets: sets, unit: unit).text
        guard spelled != "—" else { return spelled }
        return "\(spelled) \(unit.label)"
    }
}
