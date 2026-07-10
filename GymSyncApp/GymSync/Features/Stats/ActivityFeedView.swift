import SwiftUI

struct ActivityFeedView: View {
    @Environment(AppState.self) private var appState
    @State private var sessions: [WorkoutSession] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if loading { ProgressView() }
            else if let errorText { Text(errorText).foregroundStyle(.red) }
            else if sessions.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Complete a workout to see it here.")
                )
            } else {
                List(sessions) { s in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(s.completedAt?.formatted(date: .abbreviated, time: .shortened)
                             ?? s.createdAt.formatted())
                            .font(.headline)
                        if let start = s.startedAt, let end = s.completedAt {
                            Text("Duration: \(Self.formatDuration(end.timeIntervalSince(start)))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent activity")
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { sessions = try await SessionRepository.history(userID: userID, limit: 50) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        let m = Int(seconds) / 60
        let h = m / 60
        let mins = m % 60
        return h > 0 ? "\(h)h \(mins)m" : "\(mins)m"
    }
}
