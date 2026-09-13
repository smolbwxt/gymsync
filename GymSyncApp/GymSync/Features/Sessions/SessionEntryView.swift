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

    var body: some View {
        Group {
            if fetchFailed {
                LobbyView(session: session)
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
            LobbyView(session: session)
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
