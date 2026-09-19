import SwiftUI

// MARK: - SessionRoutineEditor
//
// Mid-session full builder (spec 2026-08-22 §2, solo v1): reorder, add,
// remove, and retune sets/reps — against a SESSION-LOCAL copy that never
// touches the stored routine mid-flight. The keep/save-as-new/discard
// decision happens at workout's end, in the caller. Groups are out of
// v1 (a live edit to a shared routine collides with hot-swap unanimity).
struct SessionRoutineEditor: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    /// The working list — seeded by the caller from the effective
    /// routine; handed back whole on Done.
    @State var exercises: [RoutineExercise]
    /// Name lookups: routine rows first, full catalog for additions.
    let nameByID: [UUID: String]
    let routineID: UUID
    let onDone: ([RoutineExercise]) -> Void

    @State private var showPicker = false
    @State private var catalog: [Exercise] = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(exercises) { re in
                    row(re)
                }
                .onMove { from, to in
                    exercises.move(fromOffsets: from, toOffset: to)
                }
                .onDelete { offsets in
                    exercises.remove(atOffsets: offsets)
                }

                Button {
                    showPicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.accent)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Edit this session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        // Positions renumber on the way out so a later
                        // "update routine" write is already coherent.
                        let renumbered = exercises.enumerated().map { index, re in
                            var r = re
                            r.position = index + 1
                            return r
                        }
                        onDone(renumbered)
                        dismiss()
                    }
                    .font(GSFont.bold(15, relativeTo: .body))
                }
            }
            .sheet(isPresented: $showPicker) { picker }
        }
    }

    private func row(_ re: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(nameByID[re.exerciseID]
                 ?? catalog.first(where: { $0.id == re.exerciseID })?.name
                 ?? "Exercise")
                .font(GSFont.bold(15, relativeTo: .body))
                .foregroundStyle(theme.text)
            HStack(spacing: 16) {
                stepper(label: "SETS", value: re.targetSets ?? 3) { new in
                    mutate(re.id) { $0.targetSets = max(1, new) }
                }
                stepper(label: "REPS", value: re.targetRepsLow
                        ?? re.targetReps.flatMap { Int($0.prefix(while: \.isNumber)) } ?? 8) { new in
                    mutate(re.id) { r in
                        let clamped = max(1, new)
                        if let low = r.targetRepsLow, let high = r.targetRepsHigh {
                            // Preserve the range's width when one exists.
                            let width = high - low
                            r.targetRepsLow = clamped
                            r.targetRepsHigh = clamped + width
                        } else {
                            r.targetReps = "\(clamped)"
                            r.targetRepsLow = nil
                            r.targetRepsHigh = nil
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private func stepper(label: String, value: Int,
                         onChange: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral500)
            Button { onChange(value - 1) } label: {
                Image(systemName: "minus.circle")
                    .foregroundStyle(theme.neutral700)
            }
            .buttonStyle(.plain)
            Text("\(value)")
                .font(GSFont.bold(15, relativeTo: .body).monospacedDigit())
                .foregroundStyle(theme.text)
                .frame(minWidth: 22)
            Button { onChange(value + 1) } label: {
                Image(systemName: "plus.circle")
                    .foregroundStyle(theme.neutral700)
            }
            .buttonStyle(.plain)
        }
    }

    private func mutate(_ id: UUID, _ change: (inout RoutineExercise) -> Void) {
        guard let index = exercises.firstIndex(where: { $0.id == id }) else { return }
        change(&exercises[index])
    }

    private var picker: some View {
        NavigationStack {
            List {
                ForEach(filteredCatalog) { ex in
                    Button {
                        exercises.append(RoutineExercise(
                            id: UUID(), routineID: routineID, exerciseID: ex.id,
                            position: exercises.count + 1,
                            targetSets: 3, targetReps: "8",
                            targetWeight: nil, restSeconds: nil, notes: nil,
                            supersetGroup: nil,
                            targetRepsLow: nil, targetRepsHigh: nil,
                            cardioZone: nil, cardioMinutes: nil))
                        showPicker = false
                        search = ""
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ex.name)
                                .font(GSFont.bold(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Text(ex.primaryMuscle.capitalized)
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                }
            }
            .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showPicker = false }
                }
            }
            .task {
                if catalog.isEmpty {
                    catalog = ((try? await ExerciseRepository.fetchAll()) ?? [])
                        .filter { $0.aliasOf == nil }
                }
            }
        }
    }

    private var filteredCatalog: [Exercise] {
        guard !search.isEmpty else { return Array(catalog.prefix(60)) }
        let q = search.lowercased()
        return catalog.filter { $0.name.lowercased().contains(q) }
    }
}
