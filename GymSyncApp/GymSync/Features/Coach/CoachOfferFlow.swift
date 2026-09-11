import SwiftUI

// MARK: - CoachOfferFlow
//
// The onboarding offer, routed through the consult. Owner 2026-08-27:
// "We should route everything through the consult."
//
// This used to be consult → wizard → build, with the wizard mounted
// after the consult so its `.task` read the rules the close chat had just
// stored. The wizard is gone from the flow (owner 2026-08-27: "eliminate
// the 5 door page all together") and the ordering guarantee moved into
// ConsultEntryView, which persists the consult BEFORE it builds. This
// host is now only the landing: the build finishes, the schedule page is
// pushed.
//
// Goal-first programming (plan task C3): the offer opens
// `GoalFirstBuildFlow` rather than the consult directly, so the onboarding
// build begins with the goal like every other build (spec §5.4). The
// landing is the ladder page for the goal the build just wrote (spec §5.3,
// integration task I1), or the plain schedule page when there is no id to
// land on.
struct CoachOfferFlow: View {
    @Environment(\.gsTheme) private var theme

    /// The build landed; push the ladder page, or the schedule page as the
    /// fallback landing.
    @State private var landing: BuildLanding?

    private enum BuildLanding: Identifiable, Hashable {
        case ladder(UUID)
        case schedule
        var id: String {
            switch self {
            case .ladder(let goalID): return goalID.uuidString
            case .schedule: return "schedule"
            }
        }
    }

    var body: some View {
        GoalFirstBuildFlow(onBuilt: { id in
            landing = id.map { .ladder($0) } ?? .schedule
        })
            .background(theme.bg)
            // A PUSH: the flow is this stack's root, so there is nothing
            // to swap the landing into. The athlete lands on their
            // program, which is the point.
            .navigationDestination(item: $landing) { landing in
                switch landing {
                case .ladder(let goalID):
                    LadderPageView(goalID: goalID)
                        .background(theme.bg)
                case .schedule:
                    ProgramScheduleView()
                        .background(theme.bg)
                }
            }
    }
}
