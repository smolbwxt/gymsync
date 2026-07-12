import SwiftUI

/// Thin router: LobbyView navigates here; we embed the real live UI.
/// Signature is UNCHANGED (session + participants parameters preserved).
struct SessionInProgressView: View {
    let session: WorkoutSession
    let participants: [(participant: SessionParticipant, profile: Profile)]

    var body: some View {
        GroupSessionLiveView(session: session)
    }
}
