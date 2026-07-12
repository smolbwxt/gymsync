import SwiftUI

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    @State private var exercises: [Exercise] = []
    @State private var refreshedProfile: Profile?

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
            }
            .refreshable {
                if let id = appState.currentProfile?.id {
                    refreshedProfile = try? await ProfileRepository.refresh(userID: id)
                }
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
}
