import Foundation
import Sentry

/// Sanitized session-state snapshot (Phase O Task 4, master spec §6.8.5:
/// "Each crash includes sanitized `SessionState` snapshot (no chat content,
/// no PII) for reproducibility"). `tags(...)` is the sanitization contract:
/// a PURE function (no Sentry SDK call, no singleton reads) that produces
/// EXACTLY the whitelisted key set below and nothing else —
/// `SentryContextTests` asserts this exhaustively, so it never needs to
/// import Sentry either. `refreshAppWide()`/`refreshLiveSession(...)` are
/// the only call sites that read live app state and push it to the SDK.
///
/// CAPTURED-DATA ENUMERATION (the full whitelist — see task-4-report.md for
/// the same list with rationale):
///   - `screen`                 — coarse tab identifier: home/library/social/stats/you
///   - `session_active`         — Bool: is a live group session currently open on screen
///   - `session_phase`          — coarse DB-state bucket: none/scheduled/live/completed/abandoned
///   - `queued_offline_sets`    — Int COUNT of offline-queued set logs (never their contents)
///   - `live_participant_count` — Int COUNT of participants in the open live session (never who)
///
/// HARD RULE (never violated by this file): no user ids beyond Sentry's own
/// install id, no usernames/emails, no tokens, no message content, no
/// weights/reps values, no location. Every value above is a bounded
/// enum/Bool/Int — there is no String field wide enough to accidentally
/// carry any of those.
enum SentryContext {

    /// Coarse bucket of `WorkoutSession.state` (Models/Session.swift:7) — the
    /// DB's CHECK constraint is `'scheduled','lobby_open','editing','voting',
    /// 'locked','in_progress','completed','abandoned'`
    /// (supabase/migrations/20260709000006_create_sessions.sql:6-7). Buckets
    /// down to the tri-state the master spec names (scheduled/live/completed)
    /// plus `abandoned` (a real, equally non-sensitive terminal state) and
    /// `none` (no session in view) — never the raw DB string, never the
    /// session id.
    enum SessionPhase: String {
        case none
        case scheduled
        case live
        case completed
        case abandoned

        init(rawState: String?) {
            switch rawState {
            case "scheduled", "lobby_open", "editing", "voting", "locked":
                self = .scheduled
            case "in_progress":
                self = .live
            case "completed":
                self = .completed
            case "abandoned":
                self = .abandoned
            default:
                self = .none
            }
        }
    }

    /// Pure builder — the sanitization proof. See the enumeration in this
    /// file's top doc comment; `SentryContextTests` asserts the produced key
    /// set is always a subset of exactly these 5 names.
    static func tags(
        screen: AppState.Tab,
        sessionActive: Bool,
        sessionPhase: SessionPhase,
        queuedOfflineSetCount: Int,
        liveParticipantCount: Int?
    ) -> [String: String] {
        var tags: [String: String] = [
            "screen": screenName(screen),
            "session_active": sessionActive ? "true" : "false",
            "session_phase": sessionPhase.rawValue,
            "queued_offline_sets": String(queuedOfflineSetCount),
        ]
        if let liveParticipantCount {
            tags["live_participant_count"] = String(liveParticipantCount)
        }
        return tags
    }

    private static func screenName(_ tab: AppState.Tab) -> String {
        switch tab {
        case .home:   return "home"
        case .social: return "social"
        case .shop:   return "shop"
        case .you:    return "you"
        }
    }

    // MARK: - Live refresh call sites (Phase O Task 4 — "refreshed at
    // meaningful transitions: app foreground, session join/leave")

    /// App-wide refresh — App/RootView.swift's foreground hook. No
    /// live-session-specific data is observable from RootView (that's
    /// `GroupSessionLiveView`'s job, below), so this always reports
    /// `sessionPhase: .none` / `liveParticipantCount: nil` even if a live
    /// session happens to be open — self-corrects the moment
    /// `refreshLiveSession` next runs (its own foreground hook, or the
    /// join/leave hooks), and a momentarily-stale `session_phase` is never
    /// sensitive data either way.
    @MainActor
    static func refreshAppWide() {
        guard CrashReporting.shared.isEnabled else { return }
        let appState = AppState.shared
        apply(tags(
            screen: appState.selectedTab,
            sessionActive: appState.activeSessionID != nil,
            sessionPhase: .none,
            queuedOfflineSetCount: OfflineSetLogQueue.shared.pendingSetLogIDs.count,
            liveParticipantCount: nil
        ))
    }

    /// Live-session refresh — Features/Sessions/GroupSessionLiveView.swift's
    /// join (`.onAppear`), leave (`.onDisappear`), and in-session foreground
    /// (`.onChange(of: scenePhase)`) hooks, which have the real session state
    /// + roster count this call site can't see.
    @MainActor
    static func refreshLiveSession(rawState: String, participantCount: Int) {
        guard CrashReporting.shared.isEnabled else { return }
        let appState = AppState.shared
        apply(tags(
            screen: appState.selectedTab,
            sessionActive: true,
            sessionPhase: SessionPhase(rawState: rawState),
            queuedOfflineSetCount: OfflineSetLogQueue.shared.pendingSetLogIDs.count,
            liveParticipantCount: participantCount
        ))
    }

    /// Sole call site that touches the Sentry scope. Not seamed itself
    /// (unlike `CrashReporting.starter`): the sanitization-sensitive half of
    /// this feature is `tags(...)` above, which is already fully hermetic as
    /// a pure function — this half is one well-known SDK call with no
    /// branching logic left to prove.
    @MainActor
    private static func apply(_ tags: [String: String]) {
        SentrySDK.configureScope { scope in
            for (key, value) in tags {
                scope.setTag(value: value, key: key)
            }
        }
    }
}
