import SwiftUI

/// This week's goal, as a STRIP (design:
/// `docs/superpowers/specs/2026-09-06-home-v3-production-and-weekly-goal
/// -design.md` §B; the piece began as `HomeCoachTargetsStrip` in
/// `docs/superpowers/plans/2026-09-06-home-v3-addendum-targets-strip.md`).
///
/// The owner, on variation 08: "maybe above the join with code, we display
/// the weekly muscle group goals, or whatever goal the coach is tracking as
/// a strip?" — so the piece was already named for its JOB rather than for
/// today's content. The design §A item 7 finishes that thought and renames
/// it: what it renders is THE WEEK'S GOAL, of which per-muscle sets is one
/// of five kinds. Hence `kind` + a pre-resolved `WeeklyGoalProgress` rather
/// than a list of muscle targets.
///
/// NO VIEW HERE DOES ARITHMETIC. Every number the strip shows is resolved
/// upstream (`WeeklyGoalProgressMath`, Stream A) and arrives in `progress`
/// — because the design's agreement law says this strip's right-hand read
/// and `HomeStreakTile`'s week must be the same week, and a strip that
/// recomputed either would be a second opinion about it.
///
/// One row of four equal chips for the muscle-sets kind: the group's name
/// as a kicker, a 4 pt meter, the fraction under it. Two of the four say
/// something more —
///
///   * **met** (`done >= target`): the fraction and the meter fill go green.
///     Rule 2's green means done, and finishing a target is the only "done"
///     a chip of this kind has. The NAME stays as it is: a green kicker over
///     a green number states one fact twice.
///   * **next** (the group furthest behind — exactly one): a 1.5 pt accent
///     ring, the same invitation `HomeWeekStrip` puts on today and
///     `HomeWeekPlanStrip` on the next session. The owner trains by "what's
///     fresh, what's next", so the strip has to answer the second half.
///
/// `met` is DERIVED and `isNext` is DECLARED, on purpose. A stored `.met`
/// case could disagree with the numbers beside it (`6/12`, "met"), the way
/// `HomeMilestoneTile` refuses to let its bar and its percentage drift; but
/// "furthest behind" is Coach's judgement, and a computed `argmin` here
/// would have to invent a tie-break rule that no one asked for.
///
/// The chips carry NO background fill. Their siblings' chip pill is
/// `theme.neutral300`, which on Onyx IS `surface2` (`GSTheme.swift:101`
/// says so) — the very colour the plan gives the meter track, so a filled
/// chip would erase the meter it exists to show. Unfilled is also what rule
/// 1 asks of chips: furniture stays flat.
///
/// A strip (rule 1): `surface` fill, 14 pt radius, no extrusion, because it
/// belongs to what it sits under. Tappable, with the chevron on the kicker
/// row rather than beside the chips — the row is the only line on this strip
/// that is about the strip as a whole.
struct HomeWeeklyGoalStrip: View {
    @Environment(\.gsTheme) private var theme

    /// Which of the five kinds this week's goal is, or **nil** when there is
    /// no goal row yet — the only state in which the strip shows the
    /// invitation instead of a reading.
    let kind: WeeklyGoalKind?
    /// Everything the strip renders, already resolved. See the type's doc
    /// comment in `Models/WeeklyGoalRepository.swift`.
    let progress: WeeklyGoalProgress
    /// Tap → the goal editor. Inert in the catalog (there is no navigation
    /// in a `CatalogHostView` frame), declared so the composition reads the
    /// way the shipped strip would.
    var action: () -> Void = {}

    /// The one green this codebase uses (`HomeStreakTile`, `HomeWeekStrip`,
    /// `HomeRecoveryStrip`, `HomeCalendarCard`'s `IN` chip) — here in its
    /// "done" job. Deliberately NOT a `Color.gsSuccess` token: that token
    /// does not exist on this branch, and minting one inside a catalog piece
    /// would put a design-system definition in the last place anyone would
    /// look for it.
    private static let green = Color.gsHex(0x2FA45C)

    var body: some View {
        Button(action: action) {
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    /// Two cases ship in this commit — the muscle-sets reading and the
    /// no-goal invitation — because they are the two Stream B composes
    /// against on day one. The other four kinds are Stream C's (task C1),
    /// and an `EmptyView` is the honest placeholder: a strip that guessed at
    /// a distance reading would be a design decision made by a scaffold.
    @ViewBuilder
    private var content: some View {
        switch kind {
        case .some(.muscleSets):
            muscleSetsBody
        case .none:
            invitation
        default:
            EmptyView()   // Stream C fills this in (task C1).
        }
    }

    // MARK: - muscleSets

    /// `ForEach` over the chips' POSITIONS, because `WeeklyGoalProgress.Chip`
    /// is a resolved value type with no id: a block can track the same group
    /// twice (heavy and light weeks) so the name alone cannot key the row,
    /// and the array is rebuilt whole on every refresh so its order IS its
    /// identity.
    private var muscleSetsBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            kickerRow

            HStack(spacing: 8) {
                ForEach(Array(progress.chips.enumerated()), id: \.offset) { _, chip in
                    chipView(chip)
                }
            }
        }
    }

    /// What the strip is, on the left; how much week is left, on the right;
    /// the door handle at the trailing edge — `HomeCrewPulseStrip`'s and
    /// `HomeUpNextStrip`'s chevron, same size, same weight, same muted tint.
    ///
    /// Both strings come from `progress`: the caller owes them agreement
    /// with whatever else on the page states the same week (`HomeStreakTile`
    /// does, on both addendum frames), and only the caller can see that
    /// page.
    private var kickerRow: some View {
        HStack(spacing: 8) {
            Text(progress.kicker)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            Text(progress.rightHandRead)
                .font(GSFont.bold(9.5, relativeTo: .caption2))
                .tracking(1.1)
                .monospacedDigit()
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
    }

    /// Equal widths come from `maxWidth: .infinity` on every chip inside one
    /// `HStack` — four chips, one 8 pt gap between each, and the row is the
    /// strip's width whatever the names are.
    ///
    /// `done` and `target` arrive as Doubles because a set credits
    /// fractionally (`MuscleGroup.credit`: 1.0 primary, a capped share per
    /// secondary group), and the chip rounds for display. A lifter reads
    /// "9/12", never "8.5/12" — the half-set is real accounting, not a
    /// number anyone counts in the gym.
    private func chipView(_ chip: WeeklyGoalProgress.Chip) -> some View {
        let met = chip.done >= chip.target
        return VStack(alignment: .leading, spacing: 7) {
            Text(chip.name)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            meter(fill: fraction(of: chip), met: met)

            Text("\(Int(chip.done.rounded()))/\(Int(chip.target.rounded()))")
                .font(GSFont.bold(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(met ? Self.green : theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(
            chip.isNext
                ? RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.accent, lineWidth: 1.5)
                : nil
        )
    }

    /// The 4 pt track and its fill. `GeometryReader` rather than a fixed
    /// width, the same call `HomeMilestoneTile.segment(fill:)` makes and for
    /// the same reason: a chip's width is a quarter of the page's, which is
    /// the device's, and nothing in a catalog fixture may assume one.
    private func meter(fill: Double, met: Bool) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.neutral300)
                if fill > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(met ? Self.green : theme.text)
                        .frame(width: proxy.size.width * fill)
                }
            }
        }
        .frame(height: 4)
    }

    /// Done over target, clamped to 0...1 — a group that overshoots draws a
    /// full meter rather than one that runs past its own track, and a target
    /// of zero (a group Coach is watching but not yet asking for) draws an
    /// empty one instead of dividing by nothing.
    private func fraction(of chip: WeeklyGoalProgress.Chip) -> Double {
        guard chip.target > 0 else { return 0 }
        return min(max(chip.done / chip.target, 0), 1)
    }

    // MARK: - No goal yet

    /// The design's invitation, verbatim. Accent, because inviting is one of
    /// accent's jobs (design language rule 2) and this line is the only
    /// thing on the strip when there is nothing to read yet. One line, so
    /// the strip keeps a strip's height and the page below it does not jump
    /// when the first goal lands.
    private var invitation: some View {
        Text("Set a goal for this week ›")
            .font(GSFont.bold(13.5, relativeTo: .subheadline))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Accessibility

    private var accessibilityText: String {
        guard let kind = kind else {
            return "Set a goal for this week. Opens the goal editor."
        }
        guard kind == .muscleSets else {
            // Stream C writes the per-kind read with its per-kind body.
            return "This week's goal."
        }
        let parts = progress.chips.map { chip -> String in
            let read = "\(chip.name), \(Int(chip.done.rounded())) of \(Int(chip.target.rounded()))"
            if chip.done >= chip.target { return read + ", met" }
            if chip.isNext { return read + ", next" }
            return read
        }
        // Spelled out rather than derived from `progress.kicker`: the kicker
        // is set in caps for the eye, and a synthesizer given "COACH'S GOAL"
        // — or a `.capitalized` "Coach'S Goal" — reads the apostrophe out.
        return "This week's goal. " + parts.joined(separator: ". ")
            + ". " + progress.rightHandRead.lowercased() + ". Opens the week by muscle."
    }
}
