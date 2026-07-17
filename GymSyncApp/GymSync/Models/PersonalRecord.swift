import Foundation
import Supabase

struct PersonalRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let exerciseID: UUID
    let weight: Decimal
    let reps: Int
    let previousBest: Decimal
    let sessionID: UUID?
    let achievedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case exerciseID = "exercise_id"
        case weight
        case reps
        case previousBest = "previous_best"
        case sessionID = "session_id"
        case achievedAt = "achieved_at"
    }
}

/// One row of the `session_pr_counts` RPC result — a user's PR count
/// scoped to a single session. See `PersonalRecordRepository
/// .countsBySession` for why this exists alongside `bySession`/
/// `PersonalRecord` (Fix round 1, task-4-report.md Finding 1,
/// 20260720000002_session_pr_counts_and_kudos_guard.sql).
struct SessionPRCount: Decodable, Sendable {
    let userID: UUID
    let prCount: Int

    enum CodingKeys: String, CodingKey {
        case userID = "user_id"
        case prCount = "pr_count"
    }
}

enum PersonalRecordRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Best-effort PR log — called from both detection sites (solo + group live) after
    /// a `weight > priorMax` comparison. Callers should wrap with `try?`; a failed insert
    /// must never block or delay set logging.
    static func record(
        exerciseID: UUID,
        weight: Decimal,
        reps: Int,
        previousBest: Decimal,
        sessionID: UUID?
    ) async throws -> PersonalRecord {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            var row: [String: String] = [
                "id": UUID().uuidString,
                "user_id": userID.uuidString,
                "exercise_id": exerciseID.uuidString,
                "weight": "\(weight)",
                "reps": "\(reps)",
                "previous_best": "\(previousBest)"
            ]
            if let sessionID {
                row["session_id"] = sessionID.uuidString
            }
            let inserted: PersonalRecord = try await client
                .from("personal_records")
                .insert(row)
                .select()
                .single()
                .execute()
                .value
            return inserted
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Most recent PRs for a user, descending by `achieved_at`.
    static func recent(userID: UUID, limit: Int) async throws -> [PersonalRecord] {
        do {
            let rows: [PersonalRecord] = try await client
                .from("personal_records")
                .select()
                .eq("user_id", value: userID.uuidString)
                .order("achieved_at", ascending: false)
                .limit(limit)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// PRs achieved within a specific session, visible to the CALLING user
    /// only — `personal_records`' SELECT RLS is self-only (auth.uid() =
    /// user_id, 20260715000002_personal_records.sql:23-25), so despite
    /// filtering only on `session_id` this can never return a teammate's
    /// row. Correct for the "your PR" callout (`SessionRecapView`'s `myPR`
    /// and `GroupSessionLiveView`'s own heaviestPR card) — each needs
    /// exactly the caller's own PR detail (exercise/weight/reps/
    /// previousBest) for a session they participated in, which is
    /// inherently self-scoped by the product itself, not just by RLS.
    /// `CompletedSessionView` has no own-PR-detail card and does NOT call
    /// this — it renders only counts, entirely via `countsBySession` below
    /// (Fast-follow wave, Fix 1; the 20260720000002 migration's "Scope
    /// note" — lines 28-38 — assumed CompletedSessionView/SessionRecapView
    /// were both self-scoped-only callers safe to leave on `bySession`;
    /// that was inaccurate for their COUNT uses, which is exactly what this
    /// fix corrects. That migration is applied/append-only and cannot be
    /// edited — corrected here instead).
    ///
    /// Do NOT use this for a crew-wide PR COUNT (total or per-participant)
    /// — that was Finding 1 (task-4-report.md): a group recap built from
    /// this call alone rendered 0 PRs for every teammate but whoever's
    /// device fetched it. Use `countsBySession` for that instead.
    static func bySession(sessionID: UUID) async throws -> [PersonalRecord] {
        do {
            let rows: [PersonalRecord] = try await client
                .from("personal_records")
                .select()
                .eq("session_id", value: sessionID.uuidString)
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// TRUE per-user PR counts for a session, across ALL participants —
    /// backs the group recap's hero "PRS" total (sum) and every leaderboard
    /// row's "N PR" badge (`GroupSessionLiveView.buildGroupRecapPayload`).
    /// Also backs the equivalent COUNT-only spots in the history/legacy
    /// recap views (`CompletedSessionView`'s PRS tile + per-member badges,
    /// `SessionRecapView`'s PRS pill + per-member badges) as of the
    /// Fast-follow wave, Fix 1 — those two were left on `bySession` when
    /// this RPC was first added (see `bySession`'s doc comment) and
    /// undercounted teammates the same way `buildGroupRecapPayload` did
    /// before Fix round 1.
    /// Calls the `session_pr_counts` SECURITY DEFINER RPC (Fix round 1 —
    /// task-4-report.md Finding 1,
    /// 20260720000002_session_pr_counts_and_kudos_guard.sql) instead of
    /// `bySession`: `bySession` is a direct `personal_records` select gated
    /// by SELF-ONLY SELECT RLS, so for a real multi-lifter group session the
    /// caller only ever got back their own rows — every teammate's PRs were
    /// silently dropped, not aggregated wrong. The RPC instead gates on
    /// session participation and aggregates server-side across every
    /// participant's rows (see `session_pr_counts_test.sql`). A user with
    /// zero PRs in the session produces no row — callers should default to 0
    /// on lookup miss, same as `SessionKudosRepository.counts`'s dictionary
    /// shape.
    static func countsBySession(sessionID: UUID) async throws -> [SessionPRCount] {
        do {
            let rows: [SessionPRCount] = try await client
                .rpc("session_pr_counts", params: ["p_session_id": sessionID.uuidString])
                .execute()
                .value
            return rows
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    /// Count of PRs achieved on/after `date` — backs the "PRs this month" stat tile.
    static func countSince(userID: UUID, date: Date) async throws -> Int {
        do {
            let isoFmt = ISO8601DateFormatter()
            isoFmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            struct IDRow: Decodable { let id: UUID }
            let rows: [IDRow] = try await client
                .from("personal_records")
                .select("id")
                .eq("user_id", value: userID.uuidString)
                .gte("achieved_at", value: isoFmt.string(from: date))
                .execute()
                .value
            return rows.count
        } catch {
            throw ErrorMapping.map(error)
        }
    }
}
