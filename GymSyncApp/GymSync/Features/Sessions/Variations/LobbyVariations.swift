#if DEBUG
import SwiftUI

// MARK: - The crew lobby, three frames
//
// Spec §3.1: three things on the design language's surfaces — the roster as
// an arrival track (`ON THE WAY · AT THE GYM · CHECKED IN`, replacing the
// check-in chips), the talk dock, and Start — with the plan card above them
// so the crew sees what it is about to do. Gone from every frame here: the
// routine proposal-and-vote flow, the warm-up minutes stepper, and every
// soundboard reference (spec §5).
//
// The pair below differs in ONE decision and nothing else: whether arrival
// is a SEPARATE OBJECT above the roster, or a PROPERTY OF EACH PERSON in it.
// Same crew, same stages, same readiness, same plan card, same dock, same
// disabled Start with the same count. Nothing differs in colour.

// MARK: - 01 · the arrival rail

/// `lobby-crew-waiting-a` — **arrival is a journey, so it gets a track.**
///
/// The rail argues that what a waiting crew wants to know is not four
/// separate facts but one shape: how far the group has travelled. Three
/// stages left to right with the people standing in them; the roster
/// underneath is then free to say only the other thing that matters, which
/// is who has marked ready. Two objects, each with one job.
///
/// The cost the owner is being asked to price: a lifter's own stage is now
/// two objects away from their name, and an empty stage still holds a
/// column.
///
/// ACCENT: the disabled Start, and nothing else. (`PTTDockRow`'s small
/// resting waveform is the dock's own, on every shipped crew surface.)
struct LobbyCrewWaitingAView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                 title: SVFixtures.crewSessionTitle) {
            SVPlanCard(kicker: "THE PLAN",
                       title: SVFixtures.crewSessionRung,
                       detail: SVFixtures.blockLine)

            SVArrivalRail(lifters: SVFixtures.lobbyWaiting)

            SVRosterCard(lifters: SVFixtures.lobbyWaiting,
                         showsStage: false,
                         kicker: "READY TO START")
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi"])
            SVPrimary(title: "START", enabled: false, note: "2 of 4 ready")
        }
    }
}

// MARK: - 02 · the stage on the person

/// `lobby-crew-waiting-b` — **a stage belongs to the person, not to a
/// track.**
///
/// One object instead of two: each roster row carries its own stage chip
/// beside the name, so a lifter reads one line to learn both where somebody
/// is and whether they are ready. The screen loses a whole widget and the
/// plan card moves up the page with it.
///
/// The cost the owner is being asked to price: the crew's overall progress
/// is now something you count rather than something you see, and four chips
/// in a column is four times the chip.
///
/// ACCENT: the disabled Start, and nothing else — identical to a.
struct LobbyCrewWaitingBView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                 title: SVFixtures.crewSessionTitle) {
            SVPlanCard(kicker: "THE PLAN",
                       title: SVFixtures.crewSessionRung,
                       detail: SVFixtures.blockLine)

            SVRosterCard(lifters: SVFixtures.lobbyWaiting,
                         showsStage: true,
                         kicker: "WHO'S HERE")
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi"])
            SVPrimary(title: "START", enabled: false, note: "2 of 4 ready")
        }
    }
}

// MARK: - 03 · everyone is here

/// `lobby-crew-ready` — the state, not a third composition.
///
/// Built on variation **a** on purpose: the rail is the piece whose payoff
/// the owner cannot judge from one frame. Waiting, it is three occupied
/// columns; ready, it is one — every avatar collected in CHECKED IN and the
/// two earlier stages standing empty. If the rail does not earn its space
/// here it does not earn it at all.
///
/// Start is now the leader's tap (spec §3.1: the leader's tap, or consensus
/// when every checked-in lifter has marked ready). The note under it says
/// which of the two this is, because a leader pressing a button the crew
/// could have fired itself should know that.
///
/// ACCENT: Start, live this time — the screen's one accent act, and the
/// biggest thing on the page.
struct LobbyCrewReadyView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · \(SVFixtures.crewSessionWhen.uppercased())",
                 title: SVFixtures.crewSessionTitle) {
            SVPlanCard(kicker: "THE PLAN",
                       title: SVFixtures.crewSessionRung,
                       detail: SVFixtures.blockLine)

            SVArrivalRail(lifters: SVFixtures.lobbyReady)

            SVRosterCard(lifters: SVFixtures.lobbyReady,
                         showsStage: false,
                         kicker: "READY TO START")
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
            SVPrimary(title: "START",
                      enabled: true,
                      note: "Everyone's ready — yours to start, or it fires on its own")
        }
    }
}
#endif
