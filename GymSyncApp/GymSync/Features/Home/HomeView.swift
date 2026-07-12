import SwiftUI

struct HomeView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.gsTheme) private var theme

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
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    greetingHeader
                    GSDivider()
                    scheduleButton
                    GSDivider()
                    upcomingSection
                    GSDivider()
                    joinWithCodeSection
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
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

    // MARK: - Greeting Header

    private var greetingHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Home")
                .font(GSFont.heading(28, relativeTo: .largeTitle))
                .foregroundStyle(theme.text)
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(GSFont.body(13, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 16)
    }

    // MARK: - Schedule Button

    private var scheduleButton: some View {
        Button {
            showScheduleSheet = true
        } label: {
            Text("+ Schedule Session")
        }
        .buttonStyle(GSPrimaryButtonStyle())
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Upcoming Section

    private var upcomingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Upcoming Sessions")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            if upcomingSessions.isEmpty {
                Text("No upcoming sessions — schedule one above.")
                    .font(GSFont.body(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 16)
            } else {
                ForEach(upcomingSessions) { session in
                    NavigationLink {
                        LobbyView(session: session)
                    } label: {
                        upcomingCard(session)
                    }
                    .buttonStyle(.plain)
                    GSDivider()
                }
            }
        }
    }

    @ViewBuilder
    private func upcomingCard(_ session: WorkoutSession) -> some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 4) {
                // Kicker: group name or "Session"
                HStack(spacing: 6) {
                    if let groupID = session.groupID,
                       let group = groups.first(where: { $0.id == groupID }) {
                        Text(group.name.uppercased())
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    } else {
                        Text("SESSION")
                            .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                    }
                    if session.seriesID != nil {
                        Image(systemName: "repeat")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(theme.accent700)
                    }
                }
                // Title: routine label
                Text(routineLabel(for: session))
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                // Meta: scheduled time or status
                if let scheduledFor = session.scheduledFor {
                    Text(scheduledFor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                } else {
                    Text(session.state.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
    }

    // MARK: - Join with Code Section

    private var joinWithCodeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Join with Code")
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 10)

            GSCard(bordered: true) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("6-character code", text: $joinCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .keyboardType(.asciiCapable)
                            .font(GSFont.bodyMedium(16, relativeTo: .body))
                            .foregroundStyle(theme.text)
                            .onChange(of: joinCode) {
                                let uppercased = joinCode.uppercased()
                                if joinCode != uppercased { joinCode = uppercased }
                                if joinCode.count > 6 { joinCode = String(joinCode.prefix(6)) }
                            }
                        Button("Join") {
                            Task { await joinByCode() }
                        }
                        .buttonStyle(GSPrimaryButtonStyle())
                        .frame(width: 72)
                        .disabled(joinCode.count != 6 || isJoining)
                        .opacity(joinCode.count != 6 || isJoining ? 0.4 : 1)
                    }
                    if isJoining {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small).tint(theme.accent)
                            Text("Joining…")
                                .font(GSFont.body(14, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    if let joinError {
                        Text(joinError)
                            .font(GSFont.body(13, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
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
