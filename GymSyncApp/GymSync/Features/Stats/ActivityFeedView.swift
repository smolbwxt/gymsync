import SwiftUI

struct ActivityFeedView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var sessions: [WorkoutSession] = []
    @State private var loading = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if loading {
                ProgressView().tint(theme.accent)
            } else if let errorText {
                Text(errorText).foregroundStyle(.red)
            } else if sessions.isEmpty {
                ContentUnavailableView(
                    "No workouts yet",
                    systemImage: "figure.strengthtraining.traditional",
                    description: Text("Complete a workout to see it here.")
                )
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(sessions) { s in
                            GSCard(bordered: false) {
                                VStack(alignment: .leading, spacing: 4) {
                                    GSSectionHeader("Workout")
                                    Text(s.completedAt?.formatted(date: .abbreviated, time: .shortened)
                                         ?? s.createdAt.formatted())
                                        .font(GSFont.heading(16, relativeTo: .headline))
                                        .foregroundStyle(theme.text)
                                    if let start = s.startedAt, let end = s.completedAt {
                                        Text("Duration: \(Self.formatDuration(end.timeIntervalSince(start)))")
                                            .font(GSFont.body(13, relativeTo: .caption))
                                            .foregroundStyle(theme.neutral500)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                            GSDivider()
                        }
                        Spacer(minLength: 24)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(theme.bg)
            }
        }
        .background(theme.bg)
        .navigationTitle("Recent activity")
        .navigationBarTitleDisplayMode(.inline)
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
