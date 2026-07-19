import SwiftUI

/// Thin router: LobbyView navigates here; we embed the real live UI.
/// Signature is UNCHANGED (session + participants parameters preserved).
struct SessionInProgressView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    var body: some View {
        // Phase O Task 5 (3e follow-up queue item 6): this router is the
        // ONLY route into GroupSessionLiveView from LobbyView (per this
        // file's own header comment) — `voicePersistsOnPop: true` tells
        // that view's `.onDisappear` that backing out lands back on THIS
        // SAME session's Lobby, which will reclaim the still-connected
        // voice room instead of needing a fresh reconnect.
        GroupSessionLiveView(session: session, voicePersistsOnPop: true)
    }
}
