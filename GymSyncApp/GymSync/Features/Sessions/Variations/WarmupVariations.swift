#if DEBUG
import SwiftUI

// MARK: - The warm-up screen, three frames
//
// Spec §2 and §3.2: warm-up is the first phase of EVERY session, solo or
// crew, on one shared screen — the plan card (today's rung when a program is
// running, with a swap control), one Coach line, and the move to lifting.
// Owner decision 3: solo has no lobby, so this screen is where solo's
// decision moments live. Owner decision 5: the crew warms up here, after
// Start, in the same screen's crew frame.
//
// The pair below asks one question: is the Coach suggestion a SEPARATE
// DECISION beside the plan, or a SECOND LINE OF the plan? Everything else —
// the rung, the clock, the primary, the copy — is identical.

/// The warm-up clock. A STRIP, at 22 pt, not a hero.
///
/// This is an argued choice and not a default: the hero number on a page is
/// the largest thing on it (rule 3), and on the warm-up screen the largest
/// thing should be what you are about to lift, not how long you have been
/// on the bike. Warm-up is a phase, not a number — which is exactly why spec
/// §3.1 deletes the lobby's warm-up minutes stepper. The clock is a readout.
struct SVWarmupClock: View {
    @Environment(\.gsTheme) private var theme

    let elapsed: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "timer")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(theme.neutral700)
            VStack(alignment: .leading, spacing: 1) {
                GSSectionHeader("WARMING UP")
                Text(elapsed)
                    .font(GSFont.bold(22, relativeTo: .title3))
                    .monospacedDigit()
                    .foregroundStyle(theme.text)
            }
            Spacer(minLength: 0)
            Text("No target. Go when you're ready.")
                .font(GSFont.body(11.5, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 128, alignment: .trailing)
        }
        .svStrip()
    }
}

// MARK: - 04 · the plan leads, the suggestion answers

/// `warmup-solo-a` — **the suggestion is its own decision, so it is its own
/// object.**
///
/// The plan card states today's rung and owns the swap control; Coach's line
/// sits under it as a strip with Accept and Not today. Ignoring the
/// suggestion leaves the plan card visibly untouched, which is the whole of
/// owner decision 4 rendered as layout: a suggestion is a thing beside your
/// plan until you accept it.
///
/// The cost the owner is being asked to price: two objects to read before
/// the button, and the suggestion is easy to scroll past.
///
/// ACCENT: START LIFTING. Accept is a raised face, deliberately — a page
/// never has two accent buttons (rule 2), and the physical act is the one
/// that gets it.
struct WarmupSoloAView: View {
    var body: some View {
        SVScreen(kicker: "WARM-UP · SOLO", title: SVFixtures.soloSessionTitle) {
            SVPlanCard(kicker: "TODAY'S RUNG",
                       title: SVFixtures.soloRung,
                       detail: SVFixtures.soloRungDetail)

            SVSuggestionStrip(suggestion: SVFixtures.soloSuggestion)

            SVWarmupClock(elapsed: SVFixtures.warmupClock)
        } foot: {
            SVPrimary(title: "START LIFTING")
        }
    }
}

// MARK: - 05 · the suggestion is the plan's second line

/// `warmup-solo-b` — **the suggestion is a property of today's plan, so it
/// lives in the plan card.**
///
/// One raised object holds the whole decision: the rung on top, a divider,
/// then Coach asking about it and the two words that answer. Accepting
/// visibly rewrites the card you are looking at, and there is exactly one
/// thing above the button.
///
/// The cost the owner is being asked to price: the card now carries two
/// ideas, and on a day with no suggestion it collapses to half its height —
/// so the page's rhythm changes with the weather.
///
/// ACCENT: START LIFTING, identical to a.
struct WarmupSoloBView: View {
    var body: some View {
        SVScreen(kicker: "WARM-UP · SOLO", title: SVFixtures.soloSessionTitle) {
            SVPlanCard(kicker: "TODAY'S RUNG",
                       title: SVFixtures.soloRung,
                       detail: SVFixtures.soloRungDetail,
                       suggestion: SVFixtures.soloSuggestion)

            SVWarmupClock(elapsed: SVFixtures.warmupClock)
        } foot: {
            SVPrimary(title: "START LIFTING")
        }
    }
}

// MARK: - 06 · the same screen in its crew frame

/// `warmup-crew` — **same body, different frame** (rule 4).
///
/// Everything solo has is still here in the same order — the plan card,
/// Coach's line, the clock, the primary — and crew presence ADDS rather than
/// rearranges: the readiness row above the plan (three warm, one not), the
/// talk dock above the button, and a leader's note under it. Coach's line
/// keeps variation a's strip form and says out loud that it is private,
/// because spec §3.2 speaks to each lifter alone and a crew screen that
/// shows a Coach line without saying so reads as a broadcast.
///
/// The primary stays live while Sam is still warming up: spec §3.2 lets the
/// leader move on, and the note under the button is where that costs
/// something rather than a second control.
///
/// ACCENT: START LIFTING. The readiness marks are green (done or present),
/// the dock is the dock.
struct WarmupCrewView: View {
    var body: some View {
        SVScreen(kicker: "\(SVFixtures.crewName.uppercased()) · WARM-UP",
                 title: SVFixtures.crewSessionTitle) {
            SVReadinessRow(lifters: SVFixtures.warmupCrew,
                           kicker: "WHO'S WARM",
                           count: "3 OF 4")

            SVPlanCard(kicker: "THE PLAN",
                       title: SVFixtures.crewSessionRung,
                       detail: SVFixtures.blockLine)

            SVSuggestionStrip(suggestion: SVFixtures.crewWarmupSuggestion,
                              isPrivate: true)

            SVWarmupClock(elapsed: SVFixtures.warmupClock)
        } foot: {
            PTTDockRow(otherParticipantNames: ["Dana Kord", "Sam Obi", "Lee Vance"])
            SVPrimary(title: "START LIFTING",
                      note: "You're the leader · Sam is still warming up")
        }
    }
}
#endif
