import XCTest
@testable import GymSync

/// `OneShotFlags` is the registry the QA "replay first-run tips" button
/// clears. Its failure mode is SILENT — a new tip that forgets to register
/// leaves the button looking like it works while testing less and less —
/// so these tests pin the contract rather than the current contents.
final class OneShotFlagsTests: XCTestCase {

    /// Snapshot + restore the real defaults so running the suite never
    /// wipes a developer's own first-run state.
    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for flag in OneShotFlags.all {
            if let value = UserDefaults.standard.object(forKey: flag.id) {
                saved[flag.id] = value
            }
        }
    }

    override func tearDown() {
        OneShotFlags.resetAll()
        for (key, value) in saved { UserDefaults.standard.set(value, forKey: key) }
        super.tearDown()
    }

    func testRegistryIsNonEmptyAndUniquelyIdentified() {
        XCTAssertFalse(OneShotFlags.all.isEmpty)
        let ids = OneShotFlags.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "duplicate flag id — two tips would clear each other's state")
        for flag in OneShotFlags.all {
            XCTAssertFalse(flag.label.isEmpty, "\(flag.id) has no human-readable label for the QA row")
        }
    }

    /// The registry's whole job: every registered flag is actually cleared.
    func testResetAllClearsEveryRegisteredFlag() {
        for flag in OneShotFlags.all {
            UserDefaults.standard.set(true, forKey: flag.id)
        }
        XCTAssertEqual(OneShotFlags.seenCount, OneShotFlags.all.count)

        OneShotFlags.resetAll()

        XCTAssertEqual(OneShotFlags.seenCount, 0)
        for flag in OneShotFlags.all {
            XCTAssertFalse(flag.isSet(), "\(flag.id) survived resetAll()")
        }
    }

    /// `isSet` must read the same storage `reset` writes — a flag whose
    /// accessor pair disagrees would report "seen" forever (or never), and
    /// the QA subtitle would lie about what a reset accomplished.
    func testIsSetAndResetAgreePerFlag() {
        for flag in OneShotFlags.all {
            UserDefaults.standard.set(true, forKey: flag.id)
            XCTAssertTrue(flag.isSet(), "\(flag.id): isSet() doesn't observe its own key")
            flag.reset()
            XCTAssertFalse(flag.isSet(), "\(flag.id): reset() doesn't clear what isSet() reads")
        }
    }

    /// The voice coach mark delegates through its owning store rather than
    /// duplicating a private key string — verify the delegation is wired.
    func testVoiceCoachMarkDelegatesToItsOwnStore() {
        VoiceCoachMarkStore.markShown()
        let flag = OneShotFlags.all.first { $0.id == VoiceCoachMarkStore.defaultsKey }
        XCTAssertTrue(flag?.isSet() ?? false)
        OneShotFlags.resetAll()
        XCTAssertFalse(VoiceCoachMarkStore.hasBeenShown)
    }

    /// Every flag's `id` must BE its UserDefaults key — the tests above set
    /// state by writing `flag.id` directly, and more importantly a registry
    /// whose id is a friendly alias would clear one key while reporting on
    /// another.
    func testFlagIDsAreRealDefaultsKeys() {
        for flag in OneShotFlags.all {
            UserDefaults.standard.removeObject(forKey: flag.id)
            XCTAssertFalse(flag.isSet(), "\(flag.id): isSet() true after clearing that exact key — id is not the storage key")
        }
    }
}
