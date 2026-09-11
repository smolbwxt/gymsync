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

    /// THE MILESTONE THIS BLOCK IS BEING BUILT FOR (spec §5.3, plan task C3).
    ///
    /// Non-optional, because "no block without a goal" is owner decision 4:
    /// the only way to reach this screen is through the goal screen and the
    /// milestone card (`GoalFirstBuildFlow`), so by the time a build starts
    /// there is always a milestone to build to.
    ///
    /// **IT IS NOT YET AN ARGUMENT TO `ProgramBuilder.build` ON THIS
    /// BRANCH.** Stream B has shipped that parameter — `build(profile:
    /// answers:catalog:userID:goal:)`, required and non-optional, on
    /// `origin/feat/goal-first-generator` (2515c0f) — but it does not exist
    /// HERE, and `ProgramBuilder.swift` is B's file: streams touch disjoint
    /// file sets and merging B is integration's job. So the goal is carried
    /// to the call site below and no further, and `finish()` spells out the
    /// one line integration changes. A build on this branch generates the
    /// block it generated before, which is the designed intermediate state.
    let goal: BlockGoalDraft

    /// The build landed, with the id of the goal row it wrote. The host
    /// decides where the athlete goes — a push, a route swap, a sheet
    /// dismissal — because that differs per host and is the one thing this
    /// view must not assume.
    ///
    /// The id is what lets a host push the ladder page (spec §6) for the goal
    /// just written. It is `nil` until B4 writes the row, and every host
    /// currently ignores it and pushes `ProgramScheduleView` exactly as
    /// today; integration task I1 swaps that destination, one line per host.
    var onBuilt: (UUID?) -> Void

    /// A rule the athlete just gave that could NOT be stored.
    ///
    /// `ConsultPersistence.apply` has always returned this and this view has
    /// always discarded it — a gap that only `CoachHomeView` covered, and only
    /// for its own copy of the consult, which task C4 has now removed. The
    /// whole point of the 2026-08-26 fix is that this is never nil in silence:
    /// if their words did not stick, they are told. So it is reported here,
    /// which means all four doors report it rather than one.
    var onRuleTrouble: (String) -> Void = { _ in }

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
        if let ruleTrouble = outcome.ruleTrouble { onRuleTrouble(ruleTrouble) }
        do {
            // ── THE ONE LINE INTEGRATION CHANGES, NOW MADE (I1) ──────────
            //
            // Stream B's `ProgramBuilder.build` requires `goal:` and
            // `blockGoalRepository:` (no defaults). `goal`, NOT
            // `LadderMath.detectedGoal(profile:)`: this screen's own
            // milestone (`ConsultEntryView.goal`, Stream C task C3) is in
            // scope — B4 left the detected-goal draft only as a placeholder
            // "for the call sites Stream C has not reached yet", and this is
            // that call site. The other placeholder lived in
            // `CoachHomeView.buildFromConsult`, which task C4 deleted
            // outright, so no production path ships the stand-in.
            //
            // `blockGoalRepository` is `LiveBlockGoalRepository()` (A11) —
            // the I1 swap of every `// I1: swap` marker.
            //
            // `onBuilt` is handed the id of the `block_goals` row the build
            // wrote (`outcome.goalID`, nil only when the enrollment or the
            // save itself failed), so the host can push the ladder page
            // (spec §6) for the goal just written.
            let outcome = try await ProgramBuilder.build(
                profile: profile, answers: answers,
                catalog: catalog, userID: userID,
                goal: goal,
                blockGoalRepository: LiveBlockGoalRepository())
            onBuilt(outcome.goalID)
        } catch {
            trouble = ErrorMapping.map(error).errorDescription
        }
    }
}
