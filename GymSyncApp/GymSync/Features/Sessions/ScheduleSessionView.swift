import SwiftUI

// MARK: - ScheduleSessionView

struct ScheduleSessionView: View {
    let onScheduled: (WorkoutSession) -> Void
    /// Phase L Task 3 — "Attempt with Friends" preload: the Discover routine
    /// this sheet was launched to schedule around. Seeds `selectedRoutineID`
    /// and is spliced into the routine picker's list even when it isn't one
    /// of the caller's OWN routines (`routines` below normally comes from
    /// `RoutineRepository.fetchAll(ownerID:)`, which never returns a public
    /// routine the scheduler doesn't own — see `loadData()`). `nil` for
    /// every other caller (Home's own "+ Schedule Session" sheet — unchanged).
    let preloadedRoutine: Routine?

    /// `preselectedGroupID` (owner 2026-08-13, crew-room "nothing on the
    /// books" entry): seeds the group picker so scheduling launched FROM a
    /// crew room lands on that crew. `loadData()`'s first-group default
    /// only fills a nil selection, so the seed survives the fetch. nil for
    /// every other caller — unchanged.
    init(preloadedRoutine: Routine? = nil,
         preselectedGroupID: UUID? = nil,
         onScheduled: @escaping (WorkoutSession) -> Void) {
        self.preloadedRoutine = preloadedRoutine
        self.onScheduled = onScheduled
        _selectedRoutineID = State(initialValue: preloadedRoutine?.id)
        _selectedGroupID = State(initialValue: preselectedGroupID)
    }

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    // MARK: - Who selection
    /// Owner report 2026-08-02: "there's not an option to schedule a session
    /// by yourself." Every mode here invited someone, so a planned solo lift
    /// — the most common kind — was unschedulable. `.solo` leads the segments
    /// because it's the simplest case, but the default stays `.group` so the
    /// crew-scheduling flow people already know is unchanged.
    enum WhoMode: String, CaseIterable {
        case solo    = "Just me"
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
    @State private var routineExerciseCounts: [UUID: Int] = [:]

    // MARK: - When
    @State private var scheduledFor: Date = Self.nextFullHour()

    // MARK: - Repeat weekly (Group-only)
    @State private var repeatWeekly: Bool = false
    // Weekly target (owner 2026-08-24: "it's just another way to
    // schedule workouts week to week") — for opportunistic gym-goers:
    // instead of a fixed-day series, commit to N days a week. Writes
    // the standing weekly goal the Home slots widget already tracks
    // (Profile.weeklySessionGoal); auto-checks from completed sessions.
    // Solo-only — a crew schedules real days, not a personal quota.
    @State private var useWeeklyTarget: Bool = false
    @State private var weeklyTarget: Int = 3
    /// 1 = weekly, 2 = every other week (field report #9).
    @State private var repeatInterval: Int = 1
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

    // MARK: - Body
    // Canvas: custom non-Form scroll layout; sections separated by GSDivider;
    //   bg background, surface cards, Archivo type throughout.

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // WHO section
                    whoSection

                    Spacer().frame(height: 8)

                    // WHEN section
                    whenSection

                    Spacer().frame(height: 8)

                    // ROUTINE section
                    whatSection

                    // REPEATS section — group or solo. Friends/Code invites are
                    // one-off by design (there's no standing roster to recur
                    // against); a solo series recurs against just you.
                    if whoMode == .group || whoMode == .solo {
                        Spacer().frame(height: 8)
                        repeatsSection
                    }

                    // Error
                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }

                    Spacer(minLength: 80)
                }
            }
            .background(theme.bg)
            .scrollContentBackground(.hidden)
            .safeAreaInset(edge: .bottom) {
                // Pinned CTA — "Schedule" / "Create series"
                VStack(spacing: 0) {
                    GSDivider()
                    Button {
                        Task { await schedule() }
                    } label: {
                        HStack {
                            Text(repeatWeekly ? "Create series" : "Schedule")
                                .font(GSFont.bold(15, relativeTo: .body))
                            Spacer()
                            if repeatWeekly && occurrenceCount > 0 {
                                Text("\(occurrenceCount) sessions")
                                    .font(GSFont.body(13, relativeTo: .subheadline))
                                    .foregroundStyle(theme.bg.opacity(0.8))
                            }
                        }
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .frame(maxWidth: .infinity)
                    }
                    // 3D pass (2026-08 sweep): the pinned CTA is extruded. The
                    // face carries the SAME disabled/enabled fill the label's
                    // own background used to (neutral400 vs accent) so the
                    // inert look is unchanged; the lip derives from it.
                    .buttonStyle(.gs3D(
                        face: (isScheduleButtonDisabled || isScheduling)
                            ? theme.neutral400
                            : theme.accent,
                        cornerRadius: GSMetrics.radiusSm))
                    .disabled(isScheduleButtonDisabled || isScheduling)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(theme.bg)
                }
            }
            .navigationTitle("Schedule")
            .scrollDismissesKeyboard(.interactively)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Next") { Task { await schedule() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(
                            (isScheduleButtonDisabled || isScheduling)
                                ? theme.neutral500 : theme.accent
                        )
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
    // Canvas: "Who's invited" kicker, themed segmented control, bordered group/friend rows

    private var whoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Who's invited")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // Themed segmented control — same pattern as GroupView
            themedWhoSegment
                .padding(.horizontal, 16)

            // Content for selected mode
            switch whoMode {
            case .solo:
                Text("A solo session — just you. It'll show on your calendar and count toward your streak.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
            case .group:
                groupPickerContent
                    .padding(.horizontal, 16)
            case .friends:
                friendsMultiSelectContent
                    .padding(.horizontal, 16)
            case .code:
                Text("A room code will be generated — share it so others can join.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.bottom, 14)
    }

    // Redesign (user feedback 2026-07-23: "the old art style has persisted"):
    // pill segments in a rounded surface container — same treatment as
    // Library's segmented control.
    private var themedWhoSegment: some View {
        HStack(spacing: 3) {
            ForEach(WhoMode.allCases, id: \.self) { mode in
                Button {
                    whoMode = mode
                } label: {
                    Text(mode.rawValue)
                        .font(GSFont.bold(12.5, relativeTo: .caption))
                        .foregroundStyle(whoMode == mode ? theme.bg : theme.neutral700)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(whoMode == mode ? theme.accent : Color.clear)
                        .cornerRadius(9)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusSm)   // redesign: rounded row
        .cornerRadius(13)
    }

    @ViewBuilder
    private var groupPickerContent: some View {
        if groups.isEmpty {
            Text("You have no groups yet.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
        } else {
            // Canvas: bordered row with initials avatar + name + member count + chevron
            Menu {
                Picker("Group", selection: $selectedGroupID) {
                    Text("Select a group").tag(Optional<UUID>.none)
                    ForEach(groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    // Initials avatar
                    let name = selectedGroup?.name ?? "?"
                    let initials = String(name.prefix(2)).uppercased()
                    ZStack {
                        Rectangle()
                            .fill(theme.accent)
                            .frame(width: 32, height: 32)
                        Text(initials)
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .foregroundStyle(theme.bg)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedGroup?.name ?? "Select a group")
                            .font(GSFont.bold(14, relativeTo: .headline))
                            .foregroundStyle(selectedGroup != nil ? theme.text : theme.neutral500)
                        if selectedGroup != nil {
                            Text("\(groupMemberIDs.count + 1) members")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                // gs3D pass (2026-08-13): the tappable picker row sits
                // proud (static depth — Menu owns the tap; form inputs
                // like the segmented control stay flat as furniture).
                .gs3DCard(cornerRadius: GSMetrics.radiusSm)
            }
        }
    }

    @ViewBuilder
    private var friendsMultiSelectContent: some View {
        if friends.isEmpty {
            Text("No friends to invite yet.")
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
        } else {
            VStack(spacing: 0) {
                ForEach(friends, id: \.id) { friend in
                    let isSelected = selectedFriendIDs.contains(friend.id)
                    Button {
                        if isSelected {
                            selectedFriendIDs.remove(friend.id)
                        } else {
                            selectedFriendIDs.insert(friend.id)
                        }
                    } label: {
                        HStack(spacing: 10) {
                            // Initials avatar
                            let initials = String(friend.username.prefix(2)).uppercased()
                            ZStack {
                                Rectangle()
                                    .fill(isSelected ? theme.accent : theme.neutral400)
                                    .frame(width: 32, height: 32)
                                Text(initials)
                                    .font(GSFont.bold(11, relativeTo: .caption2))
                                    .foregroundStyle(theme.bg)
                            }

                            Text(friend.username)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(theme.accent)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 9)
                        .overlay(
                            isSelected
                                ? RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                                    .strokeBorder(theme.accent, lineWidth: 2)
                                : nil
                        )
                        .contentShape(Rectangle())
                    }
                    // gs3D pass (2026-08-13): sinking extruded row; label
                    // sheds its fills, selection reads as the accent ring
                    // (pickCard precedent).
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                    .padding(.bottom, 4)
                }
            }
        }
    }

    // MARK: - What Section
    // Canvas: "Routine" kicker, bordered picker row

    private var whatSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Routine")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            // Bordered row with dumbbell icon + routine name + chevron
            Menu {
                Picker("Routine", selection: $selectedRoutineID) {
                    Text("None").tag(Optional<UUID>.none)
                    ForEach(routines, id: \.id) { routine in
                        Text(routine.name).tag(Optional(routine.id))
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "dumbbell")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(theme.accent)
                        .frame(width: 20)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(selectedRoutine?.name ?? "None")
                            .font(GSFont.bold(14, relativeTo: .headline))
                            .foregroundStyle(selectedRoutine != nil ? theme.text : theme.neutral500)
                        if let routine = selectedRoutine,
                           let count = routineExerciseCounts[routine.id] {
                            Text("\(count) exercises · ~\(StatMath.estimatedMinutes(exerciseCount: count)) min")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                // gs3D pass (2026-08-13): tappable picker row, static depth.
                .gs3DCard(cornerRadius: GSMetrics.radiusSm)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    // MARK: - When Section
    // Canvas: DATE + TIME side-by-side bordered tiles

    private var whenSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("When")
                .padding(.horizontal, 16)
                .padding(.top, 14)

            HStack(spacing: 8) {
                // Date tile
                VStack(alignment: .leading, spacing: 2) {
                    Text("DATE")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(theme.neutral500)
                    DatePicker(
                        "",
                        selection: $scheduledFor,
                        in: Date()...,
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .tint(theme.accent)
                    .font(GSFont.bold(15, relativeTo: .body))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusSm)   // redesign: rounded row
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                // Time tile
                VStack(alignment: .leading, spacing: 2) {
                    Text("TIME")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(theme.neutral500)
                    DatePicker(
                        "",
                        selection: $scheduledFor,
                        in: Date()...,
                        displayedComponents: .hourAndMinute
                    )
                    .labelsHidden()
                    .tint(theme.accent)
                    .font(GSFont.bold(15, relativeTo: .body))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(theme.surface)
                .cornerRadius(GSMetrics.radiusSm)   // redesign: rounded row
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 14)
    }

    // MARK: - Repeats Section
    // Canvas: Toggle row with accent pill-toggle, then weekday chips + per-day rows + until

    @ViewBuilder
    private var repeatsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Repeats toggle row
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Repeats")
                        .font(GSFont.bold(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text("Make this a recurring series")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }

                Spacer()

                Toggle("", isOn: $repeatWeekly)
                    .labelsHidden()
                    .tint(theme.accent)
                    .onChange(of: repeatWeekly) {
                        if repeatWeekly { useWeeklyTarget = false }
                        if repeatWeekly && selectedWeekdays.isEmpty {
                            let wd = Calendar.current.component(.weekday, from: scheduledFor)
                            selectedWeekdays.insert(wd)
                            dayTimes[wd] = DayTime(hour: defaultHour, minute: defaultMinute)
                            dayRoutines[wd] = selectedRoutineID
                        }
                        updateOccurrenceCount()
                    }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if whoMode == .solo && !repeatWeekly {
                GSDivider()
                    .padding(.horizontal, 16)

                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Weekly target")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text("No fixed days — commit to a number, train when you can")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    Spacer()
                    Toggle("", isOn: $useWeeklyTarget)
                        .labelsHidden()
                        .tint(theme.accent)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)

                if useWeeklyTarget {
                    HStack(spacing: 12) {
                        Text("\(weeklyTarget) day\(weeklyTarget == 1 ? "" : "s") a week")
                            .font(GSFont.bold(14, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                            .monospacedDigit()
                        Spacer()
                        Stepper("", value: $weeklyTarget, in: 1...7)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    Text("The Home streak card tracks it — any day you finish a workout fills a slot.")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                        .padding(.bottom, 12)
                }
            }

            if repeatWeekly {
                GSDivider()
                    .padding(.horizontal, 16)

                // Cadence: weekly or every other week. The anchor is the
                // creation day, so "every other" starts counting now.
                HStack(spacing: 6) {
                    ForEach([(1, "Every week"), (2, "Every other week")], id: \.0) { value, label in
                        let isOn = repeatInterval == value
                        Button {
                            repeatInterval = value
                            updateOccurrenceCount()
                        } label: {
                            Text(label)
                                .font(GSFont.bold(12, relativeTo: .caption))
                                .foregroundStyle(isOn ? theme.bg : theme.neutral700)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(isOn ? theme.accent : theme.surface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)

                // "On these days" kicker + chips
                VStack(alignment: .leading, spacing: 6) {
                    Text("ON THESE DAYS")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(theme.neutral500)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                    weekdayRuleEditorContent
                        .padding(.horizontal, 16)
                }

                GSDivider()
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                // Until row
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Until")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                        untilDateContent
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                occurrenceFooter
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
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
            "",
            selection: $untilDate,
            in: minDate...maxDate,
            displayedComponents: .date
        )
        .labelsHidden()
        .tint(theme.accent)
        .font(GSFont.bold(14, relativeTo: .body))
    }

    @ViewBuilder
    private var occurrenceFooter: some View {
        if occurrenceCount > 0 {
            Text("\(occurrenceCount) sessions will be scheduled")
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral500)
        }
    }

    // MARK: - Validation

    private var isScheduleButtonDisabled: Bool {
        switch whoMode {
        case .group:
            if selectedGroupID == nil { return true }
            if repeatWeekly && selectedWeekdays.isEmpty { return true }
            return false
        case .solo:
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
            // Splice the Discover "Attempt with Friends" preload into the
            // picker's list even when the scheduler doesn't own it —
            // `RoutineRepository.fetchAll(ownerID:)` above only ever returns
            // the caller's OWN routines, but `preloadedRoutine` may be a
            // public routine reached from Discover.
            if let preloadedRoutine, !r.contains(where: { $0.id == preloadedRoutine.id }) {
                routines = [preloadedRoutine] + r
            } else {
                routines = r
            }
            if selectedGroupID == nil { selectedGroupID = g.first?.id }

            let exercises = (try? await RoutineRepository.exercisesForRoutines(
                ids: routines.map(\.id))) ?? []
            routineExerciseCounts = Dictionary(
                grouping: exercises, by: \.routineID
            ).mapValues(\.count)
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
        case .solo:
            // No group, no invitees, no room code — `SessionRepository.schedule`
            // already adds the organizer as a participant, so the session lands
            // shaped exactly like a solo workout that happens to be planned.
            groupID = nil
            inviteeIDs = []
            generateRoomCode = false
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

        // Weekly-target path (solo): the standing commitment is a goal,
        // not a series. Best-effort — the session booking below is the
        // primary action and proceeds regardless.
        if whoMode == .solo, useWeeklyTarget {
            _ = try? await ProfileRepository.updateWeeklySessionGoal(weeklyTarget)
        }

        // Repeating series path (Group only)
        // Repeating path — group series (gid non-nil) or solo series (nil).
        // `SeriesRepository.create` takes an optional group since 2026-08-02.
        if (whoMode == .group || whoMode == .solo), repeatWeekly {
            do {
                let days = buildSeriesDayInputs()
                guard !days.isEmpty else {
                    errorText = "Select at least one day."
                    return
                }
                let series = try await SeriesRepository.create(
                    groupID: groupID,
                    days: days,
                    untilDate: untilDate,
                    timezone: .current,
                    intervalWeeks: repeatInterval
                )
                let occurrences = try await SeriesRepository.occurrences(seriesID: series.id)
                if let first = occurrences.first {
                    onScheduled(first)
                }
                dismiss()
                // EventKit sync (Phase H Task 2; moved AFTER dismiss in
                // Phase O Task 2): organizer-side, gated on the You-tab
                // toggle. `occurrences` is exactly the series' MATERIALIZED
                // set (bounded — `SeriesRepository.create` never
                // open-ended-recurs), so this creates one calendar event
                // per already-materialized session row, no more. The
                // server write (already awaited above) is what
                // `onScheduled` needed — the per-occurrence EventKit loop
                // no longer gates the sheet close; it now runs fire-and-
                // forget in a detached `Task`, best-effort as always
                // (`EventKitBridge.syncEvent` never throws).
                //
                // TRUE recovery picture if the app is killed mid-loop
                // (corrected — Phase O Task 2 fix wave 1, reviewer Finding
                // 2; the previous version of this comment overstated
                // re-toggle as full recovery). `EventKitBridge.reconcile()`'s
                // app-foreground sweep is NOT the safety net here (this loop
                // only ADDS events, reconcile only REMOVES stale ones).
                // Occurrences the loop hadn't REACHED yet ARE fully
                // recovered by toggling calendar sync off/on again
                // (re-triggers `backfillCalendarSync`, which syncs every
                // upcoming organized session with no existing mapping). But
                // the ONE occurrence `syncEvent` was actively processing at
                // the moment of the kill has a narrower, worse failure mode:
                // see `EventKitBridge.syncEvent`'s own "HONEST FAILURE MODE"
                // doc comment — if the kill lands in the one-statement-wide
                // window between `store.save` and
                // `SessionCalendarSyncStore.setEventIdentifier`, that
                // event becomes a PERMANENT orphan (invisible to every
                // recovery path here, all of which only look at mapped
                // ids), and the next backfill creates a DUPLICATE for it
                // rather than recovering it. Re-toggling is not a full fix
                // for a mid-loop kill — it's a fix for the unreached tail
                // only.
                Task { await syncScheduledSessionsToCalendar(occurrences) }
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
            // EventKit sync: see the series path's comment above — same
            // helper, post-dismiss Task, single-session list.
            Task { await syncScheduledSessionsToCalendar([session]) }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Calendar sync (Phase H Task 2)

    /// Best-effort EventKit sync for freshly-scheduled sessions — gated on
    /// the You-tab toggle (`CalendarSyncPrefsStore.isEnabled()`; see
    /// `YouTabView.calendarSyncRow`). Called ONLY after the corresponding
    /// server write (`SessionRepository.schedule` / `SeriesRepository.
    /// create`) has already returned successfully — a calendar failure here
    /// can never roll back or block the session that was just created
    /// (`EventKitBridge.syncEvent` never throws). Routine name + exercise
    /// count come from this view's own already-loaded `routines`/
    /// `routineExerciseCounts` state (`loadData()` above) — no extra fetch.
    @MainActor
    private func syncScheduledSessionsToCalendar(_ sessions: [WorkoutSession]) async {
        guard CalendarSyncPrefsStore.isEnabled() else { return }
        for session in sessions {
            let routine = session.routineID.flatMap { rid in routines.first { $0.id == rid } }
            let exerciseCount = session.routineID.flatMap { routineExerciseCounts[$0] }
            await EventKitBridge.syncEvent(session: session, routineName: routine?.name, exerciseCount: exerciseCount)
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
            timezone: .current,
            intervalWeeks: repeatInterval,
            anchor: Date()
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
