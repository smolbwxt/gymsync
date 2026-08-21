import CoreLocation
import SwiftUI

// MARK: - CoachWizardView (the COACH front door, generator design doc)
//
// Four dials → about-you (skippable, only what's missing) → a full
// preview of the generated week → CREATE, which writes the day routines
// into the lifter's collection with rep ranges, rests, and %1RM anchors
// from the evidence-cited generator core (GeneratorScience /
// ProgramGenerator — pure, deterministic, tested).
//
// V1 output = the WEEK OF ROUTINES (the thing you train tomorrow).
// Enrollment overlays, the Plan queue, and week-by-week waves ride the
// template-as-data integration next.
struct CoachWizardView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    var onCreated: (() -> Void)? = nil

    // Dials
    @State private var focus: GeneratorScience.Focus = .hypertrophy
    @State private var days = 3
    @State private var duration = 8
    @State private var experience: GeneratorScience.Experience = .new
    /// Equipment available (owner 2026-08-14: "factor in what equipment
    /// our home gym has — so we're not suggesting nonsense"). All on by
    /// default; the home-gym hub's inventory presets it when one exists.
    @State private var equipment: Set<String> = Set(Venue.equipmentClasses)
    /// Name of the hub whose inventory preset the dial — nil when the
    /// default all-on seed is showing.
    @State private var presetHubName: String?
    /// Cardio (owner 2026-08-14): dedicated days + MINUTES per session.
    @State private var cardioDays = 0
    @State private var cardioMinutes = 30
    @State private var fillWeek = false
    /// Session-length cap (owner 2026-08-15) — nil = no cap; the
    /// generator trims accessories, never mains, to fit.
    @State private var sessionMinutes: Int? = nil
    /// Deterministic shuffle counter — rotates picks among equivalent
    /// candidates; same seed always rebuilds the same week.
    @State private var seed = 0
    /// Kept so rerolls re-run the exact generation context.
    @State private var lastInputs: ProgramGenerator.Inputs?
    @State private var lastCatalog: [ProgramGenerator.CatalogExercise] = []
    // About you (prefilled from profile; skippable)
    @State private var sex: String = ""
    @State private var birthYearText = ""
    // Data
    @State private var allExercises: [Exercise] = []
    @State private var preview: ProgramGenerator.Program?
    @State private var busy = false
    @State private var errorText: String?
    // TrainingProfile chain (2026-08-21): the wizard now BUILDS a profile
    // and hands it to generatorInputs — the same door every athlete passes
    // through. Persona picks pre-fill the method dials (provenance-gated
    // in the profile layer); everything stays editable.
    @State private var personaSlug: String? = nil
    @State private var rankedGoals: [TrainingGoal] = [.hypertrophy]
    @State private var splitPref: GeneratorScience.SplitPreference = .auto
    @State private var structure: TrainingProfile.SessionStructure = .straight
    @State private var appetite = "standard"
    /// Pattern no-gos ("some people simply cannot do a clean & jerk"):
    /// hard exclusions, absolute by construction.
    @State private var noGoPatterns: Set<String> = []
    /// Novice calibration (owner 2026-08-21: "ask what seems hard for 5
    /// reps... percentages mean nothing to anyone other than the elite").
    @State private var calibrationAnchors: [String: Decimal] = [:]
    @State private var displayUnit: WeightUnit = .lbs
    // Body context (field report #22) — free-text in the display unit,
    // parsed to canonical lbs/inches on save; blank = not stated.
    @State private var bodyweightText = ""
    @State private var heightText = ""
    @State private var bodyFatText = ""
    // Lifts from routines the athlete starred (field report #18) —
    // fetched once per wizard visit, alias-resolved to canonical rows.
    @State private var starredExerciseIDs: Set<UUID> = []
    // Coach owns the calendar (longitudinal spec 3d): on create, the
    // block's training days land as a SOLO SERIES with max-spacing
    // weekdays, and ride the existing gated EventKit sync.
    @State private var scheduleSessions = true
    @State private var sessionHour = 17
    // Coach page redesign (owner 2026-08-21: "a form is the cardinal
    // sin"). The page reads top-down as insight -> offer -> five fat
    // section doors; each door opens a FOCUSED editor sheet holding the
    // controls that used to stack inline. A door's title renders accent
    // until its section is properly filled, then settles to theme.
    enum ProfileSection: String, Identifiable, CaseIterable {
        case goals, schedule, style, bodySection, limits
        var id: String { rawValue }
    }
    @State private var activeSection: ProfileSection? = nil
    @State private var visitedSections: Set<ProfileSection> = []
    /// The relationship's memory rides every rebuild — dropping it would
    /// reset block alternation and deprioritization each visit.
    @State private var savedCarryover: TrainingProfile.Carryover?
    @State private var savedProbeAt: Date?
    /// A block that just finished — the banner's content.
    @State private var blockCompletion: CoachLifecycle.BlockCompletion?
    /// The first-contact handshake: one computed observation from the
    /// athlete's existing log — demonstrate before you interrogate.
    @State private var firstContact: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let completion = blockCompletion {
                    blockCompleteBanner(completion)
                }

                // The page LEADS with insight (owner: never a form
                // first): the computed observation when Coach has data,
                // an honest waiting line when it doesn't.
                if blockCompletion == nil {
                    Text(firstContact ?? "Log a few sessions and Coach starts reading your training here — patterns, gaps, and what to do about them.")
                        .font(GSFont.body(13, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gs3DCard(cornerRadius: 16)
                }

                offerCard

                sectionDoor(.goals)
                sectionDoor(.schedule)
                sectionDoor(.style)
                sectionDoor(.bodySection)
                sectionDoor(.limits)

                Button {
                    generatePreview()
                } label: {
                    Text(preview == nil ? "Build my week" : "Rebuild")
                }
                .buttonStyle(GSPrimaryButtonStyle())

                // The profile is worth keeping even without a rebuild —
                // the debrief's register and the drift probes read it.
                Button {
                    Task {
                        guard let userID = appState.currentProfile?.id else { return }
                        try? await TrainingProfileRepository.save(currentProfile(),
                                                                  userID: userID)
                    }
                } label: {
                    Text("Save profile")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSSecondaryButtonStyle())

                if preview != nil {
                    // Deterministic variety: rotates among candidates the
                    // science rules score as interchangeable.
                    Button {
                        seed += 1
                        generatePreview()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "shuffle")
                                .font(.system(size: 13, weight: .semibold))
                            Text("Shuffle the picks")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(GSSecondaryButtonStyle())
                }

                if let preview {
                    previewSection(preview)
                    scheduleHint
                    Button {
                        scheduleSessions.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: scheduleSessions ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(scheduleSessions ? theme.accent : theme.neutral500)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Put my training days on the schedule")
                                    .font(GSFont.bold(14, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                Text("Coach books the rhythm above as planned sessions — edit or cancel any of them from the calendar.")
                                    .font(GSFont.body(11, relativeTo: .caption))
                                    .foregroundStyle(theme.neutral500)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if scheduleSessions {
                        dial("SESSION TIME", options: ["6 AM", "7 AM", "12 PM", "5 PM", "6 PM", "7 PM"],
                             selected: sessionTimeLabel) { sessionHour = Self.hourByLabel[$0] ?? 17 }
                    }
                    Button {
                        Task { await create(preview) }
                    } label: {
                        Text(busy ? "Creating…" : "Create these routines")
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .disabled(busy)
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
                Spacer(minLength: 24)
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Coach")
        .scrollDismissesKeyboard(.interactively)
        .sheet(item: $activeSection) { section in
            sectionSheet(section)
        }
        .navigationBarTitleDisplayMode(.inline)
        .task {
            allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
            sex = appState.currentProfile?.sex ?? ""
            // Starred-routine preference: aspiration as data. Alias rows
            // resolve to their canonical exercise so the signal survives
            // the catalog dedup.
            if let starredRoutines = try? await PublicWorkoutRepository.myStarredRoutineIDs(),
               !starredRoutines.isEmpty,
               let rows = try? await RoutineRepository.exercisesForRoutines(ids: starredRoutines) {
                let canonical = Dictionary(uniqueKeysWithValues: allExercises.map {
                    ($0.id, $0.aliasOf ?? $0.id)
                })
                starredExerciseIDs = Set(rows.map { canonical[$0.exerciseID] ?? $0.exerciseID })
            }
            // Phase 4 lifecycle: settle a finished block BEFORE loading
            // the profile, so the carryover it just wrote is what loads.
            blockCompletion = await CoachLifecycle.checkBlockEnd()
            // Settings first: displayUnit converts the body fields the
            // profile hydration below writes.
            if let settings = try? await UserSettingsRepository.get() {
                displayUnit = settings.weightUnit
                for slug in LiftAnchorMath.anchorSlugs {
                    if let anchor = settings.liftAnchors?[slug] {
                        calibrationAnchors[slug] = anchor
                    }
                }
            }
            // Returning athletes pick up where they left off: the saved
            // profile pre-fills every dial, and stated anchors show in
            // the calibration rows.
            if let saved = try? await TrainingProfileRepository.load() {
                savedCarryover = saved.carryover
                savedProbeAt = saved.lastProbeAt
                personaSlug = saved.persona
                rankedGoals = saved.rankedGoals
                splitPref = saved.split
                structure = saved.sessionStructure
                appetite = saved.intensityAppetite
                noGoPatterns = Set(saved.excludedPatterns)
                days = saved.daysPerWeek
                sessionMinutes = saved.sessionMinutes
                experience = saved.trainingAge.experience
                // A returning athlete's doors settle to theme - the
                // saved profile IS the filled state.
                visitedSections = Set(ProfileSection.allCases)
                if let bw = saved.bodyweightLbs {
                    let shown = displayUnit == .kg ? bw / 2.20462 : bw
                    bodyweightText = String(Int(shown.rounded()))
                }
                if let h = saved.heightInches {
                    let shown = displayUnit == .kg ? h * 2.54 : h
                    heightText = String(Int(shown.rounded()))
                }
                if let bf = saved.bodyFatPercent {
                    bodyFatText = String(Int(bf.rounded()))
                }
            }
            // First contact: one smart computed thing before any question.
            if let userID = appState.currentProfile?.id,
               let logs = try? await SessionRepository.recentSetLogs(
                   userID: userID,
                   since: Date(timeIntervalSinceNow: -28 * 86_400)) {
                let muscles = Dictionary(uniqueKeysWithValues: allExercises.map {
                    ($0.id, $0.primaryMuscle.lowercased())
                })
                firstContact = CoachObservations.firstContact(
                    logs: logs, muscleByExerciseID: muscles)
            }
            if let year = appState.currentProfile?.birthYear { birthYearText = "\(year)" }
            // Hub inventory preset (owner 2026-08-14: "the hub should host
            // what equipment is available, and that then should tell the
            // coach what's possible"): home gym → nearest hub → its
            // equipment seeds the dial. A preset, not a lock — every chip
            // stays tappable; any lookup failure keeps the all-on default.
            if let gym = try? await CheckInService.primaryGym(),
               let venues = try? await VenueRepository.all(),
               let hub = HubMatch.nearest(in: venues, of: CLLocationCoordinate2D(
                   latitude: gym.latitude, longitude: gym.longitude)) {
                let preset = Set(hub.equipment).intersection(Venue.equipmentClasses)
                if !preset.isEmpty {
                    equipment = preset
                    presetHubName = hub.name
                }
            }
        }
    }

    // MARK: - Dials

    private func dial(_ title: String, options: [String], selected: String,
                      onPick: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(options, id: \.self) { option in
                        let isOn = option == selected
                        Button {
                            onPick(option)
                            preview = nil
                        } label: {
                            Text(label(for: option))
                                .font(GSFont.bold(13, relativeTo: .subheadline))
                                .foregroundStyle(isOn ? theme.bg : theme.neutral700)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(isOn ? theme.accent : theme.surface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func label(for option: String) -> String {
        switch option {
        case "weightLoss": return "Weight Loss"
        case "new": return "New"
        case "intermediate": return "Intermediate"
        case "advanced": return "Advanced"
        default: return option.capitalized
        }
    }

    /// Multi-select — "what does your gym actually have."
    private var equipmentDial: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR GYM HAS")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Venue.equipmentClasses, id: \.self) { kind in
                        let isOn = equipment.contains(kind)
                        Button {
                            if isOn {
                                // Never empty — bodyweight is always true.
                                if equipment.count > 1 { equipment.remove(kind) }
                            } else {
                                equipment.insert(kind)
                            }
                            preview = nil
                        } label: {
                            Text(kind.capitalized)
                                .font(GSFont.bold(13, relativeTo: .subheadline))
                                .foregroundStyle(isOn ? theme.bg : theme.neutral700)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(isOn ? theme.accent : theme.surface)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            if let presetHubName {
                Text("Preset from the \(presetHubName) hub's inventory — tap to adjust.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - About you

    private var aboutYou: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ABOUT YOU · OPTIONAL")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
            Text("Sex tunes rest and rep tops only — the physiology, never the movements or zones. Birth year sets honest heart-rate bands.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
            HStack(spacing: 6) {
                ForEach(["female", "male"], id: \.self) { option in
                    let isOn = sex == option
                    Button {
                        sex = isOn ? "" : option
                        preview = nil
                    } label: {
                        Text(option.capitalized)
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(isOn ? theme.bg : theme.neutral700)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(isOn ? theme.accent : theme.surface)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                TextField("Birth year", text: $birthYearText)
                    .keyboardType(.numberPad)
                    .font(GSFont.body(14, relativeTo: .body))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(width: 110)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.divider, lineWidth: 1))
            }
            // Body context (field report #22): optional, athlete-stated.
            HStack(spacing: 6) {
                bodyField(displayUnit == .kg ? "Weight kg" : "Weight lb",
                          text: $bodyweightText)
                bodyField(displayUnit == .kg ? "Height cm" : "Height in",
                          text: $heightText)
                bodyField("Bodyfat %", text: $bodyFatText)
            }
            Text("Optional. Weight gives your debrief honest context; at higher bodyweights Coach parks jumps and bounding — landings, not effort, are the risk it manages.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Preview

    private func previewSection(_ program: ProgramGenerator.Program) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Your week")
            // The receipt: exactly what the generator was told — any
            // stuck dial is visible here instantly.
            Text("\(label(for: focus.rawValue)) · \(days) days · \(duration) weeks · \(label(for: experience.rawValue))\(sex.isEmpty ? "" : " · \(sex)")"
                 .uppercased())
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.accent)
            ForEach(Array(program.days.enumerated()), id: \.offset) { _, day in
                VStack(alignment: .leading, spacing: 6) {
                    Text(day.name)
                        .font(GSFont.bold(15, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    ForEach(Array(day.exercises.enumerated()), id: \.offset) { exIndex, ex in
                        HStack(spacing: 8) {
                            Text(ex.name)
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.text)
                            Spacer()
                            if let zone = ex.cardioZone, let minutes = ex.cardioMinutes {
                                Text("Zone \(zone) · \(minutes) min")
                                    .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                                    .foregroundStyle(theme.neutral500)
                            } else {
                                // Weights lead, percentages explain (owner
                                // 2026-08-21: "percentages mean nothing to
                                // anyone other than the elite"): when the
                                // athlete's stated anchors can seed a
                                // weight, show the NUMBER — the % becomes
                                // the subtext for the curious.
                                VStack(alignment: .trailing, spacing: 1) {
                                    if let pct = ex.percentOfMax,
                                       let pounds = previewSeedPounds(for: ex, percent: pct) {
                                        Text("\(ex.sets)×\(ex.repsLow)-\(ex.repsHigh) · \(Units.format(pounds: pounds, unit: displayUnit, rounded: false, includeUnit: true))")
                                            .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                                            .foregroundStyle(theme.neutral500)
                                        Text(String(format: "≈%.0f%% of your starting max", pct))
                                            .font(GSFont.body(9, relativeTo: .caption2))
                                            .foregroundStyle(theme.neutral500.opacity(0.8))
                                    } else {
                                        Text("\(ex.sets)×\(ex.repsLow)-\(ex.repsHigh)"
                                             + (ex.percentOfMax.map { String(format: " @ %.0f%%", $0) } ?? ""))
                                            .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                                            .foregroundStyle(theme.neutral500)
                                    }
                                }
                            }
                            // Reroll (deterministic next-best, never a
                            // shuffle) — any lift can be swapped.
                            if ex.slot != nil {
                                Button {
                                    reroll(dayName: day.name, exerciseIndex: exIndex)
                                } label: {
                                    Image(systemName: "arrow.2.circlepath")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(theme.accent)
                                        .frame(width: 26, height: 26)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .gs3DCard(cornerRadius: GSMetrics.radiusMd)
            }
            ForEach(Array(program.notes.enumerated()), id: \.offset) { _, note in
                Text(note)
                    .font(GSFont.body(11.5, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Generate + create

    /// Enroll the lifter in the block Coach just generated, so the weekly
    /// wave actually reaches their prescriptions.
    ///
    /// Focus lifts are the program's MAIN lifts — supplied programmatically
    /// (the `.generated` focus rule) rather than picked in the bundled
    /// enrollment UI. Baselines are each lift's best qualifying set from the
    /// last 180 days, using the same estimator the session suggestions use so
    /// the two can never disagree. A lift with no history simply gets no
    /// baseline: `WorkingWeight` then falls through to its other rungs rather
    /// than inventing a number.
    ///
    /// Best-effort throughout — the day routines are the deliverable, and a
    /// failed enrollment must not cost the lifter their program.
    @MainActor
    /// Books the block's training days as a solo SessionSeries: anchor =
    /// tomorrow, weekdays = SchedulePlanner's max-spacing offsets mapped
    /// onto real days, until = block end. Materialized occurrences then
    /// ride the same gated EventKit sync the schedule sheet uses.
    private func bookTrainingDays() async {
        let cal = Calendar.current
        guard let anchor = cal.date(byAdding: .day, value: 1, to: Date()) else { return }
        let offsets = SchedulePlanner.spacingOffsets[max(1, min(7, days))] ?? [0]
        let dayInputs: [SeriesDayInput] = offsets.compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: offset, to: anchor) else { return nil }
            return SeriesDayInput(weekday: cal.component(.weekday, from: day),
                                  hour: sessionHour, minute: 0, routineID: nil)
        }
        guard !dayInputs.isEmpty,
              let until = cal.date(byAdding: .day, value: duration * 7 - 1, to: anchor)
        else { return }
        guard let series = try? await SeriesRepository.create(
            groupID: nil, days: dayInputs, untilDate: until, timezone: .current)
        else { return }
        // Calendar writes: same gate and bridge as ScheduleSessionView.
        guard CalendarSyncPrefsStore.isEnabled(),
              let occurrences = try? await SeriesRepository.occurrences(seriesID: series.id)
        else { return }
        for session in occurrences {
            _ = await EventKitBridge.syncEvent(session: session,
                                               routineName: "Coach session",
                                               exerciseCount: nil)
        }
    }

    private func enrollGenerated(row: ProgramTemplateRow,
                                 weeks: [ProgramWeek],
                                 program: ProgramGenerator.Program) async {
        guard let userID = appState.currentProfile?.id else { return }
        let mainLiftIDs = Array(Set(program.days
            .flatMap(\.exercises)
            .filter { $0.isMain && $0.cardioZone == nil }
            .map(\.exerciseID)))
        guard !mainLiftIDs.isEmpty else { return }

        var baselines: [String: Double] = [:]
        if let since = Calendar.current.date(byAdding: .day, value: -180, to: .now),
           let logs = try? await SessionRepository.recentSetLogs(userID: userID, since: since) {
            let byExercise = Dictionary(grouping: logs, by: \.exerciseID)
            for id in mainLiftIDs {
                guard let history = byExercise[id],
                      let best = WorkingWeight.bestQualifyingSet(in: history) else { continue }
                let oneRM = StatMath.estimatedOneRepMax(weight: best.weight, reps: best.reps)
                baselines[id.uuidString.lowercased()] = NSDecimalNumber(decimal: oneRM).doubleValue
            }
        }

        // Register before enrolling so `enrollment.template` resolves on this
        // launch — the store otherwise only loads generated blocks at startup.
        let template = ProgramTemplate(row: row, weeks: weeks)
        ProgramTemplateStore.shared.register([template])

        // One active enrollment per lifter (partial unique index). Generating
        // a new block is an explicit replacement, so retire the old one.
        if let active = try? await ProgramRepository.active(), active.endedAt == nil {
            try? await ProgramRepository.end(enrollmentID: active.id, reason: "abandoned")
        }
        _ = try? await ProgramRepository.enroll(
            template: template,
            focus: ProgramFocus(exerciseIDs: mainLiftIDs),
            baseline: baselines)
    }

    private func generatePreview() {
        // Alias rows (catalog dedup 20260821000001) never enter selection —
        // the same movement can't be "varied" into itself under a second
        // name. Their history still resolves everywhere else.
        let selectable = allExercises.filter { $0.aliasOf == nil }
        let catalog = selectable.enumerated().map { index, ex in
            ProgramGenerator.CatalogExercise(
                id: ex.id, name: ex.name,
                primaryMuscle: ex.primaryMuscle,
                secondaryMuscles: ex.secondaryMuscles,
                category: ex.category, equipment: ex.equipment,
                movementPattern: ex.movementPattern ?? "other",
                rank: index,
                // Catalog labels (20260816000002) — the score-first
                // selection's fuel; defaults keep pre-label rows sane.
                focusScores: ex.focusScores ?? [:],
                complexity: ex.complexity ?? 3,
                fatigueCost: ex.fatigueCost ?? 3,
                spinalLoad: ex.spinalLoad ?? 0,
                repMin: ex.repMin,
                repMax: ex.repMax,
                lengthenedBias: ex.lengthenedBias ?? false,
                unilateral: ex.unilateral ?? false,
                impact: ex.impact ?? "none",
                legInterference: ex.legInterference ?? false,
                explosive: ex.explosive ?? false,
                jointStress: ex.jointStress ?? [])
        }
        // The profile IS the input now — the wizard builds it, the
        // generator reads it, and the same object persists on CREATE so
        // the debrief, drift probes, and block planning read the same
        // truth (2026-08-21).
        let profile = currentProfile()
        focus = profile.generatorFocus
        var inputs = profile.generatorInputs(
            durationWeeks: duration,
            cardioDays: cardioDays, cardioMinutes: cardioMinutes,
            fillWeekWithRecovery: fillWeek,
            seed: seed)
        inputs.sessionMinutes = sessionMinutes
        inputs.starredExerciseIDs = starredExerciseIDs
        lastInputs = inputs
        lastCatalog = catalog
        preview = ProgramGenerator.generate(inputs: inputs, catalog: catalog)
    }

    /// The athlete as data — every dial lands in a profile field the
    /// generator provably reads.
    private func currentProfile() -> TrainingProfile {
        var profile = TrainingProfile()
        profile.persona = personaSlug
        profile.rankedGoals = rankedGoals.isEmpty ? [.hypertrophy] : rankedGoals
        profile.trainingAge = {
            switch experience {
            case .new: return .novice
            case .intermediate: return .intermediate
            case .advanced: return .advanced
            }
        }()
        profile.sexRaw = GeneratorScience.Sex(rawValue: sex)?.rawValue
            ?? GeneratorScience.Sex.unspecified.rawValue
        profile.daysPerWeek = days
        profile.sessionMinutes = sessionMinutes
        profile.split = splitPref
        profile.sessionStructure = structure
        profile.intensityAppetite = appetite
        profile.excludedPatterns = Array(noGoPatterns).sorted()
        // All-on equipment means "everything" — nil, so a new hub class
        // never silently filters.
        profile.equipment = equipment == Set(Venue.equipmentClasses) ? nil : equipment
        // The relationship's memory (Phase 4) — block alternation and
        // deprioritized lifts survive the dials.
        profile.carryover = savedCarryover
        profile.lastProbeAt = savedProbeAt
        // Body context: parse in the display unit, store canonical.
        if let bw = Double(bodyweightText.replacingOccurrences(of: ",", with: ".")), bw > 0 {
            profile.bodyweightLbs = displayUnit == .kg ? bw * 2.20462 : bw
        }
        if let h = Double(heightText.replacingOccurrences(of: ",", with: ".")), h > 0 {
            profile.heightInches = displayUnit == .kg ? h / 2.54 : h
        }
        if let bf = Double(bodyFatText.replacingOccurrences(of: ",", with: ".")), bf > 0, bf < 75 {
            profile.bodyFatPercent = bf
        }
        return profile
    }

    private func bodyField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .keyboardType(.decimalPad)
            .font(GSFont.body(14, relativeTo: .body))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.divider, lineWidth: 1))
    }

    /// SchedulePlanner's spacing pattern as a rhythm hint (Phase 4
    /// scheduling — the calendar writes ride the scheduling UI pass, but
    /// the 48-hour law reaches the athlete as advice today).
    // MARK: - Redesign doors (owner 2026-08-21)

    /// One line on what Coach actually does — the offer, before any ask.
    private var offerCard: some View {
        Text("A training block built to your goals, booked on your calendar, and debriefed with you after every session. Fill in the sections below — Coach reads all of it.")
            .font(GSFont.body(12, relativeTo: .caption))
            .foregroundStyle(theme.neutral700)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func sectionTitle(_ section: ProfileSection) -> String {
        switch section {
        case .goals: return "GOALS"
        case .schedule: return "SCHEDULE"
        case .style: return "STYLE"
        case .bodySection: return "BODY"
        case .limits: return "LIMITS"
        }
    }

    /// The face line states the section's CURRENT values - the door shows
    /// its state from the outside, same law as every You-tab widget.
    private func sectionFace(_ section: ProfileSection) -> String {
        switch section {
        case .goals:
            let coach = CoachPersona.bySlug(personaSlug)?.name ?? "No coach picked"
            let goal = rankedGoals.first.map { $0.rawValue.replacingOccurrences(of: "_", with: " ") } ?? "no goal"
            return "\(coach) · \(goal) first · \(experience.rawValue)"
        case .schedule:
            let cap = sessionMinutes.map { "\($0) min" } ?? "no cap"
            let cardio = cardioDays > 0 ? " · \(cardioDays) cardio" : ""
            return "\(days) days · \(duration) weeks · \(cap)\(cardio)"
        case .style:
            return "\(splitPref.rawValue) split · \(structure.rawValue) · \(appetite)"
        case .bodySection:
            var parts: [String] = []
            if !bodyweightText.isEmpty { parts.append("\(bodyweightText) \(displayUnit == .kg ? "kg" : "lb")") }
            if !bodyFatText.isEmpty { parts.append("\(bodyFatText)% bf") }
            if !sex.isEmpty { parts.append(sex) }
            return parts.isEmpty ? "Sex · body · lift anchors" : parts.joined(separator: " · ")
        case .limits:
            var parts: [String] = []
            if !noGoPatterns.isEmpty { parts.append("\(noGoPatterns.count) no-go\(noGoPatterns.count == 1 ? "" : "s")") }
            if equipment != Set(Venue.equipmentClasses) { parts.append("equipment limited") }
            return parts.isEmpty ? "No-gos · equipment" : parts.joined(separator: " · ")
        }
    }

    /// Filled = the athlete has actually engaged: real data for data
    /// sections, a visit (or a saved profile) for preference sections.
    private func sectionFilled(_ section: ProfileSection) -> Bool {
        switch section {
        case .goals:
            return personaSlug != nil || rankedGoals != [.hypertrophy] || visitedSections.contains(.goals)
        case .schedule:
            return visitedSections.contains(.schedule)
        case .style:
            return visitedSections.contains(.style)
        case .bodySection:
            return !bodyweightText.isEmpty || !bodyFatText.isEmpty || !sex.isEmpty
                || visitedSections.contains(.bodySection)
        case .limits:
            return !noGoPatterns.isEmpty || equipment != Set(Venue.equipmentClasses)
                || visitedSections.contains(.limits)
        }
    }

    /// A fat You-style door: big title (ACCENT until filled, then theme),
    /// face line with current values, extruded like everything else.
    private func sectionDoor(_ section: ProfileSection) -> some View {
        Button {
            activeSection = section
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(sectionTitle(section))
                        .font(GSFont.bold(24, relativeTo: .title2))
                        .tracking(0.5)
                        .foregroundStyle(sectionFilled(section) ? theme.text : theme.accent)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(theme.neutral500)
                }
                Spacer(minLength: 14)
                Text(sectionFace(section))
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
    }

    /// The focused editor behind a door - exactly one section's controls.
    private func sectionSheet(_ section: ProfileSection) -> some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .goals:
                        CoachPersonaStrip(selected: $personaSlug)
                            .onChange(of: personaSlug) { _, slug in
                                // The coach's method preset fills dials the
                                // athlete hasn't touched; later edits win
                                // because they're edits.
                                guard let coach = CoachPersona.bySlug(slug) else { return }
                                splitPref = coach.split
                                structure = coach.sessionStructure
                                appetite = coach.intensityAppetite
                                preview = nil
                            }
                        GoalRankingSection(ranked: $rankedGoals)
                            .onChange(of: rankedGoals) { _, _ in preview = nil }
                        dial("EXPERIENCE", options: GeneratorScience.Experience.allCases.map(\.rawValue),
                             selected: experience.rawValue) { experience = GeneratorScience.Experience(rawValue: $0) ?? .new }
                    case .schedule:
                        dial("LIFTING DAYS PER WEEK", options: ["1", "2", "3", "4", "5", "6", "7"],
                             selected: "\(days)") { days = Int($0) ?? 3 }
                        dial("PROGRAM LENGTH · WEEKS", options: ["4", "8", "12"],
                             selected: "\(duration)") { duration = Int($0) ?? 8 }
                        dial("SESSION LENGTH · MINUTES", options: ["45", "60", "75", "90", "No cap"],
                             selected: sessionMinutes.map(String.init) ?? "No cap") {
                            sessionMinutes = Int($0)
                        }
                        dial("CARDIO DAYS PER WEEK", options: ["0", "1", "2", "3", "4", "5"],
                             selected: "\(cardioDays)") { cardioDays = Int($0) ?? 0 }
                        if cardioDays > 0 {
                            dial("CARDIO · MINUTES PER SESSION", options: ["15", "20", "30", "45", "60"],
                                 selected: "\(cardioMinutes)") { cardioMinutes = Int($0) ?? 30 }
                        }
                        if days + cardioDays > 7 {
                            Text("More sessions than days — cardio rides your lifting days as PM sessions. Keep 6+ hours between when you can.")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Button {
                            fillWeek.toggle()
                            preview = nil
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: fillWeek ? "checkmark.circle.fill" : "circle")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundStyle(fillWeek ? theme.accent : theme.neutral500)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Train every day")
                                        .font(GSFont.bold(14, relativeTo: .headline))
                                        .foregroundStyle(theme.text)
                                    Text("Open days become active recovery — mobility and a zone-1 walk. In the gym daily; the easy days stay easy.")
                                        .font(GSFont.body(11, relativeTo: .caption))
                                        .foregroundStyle(theme.neutral500)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    case .style:
                        dial("SPLIT", options: GeneratorScience.SplitPreference.allCases.map(\.rawValue),
                             selected: splitPref.rawValue) {
                            splitPref = GeneratorScience.SplitPreference(rawValue: $0) ?? .auto
                        }
                        if splitPref == .bro {
                            Text("A bodypart split hits each muscle once a week; the research consensus favors twice. The hybrid keeps the bro feel and adds the second touch — your call, and Coach won't nag.")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        dial("SESSION STYLE", options: TrainingProfile.SessionStructure.allCases.map(\.rawValue),
                             selected: structure.rawValue) {
                            structure = TrainingProfile.SessionStructure(rawValue: $0) ?? .straight
                        }
                        dial("INTENSITY", options: ["conservative", "standard", "aggressive"],
                             selected: appetite) { appetite = $0 }
                    case .bodySection:
                        aboutYou
                        if experience == .new {
                            NoviceCalibrationSection(anchors: $calibrationAnchors,
                                                     unit: displayUnit)
                        }
                    case .limits:
                        noGoSection
                        equipmentDial
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.bg)
            .navigationTitle(sectionTitle(section).capitalized)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        visitedSections.insert(section)
                        activeSection = nil
                        preview = nil
                    }
                }
            }
        }
    }

    private static let hourByLabel: [String: Int] = [
        "6 AM": 6, "7 AM": 7, "12 PM": 12, "5 PM": 17, "6 PM": 18, "7 PM": 19,
    ]
    private var sessionTimeLabel: String {
        Self.hourByLabel.first { $0.value == sessionHour }?.key ?? "5 PM"
    }

    private var scheduleHint: some View {
        let offsets = SchedulePlanner.spacingOffsets[max(1, min(7, days))] ?? [0]
        let dayList = offsets.map { "\($0 + 1)" }.joined(separator: ", ")
        return Text("Rhythm: train on days \(dayList) of your week — the spacing that gives every muscle its ~48 hours.")
            .font(GSFont.body(11, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func blockCompleteBanner(_ completion: CoachLifecycle.BlockCompletion) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.accent)
                Text("BLOCK COMPLETE")
                    .font(GSFont.bold(13, relativeTo: .footnote))
                    .tracking(1.0)
                    .foregroundStyle(theme.text)
                Spacer()
                Text("\(Int(completion.outcome.adherence * 100))% ATTENDANCE")
                    .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                    .foregroundStyle(theme.neutral700)
            }
            if !completion.strugglingNames.isEmpty {
                Text("Worth a change this block: \(completion.strugglingNames.joined(separator: ", ")) — stalled or fighting fatigue at the end. The next build treats them differently.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            let suggested = completion.outcome.suggestedDaysPerWeek
            if suggested != days {
                Text("Your attendance supported \(suggested) day\(suggested == 1 ? "" : "s") a week — a plan you complete beats a plan you admire.")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let graduation = completion.graduation {
                Text(graduation.probe)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                Button {
                    // Offered, never imposed — the tap IS the athlete's
                    // answer, committed with provenance `confirmed`.
                    experience = .intermediate
                    savedCarryover?.pendingGraduation = false
                    Task {
                        guard let userID = appState.currentProfile?.id,
                              var profile = try? await TrainingProfileRepository.load()
                        else { return }
                        profile.trainingAge = .intermediate
                        profile.provenance["trainingAge"] = .confirmed
                        profile.carryover?.pendingGraduation = false
                        try? await TrainingProfileRepository.save(profile, userID: userID)
                    }
                    blockCompletion = nil
                    preview = nil
                } label: {
                    Text("GRADUATE — BRING ON THE BARBELL")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .tracking(0.8)
                }
                .buttonStyle(GSSecondaryButtonStyle())
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 16).fill(theme.surface))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .strokeBorder(theme.accent.opacity(0.35), lineWidth: 1))
    }

    /// Anchor-derived preview weight: the stated hard-for-5 weight →
    /// estimated 1RM (Epley at 5 reps) → this prescription's percent, on
    /// the plate grid. nil when no anchor reaches the lift — a dash beats
    /// fake confidence.
    private func previewSeedPounds(for ex: ProgramGenerator.Exercise,
                                   percent: Double) -> Decimal? {
        guard let slug = allExercises.first(where: { $0.id == ex.exerciseID })?.slug,
              let fiveRM = LiftAnchorMath.seedPounds(for: slug,
                                                     anchors: calibrationAnchors),
              fiveRM > 0
        else { return nil }
        let oneRM = StatMath.estimatedOneRepMax(weight: fiveRM, reps: 5)
        let target = oneRM * Decimal(percent) / 100
        let unitValue = Units.fromPounds(target, to: displayUnit)
        return Units.toPounds(
            Units.roundToIncrement(unitValue, step: displayUnit.displayIncrement),
            from: displayUnit)
    }

    private var noGoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("NO-GOS · MOVEMENTS THAT ARE OFF THE TABLE")
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(0.9)
                .foregroundStyle(theme.text.opacity(0.78))
            ForEach([("push_vertical", "Overhead pressing"),
                     ("push_horizontal", "Bench pressing"),
                     ("squat", "Squatting"),
                     ("hinge", "Deadlifting / hinging")], id: \.0) { pattern, label in
                Button {
                    if noGoPatterns.contains(pattern) {
                        noGoPatterns.remove(pattern)
                    } else {
                        noGoPatterns.insert(pattern)
                    }
                    preview = nil
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: noGoPatterns.contains(pattern)
                              ? "xmark.circle.fill" : "circle")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(noGoPatterns.contains(pattern)
                                             ? theme.accent : theme.neutral500)
                        Text(label)
                            .font(GSFont.bold(13, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if !noGoPatterns.isEmpty {
                Text("Excluded absolutely — nothing overrides a no-go, and the substitution graph fills every hole it leaves.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func reroll(dayName: String, exerciseIndex: Int) {
        guard var program = preview, let inputs = lastInputs,
              let dayIndex = program.days.firstIndex(where: { $0.name == dayName }),
              program.days[dayIndex].exercises.indices.contains(exerciseIndex),
              let replacement = ProgramGenerator.reroll(
                program.days[dayIndex].exercises[exerciseIndex],
                in: program.days[dayIndex],
                inputs: inputs, catalog: lastCatalog) else { return }
        program.days[dayIndex].exercises[exerciseIndex] = replacement
        preview = program
    }

    @MainActor
    private func create(_ program: ProgramGenerator.Program) async {
        guard let ownerID = appState.currentProfile?.id else { return }
        busy = true
        defer { busy = false }
        // The profile persists on CREATE — the debrief's register, the
        // drift probes, and block planning all read this same truth.
        // Best-effort: a failed save must never cost the routines.
        var profile = currentProfile()
        focus = profile.generatorFocus
        // The ledger grows at CREATE: this block's goal joins the history
        // (the planner's alternation reads it), and any standing
        // graduation offer is considered answered by moving on.
        var carryover = profile.carryover ?? TrainingProfile.Carryover()
        carryover.blockGoalHistory.append(profile.blockGoal)
        carryover.pendingGraduation = false
        profile.carryover = carryover
        savedCarryover = carryover
        try? await TrainingProfileRepository.save(profile, userID: ownerID)
        // Novice calibration → lift anchors (owner 2026-08-21): stated
        // hard-for-5 weights become the seeds every suggestion reads;
        // merged, never wholesale — an earlier anchor survives a skipped
        // row.
        if !calibrationAnchors.isEmpty,
           var settings = try? await UserSettingsRepository.get() {
            var anchors = settings.liftAnchors ?? [:]
            for (slug, pounds) in calibrationAnchors where pounds > 0 {
                anchors[slug] = pounds
            }
            settings.liftAnchors = anchors
            try? await UserSettingsRepository.upsert(settings)
        }
        do {
            // Persist the skippable demographics when supplied.
            let year = Int(birthYearText)
            if !sex.isEmpty || year != nil {
                try? await ProfileRepository.updateDemographics(
                    sex: sex.isEmpty ? nil : sex, birthYear: year)
            }
            let now = Date()
            for day in program.days {
                let routineID = UUID()
                let routine = Routine(
                    id: routineID, ownerID: ownerID,
                    name: "Coach · \(day.name)",
                    description: "Generated by Coach — \(label(for: focus.rawValue)), \(days)×/week.",
                    visibility: "private", createdAt: now, updatedAt: now)
                let exercises = day.exercises.enumerated().map { index, ex in
                    RoutineExercise(
                        id: UUID(), routineID: routineID, exerciseID: ex.exerciseID,
                        position: index + 1,
                        targetSets: ex.sets,
                        targetReps: ex.cardioZone != nil ? nil : "\(ex.repsLow)-\(ex.repsHigh)",
                        targetWeight: nil,
                        restSeconds: ex.restSeconds,
                        notes: nil,
                        supersetGroup: ex.supersetGroup,
                        targetRepsLow: ex.cardioZone != nil ? nil : ex.repsLow,
                        targetRepsHigh: ex.cardioZone != nil ? nil : ex.repsHigh,
                        cardioZone: ex.cardioZone,
                        cardioMinutes: ex.cardioMinutes)
                }
                try await RoutineRepository.save(routine, exercises: exercises)
            }
            // Data bridge (generator wave): the block also persists as a
            // user-owned template row (kind 'takeover') so it has identity
            // in the Plan queue and on the shelf. Best-effort by design —
            // the day routines above are the deliverable; a missed row
            // just means no queue card.
            let focusKind = focus == .weightLoss ? "weight_loss" : focus.rawValue
            let weekPlan = ProgramGenerator.weekSummaries(program)
            let savedRow = try? await ProgramTemplateRepository.saveGenerated(
                name: "Coach · \(label(for: focus.rawValue)) · \(days)-day",
                summary: "Generated \(duration)-week \(label(for: focus.rawValue).lowercased()) block — \(days) lifting days a week.",
                focusKind: focusKind,
                sessionsPerWeek: days,
                durationWeeks: duration,
                weeks: weekPlan)
            // ENROLL the block we just generated. Without this the week-over-
            // week machinery never engages: WorkingWeight rung 1 reads
            // `enrollment.template.weeks[currentWeek-1]`, so an unenrolled
            // Coach block is one static week repeated for the whole duration.
            if let savedRow, !weekPlan.isEmpty {
                await enrollGenerated(row: savedRow, weeks: weekPlan, program: program)
                // The block joins the Plan queue (Phase 4 scheduling,
                // block level) — the shelf and queue can see it; per-
                // session calendar writes ride the scheduling UI pass.
                _ = try? await TrainingPlanRepository.add(templateID: savedRow.id)
            }
            // Coach owns the calendar (longitudinal spec 3d): book the
            // block's rhythm as a SOLO series anchored tomorrow, weekdays
            // from the same max-spacing pattern scheduleHint shows. Best
            // effort - a booking failure never blocks the block.
            if scheduleSessions { await bookTrainingDays() }
            errorText = nil
            onCreated?()
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
