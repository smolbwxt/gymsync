import SwiftUI

@main
struct GymSyncApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthService.shared)
        }
    }
}
