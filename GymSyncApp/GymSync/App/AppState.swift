import SwiftUI

@Observable
@MainActor
final class AppState {
    enum Tab: Hashable { case home, library, social, stats, you }
    var selectedTab: Tab = .home

    // Set to the user's profile once loaded post-sign-in.
    var currentProfile: Profile?
}
