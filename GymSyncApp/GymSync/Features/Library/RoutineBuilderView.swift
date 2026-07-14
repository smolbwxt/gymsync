import SwiftUI

// Canvas: Routine Builder — custom "×  New Routine  Save" header, flat
// bordered-box fields, card-per-exercise with SETS/REPS/WEIGHT/REST stat
// tiles, drag-to-reorder + a compact remove affordance per card (no native
// List/Form chrome), full-width bordered "+ Add Exercise" CTA.
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
    // Save honors this (private vs public); UI toggle below (curator-only),
    // bootstrap-seeded from `editing?.visibility` in `load()`.
    @State private var publishAsFeatured = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Canvas: "Routine name" label + bordered-box field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Routine name")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                    TextField("Routine name", text: $name)
                        .font(GSFont.heading(17, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface)
                        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                }

                // Optional description — not in canvas, kept for parity with the
                // existing save flow; styled minimal/secondary.
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
                    .font(GSFont.body(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                // Canvas: "N EXERCISES · ≈ X min" header (GSSectionHeader tracking,
                // reuses the shared duration heuristic Home/Library already use).
                HStack {
                    Text(exerciseCountLabel)
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                    Text("≈ \(StatMath.estimatedMinutes(exerciseCount: items.count)) min")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }

                if items.isEmpty {
                    Text("No exercises yet.")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                }

                ForEach(items) { item in
                    exerciseRow(item)
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            handleDrop(droppedIDs, onto: item)
                        }
                }

                // Canvas: full-width bordered "+ Add Exercise" CTA
                Button {
                    showExercisePicker = true
                } label: {
                    Text("+ Add Exercise")
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                }
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))

                // Curator-only publish toggle (frame 3's Featured shelf is
                // fed by this) — visible only to curators; server-enforced
                // via RLS regardless (migration 20260717000003), this is
                // just the UI gate. Bordered row, GSToggle idiom reused from
                // NotificationPreferencesView's toggleRow. Placed above the
                // Save action (Save itself lives in the nav toolbar).
                if appState.currentProfile?.isCurator == true {
                    publishToggleRow
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        // Used both as a sheet (RoutinesListView's "New Routine") and as a
        // pushed destination (a routine's "Edit routine" NavigationLink). The
        // dock-hiding preference is a no-op in the sheet case (sheets already
        // fully cover the dock and preferences don't cross the sheet
        // boundary) and necessary in the push case — see GSComponents.swift's
        // GSHidesDock.
        .gsHidesDock()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            // Canvas: "×" dismiss (replaces EditButton — reordering/removal are
            // always-on now, no separate edit mode needed).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(editing == nil ? "New Routine" : "Edit Routine")
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
            }
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

    private var exerciseCountLabel: String {
        "\(items.count) EXERCISE\(items.count == 1 ? "" : "S")"
    }

    // Canvas: bordered row, label + caption on the left, GSToggle on the
    // right — same shape as NotificationPreferencesView.toggleRow, extended
    // with a second caption line per the brief ("Visible to every Gym Sync
    // user").
    private var publishToggleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Publish as Featured")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text("Visible to every Gym Sync user")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(isOn: $publishAsFeatured, label: "Publish as Featured")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
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

    // Canvas: exercise card — drag handle + name + "Muscle · Equipment" kicker +
    // position tag + compact remove control, stat tile row below.
    private func exerciseRow(_ item: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == item.exerciseID }
        return VStack(alignment: .leading, spacing: 10) {
            // Header row: drag handle + name + position tag + remove
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.neutral500)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .draggable(item.id.uuidString)

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

                // Compact remove control — small drawn box, 44pt tap target via
                // invisible padding (matches the addendum's preferred fix for
                // small-drawn-but-44pt-tappable controls).
                Button {
                    removeItem(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }

            // Canvas: stat tile row — SETS / REPS / WEIGHT / REST
            HStack(spacing: 6) {
                statTile(value: Binding(
                    get: { String(item.targetSets ?? 0) },
                    set: { v in updateItem(item.id) { $0.targetSets = Int(v) } }
                ), label: "SETS", keyboard: .numberPad)

                statTile(value: Binding(
                    get: { item.targetReps ?? "" },
                    set: { v in updateItem(item.id) { $0.targetReps = v } }
                ), label: "REPS", keyboard: .default)

                statTile(value: Binding(
                    get: { item.targetWeight ?? "" },
                    set: { v in updateItem(item.id) { $0.targetWeight = v } }
                ), label: "WEIGHT", keyboard: .decimalPad)

                statTile(value: Binding(
                    get: { item.restSeconds.map(formatRest) ?? "" },
                    set: { v in updateItem(item.id) { $0.restSeconds = parseRest(v) } }
                ), label: "REST", keyboard: .numbersAndPunctuation)
            }
        }
        .padding(12)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // Canvas: stat tile — muted uppercase kicker + bold value, 1px divider border
    private func statTile(value: Binding<String>, label: String,
                          keyboard: UIKeyboardType) -> some View {
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

    private func removeItem(_ id: UUID) {
        withAnimation {
            items.removeAll { $0.id == id }
        }
        reindex()
    }

    /// Drag-and-drop reorder target — drops `droppedIDs.first` (the dragged
    /// row's UUID string) onto `target`'s position. Replaces the List
    /// edit-mode-gated `.onMove` so reordering works without an Edit toggle
    /// (canvas header has no Edit affordance, only ×/Save).
    private func handleDrop(_ droppedIDs: [String], onto target: RoutineExercise) -> Bool {
        guard let droppedIDString = droppedIDs.first,
              let droppedID = UUID(uuidString: droppedIDString),
              droppedID != target.id,
              let fromIndex = items.firstIndex(where: { $0.id == droppedID }),
              let toIndex = items.firstIndex(where: { $0.id == target.id })
        else { return false }
        withAnimation {
            items.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
        reindex()
        return true
    }

    private func reindex() {
        for i in items.indices { items[i].position = i + 1 }
    }

    // "2:00" — matches the mm:ss treatment used for rest elsewhere (e.g.
    // WorkoutSessionView's target-line rest suffix).
    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Parses "m:ss" back to seconds; falls back to a plain seconds integer
    /// if no colon is present (keeps the field forgiving to type into).
    private func parseRest(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let m = Int(parts[0]),
                  let s = Int(parts[1])
            else { return nil }
            return m * 60 + s
        }
        return Int(trimmed)
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
                // CRITICAL: must be seeded here, unconditionally, from
                // `editing` itself — not left at its `false` default. Without
                // this, a curator editing an already-published routine and
                // hitting Save would silently unpublish it (save writes
                // `visibility` from this toggle's current value).
                publishAsFeatured = editing.visibility == "public"
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
            visibility: publishAsFeatured ? "public" : "private",
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
