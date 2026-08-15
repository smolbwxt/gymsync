import Foundation
import Supabase

// MARK: - Generator wave: program templates as DATA + the Plan queue
//
// Server contract: 20260814000009 (program_templates, program_template_weeks,
// program_purchases, training_plan_entries). The bundled code templates in
// Program.swift stay the curated v1 shelf; these DB rows are the bridge that
// gives a generated Coach program IDENTITY — a row the Plan can queue, a
// card the shelf can show, and (creator rail, later) a thing a purchase can
// unlock. Model + repository colocated per the small-repo idiom
// (Venue.swift, ProgramEnrollment.swift).

/// A row of `program_templates` — metadata only (globally readable; the
/// store page needs premium titles too). The WEEKS live in the child table
/// behind the entitlement gate.
struct ProgramTemplateRow: Decodable, Identifiable, Sendable, Equatable {
    let id: UUID
    let slug: String
    let name: String
    let summary: String
    /// overlay (prescriptions on YOUR routines) | takeover (ships its own
    /// week) — owner-pinned kinds, 2026-08-14.
    let kind: String
    let focusKind: String?
    let sessionsPerWeek: Int
    let durationWeeks: Int
    /// Set on curated creator uploads (invite-only rail); nil for
    /// generated and house templates.
    let creatorID: UUID?
    let isPremium: Bool
    let priceTier: String?
    let storekitProductID: String?
    /// Set on user-generated templates (Coach output); RLS scopes writes
    /// to this owner.
    let ownerID: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case slug
        case name
        case summary
        case kind
        case focusKind = "focus_kind"
        case sessionsPerWeek = "sessions_per_week"
        case durationWeeks = "duration_weeks"
        case creatorID = "creator_id"
        case isPremium = "is_premium"
        case priceTier = "price_tier"
        case storekitProductID = "storekit_product_id"
        case ownerID = "owner_id"
        case createdAt = "created_at"
    }
}

enum ProgramTemplateRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// Every template row (RLS: globally readable) — the shelf. Client
    /// filters/sorts; the table is small (house rows + the user's own
    /// generated blocks + invited creators).
    static func shelf() async throws -> [ProgramTemplateRow] {
        do {
            let rows: [ProgramTemplateRow] = try await client
                .from("program_templates")
                .select()
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    /// The signed-in user's own generated templates.
    static func mine() async throws -> [ProgramTemplateRow] {
        guard let userID = await SupabaseService.shared.currentUserID() else { return [] }
        do {
            let rows: [ProgramTemplateRow] = try await client
                .from("program_templates")
                .select()
                .eq("owner_id", value: userID)
                .order("created_at", ascending: false)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    private struct WeeksRow: Decodable {
        let weeks: [ProgramWeek]
    }

    /// A template's week summaries. The RLS entitlement gate lives on this
    /// child table — a premium template you haven't bought returns EMPTY
    /// (no row visible), which callers must render as locked, not broken.
    static func weeks(templateID: UUID) async throws -> [ProgramWeek] {
        do {
            let rows: [WeeksRow] = try await client
                .from("program_template_weeks")
                .select("weeks")
                .eq("template_id", value: templateID)
                .execute()
                .value
            return rows.first?.weeks ?? []
        } catch { throw ErrorMapping.map(error) }
    }

    private struct TemplateInsert: Encodable {
        let slug: String
        let name: String
        let summary: String
        let kind: String
        let focusKind: String?
        let sessionsPerWeek: Int
        let durationWeeks: Int
        let ownerID: UUID
        enum CodingKeys: String, CodingKey {
            case slug, name, summary, kind
            case focusKind = "focus_kind"
            case sessionsPerWeek = "sessions_per_week"
            case durationWeeks = "duration_weeks"
            case ownerID = "owner_id"
        }
    }

    private struct WeeksInsert: Encodable {
        let templateID: UUID
        let weeks: [ProgramWeek]
        enum CodingKeys: String, CodingKey {
            case templateID = "template_id"
            case weeks
        }
    }

    /// Persists a generated Coach program as a user-owned template row +
    /// its week summaries. Slug carries a UUID suffix — the column is
    /// globally UNIQUE and every generation is its own block. If the weeks
    /// insert fails the metadata row is best-effort removed so the shelf
    /// never shows a block with no content.
    static func saveGenerated(name: String, summary: String, focusKind: String,
                              sessionsPerWeek: Int, durationWeeks: Int,
                              weeks: [ProgramWeek]) async throws -> ProgramTemplateRow {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let slug = "coach-\(UUID().uuidString.prefix(8).lowercased())"
        do {
            let row: ProgramTemplateRow = try await client
                .from("program_templates")
                .insert(TemplateInsert(
                    slug: slug, name: name, summary: summary, kind: "takeover",
                    focusKind: focusKind, sessionsPerWeek: sessionsPerWeek,
                    durationWeeks: durationWeeks, ownerID: userID
                ))
                .select()
                .single()
                .execute()
                .value
            do {
                try await client
                    .from("program_template_weeks")
                    .insert(WeeksInsert(templateID: row.id, weeks: weeks))
                    .execute()
            } catch {
                try? await deleteOwn(templateID: row.id)
                throw error
            }
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    /// Delete an owned template (cascades to weeks + plan entries).
    static func deleteOwn(templateID: UUID) async throws {
        do {
            try await client
                .from("program_templates")
                .delete()
                .eq("id", value: templateID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }
}

// MARK: - The Plan (training_plan_entries — the macrocycle queue)

/// A row of `training_plan_entries`: one block in the user's queue
/// ("CBum 8-week, then a 1RM test block"). Owner-managed by RLS, plus
/// trainers holding calendar scope (T4 hook).
struct TrainingPlanEntry: Decodable, Identifiable, Sendable {
    let id: UUID
    let userID: UUID
    let templateID: UUID
    let position: Int
    /// Raw DATE string ("yyyy-MM-dd") — the SessionSeries idiom; nil until
    /// a block is scheduled.
    let startsOnString: String?
    /// queued | active | complete
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case templateID = "template_id"
        case position
        case startsOnString = "starts_on"
        case status
        case createdAt = "created_at"
    }
}

enum TrainingPlanRepository {
    private static var client: SupabaseClient { SupabaseService.shared.client }

    /// The signed-in user's queue, position-ordered.
    static func queue() async throws -> [TrainingPlanEntry] {
        guard let userID = await SupabaseService.shared.currentUserID() else { return [] }
        do {
            let rows: [TrainingPlanEntry] = try await client
                .from("training_plan_entries")
                .select()
                .eq("user_id", value: userID)
                .order("position", ascending: true)
                .execute()
                .value
            return rows
        } catch { throw ErrorMapping.map(error) }
    }

    private struct EntryInsert: Encodable {
        let userID: UUID
        let templateID: UUID
        let position: Int
        enum CodingKeys: String, CodingKey {
            case userID = "user_id"
            case templateID = "template_id"
            case position
        }
    }

    /// Appends a template to the end of the queue. Position derives from
    /// the current queue tail — a single user's own queue, so the read-
    /// then-write race window is theoretical.
    static func add(templateID: UUID) async throws -> TrainingPlanEntry {
        guard let userID = await SupabaseService.shared.currentUserID() else {
            throw GymSyncError.unauthorized
        }
        let next = ((try? await queue().map(\.position).max()) ?? 0) + 1
        do {
            let row: TrainingPlanEntry = try await client
                .from("training_plan_entries")
                .insert(EntryInsert(userID: userID, templateID: templateID, position: next))
                .select()
                .single()
                .execute()
                .value
            return row
        } catch { throw ErrorMapping.map(error) }
    }

    static func remove(entryID: UUID) async throws {
        do {
            try await client
                .from("training_plan_entries")
                .delete()
                .eq("id", value: entryID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct StatusUpdate: Encodable {
        let status: String
    }

    /// queued → active → complete (block transitions; the confirm nudge
    /// between blocks drives these).
    static func setStatus(entryID: UUID, status: String) async throws {
        do {
            try await client
                .from("training_plan_entries")
                .update(StatusUpdate(status: status))
                .eq("id", value: entryID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
    }

    private struct PositionUpdate: Encodable {
        let position: Int
    }

    /// Persists a full reorder: `orderedIDs` is the queue as the user left
    /// it; positions rewrite 1...n. Sequential updates — the queue is a
    /// handful of blocks, not a feed.
    static func reorder(orderedIDs: [UUID]) async throws {
        do {
            for (index, id) in orderedIDs.enumerated() {
                try await client
                    .from("training_plan_entries")
                    .update(PositionUpdate(position: index + 1))
                    .eq("id", value: id)
                    .execute()
            }
        } catch { throw ErrorMapping.map(error) }
    }
}
