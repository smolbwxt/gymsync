import SwiftUI

struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Environment(AppState.self) private var appState

    @State private var logs: [SetLog] = []
    @State private var loading = false
    @State private var errorText: String?

    private var chartData: [(Date, Double)] {
        logs
            .filter { !$0.isFailed && !$0.isPenalty }
            .compactMap { log in
                guard let w = log.weight else { return nil }
                return (log.loggedAt, NSDecimalNumber(decimal: w).doubleValue)
            }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TrendChartView(title: "\(exercise.name) — weight over time",
                               data: chartData)
                Text("Recent sets").font(.headline).padding(.horizontal)
                ForEach(logs.prefix(30)) { log in
                    HStack {
                        Text(log.loggedAt.formatted(date: .abbreviated, time: .omitted))
                        Spacer()
                        Text("\(log.reps ?? 0) × \(log.weight?.description ?? "-")")
                        if let rpe = log.rpe {
                            Text("RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                                .foregroundStyle(.secondary).font(.caption)
                        }
                        if log.isFailed {
                            Text("FAIL").font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            if let errorText { Text(errorText).foregroundStyle(.red) }
        }
        .navigationTitle(exercise.name)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do { logs = try await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200) }
        catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
