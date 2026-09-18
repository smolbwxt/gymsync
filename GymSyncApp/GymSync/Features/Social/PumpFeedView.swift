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
    let onReact: (String) -> Void
    let onDelete: () -> Void
    let onReport: () -> Void

    @Environment(\.gsTheme) private var theme
    @State private var photoURL: URL?
    @State private var showsMetrics = false

    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    var body: some View {
        // gs3D pass (2026-08-13): the bordered flat card joins the extruded
        // language — static depth (the card itself isn't a button; its
        // reaction chips, the photo door and its menus are the tappables).
        //
        // SPEC §1'S ANATOMY, ALL SEVEN LINES, RE-COMPOSED (spec §5, reference
        // frame `pump-check-card-v2`): 1 who and when, 2 the trajectory,
        // 3 this week's rung, 4 the highlight, 5 the workout in plain terms,
        // 6 the picture, 7 reactions. The same seven facts about half the
        // height, and three moves buy it:
        //
        //  1. THE HIGHLIGHT LEADS, as a raised island with the picture beside
        //     it. Line 4 is the thing the lifter chose to say and it used to
        //     sit buried between the rung chips and the set rows.
        //  2. THE PICTURE IS A THUMBNAIL, NOT A BLOCK. 300 pt of full-bleed
        //     photo pushed the reactions off the fold and made every card the
        //     same height whatever it said. At 88 pt it still says there is a
        //     picture; tapping it opens `WorkoutMetricsSheet`, where the whole
        //     frame and every set live.
        //  3. THE SET ROWS COLLAPSE TO ONE LINE EACH (`PumpCardCollapse`).
        //     Two exercises and three sets were seven rows of furniture under
        //     the one sentence that mattered.
        //
        // Lines 2, 3, 4 and 7 are above the fold together, which is spec §1's
        // whole claim for the card. NOTHING ABOUT THE POST'S DATA CHANGED:
        // same initializer, same `WorkoutPost`, same call sites.
        VStack(alignment: .leading, spacing: 12) {
            authorRow
            highlightFace
            if let trajectory = post.trajectory {
                trajectoryBlock(trajectory)
            }
            collapsedRows
            PumpPlainTerms(post: post, unit: unit)
            GSDivider()
            reactionsRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
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
        .sheet(isPresented: $showsMetrics) {
            // THE SHEET TAKES THE URL THIS CARD ALREADY HOLDS. It is built
            // entirely from `post.summary` / `post.photoPath` — no repository
            // read of its own, and no second signed-URL round trip for a
            // photo whose link is already in hand.
            WorkoutMetricsSheet(post: post, photoURL: photoURL)
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

    /// Lines 4 and 6 — the pick the lifter made, and the picture, on one
    /// raised island (design rule 1's "a folder is a raised island"), the
    /// first thing under the name.
    ///
    /// A post can have a highlight, a photo, both, or neither — the second
    /// fixture post on `pump-feed-post` has neither — so the island appears
    /// only when it has something to hold, and the two halves are independent.
    @ViewBuilder
    private var highlightFace: some View {
        if post.highlight != nil || post.photoPath != nil {
            HStack(alignment: .top, spacing: 12) {
                if let highlight = post.highlight {
                    highlightColumn(highlight)
                }
                if post.photoPath != nil {
                    photoDoor
                }
                if post.highlight == nil {
                    Spacer(minLength: 0)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .gs3DCard(cornerRadius: GSMetrics.radiusSm, lipHeight: 5)
        }
    }

    /// NO ACCENT and no colour: the kind is carried by the WORD — the line
    /// itself already reads "PR — Back Squat" — and this card's one accent is
    /// a reaction of your own, which is the only thing on it you can do.
    private func highlightColumn(_ highlight: PostHighlight) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            GSSectionHeader("THE ONE THING")
            Text(HighlightText.line(highlight, unit: unit))
                .font(GSFont.bold(17, relativeTo: .title3))
                .foregroundStyle(theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Text(PumpCardCollapse.note(for: highlight))
                .font(GSFont.bodyMedium(12, relativeTo: .caption))
                .foregroundStyle(theme.neutral700)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// An 88 pt tile that is also a door needs one line telling you so, or the
    /// composition's whole argument — the picture shrinks, the detail moves
    /// behind it — is a claim the card never makes to its reader. The caption
    /// sits under the tile and inside its column, at the caption's own size.
    private var photoDoor: some View {
        Button {
            showsMetrics = true
        } label: {
            VStack(spacing: 5) {
                photoThumb
                Text(PumpCardCollapse.photoCaption)
                    .font(GSFont.body(10, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(width: 88)
            }
        }
        .buttonStyle(.plain)
    }

    private var photoThumb: some View {
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
        .frame(width: 88, height: 88)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// One line per exercise, every number kept — the full per-set rows live
    /// in `WorkoutMetricsSheet`, behind the photo.
    ///
    /// The `PR` tag here is NEUTRAL, not accent. The shipped card spent accent
    /// on it and again on a reaction of your own, which is two (design rule 2);
    /// a finished post is none of accent's jobs, and the word says it anyway.
    private var collapsedRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(post.summary.exercises.enumerated()), id: \.offset) { _, exercise in
                HStack(spacing: 8) {
                    Text(PumpCardCollapse.line(for: exercise, unit: unit))
                        .font(GSFont.bodyMedium(12.5, relativeTo: .caption).monospacedDigit())
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    if PumpCardCollapse.hasPR(exercise) {
                        GSTag(text: "PR", style: .neutral)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
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

// MARK: - Line 5, in both places it is printed

/// `Push day · 42 min · 7,240 lb · avg 142 · max 171 bpm` — spec §1 line 5,
/// unchanged in content, spelling and type from the composition it was lifted
/// out of. The routine name is dropped rather than replaced for a freeform
/// session; "Workout · 42 min" names nothing.
///
/// A VIEW rather than two copies: the card prints it and so does
/// `WorkoutMetricsSheet`, and one line of facts printed twice from two
/// spellings is how they drift apart.
struct PumpPlainTerms: View {
    let post: WorkoutPost
    let unit: WeightUnit

    @Environment(\.gsTheme) private var theme

    var body: some View {
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

// MARK: - The collapse, pure

/// Spec §5's third move: the per-set rows on the feed card become one line per
/// exercise. Pure over `PostSummary` and the viewer's unit, so the wording is
/// testable and identical everywhere it is printed.
enum PumpCardCollapse {

    /// `Back Squat · 2 × 235 lbs` — the exercise, how many sets it took, and
    /// the heaviest bar that was not failed.
    ///
    /// The COUNT is every set, failed ones included: the lifter did them. The
    /// WEIGHT excludes failed sets, exactly as the full rows' top-set bar
    /// loader does — a bar you did not lift is not your top set.
    ///
    /// An entry with no weight at all (bodyweight, cardio) falls back to its
    /// best rep count — `Walking Lunge · 1 × 20` — and one with neither to a
    /// bare set count, because a line that printed `— × —` says nothing.
    static func line(for exercise: PostSummary.ExerciseEntry, unit: WeightUnit) -> String {
        let count = exercise.sets.count
        let topWeight = exercise.sets.compactMap { $0.isFailed ? nil : $0.weightLbs }.max()
        if let topWeight {
            let weight = Units.format(pounds: topWeight, unit: unit,
                                      rounded: false, includeUnit: true)
            return "\(exercise.name) · \(count) × \(weight)"
        }
        let topReps = exercise.sets.compactMap { $0.isFailed ? nil : $0.reps }.max()
        if let topReps {
            return "\(exercise.name) · \(count) × \(topReps)"
        }
        return "\(exercise.name) · \(count) \(count == 1 ? "set" : "sets")"
    }

    /// Whether the collapsed line earns a `PR` tag beside it. A PR on a FAILED
    /// set is not a record — the same rule the weight above obeys.
    static func hasPR(_ exercise: PostSummary.ExerciseEntry) -> Bool {
        exercise.sets.contains(where: { $0.isPR && !$0.isFailed })
    }

    /// The island's detail line: what kind of thing the lifter picked, in
    /// words, under the highlight itself.
    static func note(for highlight: PostHighlight) -> String {
        switch highlight.kind {
        case .pr:        return "a personal record"
        case .topSet:    return "the day's top set"
        case .milestone: return "a milestone"
        }
    }

    /// The caption under the 88 pt thumbnail. The tile is a door and it says so.
    static let photoCaption = "Tap for the full workout"
}
