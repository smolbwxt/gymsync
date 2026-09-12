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
    // Sound reactions (20260811000004): rack = attachable, names label chips.
    @State private var ownedSoundSlugs: [String] = []
    @State private var soundNames: [String: String] = [:]
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
                        ownedSoundSlugs: ownedSoundSlugs,
                        soundNames: soundNames,
                        onReact: { emoji in Task { await commitReaction(post: post, emoji: emoji) } },
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
        .task {
            ownedSoundSlugs = (try? await SoundboardFavoritesRepository.get()) ?? []
            if let catalog = try? await SoundboardRepository.fetchCatalog() {
                soundNames = Dictionary(uniqueKeysWithValues: catalog.map { ($0.slug, $0.displayName ?? $0.slug) })
            }
        }
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

    /// Optimistic, and ONE-WAY. Spec §2 (Strava's kudos): a reaction commits.
    /// A second tap on a chip you already own does nothing — it is not an
    /// error and it gets no message, because nothing went wrong; the gesture
    /// simply has no second half any more.
    ///
    /// Still optimistic, still rolled back on failure: a tap that never
    /// reached the server must not leave a count that says it did.
    ///
    /// A CONFLICT IS NOT A FAILURE (review fix 9). The guard above reads
    /// CLIENT state, and client state can be behind the server's — the same
    /// reaction from another device, or a row this page loaded before the
    /// hydrate that would have revealed it. `post_reactions`' primary key is
    /// (post_id, user_id, emoji), so that insert comes back 23505 / HTTP 409,
    /// which `ErrorMapping` already distinguishes as `.conflict`. Rolling the
    /// optimistic count back there un-lit a chip the server was holding lit,
    /// and the next refresh silently put it back — the user saw their own
    /// kudos flicker off. The row exists, which is exactly what the tap
    /// wanted, so the chip stays lit and the counts are re-read from the
    /// server rather than guessed at.
    @MainActor
    private func commitReaction(post: WorkoutPost, emoji: String) async {
        guard !mineByPost[post.id, default: []].contains(emoji) else { return }
        mineByPost[post.id, default: []].insert(emoji)
        countsByPost[post.id, default: [:]][emoji, default: 0] += 1
        do {
            try await WorkoutPostRepository.react(postID: post.id, emoji: emoji)
        } catch GymSyncError.conflict {
            // Already committed, by this account, before this tap. Keep the
            // chip lit; let the server say what the counts are.
            await hydrate([post])
        } catch {
            mineByPost[post.id, default: []].remove(emoji)
            countsByPost[post.id, default: [:]][emoji, default: 1] -= 1
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
    let ownedSoundSlugs: [String]
    let soundNames: [String: String]
    let onReact: (String) -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @Environment(\.gsTheme) private var theme
    @State private var photoURL: URL?

    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    var body: some View {
        // gs3D pass (2026-08-13): the bordered flat card joins the extruded
        // language — static depth (the card itself isn't a button; its
        // reaction chips and menus are the tappables). gs3DCard clips
        // content to the rounded face, so the full-bleed photo block keeps
        // its edges.
        VStack(alignment: .leading, spacing: 0) {
            authorRow
                .padding(12)

            // SPEC §1'S ANATOMY, IN ITS ORDER: 1 who and when, 2 the
            // trajectory, 3 this week's rung, 4 the highlight, 5 the workout
            // in plain terms, 6 the picture, 7 reactions.
            //
            // The picture is SIXTH. Lines 2-5 are the reason the card exists
            // ("a snapshot of where people are in their fitness trajectory")
            // and a 300 pt photo above any of them buries it below the fold.
            // This is review fix 4 and it supersedes the plan's S2.7 snippet,
            // which left the photo between line 3 and line 4 and so shipped
            // the order 1, 2, 3, picture, 4, 5, 7.
            //
            // `summaryBlock` carries lines 4 and 5 and the per-exercise rows
            // they sit with. The exercise rows are not one of the seven lines
            // — they are the detail this card has shown since 2026-07 — so
            // they travel with the summary rather than being split from it.
            if let trajectory = post.trajectory {
                trajectoryBlock(trajectory)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }

            summaryBlock
                .padding(.horizontal, 12)
                .padding(.bottom, 12)

            if post.photoPath != nil {
                photoBlock
            }

            reactionsRow
                .padding(12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
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
            // Spec §2: the binary `late` chip becomes elapsed time, and the
            // retake count shows above zero. An OLD row (no `completed_at`)
            // keeps the chip it was written with — an honest fallback rather
            // than a computed "0 min".
            if let retakes = PostLateness.retakeTag(post.retakeCount ?? 0) {
                GSTag(text: retakes, style: .neutral)
            }
            if let lateness = PostLateness.tag(completedAt: post.completedAt,
                                               postedAt: post.createdAt) {
                GSTag(text: lateness, style: .neutral)
            } else if post.isLate {
                GSTag(text: "late", style: .neutral)
            }
        }
    }

    /// Lines 2 and 3 — the trajectory and this week's rung (spec §1).
    ///
    /// A STRIP, not a card: `surface` at 14 pt, design rule 1's "lines that
    /// belong to the card above them". The card is already the one raised
    /// object on this idea and a second extrusion inside it would make two.
    ///
    /// NO ACCENT anywhere in here, `behind` included. Accent has three jobs
    /// (rule 2) and none of them is "a fact about someone else's week"; red
    /// is errors only, and being behind is not an error. The standing is
    /// carried by the WORD, which is what spec §1 asks for.
    private func trajectoryBlock(_ trajectory: PostTrajectory) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(trajectory.line)
                .font(GSFont.bodyMedium(12.5, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.neutral700)
                .lineLimit(2)
                .minimumScaleFactor(0.85)

            if !trajectory.chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(Array(trajectory.chips.enumerated()), id: \.offset) { _, chip in
                        // isNext is never set: a finished post is not an
                        // invitation (design rule 2).
                        GSGoalChip(name: chip.name, done: chip.done,
                                   target: chip.target, fill: chip.fill)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
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
            // Line 4 — the lifter's one pick. Bold body text, no glyph and no
            // colour: the set rows below already carry a `PR` tag in accent,
            // and a second accent on the same card would be two.
            if let highlight = post.highlight {
                Text(HighlightText.line(highlight, unit: unit))
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(2)
            }

            ForEach(Array(post.summary.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise)
            }

            // Line 5 — `Push day · 42 min · 7,240 lb`. The routine name is
            // dropped rather than replaced for a freeform session; "Workout ·
            // 42 min" names nothing.
            HStack(spacing: 6) {
                let minutes = max(1, post.summary.durationSeconds / 60)
                if let routineName = post.summary.routineName, !routineName.isEmpty {
                    Text(routineName)
                    Text("·")
                }
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

            // Sound reactions: chips PLAY for anyone; only owners attach
            // (the menu below + restrictive RLS). Remove your own via the
            // chip's context menu.
            ForEach(reactionCounts.keys.filter { $0.hasPrefix("snd:") }.sorted(), id: \.self) { key in
                let slug = String(key.dropFirst(4))
                let count = reactionCounts[key] ?? 0
                Button {
                    Task { await SoundboardPlayer.shared.play(slug: slug) }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "speaker.wave.2.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("\(soundNames[slug] ?? slug)\(count > 1 ? " \(count)" : "")")
                            .font(GSFont.bold(11, relativeTo: .caption2))
                    }
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(theme.accent100)
                    .clipShape(Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if !ownedSoundSlugs.isEmpty {
                Menu {
                    ForEach(ownedSoundSlugs, id: \.self) { slug in
                        Button {
                            onReact("snd:" + slug)
                        } label: {
                            Label(soundNames[slug] ?? slug, systemImage: "speaker.wave.2")
                        }
                    }
                } label: {
                    Image(systemName: "speaker.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.neutral700)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(theme.bg)
                        .overlay(Capsule().strokeBorder(theme.divider, lineWidth: 1))
                        .clipShape(Capsule())
                        .contentShape(Capsule())
                }
            }
            Spacer(minLength: 0)
        }
    }
}
