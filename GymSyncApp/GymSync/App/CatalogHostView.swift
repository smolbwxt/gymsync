#if DEBUG
import CoreLocation
import MapKit
import SwiftUI
import UserNotifications

/// Debug-only screen catalog. The parity harness sets `UITEST_CATALOG=<id>`
/// as a launch env var; `GymSyncApp` then presents `CatalogHostView` instead
/// of the normal `RootView`, force-rendering a single target view with
/// hand-built fixture state so the harness can screenshot states that
/// navigation + seeded data can't reach (overlays, voice-dock states,
/// onboarding steps). Compiled out of release entirely.
///
/// The raw values below are a fixed contract `ScreenshotTests` (Task 5)
/// drives by string — do not rename them; see `CatalogScreenTests.swift`.
enum CatalogScreen: String, CaseIterable {
    case prCelebration = "pr-celebration"
    case voiceIdle = "voice-idle"
    case voiceConnecting = "voice-connecting"
    case voiceTransmitting = "voice-transmitting"
    case voiceMicDenied = "voice-mic-denied"
    case voiceUnavailable = "voice-unavailable"
    case onboardingSignIn = "onboarding-signin"
    case onboardingUsername = "onboarding-username"
    case onboardingHomeGym = "onboarding-homegym"
    case onboardingHomeGymSearching = "onboarding-homegym-searching"
    case onboardingDone = "onboarding-done"
    case onboardingPushPriming = "onboarding-push-priming"
    case onboardingPushDenied = "onboarding-push-denied"
    case statTileLoading = "stattile-loading"
    case statTileError = "stattile-error"
    case statTileEmpty = "stattile-empty"
    case recapSolo = "recap-solo"
    case sessionChat = "session-chat"
    case groupRecap = "group-recap"
    case editProfile = "edit-profile"
    case reportSheet = "report-sheet"
    case blockedUsers = "blocked-users"
    case deleteAccount = "delete-account"
    case discover = "discover"
    case discoverDetail = "discover-detail"
    case topLifters = "top-lifters"
}

struct CatalogHostView: View {
    let screen: CatalogScreen
    @Environment(\.gsTheme) private var theme

    var body: some View {
        Group {
            switch screen {
            case .prCelebration:              content_prCelebration
            case .voiceIdle:                  content_voice(.idle)
            case .voiceConnecting:             content_voice(.connecting)
            case .voiceTransmitting:          content_voice(.transmitting)
            case .voiceMicDenied:             content_voice(.micDenied)
            case .voiceUnavailable:           content_voice(.unavailable)
            case .onboardingSignIn:           SignInView()
            case .onboardingUsername:         content_onboardingUsername
            case .onboardingHomeGym:          content_homeGym(searching: false)
            case .onboardingHomeGymSearching: content_homeGym(searching: true)
            case .onboardingDone:             content_onboardingDone
            case .onboardingPushPriming:      content_pushPriming
            case .onboardingPushDenied:       content_pushDenied
            case .statTileLoading:            StatTilesRow(state: .loading)
            case .statTileError:              StatTilesRow(state: .offlineStale(Self.statTileOfflineFixture))
            case .statTileEmpty:              StatTilesRow(state: .firstSessionZero)
            case .recapSolo:                  content_recapSolo
            case .sessionChat:                content_sessionChat
            case .groupRecap:                 content_groupRecap
            case .editProfile:                content_editProfile
            case .reportSheet:                content_reportSheet
            case .blockedUsers:               content_blockedUsers
            case .deleteAccount:              content_deleteAccount
            case .discover:                   content_discover
            case .discoverDetail:             content_discoverDetail
            case .topLifters:                 content_topLifters
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.bg.ignoresSafeArea())
        // Descendants (`SignInView` reads `AuthService.self`; `WelcomeView`
        // reads `AppState.self`) need these Observable singletons in the
        // environment or they trap at runtime — injecting both here, once,
        // covers every case below regardless of which one actually needs it.
        .environment(AppState.shared)
        .environment(AuthService.shared)
    }

    // MARK: - PR celebration
    //
    // Renders the real `PRCelebrationOverlay` (Features/Sessions/
    // PRCelebrationOverlay.swift:26-33) instead of a hand-built
    // reproduction. Fixture values exercise every rendered element:
    // weight=205/reps=5/priorBest=200 drives the headline weight, the
    // "Bench Press × 5" line, and the "beat your best by 5 lbs" delta;
    // monthlyCount=3 (non-nil, > 0) surfaces the "3rd PR this month" badge.
    private var content_prCelebration: some View {
        PRCelebrationOverlay(
            exerciseName: "Bench Press",
            weight: 205,
            reps: 5,
            priorBest: 200,
            monthlyCount: 3,
            onDismiss: {}
        )
    }

    // MARK: - Voice dock
    //
    // `PTTDockRow` (DesignSystem/GSComponents.swift:1155) takes NO init
    // params — it reads `VoiceRoomService.shared.state` directly
    // (GSComponents.swift:1215, 1221-1231), not a value passed in. `state` is
    // `private(set)`, so forcing each of the dock's 5 button variants needs
    // the `debugSetState(_:)` seam added to VoiceRoomService.swift (below
    // the same-file `private` access rule) rather than a parameter here.
    private enum VoiceFixture { case idle, connecting, transmitting, micDenied, unavailable }

    private struct CatalogVoiceUnavailableError: Error {}

    private func content_voice(_ fixture: VoiceFixture) -> some View {
        let state: VoiceRoomState
        switch fixture {
        case .idle:         state = .idle
        case .connecting:   state = .connecting
        case .transmitting: state = .connected(.transmitting)
        case .micDenied:    state = .micDenied
        case .unavailable:  state = .unavailable(CatalogVoiceUnavailableError())
        }
        return VStack(spacing: 0) {
            Spacer()
            PTTDockRow()
                .onAppear { VoiceRoomService.shared.debugSetState(state) }
        }
    }

    // MARK: - Onboarding: username

    private var content_onboardingUsername: some View {
        UsernameView(chosenProfile: .constant(nil))
    }

    // MARK: - Onboarding: home gym / searching
    //
    // HomeGymSetupView.swift's own `.task { await loadInitial() }` makes a
    // live CheckInService network call and a CLLocationManager one-shot
    // request (10s hard timeout) — not deterministic/hermetic for a
    // screenshot harness. `catalogSearchQuery/Results/IsSearching` seed the
    // private @State search fixture directly and skip `loadInitial()`
    // entirely; see the `#if DEBUG` convenience init added to
    // HomeGymSetupView.swift (same-file, for `private` @State access).

    private func content_homeGym(searching: Bool) -> some View {
        HomeGymSetupView(
            catalogSearchQuery: searching ? "Powerhouse Gym" : "",
            catalogSearchResults: searching ? [Self.catalogMapItem] : [],
            catalogIsSearching: searching
        )
    }

    private static var catalogMapItem: MKMapItem {
        let placemark = MKPlacemark(
            coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
        )
        let item = MKMapItem(placemark: placemark)
        item.name = "Powerhouse Gym"
        return item
    }

    // MARK: - Onboarding: done ("You're set" / WelcomeView)
    //
    // `Profile`'s only initializer is `init(from decoder:)` (Codable), which
    // suppresses the auto-synthesized memberwise init — there is no other
    // way to construct a `Profile` value. Every stored property is
    // non-private, so the fixture init below can live here rather than in
    // Profile.swift.

    private var content_onboardingDone: some View {
        WelcomeView(
            profile: Profile(catalogFixtureUsername: "alex_j", lifetimeVolumeLifted: 12480),
            onComplete: {}
        )
    }

    // MARK: - Onboarding: push priming / denied
    //
    // PushPrimingView is driven by `PushReceiver.shared.authorizationStatus`
    // (`private(set)`, a real UNUserNotificationCenter-backed singleton), not
    // a parameter — and its own `.task { await checkInitialState() }` would
    // immediately overwrite a forced status with the simulator's real
    // settings. `catalogAuthorizationStatus` forces the status via the
    // `debugSetAuthorizationStatus(_:)` seam on PushReceiver.swift and skips
    // `checkInitialState()`; see the `#if DEBUG` convenience init added to
    // PushPrimingView.swift (same-file, for `private` @State access).

    private var content_pushPriming: some View {
        PushPrimingView(catalogAuthorizationStatus: .notDetermined)
    }

    private var content_pushDenied: some View {
        PushPrimingView(catalogAuthorizationStatus: .denied)
    }

    // MARK: - Stat tiles (loading / offline-stale / first-session-zero)
    //
    // Phase U Task 1 (frame 41): these 3 ids now render the REAL
    // `StatTilesRow` (Features/Home/StatTilesRow.swift) forced into a
    // specific `StatTilesRowState`, replacing the hand-built 3-GSStatTile
    // reproduction that used to live here (a `StatTileFixture` enum +
    // `statValue(_:real:)` helper — see prior revisions of this file).
    //
    // RENAMED SEMANTICS, ids kept stable: `stattile-error`'s raw value is
    // unchanged (`ScreenshotTests.swift`/`CatalogScreenTests.swift` key off
    // the exact string — the Global Constraints forbid renaming it), but it
    // now forces OFFLINE·STALE-CACHE rather than a generic "couldn't load"
    // look. Frame 41 only specifies 4 states — LOADED / LOADING·SKELETON /
    // FIRST-SESSION·ZERO / OFFLINE·STALE-CACHE — there is no separate
    // "error" state in the design, so OFFLINE·STALE-CACHE (which the old
    // reproduction's red "Couldn't load stats." text was already gesturing
    // at) is the real state this id maps to now.
    //   stattile-loading -> .loading
    //   stattile-error   -> .offlineStale(fixture)   [renamed semantics, see above]
    //   stattile-empty   -> .firstSessionZero
    //
    // The offline fixture below reuses frame 41's own sample values verbatim
    // (proof-frame-41.png's OFFLINE·STALE-CACHE row: "4·" / "312k·" / "—")
    // so the catalog capture matches the canvas one-for-one: workouts=4 and
    // lifetimeLbs=312_000 are cached (render with the "·" marker),
    // prsThisMonth was never cached (renders as the em-dash).
    private static let statTileOfflineFixture = StatTilesSnapshot(
        workoutsThisWeek: 4,
        lifetimeLbs: 312_000,
        prsThisMonth: nil
    )

    // MARK: - Solo recap (frame 17)
    //
    // Renders the real `SoloRecapView` (Features/Workout/SoloRecapView.swift,
    // extracted from `WorkoutSessionView` in Phase U Task 4) with fixture
    // values copied verbatim from proof-frame-17.png so the catalog capture
    // matches the canvas one-for-one: kicker "PUSH DAY A", duration 42:06,
    // "Friday, July 11 · solo", hero stats 7,240 / 10 / 1, PR card
    // Bench Press 190×5 (beat a 185 prior best by 5 lbs), three exercise
    // rows (Bench Press 4 sets·top 190×5, PR chip / Overhead Press 3 sets·top
    // 95×8 / Tricep Pushdown 3 sets·top 50×12), and — Phase H — the "Synced
    // to Apple Health" card, "42 min · 318 kcal" per the same proof render.
    private var content_recapSolo: some View {
        SoloRecapView(
            kicker: "PUSH DAY A",
            durationText: "42:06",
            subline: "Friday, July 11 · solo",
            totalLbsText: "7,240",
            setCount: 10,
            prCount: 1,
            heaviestPR: SoloRecapView.HeaviestPR(
                exerciseName: "Bench Press",
                weight: 190,
                reps: 5,
                previousBest: 185
            ),
            exerciseSummaries: [
                SoloRecapView.ExerciseSummary(
                    id: UUID(), name: "Bench Press", setCount: 4,
                    topWeight: 190, topReps: 5, isPR: true
                ),
                SoloRecapView.ExerciseSummary(
                    id: UUID(), name: "Overhead Press", setCount: 3,
                    topWeight: 95, topReps: 8, isPR: false
                ),
                SoloRecapView.ExerciseSummary(
                    id: UUID(), name: "Tricep Pushdown", setCount: 3,
                    topWeight: 50, topReps: 12, isPR: false
                )
            ],
            healthSummary: SoloRecapView.HealthSummary(
                minutesText: "42 min",
                caloriesText: "318 kcal"
            ),
            shareSummary: "Push Day A — 42:06, 7,240 lbs, 10 sets"
        )
    }

    // MARK: - Group recap (frame 8 — Phase F Task 4)
    //
    // Renders the real `GroupRecapView` (Features/Sessions/GroupRecapView.
    // swift) via its `#if DEBUG` fixture initializer (`catalogFixtureKudos
    // Counts:` — same same-file convenience-init seam as HomeGymSetupView/
    // PushPrimingView/ChatView's catalog fixtures elsewhere in this file:
    // skips GroupRecapView's live `.task` fetch+subscribe entirely, so the
    // capture is hermetic — no network call for a session that doesn't
    // exist in the DB). Fixture values copied verbatim from
    // proof-frame-08.png so the catalog capture matches the canvas one-for-
    // one: kicker "PUSH CREW · PUSH DAY", duration 58:12, "Thursday, July
    // 10 · 4 lifters", hero stats 24.6k / 48 / 3, four-row leaderboard (Sam
    // 7,420 lbs·1 PR·💪6, You 6,880 lbs·1 PR·💪5 — highlighted, Jordan 6,310
    // lbs·1 PR·💪4, Priya 3,990 lbs·💪3 — no PR clause, matching the proof's
    // omit-if-zero row), PR card Bench Press 190×5 (beat a 185 prior best
    // by 5 lbs), and the frame's 5 kudos icons.
    private static let groupRecapSamID = UUID()
    private static let groupRecapYouID = UUID()
    private static let groupRecapJordanID = UUID()
    private static let groupRecapPriyaID = UUID()

    private var content_groupRecap: some View {
        GroupRecapView(
            kicker: "PUSH CREW · PUSH DAY",
            durationText: "58:12",
            subline: "Thursday, July 10 · 4 lifters",
            totalLbsText: "24.6k",
            setCount: 48,
            prCount: 3,
            leaderboard: [
                GroupRecapView.LeaderboardRow(
                    id: Self.groupRecapSamID, initials: "SM", name: "Sam",
                    volumeText: "7,420 lbs", prCount: 1, isYou: false
                ),
                GroupRecapView.LeaderboardRow(
                    id: Self.groupRecapYouID, initials: "AJ", name: "You",
                    volumeText: "6,880 lbs", prCount: 1, isYou: true
                ),
                GroupRecapView.LeaderboardRow(
                    id: Self.groupRecapJordanID, initials: "JC", name: "Jordan",
                    volumeText: "6,310 lbs", prCount: 1, isYou: false
                ),
                GroupRecapView.LeaderboardRow(
                    id: Self.groupRecapPriyaID, initials: "PR", name: "Priya",
                    volumeText: "3,990 lbs", prCount: 0, isYou: false
                )
            ],
            heaviestPR: GroupRecapView.HeaviestPR(
                exerciseName: "Bench Press", weight: 190, reps: 5, previousBest: 185
            ),
            shareSummary: "PUSH CREW · PUSH DAY — 58:12, 24.6k lbs, 48 sets.",
            sessionID: UUID(),
            recipientIDs: [Self.groupRecapSamID, Self.groupRecapJordanID, Self.groupRecapPriyaID],
            catalogFixtureKudosCounts: [
                Self.groupRecapSamID: 6,
                Self.groupRecapYouID: 5,
                Self.groupRecapJordanID: 4,
                Self.groupRecapPriyaID: 3
            ],
            onDone: {}
        )
    }

    // MARK: - Session chat (Task 3 — session sub-thread chat, catalog case)
    //
    // No canvas frame depicts a session-chat affordance (proof-frame-05/06/07
    // — Lobby/Live Spotlight/Live Roster headers — show no chat button; see
    // docs/design/accepted-deviations.json's "session-chat" entry). Renders
    // the real `ChatView` scoped to a fixture session sub-thread via the
    // same catalog-fixture seam idiom as HomeGymSetupView/PushPrimingView
    // above: skip the live `.task { await load() }` fetch, seed `messages`/
    // `usernames` directly (see ChatView.swift's `#if DEBUG` extension at
    // the bottom of that file).
    //
    // `AppState.shared.currentProfile` is force-set to a fixture "self"
    // profile so the outgoing/incoming bubble-alignment logic (`ChatView.
    // messageRow`'s `mine = message.authorID == appState.currentProfile?.id`)
    // has a real identity to compare against — CatalogHostView bypasses auth
    // entirely (this file's own header comment), so `currentProfile` would
    // otherwise be nil and every fixture message would render as incoming.
    // Each `UITEST_CATALOG=<id>` capture launches a fresh app process (see
    // ScreenshotTests.captureCatalog), so this mutation never leaks into
    // another catalog screen's capture.
    private static let catalogChatSelfProfile =
        Profile(catalogFixtureUsername: "you", lifetimeVolumeLifted: 0)
    private static let catalogChatOtherUserID = UUID()
    private static let catalogChatSessionID = UUID()
    private static let catalogChatGroupID = UUID()

    private var content_sessionChat: some View {
        AppState.shared.currentProfile = Self.catalogChatSelfProfile
        return ChatView(
            catalogFixtureMessages: [
                ChatMessage(
                    catalogFixtureID: UUID(), sessionID: Self.catalogChatSessionID,
                    authorID: Self.catalogChatOtherUserID,
                    body: "2 min out, saving you a rack",
                    createdAt: Date().addingTimeInterval(-240)),
                ChatMessage(
                    catalogFixtureID: UUID(), sessionID: Self.catalogChatSessionID,
                    authorID: Self.catalogChatSelfProfile.id,
                    body: "Bet, starting the clock",
                    createdAt: Date().addingTimeInterval(-120)),
                ChatMessage(
                    catalogFixtureID: UUID(), sessionID: Self.catalogChatSessionID,
                    authorID: Self.catalogChatOtherUserID,
                    body: "Pulling in now",
                    createdAt: Date().addingTimeInterval(-30))
            ],
            catalogFixtureUsernames: [Self.catalogChatOtherUserID: "jordan_c"],
            scope: .session(sessionID: Self.catalogChatSessionID, groupID: Self.catalogChatGroupID)
        )
    }

    // MARK: - Edit Profile (Task 6 — no canvas frame, catalog case)
    //
    // No canvas frame depicts an Edit Profile screen (task-2-report.md's
    // recorded deviation: "Edit Profile is a future screen" — this task
    // fulfills it, but no designer frame was ever produced for it). See
    // docs/design/accepted-deviations.json's "edit-profile" entry, same
    // "no frame — system-designed" shape as "session-chat"/"group-stats"
    // above. Renders the real `EditProfileView` directly (no `#if DEBUG`
    // fixture seam needed, unlike ChatView/HomeGymSetupView/PushPrimingView
    // above: `EditProfileView` sources its initial state entirely from the
    // `profile:` parameter passed in below — no live `.task` fetch to skip —
    // and neither persistence path fires without a user tap, so the capture
    // makes no network call). Wrapped in its own `NavigationStack` (unlike
    // every other case in this file) because this is the one catalog screen
    // whose `.toolbar`/`.navigationTitle` need real nav-bar chrome to render
    // at all — every other case is either a full-screen overlay or a
    // top-level onboarding screen with no nav bar of its own.
    private static let catalogEditProfileFixture =
        Profile(catalogFixtureUsername: "alex_j", lifetimeVolumeLifted: 12480)

    private var content_editProfile: some View {
        NavigationStack {
            EditProfileView(profile: Self.catalogEditProfileFixture, onSaved: { _ in })
        }
    }

    // MARK: - Report sheet (Phase M Task 2 — moderation compliance)
    //
    // No canvas frame depicts a report flow — App Store compliance surface
    // (Guidelines 1.2/5.1.1), not a designed screen; see
    // docs/design/accepted-deviations.json's "report-sheet" entry.
    // `ReportSheet` self-wraps its own `NavigationStack` (same as
    // `CreateGroupView`, its sheet-shape precedent — always presented via
    // `.sheet(...)`, never pushed), so unlike `content_editProfile` above,
    // no extra `NavigationStack` wrapper is needed here. No live `.task`
    // fetch to skip: `ReportSheet`'s only network call is `submit()`, which
    // never fires without a user tap on "Submit" — the capture is hermetic
    // with fixture ids alone.

    private var content_reportSheet: some View {
        ReportSheet(
            reportedUserID: UUID(),
            contentType: .profile,
            contentID: UUID()
        )
    }

    // MARK: - Blocked users (Phase M Task 2 — moderation compliance)
    //
    // No canvas frame depicts the You-tab Blocked Users list — same App
    // Store compliance surface as report-sheet above; see
    // docs/design/accepted-deviations.json's "blocked-users" entry.
    // `BlockedUsersView` is a PUSHED destination (like `EditProfileView`),
    // not a modal sheet — it needs a real `NavigationStack` for
    // `.navigationTitle` to render any chrome, same reasoning as
    // `content_editProfile` above. Uses the `catalogFixtureBlocked:` seam
    // (BlockedUsersView.swift, `#if DEBUG` extension) to skip the live
    // `.task` fetch, same idiom as ChatView/HomeGymSetupView's fixture
    // inits elsewhere in this file.

    private static let catalogBlockedUserFixture1 =
        Profile(catalogFixtureUsername: "jordan_c", lifetimeVolumeLifted: 0)
    private static let catalogBlockedUserFixture2 =
        Profile(catalogFixtureUsername: "sam_t", lifetimeVolumeLifted: 0)

    private var content_blockedUsers: some View {
        NavigationStack {
            BlockedUsersView(catalogFixtureBlocked: [
                Self.catalogBlockedUserFixture1,
                Self.catalogBlockedUserFixture2,
            ])
        }
    }

    // MARK: - Delete Account (Phase M Task 4 — moderation compliance)
    //
    // No canvas frame depicts a Delete Account flow — App Store 5.1.1
    // compliance surface, not a designed screen; see
    // docs/design/accepted-deviations.json's "delete-account" entry.
    // `DeleteAccountSheet` self-wraps its own `NavigationStack` (same as
    // `ReportSheet` above), so no extra wrapper is needed here, unlike
    // `content_editProfile`/`content_blockedUsers` (pushed destinations).
    // No fixture seam needed: the sheet has no live `.task` fetch to skip
    // and its only network call (`AccountDeletionRepository.deleteAccount`)
    // never fires without a tap on the confirm button, which itself stays
    // disabled until "DELETE" is typed — this capture is hermetic by
    // construction and only ever shows the pre-confirmation state. Per the
    // design doc's own acceptance note, the actual deletion is
    // device-QA-only, never exercised by this catalog/screenshot capture.

    private var content_deleteAccount: some View {
        DeleteAccountSheet()
    }

    // MARK: - Discover (Phase L Task 3 — no canvas frame, catalog case)
    //
    // No canvas frame depicts Discover — grepped `docs/design/frame-map.
    // json` + `docs/design/*.dc.html` for "Discover": zero hits, matching
    // the Phase L design's own prediction ("Discover may be undesigned ->
    // system-designed + deviations"). See `docs/design/accepted-
    // deviations.json`'s "discover"/"discover-detail" entries. A catalog
    // fixture is the ONLY way to render either screen with real content
    // right now — Task 4 (the phase's seed-content task, "The Murph" +
    // templates) hasn't shipped yet, so a live/seeded capture would show an
    // empty grid, not a meaningful screenshot (same class of gap
    // `stattile-*`'s catalog cases exist for). Uses the `catalogFixture...`
    // seam idiom (skip the live `.task` fetch, seed `@State` directly) —
    // same as `ChatView`/`DiscoverView`/`DiscoverWorkoutDetailView`'s own
    // `#if DEBUG` extensions.
    private static let discoverFixtureOwnerID = UUID()
    private static let discoverFixtureMurphID = UUID()
    private static let discoverFixturePushDayID = UUID()

    private static let discoverFixtureMurph = PublicWorkout(
        catalogFixtureRoutine: Routine(
            id: Self.discoverFixtureMurphID, ownerID: Self.discoverFixtureOwnerID, name: "The Murph",
            description: "100 pull-ups, 200 push-ups, 300 squats, and two 1-mile runs — with a 20lb vest.",
            visibility: "public", createdAt: .now, updatedAt: .now
        ),
        ownerUsername: "coach_dana",
        isFeatured: true,
        defaultSort: "time",
        scoringMetrics: ["time", "volume"],
        scoringTopSetExerciseID: nil
    )

    private static let discoverFixturePushDay = PublicWorkout(
        catalogFixtureRoutine: Routine(
            id: Self.discoverFixturePushDayID, ownerID: Self.discoverFixtureOwnerID, name: "Push Day A",
            description: nil, visibility: "public", createdAt: .now, updatedAt: .now
        ),
        ownerUsername: "coach_dana",
        isFeatured: false,
        defaultSort: "volume",
        scoringMetrics: ["volume", "top_set"],
        scoringTopSetExerciseID: nil
    )

    private var content_discover: some View {
        DiscoverView(
            catalogFixtureWorkouts: [Self.discoverFixtureMurph, Self.discoverFixturePushDay],
            catalogFixtureAttemptCounts: [
                Self.discoverFixtureMurphID: 187,
                Self.discoverFixturePushDayID: 3,
            ]
        )
    }

    // MARK: - Discover Detail (Phase L Task 3 — no canvas frame, catalog case)

    private static let discoverFixtureExercisePullUp = Exercise(
        id: UUID(), name: "Pull-up", slug: "pull-up", category: "compound",
        primaryMuscle: "back", secondaryMuscles: ["biceps"], equipment: "bodyweight",
        defaultUnit: "lbs", demoVideoURL: nil
    )
    private static let discoverFixtureExercisePushUp = Exercise(
        id: UUID(), name: "Push-up", slug: "push-up", category: "compound",
        primaryMuscle: "chest", secondaryMuscles: ["triceps"], equipment: "bodyweight",
        defaultUnit: "lbs", demoVideoURL: nil
    )
    private static let discoverFixtureRoutineExercises: [RoutineExercise] = [
        RoutineExercise(
            id: UUID(), routineID: Self.discoverFixtureMurphID,
            exerciseID: Self.discoverFixtureExercisePullUp.id, position: 1,
            targetSets: 20, targetReps: "5", targetWeight: nil, restSeconds: 60, notes: nil
        ),
        RoutineExercise(
            id: UUID(), routineID: Self.discoverFixtureMurphID,
            exerciseID: Self.discoverFixtureExercisePushUp.id, position: 2,
            targetSets: 20, targetReps: "10", targetWeight: nil, restSeconds: 60, notes: nil
        ),
    ]

    private static let discoverFixtureLeaderboard: [LeaderboardEntryRow] = [
        LeaderboardEntryRow(
            catalogFixtureAttemptID: UUID(), routineID: Self.discoverFixtureMurphID,
            userID: UUID(), timeSeconds: 2533, totalVolume: 3025, topSets: [:],
            isComplete: true, isEdited: false,
            computedAt: Date().addingTimeInterval(-3600), username: "tommy"
        ),
        LeaderboardEntryRow(
            catalogFixtureAttemptID: UUID(), routineID: Self.discoverFixtureMurphID,
            userID: UUID(), timeSeconds: 2610, totalVolume: 2890, topSets: [:],
            isComplete: true, isEdited: true,
            computedAt: Date().addingTimeInterval(-7200), username: "sarah_k"
        ),
    ]

    // Wrapped in its own `NavigationStack`, matching `content_editProfile`/
    // `content_blockedUsers`/`content_topLifters` above — `DiscoverWorkoutDetailView`
    // sets `.navigationTitle` + `.toolbarBackground` (below), both of which
    // no-op without a `NavigationStack` ancestor; without this wrap the
    // capture shows no nav chrome at all.
    private var content_discoverDetail: some View {
        NavigationStack {
            DiscoverWorkoutDetailView(
                catalogFixtureWorkout: Self.discoverFixtureMurph,
                catalogFixtureRoutineExercises: Self.discoverFixtureRoutineExercises,
                catalogFixtureAllExercises: [
                    Self.discoverFixtureExercisePullUp,
                    Self.discoverFixtureExercisePushUp,
                ],
                catalogFixtureLeaderboard: Self.discoverFixtureLeaderboard
            )
        }
    }

    // MARK: - Top Lifters (Phase L Task 4 — no canvas frame, catalog case)
    //
    // No canvas frame depicts a Top Lifters board — same "Discover
    // undesigned" finding as discover/discover-detail above; see
    // `docs/design/accepted-deviations.json`'s "top-lifters" entry. Uses the
    // `catalogFixtureLifters:` seam (skip the live `.task` fetch, seed
    // `lifters` directly) — same idiom as `DiscoverView`/`TopLiftersView`'s
    // own `#if DEBUG` extensions.
    //
    // `AppState.shared.currentProfile` is force-set to one of the fixture
    // rows — same "You" identity idiom `content_sessionChat` above already
    // establishes — so `TopLiftersView.leaderboardRow`'s `isYou` branch (`
    // profile.id == appState.currentProfile?.id`) has a real id to match;
    // CatalogHostView bypasses auth entirely (this file's own header
    // comment), so `currentProfile` would otherwise be nil and no row would
    // ever highlight.
    //
    // Wrapped in its own `NavigationStack`, matching `content_editProfile`/
    // `content_blockedUsers` above (both set `.navigationTitle` and need a
    // real nav bar to render it) — `TopLiftersView` sets `.navigationTitle
    // ("Top Lifters")` the same way.
    private static let topLiftersFixtureYou =
        Profile(catalogFixtureUsername: "you", lifetimeVolumeLifted: 42_800)
    private static let topLiftersFixtureRows: [Profile] = [
        Profile(catalogFixtureUsername: "coach_dana", lifetimeVolumeLifted: 128_400),
        Profile(catalogFixtureUsername: "jordan_c", lifetimeVolumeLifted: 96_200),
        topLiftersFixtureYou,
        Profile(catalogFixtureUsername: "sam_t", lifetimeVolumeLifted: 31_050),
        Profile(catalogFixtureUsername: "alex_j", lifetimeVolumeLifted: 12_480),
    ]

    private var content_topLifters: some View {
        AppState.shared.currentProfile = Self.topLiftersFixtureYou
        return NavigationStack {
            TopLiftersView(catalogFixtureLifters: Self.topLiftersFixtureRows)
        }
    }
}

// MARK: - Profile fixture
//
// See content_onboardingDone's doc comment above: Profile.swift's only
// initializer is `init(from decoder:)`, so there's no synthesized memberwise
// init to build a fixture instance from. Every property is non-private, so
// this direct-assignment init is added here rather than editing Profile.swift.
extension Profile {
    init(catalogFixtureUsername username: String, lifetimeVolumeLifted: Decimal) {
        self.id = UUID()
        self.username = username
        self.displayName = nil
        self.avatarURL = nil
        self.createdAt = .now
        self.lifetimeVolumeLifted = lifetimeVolumeLifted
        self.isCurator = false
        // Phase M Task 4: Profile.swift's memberwise-trap fixture init needs
        // every stored property assigned or this extension fails to compile
        // — showSoloWorkouts defaults false, matching isCurator's fixture
        // default above and the column's own server-side default.
        self.showSoloWorkouts = false
    }
}

// MARK: - ChatMessage fixture (session-chat catalog case)
//
// Same memberwise-init trap as `Profile` above: ChatMessage.swift's only
// initializer is its custom `init(from decoder:)` (Codable's synthesized
// memberwise init is suppressed by that), so there is no other way to
// build a `ChatMessage` value directly. Every stored property is
// non-private, so this direct-assignment init is added here rather than
// editing ChatMessage.swift. `groupID` is fixed nil — `ChatView`'s session
// codepath never reads a message's own `groupID` field (only `scope`'s),
// so the fixture's own group_id shape is inert either way.
extension ChatMessage {
    init(catalogFixtureID id: UUID, sessionID: UUID, authorID: UUID,
         body: String, createdAt: Date) {
        self.id = id
        self.groupID = nil
        self.sessionID = sessionID
        self.authorID = authorID
        self.kind = .text
        self.body = body
        self.storagePath = nil
        self.replyToID = nil
        self.createdAt = createdAt
        self.editedAt = nil
        self.deletedAt = nil
        self.payload = nil
    }
}

// MARK: - PublicWorkout / LeaderboardEntryRow fixtures (discover catalog cases)
//
// Same memberwise-init trap as `Profile`/`ChatMessage` above:
// `PublicWorkout.swift`'s only initializers are custom `init(from
// decoder:)`s (the dual-decode-from-one-decoder idiom, needed to also
// consume the joined `profiles(...)` key) — Codable's synthesized
// memberwise init is suppressed by that. Every stored property on both
// types is non-private, so these direct-assignment inits are added here
// rather than editing `PublicWorkout.swift`, same placement precedent as
// `Profile`/`ChatMessage` above (as opposed to `ChatView`'s `#if DEBUG`
// seam, which lives in ChatView.swift itself because IT needs same-file
// access to private `@State`).
extension PublicWorkout {
    init(catalogFixtureRoutine routine: Routine, ownerUsername: String,
         isFeatured: Bool = false, defaultSort: String? = nil,
         scoringMetrics: [String]? = nil, scoringTopSetExerciseID: UUID? = nil) {
        self.routine = routine
        self.ownerUsername = ownerUsername
        self.isFeatured = isFeatured
        self.defaultSort = defaultSort
        self.scoringMetrics = scoringMetrics
        self.scoringTopSetExerciseID = scoringTopSetExerciseID
    }
}

extension LeaderboardEntryRow {
    init(catalogFixtureAttemptID attemptID: UUID, routineID: UUID?, userID: UUID,
         timeSeconds: Int?, totalVolume: Decimal?, topSets: [String: Decimal]?,
         isComplete: Bool, isEdited: Bool, computedAt: Date,
         username: String, avatarURL: URL? = nil,
         // Defaulted true — review fix (Important finding 1) added this
         // field to the real decode; both existing catalog rows below
         // represent already-opted-in completed attempts (that's the only
         // kind the real query can ever return now), so the default keeps
         // those call sites source-compatible unchanged.
         isOptInLeaderboard: Bool = true) {
        self.attemptID = attemptID
        self.routineID = routineID
        self.userID = userID
        self.timeSeconds = timeSeconds
        self.totalVolume = totalVolume
        self.topSets = topSets
        self.isComplete = isComplete
        self.isEdited = isEdited
        self.computedAt = computedAt
        self.username = username
        self.avatarURL = avatarURL
        self.isOptInLeaderboard = isOptInLeaderboard
    }
}
#endif
