import SwiftUI

// Canvas: Routine Builder — custom "×  New Routine  Save" header, flat
// bordered-box fields, card-per-exercise with SETS/REPS/WEIGHT/REST stat
// tiles, drag-to-reorder + a compact remove affordance per card (no native
// List/Form chrome), full-width bordered "+ Add Exercise" CTA.
struct RoutineBuilderView: View {
    let editing: Routine?
    let onSaved: (Routine) -> Void

    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    @State private var name: String = ""
    @State private var description: String = ""
    @State private var items: [RoutineExercise] = []
    @State private var loading = false
    @State private var showExercisePicker = false
    @State private var pickerSearchText = ""
    @State private var errorText: String?
    @State private var allExercises: [Exercise] = []
    // Save honors this (private vs public); UI toggle below (curator-only),
    // bootstrap-seeded from `editing?.visibility` in `load()`.
    @State private var publishAsFeatured = false
    /// Curator-only spotlight flag (open-publishing round 20260728000008):
    /// drives `routines.is_featured` via the targeted publish-fields UPDATE.
    @State private var featureOnSpotlight = false

    // Publish fields (Phase L Task 4) — VISIBLE ONLY while publishAsFeatured
    // is on (`publishFieldsSection`), written via a separate targeted UPDATE
    // in `save()` (see that method's comment for why they never ride
    // `Routine`'s own upsert). `DiscoverWorkoutDetailView.SortMetric`
    // (`Features/Library/DiscoverWorkoutDetailView.swift:76-91`) is reused
    // directly for both pickers' value space rather than re-declaring the
    // same time/volume/top_set/recent vocabulary a second time — that type's
    // own doc comment already states its raw values "match the routines.
    // default_sort/scoring_metrics CHECK constraint's value set verbatim,"
    // and it carries no `private`/`fileprivate` on itself or its cases, so
    // it's directly usable here.
    @State private var defaultSort: DiscoverWorkoutDetailView.SortMetric?
    @State private var scoringMetrics: Set<DiscoverWorkoutDetailView.SortMetric> = []
    @State private var scoringTopSetExerciseID: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Canvas: "Routine name" label + bordered-box field
                VStack(alignment: .leading, spacing: 6) {
                    Text("Routine name")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                    TextField("Routine name", text: $name)
                        .font(GSFont.heading(17, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface)
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                }

                // Optional description — not in canvas, kept for parity with the
                // existing save flow; styled minimal/secondary.
                TextField("Description (optional)", text: $description, axis: .vertical)
                    .lineLimit(1...4)
                    .font(GSFont.body(13, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                // Canvas: "N EXERCISES · ≈ X min" header (GSSectionHeader tracking,
                // reuses the shared duration heuristic Home/Library already use).
                HStack {
                    Text(exerciseCountLabel)
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)
                    Spacer()
                    Text("≈ \(StatMath.estimatedMinutes(exercises: items)) min")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }

                if items.isEmpty {
                    Text("No exercises yet.")
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral500)
                }

                ForEach(items) { item in
                    exerciseRow(item)
                        .dropDestination(for: String.self) { droppedIDs, _ in
                            handleDrop(droppedIDs, onto: item)
                        }
                }

                // Canvas: full-width bordered "+ Add Exercise" CTA
                Button {
                    pickerSearchText = ""
                    showExercisePicker = true
                } label: {
                    Text("+ Add Exercise")
                        .font(GSFont.bodyMedium(14, relativeTo: .body))
                        .foregroundStyle(theme.text)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                        .gsSpotlightTarget(.builder)
                }
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))

                // Open-publishing round (20260728000008, user decision
                // 2026-07-24): the publish toggle is for EVERYONE now — any
                // owner may publish public (searchable in Discover; RLS
                // matches). The FEATURED spotlight + scoring/sort pickers
                // remain curator-only (is_featured is RLS-gated to curators).
                // This also subsumes the old demoted-curator escape-hatch
                // branch: the toggle is simply always available.
                publishToggleRow

                if appState.currentProfile?.isCurator == true, publishAsFeatured {
                    featuredToggleRow
                    publishFieldsSection
                }

                if let errorText {
                    Text(errorText)
                        .font(GSFont.body(13, relativeTo: .caption))
                        .foregroundStyle(.red)
                }
            }
            .padding(16)
        }
        .background(theme.bg)
        // Used both as a sheet (RoutinesListView's "New Routine") and as a
        // pushed destination (a routine's "Edit routine" NavigationLink). The
        // dock-hiding preference is a no-op in the sheet case (sheets already
        // fully cover the dock and preferences don't cross the sheet
        // boundary) and necessary in the push case — see GSComponents.swift's
        // GSHidesDock.
        .gsHidesDock()
        .gsSpotlight(.builder)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            // Canvas: "×" dismiss (replaces EditButton — reordering/removal are
            // always-on now, no separate edit mode needed).
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
            ToolbarItem(placement: .principal) {
                Text(editing == nil ? "New Routine" : "Edit Routine")
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Save") { Task { await save() } }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .font(GSFont.bold(15, relativeTo: .body))
                    .tint(theme.accent)
            }
        }
        .sheet(isPresented: $showExercisePicker) {
            NavigationStack { exercisePicker }
        }
        .task { await load() }
    }

    private var exerciseCountLabel: String {
        "\(items.count) EXERCISE\(items.count == 1 ? "" : "S")"
    }

    // Canvas: bordered row, label + caption on the left, GSToggle on the
    // right — same shape as NotificationPreferencesView.toggleRow, extended
    // with a second caption line per the brief ("Visible to every Gym Sync
    // user").
    private var publishToggleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Publish to Discover")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text("Anyone can find, star, and attempt this routine")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(isOn: $publishAsFeatured, label: "Publish to Discover")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    /// Curator-only: the Library spotlight flag (`is_featured`).
    private var featuredToggleRow: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Feature in Library spotlight")
                    .font(GSFont.bodyMedium(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                Text("Curator-managed — shows on the Featured shelf")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
            }
            Spacer(minLength: 8)
            GSToggle(isOn: $featureOnSpotlight, label: "Feature in Library spotlight")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .frame(minHeight: 44)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Publish fields (Phase L Task 4)
    //
    // Minimal UI per the brief: a default-sort segmented row (reusing
    // `DiscoverWorkoutDetailView.sortSegmentedControl`'s flat-rectangle/1px-
    // divider shape, `Features/Library/DiscoverWorkoutDetailView.swift:
    // 451-482`, reimplemented locally since that one is `private` to its own
    // file and this row needs a "None" 5th option that screen doesn't offer),
    // a scoring-metrics multi-select (reusing `CreateGroupView.
    // selectionCheckbox`'s filled-square-checkmark row idiom,
    // `Features/Social/CreateGroupView.swift:229-241`), and a top-set
    // exercise `Menu`+`Picker` (reusing `ScheduleSessionView.whatSection`'s
    // bordered icon-row `Menu { Picker }` shape, `Features/Sessions/
    // ScheduleSessionView.swift:358-384`) shown only when "Top Set" is
    // selected among the scoring metrics.
    private var publishFieldsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Default sort")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                defaultSortControl
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Scoring metrics")
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                scoringMetricsControl
            }

            if scoringMetrics.contains(.topSet) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top-set exercise")
                        .font(GSFont.body(12, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                    topSetExercisePicker
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // "None" + the 4 `SortMetric` cases — a curator can leave a published
    // routine with no ranked metric at all (matches the column's own
    // nullable/no-default-value shape; `leaderboard_rank_and_passed`
    // already treats a NULL default_sort as "no rank" per Task 2's
    // migration, so "None" is a real, meaningful choice here, not a filler
    // option).
    private var defaultSortControl: some View {
        HStack(spacing: 0) {
            defaultSortOption(nil, label: "None")
            ForEach(DiscoverWorkoutDetailView.SortMetric.allCases) { metric in
                defaultSortOption(metric, label: metric.label)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.divider).frame(width: 1)
                    }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    private func defaultSortOption(_ metric: DiscoverWorkoutDetailView.SortMetric?, label: String) -> some View {
        let isSelected = defaultSort == metric
        return Button {
            defaultSort = metric
        } label: {
            Text(label)
                .font(GSFont.bodyMedium(11, relativeTo: .subheadline))
                .foregroundStyle(isSelected ? theme.bg : theme.text)
                .padding(.horizontal, 4)
                .padding(.vertical, 7)
                .frame(minHeight: 44)
                .frame(maxWidth: .infinity)
                .background(isSelected ? theme.accent : Color.clear)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // Scoring metrics deliberately excludes `.recent` — the `scoring_metrics`
    // CHECK constraint only allows a subset of `['time','volume','top_set']`
    // (`20260723000001_public_workout_repository.sql:33-34`); `.recent` is a
    // display ordering, never a scored metric (same migration's comment,
    // lines 40-42).
    private static let scoringMetricOptions =
        DiscoverWorkoutDetailView.SortMetric.allCases.filter { $0 != .recent }

    private var scoringMetricsControl: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.scoringMetricOptions.enumerated()), id: \.element.id) { index, metric in
                Button {
                    if scoringMetrics.contains(metric) {
                        scoringMetrics.remove(metric)
                        // Un-picking "Top Set" clears the exercise choice too
                        // so a stale exercise id never rides a save silently
                        // — the picker itself also disappears (see
                        // `publishFieldsSection`'s `if scoringMetrics.
                        // contains(.topSet)` gate).
                        if metric == .topSet { scoringTopSetExerciseID = nil }
                    } else {
                        scoringMetrics.insert(metric)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Text(metric.label)
                            .font(GSFont.body(13, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Spacer()
                        selectionCheckbox(isSelected: scoringMetrics.contains(metric))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if index < Self.scoringMetricOptions.count - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    // Filled checkbox-square with checkmark when selected — verbatim shape
    // from `CreateGroupView.selectionCheckbox` (that one is `private` to its
    // own file, so reimplemented locally rather than imported).
    private func selectionCheckbox(isSelected: Bool) -> some View {
        ZStack {
            Rectangle()
                .fill(isSelected ? theme.accent : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(isSelected ? theme.accent : theme.neutral400, lineWidth: 1))
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(theme.bg)
            }
        }
        .frame(width: 20, height: 20)
    }

    // Bordered `Menu { Picker }` row — `ScheduleSessionView.whatSection`'s
    // shape (icon + title/subtitle + chevron), cited above. Lists the
    // routine's OWN exercises only (`items`, de-duplicated by exercise id —
    // a routine could reference the same exercise at two different
    // positions), resolved to names via `allExercises`.
    private var topSetExercisePicker: some View {
        let options: [(id: UUID, name: String)] = items
            .reduce(into: [UUID: String]()) { acc, item in
                guard acc[item.exerciseID] == nil else { return }
                acc[item.exerciseID] = allExercises.first { $0.id == item.exerciseID }?.name ?? "Exercise"
            }
            .map { (id: $0.key, name: $0.value) }
            .sorted { $0.name < $1.name }

        return Menu {
            Picker("Top-set exercise", selection: $scoringTopSetExerciseID) {
                Text("None").tag(Optional<UUID>.none)
                ForEach(options, id: \.id) { option in
                    Text(option.name).tag(Optional(option.id))
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundStyle(theme.accent)
                    .frame(width: 18)
                Text(options.first { $0.id == scoringTopSetExerciseID }?.name ?? "None")
                    .font(GSFont.body(13, relativeTo: .body))
                    .foregroundStyle(scoringTopSetExerciseID != nil ? theme.text : theme.neutral500)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
    }

    private var pickerFilteredExercises: [Exercise] {
        pickerSearchText.isEmpty ? allExercises
            : allExercises.filter { $0.name.localizedCaseInsensitiveContains(pickerSearchText) }
    }

    // Canvas: exercise picker rows — name + muscle kicker, with the shared
    // in-content search field shape above the list (same idiom as
    // ExercisesListView / ExercisePickSheet).
    private var exercisePicker: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
                TextField("Search exercises", text: $pickerSearchText)
                    .font(GSFont.body(14, relativeTo: .body))
                    .foregroundStyle(theme.text)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(theme.surface)
            .cornerRadius(GSMetrics.radiusSm)
            .padding(16)

            exercisePickerList
        }
        .background(theme.bg)
        .navigationTitle("Add exercise")
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Cancel") { showExercisePicker = false }
                    .tint(theme.accent)
            }
        }
    }

    private var exercisePickerList: some View {
        List(pickerFilteredExercises) { ex in
            Button {
                items.append(RoutineExercise(
                    id: UUID(),
                    routineID: editing?.id ?? UUID(),
                    exerciseID: ex.id,
                    position: items.count + 1,
                    targetSets: 3,
                    targetReps: "8-12",
                    targetWeight: nil,
                    restSeconds: AppConfig.defaultRestSeconds,
                    notes: nil
                ))
                showExercisePicker = false
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(ex.name)
                        .font(GSFont.heading(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    Text(ex.primaryMuscle.capitalized)
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
                .padding(.vertical, 2)
            }
            .listRowBackground(theme.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    // Canvas: exercise card — drag handle + name + "Muscle · Equipment" kicker +
    // position tag + compact remove control, stat tile row below.
    private func exerciseRow(_ item: RoutineExercise) -> some View {
        let ex = allExercises.first { $0.id == item.exerciseID }
        return VStack(alignment: .leading, spacing: 10) {
            // Header row: drag handle + name + position tag + remove
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14))
                    .foregroundStyle(theme.neutral500)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .draggable(item.id.uuidString)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ex?.name ?? "Exercise")
                        .font(GSFont.heading(15, relativeTo: .body))
                        .foregroundStyle(theme.text)
                    if let ex {
                        Text("\(ex.primaryMuscle.capitalized) · \(ex.equipment.capitalized)")
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    }
                }

                Spacer()

                GSTag(text: "\(item.position)", style: .neutral)

                // Compact remove control — small drawn box, 44pt tap target via
                // invisible padding (matches the addendum's preferred fix for
                // small-drawn-but-44pt-tappable controls).
                Button {
                    removeItem(item.id)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(theme.neutral500)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }

            // Canvas: stat tile row — SETS / REPS / WEIGHT / REST
            HStack(spacing: 6) {
                statTile(value: Binding(
                    get: { String(item.targetSets ?? 0) },
                    set: { v in updateItem(item.id) { $0.targetSets = Int(v) } }
                ), label: "SETS", keyboard: .numberPad)

                statTile(value: Binding(
                    get: { item.targetReps ?? "" },
                    set: { v in updateItem(item.id) { $0.targetReps = v } }
                ), label: "REPS", keyboard: .default)

                statTile(value: Binding(
                    get: { item.targetWeight ?? "" },
                    set: { v in updateItem(item.id) { $0.targetWeight = v } }
                ), label: "WEIGHT", keyboard: .decimalPad)

                statTile(value: Binding(
                    get: { item.restSeconds.map(formatRest) ?? "" },
                    set: { v in updateItem(item.id) { $0.restSeconds = parseRest(v) } }
                ), label: "REST", keyboard: .numbersAndPunctuation)
            }

            structureRow(item)
        }
        .padding(12)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // MARK: - Set structures (owner 2026-08-13/14; schema 20260814000003)
    //
    // Third row on the exercise card: the structure prescription. Flat
    // furniture (form controls inside a bordered card — the builder's
    // established idiom), chips over menus so the common cases are one tap.

    @ViewBuilder
    private func structureRow(_ item: RoutineExercise) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // STRAIGHT / DROP / BURNOUT — one-tap chips.
                ForEach(["straight", "drop", "burnout"], id: \.self) { kind in
                    Button {
                        updateItem(item.id) {
                            $0.setType = kind
                            if kind == "drop" {
                                if $0.dropSteps == nil { $0.dropSteps = 2 }
                                if $0.dropPercent == nil { $0.dropPercent = 20 }
                            } else {
                                $0.dropSteps = nil
                                $0.dropPercent = nil
                            }
                        }
                    } label: {
                        Text(kind.uppercased())
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(0.5)
                            .foregroundStyle(item.setType == kind ? theme.bg : theme.neutral700)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 5)
                            .background(item.setType == kind ? theme.accent : theme.bg)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                // TO FAILURE — the final set is prescribed to failure.
                Button {
                    updateItem(item.id) { $0.targetFailure.toggle() }
                } label: {
                    Text("TO FAILURE")
                        .font(GSFont.bold(10, relativeTo: .caption2))
                        .tracking(0.5)
                        .foregroundStyle(item.targetFailure ? theme.bg : theme.neutral700)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(item.targetFailure ? theme.accent : theme.bg)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            if item.setType == "drop" {
                dropConfigRow(item)
            }

            // SUPERSET pairing (Phase B): link this exercise with the NEXT
            // one — the pair alternates A→B with no rest between, one
            // shared rest after. Pairs only (A/B), matching the design;
            // shown on every row except the last.
            if let next = itemAfter(item) {
                supersetLinkChip(item, next: next)
            }
        }
    }

    /// The exercise after this one in position order, if any.
    private func itemAfter(_ item: RoutineExercise) -> RoutineExercise? {
        guard let idx = items.firstIndex(where: { $0.id == item.id }),
              idx + 1 < items.count else { return nil }
        return items[idx + 1]
    }

    private func isLinked(_ item: RoutineExercise, next: RoutineExercise) -> Bool {
        item.supersetGroup != nil && item.supersetGroup == next.supersetGroup
    }

    @ViewBuilder
    private func supersetLinkChip(_ item: RoutineExercise, next: RoutineExercise) -> some View {
        let linked = isLinked(item, next: next)
        Button {
            toggleSupersetLink(item, next: next)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: linked ? "link" : "link.badge.plus")
                    .font(.system(size: 10, weight: .bold))
                Text(linked ? "SUPERSET WITH NEXT" : "LINK SUPERSET ↓")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(0.5)
            }
            .foregroundStyle(linked ? theme.bg : theme.neutral700)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(linked ? theme.accent : theme.bg)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    /// Link/unlink item and its next neighbor as a superset pair. Pairs
    /// only: linking dissolves any pair either exercise already belonged
    /// to (a lifter re-deciding, not an error).
    private func toggleSupersetLink(_ item: RoutineExercise, next: RoutineExercise) {
        if isLinked(item, next: next) {
            updateItem(item.id) { $0.supersetGroup = nil }
            updateItem(next.id) { $0.supersetGroup = nil }
        } else {
            // Dissolve any existing pair membership first.
            for member in items where member.supersetGroup != nil
                && (member.supersetGroup == item.supersetGroup || member.supersetGroup == next.supersetGroup) {
                updateItem(member.id) { $0.supersetGroup = nil }
            }
            let group = item.position
            updateItem(item.id) { $0.supersetGroup = group }
            updateItem(next.id) { $0.supersetGroup = group }
        }
    }

    /// "DROP 2 × 20%" — steppers kept as compact −/+ pairs, not a form.
    private func dropConfigRow(_ item: RoutineExercise) -> some View {
        HStack(spacing: 10) {
            Text("DROPS")
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            stepperPair(
                value: "\(item.dropSteps ?? 2)",
                minus: { updateItem(item.id) { $0.dropSteps = max(1, ($0.dropSteps ?? 2) - 1) } },
                plus: { updateItem(item.id) { $0.dropSteps = min(3, ($0.dropSteps ?? 2) + 1) } }
            )
            Text("CUT")
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            stepperPair(
                value: "\(NSDecimalNumber(decimal: item.dropPercent ?? 20).intValue)%",
                minus: { updateItem(item.id) { $0.dropPercent = max(10, ($0.dropPercent ?? 20) - 5) } },
                plus: { updateItem(item.id) { $0.dropPercent = min(50, ($0.dropPercent ?? 20) + 5) } }
            )
            Spacer()
            Text("final set: drop \(item.dropSteps ?? 2)×\(NSDecimalNumber(decimal: item.dropPercent ?? 20).intValue)%")
                .font(GSFont.body(10, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    private func stepperPair(value: String, minus: @escaping () -> Void,
                             plus: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Button(action: minus) {
                Image(systemName: "minus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 22, height: 22)
                    .background(theme.bg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            Text(value)
                .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                .foregroundStyle(theme.text)
                .frame(minWidth: 30)
            Button(action: plus) {
                Image(systemName: "plus")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.neutral700)
                    .frame(width: 22, height: 22)
                    .background(theme.bg)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
        }
    }

    // Canvas: stat tile — muted uppercase kicker + bold value, 1px divider border
    private func statTile(value: Binding<String>, label: String,
                          keyboard: UIKeyboardType) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.5)
                .foregroundStyle(theme.neutral500)
            TextField(label, text: value)
                .keyboardType(keyboard)
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    private func updateItem(_ id: UUID, mutate: (inout RoutineExercise) -> Void) {
        guard let idx = items.firstIndex(where: { $0.id == id }) else { return }
        mutate(&items[idx])
    }

    private func removeItem(_ id: UUID) {
        withAnimation {
            items.removeAll { $0.id == id }
        }
        reindex()
    }

    /// Drag-and-drop reorder target — drops `droppedIDs.first` (the dragged
    /// row's UUID string) onto `target`'s position. Replaces the List
    /// edit-mode-gated `.onMove` so reordering works without an Edit toggle
    /// (canvas header has no Edit affordance, only ×/Save).
    private func handleDrop(_ droppedIDs: [String], onto target: RoutineExercise) -> Bool {
        guard let droppedIDString = droppedIDs.first,
              let droppedID = UUID(uuidString: droppedIDString),
              droppedID != target.id,
              let fromIndex = items.firstIndex(where: { $0.id == droppedID }),
              let toIndex = items.firstIndex(where: { $0.id == target.id })
        else { return false }
        withAnimation {
            items.move(fromOffsets: IndexSet(integer: fromIndex),
                       toOffset: toIndex > fromIndex ? toIndex + 1 : toIndex)
        }
        reindex()
        return true
    }

    private func reindex() {
        for i in items.indices { items[i].position = i + 1 }
    }

    // "2:00" — matches the mm:ss treatment used for rest elsewhere (e.g.
    // WorkoutSessionView's target-line rest suffix).
    private func formatRest(_ seconds: Int) -> String {
        let m = seconds / 60
        let s = seconds % 60
        return String(format: "%d:%02d", m, s)
    }

    /// Parses "m:ss" back to seconds; falls back to a plain seconds integer
    /// if no colon is present (keeps the field forgiving to type into).
    private func parseRest(_ text: String) -> Int? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":")
            guard parts.count == 2,
                  let m = Int(parts[0]),
                  let s = Int(parts[1])
            else { return nil }
            return m * 60 + s
        }
        return Int(trimmed)
    }

    @MainActor
    private func load() async {
        loading = true
        defer { loading = false }
        do {
            allExercises = try await ExerciseRepository.fetchAll()
            if let editing {
                name = editing.name
                description = editing.description ?? ""
                // CRITICAL: must be seeded here, unconditionally, from
                // `editing` itself — not left at its `false` default. Without
                // this, a curator editing an already-published routine and
                // hitting Save would silently unpublish it (save writes
                // `visibility` from this toggle's current value).
                publishAsFeatured = editing.visibility == "public"
                if let (_, exs) = try await RoutineRepository.fetch(id: editing.id) {
                    items = exs
                }
                // Phase L Task 4: seed the publish-fields UI from the
                // routine's CURRENT values — same "read before overwriting"
                // discipline as `publishAsFeatured` above. Curator-gated (the
                // section that reads these is itself only ever shown to a
                // curator) and only fetched for an existing routine — a
                // brand-new one has no row to read yet, so the pickers start
                // at their empty/unset @State defaults.
                if appState.currentProfile?.isCurator == true,
                   let fields = try await RoutineRepository.publishFields(routineID: editing.id) {
                    featureOnSpotlight = fields.isFeatured ?? false
                    defaultSort = fields.defaultSort.flatMap { DiscoverWorkoutDetailView.SortMetric(rawValue: $0) }
                    scoringMetrics = Set((fields.scoringMetrics ?? [])
                        .compactMap { DiscoverWorkoutDetailView.SortMetric(rawValue: $0) })
                    scoringTopSetExerciseID = fields.scoringTopSetExerciseID
                }
            }
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func save() async {
        guard let ownerID = appState.currentProfile?.id else { return }
        let routineID = editing?.id ?? UUID()
        let now = Date()
        let routine = Routine(
            id: routineID,
            ownerID: ownerID,
            name: name.trimmingCharacters(in: .whitespaces),
            description: description.isEmpty ? nil : description,
            visibility: publishAsFeatured ? "public" : "private",
            createdAt: editing?.createdAt ?? now,
            updatedAt: now
        )
        var normalizedItems = items.enumerated().map { idx, item in
            RoutineExercise(
                id: item.id,
                routineID: routineID,
                exerciseID: item.exerciseID,
                position: idx + 1,
                targetSets: item.targetSets,
                targetReps: item.targetReps,
                targetWeight: item.targetWeight,
                restSeconds: item.restSeconds,
                notes: item.notes,
                // Set structures (20260814000003) — carried through so an
                // edit round-trip never wipes a structure prescription.
                setType: item.setType,
                supersetGroup: item.supersetGroup,
                dropSteps: item.dropSteps,
                dropPercent: item.dropPercent,
                targetFailure: item.targetFailure
            )
        }
        // Superset normalization: a pair is only real while its members
        // are ADJACENT — drag-reorders and removals dissolve it (silently
        // keeping a split pair would alternate across the whole gap).
        // Surviving pairs renumber to the first member's new position.
        for idx in normalizedItems.indices {
            guard let group = normalizedItems[idx].supersetGroup else { continue }
            let prevMatches = idx > 0 && normalizedItems[idx - 1].supersetGroup == group
            let nextMatches = idx + 1 < normalizedItems.count
                && normalizedItems[idx + 1].supersetGroup == group
            if !prevMatches && !nextMatches {
                normalizedItems[idx].supersetGroup = nil
            }
        }
        for idx in normalizedItems.indices {
            guard normalizedItems[idx].supersetGroup != nil, idx + 1 < normalizedItems.count,
                  normalizedItems[idx + 1].supersetGroup == normalizedItems[idx].supersetGroup
            else { continue }
            let renumbered = normalizedItems[idx].position
            normalizedItems[idx].supersetGroup = renumbered
            normalizedItems[idx + 1].supersetGroup = renumbered
        }
        do {
            try await RoutineRepository.save(routine, exercises: normalizedItems)

            // Phase L Task 4: targeted UPDATE of the publish-only columns —
            // ONLY when publishing. Deliberately does NOT ride `save()`'s
            // upsert above (see `RoutineRepository.updatePublishFields`'s doc
            // comment for the full "unpublish regression" reasoning) and is
            // deliberately skipped entirely on unpublish: Discover only ever
            // reads `visibility='public'` rows (`PublicWorkoutRepository.
            // publicWorkouts()`), so leaving a private routine's stale
            // default_sort/scoring_metrics/scoring_top_set_exercise_id in
            // place is inert — and skipping the write avoids touching a
            // curator-only column set on a save a non-publishing user (or a
            // curator saving a still-private draft) may trigger.
            if publishAsFeatured {
                // Defensive: a previously-picked top-set exercise may no
                // longer be in `items` (removed from the routine since the
                // last publish) — never write a dangling exercise id.
                let validTopSetID = scoringTopSetExerciseID.flatMap { id in
                    normalizedItems.contains { $0.exerciseID == id } ? id : nil
                }
                // Guard: `.topSet` selected with no (valid) exercise picked is
                // logically incomplete — silently drop it from the metrics
                // being written rather than publish a NULL-id scoring metric.
                let effectiveMetrics = validTopSetID == nil ? scoringMetrics.subtracting([.topSet]) : scoringMetrics
                try await RoutineRepository.updatePublishFields(
                    routineID: routineID,
                    defaultSort: defaultSort?.rawValue,
                    scoringMetrics: effectiveMetrics.isEmpty ? nil : effectiveMetrics.map(\.rawValue),
                    scoringTopSetExerciseID: effectiveMetrics.contains(.topSet) ? validTopSetID : nil,
                    // nil for non-curators: never touch the RLS-gated column.
                    isFeatured: appState.currentProfile?.isCurator == true ? featureOnSpotlight : nil
                )
            }

            onSaved(routine)
            dismiss()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
