import SwiftUI

/// The four states the Home stat-tile row can render (canvas frame 41):
/// LOADED (current/original behavior), LOADING·SKELETON,
/// FIRST-SESSION·ZERO, and OFFLINE·STALE-CACHE.
///
/// Extracted from `HomeView`'s previous single always-loaded `statTileRow`
/// computed property (HomeView.swift:229-247, MARK: "Stat Tile Row (Task 5 —
/// canvas content)") so `CatalogHostView` can force each state onto the SAME
/// view Home renders, instead of a hand-built reproduction (Phase U Task 1 —
/// replaces the old `stattile-loading/error/empty` catalog reproductions in
/// `CatalogHostView.content_statTile`).
enum StatTilesRowState: Equatable {
    case loading
    case loaded(workoutsThisWeek: Int, lifetimeLbs: Decimal, prsThisMonth: Int)
    case firstSessionZero
    case offlineStale(StatTilesSnapshot)
}

struct StatTilesRow: View {
    let state: StatTilesRowState
    let onStart: () -> Void

    @Environment(\.gsTheme) private var theme

    init(state: StatTilesRowState, onStart: @escaping () -> Void = {}) {
        self.state = state
        self.onStart = onStart
    }

    var body: some View {
        Group {
            switch state {
            case .loading:
                skeletonRow
            case .loaded(let workoutsThisWeek, let lifetimeLbs, let prsThisMonth):
                loadedRow(workoutsThisWeek: workoutsThisWeek, lifetimeLbs: lifetimeLbs, prsThisMonth: prsThisMonth)
            case .firstSessionZero:
                zeroCard
            case .offlineStale(let snapshot):
                offlineStaleColumn(snapshot)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    // MARK: - LOADED
    //
    // Byte-identical to the original `HomeView.statTileRow` body
    // (HomeView.swift:230-244) — just parameterized on values passed in
    // instead of reading `@State` directly.

    private func loadedRow(workoutsThisWeek: Int, lifetimeLbs: Decimal, prsThisMonth: Int) -> some View {
        HStack(spacing: 8) {
            GSStatTile(value: "\(workoutsThisWeek)", label: "Workouts this week")
            GSStatTile(value: StatMath.compactNumber(Units.fromPounds(lifetimeLbs, to: ThemeStore.shared.weightUnit)),
                       label: "Lifetime \(ThemeStore.shared.weightUnit.label)")
            GSStatTile(
                value: "\(prsThisMonth)",
                label: "PRs this month",
                valueColor: theme.accent700
            )
        }
    }

    // MARK: - LOADING·SKELETON
    //
    // Same 3-tile layout with placeholder content, `.redacted(reason:
    // .placeholder)` — matches the catalog's prior reproduction convention
    // (the old `CatalogHostView.content_statTile(.loading)`, which noted
    // GSStatTile needs no change at all for this), now driving the real row.

    private var skeletonRow: some View {
        HStack(spacing: 8) {
            GSStatTile(value: "0", label: "Workouts this week")
            GSStatTile(value: "0", label: "Lifetime \(ThemeStore.shared.weightUnit.label)")
            GSStatTile(value: "0", label: "PRs this month")
        }
        .redacted(reason: .placeholder)
    }

    // MARK: - FIRST-SESSION·ZERO
    //
    // Dashed-border card that REPLACES the tile row entirely — copy verbatim
    // from canvas frame 41 ("No lifts logged yet" / "Your first workout
    // unlocks these stats."). Dash style (`[4, 3]`) matches the app's one
    // existing dashed-stroke precedent (PTTDockRow's unavailable-mic ring,
    // GSComponents.swift:1328) rather than inventing new values.
    //
    // "Start" calls `onStart` — the caller (HomeView) passes the SAME
    // closure body as its existing "Start Solo Workout" CTA
    // (HomeView.swift's `startSoloWorkoutButton`, ~line 146-157:
    // `routinePickerPreselected = nil; showRoutinePicker = true`). No new
    // session-start path is introduced here.

    private var zeroCard: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("No lifts logged yet")
                    .font(GSFont.heading(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                Text("Your first workout unlocks these stats.")
                    .font(GSFont.body(13, relativeTo: .subheadline))
                    .foregroundStyle(theme.neutral500)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Start", action: onStart)
                .buttonStyle(GSPrimaryButtonStyle(fontSize: 14, verticalPadding: 10))
                .frame(minHeight: 44)
        }
        .padding(16)
        .overlay(
            RoundedRectangle(cornerRadius: GSMetrics.radiusSm)
                .strokeBorder(theme.neutral400, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
    }

    // MARK: - OFFLINE·STALE-CACHE
    //
    // Renders `snapshot`'s cached values with the frame's "·" marker
    // (U+00B7 — same middle-dot character already used throughout the app,
    // e.g. GSComponents.swift:1345 "Tap to talk · hold to talk live"); a
    // field that's never been cached renders as the frame's em-dash "—"
    // (U+2014 — same character ExerciseDetailView.swift:85 and
    // GroupSessionLiveView.swift already use for "no value" tiles). Caption
    // copy is verbatim from frame 41.

    private func offlineStaleColumn(_ snapshot: StatTilesSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                GSStatTile(
                    value: staleValue(snapshot.workoutsThisWeek.map { "\($0)" }),
                    label: "Workouts this week"
                )
                GSStatTile(
                    value: staleValue(snapshot.lifetimeLbs.map { StatMath.compactNumber(Units.fromPounds($0, to: ThemeStore.shared.weightUnit)) }),
                    label: "Lifetime \(ThemeStore.shared.weightUnit.label)"
                )
                GSStatTile(
                    value: staleValue(snapshot.prsThisMonth.map { "\($0)" }),
                    label: "PRs this month",
                    valueColor: theme.accent700
                )
            }
            Text("· = last synced value · dashes couldn't load")
                .font(GSFont.body(11, relativeTo: .caption2))
                .foregroundStyle(theme.neutral500)
        }
    }

    /// Appends the frame's "·" marker to a cached value, or "—" when the
    /// field was never successfully cached.
    private func staleValue(_ cached: String?) -> String {
        guard let cached else { return "—" }
        return "\(cached)·"
    }
}
