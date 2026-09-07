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
    /// Units sweep: display unit for the hero label and the PR-card weights
    /// this view formats itself (leaderboard `volumeText`/`totalLbsText`
    /// arrive pre-converted, per the display-ready convention). Defaulted so
    /// catalog fixtures and lbs callers compile unchanged.
    var unit: WeightUnit = .lbs
    /// Pump Check (spec 2026-07-27): non-nil mounts the composer at the top
    /// — nil (catalog fixtures) renders none.
    var pumpCheck: PumpCheckContext? = nil
    // Coach debrief (AI after-action, group mirror 2026-08-22): the
    // caller builds it from MY sets only - the report is personal even
    // when the session wasn't. Defaulted so fixtures compile unchanged.
    var coachDebrief: WorkoutDebrief? = nil
    var coachName: String = "Coach"
    var onTalkToCoach: (() -> Void)? = nil
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
        unit: WeightUnit = .lbs,
        pumpCheck: PumpCheckContext? = nil,
        coachDebrief: WorkoutDebrief? = nil,
        coachName: String = "Coach",
        onTalkToCoach: (() -> Void)? = nil,
        onDone: @escaping () -> Void
    ) {
        self.pumpCheck = pumpCheck
        self.coachDebrief = coachDebrief
        self.coachName = coachName
        self.onTalkToCoach = onTalkToCoach
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
        self.unit = unit
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
                    // Pump Check composer FIRST — the 1:00 window is live
                    // while the crew reads the leaderboard.
                    if let pumpCheck {
                        PumpCheckComposerCard(context: pumpCheck)
                            .padding(.horizontal, 16)
                    }
                    // 16 pt inset (review B1 F4): the hero is a raised object
                    // now, so it needs margins for its lip to read — matching
                    // SoloRecapView and CompletedSessionView.
                    hero
                        .padding(.horizontal, 16)
                    // Coach card after the numbers, same placement law as
                    // the solo recap: the computed observation is the
                    // debrief's own advertisement, every workout.
                    if let coachDebrief {
                        CoachDebriefCard(debrief: coachDebrief,
                                         coachName: coachName,
                                         onTalk: { onTalkToCoach?() })
                            .padding(.horizontal, 16)
                    }
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
            // neutral800, not neutral500 — the same raised3DFace contrast rule
            // GSComponents' voice-connected toast and coach mark already
            // follow. neutral500 measures 2.13:1 on Onyx against this face;
            // neutral800 measures 8.91:1, the only neutral clearing WCAG AA
            // (4.5:1) on every palette. These runs are the smallest type on
            // the card, so the large-text 3:1 relaxation does not apply.
            Text(kicker)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.neutral800)

            Text(durationText)
                .font(.custom("Archivo-Bold", size: 52).monospacedDigit())
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Text(subline)
                .font(GSFont.body(12, relativeTo: .footnote))
                .foregroundStyle(theme.neutral800)

            HStack(spacing: 0) {
                heroStatCell(value: totalLbsText, label: "TOTAL \(unit.label.uppercased())")
                Rectangle().fill(theme.divider).frame(width: 1, height: 32)
                heroStatCell(value: "\(setCount)", label: "SETS")
                Rectangle().fill(theme.divider).frame(width: 1, height: 32)
                heroStatCell(value: "\(prCount)", label: "PRS")
            }
            .padding(.top, 12)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Accent discipline (design language §1/§2, 2026-09-06): the
        // full-bleed accent fill becomes the app's static extruded card and
        // the ink inverts. Every number and copy line is unchanged.
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 7)
    }

    private func heroStatCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.heading(20, relativeTo: .title2))
                .foregroundStyle(theme.text)
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(0.6)
                // 9 pt on a raised face — see the neutral800 note on `hero`.
                .foregroundStyle(theme.neutral800)
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

    // The shared `GSLeaderboardRow` (DesignSystem/GSComponents.swift) — this
    // file's own copy of that shape (and its accent #1 rank + accent avatar
    // tile) retires with the accent-discipline sweep 2026-09-06. The row's
    // "You" highlight is the same neutral token as before; `initials:` keeps
    // this board's precomputed initials, which its display name ("You" for the
    // caller) could not produce.
    private func leaderboardRow(rank: Int, row: LeaderboardRow) -> some View {
        GSLeaderboardRow(
            rank: rank,
            name: row.name,
            initials: row.initials,
            subtitle: row.prCount > 0
                ? "\(row.volumeText) · \(row.prCount) PR\(row.prCount == 1 ? "" : "s")"
                : row.volumeText,
            isYou: row.isYou
        ) {
            // Kudos emoji are content (design language §2), so the chip stays.
            GSTag(text: "💪 \(kudosCounts[row.id, default: 0])", style: .accent)
        }
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
            Text("\(pr.exerciseName) — \(Units.format(pounds: pr.weight, unit: unit, rounded: false, includeUnit: false)) \(unit.label) × \(pr.reps)")
                .font(GSFont.bold(15, relativeTo: .headline))
                .foregroundStyle(theme.text)
            Text("▲ Beat previous best by \(Units.format(pounds: pr.weight - pr.previousBest, unit: unit, rounded: false, includeUnit: false)) \(unit.label)")
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

                // 3D pass (2026-08): the label reproduces the primary
                // style's bold-16 bg-on-accent look; 37pt face + the gs3D
                // style's 7pt lip keeps the prior 44pt footprint beside
                // the flat Share Recap secondary.
                Button {
                    onDone()
                } label: {
                    Text("Done")
                        .font(GSFont.bold(16, relativeTo: .body))
                        .foregroundStyle(theme.bg)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 37)
                }
                .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }

    // MARK: - Helpers

}
