import SwiftUI

// MARK: - CompletedSessionView
//
// Shows a summary of a completed (or abandoned) session:
//   • Header: routine/"Workout", date, duration H:MM, "✏️ EDITED" GSTag when durationWasEdited
//   • Duration row with pencil button → DurationEditSheet
//   • Per-participant stats (same semantics as SessionRecapView: volume excludes penalty+failed,
//     penalty reps shown separately)
//
// Loaded lazily via .task: sets + participants fetched from the live DB on appear.
// Any participant may edit the duration (existing RLS UPDATE policy covers).

struct CompletedSessionView: View {

    // Initial session value passed in from GroupView (may be stale — we reload on appear).
    let session: WorkoutSession

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss)  private var dismiss

    // MARK: - Loaded state

    @State private var liveSession: WorkoutSession
    @State private var sets: [SetLog] = []
    @State private var participants: [(participant: SessionParticipant, profile: Profile)] = []
    @State private var isLoading = true
    @State private var errorText: String?

    // MARK: - Duration edit sheet

    @State private var showEditSheet = false

    init(session: WorkoutSession) {
        self.session = session
        _liveSession = State(initialValue: session)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // ── HEADER ────────────────────────────────────────────────
                headerSection
                    .padding(.bottom, 14)

                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)
                } else {

                    // ── DURATION ROW ──────────────────────────────────────
                    durationRow
                        .padding(.horizontal, 16)
                        .padding(.bottom, 14)

                    GSDivider()
                        .padding(.horizontal, 16)

                    // ── PARTICIPANTS ──────────────────────────────────────
                    if !participants.isEmpty {
                        GSSectionHeader("Results")
                            .padding(.horizontal, 16)
                            .padding(.top, 14)
                            .padding(.bottom, 8)

                        ForEach(Array(stats.enumerated()), id: \.element.profile.id) { index, stat in
                            participantRow(rank: index + 1, stat: stat)

                            if index < stats.count - 1 {
                                Rectangle()
                                    .fill(theme.divider)
                                    .frame(height: 1)
                                    .padding(.horizontal, 16)
                            }
                        }
                    }

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 16)
                            .padding(.top, 8)
                    }
                }

                Spacer(minLength: 32)
            }
        }
        .background(theme.bg)
        .navigationTitle("Session Detail")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .sheet(isPresented: $showEditSheet) {
            DurationEditSheet(session: liveSession) {
                // Reload after a successful edit.
                Task { await load() }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("COMPLETED SESSION")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(dateString)
                .font(.custom("Archivo-Bold", size: 34).monospacedDigit())
                .foregroundStyle(theme.bg)
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(durationString)
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.bg.opacity(0.9))

                if liveSession.durationWasEdited {
                    GSTag(text: "✏️ EDITED", style: .neutral)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    // MARK: - Duration row

    private var durationRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Duration")
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(durationString)
                    .font(GSFont.body(12, relativeTo: .footnote))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            Button {
                showEditSheet = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(8)
                    .background(theme.surface)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.vertical, 10)
    }

    // MARK: - Stats

    private struct ParticipantStats {
        let profile: Profile
        let participant: SessionParticipant
        let setCount: Int
        let volume: Double       // Σ reps×weight, no penalty/failed sets
        let penaltyReps: Int
    }

    private var stats: [ParticipantStats] {
        participants.map { item in
            let mySets   = sets.filter { $0.userID == item.participant.userID }
            let workSets = mySets.filter { !$0.isPenalty }
            let volume   = workSets.reduce(0.0) { acc, log in
                guard !log.isFailed, let r = log.reps, let w = log.weight else { return acc }
                return acc + Double(r) * NSDecimalNumber(decimal: w).doubleValue
            }
            let penaltyReps = mySets.filter(\.isPenalty).compactMap(\.reps).reduce(0, +)
            return ParticipantStats(
                profile:     item.profile,
                participant: item.participant,
                setCount:    workSets.count,
                volume:      volume,
                penaltyReps: penaltyReps
            )
        }
        .sorted { $0.volume > $1.volume }
    }

    // MARK: - Participant row

    private func participantRow(rank: Int, stat: ParticipantStats) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 18, alignment: .leading)

            let initials = String(stat.profile.username.prefix(2)).uppercased()
            ZStack {
                Rectangle()
                    .fill(rank == 1 ? theme.accent : theme.neutral400)
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(stat.profile.username)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)

                HStack(spacing: 6) {
                    Text("\(stat.setCount) sets")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    if stat.volume > 0 {
                        Text("·")
                            .foregroundStyle(theme.neutral500)
                            .font(GSFont.body(11, relativeTo: .caption))
                        Text("\(formatVolume(stat.volume)) lbs")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                    if stat.penaltyReps > 0 {
                        Text("·")
                            .foregroundStyle(theme.neutral500)
                            .font(GSFont.body(11, relativeTo: .caption))
                        Text("\(stat.penaltyReps) penalty reps")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.accent700)
                    }
                }
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private var durationString: String {
        guard let start = liveSession.startedAt, let end = liveSession.completedAt else {
            return "--:--"
        }
        let total = Int(max(0, end.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0
            ? String(format: "%d:%02d", h, m)
            : String(format: "%02d:%02d", m, total % 60)
    }

    private var dateString: String {
        let fmt = DateFormatter()
        fmt.dateStyle = .long
        fmt.timeStyle = .none
        return (liveSession.completedAt ?? liveSession.startedAt).map { fmt.string(from: $0) } ?? ""
    }

    private func formatVolume(_ v: Double) -> String {
        v >= 1_000
            ? String(format: "%.1fk", v / 1_000)
            : String(format: "%.0f", v)
    }

    // MARK: - Data load

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let freshSession = SessionRepository.session(id: liveSession.id)
            async let fetchedSets  = SessionRepository.sessionSets(sessionID: liveSession.id)
            async let fetchedParts = SessionRepository.participants(sessionID: liveSession.id)

            if let s = try await freshSession { liveSession = s }
            sets         = try await fetchedSets
            participants = try await fetchedParts
            errorText    = nil
        } catch {
            errorText = (error as? GymSyncError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - DurationEditSheet

private struct DurationEditSheet: View {
    let session: WorkoutSession
    let onSaved: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme)  private var theme

    @State private var newStartedAt:   Date
    @State private var newCompletedAt: Date
    @State private var reason:         String = ""
    @State private var isSaving        = false
    @State private var errorText: String?

    init(session: WorkoutSession, onSaved: @escaping () -> Void) {
        self.session  = session
        self.onSaved  = onSaved
        _newStartedAt   = State(initialValue: session.startedAt   ?? Date())
        _newCompletedAt = State(initialValue: session.completedAt ?? Date())
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Start time") {
                    DatePicker("Start", selection: $newStartedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(theme.accent)
                }

                Section("End time") {
                    DatePicker("End", selection: $newCompletedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                        .tint(theme.accent)
                }

                Section("Reason (optional)") {
                    TextField("e.g. Clock was wrong", text: $reason)
                        .font(GSFont.body(14, relativeTo: .body))
                }

                if let errorText {
                    Section {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .footnote))
                            .foregroundStyle(.red)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("Edit Duration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(theme.neutral500)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .font(GSFont.bold(16, relativeTo: .body))
                        .foregroundStyle(theme.accent)
                        .disabled(isSaving)
                }
            }
        }
    }

    private func save() async {
        isSaving  = true
        errorText = nil
        defer { isSaving = false }
        do {
            try await SessionRepository.editDuration(
                sessionID:      session.id,
                newStartedAt:   newStartedAt,
                newCompletedAt: newCompletedAt,
                reason:         reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                    ? nil
                                    : reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )

            // Re-export to HealthKit with the updated interval.
            // KNOWN LIMITATION: HealthKitBridge has no delete/update API, so this may create
            // a second Health entry for the same session (duplicate); acceptable for v1.
            let updatedSession = WorkoutSession(
                id:                   session.id,
                routineID:            session.routineID,
                organizerID:          session.organizerID,
                state:                session.state,
                startedAt:            newStartedAt,
                completedAt:          newCompletedAt,
                createdAt:            session.createdAt,
                groupID:              session.groupID,
                roomCode:             session.roomCode,
                scheduledFor:         session.scheduledFor,
                seriesID:             session.seriesID,
                currentTurnUserID:    session.currentTurnUserID,
                currentTurnStartedAt: session.currentTurnStartedAt
            )
            let existingSets = (try? await SessionRepository.sessionSets(sessionID: session.id)) ?? []
            try? await HealthKitBridge.requestPermission()
            try? await HealthKitBridge.exportWorkout(session: updatedSession, setLogs: existingSets)

            onSaved()
            dismiss()
        } catch let e as GymSyncError {
            errorText = e.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
