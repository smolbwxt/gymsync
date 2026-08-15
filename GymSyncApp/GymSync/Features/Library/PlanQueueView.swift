import SwiftUI

// MARK: - PlanQueueSection (THE PLAN — the macrocycle queue)
//
// Generator wave: training_plan_entries rendered as an ordered block
// queue ("CBum 8-week, then a 1RM test block") under the Programs tab's
// program section. Queue members are program_templates ROWS — today that
// means your own Coach-generated blocks (every CREATE persists one via
// the data bridge); curated/creator rows join as the shelf grows.
//
// Self-contained by design: owns its own fetches and renders NOTHING
// until it has something real to show, so a plan/template fetch failure
// (or an empty state) never disturbs the campaigns content around it.
// Reorder rides context menus (move up/down) — a handful of blocks, not
// a drag surface.
struct PlanQueueSection: View {
    @Environment(\.gsTheme) private var theme
    @Environment(AppState.self) private var appState

    @State private var entries: [TrainingPlanEntry] = []
    @State private var templatesByID: [UUID: ProgramTemplateRow] = [:]
    @State private var myTemplates: [ProgramTemplateRow] = []
    @State private var busy = false
    @State private var errorText: String?

    var body: some View {
        Group {
            if !entries.isEmpty || !myTemplates.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    GSSectionHeader("The Plan")
                        .padding(.top, 16)
                        .padding(.bottom, 10)

                    if entries.isEmpty {
                        Text("Queue your blocks back to back — finish one, roll into the next.")
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(theme.neutral500)
                            .padding(.bottom, 10)
                    } else {
                        queueCard
                            .padding(.bottom, 10)
                    }

                    addMenu

                    if let errorText {
                        Text(errorText)
                            .font(GSFont.body(12, relativeTo: .caption))
                            .foregroundStyle(.red)
                            .padding(.top, 6)
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .task { await load() }
    }

    // MARK: - Queue card (one card, ordered rows — the hub's idiom)

    private var queueCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                queueRow(entry, index: index)
                if index < entries.count - 1 {
                    GSDivider().padding(.horizontal, 12)
                }
            }
        }
        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
    }

    private func queueRow(_ entry: TrainingPlanEntry, index: Int) -> some View {
        HStack(spacing: 10) {
            Text("\(index + 1)")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral500)
                .monospacedDigit()
                .frame(width: 18, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(templatesByID[entry.templateID]?.name ?? "Block")
                    .font(GSFont.heading(14, relativeTo: .subheadline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                if let template = templatesByID[entry.templateID] {
                    Text("\(template.durationWeeks) wk · \(template.sessionsPerWeek)×/week")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral500)
                }
            }
            Spacer()
            if entry.status != "queued" {
                GSTag(text: entry.status == "active" ? "Active" : "Done",
                      style: entry.status == "active" ? .accent : .neutral)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 52)
        .contentShape(Rectangle())
        .contextMenu {
            if index > 0 {
                Button { Task { await move(entry, to: index - 1) } } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
            }
            if index < entries.count - 1 {
                Button { Task { await move(entry, to: index + 1) } } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
            }
            Button(role: .destructive) {
                Task { await remove(entry) }
            } label: {
                Label("Remove from plan", systemImage: "trash")
            }
        }
        .disabled(busy)
    }

    /// "Add a block ▾" — your generated Coach blocks. Repeats are allowed
    /// on purpose (running the same 8-week block twice is a real plan).
    private var addMenu: some View {
        Menu {
            ForEach(myTemplates) { template in
                Button {
                    Task { await add(template) }
                } label: {
                    Text("\(template.name) · \(template.durationWeeks) wk")
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(theme.accent)
                Text("Add a block")
                    .font(GSFont.bold(14, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }
            .padding(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .disabled(busy || myTemplates.isEmpty)
        .opacity(myTemplates.isEmpty ? 0.6 : 1)
    }

    // MARK: - Data

    @MainActor
    private func load() async {
        // Shelf metadata is one globally-readable fetch and names every
        // queued row (own, house, or purchased); mine() derives from it.
        let shelf = (try? await ProgramTemplateRepository.shelf()) ?? []
        templatesByID = Dictionary(uniqueKeysWithValues: shelf.map { ($0.id, $0) })
        let me = appState.currentProfile?.id
        myTemplates = shelf.filter { $0.ownerID != nil && $0.ownerID == me }
        entries = (try? await TrainingPlanRepository.queue()) ?? []
    }

    @MainActor
    private func add(_ template: ProgramTemplateRow) async {
        busy = true
        defer { busy = false }
        do {
            _ = try await TrainingPlanRepository.add(templateID: template.id)
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func remove(_ entry: TrainingPlanEntry) async {
        busy = true
        defer { busy = false }
        do {
            try await TrainingPlanRepository.remove(entryID: entry.id)
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }

    @MainActor
    private func move(_ entry: TrainingPlanEntry, to newIndex: Int) async {
        guard let current = entries.firstIndex(where: { $0.id == entry.id }),
              entries.indices.contains(newIndex) else { return }
        var ids = entries.map(\.id)
        ids.swapAt(current, newIndex)
        busy = true
        defer { busy = false }
        do {
            try await TrainingPlanRepository.reorder(orderedIDs: ids)
            errorText = nil
            await load()
        } catch { errorText = ErrorMapping.map(error).errorDescription }
    }
}
