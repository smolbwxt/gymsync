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
struct CoachOfferFlow: View {
    @Environment(\.gsTheme) private var theme

    /// The build landed; push the schedule page.
    @State private var landed = false

    var body: some View {
        ConsultEntryView(onBuilt: { landed = true })
            .background(theme.bg)
            // A PUSH: the flow is this stack's root, so there is nothing
            // to swap the landing into. The athlete lands on their
            // program, which is the point.
            .navigationDestination(isPresented: $landed) {
                ProgramScheduleView()
                    .background(theme.bg)
            }
    }
}
