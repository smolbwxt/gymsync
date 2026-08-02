import AVFoundation
import SwiftUI
import Supabase

/// My Rack — the home for your sounds outside a session, reached from the
/// You tab's MY RACK widget. Browse the full catalog, preview any sound,
/// and manage the 4-slot dock you carry into every session.
///
/// Favorites semantics mirror the live session's Rack Room
/// (`SoundLibrarySheet` + `GroupSessionLiveView`) exactly: a local
/// optimistic copy of the ordered slug array (stale slugs filtered against
/// the catalog), adds APPEND to the end (front = longest-held), removes
/// filter by slug, and every mutation fire-and-forgets the FULL array via
/// `SoundboardFavoritesRepository.set(_:)`. One deliberate divergence,
/// per the approved design: at the 4-cap this screen disables RACK
/// ("DOCK FULL") instead of silently dropping the oldest favorite — a
/// management surface shouldn't evict plates the user didn't ask to lose.
///
/// The dock shows the user's ACTUAL favorites (0–4). The curated-first-4
/// fallback stays a send-time display behavior of the session dock and the
/// You-tab widget face; showing borrowed plates here would invite
/// "unracking" sounds that were never racked.
struct MyRackView: View {
    @Environment(\.gsTheme) private var theme

    /// Full catalog, populated on first appear (retryable on failure).
    @State private var catalog: [SoundboardSound] = []
    /// Local optimistic copy of the favorite slugs, ordered, max 4.
    @State private var favorites: [String] = []
    @State private var loading = true
    @State private var loadFailed = false
    @State private var searchText = ""

    /// Dock-slot unrack confirmation (split title/message per this
    /// codebase's confirmationDialog idiom — FriendsView's block dialog).
    @State private var unrackTarget: SoundboardSound?
    @State private var showUnrackConfirm = false

    /// One preview at a time: starting a new one stops the prior.
    @State private var previewingSlug: String?
    @State private var previewPlayer: AVAudioPlayer?

    // MARK: - Derived

    private var bySlug: [String: SoundboardSound] {
        Dictionary(catalog.map { ($0.slug, $0) },
                   uniquingKeysWith: { first, _ in first })
    }

    private var favoriteSounds: [SoundboardSound] {
        favorites.compactMap { bySlug[$0] }
    }

    private var filteredCatalog: [SoundboardSound] {
        guard !searchText.isEmpty else { return catalog }
        return catalog.filter { sound in
            sound.label.localizedCaseInsensitiveContains(searchText)
                || sound.plateName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private struct CatalogSection: Identifiable {
        let id: String
        let sounds: [SoundboardSound]
        var title: String { id.uppercased() }
    }

    /// Sections by category (hype · funny · fx, catalog order within each);
    /// nil-category sounds gather under MORE at the end.
    private var sections: [CatalogSection] {
        let order = ["hype": 0, "funny": 1, "fx": 2]
        let grouped = Dictionary(grouping: filteredCatalog) { sound in
            sound.category?.lowercased() ?? "more"
        }
        return grouped
            .map { CatalogSection(id: $0.key, sounds: $0.value) }
            .sorted { (order[$0.id] ?? 3, $0.id) < (order[$1.id] ?? 3, $1.id) }
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                dockCard
                    .padding(.horizontal, 16)
                    .padding(.top, 16)

                searchField
                    .padding(.horizontal, 16)
                    .padding(.top, 12)

                catalogContent
                    .padding(.top, 14)

                Spacer(minLength: 24)
            }
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .navigationTitle("My Rack")
        .navigationBarTitleDisplayMode(.inline)
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
        .onDisappear { stopPreview() }
        .confirmationDialog(
            "Unrack \(unrackTarget?.label ?? "this sound")?",
            isPresented: $showUnrackConfirm,
            titleVisibility: .visible
        ) {
            Button("Unrack", role: .destructive) {
                if let slug = unrackTarget?.slug {
                    removeFavorite(slug)
                }
                unrackTarget = nil
            }
            Button("Cancel", role: .cancel) {
                unrackTarget = nil
            }
        } message: {
            Text("It comes off your dock — you can rack it again anytime.")
        }
    }

    // MARK: - Dock card

    private var dockCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(loading ? "YOUR DOCK" : "YOUR DOCK · \(favoriteSounds.count) / 4")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral700)

            HStack(spacing: 0) {
                ForEach(0..<4, id: \.self) { index in
                    dockSlot(index)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func dockSlot(_ index: Int) -> some View {
        let sounds = favoriteSounds
        if index < sounds.count {
            let sound = sounds[index]
            Button {
                unrackTarget = sound
                showUnrackConfirm = true
            } label: {
                GSPlateToken(
                    name: sound.plateName,
                    envelope: sound.envelope,
                    durationMs: sound.durationMs,
                    isClipped: sound.isClipped,
                    cooldownUntil: nil,
                    size: 56
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unrack \(sound.label)")
        } else if loading {
            // Solid placeholder ring while the catalog resolves (the You-tab
            // widget's own loading idiom).
            Circle()
                .strokeBorder(theme.neutral300, lineWidth: 2)
                .frame(width: 56, height: 56)
        } else {
            Circle()
                .strokeBorder(theme.neutral400, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                .frame(width: 56, height: 56)
                .accessibilityLabel("Empty dock slot")
        }
    }

    // MARK: - Search field
    // In-content search, cloned from ExercisesListView (user feedback
    // 2026-07-23 established this pattern over .searchable's drawer).

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(theme.neutral500)
            TextField("Search sounds", text: $searchText)
                .font(GSFont.body(14, relativeTo: .body))
                .foregroundStyle(theme.text)
                .autocorrectionDisabled()
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(theme.neutral500)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusSm)
    }

    // MARK: - Catalog

    @ViewBuilder
    private var catalogContent: some View {
        if loading {
            HStack {
                Spacer()
                ProgressView().tint(theme.accent)
                Spacer()
            }
            .padding(.top, 32)
        } else if loadFailed {
            VStack(spacing: 6) {
                Text("Couldn't load your sounds")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                Button {
                    Task { await load() }
                } label: {
                    Text("RETRY")
                        .font(GSFont.bold(11, relativeTo: .caption))
                        .tracking(1.1)
                        .foregroundStyle(theme.accent700)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        } else if sections.isEmpty {
            Text(searchText.isEmpty
                 ? "The catalog is empty — check back soon."
                 : "No sounds match \u{201C}\(searchText)\u{201D}")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
                .frame(maxWidth: .infinity)
                .padding(.top, 32)
                .padding(.horizontal, 16)
        } else {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(sections) { section in
                    Text(section.title)
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(1.1)
                        .foregroundStyle(theme.neutral700)
                        .padding(.top, 8)
                        .padding(.leading, 2)
                    ForEach(section.sounds) { sound in
                        catalogRow(sound)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func catalogRow(_ sound: SoundboardSound) -> some View {
        HStack(spacing: 12) {
            GSPlateToken(
                name: sound.plateName,
                envelope: sound.envelope,
                durationMs: sound.durationMs,
                isClipped: sound.isClipped,
                cooldownUntil: nil,
                size: 32
            )
            VStack(alignment: .leading, spacing: 3) {
                Text(sound.label)
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text(rowKLine(sound))
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            previewButton(sound)
            rackControl(sound)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: GSMetrics.radiusSm))
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1)
        )
    }

    /// "1.8s · HYPE", "✂ 5s · FX" — same duration formula as GSPlateToken's
    /// bottom arc, so the row and the plate never disagree.
    private func rowKLine(_ sound: SoundboardSound) -> String {
        var parts: [String] = []
        if let durationMs = sound.durationMs {
            let s = (Double(durationMs) / 100).rounded() / 10
            let str = s == s.rounded() ? "\(Int(s))s" : "\(s)s"
            parts.append(sound.isClipped ? "✂ \(str)" : str)
        }
        if let category = sound.category {
            parts.append(category.uppercased())
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func previewButton(_ sound: SoundboardSound) -> some View {
        let isPreviewing = previewingSlug == sound.slug
        return Button {
            Task { await togglePreview(sound) }
        } label: {
            Image(systemName: isPreviewing ? "stop.fill" : "play.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isPreviewing ? theme.accent : theme.neutral700)
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isPreviewing ? "Stop preview" : "Preview \(sound.label)")
    }

    @ViewBuilder
    private func rackControl(_ sound: SoundboardSound) -> some View {
        if favorites.contains(sound.slug) {
            Button {
                removeFavorite(sound.slug)
            } label: {
                Text("RACKED")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.neutral700)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Unrack \(sound.label)")
        } else if favorites.count >= 4 {
            Text("DOCK FULL")
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
                .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
                .accessibilityLabel("\(sound.label), dock full")
        } else {
            Button {
                addFavorite(sound.slug)
            } label: {
                Text("RACK")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                    .frame(minWidth: 64, minHeight: 44, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Rack \(sound.label)")
        }
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        loading = true
        loadFailed = false
        do {
            let fetched = try await SoundboardRepository.fetchCatalog()
            let favoriteSlugs = try await SoundboardFavoritesRepository.get()
            // Drop stale slugs (sound removed/renamed server-side) before
            // seeding local state — same guard as SoundLibrarySheet's init.
            let validSlugs = Set(fetched.map(\.slug))
            catalog = fetched
            favorites = favoriteSlugs.filter { validSlugs.contains($0) }
        } catch {
            // Unlike the session dock (which degrades quietly to the curated
            // fallback), a management surface must not present an empty dock
            // it might then persist over the user's real favorites.
            loadFailed = true
        }
        loading = false
    }

    // MARK: - Favorites mutation
    // Optimistic local copy; every change persists the FULL array — the same
    // write path GroupSessionLiveView uses for SoundLibrarySheet's changes.

    private func addFavorite(_ slug: String) {
        guard favorites.count < 4, !favorites.contains(slug) else { return }
        favorites.append(slug)
        persistFavorites()
    }

    private func removeFavorite(_ slug: String) {
        favorites.removeAll { $0 == slug }
        persistFavorites()
    }

    private func persistFavorites() {
        let updated = favorites
        Task { try? await SoundboardFavoritesRepository.set(updated) }
    }

    // MARK: - Preview playback
    // SoundboardPlayer's pool is fire-and-forget (≤8 concurrent, no stop
    // API), so previews hold a single local AVAudioPlayer instead — built
    // from the SAME storage-URL + tmp-cache path (slug-keyed "sb_<slug>.wav",
    // shared with SoundboardPlayer's cache, so nothing downloads twice).
    // AUDIO SACRED RULE: never touches AVAudioSession category — the ambient
    // + mixWithOthers config from AudioSessionManager.configure() stays.

    @MainActor
    private func togglePreview(_ sound: SoundboardSound) async {
        if previewingSlug == sound.slug {
            stopPreview()
            return
        }
        stopPreview()
        previewingSlug = sound.slug
        do {
            let fileURL = try await localPreviewFile(for: sound)
            // A newer preview (or a stop) may have superseded this download.
            guard previewingSlug == sound.slug else { return }
            let player = try AVAudioPlayer(contentsOf: fileURL)
            previewPlayer = player
            player.play()
            // Clear the ▶/■ state once playback runs out on its own
            // (SoundboardPlayer's own pool-pruning idiom).
            let duration = player.duration
            let slug = sound.slug
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64((duration + 0.2) * 1_000_000_000))
                if previewingSlug == slug, previewPlayer?.isPlaying != true {
                    previewingSlug = nil
                    previewPlayer = nil
                }
            }
        } catch {
            AppLogger.soundboard.error(
                "MyRackView: could not preview \(sound.slug, privacy: .public): \(error, privacy: .public)")
            if previewingSlug == sound.slug {
                previewingSlug = nil
            }
        }
    }

    /// Same URL-construction + download path as SoundboardPlayer's
    /// `resolveLocalFile(slug:)` (private there): public URL from the
    /// `soundboard` bucket, downloaded once into tmp keyed by slug.
    private func localPreviewFile(for sound: SoundboardSound) async throws -> URL {
        let dest = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("sb_\(sound.slug).wav")
        if FileManager.default.fileExists(atPath: dest.path) { return dest }

        let publicURL = try SupabaseService.shared.client.storage
            .from("soundboard")
            .getPublicURL(path: sound.storagePath)
        let (tmpURL, _) = try await URLSession.shared.download(from: publicURL)
        // A concurrent SoundboardPlayer download may have landed it already.
        if !FileManager.default.fileExists(atPath: dest.path) {
            try FileManager.default.moveItem(at: tmpURL, to: dest)
        }
        return dest
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
        previewingSlug = nil
    }
}
