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
    @State private var selectedGroupID: UUID?
    @State private var groupMemberIDs: [UUID] = []  // excludes self

    // Friends mode
    @State private var friends: [Profile] = []
    @State private var selectedFriendIDs: Set<UUID> = []

    // MARK: - What (routine) — use UUID selection to avoid Hashable requirement on Routine
    @State private var routines: [Routine] = []
    @State private var selectedRoutineID: UUID?

    // MARK: - When
    @State private var scheduledFor: Date = Self.nextFullHour()

    // MARK: - Repeat weekly (Group-only)
    @State private var repeatWeekly: Bool = false
    @State private var selectedWeekdays: Set<Int> = []
    @State private var dayTimes: [Int: DayTime] = [:]
    @State private var dayRoutines: [Int: UUID?] = [:]
    @State private var untilDate: Date = Date().addingTimeInterval(8 * 7 * 86400)
    @State private var occurrenceCount: Int = 0

    // MARK: - State
    @State private var isScheduling = false
    @State private var errorText: String?

    // MARK: - Computed

    private var selectedGroup: GymGroup? {
        groups.first { $0.id == selectedGroupID }
    }

    private var selectedRoutine: Routine? {
        routines.first { $0.id == selectedRoutineID }
    }

    private var defaultHour: Int {
        Calendar.current.component(.hour, from: scheduledFor)
    }

    private var defaultMinute: Int {
        Calendar.current.component(.minute, from: scheduledFor)
    }

    var body: some View {
        NavigationStack {
            Form {
                whoSection
                whatSection
                whenSection
                if whoMode == .group {
                    repeatsSection
                }
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
            .onChange(of: selectedGroupID) {
                Task { await loadGroupMembers() }
            }
            .onChange(of: scheduledFor) { updateOccurrenceCount() }
            .onChange(of: selectedWeekdays) { updateOccurrenceCount() }
            .onChange(of: dayTimes) { updateOccurrenceCount() }
            .onChange(of: untilDate) { updateOccurrenceCount() }
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

            if whoMode == .group {
                groupPickerContent
            } else if whoMode == .friends {
                friendsMultiSelectContent
            } else {
                Text("A room code will be generated — share it so others can join.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var groupPickerContent: some View {
        if groups.isEmpty {
            Text("You have no groups yet.")
                .foregroundStyle(.secondary)
        } else {
            Picker("Group", selection: $selectedGroupID) {
                Text("Select a group").tag(Optional<UUID>.none)
                ForEach(groups) { group in
                    Text(group.name).tag(Optional(group.id))
                }
            }
        }
    }

    @ViewBuilder
    private var friendsMultiSelectContent: some View {
        if friends.isEmpty {
            Text("No friends to invite yet.")
                .foregroundStyle(.secondary)
        } else {
            ForEach(friends, id: \.id) { friend in
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
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
            }
        }
    }

    // MARK: - What Section

    private var whatSection: some View {
        Section("Routine (optional)") {
            Picker("Routine", selection: $selectedRoutineID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(routines, id: \.id) { routine in
                    Text(routine.name).tag(Optional(routine.id))
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

    // MARK: - Repeats Section

    @ViewBuilder
    private var repeatsSection: some View {
        Section("Repeats") {
            Toggle("Repeat weekly", isOn: $repeatWeekly)
                .onChange(of: repeatWeekly) {
                    if repeatWeekly && selectedWeekdays.isEmpty {
                        // Pre-select the weekday of the chosen date
                        let wd = Calendar.current.component(.weekday, from: scheduledFor)
                        selectedWeekdays.insert(wd)
                        dayTimes[wd] = DayTime(hour: defaultHour, minute: defaultMinute)
                        dayRoutines[wd] = selectedRoutineID
                    }
                    updateOccurrenceCount()
                }

            if repeatWeekly {
                weekdayRuleEditorContent
                untilDateContent
                occurrenceFooter
            }
        }
    }

    // Decomposed to help the type-checker
    @ViewBuilder
    private var weekdayRuleEditorContent: some View {
        WeekdayRuleEditor(
            selectedWeekdays: $selectedWeekdays,
            dayTimes: $dayTimes,
            dayRoutines: $dayRoutines,
            defaultHour: defaultHour,
            defaultMinute: defaultMinute,
            defaultRoutineID: selectedRoutineID,
            routines: routines
        )
    }

    @ViewBuilder
    private var untilDateContent: some View {
        let minDate = Date().addingTimeInterval(86400)
        let maxDate = Date().addingTimeInterval(26 * 7 * 86400)
        DatePicker(
            "Until",
            selection: $untilDate,
            in: minDate...maxDate,
            displayedComponents: .date
        )
    }

    @ViewBuilder
    private var occurrenceFooter: some View {
        if occurrenceCount > 0 {
            Text("\(occurrenceCount) sessions will be scheduled")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Validation

    private var isScheduleButtonDisabled: Bool {
        switch whoMode {
        case .group:
            if selectedGroupID == nil { return true }
            if repeatWeekly && selectedWeekdays.isEmpty { return true }
            return false
        case .friends:  return false
        case .code:     return false
        }
    }

    // MARK: - Actions

    @MainActor
    private func loadData() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        async let fetchGroups   = GroupRepository.myGroups()
        async let fetchFriends  = FriendRepository.friends()
        async let fetchRoutines = RoutineRepository.fetchAll(ownerID: ownerID)
        do {
            let (g, f, r) = try await (fetchGroups, fetchFriends, fetchRoutines)
            groups = g
            friends = f
            routines = r
            if selectedGroupID == nil { selectedGroupID = g.first?.id }
        } catch {
            errorText = ErrorMapping.map(error).errorDescription
        }
    }

    @MainActor
    private func loadGroupMembers() async {
        guard let groupID = selectedGroupID else {
            groupMemberIDs = []
            return
        }
        guard let selfID = appState.currentProfile?.id else { return }
        do {
            let members = try await GroupRepository.members(groupID: groupID)
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
            guard let gid = selectedGroupID else {
                errorText = "Please select a group."
                return
            }
            groupID = gid
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

        // Repeating series path (Group only)
        if whoMode == .group, repeatWeekly, let gid = groupID {
            do {
                let days = buildSeriesDayInputs()
                guard !days.isEmpty else {
                    errorText = "Select at least one day."
                    return
                }
                let series = try await SeriesRepository.create(
                    groupID: gid,
                    days: days,
                    untilDate: untilDate,
                    timezone: .current
                )
                let occurrences = try await SeriesRepository.occurrences(seriesID: series.id)
                if let first = occurrences.first {
                    onScheduled(first)
                }
                dismiss()
            } catch let error as GymSyncError {
                errorText = error.errorDescription
            } catch {
                errorText = error.localizedDescription
            }
            return
        }

        // Single-session path (unchanged)
        do {
            let session = try await SessionRepository.schedule(
                groupID: groupID,
                inviteeIDs: inviteeIDs,
                routineID: selectedRoutineID,
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

    // MARK: - Repeat helpers

    private func buildSeriesDayInputs() -> [SeriesDayInput] {
        selectedWeekdays.sorted().map { wd in
            let dt = dayTimes[wd] ?? DayTime(hour: defaultHour, minute: defaultMinute)
            let routineID: UUID? = dayRoutines[wd] ?? nil
            return SeriesDayInput(
                weekday: wd,
                hour: dt.hour,
                minute: dt.minute,
                routineID: routineID
            )
        }
    }

    private func updateOccurrenceCount() {
        guard repeatWeekly, !selectedWeekdays.isEmpty else {
            occurrenceCount = 0
            return
        }
        let days = buildSeriesDayInputs()
        let pairs = SeriesRepository.occurrenceDates(
            days: days,
            from: Date(),
            until: untilDate,
            timezone: .current
        )
        occurrenceCount = pairs.count
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
