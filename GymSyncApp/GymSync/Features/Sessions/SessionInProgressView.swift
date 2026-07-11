import SwiftUI

/// Placeholder for the in-progress workout UI (Phase 3b).
struct SessionInProgressView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    @Environment(\.dismiss) private var dismiss
    @State private var errorText: String?
    @State private var isEnding = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(.accentColor)

            Text("Session Live")
                .font(.title).fontWeight(.bold)

            Text("Full workout UI ships in Phase 3b.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Participants with burpees badges
            if !participants.isEmpty {
                GroupBox("Participants") {
                    ForEach(participants, id: \.participant.userID) { item in
                        HStack {
                            Text(item.profile.username)
                            Spacer()
                            if item.participant.burpeesOwed > 0 {
                                Label(
                                    "\(item.participant.burpeesOwed) burpees",
                                    systemImage: "bolt.fill"
                                )
                                .font(.caption)
                                .foregroundStyle(.orange)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
                .padding(.horizontal)
            }

            if let errorText {
                Text(errorText)
                    .foregroundStyle(.red)
                    .font(.footnote)
                    .padding(.horizontal)
            }

            Spacer()

            Button(role: .destructive) {
                Task { await endSession() }
            } label: {
                Label("End Session", systemImage: "stop.circle")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(isEnding)
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Gym Sync — In Progress")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Actions

    @MainActor
    private func endSession() async {
        isEnding = true
        defer { isEnding = false }
        do {
            _ = try await SessionRepository.complete(sessionID: session.id)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
