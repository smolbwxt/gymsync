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
///   * **met** (`target > 0 && done >= target`): the fraction and the meter
///     fill go green. Rule 2's green means done, and finishing a target is
///     the only "done" a chip of this kind has. The NAME stays as it is: a
///     green kicker over a green number states one fact twice. The `target
///     > 0` half is finding 12's: a chip that asks for nothing is not met.
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

    /// The chrome EVERY kind shares — the kicker row, then that kind's
    /// reading — hoisted here out of the muscle-sets body.
    ///
    /// Hoisting is this task's whole point, and it answers the Task 0
    /// review's first finding. The switch used to sit inside `body`'s
    /// padding, `surface` fill and 14 pt clip with a `default:` arm
    /// returning `EmptyView()`, so a `days` or a `distance` goal painted a
    /// full-width blank tappable bar carrying the accessibility label
    /// "This week's goal." and nothing else. Two changes make that state
    /// unreachable:
    ///
    ///   * the switch below is EXHAUSTIVE over `WeeklyGoalKind` with **no**
    ///     `default:`, so a sixth kind is a compile error rather than a
    ///     blank strip;
    ///   * the kicker row renders for every kind, so even an arm that has
    ///     nothing to draw yet still says what the strip is, how much week
    ///     is left, and that it opens.
    ///
    /// `kind == nil` keeps the invitation alone, without the kicker: there
    /// is no week's goal to name yet, and a kicker over an invitation would
    /// state a goal the user has not got.
    @ViewBuilder
    private var content: some View {
        if let kind = kind {
            VStack(alignment: .leading, spacing: 10) {
                kickerRow
                reading(for: kind)
            }
        } else {
            invitation
        }
    }

    /// One arm per kind, in `WeeklyGoalKind`'s own declaration order.
    ///
    /// The four empty arms are task **C2**'s (the design's §B table); C1 is
    /// the switch and the shared chrome. The Task 0 shell's marker named C1
    /// for both, which the review corrected: C1 is this structure, C2 is the
    /// renderings.
    @ViewBuilder
    private func reading(for kind: WeeklyGoalKind) -> some View {
        switch kind {
        case .muscleSets:     chipRow
        case .distance:       distanceBody
        case .sessionsOfType: sessionsBody
        case .days:           daysBody
        case .lift:           liftBody
        }
    }

    // MARK: - muscleSets

    /// `ForEach` over the chips' POSITIONS, because `WeeklyGoalProgress.Chip`
    /// is a resolved value type with no id: a block can track the same group
    /// twice (heavy and light weeks) so the name alone cannot key the row,
    /// and the array is rebuilt whole on every refresh so its order IS its
    /// identity.
    ///
    /// The row is the same `HStack(spacing: 8)` the shell shipped, one level
    /// shallower now that the `VStack` and the kicker above it belong to
    /// every kind. Nothing inside it moved, which is what keeps the approved
    /// 08a/08b frames byte-identical through this task.
    private var chipRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(progress.chips.enumerated()), id: \.offset) { _, chip in
                chipView(chip)
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
        // MET NEEDS AT LEAST ONE REAL TARGET (final review finding 12). A
        // plain `done >= target` is TRUE for a 0-target chip, so a group
        // nobody is asking for drew a green `0/0` and read as finished.
        // `WeeklyGoalProgressMath.muscleSetsProgress` guards the strip-level
        // `met` against exactly this and says why; the per-chip colour did
        // not get the same guard. Reachable through the editor's 0-stepper
        // and through a `volume_targets` deload row at `weekly_sets = 0`.
        let met = chip.target > 0 && chip.done >= chip.target
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

    // MARK: - The subject chip
    //
    // Four of the five kinds need one fact more than `value` and `target`
    // carry: WHICH activity is being run, WHICH kind of session is being
    // counted, and — for `lift` — a meter measured from the block's start
    // rather than from zero (the plan's A5 rule,
    // `(current − blockStart) / (target − blockStart)`, without which a
    // 205 → 225 goal draws a 91 % full meter on its first day).
    //
    // `WeeklyGoalProgress` is the frozen Task 0 interface and Stream A owns
    // its file, so rather than widen it this strip reads
    // `progress.chips.first` as the reading's SUBJECT:
    //
    //   * `name` NAMES it — `RUN` / `BIKE` / `ROW` / `WALK` choose the
    //     glyph; `HIIT` is printed as written after the count;
    //   * `done` / `target` give the METER its fill — the block-relative
    //     one for `lift`, and the same pair the reading prints for
    //     everything else.
    //
    // It is optional in both directions, and where it is absent the strip
    // shows an ABSENCE rather than a guess. No subject chip means no glyph
    // — not `figure.run` over a bike goal — and, for `lift`, an unfilled
    // meter rather than the 91 % a raw 205 / 225 draws on a block's first
    // day. Both of those were plausible-looking WRONG answers, which is a
    // harder failure to catch in a design round than a visible gap.
    // `distance` and `sessionsOfType` still fall back to `value` over
    // `target`, because for those two that IS the honest fraction, and the
    // noun is simply dropped.
    //
    // `days` does not depend on this slot at all — see `daysBody`.
    //
    // The contract is recorded here, in `streamC-report.md`, and (as of the
    // stream's first review) in the I1 hand-off, so A5/A6/A7 fill the slot
    // rather than guess at it. A `muscleSets` chip array — where
    // `chips.first` is CHEST, not a subject — never reaches these bodies:
    // `muscleSets` has its own arm and never asks for one.

    /// The reading's subject, when the caller supplied one.
    private var subject: WeeklyGoalProgress.Chip? { progress.chips.first }

    /// The reading's meter fill, 0...1 — the subject chip's when there is
    /// one, `value` over `target` otherwise.
    ///
    /// Guarded against a non-finite number as well as a zero denominator: a
    /// `NaN` here reaches `meter(fill:met:)`'s `frame(width:)` and takes the
    /// process down, which is a steep price for a division nobody watched.
    private var meterFraction: Double {
        if let subject = subject, subject.target > 0 {
            return Self.clamped(subject.done / subject.target)
        }
        // A lift's meter is measured from where the BLOCK started, and only
        // the subject chip carries that. Without it the honest drawing is an
        // empty track: `value / target` would report a 205 → 225 goal as
        // 91 % done on the day the block opened.
        if case .some(.lift) = kind { return 0 }
        guard progress.target > 0 else { return 0 }
        return Self.clamped(progress.value / progress.target)
    }

    private static func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }

    /// A reading's number: whole when it is whole (`15`), one decimal when
    /// it is not (`9.4`), an em dash when it is not a number at all. The one
    /// decimal is the design's own — `9.4 / 15 mi` — and sets, sessions and
    /// days are integers, so they print as integers without a special case.
    ///
    /// `String(format:)` with no locale argument formats POSIX, so the
    /// separator is a full stop on every device and a capture cannot drift
    /// on a French simulator.
    private static func number(_ value: Double) -> String {
        guard value.isFinite, abs(value) < 1_000_000 else { return "—" }
        let rounded = (value * 10).rounded() / 10
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        return String(format: "%.1f", rounded)
    }

    /// The unit beside a distance or a lift.
    ///
    /// `progress.unitLabel` is the authority when it is set: Stream A
    /// converts the VALUE into whatever `ThemeStore.shared.weightUnit` says
    /// (`Units.fromPounds` for a lift, `HKUnit` for a distance) and stamps
    /// the label it converted into, so the number and the word cannot
    /// disagree. Empty — the shell's default, and every fixture that
    /// predates Stream A — falls back to the setting itself, read exactly as
    /// owner answer 2 states it: **mi with lbs, km with kg** for a distance,
    /// and the weight unit's own label for a lift. Never a hard-coded "mi"
    /// or "lb".
    private var unitLabel: String {
        if !progress.unitLabel.isEmpty { return progress.unitLabel }
        let unit = ThemeStore.shared.weightUnit
        switch kind {
        case .some(.distance): return unit == .kg ? "km" : "mi"
        case .some(.lift):     return unit.label
        default:               return ""
        }
    }

    /// `9.4 / 15 mi`. The design writes the slash with spaces around it here
    /// and without them on a muscle chip (`8/12`), and both are kept as
    /// written: the chip is a quarter of the strip wide and the full-width
    /// reading is not.
    private func valueOverTarget(_ suffix: String) -> String {
        let read = "\(Self.number(progress.value)) / \(Self.number(progress.target))"
        return suffix.isEmpty ? read : read + " " + suffix
    }

    // MARK: - distance

    /// One full-width meter, the activity's glyph beside the reading under
    /// it. Meter above number, the order a muscle chip already uses, so the
    /// two kinds read the same way at a glance.
    ///
    /// The days remaining are NOT repeated here. The design's §B table names
    /// them ("`9.4 / 15 mi`, days remaining") and the kicker row already
    /// carries `progress.rightHandRead` at the trailing edge for every kind
    /// — printing them twice on a strip 24 pt tall would state one fact
    /// twice, which is the objection `HomeMilestoneTile` and `HomeV2World`'s
    /// own fixture notes keep raising.
    ///
    /// SF Symbols only, no emoji (design language rule 2).
    private var distanceBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            meter(fill: meterFraction, met: progress.met)

            HStack(spacing: 7) {
                if let activityGlyph = activityGlyph {
                    Image(systemName: activityGlyph)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }

                Text(valueOverTarget(unitLabel))
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .monospacedDigit()
                    .foregroundStyle(progress.met ? Self.green : theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
    }

    /// The four activities `WeeklyGoalParams.activity` documents, and **nil**
    /// for anything else.
    ///
    /// Nil rather than `figure.run`. A default glyph looks like an answer:
    /// a bike goal whose subject chip has not arrived would draw a runner,
    /// and nothing on the strip would say the app does not know. The reading
    /// beside it (`9.4 / 15 mi`) is true on its own, so the honest rendering
    /// of a missing activity is no activity.
    private var activityGlyph: String? {
        switch (subject?.name ?? "").lowercased() {
        case "run":  return "figure.run"
        case "bike": return "figure.outdoor.cycle"
        case "row":  return "figure.rower"
        case "walk": return "figure.walk"
        default:     return nil
        }
    }

    // MARK: - sessionsOfType

    /// `n` dots, filled as done, and `2 of 3 HIIT` under them.
    ///
    /// Dots rather than a meter because the count is small and countable:
    /// three sessions is a thing you can see, and a 66 %-full bar is not
    /// what anyone means by "two of the three".
    ///
    /// The dot count is CLAMPED to 14 — one every weekday and then some. It
    /// is a render guard, not a product rule: `target` arrives from a
    /// repository, and a bad row must cost the lifter a truncated row of
    /// dots rather than ten thousand circles inside a scroll view.
    private var sessionsBody: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(0..<dotCount, id: \.self) { index in
                    Circle()
                        .fill(index < filledDotCount
                              ? (progress.met ? Self.green : theme.text)
                              : theme.neutral300)
                        .frame(width: 10, height: 10)
                }
                Spacer(minLength: 0)
            }

            Text(sessionsLine)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(progress.met ? Self.green : theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var dotCount: Int {
        guard progress.target.isFinite else { return 0 }
        return max(0, min(14, Int(progress.target.rounded())))
    }

    private var filledDotCount: Int {
        guard progress.value.isFinite else { return 0 }
        return max(0, min(dotCount, Int(progress.value.rounded())))
    }

    /// `2 of 3 HIIT` — the design's line, with the noun dropped rather than
    /// invented when no subject chip names it.
    private var sessionsLine: String {
        let read = "\(Self.number(progress.value)) of \(Self.number(progress.target))"
        guard let name = subject?.name, !name.isEmpty else { return read }
        return read + " " + name
    }

    // MARK: - days

    /// The week's seven day chips — `HomeWeekDayChip`, the same view
    /// `HomeWeekStrip` draws, so Home's two week readouts are literally one
    /// view rather than two copies of one (the plan's own wording, and the
    /// reason task C2 extracted it).
    ///
    /// The chips come from `progress.chips`, one per day, which is how a
    /// per-day shape reaches a strip whose interface carries no calendar:
    /// `name` is the weekday letter, `done ≥ 1` means trained, `target ≥ 1`
    /// means something is booked, and `isNext` — "exactly one true", the
    /// field's own contract — is today.
    ///
    /// The precedence is today, then trained, then booked, then nothing.
    /// Today wins over trained because `HomeWeekStrip`'s own fixture already
    /// draws it that way (`soloDay` has four done days and Friday still
    /// reads `.today`): the ring is a statement about WHERE THE WEEK IS, and
    /// it disappearing the moment you train would remove the one chip a
    /// lifter scans for.
    ///
    /// The fraction at the trailing edge is the agreement law made visible:
    /// it is `HomeStreakTile`'s `daysDone / goal`, resolved upstream by A4
    /// from the same week, and it is a different fact from the kicker row's
    /// "3 DAYS LEFT" rather than a second telling of it.
    ///
    /// **This kind never depends on the subject-chip contract.** `days` is
    /// the one non-`muscleSets` kind the design's own phasing ships in
    /// Phase 1, and its entire rendering used to be the chips — so a Stream
    /// A that populated `value`/`target` and left `chips` empty, exactly as
    /// the frozen interface reads, would have reopened the blank-bar failure
    /// C1 exists to retire. With no chips the row is drawn from the FRACTION
    /// instead: seven chips, the first `value` of them filled. Rendered that
    /// way it says how many days are in the bank, which is what `value`
    /// means, and it does not claim WHICH days — the per-day shape and
    /// today's ring are exactly what only `chips` can carry.
    private var daysBody: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                if progress.chips.isEmpty {
                    ForEach(Array(Self.weekLetters.enumerated()), id: \.offset) { index, letter in
                        HomeWeekDayChip(letter: letter,
                                        state: index < daysDone ? .done : .empty)
                    }
                } else {
                    ForEach(Array(progress.chips.enumerated()), id: \.offset) { _, chip in
                        HomeWeekDayChip(letter: chip.name, state: Self.dayState(chip))
                    }
                }
            }

            Spacer(minLength: 6)

            Text("\(Self.number(progress.value))/\(Self.number(progress.target))")
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(progress.met ? Self.green : theme.text)
                .lineLimit(1)
        }
    }

    private static func dayState(_ chip: WeeklyGoalProgress.Chip) -> HomeWeekStrip.Day.State {
        if chip.isNext { return .today }
        if chip.done >= 1 { return .done }
        if chip.target >= 1 { return .planned }
        return .empty
    }

    /// Days in the bank, clamped to a week — the count the fraction-driven
    /// row fills.
    private var daysDone: Int {
        guard progress.value.isFinite else { return 0 }
        return max(0, min(7, Int(progress.value.rounded())))
    }

    /// The week's letters in the DEVICE calendar's order, for the row that
    /// has no chips to take them from.
    ///
    /// `Calendar.current`, not a hard-coded `M T W T F S S`: `WeekMath`'s own
    /// doc comment records the deliberate departure from ISO — Home's week is
    /// the device's week, honouring the user's `firstWeekday` — and a strip
    /// that labelled a Sunday-first week starting on Monday would contradict
    /// the streak tile beside it. Localized, because
    /// `veryShortWeekdaySymbols` is.
    ///
    /// No frame reaches this: every `days` fixture carries chips. It is the
    /// live fallback only.
    private static var weekLetters: [String] {
        let calendar = Calendar.current
        let symbols = calendar.veryShortWeekdaySymbols
        guard symbols.count == 7 else { return ["M", "T", "W", "T", "F", "S", "S"] }
        let offset = max(0, min(6, calendar.firstWeekday - 1))
        return Array(symbols[offset...]) + Array(symbols[..<offset])
    }

    // MARK: - lift

    /// `205 → 225 lb`, over a meter that starts where the block started.
    ///
    /// The arrow is U+2192 RIGHTWARDS ARROW, the design's own glyph, beside
    /// tabular digits. Two deliberate readings of the design here:
    ///
    ///   * the unit is printed (`205 → 225 lb`) where the design writes
    ///     `205 → 225`. Rule 3 gives a hero number "one small unit beside
    ///     it", and a bare 225 on a kg device would be read as pounds by
    ///     every lifter who has ever loaded a bar. The unit is never
    ///     hard-coded — see `unitLabel`.
    ///   * the WEEKS LEFT sit on the kicker row, once, for the same reason
    ///     the distance reading's days do.
    private var liftBody: some View {
        VStack(alignment: .leading, spacing: 7) {
            meter(fill: meterFraction, met: progress.met)

            Text(liftLine)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(progress.met ? Self.green : theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private var liftLine: String {
        let read = "\(Self.number(progress.value)) → \(Self.number(progress.target))"
        let unit = unitLabel
        return unit.isEmpty ? read : read + " " + unit
    }

    // MARK: - No goal yet

    /// The design's invitation, verbatim. Accent, because inviting is one of
    /// accent's jobs (design language rule 2) and this line is the only
    /// thing on the strip when there is nothing to read yet. One line, so
    /// the strip keeps a strip's height and the page below it does not jump
    /// when the first goal lands.
    ///
    /// **WHEN IT IS ACTUALLY SEEN, in the merged tree.** Not "every week
    /// Coach has not run for": `HomeView.fetchWeeklyGoal` detects on an empty
    /// read (final review finding 1) and the detector's rule 3 has no empty
    /// outcome, so what is left is signed out, a read that failed, a row this
    /// build cannot decode (`WeeklyGoalRow.model` answers nil for an unknown
    /// kind or source) and the one refresh in which the derive or its write
    /// did not land. Those are the states this line speaks for.
    ///
    /// **No chevron, deliberately.** The chevron lives on `kickerRow`, which
    /// this branch omits — so frame 89 is the one state with no door handle
    /// at the trailing edge. The `›` the design puts INSIDE the copy is the
    /// affordance here, and it is the design's own choice of one: the line
    /// reads "Set a goal for this week ›" precisely because there is nothing
    /// else on the strip for a chevron to sit beside. Two arrows on a
    /// fourteen-word strip would be the louder mistake.
    ///
    /// **`minHeight: 55`** (I1, controller ruling 3 / streamB-report.md
    /// finding 4): `HomeView.goalStripSkeleton` copies this strip's CHIP-ROW
    /// height, not the invitation's — see that skeleton's own doc comment
    /// for why — so a lifter with no goal yet got a page jump the very
    /// first time `goalLoaded` flips true. 55 is a chip's own height: 9 pt
    /// name + 7 pt spacing + 4 pt meter + 7 pt spacing + 12 pt fraction
    /// (= 39), plus the chip's 8 pt top and 8 pt bottom padding (= 16).
    private var invitation: some View {
        Text("Set a goal for this week ›")
            .font(GSFont.bold(13.5, relativeTo: .subheadline))
            .foregroundStyle(theme.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, minHeight: 55, alignment: .leading)
    }

    // MARK: - Accessibility

    /// One sentence per kind, then the week's remainder, then the door.
    ///
    /// Spelled out rather than derived from `progress.kicker`: the kicker is
    /// set in caps for the eye, and a synthesizer given "COACH'S GOAL" — or
    /// a `.capitalized` "Coach'S Goal" — reads the apostrophe out.
    ///
    /// `muscleSets` keeps the shell's wording character for character,
    /// including its "Opens the week by muscle." close, because that string
    /// shipped in task 0.3 and nothing about the chip row changed here. The
    /// four new kinds close on "Opens the goal editor.", which is what the
    /// tap now does for all five.
    private var accessibilityText: String {
        guard let kind = kind else {
            return "Set a goal for this week. Opens the goal editor."
        }
        if kind == .muscleSets {
            let parts = progress.chips.map { chip -> String in
                let read = "\(chip.name), \(Int(chip.done.rounded())) of \(Int(chip.target.rounded()))"
                if chip.done >= chip.target { return read + ", met" }
                if chip.isNext { return read + ", next" }
                return read
            }
            return "This week's goal. " + parts.joined(separator: ". ")
                + ". " + progress.rightHandRead.lowercased() + ". Opens the week by muscle."
        }
        return "This week's goal. " + spokenReading(for: kind) + metSuffix
            + ". " + progress.rightHandRead.lowercased() + ". Opens the goal editor."
    }

    /// The spoken form of the four non-chip readings. Deliberately NOT the
    /// rendered string: `→` is read as nothing by some voices and as
    /// "rightwards arrow" by others, and `9.4 / 15 mi` invites a synthesizer
    /// to say "nine point four slash".
    ///
    /// Named apart from the `reading(for:)` that returns a view rather than
    /// overloading it on the return type — an opaque `some View` and a
    /// `String` under one name is exactly the pair that produces "ambiguous
    /// use" at the first call site anyone edits.
    private func spokenReading(for kind: WeeklyGoalKind) -> String {
        let value = Self.number(progress.value)
        let target = Self.number(progress.target)
        switch kind {
        case .muscleSets:
            return ""
        case .distance:
            let unit = unitLabel
            return unit.isEmpty ? "\(value) of \(target)" : "\(value) of \(target) \(unit)"
        case .sessionsOfType:
            guard let name = subject?.name, !name.isEmpty else {
                return "\(value) of \(target) sessions"
            }
            return "\(value) of \(target) \(name)"
        case .days:
            return "\(value) of \(target) days"
        case .lift:
            let unit = unitLabel
            return unit.isEmpty ? "\(value) towards \(target)"
                                : "\(value) towards \(target) \(unit)"
        }
    }

    private var metSuffix: String { progress.met ? ", met" : "" }
}
