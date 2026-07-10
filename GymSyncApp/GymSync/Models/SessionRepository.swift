import Foundation
import Supabase

enum SessionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    static func startSolo(routineID: UUID?) async throws -> WorkoutSession {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let session = WorkoutSession(
                id: UUID(),
                routineID: routineID,
                organizerID: userID,
                state: "in_progress",
                startedAt: Date(),
                completedAt: nil,
                createdAt: Date()
            )
            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(session)
                .select().single().execute().value
            // Add self as sole participant (for RLS unification across phases)
            _ = try await client
                .from("session_participants")
                .insert([
                    "session_id": session.id.uuidString,
                    "user_id": userID.uuidString,
                    "turn_order": "1",
                    "check_in_state": "ready"
                ])
                .execute()
            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    static func complete(sessionID: UUID) async throws -> WorkoutSession {
        do {
            let updated: WorkoutSession = try await client
                .from("sessions")
                .update([
                    "state": "completed",
                    "completed_at": ISO8601DateFormatter().string(from: Date())
                ])
                .eq("id", value: sessionID)
                .select().single().execute().value
            return updated
        } catch { throw ErrorMapping.map(error) }
    }

    static func logSet(_ set: SetLog) async throws {
        do {
            _ = try await client.from("set_logs").insert(set).execute()
        } catch { throw ErrorMapping.map(error) }
    }

    static func history(userID: UUID, limit: Int) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("organizer_id", value: userID)
                .eq("state", value: "completed")
                .order("completed_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func setLogs(sessionID: UUID) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("session_id", value: sessionID)
                .order("set_index", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    static func exerciseHistory(userID: UUID, exerciseID: UUID, limit: Int) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .eq("exercise_id", value: exerciseID)
                .eq("is_failed", value: "false")
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: false)
                .limit(limit)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}
