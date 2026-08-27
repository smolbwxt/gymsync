import SwiftUI

// MARK: - CoachOfferFlow
//
// The onboarding offer, routed through the consult. Owner 2026-08-27:
// "We should route everything through the consult."
//
// Until now the post-walkthrough sheet mounted the wizard bare — a
// brand-new athlete got the five doors and the dials but was never
// ASKED anything: no consult, no health conversation beyond the gate,
// no standing rules. The flow is now the same arc a returning athlete
// walks from the Coach tab: consult (which opens with the health gate
// and closes in the chat with Coach) → wizard → build → landing on the
// program.
//
// PHASE SWAP, NOT NAVIGATION. The consult and the wizard occupy the same
// stack-root position and swap; there is no push, so there is nothing to
// pop back into — the consult-loop bug (backing out of the builder into
// a consult that re-ran its health gate) is unrepresentable here. The
// swap order also carries a load-bearing guarantee: the wizard mounts
// only AFTER the consult finishes, so its `.task` reads the standing
// rules the close chat just stored. Mount it earlier and the first
// build ignores everything just typed.
struct CoachOfferFlow: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    private enum Phase {
        case loading
        case consult
        case wizard
    }

    @State private var phase: Phase = .loading
    @State private var profile = TrainingProfile()
    @State private var catalog: [Exercise] = []
    /// The build landed; push the schedule page.
    @State private var landed = false

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .consult:
                // This host exists for exactly one clientele: an account
                // that finished signup seconds ago (WelcomeView is the
                // only setter of pendingCoachOffer). No sessions, no
                // carryover, no cadence — the log-derived facts are
                // honestly empty rather than queried into existence.
                CoachConsultView(
                    profile: profile,
                    catalog: catalog,
                    hasLog: false,
                    loggedDaysPerWeek: nil,
                    recommendedDaysPerWeek: profile.daysPerWeek,
                    userID: appState.currentProfile?.id,
                    onFinish: { answers in
                        Task {
                            if let userID = appState.currentProfile?.id {
                                let outcome = await ConsultPersistence.apply(
                                    answers, to: profile,
                                    catalog: catalog, userID: userID)
                                profile = outcome.profile
                            }
                            withAnimation(.easeOut(duration: 0.18)) {
                                phase = .wizard
                            }
                        }
                    })
                .background(theme.bg)
            case .wizard:
                CoachWizardView(onCreated: {
                    landed = true
                    return .handled
                })
                .background(theme.bg)
            }
        }
        // A PUSH: the flow is this stack's root, so there is nothing to
        // swap the landing into. Back returns to an idle wizard, which is
        // harmless; the athlete lands on their program, which is the
        // point.
        .navigationDestination(isPresented: $landed) {
            ProgramScheduleView()
        }
        .task {
            // A just-onboarded athlete usually has no profile row yet;
            // the default profile is the honest starting state, and the
            // consult is precisely the thing that will fill it.
            if let saved = try? await TrainingProfileRepository.load() {
                profile = saved
            }
            catalog = (try? await ExerciseRepository.fetchAll()) ?? []
            withAnimation(.easeOut(duration: 0.18)) { phase = .consult }
        }
    }
}
