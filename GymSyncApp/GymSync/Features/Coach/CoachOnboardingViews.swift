import SwiftUI

// MARK: - Coach onboarding components (owner 2026-08-21: "full chain from
// touching the coach tab to the AI recap")
//
// Three sections the wizard composes, all in the wizard's own dial idiom:
// the persona strip (pick your coach — the preset that answers a dozen
// questions), ranked goals (tap in priority order; people can rank,
// nobody can emit "0.45"), and the novice calibration ("what feels hard
// for 5?" — weights the athlete states beat percentages nobody feels).

// MARK: Persona strip

struct CoachPersonaStrip: View {
    @Binding var selected: String?
    @Environment(\.gsTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR COACH")
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(0.9)
                .foregroundStyle(theme.text.opacity(0.78))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    card(slug: nil, name: "House Coach",
                         tagline: "Plain-spoken and practical. Reads the log, says what matters.")
                    ForEach(CoachPersona.all) { persona in
                        card(slug: persona.slug, name: persona.name,
                             tagline: persona.tagline, isPro: persona.isPro)
                    }
                }
                .padding(.vertical, 2)
            }
            if let slug = selected, let persona = CoachPersona.bySlug(slug) {
                Text(persona.philosophy)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func card(slug: String?, name: String, tagline: String,
                      isPro: Bool = false) -> some View {
        let isSelected = selected == slug
        return Button {
            selected = slug
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text(name.uppercased())
                        .font(GSFont.bold(13, relativeTo: .footnote))
                        .tracking(0.6)
                        .foregroundStyle(isSelected ? theme.bg : theme.text)
                        .lineLimit(1)
                    if isPro {
                        Text("PRO")
                            .font(GSFont.bold(9, relativeTo: .caption2))
                            .tracking(0.8)
                            .foregroundStyle(isSelected ? theme.bg : theme.accent)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .overlay(Capsule().strokeBorder(
                                isSelected ? theme.bg.opacity(0.6) : theme.accent, lineWidth: 1))
                    }
                }
                Text(tagline)
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(isSelected ? theme.bg.opacity(0.85) : theme.neutral500)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .padding(12)
            .frame(width: 190, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14)
                .fill(isSelected ? theme.accent : theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .strokeBorder(isSelected ? theme.accent : theme.neutral500.opacity(0.35),
                              lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: Ranked goals

struct GoalRankingSection: View {
    @Binding var ranked: [TrainingGoal]
    @Environment(\.gsTheme) private var theme

    private static let display: [(TrainingGoal, String)] = [
        (.hypertrophy, "Muscle"), (.maxStrength, "Strength"),
        (.powerRFD, "Power"), (.conditioning, "Conditioning"),
        (.fatLoss, "Fat Loss"), (.boneDensity, "Bone Density"),
        (.mobility, "Mobility"), (.sportPrep, "Sport Prep"),
        (.generalHealth, "General Health"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GOALS · TAP IN PRIORITY ORDER")
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(0.9)
                .foregroundStyle(theme.text.opacity(0.78))
            FlowChips(items: Self.display, ranked: $ranked)
            if let first = ranked.first,
               let label = Self.display.first(where: { $0.0 == first })?.1 {
                Text("\(label) leads — it sets the training style; the rest tilt what gets picked.")
                    .font(GSFont.body(11, relativeTo: .caption))
                    .foregroundStyle(theme.neutral500)
            }
        }
    }

    private struct FlowChips: View {
        let items: [(TrainingGoal, String)]
        @Binding var ranked: [TrainingGoal]
        @Environment(\.gsTheme) private var theme

        var body: some View {
            let columns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(items, id: \.0) { goal, label in
                    chip(goal: goal, label: label)
                }
            }
        }

        private func chip(goal: TrainingGoal, label: String) -> some View {
            let rank = ranked.firstIndex(of: goal).map { $0 + 1 }
            return Button {
                if let index = ranked.firstIndex(of: goal) {
                    ranked.remove(at: index)
                } else {
                    ranked.append(goal)
                }
            } label: {
                HStack(spacing: 5) {
                    if let rank {
                        Text("\(rank)")
                            .font(GSFont.bold(11, relativeTo: .caption2).monospacedDigit())
                            .foregroundStyle(theme.bg)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(theme.accent700))
                    }
                    Text(label)
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(rank != nil ? theme.bg : theme.text)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10).padding(.vertical, 7)
                .frame(maxWidth: .infinity)
                .background(Capsule().fill(rank != nil ? theme.accent : theme.surface))
                .overlay(Capsule().strokeBorder(
                    rank != nil ? theme.accent : theme.neutral500.opacity(0.35), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: Novice calibration ("what feels hard for 5?")

struct NoviceCalibrationSection: View {
    /// Anchor slug -> stated 5-rep weight, canonical POUNDS
    /// (LiftAnchorMath.anchorSlugs; owner 2026-08-12 + 2026-08-21:
    /// "percentages mean nothing to anyone other than the elite").
    @Binding var anchors: [String: Decimal]
    let unit: WeightUnit
    @Environment(\.gsTheme) private var theme

    private static let lifts: [(slug: String, name: String)] = [
        ("back-squat", "Squat"), ("bench-press", "Bench Press"),
        ("deadlift", "Deadlift"), ("ohp", "Overhead Press"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("STARTING POINTS · WHAT FEELS HARD FOR 5 REPS?")
                .font(GSFont.bold(13, relativeTo: .footnote))
                .tracking(0.9)
                .foregroundStyle(theme.text.opacity(0.78))
            Text("Honest guesses are fine — skip any lift you've never tried. Your first sessions start here and the log takes over from set one.")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(Self.lifts, id: \.slug) { lift in
                row(slug: lift.slug, name: lift.name)
            }
        }
    }

    private func row(slug: String, name: String) -> some View {
        let pounds = anchors[slug]
        let display = pounds.map {
            Units.format(pounds: $0, unit: unit, rounded: false, includeUnit: true)
        } ?? "—"
        let increment = unit.displayIncrement
        return HStack(spacing: 10) {
            Text(name)
                .font(GSFont.bold(14, relativeTo: .body))
                .foregroundStyle(theme.text)
            Spacer()
            Button { step(slug: slug, by: -increment) } label: {
                Image(systemName: "minus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(pounds == nil ? theme.neutral500 : theme.accent)
            }
            .buttonStyle(.plain)
            Text(display)
                .font(GSFont.bold(15, relativeTo: .body).monospacedDigit())
                .foregroundStyle(pounds == nil ? theme.neutral500 : theme.text)
                .frame(minWidth: 76)
            Button { step(slug: slug, by: increment) } label: {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(theme.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 2)
    }

    private func step(slug: String, by unitDelta: Decimal) {
        let currentUnit = anchors[slug].map { Units.fromPounds($0, to: unit) } ?? 0
        let next = max(0, currentUnit + unitDelta)
        if next <= 0 {
            anchors[slug] = nil
        } else {
            anchors[slug] = Units.toPounds(next, from: unit)
        }
    }
}
