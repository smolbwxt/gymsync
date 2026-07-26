import SwiftUI

// MARK: - Training Programs P1: Campaigns-tab program UI
//
// Design: docs/superpowers/specs/2026-07-24-training-programs-design.md
// ("UI" section). All program surfaces live inside Library ▸ Campaigns —
// no fifth segment. Three views:
//   * ProgramCard          — the enrolled "Your program" card (tab section)
//   * ProgramDetailView    — pushed: full week table, actions, completion
//   * ProgramTemplateDetailView — pushed: scheme, focus picker, baseline,
//                            Start (the enrollment flow)
// Transparency doctrine throughout: every suggested weight renders WITH
// its math (ProgramMath.prescriptionText), and the whole plan is visible
// up front.

// MARK: - ProgramCard (the tab's "Your program" section body)

struct ProgramCard: View {
    @Environment(\.gsTheme) private var theme
    let enrollment: ProgramEnrollment
    let template: ProgramTemplate
    let focusExercises: [Exercise]
    let sessionsThisWeek: Int

    private var week: Int {
        ProgramMath.currentWeek(startedOn: enrollment.startedOn, weeks: enrollment.weeks)
    }
    private var weekSpec: ProgramWeek? {
        let index = week - 1
        guard template.weeks.indices.contains(index) else { return nil }
        return template.weeks[index]
    }
    private var complete: Bool {
        ProgramMath.isComplete(startedOn: enrollment.startedOn, weeks: enrollment.weeks)
    }

    var body: some View {
        GSCard(bordered: false) {
            // No internal kicker — this card always sits directly under the
            // tab's "Your program" GSSectionHeader (screenshot review: the
            // pair read as a stuttered duplicate).
            VStack(alignment: .leading, spacing: 6) {
                Text(template.name)
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)

                if complete {
                    Text("Complete — see your results")
                        .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.accent700)
                } else {
                    HStack(spacing: 6) {
                        Text("Week \(week) of \(enrollment.weeks)")
                            .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.accent700)
                        if weekSpec?.isDeload == true {
                            Text("· Deload")
                                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        }
                    }

                    if let weekSpec {
                        if focusExercises.isEmpty {
                            Text(ProgramMath.prescriptionText(week: weekSpec, baseline: nil))
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        } else {
                            ForEach(focusExercises) { exercise in
                                Text("\(exercise.name) — \(ProgramMath.prescriptionText(week: weekSpec, baseline: enrollment.baselineValue(for: exercise.id)))")
                                    .font(GSFont.body(13, relativeTo: .subheadline))
                                    .foregroundStyle(theme.neutral500)
                                    .lineLimit(1)
                            }
                        }
                    }

                    Text("\(sessionsThisWeek) of \(template.sessionsPerWeek) sessions this week")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

// MARK: - Template gallery card ("Start a program")

struct ProgramTemplateCard: View {
    @Environment(\.gsTheme) private var theme
    let template: ProgramTemplate

    var body: some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 4) {
                Text("PROGRAM")
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral700)
                Text(template.name)
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text(template.summary)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
                    .lineLimit(2)
                Text("\(template.weeks.count) weeks · \(template.sessionsPerWeek) sessions/wk")
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
    }
}

// MARK: - ProgramDetailView (enrolled)

struct ProgramDetailView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var enrollment: ProgramEnrollment
    let focusExercises: [Exercise]
    let sessionsThisWeek: Int
    /// Parent reload hook — fired after any mutation (repeat week,
    /// re-baseline, end) so the tab's card reflects the new state.
    let onChanged: () -> Void

    @State private var busy = false
    @State private var errorText: String?
    @State private var confirmAbandon = false
    /// Completion summary: current best est-1RM per focus lift, fetched on
    /// appear when the program is complete (baseline vs now).
    @State private var currentEst: [UUID: Decimal] = [:]

    #if DEBUG
    /// Catalog seam — skips the live current-est fetch (DiscoverView idiom).
    var catalogSkipLoad = false
    #endif

    init(enrollment: ProgramEnrollment, focusExercises: [Exercise],
         sessionsThisWeek: Int, onChanged: @escaping () -> Void) {
        _enrollment = State(initialValue: enrollment)
        self.focusExercises = focusExercises
        self.sessionsThisWeek = sessionsThisWeek
        self.onChanged = onChanged
    }

    private var template: ProgramTemplate? { enrollment.template }
    private var week: Int {
        ProgramMath.currentWeek(startedOn: enrollment.startedOn, weeks: enrollment.weeks)
    }
    private var complete: Bool {
        ProgramMath.isComplete(startedOn: enrollment.startedOn, weeks: enrollment.weeks)
    }
    private var isPercentBased: Bool {
        template?.weeks.contains { $0.percentOfBaseline != nil } ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let template {
                    headerSection(template)
                    if complete {
                        completionSection(template)
                    }
                    weekTable(template)
                    if !complete {
                        actionsSection
                    }
                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(13, relativeTo: .subheadline))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                    }
                } else {
                    // A template slug this app version doesn't bundle (older
                    // build than the enrollment) — degrade honestly.
                    GSEmptyState(
                        icon: "flag.checkered",
                        title: "Unknown program",
                        message: "Update the app to see this program's plan."
                    )
                    .padding(.top, 40)
                }
            }
            .padding(.vertical, 16)
        }
        .background(theme.bg)
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadCurrentEstIfComplete() }
        .confirmationDialog("Abandon this program?", isPresented: $confirmAbandon, titleVisibility: .visible) {
            Button("Abandon program", role: .destructive) {
                Task { await end(reason: "abandoned") }
            }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Your history stays — only the plan stops.")
        }
    }

    private func headerSection(_ template: ProgramTemplate) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            if complete {
                Text("Complete")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.accent700)
            } else {
                Text("Week \(week) of \(enrollment.weeks) · \(sessionsThisWeek) of \(template.sessionsPerWeek) sessions this week")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.accent700)
            }
            if let muscle = enrollment.focus.muscleGroup {
                Text("Focus: \(muscle.replacingOccurrences(of: "_", with: " ").capitalized)")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .padding(.horizontal, 16)
    }

    // Baseline vs now, per focus lift — the honest payoff screen.
    private func completionSection(_ template: ProgramTemplate) -> some View {
        GSCard(bordered: false) {
            VStack(alignment: .leading, spacing: 10) {
                Text("RESULTS")
                    .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral700)
                if focusExercises.isEmpty {
                    Text("You finished the block. Nice work — pick the next one when you're ready.")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                } else {
                    ForEach(focusExercises) { exercise in
                        HStack {
                            Text(exercise.name)
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Spacer()
                            Text(resultText(for: exercise))
                                .font(GSFont.body(14, relativeTo: .body))
                                .foregroundStyle(theme.accent700)
                        }
                    }
                }
                Button {
                    Task { await end(reason: "completed") }
                } label: {
                    Text("Finish program")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 12))
                .disabled(busy)
                .opacity(busy ? 0.6 : 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func resultText(for exercise: Exercise) -> String {
        let baseline = enrollment.baselineValue(for: exercise.id)
        let now = currentEst[exercise.id]
        let baseText = baseline.map { "\(NSDecimalNumber(decimal: $0).intValue)" } ?? "—"
        let nowText = now.map { "\(NSDecimalNumber(decimal: $0).intValue)" } ?? "—"
        return "\(baseText) → \(nowText) lb est 1RM"
    }

    private func weekTable(_ template: ProgramTemplate) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("The plan")
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(template.weeks.enumerated()), id: \.offset) { index, weekSpec in
                    weekRow(index: index, weekSpec: weekSpec)
                    if index < template.weeks.count - 1 { GSDivider() }
                }
            }
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(.horizontal, 16)
        }
    }

    private func weekRow(index: Int, weekSpec: ProgramWeek) -> some View {
        let isCurrent = !complete && (index + 1) == week
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("Week \(index + 1)")
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(isCurrent ? theme.accent700 : theme.text)
                if weekSpec.isDeload {
                    Text("DELOAD")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.8)
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.accent)
                        .cornerRadius(5)
                }
                if isCurrent {
                    Text("· this week")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.accent700)
                }
                Spacer(minLength: 0)
            }
            if focusExercises.isEmpty {
                Text(ProgramMath.prescriptionText(week: weekSpec, baseline: nil))
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                ForEach(focusExercises) { exercise in
                    Text("\(exercise.name) — \(ProgramMath.prescriptionText(week: weekSpec, baseline: enrollment.baselineValue(for: exercise.id)))")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                }
            }
            if let note = weekSpec.note, weekSpec.percentOfBaseline != nil {
                Text(note)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Same fix as WorkoutSessionView's pending-set row: a low-opacity
        // accent over near-black muddies rather than tints. The week table
        // already sits on `theme.surface` (#16181D), so the current week
        // steps UP one elevation — `neutral300` IS Onyx's surface2 (#1E222A,
        // see GSTheme.onyx's note) — instead of washing color over it.
        .background(isCurrent ? theme.neutral300 : Color.clear)
    }

    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Adjust")
                .padding(.horizontal, 16)
            HStack(spacing: 8) {
                Button("Repeat this week") { Task { await repeatWeek() } }
                    .buttonStyle(GSSecondaryButtonStyle(fontSize: 13, horizontalPadding: 12, verticalPadding: 9))
                if isPercentBased, !focusExercises.isEmpty {
                    Button("Re-baseline") { Task { await reBaseline() } }
                        .buttonStyle(GSSecondaryButtonStyle(fontSize: 13, horizontalPadding: 12, verticalPadding: 9))
                }
            }
            .disabled(busy)
            .opacity(busy ? 0.6 : 1)
            .padding(.horizontal, 16)

            Button("Abandon program") { confirmAbandon = true }
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(.red)
                .padding(.horizontal, 16)
                .padding(.top, 2)
        }
    }

    // MARK: Data

    @MainActor
    private func loadCurrentEstIfComplete() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        guard complete, !focusExercises.isEmpty,
              let userID = await SupabaseService.shared.currentUserID() else { return }
        for exercise in focusExercises {
            if let logs = try? await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200),
               let est = ProgramMath.baseline(fromHistory: logs) {
                currentEst[exercise.id] = est
            }
        }
    }

    @MainActor
    private func refreshEnrollment() async {
        if let updated = try? await ProgramRepository.active() {
            enrollment = updated
        }
    }

    @MainActor
    private func repeatWeek() async {
        busy = true; defer { busy = false }
        do {
            try await ProgramRepository.repeatWeek(enrollment: enrollment)
            await refreshEnrollment()
            errorText = nil
            onChanged()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func reBaseline() async {
        busy = true; defer { busy = false }
        guard let userID = await SupabaseService.shared.currentUserID() else { return }
        var newBaseline: [String: Double] = [:]
        for exercise in focusExercises {
            if let logs = try? await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200),
               let est = ProgramMath.baseline(fromHistory: logs) {
                newBaseline[exercise.id.uuidString.lowercased()] = NSDecimalNumber(decimal: est).doubleValue
            }
        }
        // Never wipe an existing baseline with an empty fetch — no data, no
        // change (the "never a guess" doctrine's inverse).
        guard !newBaseline.isEmpty else {
            errorText = "No qualifying sets found to re-baseline from."
            return
        }
        do {
            try await ProgramRepository.reBaseline(enrollmentID: enrollment.id, baseline: newBaseline)
            await refreshEnrollment()
            errorText = nil
            onChanged()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func end(reason: String) async {
        busy = true; defer { busy = false }
        do {
            try await ProgramRepository.end(enrollmentID: enrollment.id, reason: reason)
            onChanged()
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

// MARK: - ProgramTemplateDetailView (enrollment flow)

struct ProgramTemplateDetailView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    let template: ProgramTemplate
    /// Fired after a successful enroll so the Campaigns tab reloads.
    let onEnrolled: () -> Void

    @State private var allExercises: [Exercise] = []
    @State private var selectedMain: Exercise?
    @State private var selectedAccessory: Exercise?
    @State private var selectedMuscle: String?
    /// Auto-derived est-1RM per selected lift (from real history).
    @State private var derivedBaseline: [UUID: Decimal] = [:]
    /// Manual "one real set" fallback per lift when no history exists.
    @State private var manualWeight: [UUID: String] = [:]
    @State private var manualReps: [UUID: String] = [:]
    @State private var pickerTarget: PickerTarget?
    @State private var busy = false
    @State private var errorText: String?

    #if DEBUG
    var catalogSkipLoad = false
    #endif

    private enum PickerTarget: Identifiable {
        case main, accessory
        var id: Int { self == .main ? 0 : 1 }
    }

    init(template: ProgramTemplate, onEnrolled: @escaping () -> Void) {
        self.template = template
        self.onEnrolled = onEnrolled
    }

    private var selectedExercises: [Exercise] {
        [selectedMain, template.focusRule == .liftPlusAccessory ? selectedAccessory : nil]
            .compactMap { $0 }
    }
    private var isPercentBased: Bool {
        template.weeks.contains { $0.percentOfBaseline != nil }
    }
    private var muscles: [String] {
        Array(Set(allExercises.map(\.primaryMuscle))).sorted()
    }

    /// Effective baseline for a lift: derived from history, else the manual
    /// set run through Epley. Never a guess — nil until real numbers exist.
    private func baseline(for exercise: Exercise) -> Decimal? {
        if let derived = derivedBaseline[exercise.id] { return derived }
        guard let w = Double(manualWeight[exercise.id] ?? ""), w > 0,
              let r = Int(manualReps[exercise.id] ?? ""), r > 0 else { return nil }
        return StatMath.estimatedOneRepMax(weight: Decimal(w), reps: r)
    }

    private var canStart: Bool {
        switch template.focusRule {
        case .muscleGroup:
            return selectedMuscle != nil
        case .singleBarbellLift:
            guard let main = selectedMain else { return false }
            return !isPercentBased || baseline(for: main) != nil
        case .liftPlusAccessory:
            guard let main = selectedMain, let accessory = selectedAccessory,
                  main.id != accessory.id else { return false }
            return !isPercentBased
                || (baseline(for: main) != nil && baseline(for: accessory) != nil)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                aboutSection
                planSection
                focusSection
                if isPercentBased, !selectedExercises.isEmpty {
                    baselineSection
                }
                startSection
            }
            .padding(.vertical, 16)
        }
        .background(theme.bg)
        // "Program", not template.name — the in-content header already
        // carries the name; the doubled title read as a stutter in the
        // catalog capture.
        .navigationTitle("Program")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadExercises() }
        .sheet(item: $pickerTarget) { target in
            ExercisePickSheet(
                exercises: pickerCandidates(for: target),
                onPick: { exercise in
                    assign(exercise, to: target)
                    pickerTarget = nil
                }
            )
        }
    }

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(template.name)
                .font(GSFont.heading(22, relativeTo: .title2))
                .foregroundStyle(theme.text)
            Text(template.summary)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.neutral500)
            Text("\(template.weeks.count) weeks · \(template.sessionsPerWeek) sessions/wk")
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(theme.accent700)
        }
        .padding(.horizontal, 16)
    }

    // The scheme in % form — the whole plan before any commitment.
    private var planSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("The plan")
                .padding(.horizontal, 16)
            VStack(spacing: 0) {
                ForEach(Array(template.weeks.enumerated()), id: \.offset) { index, weekSpec in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("Week \(index + 1)")
                                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.text)
                            if weekSpec.isDeload {
                                Text("DELOAD")
                                    .font(GSFont.bold(9, relativeTo: .caption2))
                                    .tracking(0.8)
                                    .foregroundStyle(theme.bg)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(theme.accent)
                                    .cornerRadius(5)
                            }
                            Spacer(minLength: 0)
                            // Scheme only — the note renders on its own line
                            // below (screenshot review: prescriptionText
                            // embeds the note for nil-percent weeks, which
                            // doubled Week 8's test-week copy here).
                            Text(schemeText(weekSpec))
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                        }
                        if let note = weekSpec.note {
                            Text(note)
                                .font(GSFont.body(12, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    if index < template.weeks.count - 1 { GSDivider() }
                }
            }
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private var focusSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Focus")
                .padding(.horizontal, 16)
            switch template.focusRule {
            case .singleBarbellLift:
                exercisePickRow(label: "Lift", selection: selectedMain) { pickerTarget = .main }
            case .liftPlusAccessory:
                exercisePickRow(label: "Main lift", selection: selectedMain) { pickerTarget = .main }
                exercisePickRow(label: "Accessory", selection: selectedAccessory) { pickerTarget = .accessory }
            case .muscleGroup:
                musclePicker
            }
        }
    }

    private func exercisePickRow(label: String, selection: Exercise?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.neutral500)
                Spacer()
                Text(selection?.name ?? "Choose…")
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(selection == nil ? theme.accent700 : theme.text)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var musclePicker: some View {
        // Capsule grid of muscle groups — the ExercisesListView chip idiom.
        FlowChips(options: muscles, selected: selectedMuscle) { muscle in
            selectedMuscle = (selectedMuscle == muscle) ? nil : muscle
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var baselineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            GSSectionHeader("Baseline")
                .padding(.horizontal, 16)
            ForEach(selectedExercises) { exercise in
                baselineRow(for: exercise)
            }
            Text("Weekly targets are the plan's percent of this number, rounded to 5 lb. It's frozen when you start — re-baseline any time from the program screen.")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .padding(.horizontal, 16)
        }
    }

    @ViewBuilder
    private func baselineRow(for exercise: Exercise) -> some View {
        if let derived = derivedBaseline[exercise.id] {
            HStack {
                Text(exercise.name)
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("est 1RM \(NSDecimalNumber(decimal: derived).intValue) lb · from your history")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.accent700)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(.horizontal, 16)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Text("\(exercise.name) — no history yet. Enter one recent set:")
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                HStack(spacing: 8) {
                    TextField("Weight (lb)", text: manualBinding($manualWeight, exercise.id))
                        .keyboardType(.decimalPad)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(theme.bg)
                        .cornerRadius(10)
                    Text("×")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                    TextField("Reps", text: manualBinding($manualReps, exercise.id))
                        .keyboardType(.numberPad)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(theme.bg)
                        .cornerRadius(10)
                    if let est = baseline(for: exercise) {
                        Text("→ est \(NSDecimalNumber(decimal: est).intValue) lb")
                            .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.accent700)
                    }
                }
            }
            .padding(14)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(.horizontal, 16)
        }
    }

    private func manualBinding(_ dict: Binding<[UUID: String]>, _ key: UUID) -> Binding<String> {
        Binding(
            get: { dict.wrappedValue[key] ?? "" },
            set: { dict.wrappedValue[key] = $0 }
        )
    }

    private var startSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await start() }
            } label: {
                Text("Start program")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 13))
            .disabled(!canStart || busy)
            .opacity((!canStart || busy) ? 0.6 : 1)

            if let errorText {
                Text(errorText)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 16)
    }

    private func schemeText(_ week: ProgramWeek) -> String {
        guard let percent = week.percentOfBaseline else { return "\(week.sets)×\(week.reps)" }
        return "\(week.sets)×\(week.reps) @ \(ProgramMath.trimmedPercent(percent))%"
    }

    // MARK: Picker plumbing

    private func pickerCandidates(for target: PickerTarget) -> [Exercise] {
        switch template.focusRule {
        case .singleBarbellLift:
            return allExercises.filter { $0.equipment.lowercased() == "barbell" }
        case .liftPlusAccessory:
            // Main: barbell; accessory: anything (the user knows their gym).
            return target == .main
                ? allExercises.filter { $0.equipment.lowercased() == "barbell" }
                : allExercises
        case .muscleGroup:
            return allExercises
        }
    }

    private func assign(_ exercise: Exercise, to target: PickerTarget) {
        switch target {
        case .main: selectedMain = exercise
        case .accessory: selectedAccessory = exercise
        }
        Task { await deriveBaseline(for: exercise) }
    }

    // MARK: Data

    @MainActor
    private func loadExercises() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        guard allExercises.isEmpty else { return }
        allExercises = (try? await ExerciseRepository.fetchAll()) ?? []
    }

    @MainActor
    private func deriveBaseline(for exercise: Exercise) async {
        guard isPercentBased,
              let userID = await SupabaseService.shared.currentUserID() else { return }
        if let logs = try? await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200),
           let est = ProgramMath.baseline(fromHistory: logs) {
            derivedBaseline[exercise.id] = est
        }
    }

    @MainActor
    private func start() async {
        busy = true; defer { busy = false }
        var focus = ProgramFocus()
        var baselineDict: [String: Double] = [:]
        switch template.focusRule {
        case .muscleGroup:
            focus.muscleGroup = selectedMuscle
        case .singleBarbellLift, .liftPlusAccessory:
            focus.exerciseIDs = selectedExercises.map(\.id)
            for exercise in selectedExercises {
                if let est = baseline(for: exercise) {
                    baselineDict[exercise.id.uuidString.lowercased()] = NSDecimalNumber(decimal: est).doubleValue
                }
            }
        }
        do {
            _ = try await ProgramRepository.enroll(template: template, focus: focus, baseline: baselineDict)
            errorText = nil
            onEnrolled()
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}

// MARK: - ExercisePickSheet (minimal searchable list)

/// Internal (not private): `WorkoutSessionView`'s freeform exercise picking
/// reuses this exact sheet rather than shipping a second search list.
struct ExercisePickSheet: View {
    @Environment(\.gsTheme) private var theme
    let exercises: [Exercise]
    let onPick: (Exercise) -> Void

    @State private var filter = ""

    private var filtered: [Exercise] {
        filter.isEmpty ? exercises
            : exercises.filter { $0.name.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
                TextField("Search", text: $filter)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(16)

            List(filtered) { exercise in
                Button {
                    onPick(exercise)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(exercise.name)
                            .font(GSFont.bodyMedium(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text("\(exercise.primaryMuscle.replacingOccurrences(of: "_", with: " ").capitalized) · \(exercise.equipment.capitalized)")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    }
                }
                .buttonStyle(.plain)
                .listRowBackground(theme.surface)
                .listRowSeparatorTint(theme.divider)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(theme.bg)
    }
}

// MARK: - FlowChips (wrapping capsule picker for muscle groups)

private struct FlowChips: View {
    @Environment(\.gsTheme) private var theme
    let options: [String]
    let selected: String?
    let onTap: (String) -> Void

    var body: some View {
        // Simple wrapping layout via LazyVGrid — adaptive columns keep the
        // capsules compact without a custom Layout implementation.
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(options, id: \.self) { option in
                Button {
                    onTap(option)
                } label: {
                    Text(option.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(GSFont.bodyMedium(12, relativeTo: .caption))
                        .foregroundStyle(selected == option ? theme.bg : theme.neutral700)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(selected == option ? theme.accent : theme.neutral300)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
