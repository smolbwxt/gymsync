import Foundation
import Supabase

struct Routine: Codable, Identifiable, Sendable {
    let id: UUID
    let ownerID: UUID
    var name: String
    var description: String?
    let visibility: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case name
        case description
        case visibility
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum RoutineRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func fetchAll(ownerID: UUID) async throws -> [Routine] {
        do {
            let rows: [Routine] = try await client
                .from("routines")
                .select()
                .eq("owner_id", value: ownerID)
                .order("updated_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func fetch(id: UUID) async throws -> (Routine, [RoutineExercise])? {
        do {
            let routine: Routine = try await client
                .from("routines")
                .select()
                .eq("id", value: id)
                .single()
                .execute()
                .value

            let exercises: [RoutineExercise] = try await client
                .from("routine_exercises")
                .select()
                .eq("routine_id", value: id)
                .order("position", ascending: true)
                .execute()
                .value
            return (routine, exercises)
        } catch let error as PostgrestError where error.code == "PGRST116" {
            return nil
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func save(_ routine: Routine, exercises: [RoutineExercise]) async throws {
        do {
            _ = try await client.from("routines").upsert(routine).execute()
            _ = try await client.from("routine_exercises")
                .delete().eq("routine_id", value: routine.id).execute()
            if !exercises.isEmpty {
                _ = try await client.from("routine_exercises").insert(exercises).execute()
            }
        } catch { throw ErrorMapping.map(error) }
    }

    static func delete(id: UUID) async throws {
        do {
            _ = try await client.from("routines").delete().eq("id", value: id).execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
