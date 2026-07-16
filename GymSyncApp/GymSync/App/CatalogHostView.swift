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
            case .statTileLoading:            content_statTile(.loading)
            case .statTileError:              content_statTile(.error)
            case .statTileEmpty:              content_statTile(.empty)
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

    // MARK: - Stat tile (loading / error / empty)
    //
    // GSStatTile (DesignSystem/GSComponents.swift:479) itself has no
    // loading/error/empty API — every real call site (HomeView.swift:231,
    // YouTabView.swift:174, ExerciseHistoryView.swift:136,
    // CompletedSessionView.swift:186) renders it as a plain value+label and
    // handles those 3 states OUTSIDE the tile: a "—" placeholder value for
    // empty (ExerciseHistoryView.swift:137), a separate red Text for error
    // (CompletedSessionView.swift:91, `.foregroundStyle(.red)` /
    // `.foregroundColor(.red)` elsewhere), and a swapped-in ProgressView/
    // isLoading flag for loading. Reproduced with those same conventions —
    // loading additionally uses SwiftUI's stock `.redacted(reason:
    // .placeholder)`, which needs no change to GSStatTile at all.
    private enum StatTileFixture: Equatable { case loading, error, empty }

    private func content_statTile(_ fixture: StatTileFixture) -> some View {
        let row = HStack(spacing: 8) {
            GSStatTile(value: statValue(fixture, real: "12"), label: "Workouts this week")
            GSStatTile(value: statValue(fixture, real: "48.2k"), label: "Lifetime lbs")
            GSStatTile(
                value: statValue(fixture, real: "3"),
                label: "PRs this month",
                valueColor: theme.accent700
            )
        }
        return VStack(alignment: .leading, spacing: 8) {
            if fixture == .loading {
                row.redacted(reason: .placeholder)
            } else {
                row
            }
            if fixture == .error {
                Text("Couldn't load stats.")
                    .font(GSFont.body(13, relativeTo: .footnote))
                    .foregroundColor(.red)
            }
        }
        .padding(16)
    }

    private func statValue(_ fixture: StatTileFixture, real: String) -> String {
        (fixture == .empty || fixture == .error) ? "—" : real
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
#endif
