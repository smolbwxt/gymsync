import Foundation
import Supabase

struct Exercise: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let category: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let equipment: String
    let defaultUnit: String
    let demoVideoURL: URL?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case category
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case defaultUnit = "default_unit"
        case demoVideoURL = "demo_video_url"
    }
}

enum ExerciseRepository {
    static func fetchAll() async throws -> [Exercise] {
        do {
            let rows: [Exercise] = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func fetch(id: UUID) async throws -> Exercise? {
        do {
            let row: Exercise = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value
            return row
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
