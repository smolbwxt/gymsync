import SwiftUI

@main
struct GymSyncApp: App {
    init() {
        try? AudioSessionManager.shared.configure()
    }
    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AuthService.shared)
        }
    }
}
