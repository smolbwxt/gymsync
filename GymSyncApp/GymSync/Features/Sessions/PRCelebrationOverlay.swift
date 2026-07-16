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
    let onDismiss: () -> Void

    @Environment(\.gsTheme) private var theme

    init(
        exerciseName: String,
        weight: Decimal,
        reps: Int,
        priorBest: Decimal,
        monthlyCount: Int?,
        onDismiss: @escaping () -> Void
    ) {
        self.exerciseName = exerciseName
        self.weight = weight
        self.reps = reps
        self.priorBest = priorBest
        self.monthlyCount = monthlyCount
        self.onDismiss = onDismiss
    }

    var body: some View {
        ZStack {
            theme.accent.ignoresSafeArea()

            // Concentric target-ring background (canvas chrome, approximated with two
            // static strokes — no animation/particle system exists in this app).
            ZStack {
                Circle().stroke(theme.bg.opacity(0.22), lineWidth: 1).frame(width: 340, height: 340)
                Circle().stroke(theme.bg.opacity(0.32), lineWidth: 1).frame(width: 230, height: 230)
            }

            VStack(spacing: 16) {
                Spacer()

                Text("🔥")
                    .font(.system(size: 44))

                Text("NEW PERSONAL RECORD")
                    .font(GSFont.bold(13, relativeTo: .caption))
                    .tracking(3.0)
                    .foregroundStyle(theme.bg.opacity(0.9))

                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(decimalString(weight))
                        .font(.custom("Archivo-Bold", size: 56))
                        .foregroundStyle(theme.bg)
                    Text("lbs")
                        .font(GSFont.bold(18, relativeTo: .title3))
                        .foregroundStyle(theme.bg.opacity(0.85))
                }

                Text("\(exerciseName) × \(reps)")
                    .font(GSFont.heading(20, relativeTo: .title3))
                    .foregroundStyle(theme.bg)
                    .multilineTextAlignment(.center)

                Text("▲ Beat your best by \(decimalString(weight - priorBest)) lbs")
                    .font(GSFont.bodyMedium(14, relativeTo: .body))
                    .foregroundStyle(theme.bg.opacity(0.9))

                if let count = monthlyCount, count > 0 {
                    Text("🏆 \(ordinal(count)) PR this month")
                        .font(GSFont.bold(12, relativeTo: .caption))
                        .foregroundStyle(theme.bg)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(theme.bg.opacity(0.18))
                }

                Spacer()

                HStack(spacing: 10) {
                    ShareLink(item: shareText) {
                        Text("Share")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.bg)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .overlay(Rectangle().strokeBorder(theme.bg.opacity(0.6), lineWidth: 1))

                    Button {
                        onDismiss()
                    } label: {
                        Text("Keep Lifting")
                            .font(GSFont.bold(15, relativeTo: .body))
                            .foregroundStyle(theme.accent)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .background(theme.bg)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .zIndex(10)
    }

    private var shareText: String {
        "New PR! \(exerciseName) — \(decimalString(weight)) lbs × \(reps) on GymSync."
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
