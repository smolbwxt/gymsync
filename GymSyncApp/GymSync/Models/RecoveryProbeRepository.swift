import Foundation

// MARK: - RecoveryProbe
//
// One question, asked after a session, about the LAST session's work:
// "how's your chest from Tuesday?" — re-asked until the athlete says they
// are back.
//
// Owner 2026-08-26: "we should have a probe after every session talking
// about recovery from the previous routine and track it until recovered."
//
// The value is the DURATION, not the answer. A one-shot "are you sore?"
// measures presence; what decides whether a dose exceeded someone's
// capacity is whether they turned up for the next session for that muscle
// still carrying the last one. So the probe stays open, and what
// VolumeTitration reads is how many days it took to close.
struct RecoveryProbe: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let muscle: String
    /// When the work being recovered FROM was done. The clock starts here,
    /// not when we first got round to asking.
    let trainedAt: Date
    var recoveredAt: Date?
    var lastState: String?
    var askedCount: Int
    var lastAskedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, muscle
        case trainedAt = "trained_at"
        case recoveredAt = "recovered_at"
        case lastState = "last_state"
        case askedCount = "asked_count"
        case lastAskedAt = "last_asked_at"
    }

    var state: VolumeTitration.RecoveryState? {
        lastState.flatMap(VolumeTitration.RecoveryState.init(rawValue:))
    }

    var observation: VolumeTitration.RecoveryObservation {
        .init(muscle: muscle, trainedAt: trainedAt,
              recoveredAt: recoveredAt, lastState: state)
    }
}

enum RecoveryProbeRepository {

    /// Probes still waiting on an answer, oldest work first — the muscle
    /// they trained longest ago is the one whose recovery matters most to
    /// know about.
    static func open() async throws -> [RecoveryProbe] {
        do {
            return try await SupabaseService.shared.client
                .from("recovery_probes")
                .select("id, muscle, trained_at, recovered_at, last_state, asked_count, last_asked_at")
                .is("recovered_at", value: nil)
                .order("trained_at", ascending: true)
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Closed probes for one muscle, newest first — what the titration
    /// reads.
    static func history(muscle: String, limit: Int = 6) async throws -> [RecoveryProbe] {
        do {
            return try await SupabaseService.shared.client
                .from("recovery_probes")
                .select("id, muscle, trained_at, recovered_at, last_state, asked_count, last_asked_at")
                .eq("muscle", value: muscle)
                .not("recovered_at", operator: .is, value: "null")
                .order("trained_at", ascending: false)
                .limit(limit)
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    /// Open a probe per muscle a session actually trained.
    ///
    /// Deliberately skips a muscle that already has an OPEN probe: if they
    /// have not told us they recovered from Tuesday's chest, asking about
    /// Thursday's chest as a separate question produces two open threads
    /// about the same muscle and no clean duration for either.
    static func openProbes(sessionID: UUID, userID: UUID,
                           muscles: Set<String>, trainedAt: Date) async throws {
        guard !muscles.isEmpty else { return }
        let alreadyOpen = Set((try? await open())?.map(\.muscle) ?? [])
        let fresh = muscles.subtracting(alreadyOpen)
        guard !fresh.isEmpty else { return }
        struct Insert: Encodable {
            let user_id: UUID
            let session_id: UUID
            let muscle: String
            let trained_at: Date
        }
        do {
            try await SupabaseService.shared.client
                .from("recovery_probes")
                .insert(fresh.map {
                    Insert(user_id: userID, session_id: sessionID,
                           muscle: $0, trained_at: trainedAt)
                })
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    /// Record an answer. A recovered state CLOSES the probe and stamps the
    /// duration; anything else leaves it open to be asked again.
    static func answer(id: UUID, state: VolumeTitration.RecoveryState,
                       now: Date = .now) async throws {
        struct Update: Encodable {
            let last_state: String
            let last_asked_at: Date
            let recovered_at: Date?
        }
        do {
            try await SupabaseService.shared.client
                .from("recovery_probes")
                .update(Update(last_state: state.rawValue,
                               last_asked_at: now,
                               recovered_at: state.isRecovered ? now : nil))
                .eq("id", value: id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}

// MARK: - VolumeTargetRepository
//
// What the search has settled on, per muscle. Separate from the profile
// because it is DERIVED: the profile holds what the athlete asked for,
// this holds what their body answered.
struct VolumeTarget: Codable, Equatable, Sendable {
    let muscle: String
    var weeklySets: Int
    var reason: String?

    enum CodingKeys: String, CodingKey {
        case muscle
        case weeklySets = "weekly_sets"
        case reason
    }
}

enum VolumeTargetRepository {
    static func all() async throws -> [VolumeTarget] {
        do {
            return try await SupabaseService.shared.client
                .from("volume_targets")
                .select("muscle, weekly_sets, reason")
                .execute().value
        } catch { throw ErrorMapping.map(error) }
    }

    static func set(muscle: String, weeklySets: Int, reason: String?,
                    userID: UUID) async throws {
        struct Upsert: Encodable {
            let user_id: UUID
            let muscle: String
            let weekly_sets: Int
            let reason: String?
            let updated_at: Date
        }
        do {
            try await SupabaseService.shared.client
                .from("volume_targets")
                .upsert(Upsert(user_id: userID, muscle: muscle,
                               weekly_sets: weeklySets, reason: reason,
                               updated_at: Date()))
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
