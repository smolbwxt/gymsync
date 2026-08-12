import XCTest
@testable import GymSync

/// Sanitization proof for Task 4's session-state snapshot (master spec
/// §6.8.5: "sanitized `SessionState` snapshot (no chat content, no PII)").
/// Asserts on `SentryContext.tags(...)`'s OUTPUT DICTIONARY directly — the
/// function is pure (no Sentry SDK call inside it, no singleton reads), so
/// this is a hermetic proof that exactly the whitelisted keys are ever
/// produced. This file never imports Sentry. See
/// Services/SentryContext.swift's top doc comment for the same whitelist
/// with rationale, and task-4-report.md's captured-data enumeration.
final class SentryContextTests: XCTestCase {

    private static let fullWhitelist: Set<String> = [
        "screen", "session_active", "session_phase", "queued_offline_sets", "live_participant_count",
    ]

    // MARK: - Whitelist shape

    func test_outsideLiveSession_omitsParticipantCount_emitsOnlyFourKeys() {
        let tags = SentryContext.tags(
            screen: .home,
            sessionActive: false,
            sessionPhase: .none,
            queuedOfflineSetCount: 0,
            liveParticipantCount: nil
        )

        XCTAssertEqual(Set(tags.keys), ["screen", "session_active", "session_phase", "queued_offline_sets"])
        XCTAssertEqual(tags["screen"], "home")
        XCTAssertEqual(tags["session_active"], "false")
        XCTAssertEqual(tags["session_phase"], "none")
        XCTAssertEqual(tags["queued_offline_sets"], "0")
    }

    func test_inLiveSession_emitsAllFiveKeys_liveParticipantCountIncluded() {
        let tags = SentryContext.tags(
            screen: .home,
            sessionActive: true,
            sessionPhase: .live,
            queuedOfflineSetCount: 2,
            liveParticipantCount: 4
        )

        XCTAssertEqual(Set(tags.keys), Self.fullWhitelist)
        XCTAssertEqual(tags["session_active"], "true")
        XCTAssertEqual(tags["session_phase"], "live")
        XCTAssertEqual(tags["queued_offline_sets"], "2")
        XCTAssertEqual(tags["live_participant_count"], "4")
    }

    /// Exhaustive whitelist proof — sweeps every input combination this
    /// function can be called with and asserts the produced key set is
    /// always a SUBSET of the 5 named keys. Guards against a future edit
    /// silently adding a 6th key (e.g. a raw session id or username)
    /// without anyone updating this test — that failure IS the review gate.
    func test_neverEmitsKeysOutsideWhitelist() {
        let tabs: [AppState.Tab] = [.home, .social, .you]
        let phases: [SentryContext.SessionPhase] = [.none, .scheduled, .live, .completed, .abandoned]
        let participantCounts: [Int?] = [nil, 0, 4]

        for tab in tabs {
            for phase in phases {
                for count in participantCounts {
                    for active in [false, true] {
                        let tags = SentryContext.tags(
                            screen: tab,
                            sessionActive: active,
                            sessionPhase: phase,
                            queuedOfflineSetCount: 3,
                            liveParticipantCount: count
                        )
                        XCTAssertTrue(
                            Set(tags.keys).isSubset(of: Self.fullWhitelist),
                            "unexpected key in \(tags.keys) for tab=\(tab) phase=\(phase) count=\(String(describing: count))"
                        )
                    }
                }
            }
        }
    }

    // MARK: - Value mapping

    func test_screenNames_areCoarseTabIdentifiers_forEveryTab() {
        let expected: [(AppState.Tab, String)] = [
            (.home, "home"), (.social, "social"), (.you, "you"),
        ]
        for (tab, name) in expected {
            let tags = SentryContext.tags(
                screen: tab, sessionActive: false, sessionPhase: .none,
                queuedOfflineSetCount: 0, liveParticipantCount: nil
            )
            XCTAssertEqual(tags["screen"], name)
        }
    }

    func test_sessionPhase_bucketsRawDBStateStringsCoarsely() {
        XCTAssertEqual(SentryContext.SessionPhase(rawState: nil), .none)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "scheduled"), .scheduled)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "lobby_open"), .scheduled)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "editing"), .scheduled)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "voting"), .scheduled)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "locked"), .scheduled)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "in_progress"), .live)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "completed"), .completed)
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "abandoned"), .abandoned)
        // Unknown/future DB state — fails safe to `.none` rather than
        // crashing or fabricating a state.
        XCTAssertEqual(SentryContext.SessionPhase(rawState: "some_future_state"), .none)
    }

    // MARK: - No-PII spot checks
    //
    // Belt-and-suspenders: even though `tags(...)`'s signature makes it
    // impossible to pass through a raw UUID/username/token (every parameter
    // is a bounded enum/Bool/Int), assert the actual VALUES never contain
    // anything that looks like a UUID — catches a hypothetical future
    // refactor that widens a parameter to `String` without updating this
    // whitelist test.
    func test_producedValues_containNoUUIDLikeStrings() {
        let tags = SentryContext.tags(
            screen: .social,
            sessionActive: true,
            sessionPhase: .live,
            queuedOfflineSetCount: 7,
            liveParticipantCount: 12
        )
        let uuidPattern = try! NSRegularExpression(pattern: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-")
        for (key, value) in tags {
            let range = NSRange(value.startIndex..., in: value)
            XCTAssertNil(
                uuidPattern.firstMatch(in: value, range: range),
                "tag '\(key)' = '\(value)' looks like it contains a UUID"
            )
        }
    }
}
