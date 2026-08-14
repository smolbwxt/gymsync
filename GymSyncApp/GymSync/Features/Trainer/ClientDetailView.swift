import SwiftUI

// MARK: - ClientDetailView (trainer arm T3)
//
// The client command center: assess, manage, prescribe. Every read here
// rides the SCOPE-GATED RLS policies (20260814000008) — an ungrated
// scope's query simply returns nothing, and the section says so plainly
// instead of pretending the client has no data. Prescriptions write
// through the prescribed_by namespace: this trainer can create and edit
// their OWN prescriptions and never touch a client-authored routine.
struct ClientDetailView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    let relationship: TrainerClient
    let clientProfile: Profile?

    @State private var routines: [Routine] = []
    @State private var recentPRs: [PersonalRecord] = []
    @State private var sessionsThisWeek: Int?
    @State private var latestBodyWeight: Decimal?
    @State private var notes: [TrainerNote] = []
    @State private var noteDraft = ""
    @State private var prescribeSheet = false
    @State private var editingPrescription: Routine?
    @State private var errorText: String?

    private var clientID: UUID? { relationship.clientID }
    private var selfID: UUID? { appState.currentProfile?.id }
    private var clientName: String {
        clientProfile.map { $0.displayName?.isEmpty == false ? $0.displayName! : $0.username }
            ?? "Client"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                overviewStrip
                routinesSection
                statsSection
                notesSection
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .contentMargins(.bottom, 110, for: .scrollContent)
        .navigationTitle(clientName)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $prescribeSheet) {
            if let clientID, let selfID {
                NavigationStack {
                    RoutineBuilderView(editing: nil,
                                       prescribing: (clientID: clientID, trainerID: selfID)) { _ in
                        prescribeSheet = false
                        Task { await load() }
                    }
                }
            }
        }
        .sheet(item: $editingPrescription) { routine in
            if let clientID, let selfID {
                NavigationStack {
                    RoutineBuilderView(editing: routine,
                                       prescribing: (clientID: clientID, trainerID: selfID)) { _ in
                        editingPrescription = nil
                        Task { await load() }
                    }
                }
            }
        }
    }

    // MARK: - Overview

    private var overviewStrip: some View {
        HStack(spacing: 8) {
            overviewTile("THIS WEEK",
                         value: relationship.scopes.history
                            ? sessionsThisWeek.map { "\($0) lifts" } ?? "—"
                            : "not shared")
            overviewTile("BODY WEIGHT",
                         value: relationship.scopes.bodyWeight
                            ? latestBodyWeight.map {
                                Units.format(pounds: $0, unit: ThemeStore.shared.weightUnit, rounded: false)
                              } ?? "—"
                            : "not shared")
        }
    }

    private func overviewTile(_ kicker: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(kicker)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral500)
            Text(value)
                .font(GSFont.heading(16, relativeTo: .body))
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    // MARK: - Routines (prescribe)

    private var routinesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Routines")
            ForEach(routines) { routine in
                let mine = routine.prescribedBy == selfID
                Button {
                    if mine { editingPrescription = routine }
                } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(routine.name)
                                .font(GSFont.bold(14, relativeTo: .headline))
                                .foregroundStyle(theme.text)
                            Text(mine ? "Your prescription — tap to edit"
                                 : (routine.prescribedBy != nil ? "Prescribed by another trainer"
                                    : "Client's own routine"))
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                        }
                        Spacer()
                        if routine.prescribedBy != nil {
                            GSTag(text: "Prescribed", style: mine ? .accent : .neutral)
                        }
                        if mine {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                        }
                    }
                    .padding(12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
                .disabled(!mine)
            }
            Button {
                prescribeSheet = true
            } label: {
                Text("+ Prescribe a routine")
            }
            .buttonStyle(GSSecondaryButtonStyle())
        }
    }

    // MARK: - Stats (scope-gated)

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Recent records")
            if !relationship.scopes.stats {
                Text("Stats aren't shared — the client controls this from their Coaching settings.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else if recentPRs.isEmpty {
                Text("No records yet.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                ForEach(recentPRs.prefix(5)) { pr in
                    HStack {
                        Text(pr.weight > 0
                             ? "\(Units.format(pounds: pr.weight, unit: ThemeStore.shared.weightUnit, rounded: false)) × \(pr.reps)"
                             : "\(pr.reps) reps")
                            .font(GSFont.bold(14, relativeTo: .headline).monospacedDigit())
                            .foregroundStyle(theme.text)
                        Spacer()
                        Text(pr.achievedAt.formatted(date: .abbreviated, time: .omitted))
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .gs3DCard(cornerRadius: GSMetrics.radiusSm)
                }
            }
        }
    }

    // MARK: - Notes (T5 — trainer-private)

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Notes · private to you")
            HStack(spacing: 8) {
                TextField("Add a note…", text: $noteDraft, axis: .vertical)
                    .font(GSFont.body(14, relativeTo: .body))
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                        .strokeBorder(theme.divider, lineWidth: 1))
                Button {
                    Task { await addNote() }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(theme.bg)
                        .frame(width: 36, height: 32)
                }
                .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 10, lipHeight: 4))
                .disabled(noteDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            ForEach(notes) { note in
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.body)
                        .font(GSFont.body(13.5, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Text(note.createdAt.formatted(date: .abbreviated, time: .shortened))
                            .font(GSFont.body(10.5, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                        Spacer()
                        Button("Delete") {
                            Task {
                                try? await TrainerNoteRepository.delete(id: note.id)
                                await loadNotes()
                            }
                        }
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    }
                }
                .padding(12)
                .gs3DCard(cornerRadius: GSMetrics.radiusSm)
            }
        }
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        guard let clientID else { return }
        // Routines: readable via the trainer-read policy; client-authored
        // rows arrive read-only (the UI disables them).
        routines = (try? await RoutineRepository.fetchAll(ownerID: clientID)) ?? []
        if relationship.scopes.stats {
            recentPRs = (try? await PersonalRecordRepository.recent(userID: clientID, limit: 10)) ?? []
        }
        if relationship.scopes.history,
           let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now),
           let logs = try? await SessionRepository.recentSetLogs(userID: clientID, since: weekStart) {
            sessionsThisWeek = Set(logs.map(\.sessionID)).count
        }
        if relationship.scopes.bodyWeight {
            latestBodyWeight = (try? await BodyWeightLogRepository.recent(userID: clientID))?.first?.weight
        }
        await loadNotes()
    }

    @MainActor
    private func loadNotes() async {
        guard let clientID else { return }
        notes = (try? await TrainerNoteRepository.notes(clientID: clientID)) ?? []
    }

    @MainActor
    private func addNote() async {
        guard let clientID else { return }
        let body = noteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        do {
            try await TrainerNoteRepository.add(clientID: clientID, body: body)
            noteDraft = ""
            await loadNotes()
            errorText = nil
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
