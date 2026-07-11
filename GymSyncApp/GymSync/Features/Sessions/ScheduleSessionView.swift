import SwiftUI

// MARK: - ScheduleSessionView

struct ScheduleSessionView: View {
    let onScheduled: (WorkoutSession) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    // MARK: - Who selection
    enum WhoMode: String, CaseIterable {
        case group   = "Group"
        case friends = "Friends"
        case code    = "Code"
    }

    @State private var whoMode: WhoMode = .group

    // Group mode
    @State private var groups: [GymGroup] = []
    @State private var selectedGroup: GymGroup?
    @State private var groupMemberIDs: [UUID] = []  // excludes self

    // Friends mode
    @State private var friends: [Profile] = []
    @State private var selectedFriendIDs: Set<UUID> = []

    // MARK: - What (routine)
    @State private var routines: [Routine] = []
    @State private var selectedRoutine: Routine?

    // MARK: - When
    @State private var scheduledFor: Date = Self.nextFullHour()

    // MARK: - State
    @State private var isScheduling = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            Form {
                whoSection
                whatSection
                whenSection
                if let errorText {
                    Section {
                        Text(errorText).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .navigationTitle("Schedule Session")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Schedule") { Task { await schedule() } }
                        .disabled(isScheduleButtonDisabled || isScheduling)
                }
            }
            .task { await loadData() }
            .onChange(of: selectedGroup) {
                Task { await loadGroupMembers() }
            }
        }
    }

    // MARK: - Who Section

    private var whoSection: some View {
        Section("Who") {
            Picker("Mode", selection: $whoMode) {
                ForEach(WhoMode.allCases, id: \.self) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            switch whoMode {
            case .group:
                groupPicker
            case .friends:
                friendsMultiSelect
            case .code:
                Text("A room code will be generated — share it so others can join.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var groupPicker: some View {
        if groups.isEmpty {
            Text("You have no groups yet.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Group", selection: $selectedGroup) {
                Text("Select a group").tag(Optional<GymGroup>.none)
                ForEach(groups) { group in
                    Text(group.name).tag(Optional(group))
                }
            }
        }
    }

    @ViewBuilder
    private var friendsMultiSelect: some View {
        if friends.isEmpty {
            Text("No friends to invite yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(friends) { friend in
                Button {
                    if selectedFriendIDs.contains(friend.id) {
                        selectedFriendIDs.remove(friend.id)
                    } else {
                        selectedFriendIDs.insert(friend.id)
                    }
                } label: {
                    HStack {
                        Text(friend.username).foregroundStyle(.primary)
                        Spacer()
                        if selectedFriendIDs.contains(friend.id) {
                            Image(systemName: "checkmark").foregroundStyle(.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - What Section

    private var whatSection: some View {
        Section("Routine (optional)") {
            Picker("Routine", selection: $selectedRoutine) {
                Text("None").tag(Optional<Routine>.none)
                ForEach(routines) { routine in
                    Text(routine.name).tag(Optional(routine))
                }
            }
        }
    }

    // MARK: - When Section

    private var whenSection: some View {
        Section("When") {
            DatePicker(
                "Date & Time",
                selection: $scheduledFor,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
        }
    }

    // MARK: - Validation

    private var isScheduleButtonDisabled: Bool {
        switch whoMode {
        case .group:    return selectedGroup == nil
        case .friends:  return false  // zero invitees is allowed — solo slot with friends-mode
        case .code:     return false
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadData() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        async let fetchGroups  = GroupRepository.myGroups()
        async let fetchFriends = FriendRepository.friends()
        async let fetchRoutines = RoutineRepository.fetchAll(ownerID: ownerID)
        do {
            let (g, f, r) = try await (fetchGroups, fetchFriends, fetchRoutines)
            groups = g
            friends = f
            routines = r
            if selectedGroup == nil { selectedGroup = g.first }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    @MainActor
    private func loadGroupMembers() async {
        guard let group = selectedGroup else {
            groupMemberIDs = []
            return
        }
        guard let selfID = appState.currentProfile?.id else { return }
        do {
            let members = try await GroupRepository.members(groupID: group.id)
            groupMemberIDs = members
                .map(\.member.userID)
                .filter { $0 != selfID }
        } catch {
            AppLogger.db.error("loadGroupMembers failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    @MainActor
    private func schedule() async {
        isScheduling = true
        defer { isScheduling = false }
        errorText = nil

        let groupID: UUID?
        let inviteeIDs: [UUID]
        let generateRoomCode: Bool

        switch whoMode {
        case .group:
            guard let group = selectedGroup else {
                errorText = "Please select a group."
                return
            }
            groupID = group.id
            inviteeIDs = groupMemberIDs
            generateRoomCode = false
        case .friends:
            groupID = nil
            inviteeIDs = Array(selectedFriendIDs)
            generateRoomCode = false
        case .code:
            groupID = nil
            inviteeIDs = []
            generateRoomCode = true
        }

        do {
            let session = try await SessionRepository.schedule(
                groupID: groupID,
                inviteeIDs: inviteeIDs,
                routineID: selectedRoutine?.id,
                scheduledFor: scheduledFor,
                generateRoomCode: generateRoomCode
            )
            onScheduled(session)
            dismiss()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private static func nextFullHour() -> Date {
        let now = Date()
        let cal = Calendar.current
        var comps = cal.dateComponents([.year, .month, .day, .hour], from: now)
        comps.hour = (comps.hour ?? 0) + 1
        comps.minute = 0
        comps.second = 0
        return cal.date(from: comps) ?? now.addingTimeInterval(3600)
    }
}
