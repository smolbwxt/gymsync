import SwiftUI

// MARK: - SoundLibrarySheet
//
// Content Curation Task 3, frame 2 ("Sound library"): opened from
// GroupSessionLiveView's dock via either "Edit" or the dashed "All" tile.
//   • Grab handle + "Sounds" header + "Tap to send · star to favorite" caption.
//   • "Your N favorites · drag to reorder" — reorderable List section (star
//     tap removes from favorites).
//   • "All sounds" — Hype/Funny/FX segmented filter (a sound with no category
//     appears in every segment) over a two-column grid of the full catalog
//     (star tap toggles favorite, capped at 4 — adding a 5th drops the oldest).
//   • Any row/cell tap sends that sound (via `onSend`) and dismisses the sheet.
//
// State ownership: favorites here are a local, optimistic copy seeded from the
// `favorites` init parameter. Every mutation (reorder/star) updates the local
// copy immediately (so the UI never waits on a round-trip) AND calls
// `onFavoritesChanged` with the full new array — the caller (GroupSessionLiveView)
// is the actual source of truth and owns persistence via
// `SoundboardFavoritesRepository.set(_:)`; this view never talks to Supabase.
struct SoundLibrarySheet: View {
    let catalog: [SoundboardSound]
    let onFavoritesChanged: ([String]) -> Void
    let onSend: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    /// Local optimistic copy of the favorite slugs, ordered. Seeded (in `init`)
    /// with any stale slugs already filtered out — see `init`'s doc comment —
    /// so every index here always corresponds 1:1 with `favoriteSounds` below,
    /// which is what keeps `.onMove`'s reorder indices honest.
    @State private var favorites: [String]

    private enum LibrarySegment: String, CaseIterable, Identifiable {
        case hype  = "Hype"
        case funny = "Funny"
        case fx    = "FX"

        var id: String { rawValue }
        /// Matches the lowercase `category` values in `soundboard_sounds`.
        var categoryValue: String { rawValue.lowercased() }
    }

    @State private var selectedSegment: LibrarySegment = .hype

    init(
        catalog: [SoundboardSound],
        favorites: [String],
        onFavoritesChanged: @escaping ([String]) -> Void,
        onSend: @escaping (String) -> Void
    ) {
        self.catalog = catalog
        self.onFavoritesChanged = onFavoritesChanged
        self.onSend = onSend
        // Drop any favorite slug that no longer resolves in the catalog (sound
        // removed/renamed server-side) BEFORE seeding local state. Without this,
        // `favoriteSounds` (catalog-resolved) would be shorter than `favorites`
        // and `.onMove`'s offsets — which are indices into `favoriteSounds` —
        // would silently reorder the wrong underlying slugs.
        let validSlugs = Set(catalog.map(\.slug))
        self._favorites = State(initialValue: favorites.filter { validSlugs.contains($0) })
    }

    private var bySlug: [String: SoundboardSound] {
        Dictionary(uniqueKeysWithValues: catalog.map { ($0.slug, $0) })
    }

    private var favoriteSounds: [SoundboardSound] {
        favorites.compactMap { bySlug[$0] }
    }

    /// nil-category sounds appear in every segment.
    private var filteredCatalog: [SoundboardSound] {
        catalog.filter { sound in
            guard let category = sound.category else { return true }
            return category.lowercased() == selectedSegment.categoryValue
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(theme.neutral400)
                .frame(width: 40, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 14)

            HStack(alignment: .firstTextBaseline) {
                Text("Sounds")
                    .font(GSFont.heading(22, relativeTo: .title2))
                    .foregroundStyle(theme.text)
                Spacer()
                Text("Tap to send · star to favorite")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            List {
                if !favoriteSounds.isEmpty {
                    Section {
                        ForEach(favoriteSounds) { sound in
                            favoriteRow(sound)
                        }
                        .onMove(perform: moveFavorite)
                    } header: {
                        Text("Your \(favorites.count) favorite\(favorites.count == 1 ? "" : "s") · drag to reorder")
                            .font(GSFont.heading(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                            .textCase(nil)
                    }
                }

                Section {
                    catalogGrid
                } header: {
                    HStack(alignment: .center) {
                        Text("All sounds")
                            .font(GSFont.heading(13, relativeTo: .subheadline))
                            .foregroundStyle(theme.neutral700)
                        Spacer()
                        segmentControl
                    }
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.editMode, .constant(.active))
        }
        .background(theme.bg)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.hidden)
    }

    // MARK: - Favorites row

    private func favoriteRow(_ sound: SoundboardSound) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 13))
                .foregroundStyle(theme.neutral500)
            Text(sound.icon ?? "🔊")
                .font(.system(size: 18))
            Text(sound.label)
                .font(GSFont.bold(13, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer(minLength: 0)
            Button {
                removeFavorite(sound.slug)
            } label: {
                Image(systemName: "star.fill")
                    .foregroundStyle(theme.accent)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onTapGesture {
            onSend(sound.slug)
            dismiss()
        }
        .listRowInsets(EdgeInsets(top: 3, leading: 16, bottom: 3, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(
            Rectangle()
                .fill(theme.bg)
                .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        )
    }

    // MARK: - All sounds grid

    private var catalogGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(filteredCatalog) { sound in
                catalogCell(sound)
            }
        }
        .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    private func catalogCell(_ sound: SoundboardSound) -> some View {
        let isFavorited = favorites.contains(sound.slug)
        return HStack(spacing: 8) {
            Text(sound.icon ?? "🔊")
                .font(.system(size: 18))
            Text(sound.label)
                .font(GSFont.bold(12, relativeTo: .footnote))
                .foregroundStyle(theme.text)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                toggleFavorite(sound.slug)
            } label: {
                Image(systemName: isFavorited ? "star.fill" : "star")
                    .foregroundStyle(isFavorited ? theme.accent : theme.neutral500)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(minHeight: 44)
        .background(theme.bg)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture {
            onSend(sound.slug)
            dismiss()
        }
    }

    // MARK: - Segment control

    private var segmentControl: some View {
        HStack(spacing: 4) {
            ForEach(LibrarySegment.allCases) { segment in
                Button {
                    selectedSegment = segment
                } label: {
                    Text(segment.rawValue)
                        .font(GSFont.bold(11, relativeTo: .caption2))
                        .foregroundStyle(selectedSegment == segment ? theme.bg : theme.text)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(selectedSegment == segment ? theme.accent : Color.clear)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Favorites mutation (optimistic — `onFavoritesChanged` is the only persistence path)

    private func moveFavorite(from source: IndexSet, to destination: Int) {
        favorites.move(fromOffsets: source, toOffset: destination)
        onFavoritesChanged(favorites)
    }

    private func removeFavorite(_ slug: String) {
        favorites.removeAll { $0 == slug }
        onFavoritesChanged(favorites)
    }

    /// Toggle a catalog sound's favorite state. Adding past the 4-cap drops the
    /// OLDEST favorite (index 0 — favorites are appended to the end on add, so
    /// the front of the array is always the longest-held one).
    private func toggleFavorite(_ slug: String) {
        if favorites.contains(slug) {
            favorites.removeAll { $0 == slug }
        } else {
            if favorites.count >= 4 {
                favorites.removeFirst()
            }
            favorites.append(slug)
        }
        onFavoritesChanged(favorites)
    }
}
