import Foundation
import SwiftData
import SwiftUI

@main
struct GymSyncApp: App {
    // Only hook for APNs' didRegisterForRemoteNotificationsWithDeviceToken /
    // UNUserNotificationCenterDelegate — SwiftUI's App protocol has no
    // native equivalent. See AppDelegate.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Phase O Task 4 (master spec §6.8.5) — DSN-gated no-op when
        // `Secrets.sentryDSN` is empty (no Sentry project created yet, see
        // Config/Secrets.swift.template's USER ACTION note). See
        // `CrashReporting` (Services/CrashReporting.swift) for the
        // hermetically-provable no-op path. Runs FIRST in init so a crash
        // in any later setup call is already captured once a DSN is live.
        CrashReporting.shared.start(
            dsn: Secrets.sentryDSN,
            environment: Self.sentryEnvironment,
            release: Self.buildNumber
        )
        try? AudioSessionManager.shared.configure()
        // Field #2 2026-08-24: the old "activate on session start only"
        // rule left solo starts pushing into an INACTIVE WCSession and
        // the pairing screen unable to even read isPaired. Activation is
        // cheap and Apple-recommended at launch; the field overruled the
        // old brief twice.
        WatchConnectivityBridge.shared.activateIfNeeded()
        GSAppearance.apply()
    }

    /// Sentry `environment` tag — separates noisy debug/simulator crashes
    /// from real user (release/TestFlight/App Store) crashes in the
    /// dashboard. Standard `#if DEBUG` idiom, matching this file's own
    /// `#if DEBUG` catalog-mode branch below.
    #if DEBUG
    private static let sentryEnvironment = "debug"
    #else
    private static let sentryEnvironment = "release"
    #endif

    /// Sentry `release`/build tag. `CFBundleVersion` is populated from
    /// project.yml's `CURRENT_PROJECT_VERSION` base setting ("1") for every
    /// build EXCEPT the TestFlight archive job, which overrides it to
    /// `${{ github.run_number }}` at archive time
    /// (.github/workflows/ios.yml's "Archive (automatic signing via ASC API
    /// key)" step, `CURRENT_PROJECT_VERSION=${{ github.run_number }}`) — so
    /// a TestFlight crash's release tag maps 1:1 to the CI run that produced
    /// the build it came from.
    private static var buildNumber: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "unknown"
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["UITEST_CATALOG"],
               let screen = CatalogScreen(rawValue: id) {
                // Catalog mode bypasses auth entirely, so ThemeStore.shared.current
                // never loads the CI user's persisted palette (it stays at its
                // seed). Redesign (2026-07-20): pin ONYX with the default sky
                // accent — exactly what production RootView injects for a fresh
                // user — so catalog captures render the new visual language.
                // (Previously pinned .ink to match the old Ink-palette proofs;
                // those frames are superseded and the parity baseline is being
                // rebased to the redesign per screen.) Also re-stamp the UIKit
                // appearance proxies (same path ThemeStore uses on a real
                // palette change) so nav/tab bar chrome matches.
                let _ = GSAppearance.apply(theme: GSTheme.onyx.withAccent(GSAccents.sky))
                CatalogHostView(screen: screen)
                    .environment(\.gsTheme, GSTheme.onyx.withAccent(GSAccents.sky))
                    .environment(\.gsAccent, GSAccents.sky)
            } else {
                RootView()
                    .environment(AuthService.shared)
                    .modelContainer(for: PendingSetLog.self)
            }
            #else
            RootView()
                .environment(AuthService.shared)
                .modelContainer(for: PendingSetLog.self)
            #endif
        }
    }
}

// MARK: - GSAppearance
//
// Configures UIKit global appearances so every NavigationStack and TabView
// gets themed chrome without per-view modifier boilerplate. Called once at
// launch with the default (`.onyx` — the redesign's default palette) —
// settings haven't loaded yet at process init, and every SwiftUI-rendered
// view already gets the live theme via `\.gsTheme` regardless — then
// re-called by `ThemeStore` whenever the persisted/selected palette OR
// accent changes, so newly-created tab bars/nav bars pick up the live
// look instead of staying pinned to the launch default. ThemeStore always
// passes the ACCENT-OVERRIDDEN theme (`current.withAccent(accent)`), never
// the raw palette, so UIKit chrome tint matches the user's chosen accent.

enum GSAppearance {

    static func apply(theme: GSTheme = .onyx) {
        applyTabBar(theme: theme)
        applyNavigationBar(theme: theme)
    }

    // MARK: Tab bar
    //
    // Canvas dock treatment (values now sourced from the passed-in theme
    // rather than hardcoded — see the palette tables in GSTheme.swift):
    //   background  = theme.surface
    //   border-top  = theme.divider — 2 px rule
    //   selected    = theme.accent
    //   unselected  = theme.neutral500
    //   label font  = Archivo-Bold 10 pt (canvas: font-heading weight-800 10px)

    private static func applyTabBar(theme: GSTheme) {
        let surface    = UIColor(theme.surface)
        let accent     = UIColor(theme.accent)
        let unselected = UIColor(theme.neutral500)
        let divider    = UIColor(theme.divider)

        let labelFont  = UIFont(name: "Archivo-Bold", size: 10)
                      ?? UIFont.systemFont(ofSize: 10, weight: .bold)

        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = surface

        // 2 px divider on top edge
        appearance.shadowColor = divider
        appearance.shadowImage = UIImage.solidColor(
            divider,
            size: CGSize(width: 1, height: 2)
        )

        // Selected item attributes
        let selectedAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: accent
        ]
        // Unselected item attributes
        let normalAttrs: [NSAttributedString.Key: Any] = [
            .font: labelFont,
            .foregroundColor: unselected
        ]

        for state in [appearance.stackedLayoutAppearance,
                      appearance.inlineLayoutAppearance,
                      appearance.compactInlineLayoutAppearance] {
            state.selected.iconColor   = accent
            state.normal.iconColor     = unselected
            state.selected.titleTextAttributes   = selectedAttrs
            state.normal.titleTextAttributes     = normalAttrs
        }

        UITabBar.appearance().standardAppearance  = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    // MARK: Navigation bar
    //
    // Canvas nav treatment:
    //   background     = theme.surface
    //   title / large  = theme.text, Archivo-SemiBold
    //   back indicator = theme.accent

    private static func applyNavigationBar(theme: GSTheme) {
        let surface   = UIColor(theme.surface)
        let textColor = UIColor(theme.text)
        let accent    = UIColor(theme.accent)

        let titleFont = UIFont(name: "Archivo-SemiBold", size: 17)
                     ?? UIFont.systemFont(ofSize: 17, weight: .semibold)
        let largeTitleFont = UIFont(name: "Archivo-SemiBold", size: 34)
                          ?? UIFont.systemFont(ofSize: 34, weight: .semibold)

        let titleAttrs: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: textColor
        ]
        let largeTitleAttrs: [NSAttributedString.Key: Any] = [
            .font: largeTitleFont,
            .foregroundColor: textColor
        ]

        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = surface
        appearance.shadowColor     = .clear
        appearance.titleTextAttributes      = titleAttrs
        appearance.largeTitleTextAttributes = largeTitleAttrs

        UINavigationBar.appearance().standardAppearance   = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance    = appearance
        UINavigationBar.appearance().tintColor            = accent
    }
}

// MARK: - UIImage solid-colour helper (for tab-bar shadow rule)

private extension UIImage {
    /// Returns a 1×height solid-colour image, used to stamp the 2 px
    /// divider above the tab bar (UITabBarAppearance.shadowImage).
    static func solidColor(_ color: UIColor, size: CGSize) -> UIImage {
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
