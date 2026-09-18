import SwiftUI

// MARK: - Freestyle
//
// Own pace, with glue (spec §3.3; plan task S10). The production twin of
// frame 116 (`freestyle-rail`), captured as `session-freestyle-rail` (141).
//
// UNLIKE THE OTHER THREE ROUND SCREENS, THIS ONE HAS NO FOOT OF ITS OWN.
// Freestyle logs discrete sets — the rail counts them — and that control
// already exists: `SessionLiveView`'s pinned `turnChrome`, gated by
// `logControlIsMine` (plan task S5's own change reads "in Freestyle and
// Together there is no turn to hold", so the button is live for everyone).
// `bottomChrome`'s gate (`style != .together, !showsCrewPage`) already
// includes Freestyle without any change — a second CTA here would be a
// second way to log the same set, and this page composes ABOVE
// `bottomChrome`'s pinned foot exactly the way `myTurnFixedPage` already
// does, rather than replacing it.
//
// "THE BUTTON IS LIVE FOR EVERYONE" WAS ONLY HALF TRUE UNTIL FIX ROUND 4
// (finding 1, ruling R-B21): `logControlIsMine` always read `true` here, but
// nothing on this page ever gave a lifter reps to enter, so the button's own
// `isDisabled` check never cleared. `entryCard` below is the fix — the SAME
// `turnEntryCard` the my-turn page mounts, handed in rather than redrawn —
// and `SessionLiveView.commitInlineLog`/`prefillLogInputs` are no longer
// gated on a turn this style never has.
//
// THE STRETCHED REST AND COACH'S ACCESSORY ARE BOTH SUGGESTIONS, NEVER
// APPLIED CHANGES (owner decision 4, spec §4, no exceptions). Accepting
// either does not extend a rest timer or add a row to the routine — there is
// neither a rest-target enforcement mechanism nor an accessory-adding one in
// this schema, and building either would be a feature this task was not
// asked for. Accept and Not today both simply acknowledge the suggestion and
// it stops showing, which is the honest whole of what "never applied" means
// here.

// MARK: - The pure law

/// Where a lifter stands against their own crew, in sets done — the law
/// behind the rail and behind which suggestion (if any) a lifter sees
/// (plan task S10).
enum FreestylePace {

    enum Standing: Equatable {
        /// Ahead of the crew's SLOWEST lifter by at least two sets.
        case ahead(by: Int)
        /// Behind the crew's FASTEST lifter by at least two sets.
        case behind(by: Int)
        /// Within one set of both ends — the crew the style is named for.
        case level
    }

    /// One lifter's raw count, in any order.
    struct Lifter: Equatable {
        let userID: UUID
        let setsDone: Int
    }

    /// Compared against the SLOWEST other lifter for "ahead" (the reason to
    /// stretch a rest is the crew's tail, not its average) and against the
    /// FASTEST other lifter for "behind" (the reason to say nothing is the
    /// crew's lead, not its average). A solo rotation — nobody else present —
    /// has no crew to be ahead or behind, so it is always level.
    static func standing(sets: [Lifter], for userID: UUID) -> Standing {
        guard let mine = sets.first(where: { $0.userID == userID })?.setsDone else { return .level }
        let others = sets.filter { $0.userID != userID }.map(\.setsDone)
        guard !others.isEmpty else { return .level }
        if let slowest = others.min(), mine - slowest >= 2 { return .ahead(by: mine - slowest) }
        if let fastest = others.max(), fastest - mine >= 2 { return .behind(by: fastest - mine) }
        return .level
    }

    /// One routine row that could be Coach's accessory suggestion — the
    /// plan's own data, never invented (`exercises.category`,
    /// `20260709000002:5`).
    struct AccessoryCandidate: Equatable {
        let id: UUID
        let name: String
        let category: String
        /// Already formatted — `SessionPlanRow.prescription(for:)`'s own law.
        let prescription: String
    }

    /// The first ISOLATION row this lifter has not started. `nil` when the
    /// routine carries none, or every one is already underway — a lifter
    /// with nothing left to suggest gets no suggestion, not a repeated one.
    static func accessorySuggestion(from candidates: [AccessoryCandidate],
                                    startedIDs: Set<UUID>) -> AccessoryCandidate? {
        candidates.first { $0.category.lowercased() == "isolation" && !startedIDs.contains($0.id) }
    }
}

// MARK: - The rail's own model

/// One lifter's mark on the shared rail — sets done over the routine's own
/// total, the one axis the whole card exists to draw (plan task S10).
struct FreestyleRailModel: Equatable {
    struct Lifter: Identifiable, Equatable {
        let id: UUID
        let name: String
        let isYou: Bool
        let setsDone: Int
    }

    let lifters: [Lifter]
    /// The routine's own total prescribed sets, summed across every
    /// exercise — the denominator every lifter's marker shares.
    let totalSets: Int
}

/// One suggestion the ahead lifter is offered, answered through the shipped
/// `GSConsentCard` (owner decision 4).
struct FreestyleSuggestion: Equatable {
    let kicker: String
    let sentence: String
}

// MARK: - The screen

/// `session-freestyle-rail` (frame 141).
///
/// The rail leads because it is the style's whole reason to exist — the crew
/// spread made visible as distance rather than as four private numbers.
/// Under it, the rest card says out loud what your own pace is doing; below
/// that, exactly one of three things follows: nothing (level), two
/// suggestions (ahead), or a stated wait with nothing to accept (behind).
///
/// ACCENT: none. This page's one accent act belongs to `turnChrome`'s log
/// control beneath it (rule 2); a suggestion is not the primary act of the
/// screen it sits on, the same reasoning `GSConsentCard`'s own doc comment
/// gives for the ladder proposal on Home.
struct FreestyleRailView: View {
    @Environment(\.gsTheme) private var theme

    let kicker: String
    let title: String
    let rail: FreestyleRailModel
    let restElapsed: String
    let standing: FreestylePace.Standing

    /// Present only while `standing` is `.ahead`.
    var stretchSuggestion: FreestyleSuggestion? = nil
    var accessorySuggestion: FreestyleSuggestion? = nil
    /// Present only while `standing` is `.behind`.
    var behindLine: String? = nil

    /// The reps/weight/RPE entry, mounted directly above the pinned LOG
    /// foot below this page (fix round 4 / finding 1, ruling R-B21). This
    /// page still draws no foot of its own — the header comment's "no CTA
    /// here" reasoning is unchanged — but before this it also drew nowhere
    /// for a lifter to enter the reps that foot's button needed, so the
    /// button rendered permanently disabled. `SessionLiveView` hands in the
    /// SAME `turnEntryCard` the my-turn page mounts, type-erased since this
    /// view takes no generic content parameter elsewhere — one view, one
    /// code path, regardless of which of the three styles is on screen.
    /// `nil` in the catalog, which draws the rail alone.
    var entryCard: AnyView? = nil

    var onAcceptStretch: () -> Void = {}
    var onDeclineStretch: () -> Void = {}
    var onAcceptAccessory: () -> Void = {}
    var onDeclineAccessory: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                railCard
                restCard
                if let stretchSuggestion {
                    consentCard(stretchSuggestion, onAccept: onAcceptStretch, onDecline: onDeclineStretch)
                }
                if let accessorySuggestion {
                    consentCard(accessorySuggestion, onAccept: onAcceptAccessory, onDecline: onDeclineAccessory)
                }
                if let behindLine {
                    Text(behindLine)
                        .font(GSFont.body(12.5, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .roundStrip()
                }
                if let entryCard {
                    entryCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollContentBackground(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            GSSectionHeader(kicker)
            Text(title)
                .font(GSFont.bold(26, relativeTo: .title2))
                .foregroundStyle(theme.text)
        }
    }

    private func consentCard(_ suggestion: FreestyleSuggestion,
                             onAccept: @escaping () -> Void,
                             onDecline: @escaping () -> Void) -> some View {
        GSConsentCard(kicker: suggestion.kicker,
                     sentence: suggestion.sentence,
                     acceptTitle: GSConsentCopy.accept,
                     declineTitle: GSConsentCopy.decline,
                     onAccept: onAccept,
                     onDecline: onDecline)
    }

    // MARK: The rail

    private var railCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                GSSectionHeader(RoundCopy.freestyleRailKicker)
                Spacer(minLength: 8)
                Text(RoundCopy.freestyleOfTotal(rail.totalSets))
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .tracking(0.8)
                    .foregroundStyle(theme.neutral700)
                    .fixedSize()
            }
            track
            HStack(spacing: 0) {
                ForEach(rail.lifters) { lifter in
                    legend(lifter)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
    }

    /// One track, four markers — the thing the rail exists to show is the
    /// GAP, which four separate meters would turn into four private facts.
    private var track: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(theme.neutral300)
                    .frame(height: 6)
                    .frame(maxHeight: .infinity, alignment: .center)
                ForEach(rail.lifters) { lifter in
                    marker(isYou: lifter.isYou)
                        .offset(x: offset(lifter.setsDone, width: proxy.size.width))
                }
            }
        }
        .frame(height: 26)
    }

    private func offset(_ done: Int, width: CGFloat) -> CGFloat {
        let fraction = rail.totalSets > 0
            ? min(max(Double(done) / Double(rail.totalSets), 0), 1) : 0
        return (width - 18) * CGFloat(fraction)
    }

    /// You are `text`, the crew is `neutral500` — not accent, this page
    /// spends none on a readout (rule 2).
    private func marker(isYou: Bool) -> some View {
        Circle()
            .fill(isYou ? theme.text : theme.neutral500)
            .frame(width: 18, height: 18)
            .overlay(Circle().strokeBorder(theme.raised3DFace, lineWidth: 2))
    }

    private func legend(_ lifter: FreestyleRailModel.Lifter) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text((lifter.isYou ? "You" : lifter.name).uppercased())
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.9)
                .foregroundStyle(lifter.isYou ? theme.text : theme.neutral500)
                .lineLimit(1)
            Text("\(lifter.setsDone)")
                .font(GSFont.bold(15, relativeTo: .headline))
                .monospacedDigit()
                .foregroundStyle(lifter.isYou ? theme.text : theme.neutral700)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: The rest

    private var restCard: some View {
        VStack(alignment: .leading, spacing: 1) {
            GSSectionHeader(RoundCopy.freestyleYourRest)
            Text(restElapsed)
                .font(GSFont.bold(26, relativeTo: .title2))
                .monospacedDigit()
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .roundStrip()
    }
}
