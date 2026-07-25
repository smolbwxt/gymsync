import Foundation
import Supabase

// MARK: - Training Programs P1: enrollment model + repository
//
// Server contract: supabase/migrations/20260728000009_program_enrollments
// .sql (owner-only RLS, one-active-per-user partial unique index,
// ended_at/ended_reason pairing CHECK). Model + `enum XRepository`
// colocated per the small-repo idiom (Campaign.swift, Streak.swift).

/// `program_enrollments.focus` jsonb: `{"exercise_ids":[...]}` for the
/// lift-focused rules, `{"muscle_group":"quads"}` for hypertrophy — a
/// template picks ONE shape via its `ProgramFocusRule` (typed-over-
/// flexible, same as CampaignTarget).
struct ProgramFocus: Codable, Sendable, Equatable {
    var exerciseIDs: [UUID]? = nil
    var muscleGroup: String? = nil

    enum CodingKeys: String, CodingKey {
        case exerciseIDs = "exercise_ids"
        case muscleGroup = "muscle_group"
    }
}

/// A row of `program_enrollments`.
struct ProgramEnrollment: Decodable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let templateSlug: String
    let focus: ProgramFocus
    /// est-1RM lbs at enrollment, keyed by exercise UUID string (jsonb
    /// object keys are strings). Empty for volume-driven templates.
    let baseline: [String: Double]
    /// Raw DATE string from PostgREST ("yyyy-MM-dd") — the SessionSeries
    /// idiom (`SessionSeries.swift:7-16`): DATE columns must not go
    /// through the SDK's timestamp decoder. Use `startedOn` for math.
    let startedOnString: String
    let weeks: Int
    let endedAt: Date?
    let endedReason: String?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case templateSlug = "template_slug"
        case focus
        case baseline
        case startedOnString = "started_on"
        case weeks
        case endedAt = "ended_at"
        case endedReason = "ended_reason"
        case createdAt = "created_at"
    }

    /// Midnight of the start day in the device's calendar. A program week
    /// is a device-local concept (unlike SessionSeries, there is no
    /// per-row timezone — the enrollment follows its owner's phone).
    var startedOn: Date {
        let parts = startedOnString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return .distantPast }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            ?? .distantPast
    }

    var template: ProgramTemplate? { ProgramTemplate.bySlug(templateSlug) }

    /// Baseline for a specific focus lift, as the Decimal the math layer
    /// wants.
    func baselineValue(for exerciseID: UUID) -> Decimal? {
        baseline[exerciseID.uuidString.lowercased()].map { Decimal($0) }
            ?? baseline[exerciseID.uuidString].map { Decimal($0) }
    }
}

enum ProgramRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The user's single active enrollment (ended_at IS NULL), or nil.
    /// Fetches the user's enrollment rows (a handful at most — programs
    /// span weeks) and filters client-side rather than using PostgREST's
    /// `is.null` filter; the partial unique index guarantees at most one
    /// active row either way.
    static func active() async throws -> ProgramEnrollment? {
        guard let userID = await SupabaseService.shared.currentUserID() else { return nil }
        do {
            let rows: [ProgramEnrollment] = try await client
                .from("program_enrollments")
                .select()
                .eq("user_id", value: userID)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows.first { $0.endedAt == nil }
        } catch { throw ErrorMapping.map(error) }
    }

    private struct EnrollInsert: Encodable {
        let userID: UUID
        let templateSlug: String
        let focus: ProgramFocus
        let baseline: [String: Double]
        let startedOn: String
        let weeks: Int
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case templateSlug = "template_slug"
            case focus
            case baseline
            case startedOn = "started_on"
            case weeks
        }
    }

    /// Starts a program today. `baseline` keys are exercise UUID strings
    /// (lowercased); pass `[:]` for volume-driven templates — always an
    /// explicit value, never a server default (migration header).
    static func enroll(template: ProgramTemplate, focus: ProgramFocus,
                       baseline: [String: Double]) async throws -> ProgramEnrollment {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        do {
            let row: ProgramEnrollment = try await client
                .from("program_enrollments")
                .insert(EnrollInsert(
                    userID: userID,
                    templateSlug: template.slug,
                    focus: focus,
                    baseline: baseline,
                    startedOn: SessionSeries.dayString(for: .now, in: .current),
                    weeks: template.weeks.count
                ))
                .select()
                .single()
                .execute()
                .value
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    private struct StartedOnUpdate: Encodable {
        let startedOn: String
        enum CodingKeys: String, CodingKey { case startedOn = "started_on" }
    }

    /// "Repeat this week": shifts the whole plan forward 7 days (spec:
    /// manual deload = shift `started_on`; the math stays honest because
    /// the current week simply derives lower).
    static func repeatWeek(enrollment: ProgramEnrollment) async throws {
        let shifted = Calendar.current.date(byAdding: .day, value: 7, to: enrollment.startedOn)
            ?? enrollment.startedOn
        do {
            _ = try await client
                .from("program_enrollments")
                .update(StartedOnUpdate(startedOn: SessionSeries.dayString(for: shifted, in: .current)))
                .eq("id", value: enrollment.id)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct BaselineUpdate: Encodable {
        let baseline: [String: Double]
    }

    /// Explicit re-baseline from the program card (spec: "recorded as a
    /// new baseline value — still one tap, still transparent").
    static func reBaseline(enrollmentID: UUID, baseline: [String: Double]) async throws {
        do {
            _ = try await client
                .from("program_enrollments")
                .update(BaselineUpdate(baseline: baseline))
                .eq("id", value: enrollmentID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct EndUpdate: Encodable {
        let endedAt: Date
        let endedReason: String
        enum CodingKeys: String, CodingKey {
            case endedAt = "ended_at"
            case endedReason = "ended_reason"
        }
    }

    /// Ends the program — `reason` is 'completed' or 'abandoned' (the
    /// DB CHECK's two allowed values).
    static func end(enrollmentID: UUID, reason: String) async throws {
        do {
            _ = try await client
                .from("program_enrollments")
                .update(EndUpdate(endedAt: .now, endedReason: reason))
                .eq("id", value: enrollmentID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}
