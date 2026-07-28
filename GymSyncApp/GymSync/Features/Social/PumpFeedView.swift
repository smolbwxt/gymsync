import SwiftUI

// MARK: - Pump Check feed (spec 2026-07-27, P3)
//
// Reverse-chronological friend posts + your own. RLS is the audience: the
// query is a bare newest-first page and the server decides who sees what
// (author + unblocked accepted friends — 20260731000001). Weights render
// in the VIEWER'S unit via the Units pipeline; the snapshot stays
// canonical pounds.

struct PumpFeedView: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var posts: [WorkoutPost] = []
    @State private var authorsByID: [UUID: Profile] = [:]
    /// emoji -> count, and the viewer's own reactions, per post.
    @State private var countsByPost: [UUID: [String: Int]] = [:]
    @State private var mineByPost: [UUID: Set<String>] = [:]
    @State private var isLoading = false
    @State private var reachedEnd = false
    @State private var errorText: String?
    @State private var reportTarget: WorkoutPost?
    @State private var deleteTarget: WorkoutPost?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if posts.isEmpty && !isLoading && errorText == nil {
                    GSEmptyState(
                        icon: "camera",
                        title: "No pump checks yet",
                        message: "Finish a workout to post yours, or add friends to see theirs — photos and receipts, friends only."
                    )
                    .padding(.top, 12)
                }

                ForEach(posts) { post in
                    PumpPostCard(
                        post: post,
                        author: authorsByID[post.authorID],
                        isMine: post.authorID == appState.currentProfile?.id,
                        myReactions: mineByPost[post.id] ?? [],
                        reactionCounts: countsByPost[post.id] ?? [:],
                        onReact: { emoji in Task { await toggleReaction(post: post, emoji: emoji) } },
                        onDelete: { deleteTarget = post },
                        onReport: { reportTarget = post }
                    )
                    .onAppear {
                        if post.id == posts.last?.id { Task { await loadMore() } }
                    }
                }

                if isLoading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.vertical, 20)
                }
                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(12, relativeTo: .footnote))
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .scrollContentBackground(.hidden)
        .background(theme.bg)
        .gsHidesDock()
        .navigationTitle("Feed")
        .navigationBarTitleDisplayMode(.inline)
        .task { await initialLoad() }
        .refreshable { await refresh() }
        .sheet(item: $reportTarget) { post in
            ReportSheet(reportedUserID: post.authorID, contentType: .post, contentID: post.id)
        }
        .confirmationDialog(
            "Delete this post?",
            isPresented: Binding(get: { deleteTarget != nil },
                                 set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete post", role: .destructive) {
                if let post = deleteTarget { Task { await delete(post) } }
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("Your photo and summary disappear from every friend's feed.")
        }
    }

    // MARK: - Loading

    @MainActor
    private func initialLoad() async {
        guard posts.isEmpty else { return }
        await refresh()
    }

    @MainActor
    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await WorkoutPostRepository.feed()
            posts = page
            reachedEnd = page.count < 20
            errorText = nil
            await hydrate(page)
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading, !reachedEnd, let last = posts.last else { return }
        isLoading = true
        defer { isLoading = false }
        guard let page = try? await WorkoutPostRepository.feed(before: last.createdAt) else { return }
        // Defensive de-dupe: a post created between pages could re-appear.
        let known = Set(posts.map(\.id))
        posts.append(contentsOf: page.filter { !known.contains($0.id) })
        reachedEnd = page.count < 20
        await hydrate(page)
    }

    /// Authors + reactions for a page — best-effort; a failed hydrate
    /// leaves cards rendering with what they have.
    @MainActor
    private func hydrate(_ page: [WorkoutPost]) async {
        let missingAuthors = Set(page.map(\.authorID)).subtracting(authorsByID.keys)
        if !missingAuthors.isEmpty,
           let fetched = try? await ProfileRepository.fetchMany(ids: Array(missingAuthors)) {
            for profile in fetched { authorsByID[profile.id] = profile }
        }
        if let reactions = try? await WorkoutPostRepository.reactions(postIDs: page.map(\.id)) {
            let selfID = appState.currentProfile?.id
            for postID in page.map(\.id) {
                let rows = reactions.filter { $0.postID == postID }
                countsByPost[postID] = rows.reduce(into: [:]) { $0[$1.emoji, default: 0] += 1 }
                mineByPost[postID] = Set(rows.filter { $0.userID == selfID }.map(\.emoji))
            }
        }
    }

    // MARK: - Actions

    /// Optimistic toggle — the server is authoritative; a failure rolls the
    /// tap back.
    @MainActor
    private func toggleReaction(post: WorkoutPost, emoji: String) async {
        let had = mineByPost[post.id, default: []].contains(emoji)
        if had {
            mineByPost[post.id, default: []].remove(emoji)
            countsByPost[post.id, default: [:]][emoji, default: 1] -= 1
        } else {
            mineByPost[post.id, default: []].insert(emoji)
            countsByPost[post.id, default: [:]][emoji, default: 0] += 1
        }
        do {
            if had {
                try await WorkoutPostRepository.unreact(postID: post.id, emoji: emoji)
            } else {
                try await WorkoutPostRepository.react(postID: post.id, emoji: emoji)
            }
        } catch {
            if had {
                mineByPost[post.id, default: []].insert(emoji)
                countsByPost[post.id, default: [:]][emoji, default: 0] += 1
            } else {
                mineByPost[post.id, default: []].remove(emoji)
                countsByPost[post.id, default: [:]][emoji, default: 1] -= 1
            }
        }
    }

    @MainActor
    private func delete(_ post: WorkoutPost) async {
        deleteTarget = nil
        do {
            try await WorkoutPostRepository.delete(id: post.id, photoPath: post.photoPath)
            withAnimation(.easeOut(duration: 0.2)) {
                posts.removeAll { $0.id == post.id }
            }
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Post card

struct PumpPostCard: View {
    let post: WorkoutPost
    let author: Profile?
    let isMine: Bool
    let myReactions: Set<String>
    let reactionCounts: [String: Int]
    let onReact: (String) -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @Environment(\.gsTheme) private var theme
    @State private var photoURL: URL?

    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    var body: some View {
        GSCard(bordered: true) {
            VStack(alignment: .leading, spacing: 0) {
                authorRow
                    .padding(12)

                if post.photoPath != nil {
                    photoBlock
                }

                summaryBlock
                    .padding(12)

                reactionsRow
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .contextMenu {
            if isMine {
                Button(role: .destructive, action: onDelete) {
                    Label("Delete post", systemImage: "trash")
                }
            } else {
                Button(action: onReport) {
                    Label("Report", systemImage: "flag")
                }
            }
        }
        .task(id: post.photoPath) {
            guard let path = post.photoPath else { return }
            photoURL = try? await WorkoutPostRepository.signedPhotoURL(path: path)
        }
    }

    private var authorRow: some View {
        HStack(spacing: 9) {
            GSInitialsAvatar(name: author?.username ?? "?",
                             avatarURL: author?.avatarURL, size: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(isMine ? "You" : (author?.username ?? "Lifter"))
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text(post.createdAt.formatted(.relative(presentation: .named)))
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
            }
            Spacer()
            if post.isLate {
                GSTag(text: "late", style: .neutral)
            }
        }
    }

    private var photoBlock: some View {
        AsyncImage(url: photoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(theme.bg)
                    .overlay {
                        Image(systemName: "photo")
                            .font(.system(size: 22))
                            .foregroundStyle(theme.neutral500)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 300)
        .clipped()
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(post.summary.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise)
            }

            HStack(spacing: 6) {
                let minutes = max(1, post.summary.durationSeconds / 60)
                Text("\(minutes) min")
                Text("·")
                Text("\(StatMath.compactNumber(Units.fromPounds(post.summary.totalVolumeLbs, to: unit))) \(unit.label)")
                if post.includesHR, let avg = post.avgBpm, let maxBpm = post.maxBpm {
                    Text("·")
                    Text("avg \(avg) · max \(maxBpm) bpm")
                }
                Spacer(minLength: 0)
            }
            .font(GSFont.body(11.5, relativeTo: .caption))
            .foregroundStyle(theme.neutral500)
        }
    }

    private func exerciseRow(_ exercise: PostSummary.ExerciseEntry) -> some View {
        // Spec decision 4: one mini bar per BARBELL exercise, its top set.
        let topWeight = exercise.sets.compactMap { $0.isFailed ? nil : $0.weightLbs }.max()
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(exercise.name)
                    .font(GSFont.bold(13.5, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if exercise.equipment == "barbell", let topWeight {
                    GSBarLoaderMini(
                        target: Units.fromPounds(topWeight, to: unit),
                        barWeight: unit.defaultBar,
                        plates: unit.standardPlates,
                        unit: unit)
                }
            }
            ForEach(Array(exercise.sets.enumerated()), id: \.offset) { index, set in
                HStack(spacing: 6) {
                    Text("Set \(index + 1)")
                        .font(GSFont.body(11, relativeTo: .caption2))
                        .foregroundStyle(theme.neutral500)
                        .frame(width: 40, alignment: .leading)
                    Text(setText(set))
                        .font(GSFont.bodyMedium(12.5, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(theme.text)
                    if set.isPR { GSTag(text: "PR", style: .accent) }
                    if set.isFailed { GSTag(text: "FAIL", style: .neutral) }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func setText(_ set: PostSummary.ExerciseEntry.SetEntry) -> String {
        let weight = set.weightLbs.map {
            Units.format(pounds: $0, unit: unit, rounded: false, includeUnit: false)
        } ?? "—"
        return "\(weight) × \(set.reps.map(String.init) ?? "—")"
    }

    private var reactionsRow: some View {
        HStack(spacing: 8) {
            ForEach(GroupRecapView.kudosEmoji, id: \.self) { emoji in
                let count = reactionCounts[emoji] ?? 0
                let mine = myReactions.contains(emoji)
                Button {
                    onReact(emoji)
                } label: {
                    HStack(spacing: 4) {
                        Text(emoji).font(.system(size: 14))
                        if count > 0 {
                            Text("\(count)")
                                .font(GSFont.bold(11, relativeTo: .caption2))
                                .foregroundStyle(mine ? theme.accent700 : theme.neutral700)
                                .monospacedDigit()
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(mine ? theme.accent100 : theme.bg)
                    .overlay(
                        Capsule().strokeBorder(mine ? theme.accent : theme.divider, lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
        }
    }
}
