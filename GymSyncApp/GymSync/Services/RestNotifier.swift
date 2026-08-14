import Foundation
import UserNotifications

// MARK: - RestNotifier (owner 2026-08-14: "send push notification when
// rest timer is up")
//
// A LOCAL notification scheduled when a rest window opens and cancelled
// when it closes early — phone-in-pocket rests get a buzz the moment the
// bar wants them back. Rides the existing notification authorization
// (push registration already asked); foreground delivery is iOS's call,
// which is correct — the in-app timer is already on screen there.
//
// One identifier, always replaced: there is never more than one live
// rest window per lifter, so schedule() cancels the prior request first
// and a stale buzz can't outlive the rest that spawned it.
enum RestNotifier {
    private static let identifier = "rest-timer-done"

    static func schedule(at date: Date) {
        cancel()
        let seconds = date.timeIntervalSinceNow
        guard seconds > 5 else { return }   // sub-5s rests aren't worth a buzz
        let content = UNMutableNotificationContent()
        content.title = "Rest's up"
        content.body = "Back on the bar."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
    }

    static func cancel() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
