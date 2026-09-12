#if DEBUG
import SwiftUI

// MARK: - The warm-up screen, second pass
//
// The owner likes the warm-up screen as rendered and picked variation b's
// composition — the Coach suggestion as the plan card's second line. This
// pass expands what the day SHOWS without moving anything that was approved:
// the whole routine, and where the lifter is in the block. `warmup-solo-a`,
// `-b` and `warmup-crew` are untouched.

// MARK: - 122 · the whole day, and where it sits in the block

/// `warmup-solo-v2` — **variation b, told the whole truth about the day.**
///
/// b's argument survives intact and is still the first thing the frame
/// proves: the suggestion is a property of today's plan, so it lives inside
/// the plan card under a rule, and accepting visibly rewrites the card you
/// are looking at. What changes is what the card is ABOUT:
///
///  * **The whole routine, not the first line.** Four exercises with their
///    prescriptions, the rung line above them. A warm-up screen is the last
///    moment before the first set and the only screen where the lifter can
///    still change the shape of the hour; showing one exercise on it made
///    the decision look smaller than it is.
///  * **Where you are in the program**, as a ladder strip: eight rungs,
///    three behind you, the milestone with a flag at the end. The rung line
///    already said "week 3 of 8" in words; the strip says how much of the
///    block is left, which is the thing a lifter actually wants on the
///    morning they are being asked to drop to 3×5.
///
/// The two survivors are exactly the two the owner named: the warm-up clock
/// (still a strip at 22 pt, still not the hero — the hero is what you are
/// about to lift) and START LIFTING.
///
/// ACCENT: START LIFTING. Accept and Not today are raised faces, the ladder
/// is `text` over `neutral300`, the milestone flag is a neutral SF Symbol.
/// A block you are 3/8 of the way through is not an invitation and not an
/// achievement, and it gets no colour for being either.
struct WarmupSoloV2View: View {
    var body: some View {
        SVScrollScreen(kicker: "WARM-UP · SOLO", title: SVFixtures.soloSessionTitle) {
            SVPlanListCardWithSuggestion()

            SVProgramLadder(week: SVFixturesV2.programWeek,
                            weeks: SVFixturesV2.programWeeks,
                            milestone: SVFixturesV2.programMilestone)

            SVWarmupClock(elapsed: SVFixtures.warmupClock)
        } foot: {
            SVPrimary(title: "START LIFTING")
        }
    }
}

/// Variation b's plan card, holding the whole routine.
///
/// Not `SVPlanListCard` with a parameter bolted on: the suggestion's place
/// UNDER A RULE INSIDE THE CARD is variation b's entire argument, and a
/// boolean that moves it would let a later edit quietly turn b back into a.
/// The rows are the same rows and the same fixed 28 pt height, so the two
/// cards' columns line up when the owner puts the frames side by side.
struct SVPlanListCardWithSuggestion: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            header
            GSDivider()
            ForEach(SVFixturesV2.soloPlan) { row in
                planRow(row)
            }
            GSDivider().padding(.top, 3)
            SVSuggestionBody(suggestion: SVFixtures.soloSuggestion, isPrivate: false)
                .padding(.top, 6)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            GSSectionHeader("TODAY")
            Text(SVFixtures.soloRung)
                .font(GSFont.bold(19, relativeTo: .title3))
                .foregroundStyle(theme.text)
            Text(SVFixtures.soloRungDetail)
                .font(GSFont.body(12.5, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
        }
    }

    private func planRow(_ row: SVPlanRow) -> some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 2)
                .fill(row.isCurrent ? theme.text : Color.clear)
                .frame(width: 3, height: 16)
            Text(row.name)
                .font(row.isCurrent ? GSFont.bold(13.5, relativeTo: .subheadline)
                                    : GSFont.bodyMedium(13.5, relativeTo: .subheadline))
                .foregroundStyle(row.isCurrent ? theme.text : theme.neutral700)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 6)
            Text(row.prescription)
                .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.neutral500)
                .fixedSize()
        }
        .frame(height: 28)
    }
}
#endif
