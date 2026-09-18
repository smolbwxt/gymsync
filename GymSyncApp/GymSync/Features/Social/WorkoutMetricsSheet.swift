import SwiftUI

// MARK: - The whole workout, behind the photo (spec §5)
//
// The pump-check card collapsed: the picture became an 88 pt tile and the
// per-set rows became one line per exercise. This is where the detail went —
// the full frame, then every exercise with every set exactly as the feed card
// drew them before, the bar-loader minis, the PR and FAIL tags, and line 5.
//
// IT READS NOTHING. Every value comes from the `WorkoutPost` the card already
// holds — `summary` is an immutable snapshot frozen at post time
// (`WorkoutPost.swift:6-9`) and the signed photo URL is handed in by the card,
// which fetched it for the thumbnail. There is no session fetch and there
// could not be one: another lifter's `sessions` row is not readable, which is
// why this is a sheet over the post rather than a link to
// `CompletedSessionView`.
//
// Weights render in the VIEWER'S unit, like everything else on the feed; the
// snapshot stays canonical pounds.
struct WorkoutMetricsSheet: View {
    let post: WorkoutPost
    /// The card's already-resolved signed URL. `nil` is the honest state for a
    /// post with no photo and for a link that failed — both draw the
    /// placeholder rather than an error.
    let photoURL: URL?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.gsTheme) private var theme

    private var unit: WeightUnit { ThemeStore.shared.weightUnit }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if post.photoPath != nil {
                        photoBlock
                    }
                    detail
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 24)
            }
            .scrollContentBackground(.hidden)
            .background(theme.bg)
            .navigationTitle("The workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // An escape hatch is never the accent (design rule 2, and
                    // `ReportSheet`'s own note). The accent this screen spends
                    // is the `PR` tag in the rows below.
                    Button("Done") { dismiss() }
                        .foregroundStyle(theme.neutral700)
                }
            }
        }
    }

    /// Full-bleed, which is the size the feed card gave up.
    private var photoBlock: some View {
        AsyncImage(url: photoURL) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            default:
                Rectangle().fill(theme.surface)
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

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(Array(post.summary.exercises.enumerated()), id: \.offset) { _, exercise in
                exerciseRow(exercise)
            }
            GSDivider()
            PumpPlainTerms(post: post, unit: unit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The feed card's own `exerciseRow`, moved here unchanged — spec
    /// decision 4's one mini bar per BARBELL exercise on its top set, the set
    /// list, and the two tags.
    private func exerciseRow(_ exercise: PostSummary.ExerciseEntry) -> some View {
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
}
