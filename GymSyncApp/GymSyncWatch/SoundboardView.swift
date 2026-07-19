import SwiftUI

// MARK: - SoundboardView
//
// Phase W Task 3 (watch-hr design §2, Component 3 "Soundboard buttons") —
// the user's up to 4 favorite slugs, synced from the phone via
// `WatchSessionStatePayload.soundboardFavorites` (Task 3's own additive
// field — see `GymSyncShared/WatchEnvelope.swift`'s doc comment on that
// field for its phone-side source: `SoundboardFavoritesRepository`, the
// SAME source `GroupSessionLiveView`'s own dock ribbon reads). Tap ->
// `WatchSessionStore.tapSoundboard(slug:)` -> `WatchConnectivityBridge.
// handleSoundboardTap` on the phone (local play + broadcast, unchanged
// existing flow) — the tap payload always carries the SLUG, never the
// label (see `tap(slug:)` below); that contract is unchanged by the
// fix-wave-1 addition immediately below.
//
// Fix wave 1 (reviewer finding, IMPORTANT 2) — SUPERSEDES this file's
// original "no sound NAME is carried over the wire, the slug itself is
// already a readable label" reasoning. `WatchSessionStatePayload` gained a
// second, ADDITIVE `soundboardFavoriteLabels: [String]` field (parallel to
// `soundboardFavorites`, same order, same phone-side source
// (`GroupSessionLiveView.dockSounds`) — see that field's own doc comment in
// `WatchEnvelope.swift`) once a reviewer flagged that a raw slug like
// "crowd-cheer" reads worse at watch scale than the phone's own
// `SoundboardSound.label` (`displayName ?? slug`,
// `Models/Soundboard.swift:16`) — nothing here duplicates the full catalog
// (icon/category/etc. still stay phone-side only); this is exactly the one
// extra string per favorite this surface needs to render a name instead of
// a slug.
struct SoundboardView: View {
    @Environment(\.gsWatchTheme) private var theme
    let store: WatchSessionStore

    /// Per-slug transient feedback (checkmark / error), cleared after 1.5s
    /// — shorter than `LogSetView`'s 2s since a soundboard tap's own
    /// `WatchActionReply` is always `.success` once routed
    /// (`handleSoundboardTap`'s doc comment) — this is confirmation the tap
    /// LANDED, not a multi-outcome state to linger on.
    @State private var feedback: [String: WatchActionReply.Outcome] = [:]

    private var favorites: [String] {
        store.sessionState?.soundboardFavorites ?? []
    }

    /// Fix wave 1 addition — parallel to `favorites` above, same order
    /// (both come from the SAME phone-side `dockSounds.map(\.slug)` /
    /// `dockSounds.map(\.label)` pair, built in the same call —
    /// `GroupSessionLiveView.pushWatchSessionState()`). `label(forSlugAt:)`
    /// below still falls back to the slug itself if this array is ever
    /// shorter than `favorites` (an old-shaped phone push, or any other
    /// skew) — never crashes on an out-of-bounds index.
    private var favoriteLabels: [String] {
        store.sessionState?.soundboardFavoriteLabels ?? []
    }

    private func label(forSlugAt index: Int, slug: String) -> String {
        guard favoriteLabels.indices.contains(index) else { return slug }
        return favoriteLabels[index]
    }

    var body: some View {
        Group {
            if store.sessionState?.isActive != true {
                VStack {
                    Spacer(minLength: 0)
                    Text("No active session")
                        .font(.caption)
                        .foregroundStyle(theme.text.opacity(0.6))
                    Spacer(minLength: 0)
                }
            } else if favorites.isEmpty {
                VStack {
                    Spacer(minLength: 0)
                    Text("No favorites yet")
                        .font(.caption)
                        .foregroundStyle(theme.text.opacity(0.6))
                    Text("Pick 4 on your phone")
                        .font(.caption2)
                        .foregroundStyle(theme.text.opacity(0.45))
                    Spacer(minLength: 0)
                }
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    // `.self` on the SLUG (not the index) as the identity —
                    // unchanged from before this fix — since a slug is
                    // already guaranteed unique within one user's favorites
                    // (`SoundboardFavoritesRepository`'s `slugs` column has
                    // no duplicate-tolerance concept, and `dockSounds`'
                    // curated-fallback path draws from a catalog keyed by
                    // slug). The label rides alongside via `enumerated()`
                    // purely to look up its parallel-array position.
                    ForEach(Array(favorites.enumerated()), id: \.element) { index, slug in
                        soundTile(slug: slug, label: label(forSlugAt: index, slug: slug))
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.bg)
        .navigationTitle("Sounds")
    }

    /// `label` is display-only (fix wave 1) — the button's ACTION always
    /// closes over `slug`, never `label`, so the outbound tap
    /// (`tap(_:)` below -> `WatchSessionStore.tapSoundboard(slug:)`) is
    /// unaffected by this rendering change.
    private func soundTile(slug: String, label: String) -> some View {
        Button {
            Task { await tap(slug) }
        } label: {
            VStack(spacing: 2) {
                if let outcome = feedback[slug] {
                    Image(systemName: outcome == .failure ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(outcome == .failure ? .red : .green)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .foregroundStyle(theme.accent)
                }
                Text(label)
                    .font(.caption2)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(theme.text)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(theme.surface)
    }

    private func tap(_ slug: String) async {
        let reply = await store.tapSoundboard(slug: slug)
        feedback[slug] = reply.outcome
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if feedback[slug] == reply.outcome { feedback[slug] = nil }
    }
}

#Preview {
    SoundboardView(store: .shared)
}
