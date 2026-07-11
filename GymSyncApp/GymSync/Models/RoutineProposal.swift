import Foundation
import Supabase

// MARK: - Model

struct RoutineProposal: Codable, Identifiable, Sendable {
    let id: UUID
    let sessionID: UUID
    let proposerID: UUID
    let proposalType: ProposalType
    let status: Status
    let affectsExerciseID: UUID?
    let createdAt: Date
    let payload: [String: AnyJSON]?

    enum ProposalType: String, Codable, Sendable {
        case addExercise    = "add_exercise"
        case removeExercise = "remove_exercise"
        case editExercise   = "edit_exercise"
        case reorder        = "reorder"
    }

    enum Status: String, Codable, Sendable {
        case open, approved, vetoed, superseded
    }

    enum CodingKeys: String, CodingKey {
        case id
        case sessionID        = "session_id"
        case proposerID       = "proposer_id"
        case proposalType     = "proposal_type"
        case status
        case affectsExerciseID = "affects_exercise_id"
        case createdAt        = "created_at"
        case payload
    }
}

struct ProposalVote: Codable, Sendable {
    let proposalID: UUID
    let userID: UUID
    let vote: Vote

    enum Vote: String, Codable, Sendable {
        case approve, veto
    }

    enum CodingKeys: String, CodingKey {
        case proposalID = "proposal_id"
        case userID     = "user_id"
        case vote
    }
}

// MARK: - Payload helpers (typed wrappers over [String: AnyJSON])

extension RoutineProposal {
    /// Build a payload for add_exercise.
    /// IMPORTANT: `position` is intentionally omitted — the DB trigger computes MAX+1
    /// to avoid UNIQUE(routine_id,position) collisions.
    static func addExercisePayload(
        exerciseID: UUID,
        targetSets: Int? = nil,
        targetReps: String? = nil,
        targetWeight: String? = nil,
        restSeconds: Int? = nil
    ) -> [String: AnyJSON] {
        var d: [String: AnyJSON] = ["exercise_id": .string(exerciseID.uuidString)]
        if let v = targetSets   { d["target_sets"]   = .number(Double(v)) }
        if let v = targetReps   { d["target_reps"]   = .string(v) }
        if let v = targetWeight { d["target_weight"] = .string(v) }
        if let v = restSeconds  { d["rest_seconds"]  = .number(Double(v)) }
        return d
    }

    static func removeExercisePayload(routineExerciseID: UUID) -> [String: AnyJSON] {
        ["routine_exercise_id": .string(routineExerciseID.uuidString)]
    }

    static func editExercisePayload(
        routineExerciseID: UUID,
        targetSets: Int? = nil,
        targetReps: String? = nil,
        targetWeight: String? = nil,
        restSeconds: Int? = nil
    ) -> [String: AnyJSON] {
        var d: [String: AnyJSON] = ["routine_exercise_id": .string(routineExerciseID.uuidString)]
        if let v = targetSets   { d["target_sets"]   = .number(Double(v)) }
        if let v = targetReps   { d["target_reps"]   = .string(v) }
        if let v = targetWeight { d["target_weight"] = .string(v) }
        if let v = restSeconds  { d["rest_seconds"]  = .number(Double(v)) }
        return d
    }

    static func reorderPayload(orderedRoutineExerciseIDs: [UUID]) -> [String: AnyJSON] {
        let arr: AnyJSON = .array(orderedRoutineExerciseIDs.map { .string($0.uuidString) })
        return ["ordered_routine_exercise_ids": arr]
    }
}

// MARK: - Repository

enum ProposalRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    // Codable insert struct so the payload JSONB column encodes correctly.
    private struct ProposalInsert: Encodable {
        let id: UUID
        let sessionID: UUID
        let proposerID: UUID
        let proposalType: String
        let affectsExerciseID: UUID?
        let payload: [String: AnyJSON]

        enum CodingKeys: String, CodingKey {
            case id
            case sessionID        = "session_id"
            case proposerID       = "proposer_id"
            case proposalType     = "proposal_type"
            case affectsExerciseID = "affects_exercise_id"
            case payload
        }
    }

    /// Insert a new proposal. Returns the server row (which may already be
    /// `approved` when the session has exactly one participant).
    static func propose(
        sessionID: UUID,
        type: RoutineProposal.ProposalType,
        payload: [String: AnyJSON],
        affectsExerciseID: UUID? = nil
    ) async throws -> RoutineProposal {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row = ProposalInsert(
                id: UUID(),
                sessionID: sessionID,
                proposerID: me,
                proposalType: type.rawValue,
                affectsExerciseID: affectsExerciseID,
                payload: payload
            )
            let result: RoutineProposal = try await client
                .from("routine_proposals")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            return result
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Cast an approve or veto vote on an existing proposal.
    static func vote(proposalID: UUID, approve: Bool) async throws {
        guard let me = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            try await client
                .from("routine_proposal_votes")
                .insert([
                    "proposal_id": proposalID.uuidString,
                    "user_id":     me.uuidString,
                    "vote":        approve ? "approve" : "veto"
                ])
                .execute()
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Open proposals for a session, ordered oldest-first.
    static func open(sessionID: UUID) async throws -> [RoutineProposal] {
        do {
            let rows: [RoutineProposal] = try await client
                .from("routine_proposals")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .eq("status", value: "open")
                .order("created_at", ascending: true)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Votes for a set of proposals. Returns [] immediately when the input is empty.
    static func votes(proposalIDs: [UUID]) async throws -> [ProposalVote] {
        guard !proposalIDs.isEmpty else { return [] }
        do {
            let rows: [ProposalVote] = try await client
                .from("routine_proposal_votes")
                .select()
                .in("proposal_id", values: proposalIDs.map(\.uuidString))
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
