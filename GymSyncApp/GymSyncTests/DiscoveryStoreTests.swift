import XCTest
@testable import GymSync

/// Contract tests for the depth-based discovery highlights.
final class DiscoveryStoreTests: XCTestCase {

    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for target in DiscoveryTarget.allCases {
            if let value = UserDefaults.standard.object(forKey: target.rawValue) {
                saved[target.rawValue] = value
            }
            UserDefaults.standard.removeObject(forKey: target.rawValue)
        }
        DiscoveryStore.shared.syncFromDefaults()
    }

    override func tearDown() {
        for target in DiscoveryTarget.allCases {
            UserDefaults.standard.removeObject(forKey: target.rawValue)
        }
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        DiscoveryStore.shared.syncFromDefaults()
        super.tearDown()
    }

    func testEverythingStartsNewAndClearsOnPress() {
        let target = DiscoveryTarget.socialLocal
        XCTAssertTrue(DiscoveryStore.shared.isNew(target))
        DiscoveryStore.shared.markPressed(target)
        XCTAssertFalse(DiscoveryStore.shared.isNew(target))
        // Pressing one control must not clear any other.
        for other in DiscoveryTarget.allCases where other != target {
            XCTAssertTrue(DiscoveryStore.shared.isNew(other), "\(other.rawValue) cleared by \(target.rawValue)")
        }
    }

    /// The registry's invariant: a flag's id IS its storage key. Discovery
    /// deliberately persists one bool per target rather than a single array
    /// under one key so this holds.
    func testStorageKeyIsTheTargetRawValue() {
        // Was `.homeSchedule` until Home v3 removed that target with the
        // widget it pointed at; any target proves the same invariant.
        let target = DiscoveryTarget.socialFeed
        DiscoveryStore.shared.markPressed(target)
        XCTAssertTrue(UserDefaults.standard.bool(forKey: target.rawValue))
        DiscoveryStore.shared.unmark(target)
        XCTAssertNil(UserDefaults.standard.object(forKey: target.rawValue))
    }

    /// The tab dot must appear only while something under that tab is
    /// undiscovered, and vanish once everything there is pressed —
    /// a dot outliving its reason is worse than no dot.
    func testTabRollupTracksItsOwnTargetsOnly() {
        // Three-tab restructure (2026-08-12): You rolls up three targets —
        // PROGRAMS (ex-Campaigns), DISCOVER widget, and Appearance.
        XCTAssertTrue(DiscoveryStore.shared.hasNew(in: .you))
        DiscoveryStore.shared.markPressed(.libraryCampaigns)
        XCTAssertTrue(DiscoveryStore.shared.hasNew(in: .you), "one of three You targets pressed — dot stays")
        DiscoveryStore.shared.markPressed(.libraryDiscover)
        XCTAssertTrue(DiscoveryStore.shared.hasNew(in: .you), "two of three You targets pressed — dot stays")
        DiscoveryStore.shared.markPressed(.youAppearance)
        XCTAssertFalse(DiscoveryStore.shared.hasNew(in: .you), "all three pressed — dot must clear")

        // An unrelated tab is unaffected by those presses.
        XCTAssertTrue(DiscoveryStore.shared.hasNew(in: .social))
    }

    func testEveryTargetIsRegisteredWithTheQAReset() {
        let registered = Set(OneShotFlags.all.map(\.id))
        for target in DiscoveryTarget.allCases {
            XCTAssertTrue(registered.contains(target.rawValue),
                          "\(target.rawValue) is missing from OneShotFlags — QA replay would skip it")
        }
    }

    func testQAResetRestoresEveryHighlight() {
        DiscoveryTarget.allCases.forEach { DiscoveryStore.shared.markPressed($0) }
        OneShotFlags.resetAll()
        for target in DiscoveryTarget.allCases {
            XCTAssertTrue(DiscoveryStore.shared.isNew(target),
                          "\(target.rawValue) stayed pressed after the QA reset")
        }
    }

    func testTargetsAreUniqueVersionedAndLabelled() {
        let keys = DiscoveryTarget.allCases.map(\.rawValue)
        XCTAssertEqual(Set(keys).count, keys.count, "duplicate discovery key")
        for target in DiscoveryTarget.allCases {
            XCTAssertTrue(target.rawValue.hasPrefix("disc."), "\(target.rawValue) breaks the disc.* namespace")
            XCTAssertTrue(target.rawValue.contains(".v"), "\(target.rawValue) is not versioned")
            XCTAssertFalse(target.label.isEmpty)
        }
    }
}
