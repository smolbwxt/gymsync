import XCTest
@testable import GymSync

final class ChatRealtimeTests: XCTestCase {
    func testInsertIsDeliveredToSubscriber() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Realtime Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let expectation = XCTestExpectation(description: "realtime insert delivered")
        let service = await ChatRealtimeService()

        await service.subscribe(groupID: group.id) { message in
            if message.body == "realtime ping" { expectation.fulfill() }
        }
        // Give the socket a beat to be fully joined before writing
        try await Task.sleep(for: .seconds(4))

        _ = try await ChatRepository.send(groupID: group.id, body: "realtime ping")

        await fulfillment(of: [expectation], timeout: 25)
        await service.unsubscribe()
        try await GroupRepository.deleteGroup(groupID: group.id)
    }

    func testSessionInsertIsDeliveredToSubscriber() async throws {
        try await TestAuth.signInIfConfigured()
        // No `defer { Task { } }` here: makeTempSoloSession registers the delete
        // with addTeardownBlock, which XCTest awaits. A detached task can lose
        // the race with process exit (ModerationRepositoryTests.swift:20-27).
        let session = try await makeTempSoloSession()

        let expectation = XCTestExpectation(description: "realtime insert delivered")
        let service = await ChatRealtimeService()

        await service.subscribe(sessionID: session.id) { message in
            if message.body == "realtime session ping" { expectation.fulfill() }
        }
        // Give the socket a beat to be fully joined before writing
        try await Task.sleep(for: .seconds(4))

        _ = try await ChatRepository.sendSessionMessage(
            sessionID: session.id, groupID: session.groupID, body: "realtime session ping")

        await fulfillment(of: [expectation], timeout: 25)
        await service.unsubscribe()
    }
}
