import Foundation
import SwiftUI

@main
struct GymSyncApp: App {
    // Only hook for APNs' didRegisterForRemoteNotificationsWithDeviceToken /
    // UNUserNotificationCenterDelegate — SwiftUI's App protocol has no
    // native equivalent. See AppDelegate.swift.
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        try? AudioSessionManager.shared.configure()
        GSAppearance.apply()
    }
    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let id = ProcessInfo.processInfo.environment["UITEST_CATALOG"],
               let screen = CatalogScreen(rawValue: id) {
                // Catalog mode bypasses auth entirely, so ThemeStore.shared.current
                // never loads the CI user's persisted palette (it stays at its
                // .midnight seed). Force Ink here instead — matches the Ink design
                // proofs and the Ink tab captures the parity harness diffs catalog
                // screens against. Also re-stamp the UIKit appearance proxies (same
                // path ThemeStore.apply(paletteID:) uses on a real palette change)
                // so any nav/tab bar chrome inside the catalog screen is Ink-toned
                // too, instead of staying on the process-launch (.midnight) default.
                let _ = GSAppearance.apply(theme: .ink)
                CatalogHostView(screen: screen)
                    .environment(\.gsTheme, .ink)
            } else {
                RootView()
                    .environment(AuthService.shared)
            }
            #else
            RootView()
                .environment(AuthService.shared)
            #endif
        }
    }
}

// MARK: - GSAppearance
//
// Configures UIKit global appearances so every NavigationStack and TabView
// gets themed chrome without per-view modifier boilerplate. Called once at
// launch with the default (`.midnight`) — settings haven't loaded yet at
// process init, and every SwiftUI-rendered view already gets the live theme
// via `\.gsTheme` regardless — then re-called by `ThemeStore` (Canvas
// Completion Task 5) whenever the persisted/selected palette changes, so
// newly-created tab bars/nav bars pick up the live palette instead of
// staying pinned to midnight.

enum GSAppearance {

    static func apply(theme: GSTheme = .midnight) {
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
