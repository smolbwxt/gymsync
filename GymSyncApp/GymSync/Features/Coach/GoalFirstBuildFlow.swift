import SwiftUI

/// The ONE way into a build, now with the goal in front of it (spec §5).
///
/// Four screens open a build (Coach home, the ledger, the block calendar, the
/// onboarding offer). Each opens THIS, which walks
/// goal screen → milestone card → consult → builder → the ladder page — so
/// there is exactly one build path, which is the same reason
/// `ConsultEntryView` was collapsed into one in the first place.
///
/// Plan: task C4 names and specifies this type; task C3 is where it has to
/// EXIST, because `ConsultEntryView.goal` is non-optional from C3 onward and a
/// host with no goal screen in front of it has nothing to pass. Introducing it
/// here and re-pointing the three `ConsultEntryView` hosts in the same commit
/// is what keeps every commit on this branch compiling; C4 then does what C4
/// is actually about — retiring the wizard and bringing Coach home's own door,
/// the fourth host, onto this path.
///
/// LANDING. `onBuilt` is handed the id of the goal row the build wrote and
/// every host currently pushes `ProgramScheduleView` exactly as today. Stream
/// D's ladder page (D1) is the real landing; integration task I1 swaps the
/// destination, one line per host, and the ladder page's own `SEE THE BLOCK ›`
/// row keeps the schedule one tap away.
struct GoalFirstBuildFlow: View {

    var onBuilt: (UUID?) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    /// The tile the athlete tapped. `GoalPreset` rather than the draft,
    /// because `navigationDestination(item:)` needs `Hashable` and
    /// `BlockGoalDraft` is Task 0's frozen surface — widening it to reach a
    /// navigation API is not this stream's call.
    @State private var chosen: GoalPreset?
    /// The milestone the card built, and the push that carries it.
    @State private var goal: BlockGoalDraft?
    @State private var building = false

    /// What the athlete's log says now, for the seeds and Coach's line.
    ///
    /// EMPTY UNTIL STREAM A'S READERS LAND (task A5). An empty reading is
    /// honest — the card seeds from its documented defaults and Coach says "I
    /// haven't got a reading for this yet" rather than printing a zero — and
    /// I1 wires the real readers in. It is never fetched by the milestone card
    /// itself; it arrives here and is passed down, which is what keeps that
    /// card capturable.
    @State private var current = GoalTarget()
    @State private var lifts: [WeeklyGoalEditorSheet.LiftOption] = []
    @State private var routines: [Routine] = []

    var body: some View {
        GoalScreenView(onChosen: { chosen = $0.preset })
            .background(theme.bg)
            .navigationDestination(item: $chosen) { preset in
                milestone(preset)
            }
            .task { await load() }
    }

    private func milestone(_ preset: GoalPreset) -> some View {
        GoalMilestoneView(preset: preset,
                          current: current,
                          lifts: lifts,
                          routines: routines,
                          onBuild: { draft in
                              goal = draft
                              building = true
                          })
            .background(theme.bg)
            .navigationDestination(isPresented: $building) {
                consult
            }
    }

    @ViewBuilder
    private var consult: some View {
        if let goal {
            ConsultEntryView(goal: goal, onBuilt: onBuilt)
                .background(theme.bg)
                .navigationBarBackButtonHidden(true)
        }
    }

    /// The pickers' contents. The block's focus lifts first, then the catalog
    /// — `WeeklyGoalEditorSheet.liftPicker`'s own ordering, and the one that
    /// matters: the lift a block is built around is the lift a lift goal is
    /// nearly always about.
    private func load() async {
        let profile = (try? await TrainingProfileRepository.load()) ?? TrainingProfile()
        let catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        let focusIDs = profile.focusExerciseIDs ?? []
        let byID = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let focus = focusIDs.compactMap { id -> WeeklyGoalEditorSheet.LiftOption? in
            guard let exercise = byID[id] else { return nil }
            return .init(id: exercise.id, name: exercise.name, detail: "FOCUS LIFT")
        }
        // Compounds first behind the focus lifts, capped: the picker draws
        // six rows, so a thousand alphabetical isolations below them would be
        // a scroll nobody finishes.
        let rest = catalog
            .filter { !focusIDs.contains($0.id) && $0.category == "compound" }
            .sorted { $0.name < $1.name }
            .prefix(12)
            .map { WeeklyGoalEditorSheet.LiftOption(id: $0.id, name: $0.name,
                                                    detail: $0.primaryMuscle.uppercased()) }
        lifts = focus + rest

        if let userID = appState.currentProfile?.id {
            routines = (try? await RoutineRepository.fetchAll(ownerID: userID)) ?? []
        }
    }
}
