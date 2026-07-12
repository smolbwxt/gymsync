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

    private let weekdays: [(label: String, value: Int)] = [
        ("S", 1), ("M", 2), ("T", 3), ("W", 4), ("T", 5), ("F", 6), ("S", 7)
    ]

    var body: some View {
        chipRow
        perDayRows
    }

    // MARK: - Chip row

    @ViewBuilder
    private var chipRow: some View {
        HStack(spacing: 6) {
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
                        .font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(
                            selected
                                ? Color.accentColor
                                : Color(.systemGray5),
                            in: Circle()
                        )
                        .foregroundStyle(selected ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    // MARK: - Per-day rows

    @ViewBuilder
    private var perDayRows: some View {
        let sorted = selectedWeekdays.sorted()
        ForEach(sorted, id: \.self) { wd in
            perDayRow(weekday: wd)
        }
    }

    @ViewBuilder
    private func perDayRow(weekday: Int) -> some View {
        let fullNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        let name = fullNames[(weekday - 1) % 7]

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

        VStack(alignment: .leading, spacing: 4) {
            Text(name)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            DatePicker("Time", selection: timeBinding, displayedComponents: .hourAndMinute)
                .labelsHidden()
            Picker("Routine", selection: routineBinding) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(routines, id: \.id) { routine in
                    Text(routine.name).tag(Optional(routine.id))
                }
            }
            .pickerStyle(.menu)
        }
        .padding(.vertical, 4)
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

    @State private var series: SessionSeries?
    @State private var selectedWeekdays: Set<Int> = []
    @State private var dayTimes: [Int: DayTime] = [:]
    @State private var dayRoutines: [Int: UUID?] = [:]
    @State private var untilDate: Date = Date().addingTimeInterval(8 * 7 * 86400)
    @State private var routines: [Routine] = []

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
                    ProgressView("Loading series…")
                } else {
                    editorForm
                }
            }
            .navigationTitle("Edit Series")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
            .task { await loadData() }
        }
    }

    // MARK: - Form

    private var editorForm: some View {
        Form {
            weekdaySection
            untilDateSection
            captionSection
            if let errorText {
                Section {
                    Text(errorText).foregroundStyle(.red).font(.footnote)
                }
            }
        }
    }

    private var weekdaySection: some View {
        Section("Repeat on") {
            WeekdayRuleEditor(
                selectedWeekdays: $selectedWeekdays,
                dayTimes: $dayTimes,
                dayRoutines: $dayRoutines,
                defaultHour: defaultHour,
                defaultMinute: defaultMinute,
                defaultRoutineID: nil,
                routines: routines
            )
        }
    }

    private var untilDateSection: some View {
        let minDate = Date().addingTimeInterval(86400)
        let maxDate = Date().addingTimeInterval(26 * 7 * 86400)
        return Section("Until") {
            DatePicker(
                "End date",
                selection: $untilDate,
                in: minDate...maxDate,
                displayedComponents: .date
            )
        }
    }

    private var captionSection: some View {
        Section {
            Text("Changes apply to future sessions only.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
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
            try await SeriesRepository.editSeriesForward(
                seriesID: seriesID,
                days: days,
                untilDate: untilDate
            )
            onSaved()
            dismiss()
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
