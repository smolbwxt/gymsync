import SwiftUI

@Observable
@MainActor
final class AppState {
    /// Singleton (matches AuthService/SupabaseService's convention) rather
    /// than a per-RootView `@State` instance — AppDelegate (a plain
    /// UIApplicationDelegate, not a View) needs to read/write `selectedTab`,
    /// `pendingRoute`, and the active-context IDs from
    /// `willPresent`/`didReceive response:`, and there's no @Environment
    /// hook available outside the view tree to reach a per-View instance.
    static let shared = AppState()
    private init() {}

    enum Tab: Hashable { case home, library, social, stats, you }
    var selectedTab: Tab = .home

    // Set to the user's profile once loaded post-sign-in.
    var currentProfile: Profile?

    // MARK: - Push deep-link routing (Phase 3d Task 5)

    /// Minimal v1 deep-link target: set by AppDelegate on a notification tap
    /// (default tap or a `.foreground` action) and consumed — then cleared —
    /// by whichever tab root view owns the destination (HomeView for
    /// lobby/session, SocialTabView for chat/friends).
    ///
    /// `.lobby` and `.session` both resolve to the same destination
    /// (`LobbyView(session:)`) on the consuming side — LobbyView is already
    /// the app's single entry point for a session regardless of its current
    /// state (see HomeView's existing `upcomingSection` NavigationLink,
    /// which routes every session there whether scheduled or in_progress),
    /// so there's no need for a separate "already in progress" destination
    /// in v1. Kept as two cases anyway so the category → route mapping in
    /// AppDelegate stays self-documenting (OPEN_LOBBY → .lobby, OPEN_SESSION
    /// → .session).
    enum PendingRoute: Equatable {
        case lobby(sessionID: UUID)
        case session(sessionID: UUID)
        case chat(groupID: UUID)
        case friends
    }
    var pendingRoute: PendingRoute?

    // MARK: - Active-context suppression (push-dossier.md §B.7)
    //
    // Set/cleared by GroupSessionLiveView / ChatView on appear/disappear.
    // AppDelegate's `willPresent` compares a push's thread-id against these
    // to suppress the banner when the user is already looking at the same
    // session/chat live (they're already seeing it via Realtime).
    var activeSessionID: UUID?
    var activeChatGroupID: UUID?
}
