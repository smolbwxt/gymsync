import SwiftUI

@main
struct GymSyncApp: App {
    init() {
        try? AudioSessionManager.shared.configure()
        GSAppearance.apply()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthService.shared)
        }
    }
}

// MARK: - GSAppearance
//
// Configures UIKit global appearances once at launch so every
// NavigationStack and TabView gets the midnight chrome without
// per-view modifier boilerplate.

enum GSAppearance {

    static func apply() {
        applyTabBar()
        applyNavigationBar()
    }

    // MARK: Tab bar
    //
    // Canvas dock treatment:
    //   background  = surface  (#1e232c)
    //   border-top  = divider  (white 15%) — 2 px rule
    //   selected    = accent   (#38bdf8)
    //   unselected  = neutral500 (#6b7280)
    //   label font  = Archivo-Bold 10 pt (canvas: font-heading weight-800 10px)

    private static func applyTabBar() {
        let surface    = UIColor(hex: 0x1e232c)
        let accent     = UIColor(hex: 0x38bdf8)
        let unselected = UIColor(hex: 0x6b7280)
        let divider    = UIColor.white.withAlphaComponent(0.15)

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
    //   background     = surface (#1e232c)
    //   title / large  = text (#eef2f7), Archivo-SemiBold
    //   back indicator = accent (#38bdf8)

    private static func applyNavigationBar() {
        let surface   = UIColor(hex: 0x1e232c)
        let textColor = UIColor(hex: 0xeef2f7)
        let accent    = UIColor(hex: 0x38bdf8)

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

// MARK: - UIColor hex convenience (internal to this file)

private extension UIColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xff) / 255
        let g = CGFloat((hex >>  8) & 0xff) / 255
        let b = CGFloat( hex        & 0xff) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
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
