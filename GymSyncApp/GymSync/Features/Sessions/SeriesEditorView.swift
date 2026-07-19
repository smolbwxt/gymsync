import SwiftUI

// MARK: - DayTime

/// Equatable time value used as per-weekday dictionary value.
struct DayTime: Equatable {
    var hour: Int
    var minute: Int
}

// MARK: - WeekdayRuleEditor
//
// Shared weekday-chip + per-day time/routine editor.
// Used by both ScheduleSessionView (repeats section) and SeriesEditorView.

struct WeekdayRuleEditor: View {
    /// The currently selected weekday values (1=Sun…7=Sat).
    @Binding var selectedWeekdays: Set<Int>
    /// Per-weekday time selection. Keyed by weekday int.
    @Binding var dayTimes: [Int: DayTime]
    /// Per-weekday routine selection. Keyed by weekday int.
    @Binding var dayRoutines: [Int: UUID?]
    /// Default time to apply when a chip is first selected.
    var defaultHour: Int
    var defaultMinute: Int
    /// Default routine UUID to apply when a chip is first selected.
    var defaultRoutineID: UUID?
    /// Full list of routines for the picker.
    var routines: [Routine]

    @Environment(\.gsTheme) private var theme

    // Canvas: S M T W T F S  (weekday 1=Sun → 7=Sat)
    private let weekdays: [(label: String, value: Int)] = [
        ("S", 1), ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7)
    ]

    var body: some View {
        chipRow
        perDayRows
    }

    // MARK: - Chip row
    // Canvas: square chips, aspect-ratio 1, accent fill when selected,
    //   1px divider border + muted text when deselected; Archivo Bold 13pt; zero radius.

    @ViewBuilder
    private var chipRow: some View {
        HStack(spacing: 5) {
            ForEach(weekdays, id: \.value) { day in
                let selected = selectedWeekdays.contains(day.value)
                Button {
                    if selected {
                        selectedWeekdays.remove(day.value)
                        dayTimes.removeValue(forKey: day.value)
                        dayRoutines.removeValue(forKey: day.value)
                    } else {
                        selectedWeekdays.insert(day.value)
                        dayTimes[day.value] = DayTime(hour: defaultHour, minute: defaultMinute)
                        dayRoutines[day.value] = defaultRoutineID
                    }
                } label: {
                    Text(day.label)
                        .font(GSFont.bold(13, relativeTo: .body))
                        .foregroundStyle(selected ? theme.bg : theme.neutral500)
                        .frame(maxWidth: .infinity)
                        .aspectRatio(1, contentMode: .fit)
                        .background(selected ? theme.accent : Color.clear)
                        .overlay(
                            selected ? nil :
                                Rectangle().strokeBorder(theme.divider, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Per-day rows
    // Canvas: bordered row, accent-700 day label (3-letter), divider separator,
    //   Bold time, muted routine name trailing.

    @ViewBuilder
    private var perDayRows: some View {
        let sorted = selectedWeekdays.sorted()
        ForEach(sorted, id: \.self) { wd in
            perDayRow(weekday: wd)
        }
    }

    @ViewBuilder
    private func perDayRow(weekday: Int) -> some View {
        let shortNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let name = shortNames[(weekday - 1) % 7]

        let defaultDayTime = DayTime(hour: defaultHour, minute: defaultMinute)

        let timeBinding = Binding<Date>(
            get: {
                let dt = dayTimes[weekday] ?? defaultDayTime
                return Self.dateFromDayTime(dt)
            },
            set: { newDate in
                let comps = Calendar.current.dateComponents([.hour, .minute], from: newDate)
                dayTimes[weekday] = DayTime(
                    hour: comps.hour ?? defaultHour,
                    minute: comps.minute ?? defaultMinute
                )
            }
        )

        let routineBinding = Binding<UUID?>(
            get: { dayRoutines[weekday] ?? nil },
            set: { dayRoutines[weekday] = $0 }
        )

        // Canvas per-day row: [accent-700 day name | divider | time | trailing: routine muted]
        HStack(spacing: 0) {
            Text(name)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.accent700)
                .frame(width: 40, alignment: .leading)

            Rectangle()
                .fill(theme.divider)
                .frame(width: 1)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)

            DatePicker("", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .tint(theme.accent)

            Spacer()

            Picker("", selection: routineBinding) {
                Text("None").tag(Optional<UUID>.none)
                    .font(GSFont.body(11, relativeTo: .caption))
                ForEach(routines, id: \.id) { routine in
                    Text(routine.name).tag(Optional(routine.id))
                        .font(GSFont.body(11, relativeTo: .caption))
                }
            }
            .pickerStyle(.menu)
            .font(GSFont.body(11, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Helpers

    private static func dateFromDayTime(_ dt: DayTime) -> Date {
        var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        comps.hour = dt.hour
        comps.minute = dt.minute
        comps.second = 0
        return Calendar.current.date(from: comps) ?? Date()
    }
}

// MARK: - SeriesEditorView

/// Edit the day-rules and until-date of an existing session series.
/// Changes apply to future sessions only (via `editSeriesForward`).
struct SeriesEditorView: View {
    let seriesID: UUID
    let onSaved: () -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var series: SessionSeries?
    @State private var selectedWeekdays: Set<Int> = []
    @State private var dayTimes: [Int: DayTime] = [:]
    @State private var dayRoutines: [Int: UUID?] = [:]
    @State private var untilDate: Date = Date().addingTimeInterval(8 * 7 * 86400)
    @State private var routines: [Routine] = []
    // Phase O Task 2: per-routine exercise counts, threaded into EventKit
    // sync in `save()` below — see `loadData()`'s doc comment for why this
    // was added (kills the 60-min generic-duration fallback for
    // routine-assigned occurrences).
    @State private var routineExerciseCounts: [UUID: Int] = [:]

    @State private var isLoading = true
    @State private var isSaving = false
    @State private var errorText: String?

    // MARK: - Validation

    private var canSave: Bool {
        !selectedWeekdays.isEmpty && !isSaving
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView("Loading series…")
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .background(theme.bg)
                } else {
                    editorForm
                }
            }
            .navigationTitle("Edit Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral700)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(GSFont.bold(14, relativeTo: .body))
                        .foregroundStyle(canSave ? theme.accent700 : theme.neutral500)
                        .disabled(!canSave)
                }
            }
            .task { await loadData() }
        }
    }

    // MARK: - Form

    private var editorForm: some View {
        List {
            // Repeat on section
            Section {
                WeekdayRuleEditor(
                    selectedWeekdays: $selectedWeekdays,
                    dayTimes: $dayTimes,
                    dayRoutines: $dayRoutines,
                    defaultHour: defaultHour,
                    defaultMinute: defaultMinute,
                    defaultRoutineID: nil,
                    routines: routines
                )
            } header: {
                GSSectionHeader("Repeat on")
            }
            .listRowBackground(theme.bg)
            .listRowSeparatorTint(theme.divider)

            // Until section
            Section {
                let minDate = Date().addingTimeInterval(86400)
                let maxDate = Date().addingTimeInterval(26 * 7 * 86400)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Until")
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                        DatePicker(
                            "",
                            selection: $untilDate,
                            in: minDate...maxDate,
                            displayedComponents: .date
                        )
                        .labelsHidden()
                        .tint(theme.accent)
                    }
                    Spacer()
                }
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.divider)
            }

            // Caption
            Section {
                Text("Changes apply to future sessions only.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
                    .listRowBackground(theme.bg)
            }

            // Error
            if let errorText {
                Section {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                        .listRowBackground(theme.bg)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(theme.bg)
    }

    // MARK: - Default hour/minute from loaded data

    private var defaultHour: Int {
        dayTimes.values.first?.hour ?? Calendar.current.component(.hour, from: Date())
    }

    private var defaultMinute: Int {
        dayTimes.values.first?.minute ?? 0
    }

    // MARK: - Data loading

    @MainActor
    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let fetchSeries = SeriesRepository.series(id: seriesID)
            async let fetchDays   = SeriesRepository.seriesDays(seriesID: seriesID)

            let ownerID = appState.currentProfile?.id
            let fetchedRoutines: [Routine]
            if let ownerID {
                fetchedRoutines = (try? await RoutineRepository.fetchAll(ownerID: ownerID)) ?? []
            } else {
                fetchedRoutines = []
            }
            routines = fetchedRoutines

            // Phase O Task 2: bulk-fetch per-routine exercise counts —
            // mirrors ScheduleSessionView.loadData()'s own precedent
            // (ScheduleSessionView.swift:609-613) exactly, reusing the same
            // bulk `RoutineRepository.exercisesForRoutines(ids:)` idiom
            // (avoids an N+1 fetch fan-out) instead of adding a bespoke
            // per-routine fetch. Threaded into `save()`'s EventKit sync so
            // series-edit calendar events get a routine-specific duration
            // estimate instead of always falling back to `EventKitBridge.
            // estimatedDuration(exerciseCount:)`'s documented 60-min no-
            // count default (the fix-wave-1 "exerciseCount: nil" gap the
            // Phase H gate review ledgered for this exact follow-up).
            let exercises = (try? await RoutineRepository.exercisesForRoutines(
                ids: fetchedRoutines.map(\.id))) ?? []
            routineExerciseCounts = Dictionary(
                grouping: exercises, by: \.routineID
            ).mapValues(\.count)

            let (fetchedSeries, fetchedDays) = try await (fetchSeries, fetchDays)
            series = fetchedSeries

            if let s = fetchedSeries {
                untilDate = s.untilDate
            }

            // Convert SeriesDay rows → selection state
            var weekdays = Set<Int>()
            var times = [Int: DayTime]()
            var routineMap = [Int: UUID?]()
            for day in fetchedDays {
                weekdays.insert(day.weekday)
                times[day.weekday] = Self.parseDayTime(day.timeLocal)
                routineMap[day.weekday] = day.routineID
            }
            selectedWeekdays = weekdays
            dayTimes = times
            dayRoutines = routineMap
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Save

    @MainActor
    private func save() async {
        isSaving = true
        defer { isSaving = false }
        errorText = nil

        let days: [SeriesDayInput] = selectedWeekdays.sorted().map { wd in
            let dt = dayTimes[wd] ?? DayTime(hour: defaultHour, minute: defaultMinute)
            let routineID: UUID? = dayRoutines[wd] ?? nil
            return SeriesDayInput(
                weekday: wd,
                hour: dt.hour,
                minute: dt.minute,
                routineID: routineID
            )
        }
        guard !days.isEmpty else {
            errorText = "Select at least one day."
            return
        }

        do {
            // EventKit sync (Phase H Task 2): snapshot the future scheduled
            // occurrences' ids BEFORE `editSeriesForward` deletes and
            // re-materializes them with fresh UUIDs — same pre-delete-
            // snapshot reasoning as `LobbyView.cancelSeriesForward()`
            // (LobbyView.swift:1161-1170), since `SeriesRepository.
            // editSeriesForward` (SessionSeries.swift:384-471) doesn't hand
            // back which session rows it removed. Filter matches exactly
            // what `editSeriesForward` itself deletes server-side
            // (SessionSeries.swift:436-443: `state == "scheduled" AND
            // scheduled_for > now`).
            let now = Date()
            let oldOccurrenceIDs = ((try? await SeriesRepository.occurrences(seriesID: seriesID)) ?? [])
                .filter { $0.state == "scheduled" && ($0.scheduledFor ?? .distantPast) > now }
                .map(\.id)

            try await SeriesRepository.editSeriesForward(
                seriesID: seriesID,
                days: days,
                untilDate: untilDate
            )

            onSaved()
            dismiss()

            // EventKit sync (Phase H Task 2; moved AFTER dismiss + real
            // exerciseCount threaded through in Phase O Task 2): best-
            // effort, server op already succeeded above — `onSaved()`/
            // `dismiss()` no longer wait on this. Old events are stale
            // (their session rows are gone) — remove first. Removal is
            // ungated on the toggle, same "cleanup always runs regardless
            // of the toggle's CURRENT state" reasoning as `LobbyView.
            // cancelSeriesForward()` (LobbyView.swift:1174-1180 area).
            // Then re-fetch and sync the freshly re-materialized
            // occurrences, gated on `CalendarSyncPrefsStore.isEnabled()`
            // exactly like `ScheduleSessionView.
            // syncScheduledSessionsToCalendar` — filtered the same way as
            // the pre-delete snapshot above so completed/past series
            // occurrences (untouched by this edit) aren't touched either.
            // `exerciseCount` now looks up `routineExerciseCounts`
            // (`loadData()` above) instead of always passing `nil` — kills
            // the 60-min generic-duration fallback for routine-assigned
            // occurrences, matching `ScheduleSessionView`'s own behavior.
            // `routines`/`routineExerciseCounts` are snapshotted into local
            // `let`s before the `Task` so this closure doesn't depend on
            // `self` still being around after the sheet closes.
            let routinesSnapshot = routines
            let exerciseCountsSnapshot = routineExerciseCounts
            Task {
                for oldID in oldOccurrenceIDs {
                    await EventKitBridge.removeEvent(sessionID: oldID)
                }
                if CalendarSyncPrefsStore.isEnabled() {
                    let newOccurrences = ((try? await SeriesRepository.occurrences(seriesID: seriesID)) ?? [])
                        .filter { $0.state == "scheduled" && ($0.scheduledFor ?? .distantPast) > now }
                    for session in newOccurrences {
                        let routine = session.routineID.flatMap { rid in routinesSnapshot.first { $0.id == rid } }
                        let exerciseCount = session.routineID.flatMap { exerciseCountsSnapshot[$0] }
                        await EventKitBridge.syncEvent(session: session, routineName: routine?.name, exerciseCount: exerciseCount)
                    }
                }
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Helpers

    /// Parse "HH:mm:ss" → DayTime. Falls back to (9, 0) on malformed input.
    private static func parseDayTime(_ timeLocal: String) -> DayTime {
        let parts = timeLocal.split(separator: ":").map { Int($0) ?? 0 }
        guard parts.count >= 2 else { return DayTime(hour: 9, minute: 0) }
        return DayTime(hour: parts[0], minute: parts[1])
    }
}
