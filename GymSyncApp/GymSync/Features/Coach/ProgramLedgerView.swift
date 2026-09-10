import SwiftUI

// MARK: - ProgramLedgerView
//
// The MY PROGRAM destination. Owner 2026-08-27: "It should open up into
// a catalogue or ledger of all my previous programming... if it's a
// completed program, then I should be able to open that up and have a
// conversation with coach about the performance, but if it's my current
// program, I should be at the very top set aside from the ledger."
//
// The current block is PINNED and opens the live schedule page (where
// you are, what's coming, the reasoning, the calendar). Every past
// block is a row in the ledger below — completed or abandoned, dated,
// honest — and opens an after-action conversation with Coach carrying
// that block's computed payload. Abandoned blocks are shown, not
// hidden: they are part of the story of what drove the next block.
struct ProgramLedgerView: View {

    /// The block goals behind the rows on screen (goal-first plan, task D5).
    ///
    /// `StubBlockGoalRepository` until Stream A's live one lands (I1) — the
    /// same injection every other surface in this stream takes, so all of
    /// them swap together.
    let goalRepository: any BlockGoalRepository

    /// An override for the batch read, for a caller that has a better one
    /// than the frozen protocol can express.
    ///
    /// **THE REPOSITORY IS THE REAL PATH** (task review finding 3, and the
    /// controller's ruling on it): `load()` reads through `goalRepository`,
    /// so a goal line renders as soon as the injected repository knows about
    /// the block on screen. This closure exists only as the previewless
    /// fallback — nil is the shipping value — and it is what integration task
    /// I1 binds to Stream A's `.in("enrollment_id", …)` batch read, which is
    /// the read the plan describes and the one the frozen protocol cannot
    /// express: `BlockGoalRepository` answers `activeGoal()` and nothing
    /// else, while a ledger row is a block that has already ended. Widening a
    /// protocol three streams fork against is not this stream's call.
    let goalsForEnrollments: (@Sendable ([UUID]) async -> [UUID: BlockGoal])?

    init(goalRepository: any BlockGoalRepository = StubBlockGoalRepository(),
         goalsForEnrollments: (@Sendable ([UUID]) async -> [UUID: BlockGoal])? = nil) {
        self.goalRepository = goalRepository
        self.goalsForEnrollments = goalsForEnrollments
    }

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var enrollments: [ProgramEnrollment] = []
    /// The goal each block was for, keyed by enrollment. Empty until I1
    /// binds the read above.
    @State private var goalsByEnrollment: [UUID: BlockGoal] = [:]
    /// Names for the lifts the goals on screen name, so a milestone reads
    /// "BENCH 225" rather than nothing. Fetched once per load, and only when
    /// a goal on screen actually carries an `exerciseID`.
    @State private var liftNames: [UUID: String] = [:]
    @State private var loading = true
    /// A past block whose after-action thread is being prepared/pushed.
    @State private var aar: AARTarget?
    @State private var buildingAAR: UUID?
    /// A block was just built from the ledger; push a FRESH schedule
    /// page (the calendar's proven pattern).
    @State private var builtFromHere = false

    private struct AARTarget: Identifiable, Hashable {
        let id: UUID
        let title: String
        let opener: String
    }

    private var current: ProgramEnrollment? {
        enrollments.first { $0.endedAt == nil }
    }
    private var past: [ProgramEnrollment] {
        enrollments.filter { $0.endedAt != nil }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(theme.accent)
                        Text("READING YOUR LEDGER")
                            .font(GSFont.bold(13, relativeTo: .headline))
                            .tracking(0.9)
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .gs3DCard(cornerRadius: GSMetrics.radiusSm)
                } else {
                    if let current {
                        currentCard(current)
                    } else {
                        noBlockCard
                    }

                    buildDoor

                    if !past.isEmpty {
                        Text("THE LEDGER")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral500)
                            .padding(.top, 6)
                        ForEach(past) { enrollment in
                            pastRow(enrollment)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .navigationDestination(item: $aar) { target in
            CoachThreadLauncher(title: target.title, opener: target.opener)
                .background(theme.bg)
        }
        .navigationDestination(isPresented: $builtFromHere) {
            ProgramScheduleView()
                .background(theme.bg)
        }
    }

    // MARK: Current block — pinned, set aside from the ledger

    private func currentCard(_ enrollment: ProgramEnrollment) -> some View {
        let week = ProgramMath.currentWeek(startedOn: enrollment.startedOn,
                                           weeks: enrollment.weeks)
        return NavigationLink {
            ProgramScheduleView()
                .background(theme.bg)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("CURRENT BLOCK")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.accent)
                    Spacer()
                    Image(systemName: "figure.strengthtraining.traditional")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                }
                Text(displayName(enrollment))
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Week \(week) of \(enrollment.weeks) — where you are, what's coming, and the why behind it.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text("SCHEDULE · CALENDAR · TALK IT OVER")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral500)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
    }

    private var noBlockCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO BLOCK ON THE BAR")
                .font(GSFont.bold(16, relativeTo: .headline))
                .tracking(0.5)
                .foregroundStyle(theme.text)
            Text("Build one below and it takes this spot — the ledger keeps every block you finish.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
    }

    /// The way to the builder lives HERE now — MY PROGRAM opens the
    /// ledger, and building is one deliberate act inside it.
    private var buildDoor: some View {
        NavigationLink {
            ConsultEntryView(onBuilt: { builtFromHere = true })
                .background(theme.bg)
                .navigationBarBackButtonHidden(true)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text(current == nil ? "BUILD A PROGRAM" : "PLAN THE NEXT BLOCK")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.6)
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

    // MARK: The ledger rows

    private func pastRow(_ enrollment: ProgramEnrollment) -> some View {
        Button {
            guard buildingAAR == nil else { return }
            buildingAAR = enrollment.id
            Task {
                defer { buildingAAR = nil }
                guard let userID = appState.currentProfile?.id else { return }
                let opener = await BlockAAR.payload(enrollment: enrollment,
                                                    userID: userID)
                aar = AARTarget(id: enrollment.id,
                                title: displayName(enrollment),
                                opener: opener)
            }
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(displayName(enrollment))
                        .font(GSFont.bold(14, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(statusLine(enrollment))
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(enrollment.endedReason == "completed"
                                         ? Color.gsSuccess : theme.neutral500)
                    // What this block was FOR, and how it came out. Absent
                    // entirely for a block with no goal.
                    //
                    // The WHOLE line takes the colour, not just the outcome
                    // word: `statusLine` directly above already colours its
                    // whole line green for a completed block, and two
                    // adjacent kickers with different colouring rules read as
                    // two different kinds of thing. Green means done and
                    // nothing here is red — a missed block is a fact.
                    if let goalLine = goalLine(for: enrollment) {
                        Text(goalLine)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .tracking(0.8)
                            .foregroundStyle(goalsByEnrollment[enrollment.id]?.outcome == .met
                                             ? Color.gsSuccess : theme.neutral500)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                Spacer()
                if buildingAAR == enrollment.id {
                    ProgressView().tint(theme.accent)
                } else {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
        .accessibilityLabel("\(displayName(enrollment)), \(statusLine(enrollment)) — open the after-action with Coach")
    }

    private func displayName(_ enrollment: ProgramEnrollment) -> String {
        let raw = enrollment.template?.name ?? enrollment.templateSlug
        return raw.hasPrefix("Coach · ")
            ? String(raw.dropFirst("Coach · ".count)) : raw
    }

    /// Honest per-row status. Abandoned blocks say where they stopped —
    /// they are evidence, not embarrassments.
    private func statusLine(_ enrollment: ProgramEnrollment) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let started = formatter.string(from: enrollment.startedOn)
        guard let endedAt = enrollment.endedAt else {
            return "RUNNING — STARTED \(started.uppercased())"
        }
        let ended = formatter.string(from: endedAt)
        if enrollment.endedReason == "completed" {
            return "COMPLETED — \(started.uppercased()) TO \(ended.uppercased())"
        }
        let weeksRun = max(0, Calendar.current.dateComponents(
            [.weekOfYear], from: enrollment.startedOn, to: endedAt).weekOfYear ?? 0)
        return "ABANDONED WK \(min(weeksRun + 1, enrollment.weeks)) OF \(enrollment.weeks) — \(started.uppercased())"
    }

    // MARK: The goal each block was for (goal-first plan, task D5)

    /// This row's goal line, already worded — or nil, and then no line at
    /// all.
    private func goalLine(for enrollment: ProgramEnrollment) -> String? {
        let goal = goalsByEnrollment[enrollment.id]
        let name = goal?.target.exerciseID.flatMap { liftNames[$0] } ?? ""
        return Self.goalLine(goal, liftName: name, unit: ThemeStore.shared.weightUnit)
    }

    /// The goal this block was for, and how it came out.
    ///
    /// PHASE 1 RENDERS, PHASE 3 WRITES. `block_goals.outcome` is only ever
    /// set by the block-end check (spec §7, phase 3), so today this line is
    /// the milestone alone for every row — which is already the thing the
    /// ledger was missing: a finished block that does not say what it was FOR
    /// is a row nobody can read.
    ///
    /// Absent entirely for a block with no goal (every block built before
    /// this feature). No placeholder, no "no goal set" — the ledger is a
    /// record, and a record does not editorialise about its own gaps. The
    /// same silence covers a goal whose target carries no readable number:
    /// "  BY OCT 18" would be worse than nothing.
    ///
    /// A KICKER (caps, `neutral500`, 0.8 tracking — design rule 3), because
    /// it sits directly under `statusLine(_:)`, which is already one, and two
    /// adjacent metadata lines in different cases read as two different kinds
    /// of thing.
    static func goalLine(_ goal: BlockGoal?, liftName: String, unit: WeightUnit,
                         calendar: Calendar = .current) -> String? {
        guard let goal,
              let milestone = milestone(goal, liftName: liftName, unit: unit,
                                        calendar: calendar) else { return nil }
        guard let outcome = goal.outcome else { return milestone }
        return "\(outcome.rawValue.uppercased()) — \(milestone)"
    }

    /// "BENCH 225 BY OCT 18". The subject and its number, then the date when
    /// the goal has one — Maintenance, Recovery and Consistency are held for
    /// the block and carry none (spec §2.1).
    private static func milestone(_ goal: BlockGoal, liftName: String,
                                  unit: WeightUnit, calendar: Calendar) -> String? {
        guard let subject = subject(goal, liftName: liftName, unit: unit) else { return nil }
        guard let byDate = goal.byDate else { return subject.uppercased() }
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return "\(subject) by \(formatter.string(from: byDate))".uppercased()
    }

    /// One line per metric, from the target alone. nil when the target does
    /// not carry the number its own metric needs — a row that cannot say what
    /// it was for says nothing.
    private static func subject(_ goal: BlockGoal, liftName: String,
                                unit: WeightUnit) -> String? {
        let target = goal.target
        switch goal.metric {
        case .liftOneRepMax:
            guard let pounds = target.targetWeightLbs, !liftName.isEmpty else { return nil }
            return "\(liftName) \(Units.wholeNumber(pounds: pounds, unit: unit))"
        case .liftRepsAtLoad:
            guard let reps = target.targetReps, let load = target.loadLbs,
                  !liftName.isEmpty else { return nil }
            return "\(liftName) \(reps) × \(Units.wholeNumber(pounds: load, unit: unit))"
        case .weeklyMuscleSets:
            let sets = (target.muscleTargets ?? [:]).values.reduce(0, +)
            guard sets > 0 else { return nil }
            return "\(sets) sets a week"
        case .weeklyDistance:
            guard let distance = target.distance, distance > 0 else { return nil }
            let label = unit == .lbs ? "mi" : "km"
            return "\(Units.displayWeight(Decimal(distance))) \(label) a week"
        case .trainingDaysPerWeek:
            guard let days = target.days, days > 0 else { return nil }
            return "\(days) days a week"
        case .sessionsOfTypePerWeek:
            guard let sessions = target.sessions, sessions > 0 else { return nil }
            return "\(sessions) \(target.sessionType ?? "sessions") a week"
        case .lissMinutesPerWeek:
            guard let minutes = target.lissMinutes, minutes > 0 else { return nil }
            return "\(minutes) easy min a week"
        case .stretchingExercisesPerWeek:
            guard let count = target.stretchingExercises, count > 0 else { return nil }
            return "\(count) stretches a week"
        case .bodyWeight:
            guard let pounds = target.bodyWeightLbs else { return nil }
            return Units.formatBodyWeight(pounds: pounds, unit: unit)
        case .cumulativeVolume:
            guard let volume = target.volumeLbs, volume > 0 else { return nil }
            return "\(Int(Units.fromPounds(volume, to: unit).rounded())) \(unit.label) lifted"
        case .benchmarkTime:
            guard let seconds = target.targetSeconds, seconds > 0 else { return nil }
            return WeeklyGoalProgressMath.clock(Double(seconds))
        }
    }

    private func load() async {
        enrollments = (try? await ProgramRepository.history()) ?? []
        // ONE read for every row on screen, not one per row.
        let ids = enrollments.map(\.id)
        if let goalsForEnrollments {
            goalsByEnrollment = await goalsForEnrollments(ids)
        } else {
            goalsByEnrollment = await Self.goals(for: ids, repository: goalRepository)
        }
        await loadLiftNames()
        loading = false
    }

    /// What the frozen `BlockGoalRepository` CAN answer, keyed the way the
    /// rows need it.
    ///
    /// The protocol has one read of a goal — `activeGoal()`, the goal driving
    /// the athlete's active enrollment — so this returns at most one entry,
    /// and only when that enrollment is actually one of the rows on screen.
    /// That is a narrower answer than the plan's `.in("enrollment_id", …)`,
    /// and it is the honest one this stream can give without widening a
    /// surface three streams fork against; `goalsForEnrollments` is where I1
    /// hands in the wider read.
    ///
    /// It is a real read, not a placeholder: hand this a repository that
    /// knows the block and the line renders.
    /// `LedgerGoalLineTests.testTheLedgerReadsItsGoalThroughTheInjectedRepository`
    /// proves the whole chain — repository → map → `goalLine` — on a FINISHED
    /// block.
    static func goals(for enrollmentIDs: [UUID],
                      repository: any BlockGoalRepository) async -> [UUID: BlockGoal] {
        guard let goal = await repository.activeGoal(),
              enrollmentIDs.contains(goal.enrollmentID) else { return [:] }
        return [goal.enrollmentID: goal]
    }

    /// The exercise catalog, and only when a goal on screen names a lift.
    /// Every other ledger visit pays nothing for this.
    private func loadLiftNames() async {
        let wanted = Set(goalsByEnrollment.values.compactMap { $0.target.exerciseID })
        guard !wanted.isEmpty else {
            liftNames = [:]
            return
        }
        let rows = (try? await ExerciseRepository.fetchAll()) ?? []
        liftNames = Dictionary(uniqueKeysWithValues:
            rows.filter { wanted.contains($0.id) }.map { ($0.id, $0.name) })
    }
}
