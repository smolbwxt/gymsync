import Foundation
import Supabase

struct Exercise: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let slug: String
    let category: String
    let primaryMuscle: String
    let secondaryMuscles: [String]
    let equipment: String
    let defaultUnit: String
    let demoVideoURL: URL?
    /// YouTube video ID for the form demo (20260730000002) — rendered via
    /// GSYouTubeEmbed on the detail screen. Trailing-defaulted so every
    /// existing memberwise construction site (catalog fixtures) compiles
    /// unchanged; decodes absent as nil.
    var demoYoutubeID: String? = nil
    /// Step-by-step form cues (20260813000001, free-exercise-db import) —
    /// the detail screen's HOW TO section. Empty for the curated seeds
    /// until backfilled. Trailing default keeps fixture sites compiling;
    /// the column is NOT NULL DEFAULT '{}' so every row decodes.
    var instructions: [String] = []
    /// Generator selection engine (20260814000009): squat|hinge|lunge|
    /// push_horizontal|push_vertical|pull_horizontal|pull_vertical|
    /// isolation|other — deterministic name+muscle classification.
    var movementPattern: String? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case slug
        case category
        case primaryMuscle = "primary_muscle"
        case secondaryMuscles = "secondary_muscles"
        case equipment
        case defaultUnit = "default_unit"
        case demoVideoURL = "demo_video_url"
        case demoYoutubeID = "demo_youtube_id"
        case instructions
        case movementPattern = "movement_pattern"
    }
}

extension Exercise {
    /// Lower-body classifier for progression step sizing (research audit
    /// 2026-08: ~5% steps lower body, ~2.5% upper). Primary muscle only —
    /// hip-hinge compounds list their driver first. Unknown muscle strings
    /// fall through to `false`, which lands on the SMALLER (conservative)
    /// upper-body step.
    var isLowerBody: Bool {
        let lower: Set<String> = [
            "quads", "quadriceps", "hamstrings", "glutes", "calves",
            "legs", "adductors", "abductors", "hip flexors"
        ]
        return lower.contains(primaryMuscle.lowercased())
    }
}

enum ExerciseRepository {
    static func fetchAll() async throws -> [Exercise] {
        // Paged on purpose: PostgREST silently caps un-ranged selects at
        // 1000 rows and the machine sweeps pushed the catalog past 1300 —
        // without explicit ranges the tail of the alphabet vanishes from
        // every picker and the generator's candidate pool.
        do {
            var all: [Exercise] = []
            let pageSize = 1000
            var from = 0
            while true {
                let rows: [Exercise] = try await SupabaseService.shared.client
                    .from("exercises")
                    .select()
                    .order("name", ascending: true)
                    .range(from: from, to: from + pageSize - 1)
                    .execute()
                    .value
                all.append(contentsOf: rows)
                if rows.count < pageSize { break }
                from += pageSize
            }
            return all
        } catch {
            throw ErrorMapping.map(error)
        }
    }

    static func fetch(id: UUID) async throws -> Exercise? {
        do {
            let row: Exercise = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .eq("id", value: id)
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
}
