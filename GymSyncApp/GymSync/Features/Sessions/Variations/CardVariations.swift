#if DEBUG
import SwiftUI
import UIKit

// MARK: - The two cards
//
// The last two of the fourteen are not screens, they are objects that sit on
// screens: the crew's consensus swap, and the pump-check post re-composed on
// the design language. Both are rendered alone on the ground, the way
// `pump-composer-highlight` is, because what is being judged is the card.

// MARK: - 13 · the consensus swap

/// `swap-consensus-card` — the crew change of spec §3.4 mode 1, redesigned
/// as a **consent card**.
///
/// Spec §3.4: a change to the routine for everyone is proposed to the crew,
/// consensus sought, applied for all on acceptance — "this is what the
/// shipped `SwapProposal` / group swap sheet does; it stays, redesigned as a
/// consent card in the design language". Spec §4 makes the pattern binding:
/// every change to weight, volume or sets is a suggestion the athlete
/// accepts, and the consent card is the shape Coach chat already uses.
///
/// WHAT THE COMPOSITION ARGUES: a proposal is a sentence with a consequence,
/// so the card is read top to bottom as one — who is asking, what changes
/// (the old exercise struck through beside the new one, so the swap is a
/// picture and not a comparison you perform), how many have agreed, what
/// happens when they do, and only then the two answers. The consequence line
/// is not decoration: a consent card that does not say what accepting does
/// is a button with a story above it.
///
/// The count is four pips, not a bar. Two of four is a fact about PEOPLE and
/// a lifter should be able to count them; a meter turns a crew into a
/// percentage. Green fills an agreed pip — done or present, green's job.
///
/// ACCENT: Agree, the one primary. "Keep back squat" is the raised face, and
/// it says which exercise it keeps because a button says exactly what
/// happens (rule 9).
struct SwapConsensusCardView: View {
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
            swapLine
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

    /// The swap as a picture: what goes, then what arrives. The outgoing
    /// exercise is struck through in `neutral500` — no red, which is for
    /// errors only (rule 2), and a swap is not an error.
    private var swapLine: some View {
        HStack(spacing: 10) {
            Text(SVFixtures.swapFrom)
                .font(GSFont.bodyMedium(15, relativeTo: .headline))
                .strikethrough(true, color: theme.neutral500)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.neutral500)
            Text(SVFixtures.swapTo)
                .font(GSFont.bold(17, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .svStrip()
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

// MARK: - 14 · the pump-check card, re-composed

/// `pump-check-card-v2` — the shipped post card's **same seven lines**,
/// tightened onto the design language.
///
/// Spec §1's anatomy, unchanged and all present: 1 who and when, 2 the
/// trajectory, 3 this week's rung, 4 the highlight, 5 the workout in plain
/// terms, 6 the picture, 7 reactions. The VALUES are the ones
/// `pump-feed-post` already renders (`CatalogHostView.pumpFixtureSummary` /
/// `pumpFixtureTrajectory` / `pumpFixtureHighlight`), so the two frames are a
/// before/after of the composition and of nothing else.
///
/// WHAT THE COMPOSITION ARGUES — three moves, in order of how much they buy:
///
///  1. **The highlight leads, as a raised face.** In the shipped card line 4
///     is one bold sentence buried between the rung chips and the set rows.
///     It is the thing the lifter chose to say, so it becomes an island on
///     the card (rule 1's "a folder is a raised island") with the picture
///     beside it, and it is the first thing under the name.
///  2. **The picture is a thumbnail, not a block.** 300 pt of full-bleed
///     photo pushed reactions off the fold and made every card the same
///     height whatever it said. At 88 pt beside the highlight it still says
///     "there is a picture, here is what it looks like" and costs a fifth of
///     the page. Tapping it is where the full frame lives.
///  3. **The set rows collapse to one line.** Two exercises and three sets
///     were seven rows of furniture under the one sentence that mattered.
///     One line keeps every number and gives the trajectory strip room to be
///     read.
///
/// The card is about half its shipped height, and lines 2, 3, 4 and 7 are
/// all above the fold together — which is spec §1's whole claim for the
/// card, that it is "a snapshot of where people are in their fitness
/// trajectory".
///
/// **NO ACCENT, deliberately, and this breaks something — so it says so and
/// why** (design language's own rule for a proof). The shipped card spends
/// accent twice: a `PR` tag in the set rows and an accent fill on a reaction
/// you have already left. Neither is one of accent's four jobs (rule 2: the
/// primary action, an invitation line, the current pager item, the live talk
/// pill), and a finished post is none of those — the trajectory block's own
/// doc comment already argues exactly this for line 2 and then the rows
/// below it do the opposite. Here the PR is carried by the WORD, the way
/// line 4 is written, and a reaction of yours is marked by the raised face.
///
/// **The sound reactions are gone** (spec §5, owner decision 8): the
/// soundboard is tabled indefinitely, and the reaction vocabulary on a
/// pump-check post becomes emoji only. Emoji stay because they are content
/// (rule 2), which is the one place this round uses any.
///
/// The photo is `PumpComposerFixtures.photo` — the hermetic in-process tile
/// frame 102 already uses. The shipped card fetches a signed URL and gets
/// the honest placeholder in the harness; a frame whose whole argument is
/// the picture's SIZE cannot be judged from an empty box.
struct PumpCheckCardV2View: View {
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
            authorRow
            highlightFace
            trajectoryStrip
            plainTerms
            GSDivider()
            reactionsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// Line 1 — who and when.
    private var authorRow: some View {
        HStack(spacing: 9) {
            GSInitialsAvatar(name: SVFixtures.pumpAuthor, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(SVFixtures.pumpAuthor)
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(SVFixtures.pumpWhen)
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 6)
            GSTag(text: SVFixtures.pumpRetakeTag, style: .neutral)
            GSTag(text: SVFixtures.pumpLateTag, style: .neutral)
        }
    }

    /// Lines 4 and 6 — the pick the lifter made, and the picture, on one
    /// raised island.
    private var highlightFace: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                GSSectionHeader("THE ONE THING")
                Text(SVFixtures.pumpHighlight)
                    .font(GSFont.bold(17, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SVFixtures.pumpHighlightNote)
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                Spacer(minLength: 0)
                Text(SVFixtures.pumpDetail)
                    .font(GSFont.body(11.5, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
            photo
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
    }

    private var photo: some View {
        Image(uiImage: PumpComposerFixtures.photo)
            .resizable()
            .scaledToFill()
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Lines 2 and 3 — the trajectory and this week's rung. A STRIP, at 14 pt
    /// on `surface`, exactly as the shipped card renders it: the one thing
    /// about the shipped composition this frame does not touch, so the owner
    /// can see it is the same block in a different place.
    private var trajectoryStrip: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(SVFixtures.pumpTrajectory)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.neutral700)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
            HStack(spacing: 8) {
                ForEach(Array(SVFixtures.pumpChips.enumerated()), id: \.offset) { _, chip in
                    GSGoalChip(name: chip.name, done: chip.done, target: chip.target)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Line 5 — the workout in plain terms.
    private var plainTerms: some View {
        Text(SVFixtures.pumpPlain)
            .font(GSFont.body(11.5, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Line 7 — reactions. Emoji only (spec §5). A reaction of yours is the
    /// raised face; everyone else's is the flat ground.
    private var reactionsRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(SVFixtures.pumpReactions.enumerated()), id: \.offset) { _, reaction in
                chip(emoji: reaction.emoji, count: reaction.count)
            }
            Spacer(minLength: 0)
        }
    }

    /// `mine` is the first chip only, and it is pinned rather than a state:
    /// a catalog frame has no viewer.
    private func chip(emoji: String, count: Int) -> some View {
        let mine = emoji == SVFixtures.pumpReactions[0].emoji
        return HStack(spacing: 4) {
            Text(emoji).font(.system(size: 14))
            if count > 0 {
                Text("\(count)")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .monospacedDigit()
                    .foregroundStyle(theme.neutral700)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: GSMetrics.pill)
                .fill(mine ? theme.raised3DFace : theme.bg)
        )
        .overlay(chipBorder(mine: mine))
    }

    /// A `@ViewBuilder` rather than a `cond ? shape : nil` ternary: the
    /// nil-first spelling makes the shape's type ambiguous, and this frame
    /// cannot be compiled locally to find that out.
    @ViewBuilder
    private func chipBorder(mine: Bool) -> some View {
        if !mine {
            RoundedRectangle(cornerRadius: GSMetrics.pill)
                .strokeBorder(theme.divider, lineWidth: 1)
        }
    }
}
#endif
