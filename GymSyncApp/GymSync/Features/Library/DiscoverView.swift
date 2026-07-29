import SwiftUI

// MARK: - DiscoverView
//
// Library's Discover sub-tab (Phase L Task 3) — public workout repository
// grid. Master spec Flow 4 (`docs/superpowers/specs/2026-06-28-gymsync-
// design.md:790-797`): "Library -> Discover -> tap 'The Murph'." Library's
// four-sub-tab structure (`:690`) lists Discover third; Campaigns (4th)
// stays out per Phase L design §3 ("Campaigns stays Phase C",
// `docs/superpowers/specs/2026-07-18-discover-leaderboards-design.md:18`).
//
// Card shape borrows `LibraryTabView`'s Featured-shelf `packCard` idiom
// (150pt-wide bordered card, image placeholder, name, meta caption —
// `LibraryTabView.swift:203-240`), widened into a 2-column grid (grid idiom:
// `SoundLibrarySheet.catalogGrid`, `Features/Sessions/SoundLibrarySheet.
// swift:180`) since Discover is its own full-screen destination rather than
// a horizontal shelf.
//
// No canvas frame exists for this screen — grepped `docs/design/frame-
// map.json` + `docs/design/*.dc.html` for "Discover": zero hits. The Phase L
// design predicted this ("Discover may be undesigned -> system-designed +
// deviations", `discover-leaderboards-design.md:28`). See
// `docs/design/accepted-deviations.json`'s "discover" entry.
/// Discover grid sort orders (user request 2026-07-28).
enum DiscoverSort: String, CaseIterable, Identifiable {
    case popular, attempts, newest, name

    var id: String { rawValue }

    var label: String {
        switch self {
        case .popular:  return "Popular"
        case .attempts: return "Most attempted"
        case .newest:   return "Newest"
        case .name:     return "A–Z"
        }
    }
}

struct DiscoverView: View {
    @Environment(\.gsTheme) private var theme

    @State private var workouts: [PublicWorkout] = []
    @State private var attemptCounts: [UUID: Int] = [:]
    /// Star counts per routine (open-publishing round) — drives the sort + badge.
    @State private var starCounts: [UUID: Int] = [:]
    @State private var loading = true
    @State private var errorText: String?

    #if DEBUG
    /// Debug-only: true only via the catalog fixture init at the bottom of
    /// this file — skips `load()`'s live network fetch entirely so
    /// `CatalogHostView`'s `discover` state renders deterministically
    /// instead of showing an empty grid (Task 4's seed content doesn't exist
    /// yet). Same seam idiom as `ChatView.catalogSkipLoad`
    /// (`Features/Social/ChatView.swift:145-157`). Always false on every
    /// other path; compiled out of release entirely.
    var catalogSkipLoad = false
    #endif

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    // MARK: - Filter + sort (user request 2026-07-28)

    /// Sort order for the grid. `.popular` is the composite the repository
    /// already shipped with (curator spotlight → stars → attempts → newest),
    /// kept as the default so the unfiltered screen is unchanged.
    @State private var sort: DiscoverSort = .popular
    @State private var featuredOnly = false
    /// A `scoring_metrics` value ("time" / "volume" / "top_set"), or nil for
    /// no metric filter.
    @State private var metricFilter: String?

    private var hasActiveFilter: Bool { featuredOnly || metricFilter != nil }

    /// Metric chips are derived from what is ACTUALLY published — offering a
    /// "Time" filter that matches nothing is the same sin as a fake tag.
    private var metricOptions: [String] {
        Array(Set(workouts.flatMap { $0.scoringMetrics ?? [] })).sorted()
    }

    private var visibleWorkouts: [PublicWorkout] {
        var rows = workouts
        if featuredOnly { rows = rows.filter(\.isFeatured) }
        if let metricFilter {
            rows = rows.filter { ($0.scoringMetrics ?? []).contains(metricFilter) }
        }
        switch sort {
        case .popular:
            rows.sort { a, b in
                if a.isFeatured != b.isFeatured { return a.isFeatured }
                let sa = starCounts[a.id] ?? 0, sb = starCounts[b.id] ?? 0
                if sa != sb { return sa > sb }
                let aa = attemptCounts[a.id] ?? 0, ab = attemptCounts[b.id] ?? 0
                if aa != ab { return aa > ab }
                return a.routine.createdAt > b.routine.createdAt
            }
        case .attempts:
            rows.sort {
                (attemptCounts[$0.id] ?? 0, $0.routine.createdAt)
                    > (attemptCounts[$1.id] ?? 0, $1.routine.createdAt)
            }
        case .newest:
            rows.sort { $0.routine.createdAt > $1.routine.createdAt }
        case .name:
            rows.sort {
                $0.routine.name.localizedCaseInsensitiveCompare($1.routine.name) == .orderedAscending
            }
        }
        return rows
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                topLiftersRow

                if loading {
                    HStack { Spacer(); ProgressView().tint(theme.accent); Spacer() }
                        .padding(.top, 60)
                } else if let errorText {
                    GSErrorCard(message: errorText) { Task { await load() } }
                        .padding(16)
                } else if workouts.isEmpty {
                    GSEmptyState(
                        icon: "trophy",
                        title: "Nothing published yet",
                        message: "Featured public workouts will show up here."
                    )
                    .padding(.top, 40)
                } else {
                    filterSortRow
                        .padding(.top, 16)

                    let rows = visibleWorkouts
                    if rows.isEmpty {
                        GSEmptyState(
                            icon: "line.3.horizontal.decrease.circle",
                            title: "No workouts match",
                            message: "Nothing published fits these filters yet.",
                            ctaTitle: "Clear filters",
                            action: { featuredOnly = false; metricFilter = nil }
                        )
                        .padding(.horizontal, 16)
                        .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 10) {
                            ForEach(rows) { workout in
                                NavigationLink {
                                    DiscoverWorkoutDetailView(workout: workout)
                                } label: {
                                    workoutCard(workout)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .background(theme.bg)
        // Dock clearance — on the ScrollView directly, not LibraryTabView's
        // Group (the Group cascade inflated Exercises' chips row).
        .contentMargins(.bottom, 88, for: .scrollContent)
        .task { await load() }
    }

    /// Sort menu + filter chips, horizontally scrollable so the row never
    /// wraps or truncates as metric options vary. Chip idiom matches the
    /// Exercises sub-tab's filter chips (accent fill when active).
    private var filterSortRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(DiscoverSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                } label: {
                    chip(text: sort.label, icon: "arrow.up.arrow.down", active: false)
                }

                chip(text: "Featured", icon: nil, active: featuredOnly)
                    .onTapGesture { featuredOnly.toggle() }

                ForEach(metricOptions, id: \.self) { metric in
                    chip(text: Self.metricLabel(metric), icon: nil,
                         active: metricFilter == metric)
                        .onTapGesture {
                            metricFilter = (metricFilter == metric) ? nil : metric
                        }
                }

                if hasActiveFilter {
                    chip(text: "Clear", icon: "xmark", active: false)
                        .onTapGesture { featuredOnly = false; metricFilter = nil }
                }
            }
            .padding(.horizontal, 16)
        }
        // The row is its own scroll view — keep the parent's dock margin off
        // it (the Group-cascade bug this file's own comment below records).
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    private func chip(text: String, icon: String?, active: Bool) -> some View {
        HStack(spacing: 5) {
            if let icon {
                Image(systemName: icon).font(.system(size: 10, weight: .semibold))
            }
            Text(text).font(GSFont.bodyMedium(12.5, relativeTo: .caption))
        }
        .foregroundStyle(active ? theme.bg : theme.neutral700)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minHeight: 36)
        .background(active ? theme.accent : theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(active ? Color.clear : theme.divider, lineWidth: 1))
        .contentShape(Capsule())
    }

    // MARK: - Top Lifters entry point (Phase L Task 4)
    //
    // Card/row pushing the global cumulative-volume board, above the grid so
    // it's reachable regardless of loading/error/empty state below it. Shape
    // reuses `ScheduleSessionView.whatSection`'s bordered icon + title/
    // subtitle + chevron Menu-row idiom (`Features/Sessions/
    // ScheduleSessionView.swift:358-384`), swapped from a `Menu` to a plain
    // `NavigationLink` push since this row has nowhere to pick from — it
    // just navigates.
    private var topLiftersRow: some View {
        NavigationLink {
            TopLiftersView()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "trophy.fill")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Top Lifters")
                        .font(GSFont.bold(14, relativeTo: .headline))
                        .foregroundStyle(theme.text)
                    Text("Global leaderboard by lifetime volume")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .background(theme.surface)
            .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.top, 16)
    }

    // Canvas-idiom card: image placeholder + optional FEATURED chip
    // (LibraryTabView.heroCard's chip shape), name, owner caption, scoring-
    // metric chips (judge, per the workout's `scoring_metrics` — the T1-
    // reviewer note this task's brief cites: "the UI applies the routine's
    // scoring_metrics filter for which sort options to OFFER", so the SAME
    // filtered set doubles as the card's metric chips), and an attempt-count
    // caption when non-zero (dropped entirely at 0 — "no fake tag" idiom,
    // same as `RoutinesListView.routineCard`'s tag-omission rule).
    private func workoutCard(_ workout: PublicWorkout) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.neutral300)
                Image(systemName: "photo")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.3))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if workout.isFeatured {
                    Text("FEATURED")
                        .font(GSFont.bold(9, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(theme.accent)
                        .padding(8)
                }
            }
            .frame(height: 84)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(workout.routine.name)
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text("by \(workout.ownerUsername)")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)

                if let metrics = workout.scoringMetrics, !metrics.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(metrics, id: \.self) { metric in
                            GSTag(text: Self.metricLabel(metric), style: .neutral)
                        }
                    }
                }

                HStack(spacing: 8) {
                    if let stars = starCounts[workout.id], stars > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 9))
                            Text("\(stars)")
                        }
                        .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                        .foregroundStyle(theme.accent)
                    }
                    if let count = attemptCounts[workout.id], count > 0 {
                        Text("\(count) attempt\(count == 1 ? "" : "s")")
                            .font(GSFont.body(10, relativeTo: .caption2))
                            .foregroundStyle(theme.neutral500)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            // Redesign (user feedback 2026-07-23: "the widgets are not the
            // same size") — a fixed text-zone height makes every grid card
            // uniform regardless of optional chips/attempt lines.
            .frame(height: 84, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface)
        .cornerRadius(GSMetrics.radiusSm)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    /// Shared with `DiscoverWorkoutDetailView`'s metric chips/segmented sort
    /// labels — kept `static` (not a free function) so both call sites cite
    /// one obvious owner.
    static func metricLabel(_ raw: String) -> String {
        switch raw {
        case "time": return "Time"
        case "volume": return "Volume"
        case "top_set": return "Top Set"
        default: return raw.capitalized
        }
    }

    @MainActor
    private func load() async {
        #if DEBUG
        if catalogSkipLoad { return }
        #endif
        loading = true
        defer { loading = false }
        do {
            let rows = try await PublicWorkoutRepository.publicWorkouts()
            attemptCounts = (try? await PublicWorkoutRepository.attemptCounts(
                routineIDs: rows.map(\.id))) ?? [:]
            // Stars (open-publishing round): the popularity signal. Sort:
            // curator spotlight first, then stars, then attempts, then newest.
            starCounts = (try? await PublicWorkoutRepository.starCounts(
                routineIDs: rows.map(\.id))) ?? [:]
            workouts = rows.sorted { a, b in
                if a.isFeatured != b.isFeatured { return a.isFeatured }
                let sa = starCounts[a.id] ?? 0, sb = starCounts[b.id] ?? 0
                if sa != sb { return sa > sb }
                let aa = attemptCounts[a.id] ?? 0, ab = attemptCounts[b.id] ?? 0
                if aa != ab { return aa > ab }
                return a.routine.createdAt > b.routine.createdAt
            }
            errorText = nil
        } catch let error as GymSyncError {
            errorText = error.errorDescription
        } catch {
            errorText = error.localizedDescription
        }
    }
}

// MARK: - Catalog fixture seam (`discover` catalog case)

#if DEBUG
extension DiscoverView {
    /// Debug-only seam for the design-parity screen catalog: seeds
    /// `workouts`/`attemptCounts` directly and sets `catalogSkipLoad` so
    /// `load()` never fires its live fetch — same idiom as `ChatView`'s
    /// `catalogFixtureMessages:` init (`Features/Social/ChatView.swift:
    /// 961-968`). Added here (rather than relying on the synthesized
    /// memberwise init) because `_workouts`/`_attemptCounts` are `private
    /// @State` — this initializer can only assign them because it lives in
    /// the SAME FILE as those declarations.
    init(catalogFixtureWorkouts workouts: [PublicWorkout],
         catalogFixtureAttemptCounts attemptCounts: [UUID: Int] = [:]) {
        _workouts = State(initialValue: workouts)
        _attemptCounts = State(initialValue: attemptCounts)
        _loading = State(initialValue: false)
        catalogSkipLoad = true
    }
}
#endif
