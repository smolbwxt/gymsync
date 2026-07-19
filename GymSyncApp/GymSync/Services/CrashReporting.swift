import Foundation
import Sentry

// MARK: - SDK-start seam

/// Abstracts the single `SentrySDK.start` call so `CrashReporting`'s
/// DSN-gating logic is hermetically testable — same "protocol + production
/// conformer + test fake" idiom as `OfflineSetLogQueue`'s `SetLogSubmitting`
/// seam (Services/OfflineSetLogQueue.swift:13, `SupabaseSetLogSubmitter`)
/// and `VoiceRoomService`'s `VoiceTokenFetching` seam
/// (Services/VoiceRoomService.swift:39) — a plain synchronous protocol with
/// no Sentry types in its signature, so `CrashReportingTests` never needs to
/// import Sentry either.
protocol CrashReportingStarting {
    func start(dsn: String, environment: String, release: String)
}

/// Production conformer — the ONLY place in the app that calls
/// `SentrySDK.start`. Configuration is deliberately narrow and sanitized per
/// master spec §6.8.5 ("Crash reports via Sentry. Each crash includes
/// sanitized `SessionState` snapshot (no chat content, no PII) for
/// reproducibility") — every auto-capture surface that could leak workout
/// data (weights/reps), chat content, or identifiers is explicitly turned
/// off below, rather than left to whatever the SDK's own default happens to
/// be for a given version. `SentryContext` (Services/SentryContext.swift) is
/// the ONLY other place in the app that talks to the SDK, and it sends
/// nothing but the 5-key tag whitelist documented there.
///
/// ASSUMPTION (not verified against the vendored Sentry package source — no
/// Mac/Xcode this session, matches `SupabaseVoiceTokenFetcher`'s identical
/// caveat at Services/VoiceRoomService.swift:48-53): every property below is
/// cited from Sentry Cocoa's own documented `SentryOptions` surface, highest
/// confidence first. If CI's build-test job fails to compile in this file,
/// check `enableAutoBreadcrumbTracking` first (least certain of the exact
/// property name across SDK versions) — `dsn`/`environment`/`releaseName`/
/// `sendDefaultPii`/`tracesSampleRate` are stable, long-documented names.
struct SentryCrashReportingStarter: CrashReportingStarting {
    func start(dsn: String, environment: String, release: String) {
        SentrySDK.start { options in
            options.dsn = dsn
            options.environment = environment
            options.releaseName = release

            // Crash reporting itself needs no explicit opt-in — installing
            // the crash handler is what `SentrySDK.start` exists to do.

            // No session replay. Sentry Cocoa only records replay frames
            // when `options.sessionReplay`'s sample rates are non-zero;
            // that sub-object is deliberately never touched here, so
            // replay stays off at the SDK's own zero-by-default rates —
            // the single riskiest surface for weights/reps/chat content
            // leaking into Sentry as literal screen recordings.
            options.attachScreenshot = false
            options.attachViewHierarchy = false

            // No automatic breadcrumbs (network requests, view-controller
            // lifecycle, etc.) — Supabase PostgREST URLs embed filter
            // values like `user_id=eq.<uuid>` in query strings, which
            // would violate the "no user ids beyond Sentry's default
            // install id" rule if auto-captured. `SentryContext`'s
            // explicit, whitelisted tags (Services/SentryContext.swift)
            // are the ONLY session-state data this integration sends —
            // see task-4-report.md for why custom AppLogger-sourced
            // breadcrumbs were skipped rather than added on top of this.
            options.enableAutoBreadcrumbTracking = false

            // Reviewer-caught (Phase O T4 review, verified against live
            // Sentry docs): these two are SEPARATE flags from
            // `enableAutoBreadcrumbTracking`, both default TRUE, and both
            // capture request URLs. `enableCaptureFailedRequests` is the
            // dangerous one — it promotes failed HTTP responses (e.g. an
            // RLS-denied Supabase call) to full Sentry ERROR EVENTS whose
            // URL embeds `user_id=eq.<uuid>` — the exact leak the comment
            // above exists to prevent.
            options.enableNetworkBreadcrumbs = false
            options.enableCaptureFailedRequests = false

            // No IP address / device-identifying PII beyond Sentry's own
            // install id (covers the "NO location" rule too — IP-based
            // geolocation is exactly what this flag would otherwise send).
            options.sendDefaultPii = false

            // No performance tracing/profiling — out of this task's scope
            // (crash reporting + context snapshot only).
            options.tracesSampleRate = 0
        }
    }
}

// MARK: - CrashReporting

/// DSN-gated Sentry wrapper (Phase O Task 4, master spec §6.8.5).
/// `@MainActor final class` singleton, matching this codebase's convention
/// for exactly this shape of service (`OfflineSetLogQueue.shared`,
/// `ConnectivityMonitor.shared`, `AppState.shared`).
///
/// Controller ruling: no Sentry DSN exists yet (USER ACTION — create a
/// Sentry project, add `SENTRY_DSN` to GitHub repo secrets + `.env.local`;
/// see Config/Secrets.swift.template). `start(dsn:environment:release:)`
/// with an empty/missing DSN is a PROVABLE no-op: `starter.start` is never
/// called at all (not called-then-ignored) — `CrashReportingTests` asserts
/// this via a call-count fake, the same hermetic proof shape
/// `OfflineSetLogQueueTests` uses for its submitter fake.
@MainActor
final class CrashReporting {
    static let shared = CrashReporting()

    /// True only after a genuine `SentrySDK.start` call (non-empty DSN).
    /// `SentryContext` (Services/SentryContext.swift) gates every scope
    /// write on this — so even if a call site forgets to check, no tag
    /// ever reaches a Sentry that was never started.
    private(set) var isEnabled = false

    private let starter: CrashReportingStarting

    init(starter: CrashReportingStarting = SentryCrashReportingStarter()) {
        self.starter = starter
    }

    /// Called once, from `GymSyncApp.init()`. `dsn` empty or whitespace-only
    /// → no-op (starter never invoked, `isEnabled` stays false) — this is
    /// the DSN-absent path the controller ruling requires to be provably
    /// zero-effect.
    func start(dsn: String, environment: String, release: String) {
        let trimmed = dsn.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            isEnabled = false
            return
        }
        starter.start(dsn: trimmed, environment: environment, release: release)
        isEnabled = true
    }
}
