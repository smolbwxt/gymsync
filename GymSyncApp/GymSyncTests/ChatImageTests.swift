import XCTest
import UIKit
@testable import GymSync

final class ChatImageTests: XCTestCase {
    func testSendImageInsertsImageMessageWithStoragePath() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Image Chat Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 128, height: 128))
        let png = renderer.image { ctx in
            UIColor.systemOrange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        }.pngData()!

        let sent = try await ChatRepository.sendImage(groupID: group.id, imageData: png)
        XCTAssertEqual(sent.kind, .image)
        XCTAssertNil(sent.body)
        let path = try XCTUnwrap(sent.storagePath)
        XCTAssertTrue(path.hasPrefix(group.id.uuidString.lowercased() + "/"))

        let fetched = try await ChatRepository.messages(groupID: group.id)
        XCTAssertEqual(fetched.first?.id, sent.id)
        XCTAssertEqual(fetched.first?.storagePath, path)

        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
