import SwiftUI

struct LibraryTabView: View {
    // Phase L Task 3: added `.discover` — master spec's four-sub-tab
    // structure (`docs/superpowers/specs/2026-06-28-gymsync-design.md:690`:
    // "Routines / Exercises / Discover / Campaigns"). Campaigns stayed out
    // per Phase L design §3 ("Campaigns stays Phase C",
    // `docs/superpowers/specs/2026-07-18-discover-leaderboards-design.md:18`).
    // Phase C Task 2: added `.campaigns` — the four-sub-tab structure
    // completes (Flow 8, spec :864-865).
    enum SubTab: Hashable { case routines, exercises, discover, campaigns }
    @State private var selection: SubTab = .routines
    @Environment(\.gsTheme) private var theme

    // MARK: - Featured shelf (Canvas frame 3: Library Featured)

    @State private var featured: [(routine: Routine, ownerUsername: String)] = []
    @State private var featuredExerciseCounts: [UUID: Int] = [:]
    @State private var cloningIDs: Set<UUID> = []
    @State private var cloneErrorText: String?

    /// Bumped after a successful clone to force `RoutinesListView` to tear
    /// down and re-mount, re-running its own `.task { await load() }` so the
    /// newly-cloned routine appears in "Your routines" immediately.
    /// `RoutinesListView.swift` is out of this task's file scope (brief lists
    /// only `LibraryTabView.swift` + `RoutineBuilderView.swift`), so its
    /// private `load()` can't be invoked directly — SwiftUI's `.id()`
    /// identity-change mechanism reruns it without touching that file.
    @State private var routinesRefreshToken = UUID()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Canvas: segmented sub-tab control at top of Library (Dossier §6)
                HStack {
                    segmentedControl
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(theme.bg)

                GSDivider()

                switch selection {
                case .routines:
                    // Featured shelf rides INSIDE the routines list as its
                    // header, so the whole tab scrolls as one (was: fixed
                    // shelf pinning a cramped list below it).
                    RoutinesListView(
                        featuredHeader: featured.isEmpty ? nil : AnyView(
                            VStack(spacing: 0) { featuredShelf; GSDivider() }
                        )
                    )
                    .id(routinesRefreshToken)
                case .exercises:
                    ExercisesListView()
                case .discover:
                    DiscoverView()
                case .campaigns:
                    CampaignsTabView()
                }
            }
            .background(theme.bg)
            .navigationTitle("Library")
            // Inline (compact) title — the large-title bar left ~15% of the
            // screen blank above the content.
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(theme.surface, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await loadFeatured() }
    }

    // Canvas: `.seg` — flat rectangle, 1px divider border, no radius, hugs
    // content. Phase L Task 3 widened this from 2 to 3 segments (Discover
    // added); Phase C Task 2 widens it again, 3 -> 4 (Campaigns added) —
    // every non-first segment gets the same leading-divider overlay the
    // original Routines/Exercises pair established.
    private var segmentedControl: some View {
        HStack(spacing: 0) {
            segmentOption(title: "Routines", tab: .routines)
            segmentOption(title: "Exercises", tab: .exercises)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                }
            segmentOption(title: "Discover", tab: .discover)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                }
            segmentOption(title: "Campaigns", tab: .campaigns)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(theme.divider)
                        .frame(width: 1)
                }
        }
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // Canvas: `.seg-opt` — selected = accent fill + bg text, unselected = transparent.
    // 44pt minimum tap height per DEFECT audit, independent of the 7/12px visual padding.
    private func segmentOption(title: String, tab: SubTab) -> some View {
        let isSelected = selection == tab
        return Button {
            selection = tab
        } label: {
            Text(title)
                .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? theme.bg : theme.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .background(isSelected ? theme.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Featured shelf

    // Frame 3: accent star + "Featured · curated packs" kicker, a SEASONAL
    // hero card (newest publication), then a horizontal row of the rest.
    // Entirely absent when `featured` is empty (gated by the caller above).
    private var featuredShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(theme.accent700)
                Text("Featured · curated packs")
                    .font(GSFont.bodyMedium(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.text.opacity(0.6))
            }
            .padding(.horizontal, 16)

            if let hero = featured.first {
                heroCard(hero)
                    .padding(.horizontal, 16)
            }

            if featured.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(Array(featured.dropFirst()).enumerated()), id: \.offset) { _, item in
                            packCard(item)
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            if let cloneErrorText {
                Text(cloneErrorText)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 16)
            }
        }
        .padding(.top, 14)
        .padding(.bottom, 14)
    }

    // Canvas: 150pt image placeholder (neutral300 + centered photo glyph @30%),
    // bottom gradient scrim, SEASONAL chip, bold-22 white name, "by {owner}"
    // caption; full-width primary CTA below with space-between plus glyph
    // (canvas button doctrine — see PushPrimingView's "Open Settings" CTA for
    // the same label+Spacer+icon-inside-a-`.frame(maxWidth:.infinity)` shape).
    private func heroCard(_ item: (routine: Routine, ownerUsername: String)) -> some View {
        let isCloning = cloningIDs.contains(item.routine.id)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                Rectangle().fill(theme.neutral300)
                Image(systemName: "photo")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.3))

                VStack(alignment: .leading, spacing: 8) {
                    Text("SEASONAL")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(0.6)
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(theme.accent)

                    Text(item.routine.name)
                        .font(GSFont.bold(22, relativeTo: .title2))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text("by \(item.ownerUsername)")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.black.opacity(0.7), .clear],
                                   startPoint: .bottom, endPoint: .top)
                )
            }
            .frame(height: 150)
            .clipped()

            Button {
                Task { await clone(item.routine.id) }
            } label: {
                HStack {
                    Text("Add to my routines")
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 12))
            .disabled(isCloning)
            .opacity(isCloning ? 0.6 : 1)
        }
    }

    // Canvas: 150pt-wide bordered card — 84pt placeholder, name, exercise
    // count caption ("packs" are single routines in v1 — no pack concept in
    // the schema, see the plan's self-review notes), centered "Add" CTA.
    private func packCard(_ item: (routine: Routine, ownerUsername: String)) -> some View {
        let isCloning = cloningIDs.contains(item.routine.id)
        let count = featuredExerciseCounts[item.routine.id] ?? 0
        return VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(theme.neutral300)
                Image(systemName: "photo")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(theme.text.opacity(0.3))
            }
            .frame(width: 150, height: 84)
            .clipped()

            VStack(alignment: .leading, spacing: 4) {
                Text(item.routine.name)
                    .font(GSFont.bold(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                Text("\(count) exercise\(count == 1 ? "" : "s")")
                    .font(GSFont.body(11, relativeTo: .caption2))
                    .foregroundStyle(theme.neutral500)

                Button {
                    Task { await clone(item.routine.id) }
                } label: {
                    Text("Add")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(GSSecondaryButtonStyle(fontSize: 12, horizontalPadding: 7, verticalPadding: 7))
                .disabled(isCloning)
                .opacity(isCloning ? 0.6 : 1)
                .padding(.top, 4)
            }
            .padding(10)
        }
        .frame(width: 150)
        .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Data

    @MainActor
    private func loadFeatured() async {
        do {
            let rows = try await RoutineRepository.publicRoutines()
            let exercises = (try? await RoutineRepository.exercisesForRoutines(
                ids: rows.map { $0.routine.id }
            )) ?? []
            featuredExerciseCounts = Dictionary(grouping: exercises, by: \.routineID).mapValues(\.count)
            featured = rows
        } catch {
            // Per brief: failure or empty -> section entirely absent, no
            // empty-state chrome. `featured.isEmpty` already gates rendering.
            featured = []
            featuredExerciseCounts = [:]
        }
    }

    @MainActor
    private func clone(_ routineID: UUID) async {
        guard !cloningIDs.contains(routineID) else { return }
        cloningIDs.insert(routineID)
        defer { cloningIDs.remove(routineID) }
        do {
            _ = try await RoutineRepository.clone(routineID: routineID)
            cloneErrorText = nil
            routinesRefreshToken = UUID()
        } catch {
            cloneErrorText = ErrorMapping.map(error).errorDescription
        }
    }
}
