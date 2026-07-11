import XCTest
import UIKit
@testable import GymSync

final class StorageServiceTests: XCTestCase {
    func testChatImageUploadAndSignedURLRoundTrip() async throws {
        try await TestAuth.signInIfConfigured()
        let group = try await GroupRepository.create(name: "CI Storage Group")
        defer { Task { try? await GroupRepository.deleteGroup(groupID: group.id) } }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 64, height: 64))
        let jpeg = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        }.jpegData(compressionQuality: 0.8)!

        let messageID = UUID()
        let path = try await StorageService.uploadChatImage(
            groupID: group.id, messageID: messageID, jpegData: jpeg)
        XCTAssertEqual(path,
            "\(group.id.uuidString.lowercased())/\(messageID.uuidString.lowercased()).jpg")

        let url = try await StorageService.signedChatImageURL(path: path)
        let (data, response) = try await URLSession.shared.data(from: url)
        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertGreaterThan(data.count, 100, "signed URL serves the uploaded JPEG")

        try await GroupRepository.deleteGroup(groupID: group.id)
    }
}
