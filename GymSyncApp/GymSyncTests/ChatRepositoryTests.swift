import XCTest
@testable import GymSync

final class ChatRepositoryTests: XCTestCase {
    private var group: GymGroup!

    override func setUp() async throws {
        try await TestAuth.signInIfConfigured()
        group = try await GroupRepository.create(name: "CI Chat Group")
    }

    override func tearDown() async throws {
        if let group {
            try? await GroupRepository.deleteGroup(groupID: group.id)
        }
    }

    func testSendFetchReactReadLifecycle() async throws {
        // New group: no messages, no unread
        let empty = try await ChatRepository.messages(groupID: group.id)
        XCTAssertTrue(empty.isEmpty)
        let unreadEmpty = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertFalse(unreadEmpty, "empty chat has nothing unread")

        // Send
        let sent = try await ChatRepository.send(groupID: group.id, body: "hello ci")
        XCTAssertEqual(sent.kind, .text)
        XCTAssertEqual(sent.body, "hello ci")

        // Fetch newest-first
        let fetched = try await ChatRepository.messages(groupID: group.id)
        XCTAssertEqual(fetched.first?.id, sent.id)

        // Unread until marked read
        let unread = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertTrue(unread)
        try await ChatRepository.markRead(groupID: group.id, messageID: sent.id)
        let afterRead = try await ChatRepository.hasUnread(groupID: group.id)
        XCTAssertFalse(afterRead)

        // React / unreact
        try await ChatRepository.react(messageID: sent.id, emoji: "🔥")
        var reactions = try await ChatRepository.reactions(messageIDs: [sent.id])
        XCTAssertEqual(reactions.count, 1)
        XCTAssertEqual(reactions.first?.emoji, "🔥")
        try await ChatRepository.unreact(messageID: sent.id, emoji: "🔥")
        reactions = try await ChatRepository.reactions(messageIDs: [sent.id])
        XCTAssertTrue(reactions.isEmpty)
    }
}
