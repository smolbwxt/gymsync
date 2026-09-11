import SwiftUI

// MARK: - LadderCard
//
// Spec §6: "The block's schedule page (`ProgramScheduleView`) gains the
// ladder card at the top, above 'Why this block', and keeps everything
// else." Plan: docs/superpowers/plans/2026-09-07-goal-first-programming
// -plan.md, task D4.
//
// THREE ROWS, NOT EIGHT. The schedule page is about the block's days; this
// card is a DOOR to the ladder, not a second ladder. The window is the
// current rung and the one either side of it — where you are, what you just
// did, what is next — and `LadderCardTests` owns it, because the windowing
// is the only thing here that can be wrong in a way a capture would not
// show.
//
// Every row draws through `LadderPageView`'s own status mapping. The card
// and the page must not disagree about what a met week looks like, and the
// cheapest way to guarantee that is to have one mapping.

struct LadderCard: View {

    /// Everything the ladder renders, already worded (task A12).
    let page: LadderPageModel
    /// The door's action — `LadderPageView`, for the goal this card is about.
    var onOpen: () -> Void = {}

    @Environment(\.gsTheme) private var theme

    /// A raised card that SINKS, because the whole of it is a door
    /// (design rule 1: the sinking tappable is for things you press). The
    /// rows inside stay flat — extrusion is spent on the object, not on
    /// every row in it.
    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 10) {
                header
                rows
                footer
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(page.headline). \(page.coachLine). Open the ladder.")
    }

    // MARK: The headline and Coach's standing line

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE GOAL")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
                Spacer()
                Text("WEEK \(page.weekNumber) OF \(page.weekCount)")
                    .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral500)
            }
            Text(page.headline)
                .font(GSFont.bold(18, relativeTo: .headline))
                .foregroundStyle(theme.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !page.coachLine.isEmpty {
                // Accent ONLY when the ladder cannot reach the milestone —
                // that line is an invitation to act, which is one of accent's
                // jobs (rule 2). "On track" is a readout.
                Text(page.coachLine)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(page.reachesMilestone ? theme.neutral700 : theme.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: The three rungs

    private var rows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Self.window(page.rows), id: \.weekNumber) { row in
                rungRow(row)
            }
        }
    }

    private func rungRow(_ row: LadderRow) -> some View {
        let style = LadderPageView.style(for: row.status, theme: theme)
        let kicker = LadderPageView.kicker(for: row.status, isDeload: row.isDeload)
        let word = LadderPageView.statusWord(for: row.status)
        return HStack(spacing: 8) {
            // Design rule 3's kicker law, through the same helper the page
            // uses — the card and the page must not disagree about what a
            // week number looks like any more than about what a met week
            // does.
            Text("WK \(row.weekNumber)")
                .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                .tracking(1.0)
                .foregroundStyle(LadderPageView.kickerInk(for: row.status, theme: theme))
                .frame(width: 46, alignment: .leading)
            Text(row.targetText)
                .font(GSFont.bold(13, relativeTo: .subheadline).monospacedDigit())
                .foregroundStyle(style.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            if !kicker.isEmpty {
                Text(kicker)
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 6)
            if !word.isEmpty {
                Text(word)
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(style.ink)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(ring(style))
    }

    @ViewBuilder
    private func ring(_ style: LadderPageView.RowStyle) -> some View {
        if let ring = style.ring {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(ring, lineWidth: 1.5)
        }
    }

    // MARK: The door

    private var footer: some View {
        HStack(spacing: 6) {
            Text("SEE THE LADDER")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(theme.neutral500)
        }
    }

    // MARK: - The window (LadderCardTests)

    /// The current rung and the one either side of it, clamped at both ends.
    ///
    /// A ladder with NO current rung — a block booked but not yet begun —
    /// windows from the start: the first three weeks are what is coming, and
    /// an empty card would be worse than an honest early one. A ladder of
    /// three or fewer rungs is already its own window.
    static func window(_ rows: [LadderRow]) -> [LadderRow] {
        guard rows.count > 3 else { return rows }
        let current = rows.firstIndex { $0.status == .current } ?? 0
        let start = min(max(0, current - 1), rows.count - 3)
        return Array(rows[start..<(start + 3)])
    }
}
