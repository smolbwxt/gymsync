import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var upcomingSessions: [WorkoutSession] = []
    @State private var groups: [GymGroup] = []
    @State private var showScheduleSheet = false
    @State private var joinCode = ""
    @State private var isJoining = false
    @State private var joinError: String?
    @State private var joinedSession: WorkoutSession?
    @State private var navigateToJoined = false

    var body: some View {
        NavigationStack {
            List {
                welcomeSection
                upcomingSection
                joinWithCodeSection
            }
            .navigationTitle("Home")
            .task { await refresh() }
            .refreshable { await refresh() }
            .onChange(of: scenePhase) {
                guard scenePhase == .active else { return }
                Task { await refresh() }
            }
            .sheet(isPresented: $showScheduleSheet) {
                ScheduleSessionView { newSession in
                    upcomingSessions.insert(newSession, at: 0)
                }
            }
            .navigationDestination(isPresented: $navigateToJoined) {
                if let session = joinedSession {
                    LobbyView(session: session)
                }
            }
        }
    }

    // MARK: - Sections

    private var welcomeSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                Text("Welcome to Gym Sync")
                    .font(.title2.bold())
                Text("Start a solo workout from Library → Routines.")
                    .foregroundStyle(.secondary)
                Button {
                    showScheduleSheet = true
                } label: {
                    Label("+ Schedule Session", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
            .padding(.vertical, 4)
        }
    }

    private var upcomingSection: some View {
        Section("Upcoming Sessions") {
            if upcomingSessions.isEmpty {
                Text("No upcoming sessions — schedule one above.")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(upcomingSessions) { session in
                    NavigationLink {
                        LobbyView(session: session)
                    } label: {
                        upcomingRow(session)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingRow(_ session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            // Routine name (or generic "Workout" fallback is set at row level via label)
            Text(routineLabel(for: session))
                .fontWeight(.semibold)
            if let groupID = session.groupID,
               let group = groups.first(where: { $0.id == groupID }) {
                Text(group.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let scheduledFor = session.scheduledFor {
                Text(scheduledFor, style: .date)
                    + Text(" at ") + Text(scheduledFor, style: .time)
            } else {
                Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var joinWithCodeSection: some View {
        Section("Join with Code") {
            HStack {
                TextField("6-character code", text: $joinCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .keyboardType(.asciiCapable)
                    .onChange(of: joinCode) {
                        let uppercased = joinCode.uppercased()
                        if joinCode != uppercased { joinCode = uppercased }
                        if joinCode.count > 6 { joinCode = String(joinCode.prefix(6)) }
                    }
                Button("Join") {
                    Task { await joinByCode() }
                }
                .disabled(joinCode.count != 6 || isJoining)
            }
            if isJoining {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Joining…").foregroundStyle(.secondary)
                }
            }
            if let joinError {
                Text(joinError)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }
        }
    }

    // MARK: - Actions

    private func refresh() async {
        async let sessionsFetch = SessionRepository.upcoming()
        async let groupsFetch   = GroupRepository.myGroups()
        do {
            let (sessions, fetchedGroups) = try await (sessionsFetch, groupsFetch)
            upcomingSessions = sessions
            groups = fetchedGroups
        } catch {
            // Best-effort: leave existing data; errors are non-blocking for home
        }
    }

    @MainActor
    private func joinByCode() async {
        guard joinCode.count == 6 else { return }
        isJoining = true
        joinError = nil
        defer { isJoining = false }
        do {
            let session = try await SessionRepository.joinByCode(joinCode)
            joinCode = ""
            joinedSession = session
            navigateToJoined = true
        } catch let error as GymSyncError {
            joinError = error.errorDescription
        } catch {
            joinError = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func routineLabel(for session: WorkoutSession) -> String {
        // Without eager-loading routine names here, use a generic label.
        // If a routineID is present, "Workout" serves as a placeholder;
        // the full name is visible in LobbyView.
        "Workout"
    }
}
