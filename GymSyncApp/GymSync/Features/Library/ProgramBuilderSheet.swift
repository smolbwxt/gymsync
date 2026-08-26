import SwiftUI

// MARK: - ProgramBuilderSheet
//
// Program builder for yourself (field docket #10, owner "go ahead"
// 2026-08-22): author a multi-week block from your OWN routines and
// adopt it. Deliberately thin - it writes exactly the rows Coach's
// generated blocks write (program_templates + week summaries +
// enrollment + plan-queue card), so the shelf, the Plan queue, and the
// week-over-week machinery treat a hand-built program identically to a
// generated one. The routines themselves already exist; this is
// identity + rhythm, not routine authoring.
struct ProgramBuilderSheet: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    /// Called after a successful save so the Programs screen refreshes.
    var onSaved: () -> Void = {}

    @State private var name = ""
    @State private var routines: [Routine] = []
    /// Selection order IS the weekly rotation order.
    @State private var selectedRoutineIDs: [UUID] = []
    @State private var durationWeeks = 8
    @State private var includeDeload = true
    @State private var adoptNow = true
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    TextField("Program name", text: $name)
                        .font(GSFont.bold(17, relativeTo: .headline))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                            .strokeBorder(theme.divider, lineWidth: 1))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("WEEKLY ROTATION")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral500)
                        Text("Tap routines in the order you'll run them each week.")
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                        ForEach(routines) { routine in
                            routineRow(routine)
                        }
                        if routines.isEmpty {
                            Text("No routines yet — build one in the Library first; the program builder arranges routines you already have.")
                                .font(GSFont.body(13, relativeTo: .subheadline))
                                .foregroundStyle(theme.neutral500)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("LENGTH · WEEKS")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                            .tracking(1.1)
                            .foregroundStyle(theme.neutral500)
                        HStack(spacing: 6) {
                            ForEach([4, 8, 12], id: \.self) { weeks in
                                let isOn = durationWeeks == weeks
                                Button {
                                    durationWeeks = weeks
                                } label: {
                                    Text("\(weeks)")
                                        .font(GSFont.bold(14, relativeTo: .subheadline))
                                        .foregroundStyle(isOn ? theme.bg : theme.neutral700)
                                        .padding(.horizontal, 18)
                                        .padding(.vertical, 9)
                                        .background(isOn ? theme.accent : theme.surface)
                                        .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    toggleRow(isOn: $includeDeload,
                              title: "Deload at the ¾ mark",
                              detail: "Same law Coach's blocks follow — one half-volume week before the final push. Four-week programs skip it.")

                    toggleRow(isOn: $adoptNow,
                              title: "Start this program now",
                              detail: "Enrolls you immediately (replacing any active block) and adds it to your Plan queue. Off = it just lands on your shelf.")

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await save() }
                    } label: {
                        Text(busy ? "Saving…" : (adoptNow ? "Save & start" : "Save to shelf"))
                    }
                    .buttonStyle(GSPrimaryButtonStyle())
                    .disabled(busy || name.trimmingCharacters(in: .whitespaces).isEmpty
                              || selectedRoutineIDs.isEmpty)
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.bg)
            .navigationTitle("Build a program")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task {
                guard let userID = appState.currentProfile?.id else { return }
                routines = ((try? await RoutineRepository.fetchAll(ownerID: userID)) ?? [])
            }
        }
    }

    private func routineRow(_ routine: Routine) -> some View {
        let order = selectedRoutineIDs.firstIndex(of: routine.id)
        return Button {
            if let order {
                selectedRoutineIDs.remove(at: order)
            } else {
                selectedRoutineIDs.append(routine.id)
            }
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(order != nil ? theme.accent : theme.surface)
                        .frame(width: 26, height: 26)
                    if let order {
                        Text("\(order + 1)")
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.bg)
                    }
                }
                Text(routine.name)
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
    }

    private func toggleRow(isOn: Binding<Bool>, title: String, detail: String) -> some View {
        Button {
            isOn.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(isOn.wrappedValue ? theme.accent : theme.neutral500)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text(detail)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Week summaries mirroring the generator's law: volume-driven weeks
    /// (no percent anchor - suggestions come from history via
    /// WorkingWeight's later rungs), deload at the ¾ mark when toggled,
    /// never on 4-week programs.
    private func weekPlan() -> [ProgramWeek] {
        let deloadIndex = (includeDeload && durationWeeks > 4)
            ? Int((Double(durationWeeks) * 0.75).rounded()) - 1 : -1
        return (0..<durationWeeks).map { i in
            ProgramWeek(percentOfBaseline: nil, sets: 3, reps: 8,
                        isDeload: i == deloadIndex,
                        note: i == deloadIndex
                            ? "Deload — half the sets, keep the bar moving"
                            : "Week \(i + 1) — run the rotation")
        }
    }

    private func save() async {
        guard let userID = appState.currentProfile?.id else { return }
        busy = true
        defer { busy = false }
        let weeks = weekPlan()
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        do {
            let row = try await ProgramTemplateRepository.saveGenerated(
                name: trimmedName,
                summary: "Custom program — \(selectedRoutineIDs.count) routine\(selectedRoutineIDs.count == 1 ? "" : "s") rotating for \(durationWeeks) weeks.",
                focusKind: "custom",
                sessionsPerWeek: selectedRoutineIDs.count,
                durationWeeks: durationWeeks,
                weeks: weeks)
            _ = try? await TrainingPlanRepository.add(templateID: row.id)
            if adoptNow {
                // Same enrollment path as a Coach block: register the
                // template, retire any active block, enroll with
                // history-derived baselines over the rotation's lifts.
                let template = ProgramTemplate(row: row, weeks: weeks)
                ProgramTemplateStore.shared.register([template])
                let exerciseIDs = Array(Set(
                    ((try? await RoutineRepository.exercisesForRoutines(ids: selectedRoutineIDs)) ?? [])
                        .map(\.exerciseID)))
                var baselines: [String: Double] = [:]
                if let since = Calendar.current.date(byAdding: .day, value: -180, to: .now),
                   let logs = try? await SessionRepository.recentSetLogs(userID: userID, since: since) {
                    let byExercise = Dictionary(grouping: logs, by: \.exerciseID)
                    for id in exerciseIDs {
                        // Freeze the baseline from the CURRENT training
                        // era only. A layoff inside this window would
                        // otherwise freeze a pre-layoff max into the
                        // enrollment, and the campaign rung outranks every
                        // other source — so week one would prescribe a
                        // percentage of who they used to be.
                        guard let history = byExercise[id],
                              let best = WorkingWeight.bestQualifyingSet(
                                          in: TrainingHorizon.sinceReturn(history)) else { continue }
                        let oneRM = StatMath.estimatedOneRepMax(weight: best.weight, reps: best.reps)
                        baselines[id.uuidString.lowercased()] = NSDecimalNumber(decimal: oneRM).doubleValue
                    }
                }
                if let active = try? await ProgramRepository.active(), active.endedAt == nil {
                    try? await ProgramRepository.end(enrollmentID: active.id, reason: "abandoned")
                }
                _ = try await ProgramRepository.enroll(
                    template: template,
                    focus: ProgramFocus(exerciseIDs: exerciseIDs),
                    baseline: baselines)
            }
            errorText = nil
            onSaved()
            dismiss()
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription ?? error.localizedDescription
        }
    }
}
