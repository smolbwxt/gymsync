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

    /// Public (curator-published) routines with their owner's username, for
    /// the Library "Featured" shelf. Newest first — frame 3's hero is the
    /// newest publication.
    static func publicRoutines() async throws -> [(routine: Routine, ownerUsername: String)] {
        do {
            struct RowWithOwner: Decodable {
                let routine: Routine
                let owner: OwnerRef
                struct OwnerRef: Decodable { let username: String }
                init(from decoder: Decoder) throws {
                    routine = try Routine(from: decoder)
                    let c = try decoder.container(keyedBy: JoinKeys.self)
                    owner = try c.decode(OwnerRef.self, forKey: .profiles)
                }
                enum JoinKeys: String, CodingKey { case profiles }
            }
            let rows: [RowWithOwner] = try await client
                .from("routines")
                .select("*, profiles!routines_owner_id_fkey(username)")
                .eq("visibility", value: "public")
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows.map { ($0.routine, $0.owner.username) }
        } catch { throw ErrorMapping.map(error) }
    }

    /// "Add to my routines": copies a (public) routine + its exercises into a
    /// new private routine owned by the caller. Reads are allowed by the
    /// public-visibility RLS; writes are plain own-row inserts.
    static func clone(routineID: UUID) async throws -> Routine {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        guard let (source, exercises) = try await fetch(id: routineID) else {
            throw GymSyncError.notFound
        }
        let copy = Routine(
            id: UUID(), ownerID: userID, name: source.name,
            description: source.description, visibility: "private",
            createdAt: Date(), updatedAt: Date()
        )
        let copiedExercises = exercises.map { ex in
            RoutineExercise(
                id: UUID(), routineID: copy.id, exerciseID: ex.exerciseID,
                position: ex.position, targetSets: ex.targetSets,
                targetReps: ex.targetReps, targetWeight: ex.targetWeight,
                restSeconds: ex.restSeconds, notes: ex.notes
            )
        }
        try await save(copy, exercises: copiedExercises)
        return copy
    }

    /// Bulk routine_exercises lookup — backs the Library list's card body/tags/meta
    /// (needs every visible routine's exercises without N per-routine round-trips).
    static func exercisesForRoutines(ids: [UUID]) async throws -> [RoutineExercise] {
        guard !ids.isEmpty else { return [] }
        do {
            let rows: [RoutineExercise] = try await client
                .from("routine_exercises")
                .select()
                .in("routine_id", values: ids.map(\.uuidString))
                .order("position", ascending: true)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}
