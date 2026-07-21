import SwiftUI

// MARK: - GroupRecapView
//
// Canvas frame 8 (proof-frame-08.png) — full-screen group celebration recap.
// Presented from `GroupSessionLiveView.endSession()` the moment a GROUP
// session (liveSession.groupID != nil) completes, replacing the plain
// `SessionRecapView` sheet that view used to show for every completion
// regardless of solo/group. Solo/ad-hoc sessions routed through the same
// live view are UNCHANGED — still `SessionRecapView` (see
// `GroupSessionLiveView.buildGroupRecapPayload`'s doc comment for the
// before/after). `SessionRecapView`/`CompletedSessionView` remain the
// from-history views (spec §2: "Session Detail (frame 34) remains the
// from-history view") — this screen is the live, one-time completion
// moment only, and is the one place kudos can be sent (the crew is still
// "in the room").
//
// Parameterized on plain display-ready values, mirroring `SoloRecapView`'s
// extraction rationale (SoloRecapView.swift's type doc comment: "a
// hand-built catalog reproduction drifts from the real view over time, so
// the real view is parameterized on plain display-ready values instead"):
// `GroupSessionLiveView` computes the hero/leaderboard/PR-card values from
// data it already has at completion time (`participants`, the freshly
// fetched session sets, `ledgerGroup`, `routineName`, a
// `PersonalRecordRepository.bySession` fetch for the caller's OWN heaviestPR
// detail, and — since Fix round 1, task-4-report.md Finding 1 —
// `PersonalRecordRepository.countsBySession` for the crew-wide PR counts
// `bySession` cannot see under its self-only RLS; see
// `buildGroupRecapPayload`), and this view does no live data-fetching of
// its own for any of that.
//
// The ONE exception is kudos: counts update live while the recap sheet is
// open (participants tapping the emoji row), so kudos I/O is the one part
// of this view that talks to the network — `sessionID` + `recipientIDs`
// (crew-wide send targets = every OTHER participant, resolved by the
// caller) are passed in as plain values, and `.task` fetches the initial
// counts + opens a realtime subscription (`SessionKudosRepository`/
// `SessionKudosLiveService`, both new in this task alongside the backend
// migration). The `#if DEBUG` fixture seam below (mirrors
// `HomeGymSetupView`/`PushPrimingView`/`ChatView`'s established
// catalog-hermeticity pattern in this codebase) skips that live task
// entirely so the catalog capture is deterministic and makes no network
// call for a session that doesn't exist in the DB.
//
// Header (title + share-icon square) reuses SoloRecapView's `header`
// idiom verbatim in shape; hero + leaderboard reuse SessionRecapView's
// `heroBanner`/`participantRow` idiom in shape (both are PARALLEL
// structures with this comment, not shared extractions — SessionRecapView
// still exists as the from-history/solo-through-this-view fallback and
// must keep rendering exactly as it does today, so touching it to share
// code with a brand-new view was out of scope). Footer (Share Recap
// secondary + Done primary) reuses SessionRecapView's footer idiom, which
// is itself the same `ShareLink` idiom `PRCelebrationOverlay` uses.

struct GroupRecapView: View {
    struct LeaderboardRow: Identifiable {
        let id: UUID              // profile id — also the kudos chip lookup key
        let initials: String
        let name: String          // "You" for the caller's own row
        let volumeText: String    // e.g. "7,420 lbs" — full, comma-grouped (see formatVolumeFull)
        let prCount: Int
        let isYou: Bool
    }

    /// Parallel to `SoloRecapView.HeaviestPR` (not a shared extraction — see
    /// type doc comment above): same shape, different resolution path
    /// (whole-crew `personal_records` lookup vs a single session's own).
    struct HeaviestPR {
        let exerciseName: String
        let weight: Decimal
        let reps: Int
        let previousBest: Decimal
    }

    /// The frame's 5 kudos icons (proof-frame-08.png, "SEND KUDOS TO THE
    /// CREW" row) — single source of truth on the Swift side, mirrors the
    /// backend CHECK constraint's exact set
    /// (20260720000001_session_kudos.sql: `emoji IN ('💪','🔥','👏','🏆','⚡')`).
    static let kudosEmoji = ["💪", "🔥", "👏", "🏆", "⚡"]

    let kicker: String              // "PUSH CREW · PUSH DAY"
    let durationText: String        // "58:12"
    let subline: String             // "Thursday, July 10 · 4 lifters"
    let totalLbsText: String        // "24.6k" (abbreviated — hero only, see formatVolume)
    let setCount: Int
    let prCount: Int
    let leaderboard: [LeaderboardRow]
    let heaviestPR: HeaviestPR?
    let shareSummary: String
    let sessionID: UUID
    /// Crew-wide send targets — every OTHER participant, resolved by the
    /// caller (see kudos-send-model decision in the type doc comment).
    let recipientIDs: [UUID]
    let onDone: () -> Void

    @Environment(\.gsTheme) private var theme

    @State private var kudosCounts: [UUID: Int] = [:]
    @State private var lastKudosTapAt: Date = .distantPast
    @State private var kudosService = SessionKudosLiveService()

    #if DEBUG
    /// Catalog-fixture seam — see type doc comment. Non-nil only from the
    /// debug-only fixture initializer below; always nil on the real
    /// (GroupSessionLiveView) call path.
    private let catalogFixtureKudosCounts: [UUID: Int]?
    #endif

    init(
        kicker: String,
        durationText: String,
        subline: String,
        totalLbsText: String,
        setCount: Int,
        prCount: Int,
        leaderboard: [LeaderboardRow],
        heaviestPR: HeaviestPR?,
        shareSummary: String,
        sessionID: UUID,
        recipientIDs: [UUID],
        onDone: @escaping () -> Void
    ) {
        self.kicker = kicker
        self.durationText = durationText
        self.subline = subline
        self.totalLbsText = totalLbsText
        self.setCount = setCount
        self.prCount = prCount
        self.leaderboard = leaderboard
        self.heaviestPR = heaviestPR
        self.shareSummary = shareSummary
        self.sessionID = sessionID
        self.recipientIDs = recipientIDs
        self.onDone = onDone
        #if DEBUG
        self.catalogFixtureKudosCounts = nil
        #endif
    }

    #if DEBUG
    /// Catalog-only fixture initializer — seeds `kudosCounts` directly and
    /// makes `.task` skip the live fetch/subscribe (see `body`'s `.task`
    /// below). Same-file convenience init, needed because `kudosCounts` is
    /// `private @State` (mirrors `HomeGymSetupView`'s
    /// `catalogSkipLoadInitial`/`ChatView`'s `catalogFixtureMessages`
    /// pattern).
    init(
        kicker: String,
        durationText: String,
        subline: String,
        totalLbsText: String,
        setCount: Int,
        prCount: Int,
        leaderboard: [LeaderboardRow],
        heaviestPR: HeaviestPR?,
        shareSummary: String,
        sessionID: UUID,
        recipientIDs: [UUID],
        catalogFixtureKudosCounts: [UUID: Int],
        onDone: @escaping () -> Void
    ) {
        self.kicker = kicker
        self.durationText = durationText
        self.subline = subline
        self.totalLbsText = totalLbsText
        self.setCount = setCount
        self.prCount = prCount
        self.leaderboard = leaderboard
        self.heaviestPR = heaviestPR
        self.shareSummary = shareSummary
        self.sessionID = sessionID
        self.recipientIDs = recipientIDs
        self.onDone = onDone
        self.catalogFixtureKudosCounts = catalogFixtureKudosCounts
        _kudosCounts = State(initialValue: catalogFixtureKudosCounts)
    }
    #endif

    // MARK: - Body

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    hero
                    leaderboardSection
                    if let heaviestPR {
                        prCard(heaviestPR)
                    }
                    kudosSendSection
                }
                .padding(.bottom, 88)
            }
            footer
        }
        .background(theme.bg)
        .task {
            #if DEBUG
            if catalogFixtureKudosCounts != nil { return }
            #endif
            // Subscribe BEFORE the initial fetch (Fast-follow wave, Fix 2) —
            // subscribing after the fetch (the old order) left a lossy gap
            // between the fetch's DB snapshot and the channel reaching
            // SUBSCRIBED: any kudos tapped by another participant in that
            // window was invisible to both the snapshot (already read) and
            // the stream (not yet listening), permanently, since this view
            // never refetches. Opening the stream first closes that gap.
            //
            // Double-count note: a kudos committed between subscribe and
            // fetch-completion is now visible to BOTH the stream handler's
            // `+= 1` below AND `counts()`'s snapshot (which already reflects
            // every committed row). No dedupe-by-id was added — `counts()`'s
            // result is assigned with `=`, not merged, so it authoritatively
            // overwrites whatever the handler accumulated during the overlap
            // instead of stacking on top of it. That's the smallest correct
            // fix: the existing fetch line was already an overwrite, so
            // reordering the two statements is the entire change.
            await kudosService.subscribe(sessionID: sessionID) { kudo in
                kudosCounts[kudo.recipientID, default: 0] += 1
            }
            kudosCounts = (try? await SessionKudosRepository.counts(sessionID: sessionID)) ?? [:]
        }
        .onDisappear {
            Task { await kudosService.unsubscribe() }
        }
    }

    // MARK: - Header — "Session Complete" title + share icon (SoloRecapView's `header` idiom)

    private var header: some View {
        HStack {
            Text("Session Complete")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer()
            ShareLink(item: shareSummary) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 2)
        }
    }

    // MARK: - Hero — navy fill: kicker, huge duration, subline, TOTAL LBS/SETS/PRS
    // (SessionRecapView.heroBanner's idiom — parallel structure, see type doc comment)

    private var hero: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kicker)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(durationText)
                .font(.custom("Archivo-Bold", size: 52).monospacedDigit())
                .foregroundStyle(theme.bg)
                .lineLimit(1)

            Text(subline)
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.bg.opacity(0.9))

            HStack(spacing: 0) {
                heroStatCell(value: totalLbsText, label: "TOTAL LBS")
                Rectangle().fill(theme.bg.opacity(0.3)).frame(width: 1, height: 32)
                heroStatCell(value: "\(setCount)", label: "SETS")
                Rectangle().fill(theme.bg.opacity(0.3)).frame(width: 1, height: 32)
                heroStatCell(value: "\(prCount)", label: "PRS")
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    private func heroStatCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.heading(20, relativeTo: .title2))
                .foregroundStyle(theme.bg)
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.6)
                .foregroundStyle(theme.bg.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    // MARK: - Leaderboard · By Volume (SessionRecapView.participantRow's idiom, + kudos chip)

    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("Leaderboard · By Volume")
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ForEach(Array(leaderboard.enumerated()), id: \.element.id) { index, row in
                leaderboardRow(rank: index + 1, row: row)

                if index < leaderboard.count - 1 {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(height: 1)
                        .padding(.horizontal, 16)
                }
            }
        }
    }

    private func leaderboardRow(rank: Int, row: LeaderboardRow) -> some View {
        HStack(spacing: 10) {
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 18, alignment: .leading)

            ZStack {
                Rectangle()
                    .fill(rank == 1 ? theme.accent : theme.neutral400)
                    .frame(width: 32, height: 32)
                Text(row.initials)
                    .font(GSFont.bold(11, relativeTo: .caption2))
                    .foregroundStyle(theme.bg)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(row.name)
                    .font(GSFont.bold(13, relativeTo: .body))
                    .foregroundStyle(theme.text)

                HStack(spacing: 6) {
                    Text(row.volumeText)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                    if row.prCount > 0 {
                        Text("· \(row.prCount) PR\(row.prCount == 1 ? "" : "s")")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                    }
                }
            }

            Spacer()

            GSTag(text: "💪 \(kudosCounts[row.id, default: 0])", style: .accent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // "You" row highlight (proof-frame-08.png's tinted second row) —
        // exact hex isn't specified anywhere, this is a system-styling call
        // using an existing theme token rather than a new literal color.
        .background(row.isYou ? theme.neutral400.opacity(0.2) : Color.clear)
    }

    // MARK: - YOUR PR THIS SESSION card (SessionRecapView.yourPRCallout's idiom)

    private func prCard(_ pr: HeaviestPR) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("YOUR PR THIS SESSION")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
            }
            .foregroundStyle(theme.accent)
            Text("\(pr.exerciseName) — \(decimalString(pr.weight)) lbs × \(pr.reps)")
                .font(GSFont.bold(15, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text("▲ Beat previous best by \(decimalString(pr.weight - pr.previousBest)) lbs")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.accent700)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent100)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.accent300, lineWidth: 1))
        .padding(.horizontal, 16)
    }

    // MARK: - Send Kudos to the Crew — 5-emoji row, 1/sec client discipline
    // (same rate-limit idiom as GroupSessionLiveView.tapSound)

    private var kudosSendSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            GSSectionHeader("Send kudos to the crew")
                .padding(.horizontal, 16)

            HStack(spacing: 6) {
                ForEach(Self.kudosEmoji, id: \.self) { emoji in
                    Button {
                        tapKudos(emoji: emoji)
                    } label: {
                        Text(emoji)
                            .font(.system(size: 20))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    // No participants to send to (e.g. a 1-person "crew" edge
                    // case) — the row still renders (matches the frame), it
                    // just never fires an insert.
                    .disabled(recipientIDs.isEmpty)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func tapKudos(emoji: String) {
        let now = Date()
        guard now.timeIntervalSince(lastKudosTapAt) >= 1.0 else { return }
        lastKudosTapAt = now
        Task { await SessionKudosRepository.send(sessionID: sessionID, recipients: recipientIDs, emoji: emoji) }
    }

    // MARK: - Footer — Share Recap (secondary) + Done (primary), SessionRecapView's idiom

    private var footer: some View {
        VStack(spacing: 0) {
            GSDivider()
            HStack(spacing: 10) {
                ShareLink(item: shareSummary) {
                    Text("Share Recap")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSSecondaryButtonStyle())

                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSPrimaryButtonStyle())
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }

    // MARK: - Helpers

    private func decimalString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }
}
