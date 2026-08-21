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
    /// The trainer's OWN (non-prescribed) routines — the "copy one of
    /// yours" prescribe source.
    @State private var myRoutines: [Routine] = []
    @State private var sessionsThisWeek: Int?
    @State private var latestBodyWeight: Decimal?
    // Body health statistics (owner 2026-08-21): the client's stated
    // body context via the scope-gated RPC - nil rows read as unshared.
    @State private var bodyContext: TrainingProfileRepository.ClientBodyContext?
    @State private var notes: [TrainerNote] = []
    @State private var noteDraft = ""
    @State private var prescribeSheet = false
    @State private var editingPrescription: Routine?
    @State private var errorText: String?
    // Calendar (trainer arm T4 — owner 2026-08-16: "How do I schedule
    // workouts…from here?"). Reads + writes both ride the calendar scope.
    @State private var upcomingSessions: [WorkoutSession] = []
    // Client ledger + records (owner 2026-08-16: "There's no calendar, or
    // ledger of exercises… see statistics"). Same machinery as the
    // lifter's own Stats page, scope-gated.
    @State private var clientLedger: [ClientLedgerEntry] = []
    @State private var clientAttempted: [Exercise] = []
    @State private var showScheduleSheet = false
    @State private var scheduleDate = Date().addingTimeInterval(3600)
    @State private var scheduleRoutineID: UUID?
    @State private var booking = false

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
                calendarSection
                ledgerSection
                recordsSection
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
        .sheet(isPresented: $showScheduleSheet) { scheduleSheet }
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
                            ? bodyWeightTileText
                            : "not shared")
            if relationship.scopes.bodyWeight, let bf = bodyContext?.bodyFatPercent {
                overviewTile("BODYFAT", value: String(format: "%.0f%%", bf))
            }
            if relationship.scopes.bodyWeight, let bmi = bodyContext?.bmi {
                overviewTile("BMI", value: String(format: "%.1f", bmi))
            }
        }
    }

    /// Logged body-weight entry first (fresher), stated profile weight
    /// as the fallback.
    private var bodyWeightTileText: String {
        if let w = latestBodyWeight {
            return Units.format(pounds: w, unit: ThemeStore.shared.weightUnit, rounded: false)
        }
        if let stated = bodyContext?.bodyweightLbs {
            return Units.format(pounds: Decimal(stated), unit: ThemeStore.shared.weightUnit, rounded: false)
        }
        return "—"
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
            // Prescribe menu (owner 2026-08-16: "I can't prescribe pre
            // generated workouts"): build fresh, or duplicate one of the
            // trainer's own routines as a prescription (the copy lands on
            // the client, attributed — the T2 namespace, never a shared
            // reference). PR history left this screen on the same report;
            // it returns as small text in the builder where weight gets set.
            Menu {
                Button {
                    prescribeSheet = true
                } label: {
                    Label("Build a new routine", systemImage: "hammer")
                }
                if !myRoutines.isEmpty {
                    Menu {
                        ForEach(myRoutines) { routine in
                            Button(routine.name) {
                                Task { await prescribeCopy(of: routine) }
                            }
                        }
                    } label: {
                        Label("Copy one of your routines", systemImage: "doc.on.doc")
                    }
                }
            } label: {
                Text("+ Prescribe a routine")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        }
    }

    // MARK: - Calendar (T4 — scope-gated both ways)

    private var calendarSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Calendar")
            if !relationship.scopes.calendar {
                Text("Calendar isn't shared — the client controls this from their Coaching settings.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                if upcomingSessions.isEmpty {
                    Text("Nothing on the books.")
                        .font(GSFont.body(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.neutral500)
                } else {
                    ForEach(upcomingSessions) { session in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(session.scheduledFor?.formatted(
                                    .dateTime.weekday(.abbreviated).month(.abbreviated).day()
                                        .hour().minute()) ?? "Scheduled")
                                    .font(GSFont.bold(13, relativeTo: .subheadline))
                                    .foregroundStyle(theme.text)
                                Text(session.routineID.flatMap { id in
                                    routines.first { $0.id == id }?.name
                                } ?? "Open session")
                                    .font(GSFont.body(11, relativeTo: .caption))
                                    .foregroundStyle(theme.neutral500)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .gs3DCard(cornerRadius: GSMetrics.radiusSm)
                    }
                }
                Button {
                    scheduleRoutineID = routines.first { $0.prescribedBy == selfID }?.id
                    showScheduleSheet = true
                } label: {
                    Text("+ Schedule a session")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
            }
        }
    }

    /// Minimal booking form: when + which routine. The insert rides the
    /// "trainer books for client" policy — organizer is the CLIENT, so it
    /// lands on their Home calendar like any lift they booked themselves.
    private var scheduleSheet: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                DatePicker("When", selection: $scheduleDate, in: Date()...)
                    .tint(theme.accent)
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.text)

                VStack(alignment: .leading, spacing: 6) {
                    Text("ROUTINE")
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                    Menu {
                        Button("Open session — no routine") { scheduleRoutineID = nil }
                        ForEach(routines) { routine in
                            Button(routine.name) { scheduleRoutineID = routine.id }
                        }
                    } label: {
                        HStack {
                            Text(scheduleRoutineID.flatMap { id in
                                routines.first { $0.id == id }?.name
                            } ?? "Open session — no routine")
                                .font(GSFont.bodyMedium(14, relativeTo: .body))
                                .foregroundStyle(theme.text)
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.neutral500)
                        }
                        .padding(12)
                        .background(theme.surface)
                        .cornerRadius(GSMetrics.radiusSm)
                    }
                }

                Button {
                    Task { await book() }
                } label: {
                    Text(booking ? "Booking…" : "Book it")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
                .disabled(booking)

                Spacer()
            }
            .padding(16)
            .background(theme.bg)
            .navigationTitle("Schedule for \(clientName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { showScheduleSheet = false }
                        .tint(theme.accent)
                }
            }
        }
    }

    @MainActor
    private func book() async {
        guard let clientID else { return }
        booking = true
        defer { booking = false }
        do {
            _ = try await SessionRepository.scheduleForClient(
                clientID: clientID, routineID: scheduleRoutineID, scheduledFor: scheduleDate)
            showScheduleSheet = false
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    // MARK: - Ledger + records (owner 2026-08-16 — the client's training,
    // in the same shapes their own Stats page uses)

    struct ClientLedgerEntry: Identifiable {
        let session: WorkoutSession
        let routineName: String?
        let sets: Int
        let minutes: Int?
        var id: UUID { session.id }
    }

    private var ledgerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Ledger")
            if !relationship.scopes.history {
                Text("Workout history isn't shared — the client controls this from their Coaching settings.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else if clientLedger.isEmpty {
                Text("No workouts in the last 90 days.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else {
                ForEach(clientLedger) { entry in
                    NavigationLink {
                        CompletedSessionView(session: entry.session)
                    } label: {
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(entry.routineName ?? "Freeform workout")
                                    .font(GSFont.bold(14, relativeTo: .headline))
                                    .foregroundStyle(theme.text)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text((entry.session.startedAt ?? entry.session.scheduledFor ?? .now)
                                    .formatted(.dateTime.month(.abbreviated).day()))
                                    .font(GSFont.body(11, relativeTo: .caption))
                                    .foregroundStyle(theme.neutral500)
                            }
                            Text(entry.minutes.map { "\(entry.sets) sets · ~\($0) min" }
                                 ?? "\(entry.sets) sets")
                                .font(GSFont.body(11, relativeTo: .caption))
                                .foregroundStyle(theme.neutral500)
                                .monospacedDigit()
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
                }
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Records")
            if !relationship.scopes.stats {
                Text("Stats aren't shared — the client controls this from their Coaching settings.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            } else if let clientID {
                NavigationLink {
                    AttemptedExercisesView(exercises: clientAttempted, subjectID: clientID)
                        .background(theme.bg)
                        .navigationTitle("\(clientName) · records")
                        .navigationBarTitleDisplayMode(.inline)
                } label: {
                    HStack {
                        Text(clientAttempted.isEmpty
                             ? "No lifts attempted yet"
                             : "\(clientAttempted.count) lifts — trends and history per exercise")
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.text)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(theme.neutral500)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusSm))
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
        // Body health statistics (owner 2026-08-21): scope-gated RPC,
        // empty when body_weight is off or nothing is stated.
        if relationship.scopes.bodyWeight {
            bodyContext = await TrainingProfileRepository.clientBodyContext(clientID: clientID)
        }
        // Routines: readable via the trainer-read policy; client-authored
        // rows arrive read-only (the UI disables them).
        routines = (try? await RoutineRepository.fetchAll(ownerID: clientID)) ?? []
        if let selfID {
            myRoutines = ((try? await RoutineRepository.fetchAll(ownerID: selfID)) ?? [])
                .filter { $0.prescribedBy == nil }
        }
        if relationship.scopes.history,
           let since = Calendar.current.date(byAdding: .day, value: -90, to: .now),
           let logs = try? await SessionRepository.recentSetLogs(userID: clientID, since: since) {
            // One 90-day fetch feeds both the weekly count and the ledger.
            let valid = logs.filter { !$0.isPenalty }
            if let weekStart = Calendar.current.date(byAdding: .day, value: -7, to: .now) {
                sessionsThisWeek = Set(valid.filter { $0.loggedAt >= weekStart }.map(\.sessionID)).count
            }
            let bySession = Dictionary(grouping: valid, by: \.sessionID)
            let sessions = (try? await SessionRepository.byIDs(Array(bySession.keys))) ?? []
            let names = routines.reduce(into: [UUID: String]()) { $0[$1.id] = $1.name }
            clientLedger = sessions
                .map { session -> ClientLedgerEntry in
                    let sessionLogs = bySession[session.id] ?? []
                    let times = sessionLogs.map(\.loggedAt)
                    let minutes: Int?
                    if let first = times.min(), let last = times.max(), last > first {
                        minutes = Int(last.timeIntervalSince(first) / 60)
                    } else {
                        minutes = nil
                    }
                    return ClientLedgerEntry(
                        session: session,
                        routineName: session.routineID.flatMap { names[$0] },
                        sets: sessionLogs.count,
                        minutes: minutes)
                }
                .sorted { ($0.session.startedAt ?? .distantPast) > ($1.session.startedAt ?? .distantPast) }
                .prefix(10)
                .map { $0 }
        }
        if relationship.scopes.stats {
            // Attempted lifts (the records list): distinct exercises across
            // the client's PR ledger, most recent first.
            let prs = (try? await PersonalRecordRepository.recent(userID: clientID, limit: 400)) ?? []
            if !prs.isEmpty, let catalog = try? await ExerciseRepository.fetchAll() {
                let byID = Dictionary(uniqueKeysWithValues: catalog.map { ($0.id, $0) })
                var seen = Set<UUID>()
                var ordered: [Exercise] = []
                for pr in prs where !seen.contains(pr.exerciseID) {
                    seen.insert(pr.exerciseID)
                    if let ex = byID[pr.exerciseID] { ordered.append(ex) }
                }
                clientAttempted = ordered
            }
        }
        if relationship.scopes.bodyWeight {
            latestBodyWeight = (try? await BodyWeightLogRepository.recent(userID: clientID))?.first?.weight
        }
        if relationship.scopes.calendar {
            upcomingSessions = (try? await SessionRepository.upcomingScheduled(organizerID: clientID)) ?? []
        }
        await loadNotes()
    }

    /// Duplicate-then-prescribe: a full copy (structure fields included)
    /// with owner = client, prescribed_by = self — the trainer's original
    /// stays untouched and unlinked.
    @MainActor
    private func prescribeCopy(of source: Routine) async {
        guard let clientID, let selfID else { return }
        do {
            guard let (_, exercises) = try await RoutineRepository.fetch(id: source.id) else { return }
            let routineID = UUID()
            let now = Date()
            let copy = Routine(
                id: routineID, ownerID: clientID, name: source.name,
                description: source.description, visibility: "private",
                createdAt: now, updatedAt: now, prescribedBy: selfID)
            let copied = exercises.sorted { $0.position < $1.position }.enumerated().map { index, ex in
                RoutineExercise(
                    id: UUID(), routineID: routineID, exerciseID: ex.exerciseID,
                    position: index + 1, targetSets: ex.targetSets,
                    targetReps: ex.targetReps, targetWeight: ex.targetWeight,
                    restSeconds: ex.restSeconds, notes: ex.notes,
                    setType: ex.setType, supersetGroup: ex.supersetGroup,
                    dropSteps: ex.dropSteps, dropPercent: ex.dropPercent,
                    targetFailure: ex.targetFailure,
                    targetRepsLow: ex.targetRepsLow, targetRepsHigh: ex.targetRepsHigh,
                    cardioZone: ex.cardioZone, cardioMinutes: ex.cardioMinutes)
            }
            try await RoutineRepository.save(copy, exercises: copied)
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
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
