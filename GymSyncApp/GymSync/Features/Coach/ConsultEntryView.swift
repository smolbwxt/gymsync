import SwiftUI

// MARK: - ConsultEntryView
//
// The ONE way into a build. Owner 2026-08-27: "Let's change the copy of
// The Consult to Build my Program... eliminate the 5 door page all
// together, and land on the built program page."
//
// Self-contained on purpose: it loads the profile, the catalog and the
// log-derived cadence, hosts the consult, persists the answers, runs
// ProgramBuilder, and tells its host it landed. Four screens used to open
// the wizard (Coach home, the onboarding offer, the ledger, the block
// calendar); each now opens this, so there is exactly one build path and
// nothing for two hosts to disagree about.
//
// The consult's onFinish is ASYNC and this view awaits it, which is what
// lets the consult show "Coach is building your program" for the seconds
// the generator and the writes take, instead of a frozen BUILD IT.
struct ConsultEntryView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    /// The build landed. The host decides where the athlete goes — a
    /// push, a route swap, a sheet dismissal — because that differs per
    /// host and is the one thing this view must not assume.
    var onBuilt: () -> Void

    private enum Phase {
        case loading
        case consult
    }

    @State private var phase: Phase = .loading
    @State private var profile = TrainingProfile()
    @State private var catalog: [Exercise] = []
    @State private var loggedCadence: Double?
    @State private var trouble: String?

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .tint(theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .consult:
                CoachConsultView(
                    profile: profile,
                    catalog: catalog,
                    // A block finished OR sets logged. Carryover alone
                    // would cold-start someone midway through their first
                    // block.
                    hasLog: profile.carryover != nil || loggedCadence != nil,
                    loggedDaysPerWeek: loggedCadence
                        ?? profile.carryover?.suggestedDaysPerWeek.map(Double.init),
                    recommendedDaysPerWeek: profile.daysPerWeek,
                    userID: appState.currentProfile?.id,
                    onFinish: { answers in await finish(answers) })
            }
        }
        .background(theme.bg)
        .alert("Coach couldn't build that",
               isPresented: Binding(get: { trouble != nil },
                                    set: { if !$0 { trouble = nil } })) {
            Button("OK", role: .cancel) { trouble = nil }
        } message: {
            Text(trouble ?? "")
        }
        .task { await load() }
    }

    private func load() async {
        if let saved = try? await TrainingProfileRepository.load() {
            profile = saved
        }
        catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        if let userID = appState.currentProfile?.id,
           let since = Calendar.current.date(byAdding: .weekOfYear, value: -8, to: .now),
           let logs = try? await SessionRepository.recentSetLogs(userID: userID, since: since) {
            loggedCadence = ConsultProbe.loggedCadence(sessionDates: logs.map(\.loggedAt))
        }
        withAnimation(.easeOut(duration: 0.18)) { phase = .consult }
    }

    /// Persist the consult, then build. Persistence first, because the
    /// builder reads the standing rules and the tuned profile the consult
    /// just wrote — build before persisting and the first block ignores
    /// everything just said.
    private func finish(_ answers: ConsultAnswers) async {
        guard let userID = appState.currentProfile?.id else {
            trouble = "You're signed out, so I can't save a program."
            return
        }
        let outcome = await ConsultPersistence.apply(
            answers, to: profile, catalog: catalog, userID: userID)
        profile = outcome.profile
        do {
            _ = try await ProgramBuilder.build(profile: profile, answers: answers,
                                               catalog: catalog, userID: userID)
            onBuilt()
        } catch {
            trouble = ErrorMapping.map(error).errorDescription
        }
    }
}
