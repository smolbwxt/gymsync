import XCTest
@testable import GymSync

/// Hermetic proof of Task 4's DSN-gated no-op path (master spec §6.8.5;
/// controller ruling: "no DSN at runtime → provably zero-effect no-op, SDK
/// not even started"). Fakes `CrashReportingStarting`
/// (Services/CrashReporting.swift) — same "protocol + production conformer
/// + test fake" seam idiom `OfflineSetLogQueueTests` uses for
/// `SetLogSubmitting` (Services/OfflineSetLogQueue.swift:13) — so this file
/// never imports Sentry or touches the real SDK.
@MainActor
final class CrashReportingTests: XCTestCase {

    // MARK: - Fake

    private final class FakeStarter: CrashReportingStarting {
        private(set) var startCallCount = 0
        private(set) var lastDSN: String?
        private(set) var lastEnvironment: String?
        private(set) var lastRelease: String?

        func start(dsn: String, environment: String, release: String) {
            startCallCount += 1
            lastDSN = dsn
            lastEnvironment = environment
            lastRelease = release
        }
    }

    // MARK: - Tests

    /// The core no-op proof: an empty DSN must not just leave `isEnabled`
    /// false, it must NEVER call the SDK-start seam at all — a
    /// call-count assertion, not just a state assertion, so a future bug
    /// that calls `starter.start` and then merely forgets to flip
    /// `isEnabled` would still fail this test.
    func test_emptyDSN_neverStartsSDK_andReportsDisabled() {
        let fake = FakeStarter()
        let sut = CrashReporting(starter: fake)

        sut.start(dsn: "", environment: "debug", release: "1")

        XCTAssertFalse(sut.isEnabled)
        XCTAssertEqual(fake.startCallCount, 0, "empty DSN must never reach SentrySDK.start")
    }

    /// Whitespace-only DSN (e.g. a stray newline from a misconfigured CI
    /// secret) must be treated the same as empty — see
    /// `CrashReporting.start`'s `trimmingCharacters` guard.
    func test_whitespaceOnlyDSN_neverStartsSDK() {
        let fake = FakeStarter()
        let sut = CrashReporting(starter: fake)

        sut.start(dsn: "   \n", environment: "debug", release: "1")

        XCTAssertFalse(sut.isEnabled)
        XCTAssertEqual(fake.startCallCount, 0)
    }

    func test_nonEmptyDSN_startsSDKExactlyOnce_andReportsEnabled() {
        let fake = FakeStarter()
        let sut = CrashReporting(starter: fake)

        sut.start(dsn: "https://public@o0.ingest.sentry.io/0", environment: "release", release: "42")

        XCTAssertTrue(sut.isEnabled)
        XCTAssertEqual(fake.startCallCount, 1)
        XCTAssertEqual(fake.lastDSN, "https://public@o0.ingest.sentry.io/0")
        XCTAssertEqual(fake.lastEnvironment, "release")
        XCTAssertEqual(fake.lastRelease, "42")
    }

    func test_disabledByDefault_beforeStartIsCalled() {
        let sut = CrashReporting(starter: FakeStarter())
        XCTAssertFalse(sut.isEnabled)
    }
}
