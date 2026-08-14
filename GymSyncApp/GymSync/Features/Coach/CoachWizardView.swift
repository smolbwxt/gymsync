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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                dial("FOCUS", options: GeneratorScience.Focus.allCases.map(\.rawValue),
                     selected: focus.rawValue) { focus = GeneratorScience.Focus(rawValue: $0) ?? .hypertrophy }
                dial("LIFTING DAYS PER WEEK", options: ["1", "2", "3", "4", "5", "6", "7"],
                     selected: "\(days)") { days = Int($0) ?? 3 }
                dial("PROGRAM LENGTH · WEEKS", options: ["4", "8", "12"],
                     selected: "\(duration)") { duration = Int($0) ?? 8 }
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

                // Train every day: open days become ACTIVE RECOVERY.
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
                dial("EXPERIENCE", options: GeneratorScience.Experience.allCases.map(\.rawValue),
                     selected: experience.rawValue) { experience = GeneratorScience.Experience(rawValue: $0) ?? .new }

                equipmentDial

                aboutYou

                Button {
                    generatePreview()
                } label: {
                    Text(preview == nil ? "Build my week" : "Rebuild")
                }
                .buttonStyle(GSPrimaryButtonStyle())

                if let preview {
                    previewSection(preview)
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
        .navigationBarTitleDisplayMode(.inline)
        .task {
            allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
            sex = appState.currentProfile?.sex ?? ""
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
                                Text("\(ex.sets)×\(ex.repsLow)-\(ex.repsHigh)"
                                     + (ex.percentOfMax.map { String(format: " @ %.0f%%", $0) } ?? ""))
                                    .font(GSFont.body(12, relativeTo: .caption).monospacedDigit())
                                    .foregroundStyle(theme.neutral500)
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

    private func generatePreview() {
        let catalog = allExercises.enumerated().map { index, ex in
            ProgramGenerator.CatalogExercise(
                id: ex.id, name: ex.name,
                primaryMuscle: ex.primaryMuscle,
                secondaryMuscles: ex.secondaryMuscles,
                category: ex.category, equipment: ex.equipment,
                movementPattern: ex.movementPattern ?? "other",
                rank: index)
        }
        let inputs = ProgramGenerator.Inputs(
            focus: focus, daysPerWeek: days, durationWeeks: duration,
            experience: experience,
            sex: GeneratorScience.Sex(rawValue: sex) ?? .unspecified,
            equipment: equipment,
            cardioDays: cardioDays, cardioMinutes: cardioMinutes,
            fillWeekWithRecovery: fillWeek)
        lastInputs = inputs
        lastCatalog = catalog
        preview = ProgramGenerator.generate(inputs: inputs, catalog: catalog)
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
                        targetRepsLow: ex.cardioZone != nil ? nil : ex.repsLow,
                        targetRepsHigh: ex.cardioZone != nil ? nil : ex.repsHigh,
                        cardioZone: ex.cardioZone,
                        cardioMinutes: ex.cardioMinutes)
                }
                try await RoutineRepository.save(routine, exercises: exercises)
            }
            errorText = nil
            onCreated?()
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
