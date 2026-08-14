import Foundation

// MARK: - LiveSessionTimerStore (owner bug 2026-08-14: "swiping down,
// then swiping up erases rest timer, and resets the set timer")
//
// The group session presents as a SHEET — swipe-down recoverable by
// design — but the view's @State dies with the sheet, so rejoining wiped
// the self-rotation rest window AND the recovery-pill drop history the
// session had learned. This in-memory, session-keyed store holds the
// timer anchors across the dismiss/rejoin cycle; the view re-seeds from
// it on appear and re-arms the window's auto-clear task (the original
// died with the view).
//
// Memory-only on purpose: anchors are meaningless across app launches
// (the session itself would have moved on), and rows are tiny.
@MainActor
final class LiveSessionTimerStore {
    static let shared = LiveSessionTimerStore()

    struct Snapshot {
        var restUntil: Date?
        var restStartedAt: Date?
        var restIsTransit: Bool = false
        var restDrops: [Int] = []
    }

    private var bySession: [UUID: Snapshot] = [:]

    private init() {}

    func snapshot(for sessionID: UUID) -> Snapshot? { bySession[sessionID] }

    func updateRest(sessionID: UUID, until: Date?, startedAt: Date?, isTransit: Bool) {
        var snap = bySession[sessionID] ?? Snapshot()
        snap.restUntil = until
        snap.restStartedAt = startedAt
        snap.restIsTransit = isTransit
        bySession[sessionID] = snap
    }

    func updateDrops(sessionID: UUID, drops: [Int]) {
        var snap = bySession[sessionID] ?? Snapshot()
        snap.restDrops = drops
        bySession[sessionID] = snap
    }

    func clear(sessionID: UUID) { bySession[sessionID] = nil }
}
