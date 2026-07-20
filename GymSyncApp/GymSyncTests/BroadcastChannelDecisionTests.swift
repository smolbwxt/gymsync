import XCTest
@testable import GymSync

/// Hermetic tests for `BroadcastChannelDecision`'s pure decision core
/// (debt-zero sprint, I-1 channel-collision defensive fix —
/// `.superpowers/sdd/task-2-brief.md`). `decide(hasHeldChannel:
/// topicRegistered:)` is a plain, `@MainActor`-free static function over
/// two `Bool`s — no Supabase, no Realtime channel, no actor hop — same
/// "pure function extracted for hermetic testing" shape
/// `HeartRateThrottle.allowed(lastSentAt:now:minInterval:)` already
/// establishes (`HeartRateBroadcastServiceTests.swift`'s own throttle
/// tests). The SDK-interaction side (`HeartRateBroadcastService.publish`,
/// `SessionBroadcastService.broadcastRaw` actually calling
/// `client.realtimeV2.channels`/`client.channel(topic)`/`removeChannel`)
/// has no seam to fake the SDK behind and stays device-QA/CI territory —
/// gate finding I-1's named check is the empirical arbiter for those.
final class BroadcastChannelDecisionTests: XCTestCase {

    /// This instance's own held subscription always wins, regardless of
    /// what the client-wide registry shows — never re-derive from the
    /// registry when we already know our own channel.
    func testHeldChannelWinsRegardlessOfRegistry() {
        XCTAssertEqual(
            BroadcastChannelDecision.decide(hasHeldChannel: true, topicRegistered: false),
            .reuseHeld
        )
        XCTAssertEqual(
            BroadcastChannelDecision.decide(hasHeldChannel: true, topicRegistered: true),
            .reuseHeld
        )
    }

    /// No held channel, but the client-wide registry already has an entry
    /// for this topic (the I-1 cross-instance collision case: some OTHER
    /// holder — e.g. `GroupSessionLiveView`'s subscribed instance —
    /// registered this exact topic) — reuse it, don't create a disposable
    /// one.
    func testNoHeldChannelButTopicRegisteredReusesRegistry() {
        XCTAssertEqual(
            BroadcastChannelDecision.decide(hasHeldChannel: false, topicRegistered: true),
            .reuseRegistry
        )
    }

    /// Neither this instance nor the client-wide registry holds the
    /// topic — genuinely free, safe to create/subscribe/broadcast/remove.
    func testNoHeldChannelAndTopicUnregisteredCreatesDisposable() {
        XCTAssertEqual(
            BroadcastChannelDecision.decide(hasHeldChannel: false, topicRegistered: false),
            .createDisposable
        )
    }

    /// All four combinations map to exactly one of the three cases — no
    /// combination is left undecided (the function is total).
    func testAllFourCombinationsProduceADecision() {
        let cases: [(Bool, Bool)] = [(true, true), (true, false), (false, true), (false, false)]
        for (held, registered) in cases {
            let decision = BroadcastChannelDecision.decide(hasHeldChannel: held, topicRegistered: registered)
            XCTAssertTrue(
                [.reuseHeld, .reuseRegistry, .createDisposable].contains(decision),
                "held=\(held) registered=\(registered) produced an unexpected decision"
            )
        }
    }
}
