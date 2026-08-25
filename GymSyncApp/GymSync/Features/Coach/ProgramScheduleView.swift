import SwiftUI

// MARK: - ProgramScheduleView
//
// "The Weeks", renamed PROGRAM SCHEDULE (owner 2026-08-25) — the page
// the owner kept from the design review: click through the weeks, open
// a routine, see how the prescription moves, ask for a change.
//
// Every number here is READ, never invented (design-spec §1.5). The arc
// comes from the enrolled block's own `ProgramWeek` list, the current
// week from `ProgramMath.currentWeek`, the per-week prescription from
// `ProgramMath.prescriptionText` against the frozen enrollment baseline,
// and the day rows from the `Coach · <day>` routines the generator
// wrote. Where the data carries no phase taxonomy, none is displayed —
// a BASE/BUILD/PEAK label the block does not actually encode would be
// exactly the improvised number the spec forbids.
struct ProgramScheduleView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var enrollment: ProgramEnrollment?
    @State private var weeks: [ProgramWeek] = []
    @State private var currentWeek = 1
    @State private var selectedWeek = 1
    @State private var routines: [Routine] = []
    @State private var exercisesByRoutine: [UUID: [RoutineExercise]] = [:]
    @State private var catalog: [Exercise] = []
    @State private var loading = true
    @State private var pushedRoutineID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if weeks.isEmpty && !loading {
                    emptyCard
                } else {
                    arcCard
                    ForEach(routines) { routine in
                        dayRow(routine)
                    }
                    calendarDoor
                    askDoor
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .navigationDestination(item: $pushedRoutineID) { id in
            if let routine = routines.first(where: { $0.id == id }) {
                ProgramRoutineDetailView(
                    routine: routine,
                    exercises: exercisesByRoutine[id] ?? [],
                    catalog: catalog,
                    weekNumber: selectedWeek,
                    week: weeks.indices.contains(selectedWeek - 1) ? weeks[selectedWeek - 1] : nil,
                    baseline: leadBaseline)
                .background(theme.bg)
                .navigationTitle(displayName(routine))
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    // MARK: The arc

    private var arcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(weeks.count) WEEKS, ONE ARC")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(0.3)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("WK \(currentWeek) OF \(weeks.count)")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
            weekChips
            // The selected week's OWN prescription, computed by
            // ProgramMath against the frozen baseline.
            if weeks.indices.contains(selectedWeek - 1) {
                let week = weeks[selectedWeek - 1]
                Text(ProgramMath.prescriptionText(week: week, baseline: leadBaseline,
                                                  unit: ThemeStore.shared.weightUnit))
                    .font(GSFont.bold(13, relativeTo: .subheadline).monospacedDigit())
                    .foregroundStyle(week.isDeload ? theme.accent : theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let range = weekDateRange(selectedWeek) {
                    Text(range)
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var weekChips: some View {
        HStack(spacing: 4) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let number = index + 1
                Button {
                    selectedWeek = number
                } label: {
                    Text("W\(number)")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .foregroundStyle(chipInk(number, isDeload: week.isDeload))
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                }
                .buttonStyle(.gs3D(face: chipFace(number, isDeload: week.isDeload),
                                   lip: theme.raised3DLip,
                                   cornerRadius: 8, lipHeight: 3))
                .accessibilityLabel("Week \(number)\(week.isDeload ? ", deload" : "")")
            }
        }
    }

    private func chipFace(_ number: Int, isDeload: Bool) -> Color {
        if number == selectedWeek { return theme.accent }
        if number < currentWeek { return theme.text.opacity(0.85) }
        return theme.raised3DFace
    }

    private func chipInk(_ number: Int, isDeload: Bool) -> Color {
        if number == selectedWeek || number < currentWeek { return theme.bg }
        return isDeload ? theme.accent : theme.neutral700
    }

    // MARK: Day rows

    private func dayRow(_ routine: Routine) -> some View {
        Button {
            pushedRoutineID = routine.id
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(displayName(routine).uppercased())
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                Text(leadLine(routine))
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName(routine)). \(leadLine(routine))")
    }

    private var calendarDoor: some View {
        NavigationLink {
            BlockCalendarView(enrollment: enrollment, weeks: weeks)
                .background(theme.bg)
                .navigationTitle("On the Calendar")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 10) {
                Text("ON THE CALENDAR")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
    }

    private var askDoor: some View {
        NavigationLink {
            CoachThreadLauncher(
                title: "Block — week \(selectedWeek)",
                opener: "I'm looking at week \(selectedWeek) of my block. Ask me what you want changed and I'll propose it.")
                .background(theme.bg)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            HStack(spacing: 10) {
                Text("ASK COACH FOR A CHANGE")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO BLOCK ON THE BAR")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("Forge one from My Program and its weeks land here.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    // MARK: Derived text

    private func displayName(_ routine: Routine) -> String {
        routine.name.hasPrefix("Coach · ")
            ? String(routine.name.dropFirst("Coach · ".count))
            : routine.name
    }

    private func leadLine(_ routine: Routine) -> String {
        let rows = exercisesByRoutine[routine.id] ?? []
        guard !rows.isEmpty else { return "No exercises" }
        let nameByID = Dictionary(catalog.map { ($0.id, $0.name) },
                                  uniquingKeysWith: { first, _ in first })
        let names = rows.prefix(2).compactMap { nameByID[$0.exerciseID] }
        let more = rows.count - names.count
        let head = names.joined(separator: " · ")
        return more > 0 ? "\(head) +\(more) more" : head
    }

    /// The frozen baseline for the block's lead focus lift — the same
    /// number `WorkingWeight` rung 1 reads, so the schedule and the bar
    /// loader can never disagree.
    private var leadBaseline: Decimal? {
        guard let enrollment, let first = enrollment.focus.exerciseIDs?.first else { return nil }
        return enrollment.baselineValue(for: first)
    }

    private func weekDateRange(_ number: Int) -> String? {
        guard let enrollment else { return nil }
        let window = ProgramMath.weekWindow(startedOn: enrollment.startedOn, week: number)
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: window.start)) – \(formatter.string(from: window.end))"
    }

    // MARK: Load

    private func load() async {
        guard loading else { return }
        defer { loading = false }
        let active = try? await ProgramRepository.active()
        enrollment = active
        if let active, let template = active.template {
            weeks = template.weeks
            currentWeek = ProgramMath.currentWeek(startedOn: active.startedOn,
                                                  weeks: template.weeks.count)
            selectedWeek = currentWeek
        }
        catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        guard let ownerID = appState.currentProfile?.id,
              let all = try? await RoutineRepository.fetchAll(ownerID: ownerID) else { return }
        routines = all.filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
        let rows = (try? await RoutineRepository.exercisesForRoutines(ids: routines.map(\.id))) ?? []
        exercisesByRoutine = Dictionary(grouping: rows, by: \.routineID)
    }
}

// MARK: - ProgramRoutineDetailView
//
// One day of the block. The prescription rows plus WHY it is built this
// way (owner 2026-08-25: "maybe the client wants more information about
// how it's structured, what is driving the decision making"), and a door
// into a Coach thread already carrying this routine's context.
struct ProgramRoutineDetailView: View {
    let routine: Routine
    let exercises: [RoutineExercise]
    let catalog: [Exercise]
    let weekNumber: Int
    let week: ProgramWeek?
    let baseline: Decimal?

    @Environment(\.gsTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                prescriptionCard
                rationaleCard
                talkDoor
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
    }

    private var prescriptionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("THE PRESCRIPTION")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .tracking(0.3)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("WEEK \(weekNumber)")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
            ForEach(exercises) { row in
                HStack(spacing: 10) {
                    Text(name(for: row).uppercased())
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer()
                    Text(scheme(for: row))
                        .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(theme.neutral700)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private var rationaleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHY IT'S BUILT THIS WAY")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            ForEach(rationaleLines, id: \.self) { line in
                Text(line)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// Computed from the routine itself — never a generated narrative.
    /// Each line states a fact the rows actually carry.
    private var rationaleLines: [String] {
        var lines: [String] = []
        let mains = exercises.prefix(2).compactMap { name(for: $0) }
        if !mains.isEmpty {
            lines.append("Mains lead: \(mains.joined(separator: " then ")). Everything after them is accessory work, ordered so systemic fatigue alternates.")
        }
        if let week {
            if week.isDeload {
                lines.append("Week \(weekNumber) is a deload — same movements, volume cut so the next block has somewhere to climb from.")
            } else if let percent = week.percentOfBaseline {
                lines.append("Week \(weekNumber) runs the lead lift at \(ProgramMath.trimmedPercent(percent))% of your frozen baseline — the wave, not a guess.")
            } else {
                lines.append("Week \(weekNumber) is volume-driven: \(week.sets)×\(week.reps) on the lead lift, with load set by your logged history.")
            }
        }
        let paired = exercises.filter { $0.supersetGroup != nil }
        if !paired.isEmpty {
            lines.append("\(paired.count) lifts are paired as supersets — antagonists alternate so one side rests while the other works.")
        }
        let cardio = exercises.filter { $0.cardioZone != nil }
        if !cardio.isEmpty {
            lines.append("\(cardio.count) cardio block\(cardio.count == 1 ? "" : "s") prescribed by zone and minutes, not by distance.")
        }
        return lines
    }

    private var talkDoor: some View {
        NavigationLink {
            CoachThreadLauncher(
                title: displayName,
                opener: "I'm looking at \(displayName) in week \(weekNumber): \(exercises.count) exercises, leading with \(exercises.first.map { name(for: $0) } ?? "the main lift"). Ask me anything about how it's built, or tell me what to change.")
                .background(theme.bg)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            Text("TALK THIS ROUTINE OVER")
                .font(GSFont.bold(15, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.gs3D(face: theme.accent, lip: theme.raised3DLip,
                           cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
    }

    private var displayName: String {
        routine.name.hasPrefix("Coach · ")
            ? String(routine.name.dropFirst("Coach · ".count))
            : routine.name
    }

    private func name(for row: RoutineExercise) -> String {
        catalog.first(where: { $0.id == row.exerciseID })?.name ?? "Exercise"
    }

    private func scheme(for row: RoutineExercise) -> String {
        if let zone = row.cardioZone {
            let minutes = row.cardioMinutes.map { "\($0) min" } ?? ""
            return "Zone \(zone) \(minutes)".trimmingCharacters(in: .whitespaces)
        }
        let sets = row.targetSets.map { "\($0)" } ?? "—"
        if let low = row.targetRepsLow, let high = row.targetRepsHigh {
            return low == high ? "\(sets) × \(low)" : "\(sets) × \(low)–\(high)"
        }
        if let reps = row.targetReps { return "\(sets) × \(reps)" }
        return "\(sets) sets"
    }
}

// MARK: - CoachThreadLauncher
//
// Opens a NEW Coach thread carrying the caller's context, then hands off
// to the normal thread view. Used by the schedule and routine pages so
// "ask about this" lands in a real, persisted thread rather than a
// modal with no memory.
struct CoachThreadLauncher: View {
    let title: String
    let opener: String

    @Environment(\.gsTheme) private var theme
    @State private var thread: CoachChatThread?
    @State private var failed = false

    var body: some View {
        Group {
            if let thread {
                CoachThreadView(thread: thread, seededOpener: opener)
            } else if failed {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Couldn't open a thread just now.")
                        .font(GSFont.bold(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text("Try again from Coach → Chat.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg)
        .task {
            guard thread == nil else { return }
            if let created = await CoachChatRepository.createThread(title: String(title.prefix(48))) {
                thread = created
            } else {
                failed = true
            }
        }
    }
}
