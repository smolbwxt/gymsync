import SwiftUI

// MARK: - SessionRoute / SessionRouter (plan task S10)
//
// Spec §2, owner decision 3: a scheduled SOLO session has no lobby.
// `LobbyView`'s own doc comment used to call it "the app's single entry
// point for a session regardless of its current state" — true only because
// nothing needed to skip it yet. This router is what keeps that claim true
// of ONE type instead of the same branch copied into every call site that
// opens a session.

/// Which screen a session opens to. Pure and tested
/// (`SessionEntryRouteTests`) — `SessionEntryView` below and its four call
/// sites never re-derive this law themselves.
enum SessionRoute: Equatable {
    /// A crew, before Start.
    case lobby
    /// A solo session before Start, or anyone during warm-up.
    case warmUp
    /// Lifting has begun.
    case live
}

enum SessionRouter {
    /// `participantCount` and `roomCode` decide solo (`SessionShape.isSolo`,
    /// task S3) — never `group_id`: a `.friends` or `.code` session also
    /// leaves `group_id` nil (`ScheduleSessionView.swift:778-786`), so that
    /// column does not mean "solo".
    static func route(state: String,
                      liftingStartedAt: Date?,
                      participantCount: Int,
                      roomCode: String?) -> SessionRoute {
        if state == "completed" || state == "abandoned" {
            // The live view already self-presents the recap; this router
            // adds no new terminal screen.
            return .live
        }
        if WarmUpGate.isWarmingUp(state: state, liftingStartedAt: liftingStartedAt) {
            return .warmUp
        }
        // CI fix round (898e624 review): `in_progress` with lifting already
        // started fell through to `.lobby` — nothing above catches it, since
        // `isWarmingUp` is false once `liftingStartedAt` is set. `.live` is
        // right and belongs AHEAD of the solo check: once lifting has begun,
        // `SessionRunnerView` routes itself to `SessionInProgressView`
        // (`SessionRunnerView.warmingUp`) regardless of solo vs. crew, so
        // solo no longer decides anything for an in-progress session.
        if state == "in_progress" {
            return .live
        }
        if SessionShape.isSolo(participantCount: participantCount, roomCode: roomCode) {
            return .warmUp
        }
        return .lobby
    }
}

// MARK: - SessionEntryView

/// The app's one entry point for a session, regardless of its current state
/// (plan task S10) — the claim `LobbyView` used to carry alone, until a
/// scheduled solo session needed to skip the lobby entirely and a `LobbyView`
/// stopped being able to keep it true by itself.
///
/// Fetches `SessionRepository.participants(sessionID:)` ONCE — the count is
/// what `SessionRouter` needs, and no cheaper signal is honest — then hands
/// the fetched rows down to whichever destination it picks, so that screen
/// does not refetch on first paint.
struct SessionEntryView: View {
    let session: WorkoutSession

    @Environment(\.gsTheme) private var theme

    /// `nil` while resolving. Once set, `SessionRouter` has already decided
    /// where we're going and `body` never revisits the question.
    @State private var participants: [(participant: SessionParticipant, profile: Profile)]?
    /// The shipped behaviour on a failed fetch (S10 brief): fall through to
    /// the lobby, which does its own fetch in `reload()` and shows its own
    /// error line — this view invents no second one.
    @State private var fetchFailed = false

    /// A SOLO SESSION IS NEVER SENT TO A LOBBY, not even by a failure (fix
    /// round 1 / N5). The fall-through above is right for a crew — a lobby
    /// refetches and says so — but inside a non-dismissible cover it put a
    /// lifter who is on their own in front of a crew's waiting room for a
    /// session of one. Newly reachable, because this is the first ad-hoc path
    /// through this view.
    ///
    /// The symmetric destination is `SessionRunnerView`, which retries on
    /// exactly the same terms the lobby would: its five-second warm-up poll
    /// refetches `participants`, and once lifting has started
    /// `SessionLiveView.reload()` does. It is handed an EMPTY roster, which
    /// is the truth — the fetch failed — and which it heals itself within one
    /// poll.
    private var isSoloByConstruction: Bool {
        SoloSessionShape.isSoloByConstruction(groupID: session.groupID,
                                              roomCode: session.roomCode,
                                              scheduledFor: session.scheduledFor)
    }

    var body: some View {
        Group {
            if fetchFailed {
                if isSoloByConstruction {
                    SessionRunnerView(session: session, participants: [])
                } else {
                    LobbyView(session: session)
                }
            } else if let participants {
                destination(participants: participants)
            } else {
                // A quiet centred spinner — the only thing this view ever
                // shows itself, and only for as long as one round trip.
                ProgressView()
                    .tint(theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(theme.bg)
        .task { await resolve() }
    }

    @ViewBuilder
    private func destination(
        participants: [(participant: SessionParticipant, profile: Profile)]
    ) -> some View {
        switch SessionRouter.route(state: session.state,
                                   liftingStartedAt: session.liftingStartedAt,
                                   participantCount: participants.count,
                                   roomCode: session.roomCode) {
        case .lobby:
            LobbyView(session: session, initialParticipants: participants)
        case .warmUp, .live:
            // `.live` routes here too: the runner routes to
            // `SessionInProgressView` itself once lifting has begun
            // (`SessionRunnerView.warmingUp`) — this view does not
            // duplicate that check.
            SessionRunnerView(session: session, participants: participants)
        }
    }

    @MainActor
    private func resolve() async {
        guard participants == nil, !fetchFailed else { return }
        do {
            participants = try await SessionRepository.participants(sessionID: session.id)
        } catch {
            fetchFailed = true
        }
    }
}
