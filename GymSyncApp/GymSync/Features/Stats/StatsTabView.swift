import SwiftUI

struct StatsTabView: View {
    @Environment(AppState.self) private var appState
    @State private var exercises: [Exercise] = []
    @State private var refreshedProfile: Profile?

    var body: some View {
        NavigationStack {
            Form {
                Section("Lifetime") {
                    LabeledContent("Volume lifted") {
                        Text(volumeString).monospacedDigit()
                    }
                }
                Section("Recent activity") {
                    NavigationLink("View sessions") { ActivityFeedView() }
                }
                Section("Per-exercise history") {
                    ForEach(exercises) { ex in
                        NavigationLink(ex.name) { ExerciseHistoryView(exercise: ex) }
                    }
                }
            }
            .navigationTitle("Stats")
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
