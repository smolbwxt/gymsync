import SwiftUI

// Canvas: Routine Builder — card-per-exercise with SETS/REPS/WEIGHT/REST stat tiles,
// drag handle at leading edge, position tag at trailing edge.
// Keeps List with EditButton / onDelete / onMove (plan constraint).
struct RoutineBuilderView: View {
    let editing: Routine?
    let onSaved: (Routine) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var items: [RoutineExercise] = []
    @State private var loading = false
    @State private var showExercisePicker = false
    @State private var errorText: String?
    @State private var allExercises: [Exercise] = []

    var body: some View {
        // Keep Form so EditButton / onDelete / onMove remain functional (plan constraint)
        Form {
            // Canvas: Details section — name + optional description
            Section {
                TextField("Routine name", text: $name)
                    .font(GSFont.body(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .listRowBackground(theme.surface)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .listRowBackground(theme.surface)
            } header: {
                GSSectionHeader("Details")
            }

            // Canvas: Exercise list — one card per exercise with stat tiles
            Section {
                if items.isEmpty {
                    Text("No exercises yet.")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                        .listRowBackground(theme.surface)
                }
                ForEach(items) { item in
                    exerciseRow(item)
                        .listRowBackground(theme.surface)
                        .listRowInsets(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                    reindex()
                }
                .onMove { indices, dest in
                    items.move(fromOffsets: indices, toOffset: dest)
                    reindex()
                }

                Button {
                    showExercisePicker = true
                } label: {
                    Label("Add exercise", systemImage: "plus.circle.fill")
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                        .foregroundStyle(theme.accent)
                }
                .listRowBackground(theme.surface)
            } header: {
                GSSectionHeader("Exercises")
            }

            if let errorText {
                Section {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(.red)
                        .listRowBackground(theme.surface)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle(editing == nil ? "New Routine" : "Edit Routine")
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .font(GSFont.bold(15, relativeTo: .body))
                    .tint(theme.accent)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack { exercisePicker }
        }
        .task { await load() }
    }

    // Canvas: exercise picker rows — name + muscle kicker
    private var exercisePicker: some View {
        List(allExercises) { ex in
            Button {
                items.append(RoutineExercise(
                    id: UUID(),
                    routineID: editing?.id ?? UUID(),
                    exerciseID: ex.id,
                    position: items.count + 1,
                    targetSets: 3,
                    targetReps: "8-12",
                    targetWeight: nil,
                    restSeconds: AppConfig.defaultRestSeconds,
                    notes: nil
                ))
                showExercisePicker = false
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name)
                        .font(GSFont.heading(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text(ex.primaryMuscle.capitalized)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("Add exercise")
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { showExercisePicker = false }
                    .tint(theme.accent)
            }
        }
    }

    // Canvas: exercise card — name + "Muscle · Equipment" kicker, stat tile row
    private func exerciseRow(_ item: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == item.exerciseID }
        return VStack(alignment: .leading, spacing: 10) {
            // Header row: name + position tag
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.neutral500)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ex?.name ?? "Exercise")
                        .font(GSFont.heading(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    if let ex {
                        Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    }
                }

                Spacer()

                GSTag(text: "\(item.position)", style: .neutral)
            }

            // Canvas: stat tile row — SETS / REPS / WEIGHT / REST
            HStack(spacing: 6) {
                statTile(value: Binding(
                    get: { String(item.targetSets ?? 0) },
                    set: { v in updateItem(item.id) { $0.targetSets = Int(v) } }
                ), label: "SETS", keyboard: .numberPad, flex: 1)

                statTile(value: Binding(
                    get: { item.targetReps ?? "" },
                    set: { v in updateItem(item.id) { $0.targetReps = v } }
                ), label: "REPS", keyboard: .default, flex: 1)

                statTile(value: Binding(
                    get: { item.targetWeight ?? "" },
                    set: { v in updateItem(item.id) { $0.targetWeight = v } }
                ), label: "WEIGHT", keyboard: .decimalPad, flex: 1)
            }
        }
    }

    // Canvas: stat tile — muted uppercase kicker + bold value, 1px divider border
    private func statTile(value: Binding<String>, label: String,
                          keyboard: UIKeyboardType, flex: Int) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            TextField(label, text: value)
                .keyboardType(keyboard)
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    private func updateItem(_ id: UUID, mutate: (inout RoutineExercise) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    private func reindex() {
        for i in items.indices { items[i].position = i + 1 }
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            allExercises = try await ExerciseRepository.fetchAll()
            if let editing {
                name = editing.name
                description = editing.description ?? ""
                if let (_, exs) = try await RoutineRepository.fetch(id: editing.id) {
                    items = exs
                }
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func save() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        let routineID = editing?.id ?? UUID()
        let now = Date()
        let routine = Routine(
            id: routineID,
            ownerID: ownerID,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            visibility: "private",
            createdAt: editing?.createdAt ?? now,
            updatedAt: now
        )
        let normalizedItems = items.enumerated().map { idx, item in
            RoutineExercise(
                id: item.id,
                routineID: routineID,
                exerciseID: item.exerciseID,
                position: idx + 1,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                targetWeight: item.targetWeight,
                restSeconds: item.restSeconds,
                notes: item.notes
            )
        }
        do {
            try await RoutineRepository.save(routine, exercises: normalizedItems)
            onSaved(routine)
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
