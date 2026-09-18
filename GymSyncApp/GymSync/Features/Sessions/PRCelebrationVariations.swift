#if DEBUG
import SwiftUI

// MARK: - PRCelebrationVariations
//
// THE DESIGN ROUND for the PR celebration (owner 2026-09-18). Two real
// screens for the owner to choose between, catalog-only, `#if DEBUG`, and
// retired in the same commit that rebuilds the production overlay to the
// pick. `PRCelebrationOverlay` is NOT touched by this file's commit, so the
// owner's card has an honest "what ships now" panel beside these two.
//
// WHAT THEY ARE ARGUING ABOUT. The live screen (frame 29,
// pr-celebration-live-2026-09-18.png) spends the accent SIX times on one
// page — the 34 pt headline, the sweep capsule under it, two concentric
// rings, the delta line and the CTA — where design rule 2 spends it ONCE.
// It also draws its trophy chip on `theme.surface` with a third corner
// radius of 12 (rule 1 allows two: `radiusMd` 24 and `radiusSm` 16, plus the
// 14 pt STRIP), and words its delta with a `▲` text glyph where rule 9 asks
// for an SF Symbol. Both variations fix all of that. They differ in
// COMPOSITION, not in colour:
//
//   A — THE NUMBER LEADS. The record itself is the hero: the tabular number
//       at maximum size with one small unit beside it (rule 3), "New
//       personal record." demoted to a KICKER above it, the lift and the
//       delta folded into ONE sentence on a `surface` strip beneath, and the
//       monthly count as a `gsSuccess` tick riding that strip. Accent is
//       spent once, on KEEP LIFTING; Share is a quiet raised face under it.
//
//   B — THE LIFT'S PLACE ON YOUR LADDER LEADS. The record is read as
//       PROGRESS rather than as a number: one raised island carrying the
//       lift, the old number and the new one as a before/after pair, and the
//       rung the athlete now stands on, worded from the six values the
//       caller already holds. `nth PR this month` becomes the island's
//       kicker and Share a flat glyph chip in its header, so the page's foot
//       is one button. Accent is spent once, on the NEW NUMBER — which
//       leaves KEEP LIFTING on the raised face. Rule 2 forbids TWO accent
//       buttons, not zero, and the Onyx ruling this screen was built under
//       reserves the accent "for the record itself".
//
// BOTH keep all six facts the live screen carries — the headline, the number
// and its unit, the lift × reps, the delta over your best, the monthly count
// and both actions — and both keep the REP-PR FORM (`weight == 0`: the rep
// count is the record and `priorBest` carries prior REPS). Neither adds a
// kudos row (rule 8). Both take exactly the six values
// `PRCelebrationOverlay`'s initializer takes, so whichever wins can be
// rebuilt into that type without touching a call site.
//
// CONSTRAINT 11: pure value-in views over one shared literal fixture. No
// `Date()`, no repository, no `.shared`, and `CelebrationSound` is nowhere
// near them — the overlay never plays the sound, its two callers do, so a
// catalog capture is silent by construction.

// MARK: - The shared fixture
//
// Deliberately identical to `content_prCelebration`'s
// (`CatalogHostView.swift`), so the three captures are the SAME record drawn
// three ways and the owner is comparing compositions, not numbers.
struct PRCelebrationFixture {
    let exerciseName: String
    let weight: Decimal
    let reps: Int
    let priorBest: Decimal
    let monthlyCount: Int?
    let unit: WeightUnit

    static let bench = PRCelebrationFixture(
        exerciseName: "Bench Press",
        weight: 205,
        reps: 5,
        priorBest: 200,
        monthlyCount: 3,
        unit: .lbs
    )
}

// MARK: - Shared wording
//
// File-scope so the two compositions cannot drift into two different
// sentences about the same record. Verbatim from `PRCelebrationOverlay` where
// the wording already exists (`shareText`, `ordinal`).

private func prVariationOrdinal(_ n: Int) -> String {
    let suffix: String
    switch n % 100 {
    case 11...13: suffix = "th"
    default:
        switch n % 10 {
        case 1: suffix = "st"
        case 2: suffix = "nd"
        case 3: suffix = "rd"
        default: suffix = "th"
        }
    }
    return "\(n)\(suffix)"
}

private func prVariationShareText(exerciseName: String, weight: Decimal,
                                  reps: Int, unit: WeightUnit) -> String {
    weight == 0
        ? "New PR! \(exerciseName) — \(reps) reps on GymSync."
        : "New PR! \(exerciseName) — \(Units.format(pounds: weight, unit: unit, rounded: false, includeUnit: false)) \(unit.label) × \(reps) on GymSync."
}

/// The record's own number, rep-PR form included: `weight == 0` means the rep
/// count IS the record.
private func prVariationValueText(weight: Decimal, reps: Int, unit: WeightUnit) -> String {
    weight == 0
        ? "\(reps)"
        : Units.format(pounds: weight, unit: unit, rounded: false, includeUnit: false)
}

private func prVariationUnitText(weight: Decimal, unit: WeightUnit) -> String {
    weight == 0 ? "REPS" : unit.label.uppercased()
}

// MARK: - A · the number leads

struct PRCelebrationVariationA: View {
    let exerciseName: String
    let weight: Decimal
    let reps: Int
    let priorBest: Decimal
    let monthlyCount: Int?
    var unit: WeightUnit = .lbs
    let onDismiss: () -> Void

    @Environment(\.gsTheme) private var theme

    init(
        exerciseName: String,
        weight: Decimal,
        reps: Int,
        priorBest: Decimal,
        monthlyCount: Int?,
        unit: WeightUnit = .lbs,
        onDismiss: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.priorBest = priorBest
        self.monthlyCount = monthlyCount
        self.unit = unit
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: 96)
                kicker
                Color.clear.frame(height: 18)
                heroNumber
                Color.clear.frame(height: 26)
                strip
                Spacer()
                actions
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
    }

    /// Rule 3: 11 pt caps, ~0.12 em tracking, muted. The headline is a fact
    /// about the number below it, not the loudest thing on the page — which
    /// is what frees the accent for the one action.
    private var kicker: some View {
        Text("NEW PERSONAL RECORD")
            .font(GSFont.bold(11, relativeTo: .caption2))
            .tracking(1.3)
            .foregroundStyle(theme.neutral700)
            .multilineTextAlignment(.center)
    }

    /// Rule 3's hero: the largest thing on the page, tabular, with ONE small
    /// unit beside it. 96 pt against the live screen's 72 — with nothing else
    /// competing, it can be.
    private var heroNumber: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(prVariationValueText(weight: weight, reps: reps, unit: unit))
                .font(GSFont.boldFixed(96).monospacedDigit())
                .foregroundStyle(theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(prVariationUnitText(weight: weight, unit: unit))
                .font(GSFont.bold(16, relativeTo: .title3))
                .tracking(1.0)
                .foregroundStyle(theme.neutral700)
        }
        .padding(.horizontal, 16)
    }

    /// Rule 1's STRIP: `surface`, 14 pt, flat — a line that belongs to the
    /// number above it (the same form `RoundPieces.swift:583` already uses).
    /// Not a raised face, which rule 1 forbids `theme.surface` from being.
    /// The lift, the reps and the delta are one sentence here rather than
    /// three stacked lines, and the `▲` text glyph is an SF Symbol (rule 9).
    private var strip: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(theme.neutral800)
            Text(sentence)
                .font(GSFont.bodyMedium(13, relativeTo: .footnote).monospacedDigit())
                .foregroundStyle(theme.neutral800)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            monthlyTick
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 16)
    }

    /// The monthly count as a `gsSuccess` tick on the strip — done/present,
    /// which is what "that is your third this month" says — rather than the
    /// live screen's bordered `theme.surface` chip at a third radius.
    @ViewBuilder
    private var monthlyTick: some View {
        if let count = monthlyCount, count > 0 {
            HStack(spacing: 5) {
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.gsSuccess)
                Text("\(prVariationOrdinal(count).uppercased()) THIS MONTH")
                    .font(GSFont.bold(10, relativeTo: .caption2))
                    .tracking(1.0)
                    .foregroundStyle(Color.gsSuccess)
            }
        }
    }

    /// THE PAGE'S ONE ACCENT (rule 2): the primary action. Share keeps the
    /// quiet raised face it already wears. Both radii are `radiusSm`, where
    /// the live screen hardcodes 16.
    private var actions: some View {
        VStack(spacing: 10) {
            Button {
                onDismiss()
            } label: {
                Text("KEEP LIFTING")
                    .font(GSFont.bold(17, relativeTo: .body))
                    .tracking(0.9)
                    .foregroundStyle(theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 57)
            }
            .buttonStyle(.gs3D(face: theme.accent, cornerRadius: GSMetrics.radiusSm))

            ShareLink(item: prVariationShareText(exerciseName: exerciseName, weight: weight,
                                                 reps: reps, unit: unit)) {
                Text("SHARE")
                    .font(GSFont.bold(13, relativeTo: .subheadline))
                    .tracking(0.9)
                    .foregroundStyle(theme.text.opacity(0.78))
                    .frame(maxWidth: .infinity, minHeight: 41)
            }
            .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                               cornerRadius: GSMetrics.radiusSm))
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    /// The lift, its reps and the delta as ONE sentence (rule 9: sentence
    /// case for sentences). The rep-PR form reads its delta in reps, from
    /// `priorBest` carrying prior REPS.
    private var sentence: String {
        if weight == 0 {
            return "\(exerciseName), \(reps - priorBest.displayInt) reps over your best."
        }
        let delta = Units.format(pounds: weight - priorBest, unit: unit,
                                 rounded: false, includeUnit: false)
        return "\(exerciseName) × \(reps), \(delta) \(unit.label) over your best."
    }
}

extension PRCelebrationVariationA {
    init(fixture: PRCelebrationFixture, onDismiss: @escaping () -> Void) {
        self.init(exerciseName: fixture.exerciseName, weight: fixture.weight,
                  reps: fixture.reps, priorBest: fixture.priorBest,
                  monthlyCount: fixture.monthlyCount, unit: fixture.unit,
                  onDismiss: onDismiss)
    }
}

// MARK: - B · the lift's place on your ladder leads

struct PRCelebrationVariationB: View {
    let exerciseName: String
    let weight: Decimal
    let reps: Int
    let priorBest: Decimal
    let monthlyCount: Int?
    var unit: WeightUnit = .lbs
    let onDismiss: () -> Void

    @Environment(\.gsTheme) private var theme

    init(
        exerciseName: String,
        weight: Decimal,
        reps: Int,
        priorBest: Decimal,
        monthlyCount: Int?,
        unit: WeightUnit = .lbs,
        onDismiss: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.priorBest = priorBest
        self.monthlyCount = monthlyCount
        self.unit = unit
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                Color.clear.frame(height: 84)
                headline
                Color.clear.frame(height: 28)
                island
                Spacer()
                keepLifting
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
    }

    /// Rule 8's headline, first — but in DEFAULT TEXT, because this page
    /// spends its one accent on the number inside the island.
    private var headline: some View {
        Text("New personal record.")
            .font(GSFont.heading(26, relativeTo: .title2))
            .foregroundStyle(theme.text)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
    }

    /// ONE raised island (rule 1: `.gs3DCard`, `radiusMd`, 6 pt lip) holding
    /// the whole record. Where the live screen draws two accent rings, this
    /// draws the rung the lift now stands on.
    private var island: some View {
        VStack(alignment: .leading, spacing: 14) {
            islandHeader
            liftLine
            beforeAfter
            rungLine
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .gs3DCard(cornerRadius: GSMetrics.radiusMd, lipHeight: 6)
        .padding(.horizontal, 16)
    }

    private var islandHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            monthlyKicker
            Spacer(minLength: 8)
            shareChip
        }
    }

    /// The monthly count is this card's KICKER (rule 3: 11 pt caps, ~0.12 em,
    /// muted) rather than a chip of its own.
    @ViewBuilder
    private var monthlyKicker: some View {
        if let count = monthlyCount, count > 0 {
            Text("\(prVariationOrdinal(count).uppercased()) PR THIS MONTH")
                .font(GSFont.bold(11, relativeTo: .caption2))
                .tracking(1.3)
                .foregroundStyle(theme.neutral700)
        }
    }

    /// Share moves into the card's header so the page's FOOT is one button.
    /// FLAT, on a `surface` chip: rule 1 says furniture inside a raised box
    /// stays flat, and a second extrusion on top of the island would read as
    /// a second object rather than as a control on the first.
    private var shareChip: some View {
        ShareLink(item: prVariationShareText(exerciseName: exerciseName, weight: weight,
                                             reps: reps, unit: unit)) {
            Image(systemName: "square.and.arrow.up")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.neutral800)
                .frame(width: 38, height: 34)
                .background(theme.surface)
                .clipShape(Capsule())
        }
    }

    private var liftLine: some View {
        Text(weight == 0 ? exerciseName : "\(exerciseName) × \(reps)")
            .font(GSFont.bold(20, relativeTo: .title3))
            .foregroundStyle(theme.text)
    }

    /// The before/after pair — the old number, small and muted, the new one
    /// large and in the page's ONE accent (rule 3: tabular, hero, one small
    /// unit beside it). The `▲` glyph becomes an SF Symbol (rule 9).
    private var beforeAfter: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(priorValueText)
                .font(GSFont.boldFixed(26).monospacedDigit())
                .foregroundStyle(theme.neutral700)
            Image(systemName: "arrow.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(theme.neutral500)
            Text(prVariationValueText(weight: weight, reps: reps, unit: unit))
                .font(GSFont.boldFixed(64).monospacedDigit())
                .foregroundStyle(theme.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(prVariationUnitText(weight: weight, unit: unit))
                .font(GSFont.bold(15, relativeTo: .subheadline))
                .tracking(1.0)
                .foregroundStyle(theme.neutral700)
        }
    }

    private var rungLine: some View {
        Text(rungSentence)
            .font(GSFont.body(13, relativeTo: .footnote).monospacedDigit())
            .foregroundStyle(theme.neutral800)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The page's foot: ONE button, on the raised face, because the accent
    /// was already spent on the number.
    private var keepLifting: some View {
        Button {
            onDismiss()
        } label: {
            Text("KEEP LIFTING")
                .font(GSFont.bold(17, relativeTo: .body))
                .tracking(0.9)
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity)
                .frame(height: 57)
        }
        .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip,
                           cornerRadius: GSMetrics.radiusSm))
        .padding(.horizontal, 16)
        .padding(.bottom, 20)
    }

    /// The old number. Rep-PR form: `priorBest` carries prior REPS, so it is
    /// printed as an integer rather than run through `Units.format`.
    private var priorValueText: String {
        weight == 0
            ? "\(priorBest.displayInt)"
            : Units.format(pounds: priorBest, unit: unit, rounded: false, includeUnit: false)
    }

    /// The rung, worded ONLY from the six values the caller already holds —
    /// no block, no history, no fetch (constraint 11).
    private var rungSentence: String {
        if weight == 0 {
            let delta = reps - priorBest.displayInt
            return "Your ladder on this lift moved up \(delta) reps. \(reps) unloaded is the rung you stand on now."
        }
        let delta = Units.format(pounds: weight - priorBest, unit: unit,
                                 rounded: false, includeUnit: false)
        let now = Units.format(pounds: weight, unit: unit, rounded: false, includeUnit: false)
        return "Your ladder on this lift moved up \(delta) \(unit.label). \(now) × \(reps) is the rung you stand on now."
    }
}

extension PRCelebrationVariationB {
    init(fixture: PRCelebrationFixture, onDismiss: @escaping () -> Void) {
        self.init(exerciseName: fixture.exerciseName, weight: fixture.weight,
                  reps: fixture.reps, priorBest: fixture.priorBest,
                  monthlyCount: fixture.monthlyCount, unit: fixture.unit,
                  onDismiss: onDismiss)
    }
}
#endif
