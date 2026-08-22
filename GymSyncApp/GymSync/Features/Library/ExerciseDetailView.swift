import SwiftUI

// Canvas: Bench Press detail — small fixed "Exercise" nav title + "+" icon,
// "COMPOUND"-style category kicker + large name heading in the scrollable
// body, surface demo placeholder, "Muscles worked" section (accent tag for
// primary, neutral tags for secondary), equipment + "your best" stat cards
// side by side, "Est. 1RM" trend card, Add to Routine CTA at bottom.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(AppState.self) private var appState
    @Environment(\.gsTheme) private var theme

    @State private var bestPR: PersonalRecord?
    @State private var trendLogs: [SetLog] = []

    /// Est. 1RM per set, restricted to the trailing 12-week window,
    /// chronological. Units sweep: points are converted to the user's unit
    /// here so the delta badge derived from them is already unit-correct.
    private var trendChartData: [(Date, Double)] {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -84, to: .now) else { return [] }
        let unit = ThemeStore.shared.weightUnit
        return trendLogs
            .filter { $0.loggedAt >= cutoff }
            .compactMap { log -> (Date, Double)? in
                // completedReps: failed sets chart at n − 1 (true RIR 0);
                // failed singles contribute nothing.
                guard let w = log.weight, let reps = log.completedReps else { return nil }
                let oneRM = StatMath.estimatedOneRepMax(weight: w, reps: reps)
                return (log.loggedAt, Units.fromPounds(NSDecimalNumber(decimal: oneRM).doubleValue, to: unit))
            }
            .sorted { $0.0 < $1.0 }
    }

    /// "▲ 18 lbs" / "▲ 8 kg" — first-to-last Est. 1RM delta within the trend
    /// window (chart points are already in the user's unit, so no second
    /// conversion here).
    private var trendDeltaText: String? {
        guard trendChartData.count >= 2,
              let first = trendChartData.first?.1,
              let last = trendChartData.last?.1
        else { return nil }
        let delta = Int((last - first).rounded())
        guard delta != 0 else { return nil }
        return "\(delta >= 0 ? "▲" : "▼") \(abs(delta)) \(ThemeStore.shared.weightUnit.label)"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // Canvas: category kicker + large name heading (moved out of the
                // native nav title so the nav bar can stay a small fixed label).
                VStack(alignment: .leading, spacing: 4) {
                    Text(exercise.category.uppercased())
                        .font(GSFont.bodyMedium(11, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.accent)
                    Text(exercise.name)
                        .font(GSFont.heading(28, relativeTo: .title))
                        .foregroundStyle(theme.text)
                }

                // Demo media, in preference order: a curated YouTube form
                // video (Phase M — official iframe embed only; see
                // GSYouTubeEmbed's compliance header), else the legacy
                // two-frame GSDemoView (whose url is currently nil on every
                // seeded row, so it renders its placeholder).
                if let videoID = exercise.demoYoutubeID {
                    GSYouTubeEmbed(videoID: videoID)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                } else {
                    GSDemoView(url: exercise.demoVideoURL)
                        .frame(maxWidth: .infinity)
                        .frame(height: 220)
                        .clipped()
                        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
                }

                // ABOUT (brand pass 2026-08-22): the authored paragraph,
                // when a row carries one.
                if let details = exercise.details, !details.isEmpty {
                    Text(details)
                        .font(GSFont.body(14, relativeTo: .body))
                        .foregroundStyle(theme.neutral700)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Canvas: Muscles worked section header + accent/neutral tags
                VStack(alignment: .leading, spacing: 8) {
                    Text("MUSCLES WORKED")
                        .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                        .tracking(1.2)
                        .foregroundStyle(theme.neutral700)

                    FlowLayout(spacing: 6) {
                        GSTag(text: "\(exercise.primaryMuscle.replacingOccurrences(of: "_", with: " ").capitalized) · primary",
                              style: .accent)
                        ForEach(exercise.secondaryMuscles, id: \.self) { m in
                            GSTag(text: m.replacingOccurrences(of: "_", with: " ").localizedCapitalized, style: .neutral)
                        }
                    }
                }

                // HOW TO — the free-exercise-db import's step-by-step form
                // cues (20260813000001); hidden entirely for rows without
                // them (the curated seeds, until backfilled).
                if !exercise.instructions.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("HOW TO")
                            .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                            .tracking(1.2)
                            .foregroundStyle(theme.neutral700)
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(exercise.instructions.enumerated()), id: \.offset) { index, step in
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("\(index + 1)")
                                        .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                                        .foregroundStyle(theme.neutral500)
                                        .frame(width: 18, alignment: .trailing)
                                    Text(step)
                                        .font(GSFont.body(13.5, relativeTo: .subheadline))
                                        .foregroundStyle(theme.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .gs3DCard(cornerRadius: GSMetrics.radiusMd)
                    }
                }

                // Canvas: Equipment + "Your best" side-by-side stat tiles
                HStack(spacing: 8) {
                    statTile(kicker: "Equipment", value: exercise.equipment.capitalized)
                    statTile(kicker: "Your Best", value: bestPR.map(formatBest) ?? "—")
                }

                // Canvas: "Est. 1RM · 12 weeks" trend card + "▲ 18 lbs" delta badge
                GSMiniTrendCard(
                    kicker: "Est. 1RM · 12 weeks",
                    data: trendChartData,
                    deltaText: trendDeltaText
                )

                Spacer(minLength: 32)
            }
            .padding(16)
        }
        .background(theme.bg)
        // Pushed from ExercisesListView — see GSComponents.swift's GSHidesDock.
        .gsHidesDock()
        .navigationTitle("Exercise")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(theme.surface, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // Canvas nav "+" icon — no add-to-routine route exists from this
                // screen yet (same gap the sticky bottom CTA below already defers
                // on), so this is a visual affordance only for now.
                Button {
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(theme.text)
                        .frame(minWidth: 44, minHeight: 44)
                        .contentShape(Rectangle())
                }
            }
        }
        // Canvas: sticky "Add to Routine" CTA at bottom — deferred (no route in current app)
        .task { await load() }
    }

    // Canvas: small bordered stat tile — kicker + bold value
    private func statTile(kicker: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(kicker.uppercased())
                .font(GSFont.bodyMedium(9, relativeTo: .caption2))
                .tracking(0.8)
                .foregroundStyle(theme.neutral700)
            Text(value)
                .font(GSFont.heading(15, relativeTo: .body))
                .foregroundStyle(theme.text)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface)
        .overlay(RoundedRectangle(cornerRadius: GSMetrics.radiusSm).strokeBorder(theme.divider, lineWidth: 1))
    }

    // "190 × 5" — weight-first, matches the app-wide PR/set-display
    // convention. Units sweep: stored-lbs converted to the display unit,
    // exact (a PR is what was actually lifted — never snapped).
    private func formatBest(_ pr: PersonalRecord) -> String {
        // Weight 0 = a bodyweight rep record (owner item 6) — the rep
        // count IS the record.
        guard pr.weight > 0 else { return "\(pr.reps) reps" }
        let weightText = Units.format(pounds: pr.weight, unit: ThemeStore.shared.weightUnit,
                                      rounded: false, includeUnit: false)
        return "\(weightText) × \(pr.reps)"
    }

    @MainActor
    private func load() async {
        guard let userID = appState.currentProfile?.id else { return }
        // Best-effort — a failed fetch just leaves the tile at "—" / the chart
        // at "Not enough data yet." rather than blocking the rest of the screen.
        let recents = try? await PersonalRecordRepository.recent(userID: userID, limit: 500)
        bestPR = recents?.first { $0.exerciseID == exercise.id }
        let logs = try? await SessionRepository.exerciseHistory(userID: userID, exerciseID: exercise.id, limit: 200)
        trendLogs = logs ?? []
    }
}

// MARK: - FlowLayout helper (wrapping HStack)
// Zero-dep row-wrap for tag clouds (used only in ExerciseDetailView).
private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
