import SwiftUI

struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

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
            VStack(alignment: .leading, spacing: 0) {
                // Chart wrapped in GSCard (via TrendChartView)
                TrendChartView(title: "\(exercise.name) — weight over time",
                               data: chartData)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                GSDivider()
                    .padding(.vertical, 16)

                // Recent sets header
                GSSectionHeader("Recent Sets")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                // Set rows — kicker/title/meta + PR tag
                ForEach(logs.prefix(30)) { log in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            // Title: reps × weight
                            Text("\(log.reps ?? 0) × \(log.weight?.description ?? "-")")
                                .font(GSFont.heading(15, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            // Meta: date + RPE
                            Group {
                                if let rpe = log.rpe {
                                    Text("\(log.loggedAt.formatted(date: .abbreviated, time: .omitted)) · RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
                                } else {
                                    Text(log.loggedAt.formatted(date: .abbreviated, time: .omitted))
                                }
                            }
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                        }
                        Spacer()
                        if log.isFailed {
                            GSTag(text: "FAIL", style: .neutral)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    GSDivider()
                        .padding(.horizontal, 16)
                }

                if let errorText {
                    Text(errorText)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                }

                Spacer(minLength: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
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
