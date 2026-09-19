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
    ///
    /// Redesign Phase 1 (four-tab reorientation, 2026-08): `.library` and
    /// `.stats` left the tab bar — their content is reachable from the You
    /// tab's widget grid (`YouTabView`).
    ///
    /// Three-tab restructure (owner-approved proposal, 2026-08-12): `.shop`
    /// dissolved — its weekly rack merged into You's grid, Campaigns/
    /// Programs browse behind You's PROGRAMS widget, the inert Pro/Coach
    /// rows became You's PRO widget. `.social` is titled CREWS in the dock.
    enum Tab: Hashable, CaseIterable { case home, social, trainer, you }
    var selectedTab: Tab = .home

    /// Trainer arm T3: true when this account has clients or open invite
    /// codes — injects the TRAINER tab. Set at launch (RootView) and kept
    /// fresh by CoachingView/TrainerTabView loads.
    var isTrainer = false

    /// Onboarding COACH offer (owner decision 2026-08-13: the wizard caps
    /// onboarding). Set by WelcomeView's "Let Coach build your week"
    /// shortcut; RootView consumes it to present the wizard sheet — after
    /// the first-run walkthrough, which owns the first modal slot.
    var pendingCoachOffer = false

    /// Cold-launch readiness (owner 2026-08-16: the launch overlay lifted
    /// before below-the-fold content had settled). Tab roots wrap their
    /// INITIAL fetch in begin/end; RootView holds the overlay past the
    /// brand moment while this is non-zero — capped, so a hung request
    /// can never wedge the reveal.
    var launchFetchesInFlight = 0
    func beginLaunchFetch() { launchFetchesInFlight += 1 }
    func endLaunchFetch() { launchFetchesInFlight = max(0, launchFetchesInFlight - 1) }

    // Set to the user's profile once loaded post-sign-in.
    var currentProfile: Profile?

    // MARK: - Push deep-link routing (Phase 3d Task 5)

    /// Minimal v1 deep-link target: set by AppDelegate on a notification tap
    /// (default tap or a `.foreground` action) and consumed — then cleared —
    /// by whichever tab root view owns the destination (HomeView for
    /// lobby/session, SocialTabView for chat/friends).
    ///
    /// `.lobby` and `.session` both resolve to the same destination
    /// (`SessionEntryView(session:)`, plan task S10) on the consuming side —
    /// it is the app's single entry point for a session regardless of its
    /// current state, deciding lobby vs. warm-up vs. live itself (see
    /// HomeView's existing `upcomingSection` NavigationLink, which routes
    /// every session there whether scheduled or in_progress), so there's no
    /// need for a separate "already in progress" destination in v1. Kept as
    /// two cases anyway so the category → route mapping in AppDelegate stays
    /// self-documenting (OPEN_LOBBY → .lobby, OPEN_SESSION → .session).
    enum PendingRoute: Equatable {
        case lobby(sessionID: UUID)
        case session(sessionID: UUID)
        case chat(groupID: UUID)
        case friends
    }
    var pendingRoute: PendingRoute?

    // MARK: - Active-context suppression (push-dossier.md §B.7)
    //
    // Set/cleared by SessionLiveView / ChatView on appear/disappear.
    // AppDelegate's `willPresent` compares a push's thread-id against these
    // to suppress the banner when the user is already looking at the same
    // session/chat live (they're already seeing it via Realtime).
    var activeSessionID: UUID?
    var activeChatGroupID: UUID?

    /// Set by SessionLiveView right before it pops after ANY exit
    /// (leave, recap Done, member-side completion) — the lobby underneath
    /// consumes it to pop itself too, so every session exit lands on Home
    /// instead of a stale lobby (user 2026-08-01).
    var sessionExitToHomeID: UUID?

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
    // (ChatView, SessionLiveView, LobbyView) unsubscribes Realtime
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

    // MARK: - Live solo session recovery (user report 2026-08-11)
    //
    // NO LONGER THE RESUME MECHANISM (Phase C1 S5). An ad-hoc solo session
    // now runs in the one body (`SessionLiveView`, plan tasks S1-S4) inside a
    // `.fullScreenCover` it cannot be swiped out of, and `SessionLiveView.
    // onAppear` registers `liveGroupSession` below unconditionally — for a
    // roster of one too.
    //
    // ITS ONLY REMAINING WRITERS AND READERS ARE BEHIND `#if DEBUG` (fix
    // round 2 corrected this note, which named `SessionRepository.startSolo`
    // as a writer — it never was; the field was written by the VIEW, not by
    // the repository, and `startSolo` has never mentioned `AppState`):
    // `WorkoutSessionView` writes it at `:3955`, reads it at `:3936` for the
    // hotfix adopt and clears it at `:4749-4750`, and `CatalogHostView:1941`
    // pre-seeds it — and that view has exactly one construction site, inside
    // `#if DEBUG`. So `MainTabView`'s pill and `RootView`'s resume cover no
    // longer read it; S5 removed that dead branch. **Not deleted here**: the
    // old view still constructs it, and it retires with that view in C2.
    //
    // What follows is the ORIGINAL rationale, kept for that reader: a solo
    // session used to live inside a plain `.sheet` (Home's RoutinePickerSheet
    // → pushed WorkoutSessionView) — swiping the sheet down destroyed every
    // `@State` in it with no re-entry route, leaving an in_progress session
    // permanently orphaned. This handle was the durable trace, registered the
    // moment `SessionRepository.startSolo` succeeded and cleared only when
    // the session actually completed.
    //
    // Group sessions deliberately have no handle here: they are pushes with
    // the back button hidden (no swipe-down exists) and Home's "Join" hero +
    // check-in widget already re-enter an in_progress group session.
    /// THE FOUR `let`s BELOW ARE THE SESSION'S IDENTITY, captured once.
    ///
    /// THE SWAP MIRROR IS GONE (Phase C1, plan task S1). The 2026-09-18
    /// hotfix added a `swapOverrides` field here so the layer would survive
    /// a swipe-down, and said in this very comment that it did NOT survive
    /// an OS termination and that the durable layer — a row keyed by
    /// routine SLOT, read back before the cursor is derived — was Phase C's
    /// job. That row now exists (`session_participants.self_swaps`,
    /// 20260919000101) and `WorkoutSessionView` reads and writes it
    /// directly, so a second in-memory copy could only ever drift from it.
    ///
    /// THE REST WINDOW WAS NEVER HERE EITHER. It belongs to
    /// `LiveSessionTimerStore`, which the group body has used for the same
    /// symptom since the 2026-08-14 report. One store, one shape, both
    /// bodies.
    struct LiveSoloSession: Identifiable, Equatable {
        let session: WorkoutSession
        let routine: Routine?
        let routineExercises: [RoutineExercise]
        let allExercises: [Exercise]
        var id: UUID { session.id }
        static func == (lhs: Self, rhs: Self) -> Bool { lhs.session.id == rhs.session.id }
    }
    var liveSoloSession: LiveSoloSession?

    /// Group counterpart (owner 2026-08-12: "you can't swipe down in a group
    /// session like you can for a solo session"). Registered by
    /// SessionLiveView.onAppear, cleared ONLY by a deliberate exit
    /// (`exitToHome()` — leave, recap Done, member-side completion) or by
    /// LobbyView noticing a terminal state — NOT by onDisappear, which now
    /// also fires on a recoverable swipe-down. While set and the live view
    /// is off-screen, MainTabView's SESSION LIVE pill routes back through
    /// the lobby deep-link (`pendingRoute = .lobby`), whose existing
    /// auto-forward re-presents the live sheet.
    ///
    /// NOW THE ONLY LIVE-PILL HANDLE (Phase C1 S5, decision 6). Registration
    /// is unconditional in `SessionLiveView.onAppear` — it fires for a roster
    /// of one exactly as it does for a crew — so this single struct is what
    /// both an ad-hoc solo session and a group session ride back in on.
    struct LiveGroupSession: Equatable {
        let sessionID: UUID
        let title: String

        /// THE PILL'S TITLE, PURE (Phase C1 S5). `title` is computed by the
        /// caller (`SessionLiveView.onAppear`) before this struct is built,
        /// through this function, so the ONE rule — a solo lifter has no
        /// crew, and must never read "Crew session" — lives in one place and
        /// is unit-testable outside the view. `routineName` wins either way;
        /// only the no-routine fallback differs by whether the session is a
        /// party of one (`SessionLiveView.hidesCrewFurniture`, S4's roster
        /// law — a scheduled solo session gets the same honest fallback).
        static func pillTitle(routineName: String?, isSolo: Bool) -> String {
            routineName ?? (isSolo ? "Freeform workout" : "Crew session")
        }
    }
    var liveGroupSession: LiveGroupSession?
}

/// THE LIVE PILL'S TITLE/ROUTE DECISION, PURE (Phase C1 S5). `MainTabView`'s
/// `safeAreaInset` used to branch on two optionals (`liveSoloSession` then
/// `liveGroupSession`) inline in its `body`; the first branch is now dead
/// (`AppState.liveSoloSession`'s doc comment explains why) and this is what
/// is left of the decision once it is. Extracted so the answer — show
/// nothing, or show this title and resume this session — is testable without
/// a view.
enum LivePillDecision: Equatable {
    case hidden
    case resume(sessionID: UUID, title: String)

    static func decide(liveGroupSession: AppState.LiveGroupSession?) -> LivePillDecision {
        guard let liveGroupSession else { return .hidden }
        return .resume(sessionID: liveGroupSession.sessionID, title: liveGroupSession.title)
    }
}
