import SwiftUI

// MARK: - RoundWaitView
//
// What a crewmate who is not lifting sees, in Rounds (plan task S6). The
// production twin of `round-wait-v2` (frame 123), captured as
// `session-round-wait` (frame 137).
//
// It replaces the spectate sister page, which plan task S4 deleted. The
// difference between the two is the whole point of spec §5: the old page
// showed a SCOREBOARD — who was lifting, who was done, a progress bar — and
// this one shows THE CREW, on the racks they are standing at, with the one
// thing the reader can act on (their own recovery) beside it.
//
// VALUE-IN (constraint 11). Every string, number and duration arrives
// already resolved: no repository, no clock, no `AppState`. `SessionLiveView`
// builds the models from state it already holds, and the catalog builds them
// from `LiveFixtures.roundWait`, so frame 137 renders the SHIPPING view
// rather than a mockup of it.
//
// ACCENT: the ring on the lifter whose turn it is, drawn by `StationCard`
// (rule 2). Nothing else here spends one — the foot's gated control is a
// raised neutral face, because the next act belongs to the crew; the Coach
// door is a strip, because a door that shouts on every screen stops being a
// door; the logged tick is `Color.gsSuccess`, which means done.

struct RoundWaitView: View {

    /// `PUSH CREW · ROUND 3` — `RoundCopy.kicker(crew:round:)`.
    let kicker: String
    /// `The round`.
    let title: String

    /// One card per rack, side by side at equal height — `StationCard`'s
    /// fixed slots are what makes "equal height" a property of the layout
    /// rather than a coincidence of who happens to carry a scale-down line.
    let stations: [StationCard.Model]

    let rest: RestModel

    /// THE SESSION · WHERE WE ARE (spec §2's "is the plan still achievable",
    /// answered by the exercises that are LEFT rather than by a volume total
    /// — the reference frame's own argument, and the owner's choice).
    let planKicker: String
    /// The routine's own name. Empty hides the line: the per-lifter rung is
    /// a later phase, and `LobbyView.planRungLine` says the same of itself.
    let rungLine: String
    let plan: [SessionPlanRow]

    /// Spec §3.6's one door in three places — the lobby's `CoachDoorRow`,
    /// with the lobby's own words.
    let coach: CoachDoorRow.Model

    /// The crew this round is still waiting on, first names. Empty means
    /// nobody is outstanding and the gated control does not render at all —
    /// a gate with nothing behind it is furniture.
    let waitingOn: [String]

    /// Other participants' names for the dock's transmit hero.
    var dockNames: [String] = []

    /// The four reaction pills (fix round 1 / F3). This screen is where the
    /// crew reaches them again after plan task S4 took the dock that carried
    /// them; empty draws no strip at all.
    var reactionEmojis: [String] = []

    /// The degraded banner and the first-run coach mark, above the dock
    /// (fix round 1 / F2, ruling R-B12).
    var voice: VoiceFoot = VoiceFoot()

    var onCoachTap: () -> Void = {}
    var onReaction: (String) -> Void = { _ in }

    var body: some View {
        RoundPage(kicker: kicker, title: title) {
            HStack(alignment: .top, spacing: 10) {
                ForEach(stations) { station in
                    StationCard(model: station)
                }
            }

            RestRecoveryCard(model: rest)

            SessionPlanCard(kicker: planKicker,
                            rungLine: rungLine,
                            rows: plan,
                            showsProgress: true)

            CoachDoorRow(coach, onTap: onCoachTap)
        } foot: {
            VoiceNotices(foot: voice)
            if !reactionEmojis.isEmpty {
                ReactionStrip(emojis: reactionEmojis, onTap: onReaction)
            }
            PTTDockRow(otherParticipantNames: dockNames, compact: false)
            if !waitingOn.isEmpty {
                GatedControl(title: RoundCopy.waitingOn(waitingOn))
            }
        }
    }
}
