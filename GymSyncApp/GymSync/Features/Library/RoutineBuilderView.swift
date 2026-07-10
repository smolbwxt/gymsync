import SwiftUI

struct RoutineBuilderView: View {
    let editing: Routine?
    let onSaved: (Routine) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var items: [RoutineExercise] = []
    @State private var loading = false
    @State private var showExercisePicker = false
    @State private var errorText: String?
    @State private var allExercises: [Exercise] = []

    var body: some View {
        Form {
            Section("Details") {
                TextField("Routine name", text: $name)
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
            }
            Section("Exercises") {
                if items.isEmpty {
                    Text("No exercises yet.").foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    exerciseRow(item)
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
                }
            }
            if let errorText {
                Section { Text(errorText).foregroundStyle(.red) }
            }
        }
        .navigationTitle(editing == nil ? "New Routine" : "Edit Routine")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) { EditButton() }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack {
                exercisePicker
            }
        }
        .task { await load() }
    }

    private var exercisePicker: some View {
        List(allExercises) { ex in
            Button {
                items.append(RoutineExercise(
                    id: UUID(),
                    routineID: editing?.id ?? UUID(),  // placeholder until save
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
                VStack(alignment: .leading) {
                    Text(ex.name)
                    Text(ex.primaryMuscle.capitalized)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Add exercise")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { showExercisePicker = false }
            }
        }
    }

    private func exerciseRow(_ item: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == item.exerciseID }
        return VStack(alignment: .leading) {
            Text(ex?.name ?? "Exercise")
            HStack(spacing: 12) {
                setField(value: Binding(
                    get: { String(item.targetSets ?? 0) },
                    set: { newVal in updateItem(item.id) { $0.targetSets = Int(newVal) } }
                ), label: "sets", keyboard: .numberPad)
                setField(value: Binding(
                    get: { item.targetReps ?? "" },
                    set: { newVal in updateItem(item.id) { $0.targetReps = newVal } }
                ), label: "reps", keyboard: .default)
                setField(value: Binding(
                    get: { item.targetWeight ?? "" },
                    set: { newVal in updateItem(item.id) { $0.targetWeight = newVal } }
                ), label: "weight", keyboard: .decimalPad)
            }
        }
    }

    private func setField(value: Binding<String>, label: String, keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            TextField(label, text: value)
                .keyboardType(keyboard)
                .padding(6)
                .background(Color(.secondarySystemBackground), in: .rect(cornerRadius: 6))
        }
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
        // Ensure all items point at the actual routineID with sequential positions
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
