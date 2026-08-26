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
                    arcCard
                    ForEach(routines) { routine in
                        dayRow(routine)
                    }
                    reasoningCard
                    calendarDoor
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
                    ForEach(routines) { routine in
                        dayRow(routine)
                    }
                    reasoningCard
                    calendarDoor
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
            phaseLine
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

    /// The phase strip when the block has one, the mesocycle readback
    /// when it does not. Never both, never invented.
    @ViewBuilder
    private var phaseLine: some View {
        if let phases, phases.indices.contains(selectedWeek - 1) {
            let phase = phases[selectedWeek - 1]
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(phase.rawValue)
                        .font(GSFont.bold(11, relativeTo: .caption))
                        .tracking(1.2)
                        .foregroundStyle(phase == .deload ? theme.accent : theme.text)
                    Text(phaseSpan(phase))
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                }
                Text(phase.blurb)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else if let label = BlockPhaseMap.mesocycleLabel(for: weeks, week: selectedWeek) {
            Text(label)
                .font(GSFont.bold(11, relativeTo: .caption))
                .tracking(1.2)
                .foregroundStyle(theme.neutral700)
        }
    }

    /// "WK 3-5" — which weeks of this block share the selected phase, so
    /// the label reads as an arc rather than a one-week tag.
    private func phaseSpan(_ phase: BlockPhase) -> String {
        guard let phases else { return "" }
        let indices = phases.enumerated().filter { $0.element == phase }.map { $0.offset + 1 }
        guard let first = indices.first, let last = indices.last else { return "" }
        return first == last ? "WK \(first)" : "WK \(first)-\(last)"
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
        // A deload reads differently from an overload week even before
        // it is selected — it is the one week whose job is less work.
        if isDeload { return theme.raised3DFace.opacity(0.55) }
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
        // `try?` does not add a nesting level here: load() already returns
        // an Optional, and Swift 5 flattens. Same shape as the call in
        // CoachHomeView.task.
        lastBuild = (try? await TrainingProfileRepository.load())?.lastBuild
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
