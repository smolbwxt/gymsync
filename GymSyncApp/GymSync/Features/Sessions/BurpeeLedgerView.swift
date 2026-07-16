import SwiftUI

// MARK: - BurpeeLedgerView
//
// Proof p25 ("Penalty Ledger"). Group-scoped: aggregates burpee debt across
// every session the group has run, per crew member.
//
// Entry points (per task-3-brief.md, "likely GroupView tab/row and/or the
// live session penalty banner"):
//   1. PRIMARY — GroupView's Sessions sub-tab, a row above Upcoming/Past.
//   2. SECONDARY — GroupSessionLiveView's existing per-session penalty
//      banner, a "Crew ledger" link (only for group sessions, since ad-hoc
//      solo/friend sessions have no `groupID`).
//
// SCHEMA GAP — CLOSED (Phase S Task 5, 20260719000005_burpee_ledger_paid.sql):
// the proof's crew-debt list includes a "paid off 20 · Jul 9" state, which
// used to be unrenderable (full history in BurpeeLedgerMath's doc comment
// and task-3-report.md). The RPC now returns `paid`/`settled`; `crewDebtRow`
// below renders the settled state per frame 25 — a paid-off participant
// shows a greyed 0 with "paid off N · {date}" subtext, distinct from "all
// clear" for one who was never late.
//
// SCHEMA GAP #2: the proof's late-penalty config card also shows a fixed
// "no-show = 25" clause. `late_penalty` jsonb only ever carries `per_minute`
// (see `20260712000001_sessions_phase3_columns.sql`) — `evaluate_lateness`
// never assigns a fixed no-show burpee count, only late-minutes × per-minute.
// Rendered without that clause rather than inventing a number.
//
// SCHEMA GAP #3: the card's "Edit" affordance has no write path — no
// repository method updates `sessions.late_penalty` or
// `groups.default_late_penalty` from the client, and building that RPC is
// out of this task's contract (aggregate reads only). Rendered as an inert,
// visually-disabled label rather than a button that silently no-ops.
struct BurpeeLedgerView: View {
    let group: GymGroup

    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    // Fix round 1 (task-3-report.md): the group-wide crew debt list and the
    // self-only "YOU OWE" detail now come from two separate queries — see
    // `SessionRepository.burpeeLedger`/`myBurpeeLedgerRows` doc comments.
    @State private var crewDebts: [BurpeeLedgerMath.CrewDebt] = []
    @State private var myRows: [BurpeeLedgerRow] = []
    @State private var profiles: [UUID: Profile] = [:]
    @State private var liveSessionForCTA: WorkoutSession?
    @State private var isLoading = true
    @State private var errorText: String?

    private var selfID: UUID? { appState.currentProfile?.id }

    private var youOwe: BurpeeLedgerMath.YouOweSummary? {
        guard let selfID else { return nil }
        return BurpeeLedgerMath.youOweSummary(rows: myRows, userID: selfID)
    }

    /// The rate that actually applied most recently across the group's
    /// sessions — there's no single "the group's penalty config" read
    /// available client-side beyond what each session snapshot recorded.
    /// `myRows` is self-only, but that's not a narrower session set than the
    /// old group-wide fetch actually covered for this caller: RLS already
    /// bounded that fetch to sessions the caller participates in (own row,
    /// or "readable by other participants" — which itself requires the
    /// caller to already be a participant), so per-session coverage is
    /// identical; only the now-redundant OTHER participants' duplicate rows
    /// for those same sessions are gone.
    private var latePenaltyPerMinute: Int? {
        myRows
            .compactMap { row -> (Date, Int)? in
                guard let rate = row.session.latePenalty?.perMinute else { return nil }
                return (row.session.effectiveDate ?? .distantPast, rate)
            }
            .max { $0.0 < $1.0 }?
            .1
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let youOwe, youOwe.total > 0 {
                    youOweBanner(youOwe)
                } else if !isLoading {
                    allClearBanner
                }

                if !crewDebts.isEmpty {
                    crewDebtsSection
                }

                latePenaltyCard

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        .navigationTitle("Penalty Ledger")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: - You-owe banner

    private func youOweBanner(_ summary: BurpeeLedgerMath.YouOweSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOU OWE")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(summary.total)")
                    .font(GSFont.bold(56, relativeTo: .largeTitle))
                    .foregroundStyle(theme.bg)
                    .lineLimit(1)
                Text("burpees")
                    .font(GSFont.bold(18, relativeTo: .title2))
                    .foregroundStyle(theme.bg)
            }

            if let detail = detailLine(summary) {
                Text(detail)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.bg.opacity(0.9))
            }

            // Only actionable when the contributing session is still live —
            // burpee logging has no standalone flow outside a live session's
            // LogSetSheet (see GroupSessionLiveView.logSetSheetContent).
            if let live = liveSessionForCTA {
                NavigationLink {
                    GroupSessionLiveView(session: live)
                } label: {
                    HStack {
                        Text("Log burpees now")
                            .font(GSFont.bold(14, relativeTo: .body))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(theme.bg)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    private func detailLine(_ summary: BurpeeLedgerMath.YouOweSummary) -> String? {
        guard let minutes = summary.mostRecentLateMinutes else { return nil }
        var parts = ["\(minutes) min late to \(group.name)"]
        if let date = summary.mostRecentDate {
            parts.append(date.formatted(.dateTime.month(.abbreviated).day()))
        }
        if let rate = summary.mostRecentPerMinute {
            parts.append("\(rate) burpees / min")
        }
        return parts.joined(separator: " · ")
    }

    private var allClearBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("YOU OWE")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.neutral500)
            Text("Nothing — you're all clear")
                .font(GSFont.bold(16, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Crew debts

    private var crewDebtsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            GSSectionHeader("Crew debts")
            VStack(spacing: 0) {
                ForEach(crewDebts) { debt in
                    crewDebtRow(debt)
                    if debt.id != crewDebts.last?.id {
                        Rectangle().fill(theme.divider).frame(height: 1)
                    }
                }
            }
        }
    }

    private func crewDebtRow(_ debt: BurpeeLedgerMath.CrewDebt) -> some View {
        let profile = profiles[debt.userID]
        let isMe = debt.userID == selfID
        // Fix (minor, task-3-report.md): initials used to derive from
        // `username` alone while the label showed `displayName ?? username`
        // — a real user with a displayName would show initials that didn't
        // match their rendered name. Both now derive from the SAME identity
        // string. `identityName` (not the "You" substitution) is what feeds
        // initials even for the self row — the proof (p25) shows the self
        // row's avatar as "AJ", the user's real initials, not "Y".
        let identityName = profile?.displayName ?? profile?.username ?? "Unknown"
        let displayName = isMe ? "You" : identityName
        let initials = Self.initials(from: identityName)

        return HStack(spacing: 10) {
            ZStack {
                Rectangle()
                    .fill(theme.neutral700)
                    .frame(width: 32, height: 32)
                Text(initials)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 1) {
                Text(displayName)
                    .font(GSFont.bold(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text(crewDebtSubtext(debt))
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            // Outstanding (not the raw lifetime `totalOwed`) — a paid-off
            // debt reads 0 here, same as a never-late row (frame 25: Sam's
            // "paid off 20" row still shows a greyed 0).
            Text("\(debt.outstanding)")
                .font(GSFont.bold(18, relativeTo: .title3))
                .foregroundStyle(debt.outstanding > 0 ? theme.accent700 : theme.neutral500.opacity(0.6))
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 4)
        .frame(minHeight: 44)
        .background(isMe ? theme.text.opacity(0.04) : Color.clear)
    }

    /// "paid off 20 · Jul 9" (frame 25's settled-row treatment) when the
    /// debt was actually paid off, else the plain `summaryText` unchanged.
    /// The date suffix is appended here (not inside `BurpeeLedgerMath`) for
    /// the same reason `detailLine(_:)` above formats `mostRecentDate`
    /// itself rather than `BurpeeLedgerMath` doing it: Math returns raw
    /// `Date`s, the View owns presentation formatting.
    private func crewDebtSubtext(_ debt: BurpeeLedgerMath.CrewDebt) -> String {
        guard debt.isPaidOff else { return debt.summaryText }
        guard let date = debt.lastLateAt else { return debt.summaryText }
        return "\(debt.summaryText) · \(date.formatted(.dateTime.month(.abbreviated).day()))"
    }

    // MARK: - Late penalty config card

    private var latePenaltyCard: some View {
        HStack(spacing: 10) {
            Image(systemName: "gearshape")
                .font(.system(size: 18))
                .foregroundStyle(theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text("Late penalty")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(latePenaltyPerMinute.map { "\($0) burpees per minute" } ?? "Not yet configured")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }

            Spacer()

            // Intentionally inert — no repository write path for late_penalty
            // config exists yet (schema gap #3, see file header). A visually
            // disabled label rather than a button that silently no-ops.
            Text("Edit")
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .overlay(Rectangle().strokeBorder(theme.neutral400, lineWidth: 1))
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(theme.surface)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Data loading

    @MainActor
    private func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            async let crewTask = SessionRepository.burpeeLedger(groupID: group.id)
            async let myRowsTask = SessionRepository.myBurpeeLedgerRows(groupID: group.id)
            let (fetchedCrewDebts, fetchedMyRows) = try await (crewTask, myRowsTask)
            crewDebts = fetchedCrewDebts
            myRows = fetchedMyRows

            let ids = fetchedCrewDebts.map(\.userID)
            let fetchedProfiles = try await ProfileRepository.fetchMany(ids: ids)
            profiles = Dictionary(uniqueKeysWithValues: fetchedProfiles.map { ($0.id, $0) })

            if let selfID {
                let summary = BurpeeLedgerMath.youOweSummary(rows: fetchedMyRows, userID: selfID)
                if summary.total > 0, summary.mostRecentSessionIsLive,
                   let sessionID = summary.mostRecentSessionID {
                    liveSessionForCTA = try await SessionRepository.session(id: sessionID)
                } else {
                    liveSessionForCTA = nil
                }
            } else {
                liveSessionForCTA = nil
            }
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    // MARK: - Initials

    /// Same split-on-spaces algorithm as `GSInitialsAvatar` (SocialTabView.swift)
    /// — replicated rather than reused because that view computes initials
    /// from its own `name` property (not trivially accessible as a static
    /// helper) and this row's avatar deliberately diverges from
    /// `GSInitialsAvatar` in color (`theme.neutral700`/`theme.bg` here vs.
    /// its `theme.accent`/`theme.bg` — matches the canvas markup's
    /// `--color-neutral-700` literally, a documented judgment call from the
    /// original task-3 build, not something this fix touches).
    private static func initials(from name: String) -> String {
        let parts = name.split(separator: " ").prefix(2)
        return parts.map { String($0.prefix(1)).uppercased() }.joined()
    }
}
