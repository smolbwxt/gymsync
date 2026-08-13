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
        do {
            let rows: [Exercise] = try await SupabaseService.shared.client
                .from("exercises")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
            return rows
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
