import SwiftUI

// MARK: - SwapConsentCard
//
// THE CREW'S ROUTINE CHANGE (spec §3.4 mode 1, plan task S1). The production
// twin of `swap-consensus-card-v2` (frame 125), captured as
// `session-swap-consent` (frame 142).
//
// It replaces `SessionLiveView.swapVoteBanner`, which printed one line
// ("Dana proposes back squat → goblet squat"), a bare count and two pills.
// You cannot consent to a swap you cannot look up: both exercises are now
// raised tappable rows that open the real exercise page, with the kickers
// NOW and PROPOSED carrying the direction the arrow used to carry alone.
//
// VALUE-IN (constraint 11). No repository, no `Date.now`, no environment
// beyond `gsTheme`: `SessionLiveView` builds the model from the same five
// sources the banner read, and the catalog builds it from
// `LiveFixtures.swapConsent`, so frame 142 renders the SHIPPING view.
//
// THE WIRE IS FROZEN (constraint 21). This file redraws the card and nothing
// else: `SessionBroadcastService.SwapEvent`'s four kinds, `evaluateUnanimity`
// (every PRESENT lifter said yes) and the proposal-expiry arming are
// untouched, and `onAgree`/`onKeep` are `castVote(true)` / `castVote(false)`.
//
// ACCENT: NONE (decision 3, rule 2). The design round's own tappable-swap
// card (retired, `Features/Sessions/Variations/`) painted Agree with
// `GSPrimaryButtonStyle`, which was correct for a frame rendered alone on
// its own page. In production this card is an OVERLAY on a live session page
// that has already spent its accent — the LOG card is the act of every
// style's page. So the answers are `GSConsentCard`'s pair: two raised faces,
// the word carrying which one is "yes". `GSConsentCard.swift:33-41` argues
// the identical departure for the ladder proposal.
//
// IT IS NOT A `GSConsentCard`, deliberately. That type takes
// `kicker`/`sentence`/`detail` strings and has no slot for two tappable rows
// or a pip meter, and its whole doc comment is about having exactly one
// composition. This is its SIBLING — same padding, same radius, same lip,
// same answer pair, built from the same primitives.

/// Every string this card prints, in one place, asserted by
/// `SwapConsentCopyTests`.
///
/// `GSConsentCopy.accept`'s discipline, applied to the crew's vocabulary:
/// copy that lives in a view body is copy nobody can review, and a second
/// spelling of "Agree" is a spelling that drifts.
enum SwapConsentCopy {
    /// Caps, over the proposer's sentence (rule 3).
    static let kicker = "CREW PROPOSAL"

    /// Who is asking, and of whom. "for everyone" is the whole difference
    /// between this and the quiet self-scale (spec §3.4 mode 2).
    static func proposal(by name: String) -> String {
        "\(name) proposes a change for everyone"
    }

    static let nowKicker = "NOW"
    static let proposedKicker = "PROPOSED"

    /// `2 of 4 agree` — tabular, beside the pips that count the same thing.
    static func agreement(agreed: Int, crew: Int) -> String {
        "\(agreed) of \(crew) agree"
    }

    /// What accepting does, AND what it leaves alone. A crewmate asked to
    /// agree to "a change for everyone" with no such assurance would
    /// reasonably read it as their own set being altered the moment they tap.
    static let consequence =
        "It applies to everyone the moment the crew agrees. Until then your set is unchanged."

    /// A button says exactly what happens (rule 9).
    static let agree = "Agree"

    /// Declining is about THIS exercise, not about the notice — so it names
    /// the exercise the crew would keep.
    static func keep(_ exercise: String) -> String {
        "Keep \(exercise.lowercased())"
    }

    /// What stands in place of the answers once I have voted. The old banner
    /// showed a bare count and said nothing about what happens next.
    static let waiting = "Waiting on the crew"
}

/// The crew's proposed routine change, as a card you can look up.
struct SwapConsentCard: View {
    @Environment(\.gsTheme) private var theme

    struct Model: Equatable {
        /// First name — the card is read by people who know each other.
        let proposerName: String
        /// The kicker `NOW` row.
        let from: Door
        /// The kicker `PROPOSED` row.
        let to: Door
        /// How many pips are drawn: the PRESENT crew, which is exactly the
        /// set `evaluateUnanimity` requires to have said yes.
        let crewSize: Int
        /// How many are filled, in `Color.gsSuccess` — green means present or
        /// done (rule 2), and an agreement is both.
        let agreed: Int
        /// First names of everyone who has agreed, one trailing line.
        let agreedNames: [String]
        /// True once I have answered either way: the answers give way to
        /// `SwapConsentCopy.waiting`, because there is nothing left for me
        /// to do and a live pair of buttons would say otherwise.
        let iHaveAnswered: Bool
    }

    /// One exercise as a door.
    struct Door: Equatable {
        let exerciseID: UUID
        let name: String
        /// The load line — `4 × 5 @ 225`.
        let detail: String
        /// FALSE when the exercise is not in the catalog this client holds,
        /// in which case the row renders as a flat strip with no chevron: a
        /// door that opens nothing is worse than a line. Defaulted true so
        /// the ordinary case reads as the ordinary case.
        var opens: Bool = true
    }

    let model: Model
    var onOpen: (UUID) -> Void = { _ in }
    var onAgree: () -> Void = {}
    var onKeep: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            doors
            agreement
            Text(SwapConsentCopy.consequence)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
            answers
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    private var header: some View {
        HStack(spacing: 10) {
            GSInitialsAvatar(name: model.proposerName, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                GSSectionHeader(SwapConsentCopy.kicker)
                Text(SwapConsentCopy.proposal(by: model.proposerName))
                    .font(GSFont.bodyMedium(12.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// The two doors, and the arrow that says which way the swap runs. The
    /// arrow sits in a FIXED 22 pt slot so both rows keep the same edges as
    /// each other however long either name is.
    private var doors: some View {
        VStack(spacing: 0) {
            ExerciseDoorRow(kicker: SwapConsentCopy.nowKicker,
                            name: model.from.name,
                            detail: model.from.detail,
                            onTap: tap(model.from))
            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.neutral500)
                .frame(height: 22)
            ExerciseDoorRow(kicker: SwapConsentCopy.proposedKicker,
                            name: model.to.name,
                            detail: model.to.detail,
                            onTap: tap(model.to))
        }
    }

    /// Nil for a door this client cannot open, which is what makes the row a
    /// line instead of a button.
    private func tap(_ door: Door) -> (() -> Void)? {
        guard door.opens else { return nil }
        let exerciseID = door.exerciseID
        return { onOpen(exerciseID) }
    }

    private var agreement: some View {
        HStack(spacing: 10) {
            HStack(spacing: 5) {
                ForEach(0..<max(model.crewSize, 0), id: \.self) { index in
                    Circle()
                        .fill(index < model.agreed ? Color.gsSuccess : theme.neutral300)
                        .frame(width: 10, height: 10)
                }
            }
            Text(SwapConsentCopy.agreement(agreed: model.agreed, crew: model.crewSize))
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .monospacedDigit()
                .foregroundStyle(theme.text)
                .fixedSize()
            Spacer(minLength: 0)
            Text(model.agreedNames.joined(separator: ", "))
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
        }
    }

    /// Two raised faces, no accent — `GSConsentCard`'s pair, in the crew's
    /// words. Once I have answered they give way to one quiet line.
    @ViewBuilder
    private var answers: some View {
        if model.iHaveAnswered {
            Text(SwapConsentCopy.waiting)
                .font(GSFont.bold(12.5, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
        } else {
            HStack(spacing: 8) {
                pill(SwapConsentCopy.agree, action: onAgree)
                pill(SwapConsentCopy.keep(model.from.name), action: onKeep)
                // The pills hug their labels rather than splitting the width
                // — `GSConsentCard.pill`'s own reasoning, and the same face.
                Spacer(minLength: 0)
            }
        }
    }

    private func pill(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(GSFont.bold(12.5, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }
}

/// One exercise as a door: a kicker, the name, one detail line, a chevron.
///
/// The design round's tappable exercise row (retired, `Features/Sessions/
/// Variations/`), in production form. A raised tappable face rather than a
/// strip, because a sinking face is how this app says "press me"
/// (rule 1) — and with `onTap` nil it is a flat strip with no chevron, which
/// is what an exercise this client cannot open honestly looks like.
struct ExerciseDoorRow: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    let name: String
    let detail: String
    /// Nil renders the row as a flat strip: no chevron, no press.
    var onTap: (() -> Void)?

    var body: some View {
        if let onTap {
            Button(action: onTap) {
                content(isDoor: true)
            }
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
        } else {
            content(isDoor: false)
                .background(theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        }
    }

    private func content(isDoor: Bool) -> some View {
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
            if isDoor {
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
