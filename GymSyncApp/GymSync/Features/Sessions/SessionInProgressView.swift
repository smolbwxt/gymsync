import SwiftUI

/// Placeholder for the in-progress workout UI (Phase 3b).
struct SessionInProgressView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme
    @State private var errorText: String?
    @State private var isEnding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Hero: icon + status header
                VStack(alignment: .leading, spacing: 8) {
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 48, weight: .regular))
                        .foregroundStyle(theme.accent)

                    Text("SESSION LIVE")
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(theme.accent)

                    Text("Full workout UI ships in Phase 3b.")
                        .font(GSFont.body(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 20)

                GSDivider()
                    .padding(.horizontal, 16)

                // Participants with burpees
                if !participants.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        GSSectionHeader("Participants")
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(participants, id: \.participant.userID) { item in
                            participantRow(item)

                            if item.participant.userID != participants.last?.participant.userID {
                                Rectangle()
                                    .fill(theme.divider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    GSDivider()
                        .padding(.horizontal, 16)
                        .padding(.top, 8)
                }

                // Burpee banner — if any participant owes burpees
                if participants.contains(where: { $0.participant.burpeesOwed > 0 }) {
                    burpeeBanner
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }

                Spacer(minLength: 80)
            }
        }
        .background(theme.bg)
        .safeAreaInset(edge: .bottom) {
            // End Session CTA pinned to bottom, full-width, red-tinted, zero radius
            VStack(spacing: 0) {
                GSDivider()
                Button(role: .destructive) {
                    Task { await endSession() }
                } label: {
                    HStack {
                        Image(systemName: "stop.circle")
                        Text("End Session")
                        Spacer()
                    }
                    .font(GSFont.bold(15, relativeTo: .body))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                    .background(isEnding ? Color.red.opacity(0.7) : Color.red)
                }
                .buttonStyle(.plain)
                .disabled(isEnding)
            }
            .background(theme.bg)
        }
        .navigationTitle("Gym Sync — In Progress")
        .navigationBarBackButtonHidden(true)
    }

    // MARK: - Participant row
    // Canvas: initials avatar + name/status + burpees badge if owed

    private func participantRow(
        _ item: (participant: SessionParticipant, profile: Profile)
    ) -> some View {
        HStack(spacing: 10) {
            // Initials avatar
            let initials = String(item.profile.username.prefix(2)).uppercased()
            ZStack {
                Rectangle()
                    .fill(item.participant.checkInState == "ready" ? theme.accent : theme.neutral400)
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(item.profile.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(checkInLabel(for: item.participant.checkInState))
                    .font(GSFont.body(10, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            if item.participant.burpeesOwed > 0 {
                Text("\(item.participant.burpeesOwed) burpees")
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.accent700)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Burpee banner
    // Canvas: accent-fill banner with "YOU OWE" kicker + large count + note

    @ViewBuilder
    private var burpeeBanner: some View {
        let totalBurpees = participants
            .map(\.participant.burpeesOwed)
            .reduce(0, +)

        if totalBurpees > 0 {
            VStack(alignment: .leading, spacing: 6) {
                Text("BURPEES OWED")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.4)
                    .foregroundStyle(theme.bg.opacity(0.85))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(totalBurpees)")
                        .font(GSFont.bold(48, relativeTo: .largeTitle))
                        .foregroundStyle(theme.bg)
                        .lineLimit(1)

                    Text("burpees")
                        .font(GSFont.bold(18, relativeTo: .title2))
                        .foregroundStyle(theme.bg)
                }

                Text("Late arrivals — settle up after the session")
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.accent)
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    // MARK: - Helpers

    private func checkInLabel(for state: String?) -> String {
        switch state {
        case "ready":    return "Checked in"
        case "invited":  return "Invited"
        default:         return "Traveling"
        }
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
