import UIKit
import UserNotifications

/// UIApplicationDelegate + UNUserNotificationCenterDelegate, wired into
/// GymSyncApp via `@UIApplicationDelegateAdaptor`. SwiftUI's `App` protocol
/// has no direct hook for `didRegisterForRemoteNotificationsWithDeviceToken`
/// or UNUserNotificationCenterDelegate callbacks (needed for push action
/// buttons per design doc line 1181), so an AppDelegate is required even in
/// an otherwise-SwiftUI-native app.
///
/// Explicitly `@MainActor` (rather than relying on the SDK's own delegate-
/// protocol isolation annotations, which vary by SDK version) so every
/// method here can freely touch `AppState.shared` / `PushReceiver.shared`
/// (both `@MainActor`-isolated) without an extra `await` — matches how
/// UIKit/UserNotifications actually invoke these callbacks (always on the
/// main thread).
@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        UNUserNotificationCenter.current().setNotificationCategories(NotificationCategories.all)
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { await PushReceiver.shared.didReceiveToken(deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushReceiver.shared.didFailToRegister(error)
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// Foreground presentation. Suppresses the banner (`[]`) when the push's
    /// thread-id matches whatever live session/chat the user already has
    /// open (push-dossier.md §B.7 — they're already seeing the same content
    /// via Realtime); otherwise shows banner + sound. thread-id is set by
    /// push-dispatcher's payloads.ts to a session_id or group_id string (see
    /// `aps["thread-id"]` in dispatchBatch, index.ts) — comparing it against
    /// AppState's UUIDs as strings avoids a parse failure branch on every
    /// push that has no thread-id at all (friend_request).
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        let threadID = notification.request.content.threadIdentifier
        guard !threadID.isEmpty else { return [.banner, .sound] }

        let appState = AppState.shared
        if appState.activeSessionID?.uuidString == threadID { return [] }
        if appState.activeChatGroupID?.uuidString == threadID { return [] }
        return [.banner, .sound]
    }

    /// Tap / action-button routing.
    ///
    /// - IDLE_ACTIONS' WRAP_UP / STILL_GOING are non-foreground actions —
    ///   they execute the RPC directly via PushReceiver and return, no UI
    ///   routing (see PushReceiver.swift's doc comment for why these run in
    ///   the background).
    /// - Everything else (the default tap, and FRIEND_REQUEST's `.foreground`
    ///   Accept/Decline actions) opens the app and routes via
    ///   `AppState.selectedTab` + `.pendingRoute`, consumed by HomeView /
    ///   SocialTabView.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        let category = content.categoryIdentifier
        let sessionID = UUID(uuidString: content.threadIdentifier)

        switch response.actionIdentifier {
        case NotificationCategories.ActionID.wrapUp:
            if let sessionID { await PushReceiver.shared.wrapUpSession(sessionID) }
            return
        case NotificationCategories.ActionID.stillGoing:
            if let sessionID { await PushReceiver.shared.stillGoing(sessionID) }
            return
        case UNNotificationDismissActionIdentifier:
            // Swiped away without tapping — must NOT trigger navigation.
            return
        default:
            break
        }

        let appState = AppState.shared
        switch category {
        case NotificationCategories.ID.sessionInvite, NotificationCategories.ID.openLobby:
            appState.selectedTab = .home
            if let sessionID { appState.pendingRoute = .lobby(sessionID: sessionID) }

        case NotificationCategories.ID.openSession,
             NotificationCategories.ID.idleActions,
             NotificationCategories.ID.roast:
            appState.selectedTab = .home
            if let sessionID { appState.pendingRoute = .session(sessionID: sessionID) }

        case NotificationCategories.ID.sessionView:
            // partner_pr / chat_mention (group-shaped thread-id) and
            // session_reminder_15min (session-shaped thread-id) all share
            // this one category (see payloads.ts's CATEGORY doc comment) —
            // a bare UUID can't tell us which kind it is. v1 lands on the
            // Social tab without attempting a chat deep-link: right for 2 of
            // the 3 underlying events, and safer than guessing GroupView(
            // group:) for what might actually be a session_id. Documented
            // gap, not a bug — see task-5-report.md.
            appState.selectedTab = .social

        case NotificationCategories.ID.friendRequest:
            // No requester ID is available here (payloads.ts's friend_request
            // case sets no thread-id — see NotificationCategories' doc
            // comment), so both the default tap and the Accept/Decline
            // actions just open Social → Friends, where FriendsView's
            // existing incoming-requests UI (FriendRepository.accept/
            // removeFriendship) completes the action.
            appState.selectedTab = .social
            appState.pendingRoute = .friends

        default:
            break
        }
    }
}

// MARK: - NotificationCategories

enum NotificationCategories {
    enum ID {
        static let friendRequest = "FRIEND_REQUEST"
        static let sessionInvite = "SESSION_INVITE"
        static let sessionView   = "SESSION_VIEW"
        static let openLobby     = "OPEN_LOBBY"
        static let openSession   = "OPEN_SESSION"
        static let roast         = "ROAST"
        static let idleActions   = "IDLE_ACTIONS"
    }

    enum ActionID {
        static let wrapUp        = "WRAP_UP"
        static let stillGoing    = "STILL_GOING"
        static let friendAccept  = "FRIEND_ACCEPT"
        static let friendDecline = "FRIEND_DECLINE"
    }

    /// Registered once at launch. IDs must match exactly what
    /// push-dispatcher emits as `aps.category`
    /// (supabase/functions/push-dispatcher/payloads.ts's `CATEGORY` const)
    /// — that file is the single source of truth on the server side; there's
    /// no shared Swift/TS type; a mismatch here means the OS silently shows
    /// no action buttons for that category (not a crash), so keep these two
    /// lists in sync by hand if either changes.
    ///
    /// Only IDLE_ACTIONS and FRIEND_REQUEST get custom `UNNotificationAction`s
    /// — the two the Task 5 contract specifies concrete backend wiring for.
    /// The other five categories register with zero custom actions (default
    /// tap only): SESSION_INVITE's "Decline" and similar buttons implied by
    /// the design doc's event table (push-dossier.md §A.3) aren't backed by
    /// an existing repository call from a bare push payload here, and
    /// shipping a button that doesn't actually do what it says would be
    /// worse than not having it — left for a follow-up task. Default tap
    /// still routes every category to a sensible destination (see
    /// `didReceive(response:)` above).
    static let all: Set<UNNotificationCategory> = [
        UNNotificationCategory(
            identifier: ID.friendRequest,
            actions: [
                UNNotificationAction(identifier: ActionID.friendAccept, title: "Accept", options: [.foreground]),
                UNNotificationAction(identifier: ActionID.friendDecline, title: "Decline", options: [.foreground]),
            ],
            intentIdentifiers: [],
            options: []
        ),
        UNNotificationCategory(identifier: ID.sessionInvite, actions: [], intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: ID.sessionView, actions: [], intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: ID.openLobby, actions: [], intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: ID.openSession, actions: [], intentIdentifiers: [], options: []),
        UNNotificationCategory(identifier: ID.roast, actions: [], intentIdentifiers: [], options: []),
        UNNotificationCategory(
            identifier: ID.idleActions,
            actions: [
                // No `.foreground` option — these dispatch as background
                // actions, no app launch (design doc line 1181).
                UNNotificationAction(identifier: ActionID.wrapUp, title: "Wrap Up", options: []),
                UNNotificationAction(identifier: ActionID.stillGoing, title: "Still Going", options: []),
            ],
            intentIdentifiers: [],
            options: []
        ),
    ]
}
