import SwiftUI

// MARK: - TopLiftersView (Phase L Task 4)
//
// Global cumulative-volume leaderboard — Phase L design §3 (`docs/
// superpowers/specs/2026-07-18-discover-leaderboards-design.md:19`): "Top
// Lifters ranks profiles by lifetime volume — public data per profiles RLS
// (anyone reads public fields) — no extra opt-in needed." Backed by
// `ProfileRepository.topLifters()` (`Models/Profile.swift`) — a plain
// ordered+LIMIT-ed `profiles` read; that table's SELECT policy is `USING
// (true)` for any authenticated user (`supabase/migrations/
// 20260709000001_create_profiles.sql:15-18`), so no RLS change was needed
// for this board (cited in the repository method's own doc comment).
//
// Row idiom cited + reused: `GroupRecapView.leaderboardRow` (`Features/
// Sessions/GroupRecapView.swift:323-366`) — rank number, avatar circle,
// name, compact metric text, "You" row highlight (that file's own comment:
// "'You' row highlight (proof-frame-08.png's tinted second row)"). Swapped
// its plain-initials-square avatar for the shared `GSInitialsAvatar`
// component (`Features/Social/SocialTabView.swift:387-432`, the avatar-or-
// initials idiom `DiscoverWorkoutDetailView`'s own doc comment already
// names as "the avatar-or-real-photo idiom this task's brief names
// explicitly") since `profiles` carries a real `avatar_url` this board can
// show. Compact volume text via `StatMath.compactNumber` — the same
// formatter `YouTabView`'s own lifetime-volume stat tile already uses
// (`Features/You/YouTabView.swift:228`).
struct TopLiftersView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var lifters: [Profile] = []
    @State private var loading = true
    @State private var errorText: String?

    #if DEBUG
    /// Debug-only: true only via the catalog fixture init at the bottom of
    /// this file — same seam idiom as `DiscoverView.catalogSkipLoad`
    /// (`Features/Library/DiscoverView.swift:32-41`).
    var catalogSkipLoad = false
    #endif

    var body: some View {
        ScrollView {
            if loading {
                HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                    .padding(.top, 60)
            } else if let errorText {
                GSErrorCard(message: errorText) { Task { await load() } }
                    .padding(16)
            } else if lifters.isEmpty {
                GSEmptyState(
                    icon: "trophy",
                    title: "No lifters yet",
                    message: "Lifetime volume leaders will show up here."
                )
                .padding(.top, 40)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(lifters.enumerated()), id: \.element.id) { index, profile in
                        leaderboardRow(rank: index + 1, profile: profile)

                        if index < lifters.count - 1 {
                            Rectangle()
                                .fill(theme.divider)
                                .frame(height: 1)
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
        .background(theme.bg)
        .navigationTitle("Top Lifters")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .task { await load() }
    }

    // GroupRecapView.leaderboardRow's shape (rank/avatar/name/metric/You-
    // highlight), reused per this file's header comment.
    private func leaderboardRow(rank: Int, profile: Profile) -> some View {
        let isYou = profile.id == appState.currentProfile?.id
        return HStack(spacing: 10) {
            Text("\(rank)")
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(rank == 1 ? theme.accent : theme.neutral700)
                .frame(width: 24, alignment: .leading)

            GSInitialsAvatar(name: profile.username, avatarURL: profile.avatarURL, size: 32)

            Text(isYou ? "You" : profile.username)
                .font(GSFont.bold(13, relativeTo: .body))
                .foregroundStyle(theme.text)
                .lineLimit(1)

            Spacer()

            Text("\(StatMath.compactNumber(profile.lifetimeVolumeLifted)) lbs")
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        // Same "You" tint token GroupRecapView.leaderboardRow uses — see that
        // file's comment: exact hex isn't specified anywhere (no canvas frame
        // for this screen either), a system-styling call using an existing
        // theme token rather than a new literal color.
        .background(isYou ? theme.neutral400.opacity(0.2) : Color.clear)
    }

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        do {
            lifters = try await ProfileRepository.topLifters()
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Catalog fixture seam (`top-lifters` catalog case)

#if DEBUG
extension TopLiftersView {
    /// Debug-only seam for the design-parity screen catalog — same idiom as
    /// `DiscoverView`'s `catalogFixtureWorkouts:` init
    /// (`Features/Library/DiscoverView.swift:183-189`): seeds `lifters`
    /// directly and sets `catalogSkipLoad` so `load()` never fires its live
    /// fetch. Added here (rather than relying on a synthesized memberwise
    /// init) because `_lifters`/`_loading` are `private @State` — this
    /// initializer can only assign them because it lives in the SAME FILE as
    /// those declarations.
    init(catalogFixtureLifters lifters: [Profile]) {
        _lifters = State(initialValue: lifters)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
}
#endif
