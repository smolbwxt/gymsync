import Foundation
import Supabase

enum SessionRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // MARK: - Room-code alphabet (no ambiguous chars: 0/O, 1/I/L)
    private static let roomCodeAlphabet = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")

    private static func makeRoomCode() -> String {
        String((0..<6).map { _ in roomCodeAlphabet.randomElement()! })
    }

    // MARK: - ISO8601 with fractional seconds (matches existing pattern)
    private static func iso8601Now() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    // MARK: - Existing methods (unchanged)

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
                createdAt: Date(),
                groupID: nil,
                roomCode: nil,
                scheduledFor: nil,
                seriesID: nil,
                currentTurnUserID: nil,
                currentTurnStartedAt: nil
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
                    "completed_at": iso8601Now()
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

    // MARK: - Phase 3a: Scheduling

    /// Schedule a session (group or ad-hoc). Inserts organizer + invitee participant rows.
    static func schedule(
        groupID: UUID?,
        inviteeIDs: [UUID],
        routineID: UUID?,
        scheduledFor: Date,
        generateRoomCode: Bool
    ) async throws -> WorkoutSession {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let sessionID = UUID()
            var row: [String: String] = [
                "id": sessionID.uuidString,
                "organizer_id": userID.uuidString,
                "state": "scheduled",
                "scheduled_for": ISO8601DateFormatter().string(from: scheduledFor)
            ]
            if let gid = groupID { row["group_id"] = gid.uuidString }
            if let rid = routineID { row["routine_id"] = rid.uuidString }
            if generateRoomCode { row["room_code"] = makeRoomCode() }

            let inserted: WorkoutSession = try await client
                .from("sessions")
                .insert(row)
                .select().single().execute().value

            // Organizer participant
            _ = try await client
                .from("session_participants")
                .insert([
                    "session_id": sessionID.uuidString,
                    "user_id": userID.uuidString,
                    "check_in_state": "online"
                ])
                .execute()

            // Invitee participants
            if !inviteeIDs.isEmpty {
                let inviteeRows = inviteeIDs.map { id in
                    ["session_id": sessionID.uuidString,
                     "user_id": id.uuidString,
                     "check_in_state": "invited"]
                }
                _ = try await client
                    .from("session_participants")
                    .insert(inviteeRows)
                    .execute()
            }

            return inserted
        } catch { throw ErrorMapping.map(error) }
    }

    /// Join a session by room code. Calls the SECURITY DEFINER RPC then fetches the session row.
    static func joinByCode(_ code: String) async throws -> WorkoutSession {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            let normalized = code.uppercased()
            let sessionID: UUID = try await client
                .rpc("join_session_by_code", params: ["p_code": normalized])
                .execute().value
            let session: WorkoutSession = try await client
                .from("sessions")
                .select()
                .eq("id", value: sessionID)
                .single()
                .execute().value
            return session
        } catch { throw ErrorMapping.map(error) }
    }

    /// Sessions where I am a participant with an active (pre-workout) state, ordered by scheduled_for.
    static func upcoming() async throws -> [WorkoutSession] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            // Two-step: my participant rows → sessions .in(ids)
            let participations: [SessionParticipant] = try await client
                .from("session_participants")
                .select()
                .eq("user_id", value: userID.uuidString)
                .execute().value
            guard !participations.isEmpty else { return [] }
            let sessionIDs = participations.map(\.sessionID.uuidString)
            let sessions: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .in("id", values: sessionIDs)
                .in("state", values: ["scheduled", "lobby_open", "editing", "voting", "locked"])
                .order("scheduled_for", ascending: true)
                .execute().value
            return sessions
        } catch { throw ErrorMapping.map(error) }
    }

    /// Participants for a session, joined with their profiles.
    static func participants(sessionID: UUID) async throws -> [(participant: SessionParticipant, profile: Profile)] {
        do {
            let rows: [SessionParticipant] = try await client
                .from("session_participants")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .execute().value
            let profiles = try await ProfileRepository.fetchMany(ids: rows.map(\.userID))
            let byID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
            return rows.compactMap { row in
                byID[row.userID].map { (participant: row, profile: $0) }
            }
        } catch { throw ErrorMapping.map(error) }
    }

    /// Transition session from 'scheduled' → 'lobby_open'. Idempotent (0 rows updated if already open).
    static func openLobby(sessionID: UUID) async throws {
        do {
            _ = try await client
                .from("sessions")
                .update(["state": "lobby_open"])
                .eq("id", value: sessionID.uuidString)
                .eq("state", value: "scheduled")
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Self check-in: updates own participant row with ready state, timestamp, and method.
    static func checkIn(sessionID: UUID, method: String) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _ = try await client
                .from("session_participants")
                .update([
                    "check_in_state": "ready",
                    "check_in_at": fmt.string(from: Date()),
                    "check_in_method": method
                ])
                .eq("session_id", value: sessionID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// All sessions for a group (upcoming + past), server-side filtered by group_id.
    /// Participant-only RLS automatically scopes results.
    static func groupSessions(groupID: UUID, pastLimit: Int = 10) async throws -> [WorkoutSession] {
        do {
            let rows: [WorkoutSession] = try await client
                .from("sessions")
                .select()
                .eq("group_id", value: groupID.uuidString)
                .order("scheduled_for", ascending: false)
                .limit(pastLimit + 20)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Fetch a single session row by ID. Returns nil if not found (PGRST116).
    static func session(id: UUID) async throws -> WorkoutSession? {
        do {
            let row: WorkoutSession = try await client
                .from("sessions")
                .select()
                .eq("id", value: id.uuidString)
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

    /// Reschedule a session by updating its `scheduled_for` timestamp.
    /// Organizer-only; enforced by DB policy.
    static func reschedule(sessionID: UUID, to newDate: Date) async throws {
        do {
            let fmt = ISO8601DateFormatter()
            fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            _ = try await client
                .from("sessions")
                .update(["scheduled_for": fmt.string(from: newDate)])
                .eq("id", value: sessionID.uuidString)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Start: atomically calls `start_session` RPC (lateness + turn-order + state flip).
    /// Signature unchanged — LobbyView untouched.
    static func start(sessionID: UUID) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .rpc("start_session", params: ["p_session_id": sessionID.uuidString])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Advance the turn to the next participant (current-lifter or organizer gated).
    static func advanceTurn(sessionID: UUID) async throws {
        guard await SupabaseService.shared.currentUserID() != nil else {
            throw GymSyncError.unauthorized
        }
        do {
            _ = try await client
                .rpc("advance_turn", params: ["p_session_id": sessionID.uuidString])
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// All set_logs for a session ordered by logged_at ascending.
    static func sessionSets(sessionID: UUID) async throws -> [SetLog] {
        do {
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .order("logged_at", ascending: true)
                .execute().value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }
}
