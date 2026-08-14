import SwiftData
import SwiftUI

struct RootView: View {
    @Environment(AuthService.self) private var auth
    // AppState is now a singleton (Phase 3d Task 5) so AppDelegate can reach
    // the same instance from outside the view tree — see AppState.shared's
    // doc comment.
    @State private var appState = AppState.shared
    // Singleton (Canvas Completion Task 5), same convention as `appState`
    // above — reading `themeStore.current` here (rather than a hardcoded
    // `.midnight`) is what makes the whole app re-render live when
    // `AppearanceView` calls `ThemeStore.select(_:)`.
    @State private var themeStore = ThemeStore.shared
    // Phase O Task 2: app-level foreground hook for the calendar reconcile
    // sweep (`EventKitBridge.reconcile()`) — see the `.onChange` below for
    // why this lives HERE rather than following the per-screen `scenePhase`
    // idiom every other consumer uses (HomeView/YouTabView/LobbyView/
    // GroupSessionLiveView/ChatView/SocialTabView/PushPrimingView/
    // NotificationPreferencesView all read `@Environment(\.scenePhase)`
    // themselves).
    @Environment(\.scenePhase) private var scenePhase
    // Phase O Task 3 — offline set-log queue. `RootView` is the one view
    // instance alive for the whole signed-in session (same rationale as the
    // calendar-reconcile hook above), so it's the right place to both
    // configure the queue's ModelContext once and drive its two
    // app-level replay triggers (connectivity restored, app foreground).
    @Environment(\.modelContext) private var modelContext
    @State private var connectivity = ConnectivityMonitor.shared

    // First-time walkthrough (redesign 2026-07-23, user-requested): shown once
    // per device, the first time the signed-in main app appears (i.e. after
    // sign-in + profile onboarding). Both Skip and "Get started" set the flag.
    // Key comes from OneShotFlags so the QA "replay first-run tips" reset
    // can never drift from what this actually reads.
    @AppStorage(OneShotFlags.walkthroughKey) private var hasSeenWalkthrough = false
    @State private var showWalkthrough = false

    /// Onboarding COACH offer — the wizard sheet queued behind the
    /// walkthrough (SwiftUI presents one modal at a time; the walkthrough
    /// owns the first slot for a fresh signup). Fires either on main-app
    /// appear (walkthrough already seen) or from the walkthrough's
    /// completion, whichever consumes `appState.pendingCoachOffer`.
    @State private var showCoachOffer = false

    /// Launch overlay gate. `RootView` is alive for the whole app run, so this
    /// stays true after the first reveal — a later sign-out/sign-in transition
    /// does not replay the animation.
    @State private var launchOverlayFinished = false

    var body: some View {
        Group {
            switch auth.state {
            case .pending:
                ProgressView().controlSize(.large)
            case .signedOut:
                SignInView()
            case .signedIn(let userID):
                if appState.currentProfile == nil {
                    OnboardingCoordinator(userID: userID)
                        .environment(appState)
                } else {
                    MainTabView()
                        .environment(appState)
                        // Cold-launch brand moment: every tab mounts and fetches
                        // underneath this, so the first tap on any tab lands on a
                        // settled screen instead of one still assembling itself.
                        // Signed-in only — sign-in and onboarding own their own
                        // first impression.
                        .overlay {
                            if !launchOverlayFinished {
                                LaunchLoadingOverlay {
                                    withAnimation(.easeOut(duration: 0.35)) {
                                        launchOverlayFinished = true
                                    }
                                }
                                .transition(.opacity)
                            }
                        }
                        .onAppear {
                            if !hasSeenWalkthrough {
                                showWalkthrough = true
                            } else if appState.pendingCoachOffer {
                                appState.pendingCoachOffer = false
                                showCoachOffer = true
                            }
                        }
                        .fullScreenCover(isPresented: $showWalkthrough) {
                            WalkthroughView {
                                hasSeenWalkthrough = true
                                showWalkthrough = false
                                if appState.pendingCoachOffer {
                                    appState.pendingCoachOffer = false
                                    showCoachOffer = true
                                }
                            }
                            .environment(\.gsTheme, themeStore.current.withAccent(themeStore.accent))
                        }
                        .sheet(isPresented: $showCoachOffer) {
                            // Same explicit environment injection as the
                            // walkthrough cover — presentation content does
                            // not reliably inherit it here.
                            NavigationStack {
                                CoachWizardView()
                            }
                            .environment(appState)
                            .environment(\.gsTheme, themeStore.current.withAccent(themeStore.accent))
                        }
                }
            }
        }
        // ── Live theme chrome ──
        // `isDark` covers modernist/ink (light palettes) alongside
        // midnight/arena (dark) — see GSTheme.isDark's doc comment for the
        // luminance-based determination.
        .preferredColorScheme(themeStore.current.isDark ? .dark : .light)
        // Redesign: inject the palette with its accent ramp overridden by the
        // user's chosen accent, so every component reading `theme.accent*` picks
        // up the personal accent without being individually rewired.
        .environment(\.gsTheme, themeStore.current.withAccent(themeStore.accent))
        // The precise `GSAccent` too, for components that need base/soft/onAccent
        // distinctly (e.g. GSAccentPicker). `themeStore` is @Observable, so a
        // `selectAccent(_:)` re-renders the whole tree with both updated.
        .environment(\.gsAccent, themeStore.accent)
        // Tint every NavigationStack's bar items — chiefly the back button —
        // with the theme accent. Without this, SwiftUI falls back to the
        // system-blue environment tint, so pushed screens (Appearance,
        // Notifications, …) showed an iOS-blue "‹ Back" against the themed
        // chrome. UINavigationBar.appearance().tintColor alone does NOT reach
        // the SwiftUI back button; this environment tint does.
        .tint(themeStore.accent.base)
        .background(themeStore.current.bg.ignoresSafeArea())
        // Phase O Task 2: calendar reconcile sweep, app-foreground gated.
        // `RootView` is the one view instance that's alive for the entire
        // signed-in session regardless of which tab is selected —
        // `MainTabView.body` below only ever mounts the CURRENTLY selected
        // tab (`switch appState.selectedTab { case .home: HomeView() ... }`
        // inside a bare `ZStack`, not a `TabView` that keeps every tab
        // alive), so a `scenePhase` hook placed on any one tab's own view
        // (the idiom every other consumer above uses) would silently miss
        // every foreground transition that happens while a DIFFERENT tab is
        // selected. Hooking here instead guarantees "fires on every
        // foreground transition" regardless of the user's current screen —
        // the actual requirement for a sweep that has to run app-wide.
        // `.onChange(of: scenePhase)` itself already fires at most once per
        // transition (SwiftUI semantics, same as every other consumer's
        // `guard scenePhase == .active else { return }` idiom); `reconcile()`
        // additionally guards its own re-entrancy (`EventKitBridge.
        // isReconciling`) in case two transitions land close together.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            guard case .signedIn = auth.state else { return }
            guard CalendarSyncPrefsStore.isEnabled() else { return }
            Task { await EventKitBridge.reconcile() }
        }
        // Phase O Task 3 — configure the queue's ModelContext once, then
        // attempt an initial drain (covers "was offline when the app was
        // last force-quit, is online again by the time it relaunches").
        .task {
            OfflineSetLogQueue.shared.configure(modelContext: modelContext)
            guard case .signedIn = auth.state else { return }
            await OfflineSetLogQueue.shared.replay()
            // Rotation guard (20260801000001): a turn advance owed from an
            // offline group set drains on the SAME triggers as the set queue.
            // Safe to repeat — the RPC no-ops once the rotation has moved on.
            await PendingTurnAdvanceStore.shared.replay()
        }
        // Replay trigger 1/4 — auth-state transition to .signedIn. Phase O
        // Task 3 fix wave 1 (reviewer Finding 2): the `.task` above gates on
        // `auth.state == .signedIn` at the single moment it first runs, but
        // `AuthService.state` starts `.pending` and resolves asynchronously
        // (`AuthService.bootstrap()`, Services/AuthService.swift ~22-54,
        // kicked off fire-and-forget from `private init()` ~18-20) — a cold
        // launch that's already online can have `.task` evaluate its guard
        // WHILE bootstrap is still in flight, silently skipping the launch
        // drain. Before this hook, nothing else re-checked: if connectivity
        // and scenePhase never change afterward (device already online,
        // app already foreground), that launch's queued sets would sit
        // undrained indefinitely. This hook closes the gap by observing
        // every auth-state transition and draining whenever the NEW state
        // is `.signedIn` — including the ordinary sign-in transition, where
        // it's a harmless extra call: `OfflineSetLogQueue.replay()` is
        // idempotent and reentrancy-guarded (`isReplaying`, Services/
        // OfflineSetLogQueue.swift — declared ~154, checked/set ~218-219;
        // shifted again by the gate fix below, re-verified post-edit same
        // as fix wave 2's own NEW-2 correction did), so overlapping with
        // the `.task`'s own call is a no-op, not a double-submit.
        //
        // Gate fix (shared-device queue-scoping finding, task-3-report.md
        // "## Gate fix"): `OfflineSetLogQueue.refreshPendingIDs()` is now
        // ALSO re-called on every transition through this same hook — not
        // just from `configure()`'s one-time call in the `.task` above.
        // `pendingSetLogIDs` drives the "syncing" UI badges
        // (`WorkoutSessionView.loggedSetsTable`, `GroupSessionLiveView.
        // feedRow`) and, like `replay()`, is now scoped to the CURRENT
        // signed-in user (`OfflineSetLogQueue.swift`'s class doc comment).
        // Without re-syncing here, a second user signing into a shared
        // device would keep seeing whatever was left in memory from the
        // first user's session until the next `configure()` call (which
        // never happens again post-launch) — this hook is the one place
        // guaranteed to fire on every sign-in AND sign-out.
        .onChange(of: auth.state) {
            OfflineSetLogQueue.shared.refreshPendingIDs()
            // Debt-zero gate IMPORTANT-1: the replay-failure surface is
            // per-identity state and must not survive an auth transition —
            // user B on a shared device must never see user A's "a set
            // couldn't sync" banner (same shared-device doctrine as
            // signOut()'s chatDrafts/pendingRoute clears and this hook's
            // own refreshPendingIDs re-scope directly above).
            OfflineSetLogQueue.shared.clearLastPermanentFailure()
            guard case .signedIn = auth.state else { return }
            Task {
                await OfflineSetLogQueue.shared.replay()
                await PendingTurnAdvanceStore.shared.replay()
            }
        }
        // Replay trigger 2/4 — connectivity restored. `.onChange` fires only
        // on a transition, so this is exactly the "path becomes satisfied"
        // edge (not a repeat while already online, not the offline edge).
        .onChange(of: connectivity.isOnline) {
            guard connectivity.isOnline else { return }
            guard case .signedIn = auth.state else { return }
            Task {
                await OfflineSetLogQueue.shared.replay()
                await PendingTurnAdvanceStore.shared.replay()
            }
        }
        // Replay trigger 3/4 — app foreground. A SEPARATE `.onChange(of:
        // scenePhase)` block, deliberately not merged into the calendar
        // reconcile hook above — brief's explicit "do NOT duplicate the
        // reconcile throttle, add alongside": `EventKitBridge.isReconciling`
        // and `OfflineSetLogQueue`'s own reentrancy guard are independent,
        // unrelated concerns that just happen to share the same trigger
        // shape. Same "one instance alive all session" rationale as the
        // reconcile hook for why this lives on RootView rather than a
        // per-tab `scenePhase` read.
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            guard case .signedIn = auth.state else { return }
            Task {
                await OfflineSetLogQueue.shared.replay()
                await PendingTurnAdvanceStore.shared.replay()
            }
        }
        // Phase O Task 4 (Sentry, master spec §6.8.5) — refresh the
        // crash-time context snapshot on every foreground transition. A
        // SEPARATE `.onChange(of: scenePhase)` block, same rationale as the
        // calendar-reconcile and offline-queue-replay blocks above (each
        // keeps an unrelated concern in its own block instead of overloading
        // one closure). `SentryContext.refreshAppWide()` is a no-op whenever
        // Sentry isn't started (`CrashReporting.shared.isEnabled == false`,
        // today's DSN-absent default), so this costs nothing in the common
        // case. See `GroupSessionLiveView`'s own scenePhase hook for the
        // equivalent in-live-session refresh (has real session/roster data
        // this app-wide one can't see).
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            SentryContext.refreshAppWide()
        }
        // Replay trigger 4/4 — post-submit "cheap drain": NOT a RootView
        // hook. Fired inline, fire-and-forget, right after every successful
        // ONLINE set-log submit (WorkoutSessionView.swift ~726-731,
        // GroupSessionLiveView.swift's logSetAndAdvance/logSet cheap-drain
        // call sites) — opportunistically flushes anything still queued
        // from an earlier offline stretch now that a submit just proved
        // we're back online. Listed here only so this file's trigger
        // enumeration is the complete set (reviewer Finding 2's phrasing:
        // "signed-in transition, foreground, connectivity, post-submit").
    }
}

private struct MainTabView: View {
    @Environment(AppState.self) private var appState

    // Set true whenever a pushed descendant (LobbyView, ChatView, etc.) reports
    // `.gsHidesDock()` — see GSComponents.swift for the full rationale. Popping
    // back to a tab root (no more `.gsHidesDock()` contributors mounted) flips
    // this back to false via the same onPreferenceChange callback, restoring
    // the dock reliably regardless of push depth.
    @State private var isDockHidden = false

    /// Tabs that have been visited at least once. Perf (user report
    /// 2026-07-25: "everytime you click on a page, things load incrementally
    /// over a fraction of a second"): the previous `switch` mounted ONLY the
    /// selected tab, so every switch destroyed the outgoing screen and
    /// rebuilt the incoming one from zero — `@State` reset to empty, `.task`
    /// re-ran, and content re-appeared piecewise as each fetch landed. That
    /// teardown/rebuild, not network latency, was the perceived jank.
    ///
    /// Now a tab mounts and stays alive, so every switch is a pure visibility
    /// change with nothing to rebuild.
    ///
    /// EAGER since 2026-08-02 (user report: "click a tab and then see all the
    /// widgets kind of push each other around and populate asynchronously").
    /// This was deliberately lazy before, to avoid trading tab-switch jank for
    /// a slower cold start and four simultaneous fetch storms at launch — the
    /// launch overlay (`LaunchLoadingOverlay`, shown by `RootView`) is what
    /// changed the calculus: the cold-start cost is now paid ONCE behind a
    /// brand moment the user reads as intentional, and the fetch storm is the
    /// point rather than the problem, because it resolves while nobody is
    /// looking at a half-built screen.
    ///
    /// Safe because no tab root performs a "the user saw this" side effect at
    /// mount (audited 2026-08-02): read receipts live in `ChatView` (pushed,
    /// never mounted at launch), and the two `consumePendingRouteIfNeeded()`
    /// callers claim DISJOINT deep-link cases — Home takes `.lobby`/`.session`,
    /// Social takes `.friends`/`.chat` — so mounting both cannot race for one
    /// route.
    @State private var mountedTabs: Set<AppState.Tab> = Set(AppState.Tab.allCases)

    /// The live solo session being re-presented after the lifter swiped its
    /// sheet away (user report 2026-08-11: sessions were irrecoverable).
    /// Driven by the "SESSION LIVE" pill below; presents WorkoutSessionView
    /// in resume mode. A plain sheet ON PURPOSE — swiping it down again is
    /// harmless now, because `AppState.liveSoloSession` persists until the
    /// session completes and the pill just comes back.
    @State private var resumeTarget: AppState.LiveSoloSession?

    var body: some View {
        @Bindable var appState = appState
        ZStack {
            ForEach(AppState.Tab.allCases, id: \.self) { tab in
                if mountedTabs.contains(tab) {
                    tabContent(tab)
                        .opacity(appState.selectedTab == tab ? 1 : 0)
                        // A retained-but-hidden tab must not absorb touches
                        // or be reachable by VoiceOver — invisible is not the
                        // same as inert, and both of these are required for
                        // it to actually behave as if it weren't there.
                        .allowsHitTesting(appState.selectedTab == tab)
                        .accessibilityHidden(appState.selectedTab != tab)
                        .zIndex(appState.selectedTab == tab ? 1 : 0)
                }
            }
        }
        .onAppear { mountedTabs.insert(appState.selectedTab) }
        .onChange(of: appState.selectedTab) { _, newTab in
            mountedTabs.insert(newTab)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task {
            // Re-register the APNs token for users who have ALREADY granted
            // push authorization, on every launch that reaches the signed-
            // in + profile-loaded state (MainTabView) — covers reinstall/
            // restore, where the OS hands out a fresh token but the user
            // never revisits onboarding to trigger the original
            // registration. registerTokenIfAuthorized() is a no-op when
            // authorization is .notDetermined/.denied (no prompt fires) —
            // the initial permission prompt stays owned by onboarding
            // (Task 6), which this deliberately does not touch.
            await PushReceiver.shared.registerTokenIfAuthorized()
        }
        .task {
            // Best-effort load of the persisted palette (Canvas Completion
            // Task 5) — same "runs on every launch that reaches signed-in +
            // profile-loaded state" timing as the push-token registration
            // above, since that's the earliest point a `user_settings` row
            // is guaranteed to be readable for the signed-in user.
            await ThemeStore.shared.load()
        }
        .onPreferenceChange(GSHidesDock.self) { hides in
            withAnimation(.easeInOut(duration: 0.2)) {
                isDockHidden = hides
            }
        }
        // Retention makes `.gsHidesDock()` ambiguous: a hidden-but-mounted
        // tab whose pushed descendant sets the preference would keep the
        // dock hidden on a DIFFERENT tab (the preference reduce is an OR
        // across the whole subtree, and that subtree now includes tabs
        // nobody is looking at). Re-deriving on selection change is the
        // cheap correction — the visible tab's own contributors re-publish
        // immediately after.
        .onChange(of: appState.selectedTab) { isDockHidden = false }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Dock stays pinned at the physical bottom edge — it must NOT ride
            // up on the keyboard (matches system TabView chrome behavior).
            // Ignoring keyboard here only (not on an ancestor of the tab
            // content) keeps this opt-out scoped to the dock, so content
            // above it (ChatView compose bar, HomeView join-code field)
            // still receives the keyboard safe-area inset normally.
            if !isDockHidden {
                VStack(spacing: 0) {
                    // Rides with the dock (hidden alongside it on full-bleed
                    // screens — anyone on such a screen is mid-flow anyway).
                    // While the session's own sheet is up this sits harmlessly
                    // underneath it; the moment a swipe-down orphans the
                    // session, the pill is the way back in.
                    if let live = appState.liveSoloSession {
                        LiveSessionPill(title: live.routine?.name ?? "Freeform workout") {
                            resumeTarget = live
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    } else if let group = appState.liveGroupSession {
                        // Group re-entry rides the existing lobby deep-link:
                        // a fresh LobbyView fetch sees in_progress and its
                        // auto-forward re-presents the live sheet.
                        LiveSessionPill(title: group.title) {
                            appState.pendingRoute = .lobby(sessionID: group.sessionID)
                            appState.selectedTab = .home
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                    }
                    GSTabBar(selection: $appState.selectedTab,
                             showTrainer: appState.isTrainer)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .sheet(item: $resumeTarget) { live in
            NavigationStack {
                WorkoutSessionView(routine: live.routine,
                                   routineExercises: live.routineExercises,
                                   allExercises: live.allExercises,
                                   resume: live.session,
                                   onFinished: { resumeTarget = nil })
            }
        }
        // Trainer arm T3: does this account coach? One light fetch at
        // launch; CoachingView/TrainerTabView keep it fresh after.
        .task {
            let mine = (try? await TrainerClientRepository.mine()) ?? []
            let me = appState.currentProfile?.id
            appState.isTrainer = mine.contains { $0.trainerID == me && $0.status != "ended" }
        }
    }

    @ViewBuilder
    private func tabContent(_ tab: AppState.Tab) -> some View {
        switch tab {
        case .home:   HomeView()
        case .social:  SocialTabView()
        case .trainer: TrainerTabView()
        case .you:     YouTabView()
        }
    }
}

/// "SESSION LIVE" recovery pill — mounted by MainTabView above the dock
/// whenever `AppState.liveSoloSession` is set, i.e. a solo workout is
/// running but its sheet was swiped away. Tap to re-enter the session.
/// Extruded like every tappable surface (design law); the pulsing accent
/// dot is the "alive" signal.
private struct LiveSessionPill: View {
    @Environment(\.gsTheme) private var theme
    let title: String
    let action: () -> Void
    @State private var pulsing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .fill(theme.accent)
                    .frame(width: 8, height: 8)
                    .opacity(pulsing ? 0.35 : 1)
                    .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                               value: pulsing)
                Text("SESSION LIVE")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .kerning(1.2)
                    .foregroundStyle(theme.accent)
                Text(title)
                    .font(GSFont.bodyMedium(12, relativeTo: .caption))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: 12, lipHeight: 4))
        .onAppear { pulsing = true }
        .accessibilityLabel("Session live: \(title). Tap to return to your workout.")
    }
}
