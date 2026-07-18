import SwiftUI

// Canvas frame 17 — "Workout Complete" solo recap.
//
// Extracted from `WorkoutSessionView`'s previous inline `recapHeader` /
// `recapBody` computed properties (Phase U Task 4 — solo recap alignment)
// so `CatalogHostView` can construct this screen directly with fixture
// values, mirroring the `StatTilesRow` extraction precedent
// (Features/Home/StatTilesRow.swift): a hand-built catalog reproduction
// drifts from the real view over time, so the real view is parameterized on
// plain display-ready values instead and the catalog forces it into a
// specific shape.
//
// Layout/copy below is byte-identical to the prior inline implementation
// (accent hero: kicker / duration / subline / TOTAL LBS·SETS·PR row; New
// Personal Record card; "By exercise" breakdown; full-width Done bar), PLUS
// the "Synced to Apple Health" card (Phase H — dormancy ends here). The
// design doc (docs/superpowers/specs/2026-07-16-design-frames-design.md,
// "Recap adjudication") had called for that row to render ABSENT until
// Phase H shipped; canvas frame 17 (docs/design/Gym Sync App Designs.dc.html,
// "SOLO RECAP") always included it — icon + "Synced to Apple Health" title +
// "NN min · NNN kcal" meta line, rendered only when the export actually
// succeeded (`healthSummary == nil` otherwise; see
// `WorkoutSessionView.recapHealthSummary`).
struct SoloRecapView: View {
    /// One row of the "By exercise" breakdown: name, set count, top set, PR flag.
    /// Moved here (was a private nested type on `WorkoutSessionView`) since the
    /// catalog needs to construct fixture rows from outside that view.
    struct ExerciseSummary: Identifiable {
        let id: UUID
        let name: String
        let setCount: Int
        let topWeight: Decimal?
        let topReps: Int?
        let isPR: Bool

        var metaText: String {
            if let topWeight, let topReps {
                return "\(setCount) sets · top \(topWeight) × \(topReps)"
            }
            return "\(setCount) sets"
        }
    }

    /// Display-ready fields for the "New personal record" card — the caller
    /// resolves the heaviest session PR to an exercise name before
    /// constructing this (mirrors the `allExercises.first { ... }?.name`
    /// lookup the old inline `prCelebrationCard(_:)` did against a raw
    /// `PersonalRecord`).
    struct HeaviestPR {
        let exerciseName: String
        let weight: Decimal
        let reps: Int
        let previousBest: Decimal
    }

    /// Display-ready fields for the "Synced to Apple Health" card (Phase H).
    /// The caller (`WorkoutSessionView.recapHealthSummary`) pre-formats both
    /// strings — mirrors the "plain display-ready values" convention this
    /// type already uses for `durationText`/`totalLbsText`/etc. — and
    /// resolves to `nil` when the export didn't actually succeed
    /// (`healthSynced == false`), so this card never claims a sync that
    /// didn't happen.
    struct HealthSummary {
        let minutesText: String   // e.g. "42 min"
        let caloriesText: String  // e.g. "318 kcal"
    }

    let kicker: String
    let durationText: String
    let subline: String
    let totalLbsText: String
    let setCount: Int
    let prCount: Int
    let heaviestPR: HeaviestPR?
    let exerciseSummaries: [ExerciseSummary]
    let healthSummary: HealthSummary?
    let shareSummary: String
    let onDone: () -> Void

    @Environment(\.gsTheme) private var theme

    init(
        kicker: String,
        durationText: String,
        subline: String,
        totalLbsText: String,
        setCount: Int,
        prCount: Int,
        heaviestPR: HeaviestPR?,
        exerciseSummaries: [ExerciseSummary],
        healthSummary: HealthSummary? = nil,
        shareSummary: String,
        onDone: @escaping () -> Void = {}
    ) {
        self.kicker = kicker
        self.durationText = durationText
        self.subline = subline
        self.totalLbsText = totalLbsText
        self.setCount = setCount
        self.prCount = prCount
        self.heaviestPR = heaviestPR
        self.exerciseSummaries = exerciseSummaries
        self.healthSummary = healthSummary
        self.shareSummary = shareSummary
        self.onDone = onDone
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView {
                // spacing: 12 matches the original shared outer VStack in
                // `WorkoutSessionView.body` (pre-extraction) — `header` and
                // `content` were two top-level children of that VStack, spaced
                // by its `spacing: 12`, not adjacent siblings in their own
                // zero-spacing container.
                VStack(alignment: .leading, spacing: 12) {
                    header
                    content
                }
                .padding(.top, 14)
                // bottom padding so content isn't hidden behind the sticky Done button
                .padding(.bottom, 88)
            }
            doneFooter
        }
        .background(theme.bg)
    }

    // Canvas: recap header bar — "Workout Complete" title + share button, border-bottom divider.
    private var header: some View {
        HStack {
            Text("Workout Complete")
                .font(GSFont.bold(14, relativeTo: .subheadline))
                .foregroundStyle(theme.text)
            Spacer()
            ShareLink(item: shareSummary) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 30, height: 30)
                    .overlay(Rectangle().strokeBorder(theme.divider, lineWidth: 1))
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(theme.divider).frame(height: 2)
        }
    }

    // Canvas: recap body — accent hero, PR card, by-exercise breakdown,
    // Apple Health card (Phase H — see type doc comment above).
    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            hero

            if let heaviestPR {
                prCard(heaviestPR)
            }

            if !exerciseSummaries.isEmpty {
                breakdown
            }

            if let healthSummary {
                healthCard(healthSummary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    // Canvas: accent hero block — routine kicker, duration hero (52pt), subline, 3-cell stat row.
    private var hero: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(kicker)
                .font(GSFont.bodyMedium(10, relativeTo: .caption2))
                .tracking(1.4)
                .foregroundStyle(theme.bg.opacity(0.85))

            Text(durationText)
                .font(GSFont.heading(52, relativeTo: .largeTitle))
                .tracking(-0.4)
                .foregroundStyle(theme.bg)

            Text(subline)
                .font(GSFont.body(12, relativeTo: .caption))
                .foregroundStyle(theme.bg.opacity(0.9))

            HStack(spacing: 8) {
                heroStatCell(value: totalLbsText, label: "TOTAL LBS")
                heroStatCell(value: "\(setCount)", label: "SETS")
                heroStatCell(value: "\(prCount)", label: "PR")
            }
            .padding(.top, 14)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.accent)
    }

    private func heroStatCell(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(GSFont.bold(20, relativeTo: .title3))
                .foregroundStyle(theme.bg)
            Text(label)
                .font(GSFont.bold(9, relativeTo: .caption2))
                .tracking(1.0)
                .foregroundStyle(theme.bg.opacity(0.85))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Canvas: PR celebration card — accent100 fill, shown for the heaviest PR this session.
    private func prCard(_ pr: HeaviestPR) -> some View {
        let delta = pr.weight - pr.previousBest
        return GSCard(backgroundColor: theme.accent100) {
            VStack(alignment: .leading, spacing: 4) {
                Text("🔥 New personal record")
                    .font(GSFont.bodyMedium(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent)
                Text("\(pr.exerciseName) — \(decimalString(pr.weight)) lbs × \(pr.reps)")
                    .font(GSFont.bold(15, relativeTo: .body))
                    .foregroundStyle(theme.text)
                Text("▲ Beat previous best by \(decimalString(delta)) lbs")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.accent700)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Canvas: "By exercise" breakdown — grouped by first-logged order, 1px dividers, PR tags.
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            GSSectionHeader("By exercise")
                .padding(.bottom, 8)

            ForEach(Array(exerciseSummaries.enumerated()), id: \.element.id) { index, summary in
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(summary.name)
                            .font(GSFont.bold(14, relativeTo: .body))
                            .foregroundStyle(theme.text)
                        Text(summary.metaText)
                            .font(GSFont.body(11, relativeTo: .caption))
                            .foregroundStyle(theme.neutral700)
                    }
                    Spacer()
                    if summary.isPR {
                        GSTag(text: "PR", style: .accent)
                    }
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 4)

                if index < exerciseSummaries.count - 1 {
                    Rectangle().fill(theme.divider).frame(height: 1)
                }
            }
        }
    }

    // Canvas: "Synced to Apple Health" card (Phase H) — surface-filled row,
    // accent plus-in-circle icon, bold title, muted "NN min · NNN kcal" meta
    // line. Matches the canvas's `.card.elev-sm` row (dc.html "SOLO RECAP",
    // the card following "By exercise") — GSCard already renders flat
    // (no shadow), matching the rest of this codebase's translation of
    // `.elev-*` canvas classes (none of GSComponents.swift's card usages add
    // `.shadow(...)` either).
    private func healthCard(_ summary: HealthSummary) -> some View {
        GSCard {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(theme.accent)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Synced to Apple Health")
                        .font(GSFont.bold(13, relativeTo: .subheadline))
                        .foregroundStyle(theme.text)
                    Text("\(summary.minutesText) · \(summary.caloriesText)")
                        .font(GSFont.body(11, relativeTo: .caption))
                        .foregroundStyle(theme.neutral700)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Canvas: recap sticky footer — single centered "Done" CTA (Dossier §A.4).
    private var doneFooter: some View {
        VStack(spacing: 0) {
            GSDivider()
            Button(action: onDone) {
                Text("Done")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(GSPrimaryButtonStyle(fontSize: 15, verticalPadding: 14))
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 22)
        }
        .background(theme.bg)
    }

    /// Trims a trailing ".0"/zero fraction so whole-number weights read as "190" not "190.0".
    private func decimalString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }
}
