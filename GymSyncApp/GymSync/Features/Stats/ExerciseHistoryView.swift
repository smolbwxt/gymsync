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

    /// Valid (non-penalty) logs. Failed sets STAY (doctrine 2026-08-13):
    /// their completed reps are real data — every consumer below reads
    /// `completedReps`, so failed singles (0 completed) drop out naturally.
    private var validLogs: [SetLog] {
        logs.filter { !$0.isPenalty }
    }

    private var chartData: [(Date, Double)] {
        // Units sweep: points in the user's unit, matching the stat tiles.
        let unit = ThemeStore.shared.weightUnit
        return validLogs
            .compactMap { log -> (Date, Double)? in
                guard let w = log.weight, let reps = log.completedReps else { return nil }
                let oneRM = StatMath.estimatedOneRepMax(weight: w, reps: reps)
                return (log.loggedAt, Units.fromPounds(NSDecimalNumber(decimal: oneRM).doubleValue, to: unit))
            }
            .sorted { $0.0 < $1.0 }
    }

    // Canvas: "BEST 190×5 / EST 1RM 214 / SESSIONS 28" summary tiles.
    // Completed reps only — a missed 1RM never becomes "your best".
    private var bestSet: SetLog? {
        validLogs
            .filter { ($0.completedReps ?? 0) > 0 }
            .max { ($0.weight ?? 0) < ($1.weight ?? 0) }
    }

    /// Weight/reps pairs for the record math — the shared basis both this
    /// screen and the live views judge against.
    private var basis: [(weight: Decimal, reps: Int)] {
        validLogs.compactMap { log in
            guard let w = log.weight, let r = log.completedReps, w > 0 else { return nil }
            return (w, r)
        }
    }

    /// The lifter's one-rep max: MEASURED when they've actually done a single,
    /// otherwise estimated from their best work (owner 2026-08-02: "a one rep
    /// max should be estimated if you've never logged a max"). The tile's
    /// label changes with it, so an estimate is never presented as a fact.
    private var oneRepMax: PersonalRecordMath.OneRepMax? {
        PersonalRecordMath.oneRepMax(from: basis)
    }

    private var oneRepMaxValue: Int? {
        guard let oneRepMax else { return nil }
        // Units sweep: whole number in the user's unit.
        return Int(Units.fromPounds(NSDecimalNumber(decimal: oneRepMax.pounds).doubleValue,
                                    to: ThemeStore.shared.weightUnit).rounded())
    }

    private var sessionCount: Int {
        Set(validLogs.map(\.sessionID)).count
    }

    /// Chronological PR replay: a set is tagged "PR" when, at the moment it
    /// was logged, it beat everything done for AT LEAST that many reps.
    ///
    /// Must stay the same rule the live views celebrate with — hence the
    /// shared `PersonalRecordMath` — or history would quietly contradict the
    /// overlay a lifter saw in the gym. Replayed forward rather than compared
    /// against the full set, so a later heavier session can't retroactively
    /// strip the badge off a set that genuinely was a record that day.
    private var prSetIDs: Set<UUID> {
        var seen: [(weight: Decimal, reps: Int)] = []
        var ids: Set<UUID> = []
        for log in validLogs.sorted(by: { $0.loggedAt < $1.loggedAt }) {
            guard let weight = log.weight, let reps = log.completedReps, weight > 0 else { continue }
            if PersonalRecordMath.isPR(weight: weight, reps: reps, basis: seen) {
                ids.insert(log.id)
            }
            seen.append((weight, reps))
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
                        // Not either/or anymore: a failed set CAN be the
                        // record (doctrine 2026-08-13 — "9 + FAIL" may be
                        // the best 8 ever done). Both tags render.
                        if prSetIDs.contains(log.id) {
                            GSTag(text: "PR", style: .accent)
                        }
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
        // Pushed from StatsTabView's per-exercise history list — see
        // GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private var statTileRow: some View {
        HStack(spacing: 8) {
            GSStatTile(
                value: bestSet.map { "\(weightText($0.weight))×\($0.completedReps ?? 0)" } ?? "—",
                label: "Best",
                valueFontSize: 18,
                labelColor: theme.accent700,
                uppercaseLabel: true
            )
            GSStatTile(
                value: oneRepMaxValue.map { "\($0)" } ?? "—",
                // "1RM" when they've actually lifted a single, "Est 1RM" when
                // the number is inferred — the tile must never claim a max
                // nobody has stood up with.
                label: (oneRepMax?.isMeasured == true) ? "1RM" : "Est 1RM",
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

    // Units sweep: stored-lbs → display unit, exact (this is a log of what
    // was actually lifted).
    private func weightText(_ weight: Decimal?) -> String {
        guard let weight else { return "-" }
        return Units.format(pounds: weight, unit: ThemeStore.shared.weightUnit,
                            rounded: false, includeUnit: false)
    }

    private func metaText(for log: SetLog) -> String {
        var parts = [log.loggedAt.formatted(date: .abbreviated, time: .omitted)]
        // A failed set stores rpe = 10, so printing rpe alone would show a
        // miss in your own history as "RPE 10.0" — the signature of a
        // max-effort success. isFailed is authoritative and wins.
        if log.isFailed {
            parts.append("FAIL")
        } else if let rpe = log.rpe {
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
