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
// existing flow).
//
// No sound NAME/icon is carried over the wire (`soundboardFavorites` is
// just `[String]` slugs) — the full `SoundboardSound` catalog
// (`displayName`/`icon`) lives phone-side only and was judged out of scope
// to duplicate here for 4 buttons: the slug itself (e.g. "airhorn",
// "crowd-cheer") is already a readable label at watch scale, and adding a
// second synced catalog would be exactly the kind of speculative plumbing
// the design doc's "do NOT build a scheduling-sync subsystem" caution (said
// of the idle state, but the same restraint applies here) warns against.
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
                    ForEach(favorites, id: \.self) { slug in
                        soundTile(slug)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(theme.bg)
        .navigationTitle("Sounds")
    }

    private func soundTile(_ slug: String) -> some View {
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
                Text(slug)
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
