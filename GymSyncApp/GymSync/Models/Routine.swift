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
                // Open-publishing round (20260728000008): everyone can publish
                // public now, so the Library FEATURED shelf filters to the
                // curator-managed spotlight — is_featured is RLS-gated to
                // curators. Discover remains the all-public surface.
                .eq("is_featured", value: true)
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

    // MARK: - Phase L Task 4: publish fields (default_sort/scoring_metrics/
    // scoring_top_set_exercise_id)
    //
    // These 3 columns (+ is_featured) were added fix-forward to `routines` in
    // Task 1 (`supabase/migrations/20260723000001_public_workout_repository.
    // sql:29-35`) but deliberately NOT added as `Routine` stored properties —
    // see `PublicWorkout.swift`'s doc comment: `RoutineBuilderView.save()`
    // (below, `save()`) constructs a brand-new `Routine(...)` from scratch on
    // every edit, so widening `Routine` would silently reset these fields to
    // their defaults on every unrelated save (an "unpublish" regression for
    // is_featured/default_sort/etc, parallel to the one that file's own
    // `publishAsFeatured` comment already warns about for `visibility`).
    // These two methods keep that surface OFF `Routine`/`save()` entirely: a
    // narrow read (to seed the publish-fields UI when editing an
    // already-published routine) and a narrow, targeted UPDATE of exactly
    // these 3 columns (called only when publishing) — never routed through
    // `save()`'s full-row upsert.

    struct PublishFields: Decodable {
        let defaultSort: String?
        let scoringMetrics: [String]?
        let scoringTopSetExerciseID: UUID?
        /// Open-publishing round (20260728000008): the curator spotlight flag,
        /// seeded into the builder's Feature toggle.
        let isFeatured: Bool?
        enum CodingKeys: String, CodingKey {
            case defaultSort = "default_sort"
            case scoringMetrics = "scoring_metrics"
            case scoringTopSetExerciseID = "scoring_top_set_exercise_id"
            case isFeatured = "is_featured"
        }
    }

    /// Seeds `RoutineBuilderView`'s publish-fields UI when `editing` is an
    /// already-published routine — same "must read the current value before
    /// overwriting it" discipline `RoutineBuilderView.load()`'s
    /// `publishAsFeatured = editing.visibility == "public"` line already
    /// documents for `visibility`. Read-only; owner/curator/public-visibility
    /// RLS (`20260717000003_curation.sql`) already covers this exactly like
    /// every other `routines` SELECT in this file — no new policy needed.
    static func publishFields(routineID: UUID) async throws -> PublishFields? {
        do {
            let row: PublishFields = try await client
                .from("routines")
                .select("default_sort, scoring_metrics, scoring_top_set_exercise_id, is_featured")
                .eq("id", value: routineID)
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

    /// Encodable counterpart to `PublishFields` above, backing the targeted
    /// UPDATE in `updatePublishFields` below. Declared here (a nested type of
    /// `RoutineRepository`, sibling to `PublishFields`) rather than local to
    /// `updatePublishFields` — where it originally lived — so
    /// `PublishFieldsEncodingTests` can reference it via `@testable import
    /// GymSync`: a type declared inside a function body has no externally
    /// nameable path, `internal` access or not. Behavior is unchanged: same
    /// fields, same `CodingKeys`, same explicit `encode(to:)`.
    ///
    /// The EXPLICIT `encode(to:)` (`container.encode(_:forKey:)`, not the
    /// synthesized `encodeIfPresent`) is deliberate: it makes a `nil` field
    /// serialize as JSON `null` and actually CLEAR that column via
    /// PostgREST's PATCH, rather than being silently omitted from the
    /// request body and leaving a previously-set value stuck — the exact
    /// behavior a curator un-picking "Top Set" (or any other field) needs.
    struct PublishFieldsUpdate: Encodable {
        let defaultSort: String?
        let scoringMetrics: [String]?
        let scoringTopSetExerciseID: UUID?
        /// encodeIfPresent (NOT the explicit-null treatment of the trio
        /// above): nil means "don't touch is_featured" — a non-curator's
        /// publish must never write the RLS-gated column at all, or the
        /// whole UPDATE would 42501. `var … = nil` (trailing, defaulted) for
        /// the same memberwise-init reason as UserSettings.shareHeartRate:
        /// pre-existing 3-arg call sites (PublishFieldsEncodingTests) keep
        /// compiling unchanged.
        var isFeatured: Bool? = nil
        enum CodingKeys: String, CodingKey {
            case defaultSort = "default_sort"
            case scoringMetrics = "scoring_metrics"
            case scoringTopSetExerciseID = "scoring_top_set_exercise_id"
            case isFeatured = "is_featured"
        }
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(defaultSort, forKey: .defaultSort)
            try c.encode(scoringMetrics, forKey: .scoringMetrics)
            try c.encode(scoringTopSetExerciseID, forKey: .scoringTopSetExerciseID)
            try c.encodeIfPresent(isFeatured, forKey: .isFeatured)
        }
    }

    /// Targeted UPDATE of exactly the 3 publish-only columns — the brief's
    /// "minimal safe shape" decision (see this section's header comment).
    /// Called by `RoutineBuilderView.save()` ONLY when the routine is being
    /// published (`publishAsFeatured == true`); left untouched on unpublish
    /// (Discover only ever reads `visibility='public'` rows anyway, so a
    /// stale value on a private routine is inert either way — see that
    /// call site's comment for the full reasoning). See `PublishFieldsUpdate`
    /// above for why a `nil` field still needs writing.
    static func updatePublishFields(
        routineID: UUID,
        defaultSort: String?,
        scoringMetrics: [String]?,
        scoringTopSetExerciseID: UUID?,
        isFeatured: Bool? = nil
    ) async throws {
        do {
            _ = try await client
                .from("routines")
                .update(PublishFieldsUpdate(
                    defaultSort: defaultSort,
                    scoringMetrics: scoringMetrics,
                    scoringTopSetExerciseID: scoringTopSetExerciseID,
                    isFeatured: isFeatured
                ))
                .eq("id", value: routineID)
                .execute()
        } catch { throw ErrorMapping.map(error) }
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
