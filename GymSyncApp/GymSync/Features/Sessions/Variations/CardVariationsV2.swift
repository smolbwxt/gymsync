#if DEBUG
import SwiftUI

// MARK: - The consensus swap, second pass
//
// The owner approved the card and asked for one change with a real
// consequence: both exercises are TAPPABLE and open their exercise pages, so
// the from → to line has to be reformatted into two clear tappable objects.
// The pips, the consequence line and Agree / Keep stay.
// `swap-consensus-card` is untouched and still renders beside this.

// MARK: - 125 · both exercises are doors

/// `swap-consensus-card-v2` — **you cannot consent to a swap you cannot look
/// up.**
///
/// Round 1 drew the swap as one line: the old exercise struck through, an
/// arrow, the new one in bold. It read well and it was inert. A crewmate
/// being asked to agree to a front squat may not know what a front squat
/// costs them, and the answer to that lives on the exercise page — so both
/// halves become raised tappable rows with their own chevrons, stacked, with
/// the arrow between them carrying the direction the strikethrough used to.
///
/// **Stacked rows, not two side-by-side cards.** Two cards would make the
/// swap a comparison you perform left-to-right and would halve the room each
/// name has; stacked rows keep the reading order (this is what we're on,
/// this is what's proposed), give each name the full width, and let each row
/// carry its own detail line — the load, and whose proposal it is.
///
/// **The strikethrough is gone with it.** A struck-through label reads as
/// disabled, and this row is now the most tappable thing on the card. The
/// kickers carry what the strikethrough carried: NOW and PROPOSED.
///
/// Everything else is round 1's, unchanged and in the same order: the
/// proposer's header, four countable pips over a meter, the consequence line
/// that says what accepting does, then the two answers.
///
/// ACCENT: Agree, the one primary. The two exercise rows are raised faces —
/// they are doors, and a door is not the screen's act (rule 4).
struct SwapConsensusCardV2View: View {
    @Environment(\.gsTheme) private var theme

    var body: some View {
        ScrollView {
            card.padding(16)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            swapRows
            agreement
            consequence
            answers
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            GSInitialsAvatar(name: SVFixtures.swapProposer, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                GSSectionHeader("CREW PROPOSAL")
                Text("\(SVFixtures.swapProposer) proposes a change for everyone")
                    .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The two doors, and the arrow that says which way the swap runs. The
    /// arrow sits in a fixed-height slot between them so both rows keep the
    /// same top and bottom edges as each other.
    private var swapRows: some View {
        VStack(spacing: 0) {
            SVTappableExerciseRow(kicker: "NOW",
                                  name: SVFixtures.swapFrom,
                                  detail: SVFixturesV2.swapNowDetail)
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.neutral500)
                .frame(height: 22)
            SVTappableExerciseRow(kicker: "PROPOSED",
                                  name: SVFixtures.swapTo,
                                  detail: SVFixturesV2.swapProposedDetail)
        }
    }

    private var agreement: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<SVFixtures.swapCrewSize, id: \.self) { index in
                    pip(filled: index < SVFixtures.swapAgreed)
                }
            }
            Text("\(SVFixtures.swapAgreed) of \(SVFixtures.swapCrewSize) agree")
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .fixedSize()
            Spacer(minLength: 0)
            Text(SVFixtures.swapAgreedBy.map(SVName.first).joined(separator: ", "))
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
        }
    }

    private func pip(filled: Bool) -> some View {
        Circle()
            .fill(filled ? Color.gsSuccess : theme.neutral300)
            .frame(width: 10, height: 10)
    }

    private var consequence: some View {
        Text("It applies to everyone the moment the crew agrees. Until then your set is unchanged.")
            .font(GSFont.body(12, relativeTo: .caption))
            .foregroundStyle(theme.neutral700)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var answers: some View {
        HStack(spacing: 10) {
            Button(action: {}) {
                Text("Agree")
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 12))

            SVQuietPill(title: "Keep \(SVFixtures.swapFrom.lowercased())")

            Spacer(minLength: 0)
        }
    }
}

/// One exercise as a door: a kicker, the name, one detail line, a chevron.
///
/// A raised tappable face (`gs3DCardStyle`) rather than a strip, because the
/// whole point of the change is that this is pressable and the round-1 line
/// was not — and a sinking face is how this app says "press me" (rule 1).
/// Both rows are built from the same constants, so the two kickers, the two
/// names and the two chevrons each line up.
struct SVTappableExerciseRow: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    let name: String
    let detail: String

    var body: some View {
        Button(action: {}) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    GSSectionHeader(kicker)
                    Text(name)
                        .font(GSFont.bold(17, relativeTo: .title3))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(detail)
                        .font(GSFont.body(11.5, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }
}
#endif
