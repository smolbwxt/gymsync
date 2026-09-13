import SwiftUI

// MARK: - WarmUpScreen
//
// Plan task S9. Spec §2 and §3.2, owner decisions 3 and 5. Reference frames:
// `warmup-solo-v2` (122) and `warmup-crew` (111).
//
// ONE SCREEN, TWO FRAMES — same body, different frame (design rule 4). Crew
// presence ADDS (the readiness row, the dock, the leader's note) and never
// rearranges: both frames carry, in this order, the plan card, the clock, and
// `START LIFTING` as the one accent primary in the foot.

/// When the warm-up screen renders.
enum WarmUpGate {
    /// The warm-up screen renders while the session is live and lifting has
    /// not begun. `warmup_minutes` is deliberately NOT read: spec §6 retires
    /// it ("warm-up is a phase, not a number"), and the clock that used to
    /// end the phase is now a readout.
    ///
    /// THE ONE EDGE, named rather than discovered: a session that was already
    /// `in_progress` with `lifting_started_at IS NULL` when this build shipped
    /// re-enters the warm-up screen once. Every such session's next
    /// "Start lifting" writes `lifting_started_at`, so the state is
    /// self-healing and bounded by one tap.
    static func isWarmingUp(state: String, liftingStartedAt: Date?) -> Bool {
        state == "in_progress" && liftingStartedAt == nil
    }

    /// The runner's own restatement of this gate (review push-5 finding 2)
    /// — `SessionRunnerView` is the destination of both `.warmUp` and
    /// `.live` from `SessionRouter`, and must not draw a screen that
    /// contradicts the route that sent it here. Unlike `isWarmingUp`, this
    /// also covers `scheduled` and `lobby_open`: `SessionEntryView` sends a
    /// SCHEDULED solo session straight to the runner too (spec §2, owner
    /// decision 3 — solo has no lobby), a case `isWarmingUp` alone has never
    /// seen. A terminal session stays false regardless of
    /// `liftingStartedAt`: it self-presents its recap through
    /// `SessionInProgressView` rather than re-entering warm-up.
    ///
    /// N1 (review push-5): this used to be a second, untested law inlined
    /// as `SessionRunnerView.warmingUp`. Named and tested here instead, so
    /// the two gates cannot silently diverge again the way they did when
    /// `isWarmingUp` alone produced finding 2.
    static func showsWarmUp(state: String, liftingStartedAt: Date?) -> Bool {
        if state == "completed" || state == "abandoned" { return false }
        return liftingStartedAt == nil
    }

    /// `"12:04"` — the phase's elapsed time, as the clock strip prints it.
    ///
    /// A pure function of two dates so the screen has no clock of its own and
    /// a catalog frame can hand it a fixture. Negative and absent both read
    /// `0:00`: a warm-up that has not started has not run backwards.
    static func elapsed(since startedAt: Date?, now: Date) -> String {
        guard let startedAt else { return "0:00" }
        let seconds = Int(max(0, now.timeIntervalSince(startedAt)))
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// `"2 of 4 warm"` — the readiness row's right-hand count.
    static func warmCaption(warm: Int, total: Int) -> String {
        "\(warm) of \(total) warm"
    }

    /// The leader's note under `START LIFTING` while somebody is still
    /// warming up. Nil when everyone is warm, or when I am not the leader —
    /// the primary stays LIVE either way (spec §3.2 lets the leader move on),
    /// and this is where that costs something rather than a second control.
    static func leaderNote(isOrganizer: Bool, stillWarming: [String]) -> String? {
        guard isOrganizer, let first = stillWarming.first else { return nil }
        // Subject-verb agreement (review push-5 R-18, finding 8): one name
        // is singular ("Sam is"); a name plus a count is plural ("Sam and 1
        // more ARE"), not the "is" a naive single template produced.
        if stillWarming.count == 1 {
            return "You're the leader · \(first) is still warming up"
        }
        return "You're the leader · \(first) and \(stillWarming.count - 1) more are still warming up"
    }
}

/// The warm-up screen — solo and crew, one body.
struct WarmUpScreen: View {
    @Environment(\.gsTheme) private var theme

    /// The crew, already staged for the readiness row. Empty in the solo
    /// frame, which is what `isSolo` means here rather than a second source.
    let warmthRows: [SessionWarmthRow]
    let isSolo: Bool
    let isOrganizer: Bool

    // The plan
    let planRows: [SessionPlanRow]
    /// The day's rung, large — the biggest thing on this screen is what you
    /// are about to lift.
    let rungHeadline: String
    let rungDetail: String
    /// Coach's line. Solo shows it inside the plan card; crew shows it below,
    /// marked private.
    let coachLine: String?

    // The block, solo only (`warmup-solo-v2`'s ladder strip).
    let blockWeek: Int
    let blockWeeks: Int
    let blockMilestone: String

    /// `WarmUpGate.elapsed(since:now:)`, already formatted. A VALUE, so this
    /// screen owns no clock and a catalog frame is deterministic.
    let elapsed: String

    // Check in — solo only (spec §2's path is check-in → warm-up).
    var showsCheckIn: Bool = false
    var isCheckingIn: Bool = false
    var canCheckIn: Bool = true
    var checkInOpensAtText: String = ""
    var onCheckIn: () -> Void = {}

    var onStartLifting: () -> Void = {}
    var onAcceptSuggestion: () -> Void = {}
    var onDeclineSuggestion: () -> Void = {}
    /// True while a `markWarmupReady` / `startLifting` round trip is open.
    var isStarting: Bool = false

    private var warmCount: Int { warmthRows.filter(\.isWarm).count }

    private var stillWarming: [String] {
        warmthRows.filter { !$0.isWarm && !$0.isYou }
            .map { SessionCopy.firstName($0.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if isSolo { soloBody } else { crewBody }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
            }
            foot
        }
        .background(theme.bg)
    }

    // MARK: - Solo (`warmup-solo-v2`)

    /// The whole day with Coach's line INSIDE the plan card, then where the
    /// block stands, then the clock.
    @ViewBuilder
    private var soloBody: some View {
        SessionPlanCardWithSuggestion(
            kicker: "TODAY",
            rungHeadline: rungHeadline,
            rungDetail: rungDetail,
            rows: planRows,
            suggestion: coachLine,
            // Nobody else is here, so nothing needs saying about who can see
            // it — `Only you see this.` on a solo screen is noise.
            isPrivate: false,
            onAccept: onAcceptSuggestion,
            onDecline: onDeclineSuggestion)
        // Absent entirely when there is no block behind the session — a
        // strip reading WEEK 0 OF 0 is not a state, and a lifter without an
        // enrolled block has no ladder to be on. (Production passes 0 today;
        // the block's rung reaching this screen is Phase B's.)
        if blockWeeks > 0 {
            BlockLadderStrip(week: blockWeek, weeks: blockWeeks,
                             milestone: blockMilestone)
        }
        WarmUpClockStrip(elapsed: elapsed)
    }

    // MARK: - Crew (`warmup-crew`)

    /// Who's warm, then the plan, then the clock. The readiness row is what
    /// crew presence adds; the order below it is the solo order minus the
    /// block strip, which is a personal fact. Coach's PRIVATE line is
    /// Phase B's: `CoachSuggestionBlock`, the type that used to render it
    /// here, had no path anywhere in the app after R-17 (production and
    /// both fixtures always pass `coachLine == nil`) and was deleted
    /// (review push-5 N4); `coachLine` itself stays, still read by
    /// `soloBody`, for Phase B's re-add with the readiness signal.
    @ViewBuilder
    private var crewBody: some View {
        SessionReadinessRow(rows: warmthRows,
                            kicker: SessionCopy.whosWarm,
                            count: WarmUpGate.warmCaption(warm: warmCount,
                                                          total: warmthRows.count))
        SessionPlanCard(kicker: SessionCopy.theSession,
                        rungLine: rungHeadline,
                        rows: planRows)
        WarmUpClockStrip(elapsed: elapsed)
    }

    // MARK: - The foot

    /// The talk dock, then the one accent primary (rule 6 gives the talk
    /// control its home directly above the primary).
    ///
    /// SOLO CARRIES CHECK IN ABOVE IT when the session has not started —
    /// spec §2's path is check-in → warm-up, and a scheduled solo session
    /// never passes through a lobby to find that button (plan task S10).
    private var foot: some View {
        VStack(spacing: 0) {
            GSDivider()
            VStack(spacing: 8) {
                if showsCheckIn {
                    SessionCheckInControl(isCheckingIn: isCheckingIn,
                                          canCheckIn: canCheckIn,
                                          opensAtText: checkInOpensAtText,
                                          onTap: onCheckIn)
                }
                if !isSolo {
                    PTTDockRow(otherParticipantNames: warmthRows
                        .filter { !$0.isYou }.map(\.name),
                               onRetry: { Task { await VoiceRoomService.shared.retry() } })
                }
                startLifting
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 22)
            .background(theme.bg)
        }
    }

    /// The screen's ONE accent primary, and it stays LIVE for the leader
    /// while somebody is still warming up — spec §3.2 lets the leader move on.
    /// The note beneath is where that costs something.
    private var startLifting: some View {
        VStack(spacing: 7) {
            Button(action: onStartLifting) {
                HStack {
                    if isStarting {
                        ProgressView()
                            .controlSize(.small)
                            .tint(theme.bg)
                        Text("Starting…")
                            .font(GSFont.bold(15, relativeTo: .body))
                    } else {
                        Text("START LIFTING")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .tracking(0.6)
                    }
                }
                .foregroundStyle(theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 10.5)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.gs3D(face: isStarting ? theme.accent600 : theme.accent,
                               cornerRadius: GSMetrics.radiusSm))
            .disabled(isStarting)

            if let note = WarmUpGate.leaderNote(isOrganizer: isOrganizer,
                                                stillWarming: stillWarming) {
                Text(note)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .frame(maxWidth: .infinity, alignment: .center)
            }
        }
    }
}
