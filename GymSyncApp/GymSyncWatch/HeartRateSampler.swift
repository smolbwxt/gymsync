import Foundation
import HealthKit
import WatchConnectivity
import os

// MARK: - HeartRateSampler
//
// Phase W Task 5 (watch-hr design §4 + master spec §6.5 "HealthKit heart
// rate authorization + Watch integration"). Watch-side continuous HR
// sampler — started/stopped by `WatchSessionStore.syncHeartRateSampler()`
// whenever a new `sessionState` push arrives (that file's own doc comment
// covers the exact trigger).
//
// API PATTERN (cited, not invented): Apple's documented watchOS shape for
// continuous background heart-rate delivery is an ACTIVE `HKWorkoutSession`
// (the design brief's own instruction: "the workout session keeps delivery
// alive") paired with an `HKAnchoredObjectQuery` on `HKQuantityType(
// .heartRate)`. A bare `HKAnchoredObjectQuery` with no workout session gets
// throttled/suspended once the app backgrounds on watchOS; an active
// `HKWorkoutSession` is what keeps the process (and therefore the query's
// `updateHandler`) alive continuously for the session's duration — this is
// the standard "log a workout" pattern (`HKWorkoutSession` +
// `HKLiveWorkoutBuilder`, both introduced for watchOS in the HealthKit
// workout-session API), reused here PURELY as a background-execution
// vehicle: the builder's collected data is NEVER saved
// (`builder.discardWorkout()` on teardown, never `finishWorkout()`/
// `endCollection` followed by a save) — this app already exports the
// PHONE's own completed-session workout to Health separately
// (`Services/HealthKitBridge.swift.exportWorkout`), so a second, watch-side
// `HKWorkout` sample would be a duplicate Activity-ring entry, and the
// EPHEMERAL LAW (design §4/§6.5) forbids persisting heart-rate-bearing data
// at all. This is NOT the "standalone Watch workout" the design doc
// explicitly defers (§5, "Explicitly deferred... standalone Watch
// workouts") — that refers to a user-visible, Watch-native workout-tracking
// UI/flow; this session is invisible chrome purely for keeping HR delivery
// alive during an ALREADY-phone-driven live session.
//
// PERMISSION DISCIPLINE LAW: `requestAuthorization` is called from `start()`
// ONLY, and `start()` is only ever invoked by `WatchSessionStore
// .syncHeartRateSampler()` when a session is genuinely live AND
// `shareHeartRate` is genuinely true — i.e., on FIRST NEED, never at app
// launch (`GymSyncWatchApp.swift` never touches this type). If the user
// previously denied HR read access, `requestAuthorization` resolves without
// re-prompting (HealthKit's own documented behavior — a denied read
// permission via `requestAuthorization` is a silent no-op, not a repeat
// prompt) and the subsequent `HKAnchoredObjectQuery` simply yields zero
// samples; per master spec §6.5, that degraded state surfaces phone-side
// ("Heart rate sharing paused" + Settings deep-link) — out of THIS file's
// scope (no such surface exists in this task; this sampler only knows
// "yields nothing," not "why").
//
// NO TEST TARGET (same documented gap as `WatchSessionStore.swift`'s own
// header comment — this target has no unit-test bundle at all). CI proves
// only that this file compiles; every runtime behavior below (workout
// session lifecycle, authorization prompt, anchored-query delivery,
// discard-not-save teardown) is device-QA only. Listed in task-5-report.md.
@MainActor
final class HeartRateSampler: NSObject {
    static let shared = HeartRateSampler()

    private static let logger = Logger(subsystem: "app.gymsync.ios.watchkitapp", category: "heartrate")

    private let healthStore = HKHealthStore()
    private var workoutSession: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var anchoredQuery: HKAnchoredObjectQuery?
    private var isRunning = false

    /// Pure throttle core, reused from the phone side (`GymSyncShared/
    /// HeartRateThrottle.swift`'s own header comment explains why THIS file
    /// uses the static `allowed(lastSentAt:now:minInterval:)` function
    /// directly against a single local `Date?`, rather than the per-user
    /// stateful wrapper — the watch has no per-user concept, only its one
    /// wrist).
    private var lastSentAt: Date?
    private static let minSendInterval: TimeInterval = 5.0

    private override init() { super.init() }

    // MARK: - Lifecycle

    /// Starts sampling. Idempotent — a second call while already running is
    /// a no-op (mirrors `WatchConnectivityBridge.activateIfNeeded`'s own
    /// idempotency guard shape). Called ONLY from `WatchSessionStore
    /// .syncHeartRateSampler()` when `sessionState.isActive &&
    /// sessionState.shareHeartRate` — see that method for the gating logic;
    /// this type has no opinion on WHEN it should run, only HOW.
    func start() {
        guard !isRunning else { return }
        guard HKHealthStore.isHealthDataAvailable() else { return }
        isRunning = true
        Task {
            do {
                try await requestAuthorizationIfNeeded()
                try beginWorkoutSession()
                startAnchoredQuery()
            } catch {
                isRunning = false
                Self.logger.error("HeartRateSampler start failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Stops sampling — called when `isActive` goes false (session ended)
    /// OR `shareHeartRate` flips false (opt-out), per
    /// `WatchSessionStore.syncHeartRateSampler()`'s single combined guard.
    /// Idempotent. `builder.discardWorkout()`, never `finishWorkout()` —
    /// see this type's header comment on why nothing gets saved.
    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let anchoredQuery {
            healthStore.stop(anchoredQuery)
        }
        anchoredQuery = nil
        workoutSession?.end()
        // `builder.discardWorkout()` happens in the `HKWorkoutSessionDelegate`
        // callback below once the session actually reaches `.ended` — ending
        // a session is asynchronous (Apple's documented state-machine
        // transition), so discarding here immediately (before that
        // transition lands) would race an in-flight `beginCollection`.
    }

    // MARK: - HealthKit setup

    private func requestAuthorizationIfNeeded() async throws {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        try await healthStore.requestAuthorization(toShare: [], read: [heartRateType])
    }

    /// Apple's documented watchOS workout-session pattern: construct the
    /// session, derive its ASSOCIATED live builder (`associatedWorkoutBuilder()`
    /// — not a separately-constructed `HKLiveWorkoutBuilder`), attach a live
    /// data source, then start both the session's activity and the
    /// builder's collection. `config.activityType = .functionalStrengthTraining`
    /// matches the PHONE's own export config for the real completed-session
    /// workout (`Services/HealthKitBridge.swift`'s `exportWorkout`) purely
    /// for consistency — this session is never saved, so the activity type
    /// has no user-visible effect.
    private func beginWorkoutSession() throws {
        let config = HKWorkoutConfiguration()
        config.activityType = .functionalStrengthTraining
        config.locationType = .indoor

        let session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        let liveBuilder = session.associatedWorkoutBuilder()
        liveBuilder.dataSource = HKLiveWorkoutDataSource(healthStore: healthStore, workoutConfiguration: config)
        session.delegate = self
        liveBuilder.delegate = self

        let now = Date()
        session.startActivity(with: now)
        liveBuilder.beginCollection(withStart: now) { [weak self] success, error in
            if !success {
                Self.logger.error("HeartRateSampler beginCollection failed: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            }
            _ = self // silence unused-capture warning; nothing else to do on this callback
        }

        self.workoutSession = session
        self.builder = liveBuilder
    }

    /// Continuous HR delivery via `HKAnchoredObjectQuery` — both the
    /// initial results handler and `updateHandler` route through the same
    /// `handle(samples:)`, matching Apple's documented pattern for a
    /// long-lived anchored query (initial snapshot + ongoing updates are
    /// the same callback shape).
    private func startAnchoredQuery() {
        guard let heartRateType = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        let query = HKAnchoredObjectQuery(
            type: heartRateType, predicate: nil, anchor: nil, limit: HKObjectQueryNoLimit
        ) { [weak self] _, samples, _, _, error in
            self?.handle(samples: samples, error: error)
        }
        query.updateHandler = { [weak self] _, samples, _, _, error in
            self?.handle(samples: samples, error: error)
        }
        healthStore.execute(query)
        anchoredQuery = query
    }

    private nonisolated func handle(samples: [HKSample]?, error: Error?) {
        if let error {
            Self.logger.error("HeartRateSampler anchored query error: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let quantitySamples = samples as? [HKQuantitySample], !quantitySamples.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let unit = HKUnit.count().unitDivided(by: .minute())
            // Newest sample last per HealthKit's own ordering — only the
            // most recent one matters once throttled to 1/5s; iterating in
            // order lets the throttle's own `now` naturally advance instead
            // of firing once per queued sample in a backlog.
            for sample in quantitySamples {
                let bpm = Int(sample.quantity.doubleValue(for: unit).rounded())
                let now = Date()
                guard HeartRateThrottle.allowed(lastSentAt: self.lastSentAt, now: now, minInterval: Self.minSendInterval) else {
                    continue
                }
                self.lastSentAt = now
                await self.send(bpm: bpm, recordedAt: sample.endDate)
            }
        }
    }

    // MARK: - Send

    /// Sends via `hrSample` envelope kind, `sendMessage` (watch→phone,
    /// interactive — same wire kind/direction `WatchMessageKind.hrSample`'s
    /// own doc comment declares, `GymSyncShared/WatchEnvelope.swift`).
    /// No reply handling here: `WatchConnectivityBridge.handleHRSample`
    /// (phone side) does reply `.success`/`.failure`, but this sampler has
    /// no user-facing state to update from that reply the way `LogSetView`/
    /// `SoundboardView` do via `WatchSessionStore.logSet`/`tapSoundboard` —
    /// a dropped HR sample is simply the next one arriving in ~5s, honest
    /// fire-and-forget for a high-frequency ephemeral stream (same
    /// "ephemeral broadcast, missed events lost by design" philosophy
    /// `SessionBroadcastService`'s own header comment states for the
    /// phone-side broadcast this feeds).
    private func send(bpm: Int, recordedAt: Date) async {
        let payload = WatchHRSamplePayload(bpm: bpm, recordedAt: recordedAt)
        guard let envelope = try? WatchEnvelope.encode(kind: .hrSample, payload: payload),
              let message = try? envelope.asMessage() else { return }
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.sendMessage(message, replyHandler: nil, errorHandler: { error in
            Self.logger.error("HeartRateSampler send failed: \(error.localizedDescription, privacy: .public)")
        })
    }
}

// MARK: - HKWorkoutSessionDelegate

extension HeartRateSampler: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        guard toState == .ended else { return }
        Task { @MainActor [weak self] in
            guard let self, let builder = self.builder else { return }
            builder.endCollection(withEnd: date) { [weak self] _, error in
                if let error {
                    Self.logger.error("HeartRateSampler endCollection failed: \(error.localizedDescription, privacy: .public)")
                }
                // Discard, never save — see this type's header comment.
                builder.discardWorkout()
                Task { @MainActor in
                    self?.workoutSession = nil
                    self?.builder = nil
                }
            }
        }
    }

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        Self.logger.error("HeartRateSampler workout session failed: \(error.localizedDescription, privacy: .public)")
    }
}

// MARK: - HKLiveWorkoutBuilderDelegate
//
// No live-data collection handling needed here — HR delivery rides the
// `HKAnchoredObjectQuery` above, not the builder's own `didCollectDataOf:`
// callback (that callback fires for whatever the builder's `dataSource`
// collects, which this sampler never reads from). Both requirements are
// still mandatory to satisfy the protocol.
extension HeartRateSampler: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {}
}
