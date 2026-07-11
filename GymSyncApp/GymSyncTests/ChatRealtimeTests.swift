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
}
