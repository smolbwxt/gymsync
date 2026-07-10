import SwiftUI

struct RoutinesListView: View {
    @Environment(AppState.self) private var appState
    @State private var routines: [Routine] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var showingBuilder = false
    @State private var editing: Routine?

    var body: some View {
        Group {
            if loading { ProgressView() }
            else if let errorText { Text(errorText).foregroundStyle(.red) }
            else if routines.isEmpty {
                ContentUnavailableView(
                    "No routines yet",
                    systemImage: "list.clipboard",
                    description: Text("Tap + to build your first workout.")
                )
            } else {
                List {
                    ForEach(routines) { routine in
                        NavigationLink {
                            RoutineBuilderView(editing: routine) { updated in
                                Task { await load() }
                            }
                        } label: {
                            VStack(alignment: .leading) {
                                Text(routine.name)
                                if let desc = routine.description, !desc.isEmpty {
                                    Text(desc).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingBuilder = true
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingBuilder) {
            NavigationStack {
                RoutineBuilderView(editing: nil) { _ in
                    showingBuilder = false
                    Task { await load() }
                }
            }
        }
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { routines = try await RoutineRepository.fetchAll(ownerID: ownerID) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    private func delete(at offsets: IndexSet) {
        Task {
            for idx in offsets {
                let r = routines[idx]
                try? await RoutineRepository.delete(id: r.id)
            }
            await load()
        }
    }
}
