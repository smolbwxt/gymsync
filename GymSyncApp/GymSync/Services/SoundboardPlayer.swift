import AVFoundation
import Foundation
import Supabase

// ── SoundboardPlayer ──────────────────────────────────────────────────────────
//
// Responsibilities:
//   • Fetch + cache the soundboard_sounds table (one trip per app session).
//   • Resolve the public storage URL for a given slug.
//   • Download each WAV once into the tmp directory (keyed by slug).
//   • Play via an AVAudioPlayer pool (≤8 concurrent, FIFO eviction).
//
// CONTRACT: NEVER touches AVAudioSession category.  The ambient + mixWithOthers
// config set by AudioSessionManager.configure() must remain in force so
// soundboard playback mixes with Spotify.  (AUDIO SACRED RULE §6.1)

@MainActor
final class SoundboardPlayer {

    // MARK: - Shared instance

    static let shared = SoundboardPlayer()
    private init() {}

    // MARK: - Sound catalog

    private struct SoundRow: Decodable {
        let slug: String
        let storagePath: String
        let displayName: String?

        enum CodingKeys: String, CodingKey {
            case slug
            case storagePath = "storage_path"
            case displayName = "display_name"
        }
    }

    /// Cached catalog — loaded once, then reused.
    private var catalog: [String: SoundRow] = [:]
    private var catalogLoaded = false
    private var catalogLoadTask: Task<Void, Never>?

    // MARK: - File cache

    /// slug → local tmp URL for downloaded WAV files.
    private var fileCache: [String: URL] = [:]

    // MARK: - Player pool (≤8 FIFO)

    private var pool: [AVAudioPlayer] = []
    private let maxPool = 8

    // MARK: - Public API

    /// Play the sound identified by `slug`.
    /// Downloads + caches on first call; subsequent calls are instant.
    /// Never throws: errors are logged + swallowed (non-fatal audio).
    func play(slug: String) async {
        do {
            let fileURL = try await resolveLocalFile(slug: slug)
            try playFromFile(fileURL)
        } catch {
            AppLogger.soundboard.error(
                "SoundboardPlayer: could not play \(slug, privacy: .public): \(error, privacy: .public)")
        }
    }

    /// Return the display_name for a sound slug from the cached catalog.
    /// Returns the slug itself if not found or catalog is unavailable.
    func displayName(for slug: String) async -> String {
        do {
            try await ensureCatalog()
            return catalog[slug]?.displayName ?? slug
        } catch {
            return slug
        }
    }

    // MARK: - Internal helpers

    /// Load the catalog once; subsequent callers await the in-flight task.
    private func ensureCatalog() async throws {
        if catalogLoaded { return }

        // Coalesce concurrent callers.
        if let t = catalogLoadTask { await t.value; return }

        let task = Task<Void, Never> { @MainActor in
            do {
                let rows: [SoundRow] = try await SupabaseService.shared.client
                    .from("soundboard_sounds")
                    .select("slug, storage_path, display_name")
                    .execute()
                    .value
                for row in rows {
                    self.catalog[row.slug] = row
                }
                self.catalogLoaded = true
            } catch {
                AppLogger.soundboard.error(
                    "SoundboardPlayer: catalog fetch failed: \(error, privacy: .public)")
            }
        }
        catalogLoadTask = task
        await task.value
        catalogLoadTask = nil
    }

    /// Return (and cache) the local file URL for a slug.
    private func resolveLocalFile(slug: String) async throws -> URL {
        // 1. Return cached file if already downloaded.
        if let url = fileCache[slug] { return url }

        // 2. Load catalog if needed.
        try await ensureCatalog()
        guard let row = catalog[slug] else {
            throw SoundError.unknownSlug(slug)
        }

        // 3. Resolve public URL from the `soundboard` bucket.
        let publicURL = try SupabaseService.shared.client.storage
            .from("soundboard")
            .getPublicURL(path: row.storagePath)

        // 4. Download to tmp (slug-keyed so we never double-download).
        let dest = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("sb_\(slug).wav")

        if !FileManager.default.fileExists(atPath: dest.path) {
            let (tmpURL, _) = try await URLSession.shared.download(from: publicURL)
            try FileManager.default.moveItem(at: tmpURL, to: dest)
        }

        fileCache[slug] = dest
        return dest
    }

    /// Obtain a player from the pool (FIFO eviction when full) and play.
    private func playFromFile(_ url: URL) throws {
        // If the pool is at capacity, evict the oldest (first) player.
        if pool.count >= maxPool {
            pool.first?.stop()
            pool.removeFirst()
        }

        let player = try AVAudioPlayer(contentsOf: url)
        // AUDIO SACRED RULE: do NOT call setCategory here.
        // The ambient session is already configured by AudioSessionManager.
        // Field #39: ...except when it ISN'T - a session that lost
        // mixWithOthers pauses the lifter's Spotify the moment this
        // player activates it. The manager restores its own documented
        // baseline only when the invariant is broken (never in voice
        // mode), so the sacred rule's intent survives.
        AudioSessionManager.shared.ensureMixablePlayback()
        pool.append(player)
        player.play()

        // Prune finished players after playback completes.
        let duration = player.duration
        Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: UInt64((duration + 0.5) * 1_000_000_000))
            self.pool.removeAll { !$0.isPlaying }
        }
    }

    // MARK: - Error types

    enum SoundError: Error {
        case unknownSlug(String)
    }
}
