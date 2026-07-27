import SwiftUI

// MARK: - CompletedSessionView
//
// Shows a summary of a completed (or abandoned) session:
//   • Header: duration H:MM headline + inline Edit button, audit line
//     ("Duration edited by X · was Y") when durationWasEdited
//   • Aggregate stats row (volume / sets / PRs)
//   • Per-participant stats (same semantics as SessionRecapView: volume excludes penalty+failed,
//     PR count + late/penalty reps shown as trailing pills)
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

    // MARK: - Audit / group / PR data

    @State private var groupName: String?
    @State private var editorName: String?
    @State private var previousDuration: (start: Date, end: Date)?
    /// Per-user PR counts for this session, across ALL participants (aggregate
    /// PRS tile + every "N PR" badge below — both COUNT-only; this view has no
    /// own-PR-detail card, so `PersonalRecordRepository.bySession` was never
    /// needed here). Sourced from `.countsBySession`, backed by the
    /// `session_pr_counts` SECURITY DEFINER RPC
    /// (20260720000002_session_pr_counts_and_kudos_guard.sql) — `bySession`
    /// is a direct `personal_records` select gated by that table's SELF-ONLY
    /// SELECT RLS (20260715000002_personal_records.sql:23-25), so for a real
    /// multi-lifter group session it silently returned only the viewing
    /// user's own rows and undercounted every teammate to zero (Fast-follow
    /// wave, Fix 1 — tracked as DEBT in the Phase F ledger since
    /// F-Task 4 COMPLETE: "CompletedSessionView teammate-PR badges (same
    /// latent RLS bug, flagged not fixed)"). See
    /// `PersonalRecordRepository.countsBySession`'s doc comment for the full
    /// history (Fix round 1 fixed the equivalent bug in
    /// `GroupSessionLiveView.buildGroupRecapPayload`).
    @State private var prCountByUser: [UUID: Int] = [:]

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

                    // ── AGGREGATE STATS ────────────────────────────────────
                    aggregateStatsRow
                        .padding(.horizontal, 16)
                        .padding(.top, 14)
                        .padding(.bottom, 14)

                    GSDivider()
                        .padding(.horizontal, 16)

                    // ── PARTICIPANTS ──────────────────────────────────────
                    if !participants.isEmpty {
                        GSSectionHeader("Lifters · \(participants.count)")
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
        // Pushed from GroupView's Sessions sub-tab — see GSComponents.swift's
        // GSHidesDock (matches system hidesBottomBarWhenPushed for every
        // pushed detail screen, per the canvas proofs, not just ones with an
        // explicit bottom bar of their own).
        .gsHidesDock()
        .navigationTitle(navigationTitleText)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: shareText) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
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
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("DURATION")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.4)
                        .foregroundStyle(theme.bg.opacity(0.85))

                    Text(durationString)
                        .font(.custom("Archivo-Bold", size: 34).monospacedDigit())
                        .foregroundStyle(theme.bg)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    showEditSheet = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "pencil")
                            .font(.system(size: 13, weight: .medium))
                        Text("Edit")
                            .font(GSFont.bold(12, relativeTo: .caption))
                    }
                    .foregroundStyle(theme.bg)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .background(theme.bg.opacity(0.15))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if liveSession.durationWasEdited {
                Text(auditLineText)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .italic()
                    .foregroundStyle(theme.bg.opacity(0.8))
                    .padding(.top, 2)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    // MARK: - Aggregate stats row

    private var aggregateStatsRow: some View {
        HStack(spacing: 8) {
            GSStatTile(value: formatVolume(totalVolume), label: "VOLUME")
            GSStatTile(value: "\(totalSets)", label: "SETS")
            GSStatTile(value: "\(totalPRCount)", label: "PRS")
        }
    }

    private var totalSets: Int { sets.filter { !$0.isPenalty }.count }

    /// Sum across all participants — see `prCountByUser`'s doc comment.
    private var totalPRCount: Int { prCountByUser.values.reduce(0, +) }

    private var totalVolume: Double {
        sets.filter { !$0.isPenalty }.reduce(0.0) { acc, log in
            guard !log.isFailed, let r = log.reps, let w = log.weight else { return acc }
            return acc + Double(r) * NSDecimalNumber(decimal: w).doubleValue
        }
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
                        Text("\(formatVolume(Units.fromPounds(stat.volume, to: ThemeStore.shared.weightUnit))) \(ThemeStore.shared.weightUnit.label)")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                let prs = prCount(for: stat.participant.userID)
                if prs > 0 {
                    GSTag(text: "\(prs) PR\(prs == 1 ? "" : "s")", style: .accent)
                }
                if stat.penaltyReps > 0 {
                    // Emoji sweep (spec §7): the flame implied the burpee
                    // penalty — say it plainly instead.
                    Text("late · \(stat.penaltyReps) burpees")
                        .font(GSFont.body(10, relativeTo: .caption2))
                        .foregroundStyle(theme.accent700)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func prCount(for userID: UUID) -> Int {
        prCountByUser[userID, default: 0]
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

    private var shortDateString: String {
        guard let date = liveSession.completedAt ?? liveSession.startedAt else { return "" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }

    private var navigationTitleText: String {
        guard let groupName else { return shortDateString }
        return "\(shortDateString) · \(groupName)"
    }

    private var shareText: String {
        let unit = ThemeStore.shared.weightUnit
        return "\(navigationTitleText) — \(durationString), \(formatVolume(Units.fromPounds(totalVolume, to: unit))) \(unit.label), \(totalSets) sets."
    }

    private func durationString(from start: Date, to end: Date) -> String {
        let total = Int(max(0, end.timeIntervalSince(start)))
        let h = total / 3600
        let m = (total % 3600) / 60
        return h > 0
            ? String(format: "%d:%02d", h, m)
            : String(format: "%02d:%02d", m, total % 60)
    }

    private var auditLineText: String {
        var text = "Duration edited"
        if let editorName {
            text += " by \(editorName)"
        }
        if let previousDuration {
            text += " · was \(durationString(from: previousDuration.start, to: previousDuration.end))"
        }
        return text
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

            if let groupID = liveSession.groupID {
                groupName = (try? await GroupRepository.fetchMany(ids: [groupID]))?.first?.name
            }
            if liveSession.durationWasEdited {
                if let editedBy = liveSession.editedBy {
                    editorName = (try? await ProfileRepository.fetch(userID: editedBy))?.username
                }
                if let edit = try? await SessionRepository.latestDurationEdit(sessionID: liveSession.id),
                   let start = edit.oldStartedAt, let end = edit.oldCompletedAt {
                    previousDuration = (start: start, end: end)
                }
            }
            let prCounts = (try? await PersonalRecordRepository.countsBySession(sessionID: liveSession.id)) ?? []
            prCountByUser = prCounts.reduce(into: [:]) { acc, row in acc[row.userID] = row.prCount }
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

            // Re-write the HealthKit export with the corrected interval.
            // HealthKitBridge.replaceWorkout (Phase H) deletes the prior
            // export — matched by the HKMetadataKeyExternalUUID stamp
            // exportWorkout now writes — then re-exports; best-effort,
            // logged internally, never throws. HONEST LIMITATION (see that
            // function's doc comment): a session exported before this change
            // has no stamp to match on, so its old sample can't be found and
            // deleted — the edit still re-exports, so pre-Phase-H sessions
            // may still end up with a duplicate Health entry. That was the
            // ONLY case before this change too; now it's the exception
            // rather than the rule.
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
            await HealthKitBridge.replaceWorkout(session: updatedSession, setLogs: existingSets)

            onSaved()
            dismiss()
        } catch let e as GymSyncError {
            errorText = e.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}
