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
    case voiceCoachMark = "voice-coach-mark"
    case voiceConnectedToast = "voice-connected-toast"
    case voiceMixerSheet = "voice-mixer-sheet"
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
    case bodyWeightLog = "body-weight-log"
    case plateMath = "plate-math"
    case heartRatePill = "heart-rate-pill"
    case campaignsTab = "campaigns-tab"
    case campaignDetailUnjoined = "campaign-detail-unjoined"
    case campaignDetailJoined = "campaign-detail-joined"
    case programActive = "program-active"
    case programDetail = "program-detail"
    case programTemplateDetail = "program-template-detail"
    case venueLocalTab = "venue-local-tab"
    case venueHub = "venue-hub"
    case venueAgeGate = "venue-age-gate"
    case guidanceSpotlight = "guidance-spotlight"
    case guidanceDiscovery = "guidance-discovery"
    case barLoader = "bar-loader"
    case paywall = "paywall"
    case pumpComposer = "pump-composer"
    case pumpFeedPost = "pump-feed-post"
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
            case .voiceCoachMark:             content_voiceCoachMark
            case .voiceConnectedToast:        content_voiceConnectedToast
            case .voiceMixerSheet:            content_voiceMixerSheet
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
            case .bodyWeightLog:              content_bodyWeightLog
            case .plateMath:                  content_plateMath
            case .heartRatePill:              content_heartRatePill
            case .campaignsTab:               content_campaignsTab
            case .campaignDetailUnjoined:     content_campaignDetailUnjoined
            case .campaignDetailJoined:       content_campaignDetailJoined
            case .programActive:              content_programActive
            case .programDetail:              content_programDetail
            case .programTemplateDetail:      content_programTemplateDetail
            case .venueLocalTab:              content_venueLocalTab
            case .venueHub:                   content_venueHub
            case .venueAgeGate:               content_venueAgeGate
            case .guidanceSpotlight:          content_guidanceSpotlight
            case .guidanceDiscovery:          content_guidanceDiscovery
            case .barLoader:                  content_barLoader
            case .paywall:                    PaywallView(highlight: .programs)
            case .pumpComposer:               content_pumpComposer
            case .pumpFeedPost:               content_pumpFeedPost
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

    // MARK: - Voice chrome (Phase O Task 5 item 5 — designer follow-up
    // frames, docs/design/sections/2026-07-live-voice.dc.html; see
    // docs/design/accepted-deviations.json's "voice-coach-mark"/
    // "voice-connected-toast"/"voice-mixer-sheet" entries for frame
    // authority + fidelity notes)

    private var content_voiceCoachMark: some View {
        VStack(spacing: 0) {
            Spacer()
            GSVoiceCoachMark(onDismiss: {})
                .padding(.horizontal, 16)
                .padding(.bottom, 6)
            PTTDockRow()
                .onAppear { VoiceRoomService.shared.debugSetState(.connected(.muted)) }
        }
    }

    private var content_voiceConnectedToast: some View {
        VStack(spacing: 0) {
            GSVoiceConnectedToast(groupName: "Push Crew")
                .padding(.horizontal, 16)
                .padding(.top, 8)
            Spacer()
        }
    }

    private static let mixerFixtureJordan = "jordan-uuid"
    private static let mixerFixtureSam = "sam-uuid"
    private static let mixerFixturePriya = "priya-uuid"

    private var content_voiceMixerSheet: some View {
        GSVoiceMixerSheet(
            participants: [
                (Self.mixerFixtureJordan, "Jordan"),
                (Self.mixerFixtureSam, "Sam"),
                (Self.mixerFixturePriya, "Priya"),
            ],
            mutedIdentities: [Self.mixerFixturePriya],
            onToggleMute: { _ in }
        )
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

    // MARK: - Body Weight log sheet (Phase H Task 3 — no canvas frame, catalog case)
    //
    // No canvas frame depicts a body-weight log affordance — see
    // `docs/design/accepted-deviations.json`'s "body-weight-log" entry.
    // `BodyWeightLogSheet` self-wraps its own `NavigationStack` (same shape
    // as `ReportSheet`/`DeleteAccountSheet` above), so no extra wrapper is
    // needed here. No fixture seam needed: the sheet has no live `.task`
    // fetch to skip and its only network call (`BodyWeightLogRepository
    // .log`) never fires without a tap on "Save", which itself stays
    // disabled until a valid weight is entered — hermetic by construction,
    // same reasoning `content_deleteAccount` documents above.

    private var content_bodyWeightLog: some View {
        BodyWeightLogSheet()
    }

    // MARK: - Plate math (Phase H Task 4 — no canvas frame, catalog case)
    //
    // No canvas frame depicts a plate-math affordance — see `docs/design/
    // accepted-deviations.json`'s "plate-math" entry. Renders the real
    // `LogSetSheet` (Features/Workout/LogSetSheet.swift) via its `#if DEBUG`
    // `catalogFixtureExercise:` convenience init (added there — same
    // same-file seam idiom as `HomeGymSetupView`'s `catalogSearchQuery:`
    // init above: `_showPlateStack` is `private` @State, only reassignable
    // from LogSetSheet.swift itself), forcing the "Plates" disclosure open
    // with defaultWeight "185" pre-filled — deterministic per this file's
    // own "prefer disclosure-open over closed-with-prefill" instruction.
    // 185 lbs / 45 lb bar resolves to a clean two-denomination stack (1×45,
    // 1×25 per side, exact — no remainder note), a representative capture
    // that also isn't the trivial single-denomination case.
    private static let plateMathFixtureExercise = Exercise(
        id: UUID(), name: "Back Squat", slug: "back-squat", category: "compound",
        primaryMuscle: "quads", secondaryMuscles: ["glutes", "hamstrings"],
        equipment: "barbell", defaultUnit: "lbs", demoVideoURL: nil
    )

    private var content_plateMath: some View {
        LogSetSheet(
            catalogFixtureExercise: Self.plateMathFixtureExercise,
            setIndex: 1,
            defaultReps: "5",
            defaultWeight: "185"
        ) { _, _, _, _, _ in }
    }

    // MARK: - Heart rate pill (Phase W Task 5 — no canvas gallery, component-alone capture)
    //
    // `GSHeartRatePill` (`DesignSystem/GSComponents.swift`) is embedded deep
    // inside `GroupSessionLiveView`'s roster/spotlight rendering, which has
    // no catalog-fixture seam (unlike `ChatView`/`LogSetSheet` above) — that
    // view's participants/sets/routine state all come from LIVE
    // `SessionRepository`/`RoutineRepository` fetches with no `#if DEBUG`
    // bypass, and building one for this task alone would be a large,
    // disproportionate addition just to showcase one small atom. Same
    // "component alone" idiom `voice-coach-mark`/`voice-connected-toast`
    // already established (docs/design/accepted-deviations.json) — this
    // captures `GSHeartRatePill` directly, not the live roster it's
    // embedded in.
    //
    // Shows all 4 zone colors + the two caption variants (roster "BPM" /
    // spotlight "BPM · LIVE") in one screenshot rather than 5+ separate
    // catalog ids — this is a small reusable atom with orthogonal color
    // variants, not a set of mutually exclusive dock states the way
    // `VoiceFixture` above is; one gallery capture proves every variant
    // renders correctly without a proliferation of near-duplicate catalog
    // ids. See docs/design/accepted-deviations.json's "heart-rate-pill"
    // entry.
    private var content_heartRatePill: some View {
        VStack(alignment: .leading, spacing: 16) {
            GSHeartRatePill(bpm: 112, zone: .warmup)
            GSHeartRatePill(bpm: 151, zone: .moderate)
            GSHeartRatePill(bpm: 172, zone: .hard, showsLiveSuffix: true)
            GSHeartRatePill(bpm: 188, zone: .max)
            // Unrecognized/future zone value — proves the nil-zone fallback
            // (`GSHeartRatePill.zoneColor`'s `case nil` branch) renders
            // rather than crashing.
            GSHeartRatePill(bpm: 140, zone: nil)
        }
        .padding(20)
        .background(theme.surface)
    }

    // MARK: - Campaigns (Phase C Task 2 — no canvas frame, catalog cases)
    //
    // No canvas frame depicts any campaigns surface — grepped `docs/design/
    // frame-map.json` + every `.dc.html` canvas file for "campaign": zero
    // hits, same "undesigned -> system-designed + deviations" finding as
    // `discover`/`discover-detail` above. See `docs/design/accepted-
    // deviations.json`'s "campaigns-tab"/"campaign-detail" entries.
    //
    // `Campaign`/`CampaignParticipant`/`CampaignProgress`/
    // `CampaignCommunityProgress`/`CampaignLeaderboardRow` are all plain
    // `Decodable` (or plain) structs with NO custom `init(from decoder:)`
    // override (`Models/Campaign.swift`) — unlike `Profile`/`ChatMessage`
    // above, the compiler-synthesized memberwise init is still available,
    // so these fixtures are built directly with no extension-init workaround
    // needed.
    private static let campaignFixtureID = UUID()
    private static let campaignFixtureUserID = UUID()

    // Phase C Task 3: curated workout list section — reuses the EXISTING
    // `discoverFixtureMurph`/`discoverFixturePushDay` `PublicWorkout`
    // fixtures (defined above, `content_discover`'s own fixtures) rather
    // than minting new ones, same "extend additively" instruction as the
    // task brief. `curatedRoutineIDs` below is updated to reference their
    // real fixture ids so the fixture stays internally consistent for
    // anyone reading it, even though catalog-fixture mode renders from
    // `catalogFixtureCuratedWorkouts:` directly and never actually resolves
    // ids -> workouts via the network path (`catalogSkipLoad`).
    private static let campaignFixtureActive = Campaign(
        id: campaignFixtureID,
        name: "Spring Break Prep 2026",
        description: "12 sessions before break — every rep counts toward the community goal.",
        startsAt: Date.now.addingTimeInterval(-5 * 86400),
        endsAt: Date.now.addingTimeInterval(20 * 86400),
        bannerURL: nil,
        globalTarget: CampaignTarget(metric: "total_volume", target: 100_000_000),
        individualTarget: CampaignIndividualTarget(sessions: 12, workoutsCompleted: nil),
        curatedRoutineIDs: [Self.discoverFixtureMurphID, Self.discoverFixturePushDayID],
        isFeatured: true,
        isDraft: false,
        createdAt: .now
    )

    private static let campaignFixtureUpcoming = Campaign(
        id: UUID(),
        name: "Summer Shred",
        description: "8 weeks, 4 workouts a week.",
        startsAt: Date.now.addingTimeInterval(14 * 86400),
        endsAt: Date.now.addingTimeInterval(70 * 86400),
        bannerURL: nil,
        globalTarget: nil,
        individualTarget: CampaignIndividualTarget(sessions: nil, workoutsCompleted: 16),
        curatedRoutineIDs: [],
        isFeatured: false,
        isDraft: false,
        createdAt: .now
    )

    // Ended (window closed) — feeds the Campaigns sub-tab's "Past" section
    // (Opus pre-GA closeout, gate MINOR-2). `endsAt` in the past so
    // `windowState()` reads `.ended`.
    private static let campaignFixturePast = Campaign(
        id: UUID(),
        name: "New Year Kickoff",
        description: "January's 20-session challenge — final standings below.",
        startsAt: Date.now.addingTimeInterval(-40 * 86400),
        endsAt: Date.now.addingTimeInterval(-10 * 86400),
        bannerURL: nil,
        globalTarget: CampaignTarget(metric: "total_volume", target: 50_000_000),
        individualTarget: CampaignIndividualTarget(sessions: 20, workoutsCompleted: nil),
        curatedRoutineIDs: [],
        isFeatured: false,
        isDraft: false,
        createdAt: .now
    )

    private static let campaignFixtureCommunity = CampaignCommunityProgress(
        sessionsCompleted: 812, workoutsCompleted: 812, volumeLifted: 47_300_000
    )

    private static let campaignFixtureMyProgress = CampaignProgress(
        campaignID: campaignFixtureID, userID: campaignFixtureUserID,
        sessionsCompleted: 7, workoutsCompleted: 7, volumeLifted: 18_400, updatedAt: .now
    )

    private static let campaignFixtureParticipant = CampaignParticipant(
        campaignID: campaignFixtureID, userID: campaignFixtureUserID,
        joinedAt: Date.now.addingTimeInterval(-4 * 86400)
    )

    private static let campaignFixtureLeaderboard: [CampaignLeaderboardRow] = [
        CampaignLeaderboardRow(userID: UUID(), username: "coach_dana", avatarURL: nil,
                                sessionsCompleted: 11, workoutsCompleted: 11, volumeLifted: 28_900),
        CampaignLeaderboardRow(userID: campaignFixtureUserID, username: "you", avatarURL: nil,
                                sessionsCompleted: 7, workoutsCompleted: 7, volumeLifted: 18_400),
        CampaignLeaderboardRow(userID: UUID(), username: "sam_t", avatarURL: nil,
                                sessionsCompleted: 5, workoutsCompleted: 5, volumeLifted: 12_050),
    ]

    // `campaigns-tab`: no NavigationStack wrapper, matching `content_discover`
    // above exactly — `CampaignsTabView` (like `DiscoverView`) sets no
    // `.navigationTitle` of its own; LibraryTabView's own outer
    // NavigationStack owns that chrome when live.
    private var content_campaignsTab: some View {
        CampaignsTabView(
            catalogFixtureActive: [Self.campaignFixtureActive],
            catalogFixtureUpcoming: [Self.campaignFixtureUpcoming],
            catalogFixturePast: [Self.campaignFixturePast]
        )
    }

    // `campaign-detail-*`: DOES need the NavigationStack wrapper (same
    // reasoning as `content_discoverDetail` above) — `CampaignDetailView`
    // sets `.navigationTitle`/`.navigationBarTitleDisplayMode`, which is a
    // no-op without a NavigationStack ancestor.
    private var content_campaignDetailUnjoined: some View {
        NavigationStack {
            CampaignDetailView(
                campaign: Self.campaignFixtureActive,
                catalogFixtureParticipation: nil,
                catalogFixtureProgress: nil,
                catalogFixtureCommunity: Self.campaignFixtureCommunity,
                catalogFixtureLeaderboard: [],
                catalogFixtureCuratedWorkouts: [Self.discoverFixtureMurph, Self.discoverFixturePushDay]
            )
        }
    }

    private var content_campaignDetailJoined: some View {
        NavigationStack {
            CampaignDetailView(
                campaign: Self.campaignFixtureActive,
                catalogFixtureParticipation: Self.campaignFixtureParticipant,
                catalogFixtureProgress: Self.campaignFixtureMyProgress,
                catalogFixtureCommunity: Self.campaignFixtureCommunity,
                catalogFixtureLeaderboard: Self.campaignFixtureLeaderboard,
                catalogFixtureCuratedWorkouts: [Self.discoverFixtureMurph, Self.discoverFixturePushDay]
            )
        }
    }

    // MARK: Training Programs P1 fixtures

    private static let programFixtureSquat = Exercise(
        id: UUID(uuidString: "aaaaaaaa-1111-4111-8111-111111111111")!,
        name: "Back Squat", slug: "back-squat", category: "strength",
        primaryMuscle: "quads", secondaryMuscles: ["glutes"],
        equipment: "barbell", defaultUnit: "lbs", demoVideoURL: nil
    )

    /// Week 3 of the March: started 15 days ago, one baseline lift.
    private static let programFixtureEnrollment = ProgramEnrollment(
        id: UUID(),
        userID: campaignFixtureUserID,
        templateSlug: "march-to-1rm",
        focus: ProgramFocus(exerciseIDs: [programFixtureSquat.id]),
        baseline: [programFixtureSquat.id.uuidString.lowercased(): 262.5],
        startedOnString: SessionSeries.dayString(
            for: Date.now.addingTimeInterval(-15 * 86400), in: .current),
        weeks: 8,
        endedAt: nil,
        endedReason: nil,
        createdAt: Date.now.addingTimeInterval(-15 * 86400)
    )

    // `program-active`: the campaigns tab with an enrolled program card on
    // top — no NavigationStack, same reasoning as `content_campaignsTab`.
    private var content_programActive: some View {
        CampaignsTabView(
            catalogFixtureActive: [Self.campaignFixtureActive],
            catalogFixtureUpcoming: [Self.campaignFixtureUpcoming],
            catalogFixtureProgram: Self.programFixtureEnrollment,
            catalogFixtureProgramExercises: [Self.programFixtureSquat],
            catalogFixtureProgramSessions: 1
        )
    }

    // `program-detail`/`program-template-detail`: pushed screens that set
    // `.navigationTitle` — NavigationStack wrapper required (same reasoning
    // as `content_campaignDetailUnjoined`).
    private var content_programDetail: some View {
        var view = ProgramDetailView(
            enrollment: Self.programFixtureEnrollment,
            focusExercises: [Self.programFixtureSquat],
            sessionsThisWeek: 1,
            onChanged: {}
        )
        view.catalogSkipLoad = true
        return NavigationStack { view }
    }

    private var content_programTemplateDetail: some View {
        var view = ProgramTemplateDetailView(
            template: ProgramTemplate.bySlug("march-to-1rm")!,
            onEnrolled: {}
        )
        view.catalogSkipLoad = true
        return NavigationStack { view }
    }

    // MARK: Venue Hubs H1 fixtures

    private static let venueFixtureID = UUID(uuidString: "50000000-0000-4000-d000-0000000004a1")!
    private static let venueFixtureMeID = UUID(uuidString: "60000000-0000-4000-d000-0000000004b1")!

    private static let venueFixture = Venue(
        id: venueFixtureID,
        name: "Iron Temple",
        latitude: 34.0195, longitude: -118.4912,
        radiusMeters: 200,
        createdBy: venueFixtureMeID,
        isVerified: true,
        bannerURL: nil
    )

    private static let venueFixtureSecond = Venue(
        id: UUID(), name: "Sunset Barbell Club",
        latitude: 34.0300, longitude: -118.5000,
        radiusMeters: 200, createdBy: UUID(), isVerified: false, bannerURL: nil
    )

    private static let venueFixtureMembers: [VenueMember] = [
        VenueMember(venueID: venueFixtureID, userID: venueFixtureMeID,
                    isVisibleOnHub: true, lastSeenAt: Date.now.addingTimeInterval(-600)),
        VenueMember(venueID: venueFixtureID, userID: UUID(uuidString: "60000000-0000-4000-d000-0000000004b2")!,
                    isVisibleOnHub: true, lastSeenAt: Date.now.addingTimeInterval(-1800)),
        VenueMember(venueID: venueFixtureID, userID: UUID(uuidString: "60000000-0000-4000-d000-0000000004b3")!,
                    isVisibleOnHub: true, lastSeenAt: Date.now.addingTimeInterval(-3600)),
    ]

    private static let venueFixtureBoard: [VenueLeaderboardRow] = [
        VenueLeaderboardRow(userID: venueFixtureMembers[1].userID, username: "coach_dana", volume: 128_400),
        VenueLeaderboardRow(userID: venueFixtureMeID, username: "you", volume: 96_250),
        VenueLeaderboardRow(userID: venueFixtureMembers[2].userID, username: "sam_t", volume: 71_900),
    ]

    // No NavigationStack: `LocalHubsView`'s own title is owned by the
    // Social tab's stack when live (same as content_campaignsTab).
    private var content_venueLocalTab: some View {
        NavigationStack {
            LocalHubsView(catalogFixtureVenues: [Self.venueFixture, Self.venueFixtureSecond])
        }
    }

    private var content_venueHub: some View {
        NavigationStack {
            VenueHubView(
                venue: Self.venueFixture,
                here: nil,
                catalogFixtureMembers: Self.venueFixtureMembers,
                catalogFixtureBoard: Self.venueFixtureBoard,
                catalogFixtureMine: Self.venueFixtureMembers[0],
                catalogSkipLoad: true
            )
        }
    }

    private var content_venueAgeGate: some View {
        AgeGateView(onConfirm: {}, onDecline: {})
    }

    // `guidance-discovery`: the depth treatment side by side with a plain
    // control, since the whole question under review is whether the
    // difference is visible WITHOUT being loud. Renders the border directly
    // rather than through .gsDiscovery — the modifier is state-gated on
    // "never pressed", which a capture run can't guarantee.
    private var content_guidanceDiscovery: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Discovery depth")
                .font(GSFont.heading(20, relativeTo: .title3))
                .foregroundStyle(theme.text)

            VStack(alignment: .leading, spacing: 6) {
                Text("NEW — never pressed")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)
                catalogDiscoveryRow(raised: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("ALREADY USED")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.2)
                    .foregroundStyle(theme.neutral500)
                catalogDiscoveryRow(raised: false)
            }

            HStack(spacing: 10) {
                GSDiscoveryDot()
                Text("Tab-bar rollup dot — stroked, never accent-filled")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.top, 4)

            Spacer()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // `bar-loader`: three loads in each unit — an exact lbs stack, a kg
    // stack, and a target that ISN'T loadable with the given plates, since
    // the honest "closest loadable" state is the one most worth reviewing.
    private var content_barLoader: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                catalogLoaderBlock(title: "225 lbs · standard plates",
                                   target: 225, bar: 45,
                                   plates: WeightUnit.lbs.standardPlates, unit: .lbs)
                catalogLoaderBlock(title: "102.5 kg · standard plates",
                                   target: 102.5, bar: 20,
                                   plates: WeightUnit.kg.standardPlates, unit: .kg)
                catalogLoaderBlock(title: "227.5 lbs · gym has no 2.5s",
                                   target: 227.5, bar: 45,
                                   plates: [45, 35, 25, 10, 5], unit: .lbs)
            }
            .padding(16)
        }
    }

    private func catalogLoaderBlock(title: String, target: Decimal, bar: Decimal,
                                    plates: [Decimal], unit: WeightUnit) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
            GSBarLoader(target: target, barWeight: bar, plates: plates, unit: unit)
        }
    }

    // MARK: - Pump Check (spec 2026-07-27, P4)

    /// `pump-composer`: the recap composer in its idle state — CTA, live
    /// countdown (window anchored at render; the ticking value varies per
    /// capture like the session's elapsed clock), Snap/Skip. The camera
    /// itself can't be driven headless — capture/review QA is on-device.
    private var content_pumpComposer: some View {
        ScrollView {
            PumpCheckComposerCard(context: PumpCheckContext(
                sessionID: UUID(),
                summary: Self.pumpFixtureSummary,
                avgBpm: 142, maxBpm: 171,
                includeHRDefault: true,
                windowStart: Date()))
                .padding(16)
        }
    }

    /// `pump-feed-post`: two feed cards — a friend's photo post (signed-URL
    /// fetch fails in the harness, so the photo block shows its honest
    /// placeholder) with reactions, and a summary-only late post of your
    /// own. Exercises cover the barbell mini-bar and a bodyweight entry.
    private var content_pumpFeedPost: some View {
        ScrollView {
            VStack(spacing: 14) {
                PumpPostCard(
                    post: WorkoutPost(
                        id: UUID(), authorID: UUID(), sessionID: UUID(),
                        photoPath: "posts/fixture/fixture.jpg",
                        summary: Self.pumpFixtureSummary,
                        includesHR: true, avgBpm: 142, maxBpm: 171,
                        isLate: false,
                        createdAt: Date().addingTimeInterval(-3600)),
                    author: nil, isMine: false,
                    myReactions: ["🔥"],
                    reactionCounts: ["🔥": 3, "💪": 1, "snd:airhorn": 2],
                    ownedSoundSlugs: ["airhorn"],
                    soundNames: ["airhorn": "Airhorn"],
                    onReact: { _ in }, onDelete: {}, onReport: {})
                PumpPostCard(
                    post: WorkoutPost(
                        id: UUID(), authorID: UUID(), sessionID: UUID(),
                        photoPath: nil,
                        summary: Self.pumpFixtureSummary,
                        includesHR: false, avgBpm: nil, maxBpm: nil,
                        isLate: true,
                        createdAt: Date().addingTimeInterval(-7200)),
                    author: nil, isMine: true,
                    myReactions: [],
                    reactionCounts: [:],
                    ownedSoundSlugs: [],
                    soundNames: [:],
                    onReact: { _ in }, onDelete: {}, onReport: {})
            }
            .padding(16)
        }
    }

    private static let pumpFixtureSummary = PostSummary(
        durationSeconds: 2520,
        totalVolumeLbs: 7240,
        exercises: [
            .init(name: "Back Squat", equipment: "barbell", sets: [
                .init(weightLbs: 225, reps: 5, isPR: false, isFailed: false),
                .init(weightLbs: 235, reps: 3, isPR: true, isFailed: false),
            ]),
            .init(name: "Walking Lunge", equipment: "bodyweight", sets: [
                .init(weightLbs: nil, reps: 20, isPR: false, isFailed: false),
            ]),
        ])

    private func catalogDiscoveryRow(raised: Bool) -> some View {
        HStack(spacing: 13) {
            RoundedRectangle(cornerRadius: 12)
                .fill(theme.neutral300)
                .frame(width: 42, height: 42)
                .overlay(
                    Image(systemName: "calendar.badge.plus")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(theme.accent)
                )
            VStack(alignment: .leading, spacing: 2) {
                Text("Schedule a session")
                    .font(GSFont.bold(15.5, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text("Plan your next lift — solo or with a crew")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer(minLength: 8)
        }
        .padding(16)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusMd)
        .overlay {
            if raised {
                RoundedRectangle(cornerRadius: GSMetrics.radiusMd)
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white.opacity(0.30), Color.white.opacity(0.04)],
                            startPoint: .top, endPoint: .bottom
                        ),
                        lineWidth: 1
                    )
            }
        }
    }

    // `guidance-spotlight`: the overlay rendered directly with a fixed
    // target rect. The live modifier is gated on "unseen + tips on + layout
    // settled", none of which a capture run can arrange — so the catalog
    // constructs GSSpotlightOverlay itself, which is the part worth
    // reviewing (scrim opacity, cutout, card placement).
    private var content_guidanceSpotlight: some View {
        ZStack {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: GSMetrics.radiusMd)
                        .fill(theme.surface)
                        .frame(height: 76)
                }
            }
            .padding(16)

            GSSpotlightOverlay(
                targetRect: CGRect(x: 16, y: 192, width: 360, height: 76),
                title: GuidanceTip.home.title,
                message: GuidanceTip.home.message,
                onDismiss: {}
            )
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
        self.proUntil = nil
        // 20260811000003: fixture matches the column's server-side default.
        self.weeklySessionGoal = 3
        // 20260812000001: nil = never edited, matching fresh-row state.
        self.weeklySessionGoalPrev = nil
        self.weeklySessionGoalChangedAt = nil
        // 20260814000009: generator demographics — nil = never provided,
        // matching fresh-row state.
        self.sex = nil
        self.birthYear = nil
        // 20260828000001: a catalog fixture is an "already onboarded"
        // user - nil here would route the host into onboarding resume.
        self.onboardedAt = .now
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
