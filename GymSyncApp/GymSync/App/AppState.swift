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

    /// `CaseIterable` so `MainTabView` can iterate every tab to decide which
    /// are mounted (tab retention, RootView.swift) rather than switching on
    /// the selected one.
    enum Tab: Hashable, CaseIterable { case home, library, social, stats, you }
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

    // MARK: - Tab-switch transient-state (Task 6 item 2, reliability/debt
    // roll-up — .superpowers/sdd/progress.md:158-163)
    //
    // ADJUDICATION: MainTabView (RootView.swift) is a bare `ZStack` that
    // mounts only `switch appState.selectedTab { ... }` — every screen
    // below the tab root is destroyed and rebuilt on tab switch. A prior
    // review (progress.md:158) considered the alternative — keeping every
    // tab alive via a ZStack-of-all-tabs + opacity — and REJECTED it:
    // "keep-alive ZStack alternative breaks onDisappear-driven realtime
    // unsubscribe (worse bug class)". Every live-data screen in this app
    // (ChatView, GroupSessionLiveView, LobbyView) unsubscribes Realtime
    // channels / LiveKit rooms from `onDisappear`; keep-alive would leave
    // those channels open indefinitely for a backgrounded tab, trading a
    // small UX papercut for a resource leak and stale-data class of bug.
    // Recreation-on-switch stays the standing decision.
    //
    // The honest fix is therefore targeted, not structural: lift the ONE
    // piece of transient state whose loss is a real content-loss risk
    // (not just a re-navigation annoyance) into this already-existing
    // "cross-view ephemeral state" home (same idiom as
    // `activeChatGroupID`/`activeSessionID` above). Candidates considered:
    //   - Chat draft text: a half-typed message is genuine USER CONTENT —
    //     losing it mid-composition to an incidental tab switch (e.g. to
    //     check Home while typing) is a real, previously-reported UX
    //     complaint class. PICKED.
    //   - Nav depth (which screen you'd drilled into): real loss, but
    //     fixing it honestly means persisting a `NavigationPath` per tab
    //     (or promoting selection state for every pushed screen) — a
    //     structural change closer in cost to the keep-alive redesign this
    //     item exists to avoid. Left as documented, accepted debt.
    //   - HomeView join-code field: a short, quick-to-retype string with
    //     no composition cost — lowest-severity of the three named in the
    //     DEVICE-QA note. Not picked.
    //
    // Keyed by ChatView.Scope's own `draftKey` (group id for a group's
    // persistent chat, session id for a session sub-thread — see that
    // computed property's doc comment) so distinct chats never collide.
    // Entries are removed (not left as "") once a draft is sent or
    // abandoned empty — see ChatView's onAppear/onDisappear.
    var chatDrafts: [UUID: String] = [:]
}
