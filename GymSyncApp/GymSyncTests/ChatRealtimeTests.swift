import XCTest
@testable import GymSync

final class ChatRealtimeTests: XCTestCase {
    func testInsertIsDeliveredToSubscriber() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Realtime Group")
        // Registered the instant the row exists. The `defer { Task { } }` this
        // replaces was detached: XCTest does not await it, so it could lose the
        // race with process exit — the defect
        // ModerationRepositoryTests.swift:20-27 records having been bitten by.
        addTeardownBlock {
            try? await GroupRepository.deleteGroup(groupID: group.id)
        }

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
    }

    func testSessionInsertIsDeliveredToSubscriber() async throws {
        try await TestAuth.signInIfConfigured()
        // Cleanup is the teardown block inside makeTempSoloSession, which
        // XCTest awaits — same discipline as the group above.
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
