import Foundation
import XCTest
@testable import GymSync

/// `ChatMessage.displayBody` — the legacy-flame strip and, more importantly,
/// its boundary.
///
/// Migration 20260906000003 stopped `public.announce_pr()` authoring a literal
/// "🔥 " prefix, but rows already in `chat_messages` keep theirs, so the client
/// strips it (design language §2: no decorative emoji — ChatView draws a real
/// SF flame beside the body).
///
/// The strip must stay narrow. `system_streak` bodies carry their own flame
/// from `push_streak_milestone_group()`
/// (20260719000008_streak_pushes.sql:163) — that is message text — and a
/// member's own "🔥 let's go" is content. Both must survive untouched. These
/// tests pin that line.
final class ChatMessageTests: XCTestCase {

    /// `ChatMessage` declares `init(from:)`, so it has no memberwise init —
    /// rows are built the way the app actually receives them, by decoding.
    private func makeMessage(kind: String, body: String?) throws -> ChatMessage {
        var object: [String: Any] = [
            "id": UUID().uuidString,
            "created_at": 0,
            "kind": kind,
        ]
        if let body { object["body"] = body }
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(ChatMessage.self, from: data)
    }

    func testLegacyPRAnnouncementLosesItsFlame() throws {
        let message = try makeMessage(
            kind: "system_pr",
            body: "🔥 sam hit a PR on Bench Press: 225 lbs")
        XCTAssertEqual(message.kind, .systemPR)
        XCTAssertEqual(message.displayBody, "sam hit a PR on Bench Press: 225 lbs")
    }

    func testCurrentPRAnnouncementIsUnchanged() throws {
        let body = "sam hit a PR on Bench Press: 225 lbs"
        let message = try makeMessage(kind: "system_pr", body: body)
        XCTAssertEqual(message.kind, .systemPR)
        XCTAssertEqual(message.displayBody, body)
    }

    /// The crew-streak announcement authors its own flame server-side. If the
    /// strip ever widens past `system_pr` this test is what catches it.
    func testStreakAnnouncementKeepsItsFlame() throws {
        let body = "🔥 Crew streak: 6 sessions strong!"
        let message = try makeMessage(kind: "system_streak", body: body)
        XCTAssertEqual(message.kind, .systemStreak)
        XCTAssertEqual(message.displayBody, body)
    }

    /// A member's own words are content, not chrome.
    func testMemberTextKeepsItsFlame() throws {
        let body = "🔥 let's go"
        let message = try makeMessage(kind: "text", body: body)
        XCTAssertEqual(message.kind, .text)
        XCTAssertEqual(message.displayBody, body)
    }

    func testNilBodyStaysNil() throws {
        let message = try makeMessage(kind: "system_pr", body: nil)
        XCTAssertEqual(message.kind, .systemPR)
        XCTAssertNil(message.displayBody)
    }
}
