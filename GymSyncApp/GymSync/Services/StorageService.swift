import Foundation
import Supabase

enum StorageService {
    static func uploadChatImage(groupID: UUID, messageID: UUID,
                                jpegData: Data) async throws -> String {
        let path = "\(groupID.uuidString.lowercased())/\(messageID.uuidString.lowercased()).jpg"
        do {
            try await SupabaseService.shared.client.storage
                .from("chat-images")
                .upload(path, data: jpegData,
                        options: FileOptions(contentType: "image/jpeg"))
            return path
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func signedChatImageURL(path: String) async throws -> URL {
        do {
            return try await SupabaseService.shared.client.storage
                .from("chat-images")
                .createSignedURL(path: path, expiresIn: 3600)
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func uploadGroupAvatar(groupID: UUID, jpegData: Data) async throws -> URL {
        let path = "groups/\(groupID.uuidString.lowercased()).jpg"
        do {
            try await SupabaseService.shared.client.storage
                .from("avatars")
                .upload(path, data: jpegData,
                        options: FileOptions(contentType: "image/jpeg", upsert: true))
            let publicURL = try SupabaseService.shared.client.storage
                .from("avatars")
                .getPublicURL(path: path)
            // Cache-buster: same path is overwritten on each change
            var components = URLComponents(url: publicURL, resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(
                name: "v", value: String(Int(Date().timeIntervalSince1970)))]
            return components?.url ?? publicURL
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
