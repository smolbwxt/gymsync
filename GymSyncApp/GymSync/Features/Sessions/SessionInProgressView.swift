import SwiftUI

/// THE STYLE ROUTER (plan task S5). `LobbyView` navigates here through
/// `SessionRunnerView` — that view's `:149` is this router's ONLY caller —
/// and this is where a reader learns that a crew session moves in three
/// different ways (spec §1, owner decision 1).
///
/// The `switch` is deliberately NOT collapsed to a single line with `style:
/// session.style`. `SessionLiveView` hangs its presentations off `style`
/// inside the body — the round wait and spotter mode for `.rounds` (plan
/// tasks S6 and S8), Together's clock (S9), Freestyle's rail (S10) — and the
/// three arms written out are what make that visible from the route in.
///
/// `session.style` is the row's own column, frozen by
/// `private.session_round_guard` the moment `lifting_started_at` is stamped
/// (plan task D3), so a session that has begun cannot change arm underneath
/// the body it pushed.
///
/// Signature is UNCHANGED (session + participants parameters preserved).
struct SessionInProgressView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    var body: some View {
        // Phase O Task 5 (3e follow-up queue item 6): this router is the
        // ONLY route into SessionLiveView from LobbyView (per this file's
        // own header comment) — `voicePersistsOnPop: true` tells that view's
        // `.onDisappear` that backing out lands back on THIS SAME session's
        // Lobby, which will reclaim the still-connected voice room instead of
        // needing a fresh reconnect.
        switch session.style {
        case .rounds:
            SessionLiveView(session: session, style: .rounds, voicePersistsOnPop: true)
        case .freestyle:
            SessionLiveView(session: session, style: .freestyle, voicePersistsOnPop: true)
        case .together:
            SessionLiveView(session: session, style: .together, voicePersistsOnPop: true)
        }
    }
}
