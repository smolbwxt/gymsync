import Foundation

/// Lightweight exercise-name cache backed by a single `ExerciseRepository.fetchAll()` call.
///
/// Usage:
///   await ExerciseNameCache.preload()          // call once at session start
///   let name = await ExerciseNameCache.name(for: exerciseID)  // "Exercise" fallback
///
/// Actor-safe: all mutable state is behind the @MainActor; `name(for:)` and `preload()`
/// are async and always dispatch to the main actor.
enum ExerciseNameCache {
    @MainActor private static var cache: [UUID: String] = [:]
    @MainActor private static var loaded = false

    /// Fetch all exercises and populate the cache. Safe to call multiple times — subsequent
    /// calls are no-ops if the cache has already been loaded.
    @MainActor
    static func preload() async {
        guard !loaded else { return }
        do {
            let exercises = try await ExerciseRepository.fetchAll()
            cache = Dictionary(uniqueKeysWithValues: exercises.map { ($0.id, $0.name) })
            loaded = true
        } catch {
            AppLogger.sessions.error(
                "ExerciseNameCache.preload failed: \(error, privacy: .public)")
        }
    }

    /// Return the display name for an exercise ID, preloading if necessary.
    /// Returns `"Exercise"` when the ID is not found or the fetch fails.
    @MainActor
    static func name(for id: UUID) async -> String {
        if !loaded { await preload() }
        return cache[id] ?? "Exercise"
    }
}
