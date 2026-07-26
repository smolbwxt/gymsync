import XCTest
@testable import GymSync

/// Contract tests for the first-visit spotlights. These pin the properties
/// that make a tip system trustworthy — fires once, every tip is
/// resettable, copy actually exists — rather than the current wording.
final class GuidanceTipTests: XCTestCase {

    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for tip in GuidanceTip.allCases {
            if let value = UserDefaults.standard.object(forKey: tip.rawValue) {
                saved[tip.rawValue] = value
            }
        }
        GuidanceTip.allCases.forEach { $0.reset() }
    }

    override func tearDown() {
        GuidanceTip.allCases.forEach { $0.reset() }
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        super.tearDown()
    }

    func testSeenIsStickyPerTipAndIndependent() {
        let tip = GuidanceTip.home
        XCTAssertFalse(tip.hasBeenSeen)
        tip.markSeen()
        XCTAssertTrue(tip.hasBeenSeen)
        // Marking one tip must not mark any other — a shared key would make
        // the first screen you open swallow every other screen's tip.
        for other in GuidanceTip.allCases where other != tip {
            XCTAssertFalse(other.hasBeenSeen, "\(other.rawValue) was marked seen by \(tip.rawValue)")
        }
        tip.reset()
        XCTAssertFalse(tip.hasBeenSeen)
    }

    func testEveryTipHasDistinctVersionedKeyAndRealCopy() {
        let keys = GuidanceTip.allCases.map(\.rawValue)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate tip key")
        for tip in GuidanceTip.allCases {
            XCTAssertTrue(tip.rawValue.hasPrefix("tip."), "\(tip.rawValue) breaks the tip.* namespace")
            // Versioned so a meaningful copy rewrite can re-show the tip
            // instead of being invisible to everyone who saw the old one.
            XCTAssertTrue(tip.rawValue.contains(".v"), "\(tip.rawValue) is not versioned")
            XCTAssertFalse(tip.title.isEmpty, "\(tip.rawValue) has no title")
            XCTAssertFalse(tip.message.isEmpty, "\(tip.rawValue) has no message")
            XCTAssertFalse(tip.label.isEmpty, "\(tip.rawValue) has no QA label")
            XCTAssertLessThan(tip.title.count, 40, "\(tip.rawValue) title is too long for the card")
        }
    }

    /// The QA reset must cover every tip — that's the registry's whole job,
    /// and the failure is silent if a new tip escapes it.
    func testEveryTipIsRegisteredWithOneShotFlags() {
        let registered = Set(OneShotFlags.all.map(\.id))
        for tip in GuidanceTip.allCases {
            XCTAssertTrue(registered.contains(tip.rawValue),
                          "\(tip.rawValue) is not in OneShotFlags — the QA replay button would skip it")
        }
    }

    func testResetAllReplaysEveryTip() {
        GuidanceTip.allCases.forEach { $0.markSeen() }
        OneShotFlags.resetAll()
        for tip in GuidanceTip.allCases {
            XCTAssertFalse(tip.hasBeenSeen, "\(tip.rawValue) survived the QA reset")
        }
    }

    /// Tips default ON for a fresh install (no stored value) — a first-run
    /// system that defaults off teaches nobody.
    func testTipsDefaultOnWhenUnset() {
        UserDefaults.standard.removeObject(forKey: GuidanceTip.tipsEnabledKey)
        XCTAssertTrue(GuidanceTip.tipsEnabled)
        UserDefaults.standard.set(false, forKey: GuidanceTip.tipsEnabledKey)
        XCTAssertFalse(GuidanceTip.tipsEnabled)
        UserDefaults.standard.removeObject(forKey: GuidanceTip.tipsEnabledKey)
    }
}
