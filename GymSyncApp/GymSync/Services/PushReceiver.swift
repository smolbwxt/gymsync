import Foundation
import UIKit
import UserNotifications
import Supabase

/// APNs authorization + token registration, and the two idle-ladder action
/// RPC calls. Owns the round trip from "ask the user" through "token saved
/// to push_devices" — AppDelegate wires the actual UIKit/
/// UNUserNotificationCenter callbacks into this.
@MainActor
@Observable
final class PushReceiver {
    static let shared = PushReceiver()
    private init() {}

    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// Refreshes `authorizationStatus` from the current
    /// UNUserNotificationCenter settings — call on launch and whenever the
    /// app returns to foreground (the user may have flipped the OS toggle
    /// in Settings while backgrounded).
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Standard alert+sound+badge prompt (design doc: "Standard iOS
    /// prompt"). Returns the granted flag; `authorizationStatus` reflects
    /// the result afterward too.
    @discardableResult
    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            return granted
        } catch {
            AppLogger.push.error("requestAuthorization failed: \(error, privacy: .public)")
            await refreshAuthorizationStatus()
            return false
        }
    }

    /// Kicks off APNs registration only if the user has already granted
    /// authorization — calling `registerForRemoteNotifications()` pre-grant
    /// is harmless (no token callback fires until authorization exists
    /// anyway) but pointless, so gating here keeps every call site
    /// (onboarding, You tab re-entry, app launch) simple.
    func registerTokenIfAuthorized() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .authorized else { return }
        UIApplication.shared.registerForRemoteNotifications()
    }

    /// AppDelegate's `didRegisterForRemoteNotificationsWithDeviceToken`
    /// hands the raw token here; this persists it to `push_devices`.
    /// Best-effort — a failed upsert must never crash or block app launch
    /// (mirrors PersonalRecordRepository's "must never block" convention).
    func didReceiveToken(_ token: Data) async {
        do {
            try await PushDeviceRepository.upsert(token: token)
        } catch {
            AppLogger.push.error("push_devices upsert failed: \(error, privacy: .public)")
        }
    }

    func didFailToRegister(_ error: Error) {
        AppLogger.push.error("didFailToRegisterForRemoteNotifications: \(error, privacy: .public)")
    }

    #if DEBUG
    /// Debug-only seam for the design-parity screen catalog (Task 4): forces
    /// `authorizationStatus` so `CatalogHostView` can force-present
    /// `PushPrimingView`'s pre-prompt and denied states without a real
    /// UNUserNotificationCenter permission decision. `authorizationStatus`
    /// is `private(set)` above; this compiles here because it's the SAME
    /// FILE as that declaration (Swift's `private` access rule). Compiled
    /// out of release entirely.
    func debugSetAuthorizationStatus(_ status: UNAuthorizationStatus) {
        authorizationStatus = status
    }
    #endif

    // MARK: - Idle-ladder actions (IDLE_ACTIONS: Wrap Up / Still Going)
    //
    // DECISION (recorded per task brief — see task-5-report.md for the full
    // writeup): these run as NON-foreground UNNotificationActions, executing
    // a direct PostgREST RPC POST rather than routing through
    // SupabaseClient.rpc() from a `.foreground` action. `client.auth.session`
    // is an async, Keychain-backed getter that supabase-swift documents as
    // safe to call from any await context (it refreshes the access token if
    // needed); AppDelegate's `didReceive response:` has an async overload
    // (no completion-handler dance required), and UNNotificationAction
    // without `.foreground` grants the process background execution time to
    // finish an in-flight async call — the same "no app launch" contract the
    // design doc calls for on Wrap-Up/RSVP actions (line 1181). If this ever
    // proves unreliable in the field (e.g. the session getter blocks or
    // fails when the app hasn't run in a long time), the fallback is making
    // these `.foreground` actions and calling `SessionRepository`-style
    // `.rpc()` normally instead — everything below is isolated to this pair
    // of methods, so that swap wouldn't touch AppDelegate's routing switch.

    func wrapUpSession(_ sessionID: UUID) async {
        await callIdleRPC(name: "wrap_up_session", sessionID: sessionID)
    }

    func stillGoing(_ sessionID: UUID) async {
        await callIdleRPC(name: "still_going", sessionID: sessionID)
    }

    private func callIdleRPC(name: String, sessionID: UUID) async {
        do {
            let session = try await SupabaseService.shared.client.auth.session
            var request = URLRequest(
                url: Secrets.supabaseURL.appendingPathComponent("rest/v1/rpc/\(name)")
            )
            request.httpMethod = "POST"
            request.setValue(Secrets.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(["p_session": sessionID.uuidString])

            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                AppLogger.push.error("\(name) RPC returned status \(http.statusCode, privacy: .public)")
            }
        } catch {
            AppLogger.push.error("\(name) RPC failed: \(error, privacy: .public)")
        }
    }
}
