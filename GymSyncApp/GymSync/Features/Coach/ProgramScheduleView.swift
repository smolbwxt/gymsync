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
// wrote.
//
// The phase strip (2026-08-25 periodization pass) is GOAL-CONDITIONAL,
// not omitted: `BlockPhaseMap` derives accumulation / intensification /
// peak / deload from the block's OWN prescribed percentages for
// performance blocks, and returns nil for volume-driven ones — because
// the field holds that the taxonomy exists to peak a performance on a
// date and does not transfer to hypertrophy. A block with no arc shows
// its mesocycle structure instead, which IS universal.
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
    /// nil when this block carries no phase taxonomy — a hypertrophy /
    /// volume-driven block, where the periodization evidence says an
    /// accumulation-peak arc asserts something untrue. Those blocks show
    /// their mesocycle structure instead. See BlockPhase.
    @State private var phases: [BlockPhase]?
    /// What Coach said when it built this block. Read from the profile,
    /// because the wizard screen that used to show it no longer exists -
    /// building now commits and lands here (owner 2026-08-26).
    @State private var lastBuild: TrainingProfile.BuiltBlock?
    /// The provenance drawer. Closed by default on purpose - owner
    /// 2026-08-27: the options that led to the build "isn't necessarily
    /// something that a user is going to want to look at every single
    /// time". They want where-am-I and what's-coming first; the why is
    /// one tap away.
    @State private var showProvenance = false
    /// What has MOVED since the block started: rules that went live,
    /// volume targets the titration adjusted.
    @State private var changes: [String] = []
    /// The weeks scheduler at the top of the page (owner 2026-08-27:
    /// "the top widget becomes the training calendar... weeks are
    /// extruded buttons... schedule your weeks here").
    @State private var weekSchedules: [Int: BlockWeekSchedule] = [:]
    @State private var completedDays: Set<Date> = []
    @State private var scheduledDays: Set<Date> = []
    @State private var sheetWeek: WeekRef?
    /// Bumped after this page books a week so the embedded calendar
    /// re-reads its dots.
    @State private var calendarRefresh = 0

    private struct WeekRef: Identifiable { let id: Int }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                // FOUR states, not two, and the split is keyed on the
                // ENROLLMENT rather than on `weeks`.
                //
                // The old guard read `weeks.isEmpty && !loading`, which
                // sent every other case to arcCard — including the one
                // that is true on entry, when loading is still true and
                // weeks is still empty. arcCard then drew "WK 1 OF 0"
                // over "0 WEEKS, ONE ARC": real-looking numbers for a
                // block it had not read yet. That was survivable while
                // the only way in was a deliberate tap. It is not
                // survivable now that finishing a build lands here
                // directly, because it is the first thing the athlete
                // sees of the week they just commissioned.
                //
                // `weeks` is derived (`active.template?.weeks`), so it
                // cannot distinguish "no block" from "block whose
                // template did not resolve". `enrollment` can.
                if loading {
                    loadingCard
                } else if enrollment != nil && !weeks.isEmpty {
                    // The block in time, first (owner 2026-08-27). The
                    // same view as the old ON THE CALENDAR page, embedded
                    // - one grid implementation, not a copy.
                    BlockCalendarView(enrollment: enrollment, weeks: weeks,
                                      embedded: true,
                                      highlightedWeek: selectedWeek,
                                      refreshToken: calendarRefresh,
                                      onScheduleChanged: { await reloadSchedule() })
                    arcCard
                    routinesCard
                    reasoningCard
                    if !changes.isEmpty {
                        changesCard
                    }
                    provenanceCard
                    askDoor
                } else if !routines.isEmpty {
                    // (reasoningCard renders inside this branch too, below
                    // the rows, so an un-enrolled block still explains
                    // itself.)
                    // The days exist, the arc does not. Real, and not
                    // rare: enrollGenerated returns early when a block has
                    // no main lifts, and both the template row and the
                    // enrollment are best-effort `try?`. Showing the
                    // routines the athlete actually has beats an empty
                    // screen that says they have nothing.
                    unenrolledCard
                    routinesCard
                    reasoningCard
                    askDoor
                } else {
                    emptyCard
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .sheet(item: $sheetWeek) { ref in
            WeekScheduleSheet(weekNumber: ref.id,
                              window: weekWindow(ref.id),
                              enrollmentID: enrollment?.id,
                              existing: weekSchedules[ref.id],
                              completed: completedDays,
                              scheduled: scheduledDays,
                              totalWeeks: weeks.count,
                              startedOn: enrollment?.startedOn,
                              onChanged: { await reloadSchedule() })
                .presentationDetents([.height(500)])
        }
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

    // MARK: The weeks (schedule them here)

    /// The top widget: every week of the block as an extruded button that
    /// opens the day/time sheet. Where-am-I is one line; the why lives in
    /// the provenance drawer below. Booking is REAL - the sheet writes
    /// sessions, not just intent (WeekBooker).
    private var arcCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("SCHEDULE YOUR WEEKS HERE")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("WK \(currentWeek) OF \(weeks.count)")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
            }
            // The selected week, in one line: its phase (read from the
            // block's own percentages, or the mesocycle label when the
            // block has no arc) and its prescription.
            if weeks.indices.contains(selectedWeek - 1) {
                let week = weeks[selectedWeek - 1]
                Text(weekLine(selectedWeek, week: week))
                    .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                    .tracking(0.6)
                    .foregroundStyle(week.isDeload ? theme.accent : theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            weekButtons
            Text("Tap a week to pick the days and time. Coach books the sessions and puts them on your calendar.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    private func weekLine(_ number: Int, week: ProgramWeek) -> String {
        var parts = ["WEEK \(number)"]
        if let phases, phases.indices.contains(number - 1) {
            parts.append(phases[number - 1].rawValue)
        } else if let label = BlockPhaseMap.mesocycleLabel(for: weeks, week: number) {
            parts.append(label)
        }
        parts.append(ProgramMath.prescriptionText(week: week, baseline: leadBaseline,
                                                  unit: ThemeStore.shared.weightUnit))
        if let range = weekDateRange(number) { parts.append(range) }
        return parts.joined(separator: " \u{00B7} ")
    }

    private var weekButtons: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4),
                  spacing: 6) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { index, week in
                let number = index + 1
                Button {
                    selectedWeek = number
                    sheetWeek = WeekRef(id: number)
                } label: {
                    VStack(spacing: 3) {
                        Text("WK \(number)")
                            .font(GSFont.bold(12, relativeTo: .caption))
                            .tracking(0.6)
                            .foregroundStyle(weekInk(number))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(weekDaysLine(number, isDeload: week.isDeload))
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(weekInk(number).opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.gs3D(face: weekFace(number, isDeload: week.isDeload),
                                   lip: theme.raised3DLip,
                                   cornerRadius: 10, lipHeight: 4))
                .accessibilityLabel("Week \(number)\(week.isDeload ? ", deload" : ""), \(weekDaysLine(number, isDeload: week.isDeload))")
            }
        }
    }

    /// "M W F" once the week is set, "DELOAD" / "SET DAYS" before.
    private func weekDaysLine(_ number: Int, isDeload: Bool) -> String {
        if let schedule = weekSchedules[number], !schedule.weekdays.isEmpty {
            let letters = ["", "S", "M", "T", "W", "T", "F", "S"]
            let order = [2, 3, 4, 5, 6, 7, 1]
            return order.filter { schedule.weekdays.contains($0) }
                .map { letters[$0] }.joined(separator: " ")
        }
        return isDeload ? "DELOAD" : "SET DAYS"
    }

    private func weekFace(_ number: Int, isDeload: Bool) -> Color {
        if number == currentWeek { return theme.accent }
        if number < currentWeek { return theme.text.opacity(0.85) }
        if isDeload { return theme.raised3DFace.opacity(0.55) }
        return theme.raised3DFace
    }

    private func weekInk(_ number: Int) -> Color {
        number <= currentWeek ? theme.bg : theme.neutral700
    }

    private func weekWindow(_ number: Int) -> (start: Date, end: Date) {
        guard let enrollment else { return (Date(), Date()) }
        return ProgramMath.weekWindow(startedOn: enrollment.startedOn, week: number)
    }

    /// The per-week overrides and the real sessions on the calendar.
    private func reloadSchedule() async {
        guard let enrollment else { return }
        weekSchedules = await BlockWeekScheduleRepository.forEnrollment(enrollment.id)
        let calendar = Calendar.current
        if let userID = appState.currentProfile?.id,
           let history = try? await SessionRepository.history(userID: userID, limit: 120) {
            completedDays = Set(history.compactMap { $0.completedAt }
                .map { calendar.startOfDay(for: $0) })
        }
        if let upcoming = try? await SessionRepository.upcoming() {
            scheduledDays = Set(upcoming.compactMap { $0.scheduledFor }
                .map { calendar.startOfDay(for: $0) })
        }
        calendarRefresh += 1
    }

    // MARK: Day rows (housed: owner 2026-08-27, "within a widget border
    // with a title, something like: Your Routine, built for you")

    private var routinesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("YOUR ROUTINE")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("BUILT FOR YOU")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
            }
            Text("\(routines.count) day\(routines.count == 1 ? "" : "s") a week, in the order Coach wrote them. Tap a day for the lifts and why they're there.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
            VStack(spacing: 0) {
                ForEach(Array(routines.enumerated()), id: \.element.id) { index, routine in
                    dayRow(routine)
                    if index < routines.count - 1 {
                        Divider().overlay(theme.neutral500.opacity(0.25))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

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
                    // Was lineLimit(1): the exercise roll-call clipped at
                    // the screen edge on default type (owner report,
                    // 2026-08-27 UI wave). Two lines and it breathes.
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(displayName(routine)). \(leadLine(routine))")
    }

    private var askDoor: some View {
        // The program-specific payload (owner 2026-08-27: "clicking on a
        // coach chat from the programming page on a specific program
        // should load up a payload that is program specific with the
        // goal, intent of the program, along with all of the information
        // that led to it"). Built by the SAME engine the ledger's
        // after-action uses, so a mid-block chat and a post-block AAR
        // can never tell two different stories.
        BlockThreadDoor(enrollment: enrollment, selectedWeek: selectedWeek)
    }

    /// Says one true thing and no numbers. The rule this screen runs on
    /// is that every number is READ, never invented — a placeholder arc
    /// would break it in the one moment the athlete is least equipped to
    /// notice.
    private var loadingCard: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(theme.accent)
            Text("READING YOUR BLOCK")
                .font(GSFont.bold(13, relativeTo: .headline))
                .tracking(0.9)
                .foregroundStyle(theme.neutral700)
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// Days on the bar, no arc over them.
    private var unenrolledCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR DAYS, NO ARC YET")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("These routines are yours to train today. They are not carrying a week-over-week progression — forge a block from My Program and the weeks land here.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// WHY the block looks like this, plus anything Coach was told and
    /// could not build.
    ///
    /// Two visually distinct groups, and the distinction is load-bearing.
    /// The notes describe decisions Coach MADE. The un-honoured rules are
    /// things the athlete ASKED FOR that did not happen - previously
    /// appended into the same grey list as the notes, where a dropped
    /// request was indistinguishable from a fulfilled one. That was the
    /// silent-ignore the owner reported on 2026-08-26.
    @ViewBuilder
    private var reasoningCard: some View {
        if let lastBuild, !(lastBuild.notes.isEmpty && lastBuild.unhonoredRules.isEmpty) {
            VStack(alignment: .leading, spacing: 10) {
                if !lastBuild.unhonoredRules.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("YOU ASKED, I COULDN'T BUILD IT")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.accent)
                        ForEach(lastBuild.unhonoredRules, id: \.self) { rule in
                            Text("“\(rule)”")
                                .font(GSFont.body(12.5, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Text("I kept these, and Coach can talk them through with you — but this block does not act on them yet.")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(theme.accent, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if !lastBuild.notes.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("WHY THIS BLOCK")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral500)
                        ForEach(lastBuild.notes, id: \.self) { note in
                            Text(note)
                                .font(GSFont.body(12.5, relativeTo: .caption))
                                .foregroundStyle(theme.neutral700)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: GSMetrics.radiusSm)
        }
    }

    /// "HOW THIS WAS BUILT" - the five doors' frozen state, behind a
    /// disclosure. Blocks that predate the snapshot say so instead of
    /// inventing a past.
    private var provenanceCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    showProvenance.toggle()
                }
            } label: {
                HStack(spacing: 10) {
                    Text("HOW THIS WAS BUILT")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .tracking(0.8)
                        .foregroundStyle(theme.text)
                    Spacer()
                    Image(systemName: showProvenance ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showProvenance {
                if let config = enrollment?.config, !config.isEmpty {
                    ForEach(config.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                        HStack(alignment: .top, spacing: 8) {
                            Text(key.uppercased())
                                .font(GSFont.bold(10, relativeTo: .caption2))
                                .tracking(0.8)
                                .foregroundStyle(theme.neutral500)
                                .frame(width: 118, alignment: .leading)
                            Text(value)
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.text)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } else {
                    Text("This block was built before Coach started keeping the build options. Every block from now on carries them.")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// What has moved since the start - the block is not a stone tablet,
    /// and the athlete should see its history without asking.
    private var changesCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SINCE THE START")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.accent)
            ForEach(changes, id: \.self) { line in
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
            phases = BlockPhaseMap.phases(for: template.weeks)
        }
        await reloadSchedule()
        // `try?` does not add a nesting level here: load() already returns
        // an Optional, and Swift 5 flattens. Same shape as the call in
        // CoachHomeView.task.
        lastBuild = (try? await TrainingProfileRepository.load())?.lastBuild
        await loadChanges()
        catalog = (try? await ExerciseRepository.fetchAll()) ?? []
        guard let ownerID = appState.currentProfile?.id,
              let all = try? await RoutineRepository.fetchAll(ownerID: ownerID) else { return }
        routines = all.filter { $0.name.hasPrefix("Coach · ") && $0.prescribedBy == nil }
        let rows = (try? await RoutineRepository.exercisesForRoutines(ids: routines.map(\.id))) ?? []
        exercisesByRoutine = Dictionary(grouping: rows, by: \.routineID)
    }

    /// The block's movement history: rules that went live during it and
    /// volume the titration moved. Compact lines, computed - never prose
    /// the model wrote.
    private func loadChanges() async {
        guard let started = enrollment?.startedOn else { return }
        var lines: [String] = []
        for rule in (try? await TrainingRulesRepository.active()) ?? [] {
            if let applied = rule.appliedAt, applied >= started {
                lines.append("Your rule went in: \u{201c}\(rule.rule)\u{201d}")
            }
        }
        for target in (try? await VolumeTargetRepository.all()) ?? [] {
            if let reason = target.reason, !reason.isEmpty {
                lines.append("\(target.muscle.capitalized) \u{2192} \(target.weeklySets) sets/week \u{2014} \(reason)")
            }
        }
        changes = Array(lines.prefix(6))
    }
}

/// The ask-door with the block's computed payload attached. A separate
/// tiny view because the payload is async - it assembles on tap, with a
/// spinner in the row, and the thread opens already knowing the block.
private struct BlockThreadDoor: View {
    let enrollment: ProgramEnrollment?
    let selectedWeek: Int

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme
    private struct OpenerPayload: Identifiable, Hashable {
        let id = UUID()
        let text: String
    }

    @State private var opener: OpenerPayload?
    @State private var building = false

    var body: some View {
        Button {
            guard !building else { return }
            building = true
            Task {
                defer { building = false }
                if let enrollment, let userID = appState.currentProfile?.id {
                    opener = OpenerPayload(text: await BlockAAR.payload(
                        enrollment: enrollment, userID: userID))
                } else {
                    opener = OpenerPayload(text: "I'm looking at week \(selectedWeek) of my block. Ask me what you want changed and I'll propose it.")
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "text.bubble.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(theme.bg)
                Text("ASK COACH FOR A CHANGE")
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .tracking(0.5)
                    .foregroundStyle(theme.bg)
                Spacer()
                if building {
                    ProgressView().tint(theme.bg)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.bg.opacity(0.8))
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        // The one accent-faced door on the page (owner 2026-08-27):
        // scheduling and viewing are the page; talking to Coach is the
        // action.
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm, face: theme.accent))
        .navigationDestination(item: $opener) { payload in
            CoachThreadLauncher(title: "Block \u{2014} week \(selectedWeek)",
                                opener: payload.text)
                .background(theme.bg)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
        }
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
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 10) {
                        Text(name(for: row).uppercased())
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                        Spacer()
                        Text(scheme(for: row))
                            .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                            .foregroundStyle(theme.neutral700)
                            // The prescription is the one number the
                            // athlete came for - a long exercise name
                            // must never squeeze "3 x 8-12" out of the
                            // row (UI wave 2026-08-27).
                            .fixedSize()
                            .layoutPriority(1)
                    }
                    // The structure, if this lift has one. Accent-coloured
                    // because a superset or a drop set changes HOW the set
                    // is run, not just how many - it should not read as
                    // more grey metadata.
                    if let badge = structureBadge(for: row) {
                        Text(badge)
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(theme.accent)
                    }
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
        RoutineThreadDoor(
            title: displayName,
            opener: "I'm looking at \(displayName) in week \(weekNumber): \(exercises.count) exercises, leading with \(exercises.first.map { name(for: $0) } ?? "the main lift"). Ask me anything about how it's built, or tell me what to change.",
            context: { await routineContext() }) {
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

    /// What Coach needs to answer "why is X in here" and "why isn't Y":
    /// the prescription as written, the rationale the page shows, the
    /// build's own notes, and the constraints that shaped it. Field
    /// 2026-08-27: asked "why aren't there any hamstring movements", a
    /// thread opened with only "2 exercises, leading with Nordic
    /// Hamstring Curl" had nothing to answer from and reached for the
    /// trend tool instead.
    private func routineContext() async -> String {
        var lines: [String] = []
        lines.append("ROUTINE: \(displayName), week \(weekNumber) of the block.")
        lines.append("PRESCRIPTION, in order:")
        var muscles: [String] = []
        for row in exercises {
            let ex = catalog.first { $0.id == row.exerciseID }
            let muscle = ex?.primaryMuscle ?? "?"
            let pattern = ex?.movementPattern ?? "?"
            if !muscles.contains(muscle) { muscles.append(muscle) }
            lines.append("- \(name(for: row)) - \(scheme(for: row)) (\(muscle), \(pattern))")
        }
        lines.append("MUSCLES WITH DIRECT WORK IN THIS ROUTINE: \(muscles.joined(separator: ", ")). A muscle not listed has no direct work on this day; another day of the block may carry it.")
        let rationale = rationaleLines
        if !rationale.isEmpty {
            lines.append("WHY THIS ROUTINE IS BUILT THIS WAY (the page shows the athlete these lines):")
            lines.append(contentsOf: rationale.map { "- " + $0 })
        }
        if let profile = try? await TrainingProfileRepository.load() {
            if let build = profile.lastBuild, !build.notes.isEmpty {
                lines.append("COACH'S NOTES FROM THE BUILD (why the block looks like it does):")
                lines.append(contentsOf: build.notes.map { "- " + $0 })
            }
            if let build = profile.lastBuild, !build.unhonoredRules.isEmpty {
                lines.append("RULES THE ATHLETE GAVE THAT THE BUILD COULD NOT HONOR: " + build.unhonoredRules.joined(separator: "; "))
            }
            var constraints: [String] = []
            constraints.append("\(profile.daysPerWeek) days a week")
            if let minutes = profile.sessionMinutes { constraints.append("sessions capped at \(minutes) min (the cap trims accessories, last first)") }
            if !profile.injuredJoints.isEmpty { constraints.append("INJURED, every lift that loads it is out: " + profile.injuredJoints.joined(separator: ", ")) }
            if !profile.cautionJoints.isEmpty { constraints.append("working around (lifts that load it sort last): " + profile.cautionJoints.joined(separator: ", ")) }
            if !profile.excludedPatterns.isEmpty { constraints.append("won't do these patterns: " + profile.excludedPatterns.joined(separator: ", ")) }
            if let cap = profile.derivedComplexityCap { constraints.append("movement complexity capped at level \(cap) of 5") }
            lines.append("THE ATHLETE'S CONSTRAINTS THAT SHAPED THE BLOCK: " + constraints.joined(separator: "; "))
        }
        lines.append("When asked why a lift or muscle is missing, answer from the notes and constraints above - name the cap, the exclusion, the injury or the day that carries it. Never guess, and never answer with only a promise to look.")
        return lines.joined(separator: "\n")
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

    /// The set STRUCTURE, said out loud.
    ///
    /// Owner 2026-08-26: "I am not able to see that they are prescribed
    /// from the routine report." Supersets were prescribed and rendered
    /// nowhere on the way in - the only signal was one prose paragraph
    /// about the day as a whole, which cannot tell you WHICH two lifts
    /// are paired. Drop sets could not be prescribed at all until this
    /// same change, so there was nothing to show.
    ///
    /// Same vocabulary as RoutinesListView so the three surfaces agree.
    private func structureBadge(for row: RoutineExercise) -> String? {
        var parts: [String] = []
        if let group = row.supersetGroup { parts.append("SS\(group)") }
        switch row.setType {
        case "drop":
            if let steps = row.dropSteps, let pct = row.dropPercent {
                parts.append("DROP ×\(steps) −\(NSDecimalNumber(decimal: pct).intValue)%")
            } else {
                parts.append("DROP")
            }
        case "burnout": parts.append("BURNOUT")
        default: break
        }
        if row.targetFailure { parts.append("TO FAILURE") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - RoutineThreadDoor
//
// The routine page's ask-door. Like BlockThreadDoor: the context is
// computed on tap (it reads the profile), a spinner sits in the row, and
// the thread opens already knowing the routine.
private struct RoutineThreadDoor<Label: View>: View {
    let title: String
    let opener: String
    let context: () async -> String
    @ViewBuilder let label: () -> Label

    @Environment(\.gsTheme) private var theme
    private struct Payload: Identifiable, Hashable {
        let id = UUID()
        let text: String
    }
    @State private var payload: Payload?
    @State private var building = false

    var body: some View {
        Button {
            guard !building else { return }
            building = true
            Task {
                defer { building = false }
                payload = Payload(text: await context())
            }
        } label: {
            label()
        }
        .buttonStyle(.gs3D(face: theme.accent, lip: theme.raised3DLip,
                           cornerRadius: GSMetrics.radiusSm, lipHeight: 4))
        .navigationDestination(item: $payload) { payload in
            CoachThreadLauncher(title: title, opener: opener, context: payload.text)
                .background(theme.bg)
                .navigationTitle("Coach")
                .navigationBarTitleDisplayMode(.inline)
        }
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
    /// Instructions-only context (see CoachThreadView.seededContext).
    var context: String? = nil

    @Environment(\.gsTheme) private var theme
    @State private var thread: CoachChatThread?
    @State private var failed = false

    var body: some View {
        Group {
            if let thread {
                CoachThreadView(thread: thread, seededOpener: opener,
                                seededContext: context)
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
