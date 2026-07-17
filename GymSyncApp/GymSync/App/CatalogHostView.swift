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
    // Bench Press 190×5 (beat a 185 prior best by 5 lbs), and three exercise
    // rows (Bench Press 4 sets·top 190×5, PR chip / Overhead Press 3 sets·top
    // 95×8 / Tricep Pushdown 3 sets·top 50×12). No Apple Health row —
    // `SoloRecapView` never renders one (see its type doc comment).
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
#endif
