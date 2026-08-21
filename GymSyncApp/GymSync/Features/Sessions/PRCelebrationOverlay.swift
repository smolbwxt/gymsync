import SwiftUI

// MARK: - PRCelebrationOverlay
//
// Full-screen, USER-DISMISSED PR celebration (canvas frame p29) — lifted out of
// `GroupSessionLiveView` (Phase P Task 1) so solo sessions and the debug catalog can
// reuse the identical visual + dismiss behavior. Every color/font/layout token below
// is copied verbatim from the original `prCelebrationOverlay` computed property —
// this is a behavior-preserving extraction, not a redesign.
//
// Trigger + dismiss semantics are owned by the caller: the caller decides when to
// show this view (e.g. `if isPROverlay { PRCelebrationOverlay(...) }`) and supplies
// `onDismiss` for the "Keep Lifting" action — there is NO auto-timeout here, matching
// the original group-session behavior exactly.

struct PRCelebrationOverlay: View {
    let exerciseName: String
    let weight: Decimal
    let reps: Int
    let priorBest: Decimal
    let monthlyCount: Int?
    /// Units sweep — display unit; stored weights arrive as pounds.
    /// Trailing-defaulted so GroupSessionLiveView's call site compiles
    /// unchanged (lbs) until its own sweep.
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

    // Onyx redesign (user 2026-08-01: "make the screen congruent with the
    // current theme from the main lobby and my turn/spectator screen"):
    // the accent flood becomes the Onyx floor — near-black bg, accent
    // reserved for the record itself and the primary CTA, big fixed-size
    // numerals with the 3pt accent underline (the "yours" mark), floating
    // rounded cards for the chip and CTAs.
    var body: some View {
        ZStack {
            theme.bg.ignoresSafeArea()

            // Concentric rings, now in the accent at low opacity — the
            // target chrome survives the palette flip.
            ZStack {
                Circle().stroke(theme.accent.opacity(0.14), lineWidth: 1.5).frame(width: 360, height: 360)
                Circle().stroke(theme.accent.opacity(0.24), lineWidth: 1.5).frame(width: 240, height: 240)
            }

            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "flame.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(theme.accent)

                Color.clear.frame(height: 16)

                Text("NEW PERSONAL RECORD")
                    .font(GSFont.bold(12, relativeTo: .caption))
                    .tracking(3.0)
                    .foregroundStyle(theme.neutral700)

                Color.clear.frame(height: 14)

                // Rep-PR form (owner item 6, 2026-08-13): weight == 0 means
                // a bodyweight rep record — the rep count IS the headline,
                // and priorBest carries prior REPS, not pounds.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if weight == 0 {
                        Text("\(reps)")
                            .font(GSFont.boldFixed(72).monospacedDigit())
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text("REPS")
                            .font(GSFont.bold(16, relativeTo: .title3))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral700)
                    } else {
                        Text(Units.format(pounds: weight, unit: unit, rounded: false, includeUnit: false))
                            .font(GSFont.boldFixed(72).monospacedDigit())
                            .foregroundStyle(theme.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                        Text(unit.label.uppercased())
                            .font(GSFont.bold(16, relativeTo: .title3))
                            .tracking(1.0)
                            .foregroundStyle(theme.neutral700)
                    }
                }
                Capsule().fill(theme.accent)
                    .frame(width: 56, height: 3)
                    .padding(.top, 8)

                Color.clear.frame(height: 16)

                Text(weight == 0 ? exerciseName : "\(exerciseName) × \(reps)")
                    .font(GSFont.bold(20, relativeTo: .title3))
                    .foregroundStyle(theme.text)
                    .multilineTextAlignment(.center)

                Color.clear.frame(height: 10)

                Text(weight == 0
                     ? "▲ \(reps - (priorBest).displayInt) REPS OVER YOUR BEST"
                     : "▲ \(Units.format(pounds: weight - priorBest, unit: unit, rounded: false, includeUnit: false)) \(unit.label.uppercased()) OVER YOUR BEST")
                    .font(GSFont.bold(12, relativeTo: .caption).monospacedDigit())
                    .tracking(0.8)
                    .foregroundStyle(theme.accent)

                if let count = monthlyCount, count > 0 {
                    Color.clear.frame(height: 16)
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.accent)
                        Text("\(ordinal(count).uppercased()) PR THIS MONTH")
                            .font(GSFont.bold(10, relativeTo: .caption2))
                            .tracking(1.0)
                            .foregroundStyle(theme.text.opacity(0.78))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(theme.surface)
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(theme.neutral500.opacity(0.35), lineWidth: 1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                Spacer()

                // 3D pass (2026-08): both CTAs wear the extruded style —
                // accent face for the primary, quiet raised face for SHARE
                // (ShareLink takes a ButtonStyle like any Button — same
                // idiom as SessionRecapView's styled Share Recap link).
                // Faces are 7pt shorter so face + lip keeps each button's
                // exact prior footprint (64 and 48).
                VStack(spacing: 10) {
                    Button {
                        onDismiss()
                    } label: {
                        Text("KEEP LIFTING")
                            .font(GSFont.bold(17, relativeTo: .body))
                            .tracking(0.9)
                            .foregroundStyle(theme.bg)
                            .frame(maxWidth: .infinity)
                            .frame(height: 57)   // + 7pt lip = the 64pt CTA rhythm
                    }
                    .buttonStyle(.gs3D(face: theme.accent, cornerRadius: 16))

                    ShareLink(item: shareText) {
                        Text("SHARE")
                            .font(GSFont.bold(13, relativeTo: .subheadline))
                            .tracking(0.9)
                            .foregroundStyle(theme.text.opacity(0.78))
                            .frame(maxWidth: .infinity, minHeight: 41)   // + 7pt lip = the prior 48pt
                    }
                    .buttonStyle(.gs3D(face: theme.raised3DFace, lip: theme.raised3DLip, cornerRadius: 16))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
    }

    private var shareText: String {
        weight == 0
            ? "New PR! \(exerciseName) — \(reps) reps on GymSync."
            : "New PR! \(exerciseName) — \(Units.format(pounds: weight, unit: unit, rounded: false, includeUnit: false)) \(unit.label) × \(reps) on GymSync."
    }

    // `decimalString`/`ordinal` are copied verbatim from `GroupSessionLiveView` (which
    // keeps its own private copies — they're still used there by unrelated elements:
    // the roster grid's weight formatting and the rotation strip's ordinal labels — so
    // this is a duplicate for isolation, not a shared extraction of those helpers).
    private func decimalString(_ value: Decimal) -> String {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, 0, .plain)
        return rounded == value ? "\(rounded)" : "\(value)"
    }

    private func ordinal(_ n: Int) -> String {
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
}
