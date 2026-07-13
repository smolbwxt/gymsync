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

    /// All of a user's set logs since `since`, excluding failed/penalty —
    /// backs the Stats weekly-volume chart. Mirrors `exerciseHistory`'s
    /// failed/penalty exclusion filters exactly.
    static func recentSetLogs(userID: UUID, since: Date) async throws -> [SetLog] {
        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let rows: [SetLog] = try await client
                .from("set_logs")
                .select()
                .eq("user_id", value: userID)
                .gte("logged_at", value: isoFmt.string(from: since))
                .eq("is_failed", value: "false")
                .eq("is_penalty", value: "false")
                .order("logged_at", ascending: true)
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
            // Server-side inner join on my participant rows. The previous
            // two-step (fetch ALL participations, then sessions .in(ids))
            // fanned every historical session ID into the request URL and
            // returned 400 once a user accumulated a few hundred sessions.
            let sessions: [WorkoutSession] = try await client
                .from("sessions")
                .select("*, session_participants!inner(user_id)")
                .eq("session_participants.user_id", value: userID.uuidString)
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

    /// Bulk session lookup — backs Exercise History's "· solo" / "· {group}"
    /// meta suffix (needs each logged set's session to know its `group_id`).
    static func sessions(ids: [UUID]) async throws -> [WorkoutSession] {
        guard !ids.isEmpty else { return [] }
        do {
            // Chunked: .in(ids) rides the request URL, which caps out around
            // a couple hundred UUIDs (see upcoming()'s 400 regression).
            var rows: [WorkoutSession] = []
            for chunk in stride(from: 0, to: ids.count, by: 100).map({ Array(ids[$0..<min($0 + 100, ids.count)]) }) {
                let batch: [WorkoutSession] = try await client
                    .from("sessions")
                    .select()
                    .in("id", values: chunk.map(\.uuidString))
                    .execute()
                    .value
                rows.append(contentsOf: batch)
            }
            return rows
        } catch { throw ErrorMapping.map(error) }
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

    /// Client foreground heartbeat — resets the idle-ladder's activity clock
    /// while any participant has the app open on a live session
    /// (push-dossier.md §A.4: "app foreground >5s" counts as activity; v1
    /// fires once per scenePhase → active transition, no polling timer).
    /// No-ops server-side (0 rows updated, no error) if the session isn't
    /// in_progress — a heartbeat arriving just after a session ends is a
    /// harmless straggler, not something callers need to special-case.
    static func touchActivity(sessionID: UUID) async throws {
        do {
            _ = try await client
                .rpc("touch_session_activity", params: ["p_session": sessionID.uuidString])
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

    // MARK: - Phase 3b: Duration editing

    /// Edit a completed session's start/end timestamps.
    ///
    /// Validates:
    ///   - `newCompletedAt > newStartedAt`
    ///   - Both new values are within ±48 h of the ORIGINAL session times
    ///
    /// On success:
    ///   1. Inserts a `session_duration_edits` audit row (old + new values, edited_by me).
    ///   2. Updates `sessions` (started_at, completed_at, duration_was_edited = true, edited_by = me).
    ///
    /// HealthKit re-write on edit is deferred to Phase 3c polish.
    /// TODO(3c): after a successful edit, call HealthKitBridge.replaceWorkout(session:) to
    ///           update the Health sample's duration to match the corrected timestamps.
    static func editDuration(
        sessionID: UUID,
        newStartedAt: Date,
        newCompletedAt: Date,
        reason: String?
    ) async throws {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }

        // Client-side validation: order must be correct.
        guard newCompletedAt > newStartedAt else {
            throw GymSyncError.validation("End time must be after start time.")
        }

        do {
            // Fetch the current session to obtain current stored values (used for the audit row).
            guard let existing = try await session(id: sessionID) else {
                throw GymSyncError.notFound
            }
            guard existing.state == "completed" else {
                throw GymSyncError.validation("Only completed sessions can be edited.")
            }

            // ±48 h anchor rule: always measure against the ORIGINAL times, not the current
            // stored values. The earliest audit row preserves the old_* values from the very
            // first edit (which recorded the session's as-completed times). If no audit row
            // exists this is the first edit, so fall back to the current stored values.
            struct EarliestAuditRow: Decodable {
                let old_started_at: String?
                let old_completed_at: String?
            }
            let earliestRows: [EarliestAuditRow] = try await client
                .from("session_duration_edits")
                .select("old_started_at,old_completed_at")
                .eq("session_id", value: sessionID.uuidString)
                .order("edited_at", ascending: true)
                .limit(1)
                .execute().value

            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            // Derive anchor dates from the earliest audit row when available.
            let anchorStart: Date?
            let anchorEnd: Date?
            if let earliest = earliestRows.first {
                anchorStart = earliest.old_started_at.flatMap { isoFmt.date(from: $0) }
                    ?? existing.startedAt
                anchorEnd = earliest.old_completed_at.flatMap { isoFmt.date(from: $0) }
                    ?? existing.completedAt
            } else {
                anchorStart = existing.startedAt
                anchorEnd   = existing.completedAt
            }

            let fortyEightHours: TimeInterval = 48 * 3600

            if let anchor = anchorStart {
                guard abs(newStartedAt.timeIntervalSince(anchor)) <= fortyEightHours else {
                    throw GymSyncError.validation("New start time must be within 48 hours of the original start.")
                }
            }
            if let anchor = anchorEnd {
                guard abs(newCompletedAt.timeIntervalSince(anchor)) <= fortyEightHours else {
                    throw GymSyncError.validation("New end time must be within 48 hours of the original end.")
                }
            }

            // 1. Insert audit row (Codable struct for type safety).
            // old_* values always reflect the CURRENT stored values so the chain is auditable;
            // the anchor for ±48 h validation is handled separately above.
            struct DurationEditInsert: Encodable {
                let id: String
                let session_id: String
                let edited_by: String
                let old_started_at: String?
                let old_completed_at: String?
                let new_started_at: String
                let new_completed_at: String
                let reason: String?
            }
            let auditRow = DurationEditInsert(
                id:               UUID().uuidString,
                session_id:       sessionID.uuidString,
                edited_by:        userID.uuidString,
                old_started_at:   existing.startedAt.map   { isoFmt.string(from: $0) },
                old_completed_at: existing.completedAt.map { isoFmt.string(from: $0) },
                new_started_at:   isoFmt.string(from: newStartedAt),
                new_completed_at: isoFmt.string(from: newCompletedAt),
                reason:           reason
            )

            _ = try await client
                .from("session_duration_edits")
                .insert(auditRow)
                .execute()

            // 2. Update session row.
            _ = try await client
                .from("sessions")
                .update([
                    "started_at":          isoFmt.string(from: newStartedAt),
                    "completed_at":        isoFmt.string(from: newCompletedAt),
                    "duration_was_edited": "true",
                    "edited_by":           userID.uuidString
                ])
                .eq("id", value: sessionID.uuidString)
                .execute()

        } catch let e as GymSyncError {
            throw e
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Old start/end timestamps from the most recent duration-edit audit row —
    /// backs the "Duration edited by X · was Y" audit line on Session Detail.
    static func latestDurationEdit(sessionID: UUID) async throws -> (oldStartedAt: Date?, oldCompletedAt: Date?)? {
        struct AuditRow: Decodable {
            let old_started_at: String?
            let old_completed_at: String?
        }
        do {
            let rows: [AuditRow] = try await client
                .from("session_duration_edits")
                .select("old_started_at,old_completed_at")
                .eq("session_id", value: sessionID.uuidString)
                .order("edited_at", ascending: false)
                .limit(1)
                .execute().value
            guard let row = rows.first else { return nil }
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            return (
                oldStartedAt: row.old_started_at.flatMap { isoFmt.date(from: $0) },
                oldCompletedAt: row.old_completed_at.flatMap { isoFmt.date(from: $0) }
            )
        } catch { throw ErrorMapping.map(error) }
    }

    // MARK: - Phase 3b/Canvas Task 3: Burpee Ledger

    /// Group-wide crew debts (Fix round 1 — task-3-report.md). Calls the
    /// `group_burpee_ledger` SECURITY DEFINER RPC instead of querying
    /// `session_participants` directly: the direct query was gated by
    /// "readable by other participants" RLS, so a member who joined the
    /// group after some of its sessions had already run was never invited to
    /// those sessions and couldn't see their `session_participants` rows —
    /// silently undercounting EVERY crew member's total, not just their own.
    /// The RPC instead gates on current group membership and sums across
    /// every session the group has run, regardless of who was invited to
    /// which one (see `burpee_ledger_rpc_test.sql`).
    static func burpeeLedger(groupID: UUID) async throws -> [BurpeeLedgerMath.CrewDebt] {
        do {
            let aggregates: [GroupBurpeeLedgerAggregate] = try await client
                .rpc("group_burpee_ledger", params: ["p_group": groupID.uuidString])
                .execute().value
            return BurpeeLedgerMath.crewDebts(aggregates: aggregates)
        } catch { throw ErrorMapping.map(error) }
    }

    /// The current user's OWN `session_participants` rows for the group,
    /// joined with the session fields the "YOU OWE" banner's detail line
    /// needs (late minutes, per-minute rate, date, live-session id). Kept as
    /// a direct query (not the RPC above): a user's own rows are always RLS
    /// -visible via "user_id = auth.uid()" regardless of current group
    /// membership timing, so there's no undercount risk here to fix — see
    /// `BurpeeLedgerMath.youOweSummary`.
    static func myBurpeeLedgerRows(groupID: UUID) async throws -> [BurpeeLedgerRow] {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let rows: [BurpeeLedgerRow] = try await client
                .from("session_participants")
                .select("user_id, check_in_state, late_minutes, burpees_owed, sessions!inner(id, state, scheduled_for, started_at, late_penalty)")
                .eq("sessions.group_id", value: groupID.uuidString)
                .eq("user_id", value: userID.uuidString)
                .execute().value
            return rows
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
