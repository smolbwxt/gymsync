import SwiftUI

struct ExerciseHistoryView: View {
    let exercise: Exercise
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var logs: [SetLog] = []
    @State private var loading = false
    @State private var errorText: String?
    @State private var selectedRange: TrendRange = .sixMonths
    /// sessionID -> "solo" or the group's name — best-effort, empty means
    /// the session/group lookup hasn't resolved (or failed) and rows fall
    /// back to no suffix rather than blocking on it.
    @State private var sessionContext: [UUID: String] = [:]

    /// Valid (non-failed, non-penalty) logs — `exerciseHistory` already
    /// filters these server-side, but this stays defensive/explicit.
    private var validLogs: [SetLog] {
        logs.filter { !$0.isFailed && !$0.isPenalty }
    }

    private var chartData: [(Date, Double)] {
        validLogs
            .compactMap { log -> (Date, Double)? in
                guard let w = log.weight, let reps = log.reps else { return nil }
                let oneRM = StatMath.estimatedOneRepMax(weight: w, reps: reps)
                return (log.loggedAt, NSDecimalNumber(decimal: oneRM).doubleValue)
            }
            .sorted { $0.0 < $1.0 }
    }

    // Canvas: "BEST 190×5 / EST 1RM 214 / SESSIONS 28" summary tiles.
    private var bestSet: SetLog? {
        validLogs.max { ($0.weight ?? 0) < ($1.weight ?? 0) }
    }

    private var estimatedOneRepMax: Int? {
        let values = validLogs.compactMap { log -> Decimal? in
            guard let w = log.weight, let reps = log.reps else { return nil }
            return StatMath.estimatedOneRepMax(weight: w, reps: reps)
        }
        guard let maxValue = values.max() else { return nil }
        return Int(NSDecimalNumber(decimal: maxValue).doubleValue.rounded())
    }

    private var sessionCount: Int {
        Set(validLogs.map(\.sessionID)).count
    }

    /// Chronological running-max PR check: a set is tagged "PR" when it's a
    /// new all-time-high weight at the moment it was logged (matches the
    /// same "weight > priorMax" rule `WorkoutSessionView.log()` uses live).
    private var prSetIDs: Set<UUID> {
        var runningMax = Decimal(0)
        var ids: Set<UUID> = []
        for log in validLogs.sorted(by: { $0.loggedAt < $1.loggedAt }) {
            guard let weight = log.weight, weight > 0 else { continue }
            if weight > runningMax {
                runningMax = weight
                ids.insert(log.id)
            }
        }
        return ids
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                statTileRow
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 16)

                // Chart wrapped in GSCard (via TrendChartView)
                TrendChartView(title: "Est. 1RM Trend",
                               data: chartData,
                               selectedRange: $selectedRange)
                    .padding(.horizontal, 16)

                GSDivider()
                    .padding(.vertical, 16)

                // All-sets header
                GSSectionHeader("All Sets")
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)

                // Set rows — weight-first title/meta + PR/FAIL tag
                ForEach(logs.prefix(30)) { log in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 3) {
                            // Title: weight × reps (weight-first, matches Home/Stats/Recap convention)
                            Text("\(weightText(log.weight)) × \(log.reps ?? 0)")
                                .font(GSFont.heading(15, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            // Meta: date + RPE + session context (solo / group name)
                            Text(metaText(for: log))
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                        Spacer()
                        if log.isFailed {
                            GSTag(text: "FAIL", style: .neutral)
                        } else if prSetIDs.contains(log.id) {
                            GSTag(text: "PR", style: .accent)
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

    private var statTileRow: some View {
        HStack(spacing: 8) {
            GSStatTile(
                value: bestSet.map { "\(weightText($0.weight))×\($0.reps ?? 0)" } ?? "—",
                label: "Best",
                valueFontSize: 18,
                labelColor: theme.accent700,
                uppercaseLabel: true
            )
            GSStatTile(
                value: estimatedOneRepMax.map { "\($0)" } ?? "—",
                label: "Est 1RM",
                valueFontSize: 18,
                labelColor: theme.accent700,
                uppercaseLabel: true
            )
            GSStatTile(
                value: "\(sessionCount)",
                label: "Sessions",
                valueFontSize: 18,
                labelColor: theme.accent700,
                uppercaseLabel: true
            )
        }
    }

    private func weightText(_ weight: Decimal?) -> String {
        guard let weight else { return "-" }
        var value = weight
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    private func metaText(for log: SetLog) -> String {
        var parts = [log.loggedAt.formatted(date: .abbreviated, time: .omitted)]
        if let rpe = log.rpe {
            parts.append("RPE \(String(format: "%.1f", NSDecimalNumber(decimal: rpe).doubleValue))")
        }
        if let context = sessionContext[log.sessionID] {
            parts.append(context)
        }
        return parts.joined(separator: " · ")
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        loading = true
        defer { loading = false }
        do {
            logs = try await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200)
        } catch { errorText = ErrorMapping.map(error).errorDescription }
        await loadSessionContext()
    }

    /// Best-effort "· solo" / "· {group name}" resolution for the meta line —
    /// a failure here just leaves rows without the suffix, never blocks the
    /// set list itself from rendering.
    @MainActor
    private func loadSessionContext() async {
        let sessionIDs = Array(Set(logs.map(\.sessionID)))
        guard !sessionIDs.isEmpty,
              let sessions = try? await SessionRepository.sessions(ids: sessionIDs) else { return }

        let groupIDs = Array(Set(sessions.compactMap(\.groupID)))
        let groups = (try? await GroupRepository.fetchMany(ids: groupIDs)) ?? []
        let groupNames = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })

        var context: [UUID: String] = [:]
        for session in sessions {
            if let groupID = session.groupID {
                context[session.id] = groupNames[groupID] ?? "group"
            } else {
                context[session.id] = "solo"
            }
        }
        sessionContext = context
    }
}
