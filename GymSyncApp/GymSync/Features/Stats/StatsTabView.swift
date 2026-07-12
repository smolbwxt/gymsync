import SwiftUI

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var refreshedProfile: Profile?
    @State private var weeklyVolumes: [Decimal] = Array(repeating: 0, count: 6)
    @State private var recentPRs: [PersonalRecord] = []

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // ── Lifetime Volume Card ───────────────────────────────────
                    GSCard(bordered: false) {
                        VStack(alignment: .leading, spacing: 4) {
                            GSSectionHeader("Lifetime volume")
                            Text(volumeString)
                                .font(GSFont.heading(34, relativeTo: .largeTitle))
                                .foregroundStyle(theme.text)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(16)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                    GSDivider()
                        .padding(.vertical, 16)

                    // ── Weekly Volume Card ──────────────────────────────────────
                    weeklyVolumeCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Recent PRs Table ────────────────────────────────────────
                    recentPRsCardView
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)

                    // ── Recent Activity Row ────────────────────────────────────
                    GSSectionHeader("Recent Activity")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    NavigationLink { ActivityFeedView() } label: {
                        HStack {
                            Text("View sessions")
                                .font(GSFont.bodyMedium(15, relativeTo: .body))
                                .foregroundStyle(theme.accent)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .background(theme.surface)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)

                    GSDivider()
                        .padding(.vertical, 16)

                    // ── Per-Exercise History ───────────────────────────────────
                    GSSectionHeader("Per-Exercise History")
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)

                    if exercises.isEmpty {
                        Text("No exercises yet.")
                            .font(GSFont.body(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral500)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 24)
                    } else {
                        ForEach(exercises) { ex in
                            NavigationLink { ExerciseHistoryView(exercise: ex) } label: {
                                HStack {
                                    Text(ex.name)
                                        .font(GSFont.bodyMedium(15, relativeTo: .body))
                                        .foregroundStyle(theme.text)
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(theme.neutral500)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(theme.surface)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 16)
                            GSDivider()
                                .padding(.horizontal, 16)
                        }
                    }

                    Spacer(minLength: 24)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Stats")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                exercises = (try? await ExerciseRepository.fetchAll()) ?? []
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
            }
            .refreshable {
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
                await loadWeeklyVolumeAndPRs()
            }
        }
    }

    private var volumeString: String {
        let profile = refreshedProfile ?? appState.currentProfile
        let vol = profile?.lifetimeVolumeLifted ?? 0
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 0
        let raw = NSDecimalNumber(decimal: vol).doubleValue
        return "\(formatter.string(from: NSNumber(value: raw)) ?? "0") lbs"
    }

    // MARK: - Weekly Volume Card (Task 6)

    @ViewBuilder
    private var weeklyVolumeCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                GSSectionHeader("Weekly volume")

                HStack(alignment: .bottom, spacing: 8) {
                    ForEach(Array(weeklyVolumes.enumerated()), id: \.offset) { index, volume in
                        Rectangle()
                            .fill(index == weeklyVolumes.count - 1 ? theme.accent : theme.neutral400)
                            .frame(maxWidth: .infinity)
                            .frame(height: barHeight(for: volume))
                    }
                }
                .frame(height: 76, alignment: .bottom)

                HStack(spacing: 8) {
                    ForEach(0..<weeklyVolumes.count, id: \.self) { index in
                        Text("W\(index + 1)")
                            .font(GSFont.body(9, relativeTo: .caption2))
                            .foregroundStyle(index == weeklyVolumes.count - 1 ? theme.accent700 : theme.neutral700)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    /// Bar height in points for a 76pt-tall chart: proportional to the max
    /// week's volume (max week = full 76pt), with a 2pt floor for zero-volume
    /// weeks (and for the degenerate all-zero case).
    private func barHeight(for volume: Decimal) -> CGFloat {
        guard volume > 0 else { return 2 }
        let maxVolume = weeklyVolumes.max() ?? 0
        guard maxVolume > 0 else { return 2 }
        let ratio = NSDecimalNumber(decimal: volume / maxVolume).doubleValue
        return max(CGFloat(ratio) * 76, 2)
    }

    // MARK: - Recent PRs Card (Task 6)

    @ViewBuilder
    private var recentPRsCardView: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 0) {
                GSSectionHeader("Recent PRs")

                if recentPRs.isEmpty {
                    Text("No PRs yet — go set one.")
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.top, 10)
                } else {
                    HStack {
                        Text("Exercise").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Best").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Date").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral700)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                    Rectangle().fill(theme.divider).frame(height: 1)

                    ForEach(Array(recentPRs.enumerated()), id: \.element.id) { index, pr in
                        HStack {
                            Text(exerciseName(for: pr.exerciseID))
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(trimmedDecimal(pr.weight)) lbs")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(shortDate(pr.achievedAt))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .padding(.vertical, 8)

                        if index < recentPRs.count - 1 {
                            Rectangle().fill(theme.divider).frame(height: 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }

    private func exerciseName(for id: UUID) -> String {
        exercises.first(where: { $0.id == id })?.name ?? "Exercise"
    }

    private func trimmedDecimal(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSDecimalNumber(decimal: value)) ?? "\(value)"
    }

    private func shortDate(_ date: Date) -> String {
        date.formatted(.dateTime.month(.abbreviated).day())
    }

    // MARK: - Data loading (Task 6)

    @MainActor
    private func loadWeeklyVolumeAndPRs() async {
        guard let userID = appState.currentProfile?.id else { return }
        let currentWeekStart = StatMath.startOfWeek(containing: .now, calendar: .current)
        let since = Calendar.current.date(byAdding: .day, value: -35, to: currentWeekStart) ?? currentWeekStart
        let logs = (try? await SessionRepository.recentSetLogs(userID: userID, since: since)) ?? []
        weeklyVolumes = StatMath.weeklyVolumes(logs: logs, weeks: 6, calendar: .current)
        recentPRs = (try? await PersonalRecordRepository.recent(userID: userID, limit: 5)) ?? []
    }
}
