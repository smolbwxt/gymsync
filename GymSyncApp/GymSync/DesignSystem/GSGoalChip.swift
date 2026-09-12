import SwiftUI

/// One goal chip: the subject's name as a kicker, a 4 pt meter, the fraction
/// under it.
///
/// LIFTED VERBATIM from `HomeWeeklyGoalStrip.chipView(_:)` (plan task S2.3)
/// so the Home strip and the pump-check card render one chip rather than two
/// that look alike. Every literal here — 7 pt spacing, 9 pt tracked caps,
/// 12 pt tabular fraction, 8 pt padding, the 10 pt ring, the 4 pt track — is
/// the strip's, unchanged, because `app-home-v3-08a-targets-above-calendar`,
/// `-08b-targets-above-join` and `app-home-goal-strip-muscle-sets` are
/// owner-approved and must stay byte-identical.
///
/// The chips carry NO background fill, for the reason the strip's own doc
/// comment gives: their siblings' chip pill is `theme.neutral300`, which on
/// Onyx IS the colour the meter's track uses, so a filled chip would erase
/// the meter it exists to show. Unfilled is also what design rule 1 asks of
/// chips — furniture stays flat.
struct GSGoalChip: View {
    @Environment(\.gsTheme) private var theme

    /// The subject, in caps — the caller owns the case.
    let name: String
    /// Unrounded; the chip shows `Int(done.rounded())`. A set credits
    /// fractionally (`MuscleGroup.credit`), and a lifter reads "9/12", never
    /// "8.5/12".
    let done: Double
    let target: Double
    /// The accent ring — design rule 2's "current item", the group furthest
    /// behind. The Home strip sets it; a finished post never does.
    var isNext: Bool = false
    /// The meter's fill, 0...1, when the fraction the NUMBERS print is not
    /// the fraction the METER draws. nil = `done / target`.
    ///
    /// Only the pump-check card passes this, and only for a span-above-a-
    /// floor kind: a `lift` rung prints `205 / 225` and must draw the share
    /// of the block's own span, or a goal reads 91 % done on the day it
    /// opened — the plausible-looking wrong answer the strip's "subject chip"
    /// note already records paying for once.
    var fill: Double? = nil

    /// The one green this codebase uses, in its "done" job (design rule 2).
    private static let green = Color.gsSuccess

    var body: some View {
        // MET NEEDS AT LEAST ONE REAL TARGET: a plain `done >= target` is
        // TRUE for a 0-target chip, so a group nobody is asking for drew a
        // green `0/0` and read as finished.
        let met = target > 0 && done >= target
        return VStack(alignment: .leading, spacing: 7) {
            Text(name)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            meter(met: met)

            Text("\(Int(done.rounded()))/\(Int(target.rounded()))")
                .font(GSFont.bold(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(met ? Self.green : theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(
            isNext
                ? RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.accent, lineWidth: 1.5)
                : nil
        )
    }

    /// Done over target, clamped to 0...1 — an overshoot draws a full meter
    /// rather than one that runs past its own track, and a target of zero
    /// draws an empty one instead of dividing by nothing. `fill` wins when
    /// the caller supplied one.
    ///
    /// INTERNAL, not private, ONLY so `GSGoalChipTests` can read it. This
    /// repo has no snapshot harness, so the one testable thing about a chip
    /// is the number its meter draws; making that number reachable is what
    /// keeps the `fill` override — the rule that stops a 205 → 225 lift
    /// drawing 91 % on day one — under test at all. Nothing outside the
    /// chip's own tests calls it.
    var fraction: Double {
        if let fill { return min(max(fill, 0), 1) }
        guard target > 0 else { return 0 }
        return min(max(done / target, 0), 1)
    }

    /// The 4 pt track and its fill, through a `GeometryReader` rather than a
    /// fixed width — a chip's width is a quarter of the page's, which is the
    /// device's, and nothing in a catalog fixture may assume one.
    private func meter(met: Bool) -> some View {
        let value = fraction
        return GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(theme.neutral300)
                if value > 0 {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(met ? Self.green : theme.text)
                        .frame(width: proxy.size.width * value)
                }
            }
        }
        .frame(height: 4)
    }
}
