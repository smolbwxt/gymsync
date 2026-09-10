import SwiftUI

// MARK: - GoalScreenView
//
// "Set a goal → Coach builds your block." Building a block ALWAYS begins with
// the goal; there is no other entry (spec §5, owner decision 4).
//
// Spec: docs/superpowers/specs/2026-09-07-goal-first-programming-design.md
// §5.1. Plan: docs/superpowers/plans/2026-09-07-goal-first-programming-plan.md,
// task C1.
//
// HERMETIC. No repository, no clock, no `AppState`: the screen is a title, a
// table of copy and a callback, which is what lets `goal-screen` (frame 93) be
// a capture rather than a fetch.
//
// ── ACCENT IS SPENT ONCE ON THIS SCREEN ──────────────────────────────────
//
// The `COACH SUGGESTS` marker, and nothing else. Design rule 2 gives accent
// three jobs — the one primary action, an invitation line, the current item —
// and this screen is a PICKER, so it has no primary (rule 4: the one primary
// lives on the milestone card). That leaves the current item, which is Coach's
// suggestion.
//
// The plan asked for the tile glyphs in `theme.accent` — the `doorLabel`
// recipe, which carries three of them on Coach home — and, three lines later,
// called the suggestion kicker "the only accent on this screen". Both were
// shipped as written and escalated; frame 93 settled it: with ten accent
// glyphs competing, the marker stopped reading as the current item at all.
// So the ten glyphs, the Pro door's glyph and its `PRO` capsule are all
// NEUTRAL now (controller ruling, review finding 2), and the one accent on
// the screen points at the one thing accent is for.

/// The first question of the build: which kind of goal is this block for?
struct GoalScreenView: View {

    /// The block that will be built, once a milestone is chosen.
    ///
    /// The draft handed over NAMES ITS PRESET and carries an empty target:
    /// seeding the numbers is the milestone card's job
    /// (`GoalMilestoneCopy.draft`, task C2), because the seed depends on what
    /// the athlete's log says right now and this screen deliberately reads
    /// nothing.
    var onChosen: (BlockGoalDraft) -> Void

    /// Coach's suggestion, seeded from the last block (spec §7). nil on a
    /// first block, which is the normal case in phase 1.
    var suggested: GoalPreset? = nil

    @Environment(\.gsTheme) private var theme

    // MARK: - The copy table
    //
    // The TABLE is what `GoalScreenCopyTests` reads, so the test reads the
    // SHIPPED values rather than a second copy of them.

    /// Plan task C1's table, verbatim. SF SYMBOLS ONLY (design rule 2: no
    /// decorative emoji), and no two presets share one — a grid where two
    /// tiles wear the same symbol is a grid nobody can scan.
    static let copy: [GoalPreset: (glyph: String, line: String)] = [
        .strength:        ("figure.strengthtraining.traditional",
                           "Add weight to a lift by a date."),
        .muscle:          ("figure.arms.open",
                           "More weekly sets for a muscle group."),
        .endurance:       ("figure.run",
                           "More distance each week."),
        .consistency:     ("calendar",
                           "Train more days a week, and hold it."),
        .conditioning:    ("bolt.heart",
                           "More sessions of one kind each week."),
        .maintenance:     ("equal.circle",
                           "Hold the recommended volumes."),
        .recovery:        ("figure.cooldown",
                           "Easy cardio and stretching, for a while."),
        .bodyComposition: ("scalemass",
                           "A body weight, at a safe rate."),
        .volume:          ("chart.bar.fill",
                           "Move a total this block."),
        .benchmark:       ("stopwatch",
                           "A named workout, faster."),
    ]

    /// The word on the tile — and, for `repStrength`, the word the Strength
    /// card's second lever wears. Sentence case here; the tile prints it in
    /// caps (design rule 9: caps for kickers and short labels).
    ///
    /// It lives beside `copy` rather than on `GoalPreset` because the model is
    /// Task 0's frozen surface and a display string is not part of it.
    static func name(_ preset: GoalPreset) -> String {
        switch preset {
        case .strength:        return "Strength"
        case .repStrength:     return "Rep strength"
        case .muscle:          return "Muscle"
        case .endurance:       return "Endurance"
        case .consistency:     return "Consistency"
        case .conditioning:    return "Conditioning"
        case .maintenance:     return "Maintenance"
        case .recovery:        return "Recovery"
        case .bodyComposition: return "Body composition"
        case .volume:          return "Volume"
        case .benchmark:       return "Benchmark"
        }
    }

    /// What a tile hands to `onChosen`.
    ///
    /// `source = .user` because the door is the athlete choosing — the same
    /// reason `BlockGoalDraft` defaults it that way, restated here so the
    /// screen's own test can say it out loud.
    static func chosen(_ preset: GoalPreset) -> BlockGoalDraft {
        BlockGoalDraft(metric: preset.metric, target: GoalTarget(),
                       byDate: nil, preset: preset, source: .user)
    }

    // MARK: - The Pro door's copy
    //
    // Static so the test reads the shipped strings, exactly like `copy`.

    /// PHASE-1 BEHAVIOUR, DECIDED IN THE PLAN (task C1): the door is RENDERED
    /// AND DISABLED.
    ///
    /// It is disabled because the feature is **not built yet** — spec §10 puts
    /// the Coach-guided consult in phase 2 — and NOT because of entitlement.
    /// `Entitlements.hasPro` is `true` today (`Models/CoachObservations.swift`
    /// :11-13, "every gate in the app asks HERE and nowhere else"), and that
    /// is the gate phase 2 consults. Naming the gate now and disabling for a
    /// stated reason is the honest shape; silently routing to a screen that
    /// cannot bind a goal is not.
    ///
    /// A constant rather than a read of `Entitlements.hasPro`, because a read
    /// whose answer is discarded is worse than no read: it would claim the
    /// entitlement was consulted when the door is shut for a different reason.
    /// Phase 2 replaces this line with that read.
    static let proDoorEnabled = false

    static let proDoorTitle = "Talk it through with Coach"
    static let proDoorGlyph = "bubble.left.and.text.bubble.right"
    static let proDoorLine = "Coach finds the goal and the ladder with you. Pick a preset below and I'll build to it."
    static let proDoorFooter = "PRO · ARRIVING WITH THE WATCH METRICS"

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                title
                grid
                proDoor
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(theme.bg)
        .navigationTitle("Your goal")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var title: some View {
        Text("Your goal for this block")
            .font(GSFont.heading(28, relativeTo: .largeTitle))
            .foregroundStyle(theme.text)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.bottom, 2)
    }

    // MARK: - The grid

    /// Two columns, `GoalPreset.tiles` in order — the spec §2.3 table's order,
    /// which is also the order the design reads them in.
    ///
    /// NO ACCENT PRIMARY on this screen (design rule 4): it is a picker, and
    /// the one primary lives on the milestone card.
    private var grid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10),
                            GridItem(.flexible(), spacing: 10)],
                  spacing: 10) {
            ForEach(GoalPreset.tiles, id: \.self) { preset in
                tile(preset)
            }
        }
    }

    /// A thing you press sinks (design rule 1), so the tile is
    /// `.gs3DCardStyle` rather than `.gs3DCard`.
    private func tile(_ preset: GoalPreset) -> some View {
        Button { onChosen(Self.chosen(preset)) } label: {
            tileLabel(preset)
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(preset))
    }

    private func tileLabel(_ preset: GoalPreset) -> some View {
        let entry = Self.copy[preset]
        return VStack(alignment: .leading, spacing: 6) {
            if preset == suggested {
                // ACCENT'S "CURRENT ITEM" JOB (design rule 2), and on this
                // screen it is the ONLY accent — see the type's doc comment.
                Text("COACH SUGGESTS")
                    .font(GSFont.bold(9, relativeTo: .caption2))
                    .tracking(1.1)
                    .foregroundStyle(theme.accent)
                    .lineLimit(1)
            }

            HStack(alignment: .top, spacing: 6) {
                Text(Self.name(preset).uppercased())
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.6)
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)

                Spacer(minLength: 4)

                // The `doorLabel` recipe (`CoachHomeView.swift:174-209`) at
                // tile scale — but NEUTRAL, not accent (see the type's doc
                // comment). Ten of these in a grid is not the three that
                // recipe was drawn for.
                Image(systemName: entry?.glyph ?? "questionmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }

            Text(entry?.line ?? "")
                .font(GSFont.body(11, relativeTo: .caption))
                .foregroundStyle(theme.neutral500)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .contentShape(Rectangle())
    }

    private func accessibilityLabel(_ preset: GoalPreset) -> String {
        let line = Self.copy[preset]?.line ?? ""
        let suggestion = preset == suggested ? "Coach suggests. " : ""
        return "\(suggestion)\(Self.name(preset)). \(line)"
    }

    // MARK: - The Pro door

    /// Below the grid, full width — the pro path (spec §2.4), rendered and
    /// disabled (see `proDoorEnabled`).
    ///
    /// The `PRO` capsule keeps `CoachOnboardingViews.swift:60-68`'s GEOMETRY
    /// and TYPOGRAPHY — 9 pt bold, 0.8 tracking, `Capsule()` stroke — so the
    /// badge is recognisably the same badge, and takes a NEUTRAL ink instead
    /// of that screen's accent. Design rule 4: badges point, they do not
    /// shout, and a tag on a door that cannot be opened yet is the last thing
    /// on this screen that should be the loudest.
    private var proDoor: some View {
        Button { } label: {
            proDoorLabel
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .disabled(!Self.proDoorEnabled)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Self.proDoorTitle). Pro.")
        .accessibilityHint("Not available yet — arriving with the watch metrics.")
    }

    private var proDoorLabel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(Self.proDoorTitle)
                    .font(GSFont.bold(16, relativeTo: .headline))
                    .foregroundStyle(theme.text)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                proCapsule

                Spacer(minLength: 4)

                Image(systemName: Self.proDoorGlyph)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(theme.neutral500)
            }

            Text(Self.proDoorLine)
                .font(GSFont.body(13, relativeTo: .subheadline))
                .foregroundStyle(theme.neutral700)
                .fixedSize(horizontal: false, vertical: true)

            Text(Self.proDoorFooter)
                .font(GSFont.bold(10, relativeTo: .caption2))
                .tracking(1.1)
                .foregroundStyle(theme.neutral500)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var proCapsule: some View {
        Text("PRO")
            .font(GSFont.bold(9, relativeTo: .caption2))
            .tracking(0.8)
            .foregroundStyle(theme.neutral500)
            .padding(.horizontal, 5).padding(.vertical, 2)
            .overlay(Capsule().strokeBorder(theme.neutral500, lineWidth: 1))
    }
}
