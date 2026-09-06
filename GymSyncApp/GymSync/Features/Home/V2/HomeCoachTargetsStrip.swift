import SwiftUI

/// What Coach is tracking this week, as a STRIP (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-addendum-targets-strip.md`).
///
/// The owner, on variation 08: "maybe above the join with code, we display
/// the weekly muscle group goals, or whatever goal the coach is tracking as
/// a strip?" — so the piece is named for its JOB rather than for today's
/// content. `COACH'S TARGETS` renders whatever the current block tracks;
/// per-muscle sets is only what that happens to be by default, which is why
/// the chip carries a `name` string rather than a muscle enum.
///
/// One row of four equal chips: the group's name as a kicker, a 4 pt meter,
/// the fraction under it. Two of the four say something more —
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
/// `met` is DERIVED and `next` is DECLARED, on purpose. A stored `.met` case
/// could disagree with the numbers beside it (`6/12`, "met"), the way
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
struct HomeCoachTargetsStrip: View {
    @Environment(\.gsTheme) private var theme

    /// One tracked group.
    struct Target: Identifiable {
        /// Stable id — a block can track the same group twice under two
        /// targets (heavy and light weeks), so the name alone cannot key a
        /// `ForEach`.
        let id: Int
        /// e.g. `CHEST`. Rendered as written: the fixture owns the caps, the
        /// same call every other kicker in this kit makes.
        let name: String
        /// Sets logged against this group so far this week.
        let done: Int
        /// Sets the block asks for.
        let target: Int
        /// The group furthest behind — exactly one per strip. See the type's
        /// doc comment for why this is declared rather than computed.
        let isNext: Bool
    }

    let targets: [Target]
    /// The kicker row's right-hand read, e.g. `2 SESSIONS LEFT` — how much
    /// of the week is left to move these numbers.
    let sessionsLeft: String
    /// Tap → the per-muscle week on Stats. Inert in the catalog (there is no
    /// navigation in a `CatalogHostView` frame), declared so the composition
    /// reads the way the shipped strip would.
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
            VStack(alignment: .leading, spacing: 10) {
                kickerRow

                HStack(spacing: 8) {
                    ForEach(targets) { target in
                        chip(target)
                    }
                }
            }
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

    /// What the strip is, on the left; how much week is left, on the right;
    /// the door handle at the trailing edge — `HomeCrewPulseStrip`'s and
    /// `HomeUpNextStrip`'s chevron, same size, same weight, same muted tint.
    private var kickerRow: some View {
        HStack(spacing: 8) {
            Text("THIS WEEK · COACH'S TARGETS")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 6)

            Text(sessionsLeft)
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
    private func chip(_ target: Target) -> some View {
        let met = target.done >= target.target
        return VStack(alignment: .leading, spacing: 7) {
            Text(target.name)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            meter(fill: fraction(of: target), met: met)

            Text("\(target.done)/\(target.target)")
                .font(GSFont.bold(12, relativeTo: .caption))
                .monospacedDigit()
                .foregroundStyle(met ? Self.green : theme.text)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .overlay(
            target.isNext
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
    private func fraction(of target: Target) -> Double {
        guard target.target > 0 else { return 0 }
        return min(max(Double(target.done) / Double(target.target), 0), 1)
    }

    private var accessibilityText: String {
        let parts = targets.map { target -> String in
            let read = "\(target.name), \(target.done) of \(target.target)"
            if target.done >= target.target { return read + ", met" }
            if target.isNext { return read + ", next" }
            return read
        }
        return "This week, Coach's targets. " + parts.joined(separator: ". ")
            + ". " + sessionsLeft.lowercased() + ". Opens the week by muscle."
    }
}
