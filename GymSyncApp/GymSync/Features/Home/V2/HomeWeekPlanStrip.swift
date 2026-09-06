import SwiftUI

/// The week as a PLAN rather than as a tally, as a STRIP (plan:
/// `docs/superpowers/plans/2026-09-06-home-v3-ten-variations.md`, "New
/// pieces").
///
/// Where `HomeWeekStrip` answers "how many did I do", this one answers
/// "which ones, and what's next": kicker `THIS WEEK`, then a named chip per
/// training day — the done ones ticked, the next one ringed in accent (the
/// invitation, rule 2), exactly the way `HomeStreakTile`'s slot grid rings
/// its next slot.
///
/// The done chips stay in the DEFAULT text colour rather than going green,
/// following `HomeWeekStrip`'s own reviewed decision: on a strip that also
/// carries an accent ring, a green fill turns three states into three
/// colours and the eye stops reading the row as a sequence.
///
/// The tick is an SF Symbol, not a `✓` character in the string — rule 2's
/// "SF Symbols for glyphs", and the same call `HomeCalendarCard` makes for
/// its `repeat` glyph.
///
/// A strip (rule 1): `surface` fill, 14 pt radius, no extrusion.
struct HomeWeekPlanStrip: View {
    @Environment(\.gsTheme) private var theme

    /// One planned training day.
    struct Entry: Identifiable {
        enum State {
            /// Already trained — the chip is ticked.
            case done
            /// The next one up — an accent ring, the invitation.
            case next
        }
        /// Stable id: two chips can carry the same words in a longer week.
        let id: Int
        /// e.g. `TUE PUSH`.
        let label: String
        let state: State
    }

    let entries: [Entry]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("THIS WEEK")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.2)
                .foregroundStyle(theme.neutral500)

            HStack(spacing: 8) {
                ForEach(entries) { entry in
                    chip(entry)
                }
                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: HomeV2Metrics.stripRadius))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let parts = entries.map { entry -> String in
            switch entry.state {
            case .done: return "\(entry.label), done"
            case .next: return "\(entry.label), next"
            }
        }
        return "This week. " + parts.joined(separator: ". ") + "."
    }

    @ViewBuilder
    private func chip(_ entry: Entry) -> some View {
        HStack(spacing: 5) {
            Text(entry.label)
            if case .done = entry.state {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
            }
        }
        .font(GSFont.bold(10, relativeTo: .caption2))
        .kerning(1.1)
        .lineLimit(1)
        .foregroundStyle(theme.text)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(theme.neutral300))
        .overlay(
            entry.isNext
                ? Capsule().strokeBorder(theme.accent, lineWidth: 1.5)
                : nil
        )
    }
}

private extension HomeWeekPlanStrip.Entry {
    var isNext: Bool {
        if case .next = state { return true }
        return false
    }
}
