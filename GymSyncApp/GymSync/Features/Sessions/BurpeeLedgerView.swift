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

    /// Set only by `GroupSessionLiveView`'s "Crew ledger" NavigationLink
    /// (`GroupSessionLiveView.swift:1469` — the ONE other construction site
    /// is `GroupView.swift:344`'s primary Sessions-tab entry, which leaves
    /// this `nil` since there's no live session anywhere below it on the
    /// nav stack). Fix wave 1 (reviewer Finding F4): before this fix, the
    /// "Log burpees now" CTA below unconditionally pushed a SECOND
    /// `GroupSessionLiveView` — if `liveSessionForCTA` happened to be the
    /// SAME session as the one this view was pushed from (reachable: the
    /// penalty banner that hosts the "Crew ledger" link only renders for a
    /// session you currently owe burpees in, which is exactly the session
    /// `liveSessionForCTA` resolves to whenever its most-recent-late session
    /// is still live), popping that duplicate back out fired ITS
    /// `onDisappear` with the default `voicePersistsOnPop: false` —
    /// unconditionally tearing down voice out from under the ORIGINAL,
    /// still-live `GroupSessionLiveView` instance sitting right below it.
    /// Read `GroupSessionLiveView.swift`'s nav structure (init at line 397,
    /// `onDisappear`'s `voicePersistsOnPop` guard at ~708-750) before
    /// choosing a fix: threading `voicePersistsOnPop: true` through was one
    /// option, but it only patches the SYMPTOM (the duplicate instance would
    /// still exist, still re-run `.onAppear`/`.task` roster/realtime
    /// subscriptions it doesn't need, and still leave two live copies of the
    /// same session on the stack simultaneously). Popping back to the
    /// EXISTING instance instead — via `@Environment(\.dismiss)` — is
    /// smaller and more honest: no duplicate is ever created, so there's
    /// nothing for a second `onDisappear` to mishandle. Deliberately a
    /// session id, not `VoiceRoomService.currentSessionID` (not exposed
    /// publicly for this per the task's own instruction) — this view has no
    /// business reaching into voice internals just to make a navigation
    /// decision.
    let pushedFromLiveSessionID: UUID?

    @Environment(\.gsTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(AppState.self) private var appState

    init(group: GymGroup, pushedFromLiveSessionID: UUID? = nil) {
        self.group = group
        self.pushedFromLiveSessionID = pushedFromLiveSessionID
    }

    // Fix round 1 (task-3-report.md): the group-wide crew debt list and the
    // self-only "YOU OWE" detail now come from two separate queries — see
    // `SessionRepository.burpeeLedger`/`myBurpeeLedgerRows` doc comments.
    @State private var crewDebts: [BurpeeLedgerMath.CrewDebt] = []
    @State private var myRows: [BurpeeLedgerRow] = []
    @State private var profiles: [UUID: Profile] = [:]
    @State private var liveSessionForCTA: WorkoutSession?
    @State private var isLoading = true
    @State private var errorText: String?
    // Payoff sheet (user 2026-07-31: "there's no way to actually pay off
    // your burpee debt" from this screen). Penalty reps attach to the most
    // recent session that contributed debt — the ledger RPC nets `paid`
    // across ALL the group's sessions, so any owed session settles the
    // aggregate; the completed-session insert is deliberately allowed by
    // the pre-live trigger (20260803000002).
    @State private var showPayoffSheet = false
    @State private var payoffReps = 0
    @State private var isSubmittingPayoff = false

    private var selfID: UUID? { appState.currentProfile?.id }

    private var youOwe: BurpeeLedgerMath.YouOweSummary? {
        guard let selfID else { return nil }
        return BurpeeLedgerMath.youOweSummary(rows: myRows, userID: selfID)
    }

    /// What I actually still owe TODAY — the server-netted aggregate (owed
    /// minus paid), never the raw lifetime total. The raw `youOwe.total`
    /// would keep showing settled debt forever once payoff exists.
    private var myOutstanding: Int {
        guard let selfID else { return 0 }
        if let mine = crewDebts.first(where: { $0.userID == selfID }) {
            return mine.outstanding
        }
        return youOwe?.total ?? 0
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
                if let youOwe, myOutstanding > 0 {
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
        .sheet(isPresented: $showPayoffSheet) { payoffSheet }
    }

    // MARK: - You-owe banner

    private func youOweBanner(_ summary: BurpeeLedgerMath.YouOweSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOU OWE")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(myOutstanding)")
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

            // Live session available → go log them there (Finding F4's
            // pop-back-vs-push split unchanged). Otherwise the ledger's own
            // payoff sheet (user 2026-07-31) — debt no longer needs a live
            // session to settle.
            if let live = liveSessionForCTA {
                if live.id == pushedFromLiveSessionID {
                    Button {
                        dismiss()
                    } label: {
                        logBurpeesNowLabel
                    }
                    .buttonStyle(.gs3D(face: theme.bg, cornerRadius: 12, lipHeight: 5))
                } else {
                    NavigationLink {
                        GroupSessionLiveView(session: live)
                    } label: {
                        logBurpeesNowLabel
                    }
                    .buttonStyle(.gs3D(face: theme.bg, cornerRadius: 12, lipHeight: 5))
                }
            } else {
                Button {
                    payoffReps = myOutstanding
                    showPayoffSheet = true
                } label: {
                    logBurpeesNowLabel
                }
                .buttonStyle(.gs3D(face: theme.bg, cornerRadius: 12, lipHeight: 5))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
        // Onyx alignment (2026-07-31): the banner is a floating widget now.
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    /// Shared visual content for the "Log burpees now" CTA — identical
    /// whichever of the navigation actions above wraps it (push vs.
    /// pop-back vs. payoff sheet), so the fix's dismiss-instead-of-push
    /// branch (Finding F4) reads as a pure behavior change, not a redesign.
    /// 3D pass (2026-08): every wrapper applies the same `.gs3D` bg-face
    /// style; this label is face content only — 39pt + 5pt lip keeps the
    /// prior 44pt footprint on the accent banner.
    private var logBurpeesNowLabel: some View {
        HStack {
            Text("Log burpees now")
                .font(GSFont.bold(14, relativeTo: .body))
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
        }
        .foregroundStyle(theme.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 9.5)
        .frame(maxWidth: .infinity, minHeight: 39)
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
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 20))
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
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(theme.surface)
            // Onyx alignment (2026-07-31): the row list rides in one
            // floating card, like every list on the live pages.
            .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 20))
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

        return HStack(spacing: 10) {
            // Onyx alignment (2026-07-31): circle avatar, real photo when
            // one exists — matches the rotation widget and board rows.
            GSInitialsAvatar(name: identityName, avatarURL: profile?.avatarURL, size: 32)

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
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.neutral400, lineWidth: 1))
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Payoff sheet (2026-07-31)
    //
    // "How many did you do?" — a stepper prefilled with the full
    // outstanding amount, capped there (overpaying would bank phantom
    // credit against future lateness). Writes ONE penalty SetLog against
    // the most recent debt-contributing session; the ledger RPC nets
    // `paid` group-wide, so the aggregate settles regardless of which
    // owed session carries the reps.

    private var payoffSheet: some View {
        VStack(spacing: 0) {
            Text("PAY OFF BURPEES")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.neutral700)
                .padding(.top, 26)
            Spacer(minLength: 12)
            HStack(spacing: 26) {
                Button {
                    payoffReps = max(1, payoffReps - 1)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.text)
                        .frame(width: 52, height: 52)
                        .background(theme.surface)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)

                Text("\(payoffReps)")
                    .font(GSFont.boldFixed(64).monospacedDigit())
                    .foregroundStyle(theme.text)
                    .frame(minWidth: 120)

                Button {
                    payoffReps = min(myOutstanding, payoffReps + 1)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(theme.text)
                        .frame(width: 52, height: 52)
                        .background(theme.surface)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
            Text("OF \(myOutstanding) OUTSTANDING")
                .font(GSFont.bold(10, relativeTo: .caption2).monospacedDigit())
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)
                .padding(.top, 12)
            Spacer(minLength: 16)
            // 3D pass (2026-08): accent gs3D face, 59pt + 5pt lip = the
            // prior 64pt CTA footprint.
            Button {
                Task { await submitPayoff() }
            } label: {
                Text(isSubmittingPayoff ? "LOGGING…" : "LOG \(payoffReps) BURPEES")
                    .font(GSFont.bold(17, relativeTo: .body).monospacedDigit())
                    .tracking(0.9)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 59)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 16, lipHeight: 5))
            .disabled(isSubmittingPayoff || payoffReps < 1)
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .presentationDetents([.height(340)])
        .presentationBackground(theme.bg)
    }

    @MainActor
    private func submitPayoff() async {
        guard !isSubmittingPayoff, payoffReps > 0,
              let userID = selfID,
              let target = youOwe?.mostRecentSessionID else { return }
        isSubmittingPayoff = true
        defer { isSubmittingPayoff = false }
        do {
            // Same burpee-exercise resolution the live session's penalty
            // sheet uses: name-contains, catalog-wide.
            let catalog = try await ExerciseRepository.fetchAll()
            guard let burpee = catalog.first(where: {
                $0.name.localizedCaseInsensitiveContains("burpee")
            }) else {
                errorText = "No burpee exercise in the catalog."
                return
            }
            let log = SetLog(
                id: UUID(), userID: userID, sessionID: target,
                exerciseID: burpee.id, setIndex: 1,
                reps: payoffReps, weight: nil, rpe: nil,
                isFailed: false, isPenalty: true,
                note: nil, loggedAt: Date()
            )
            try await SessionRepository.logSet(log)
            showPayoffSheet = false
            await load()
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
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

}
