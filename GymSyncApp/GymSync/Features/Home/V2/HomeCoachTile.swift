import SwiftUI

/// Coach as a TILE — arrangement A's right-hand slot.
///
/// A widget is named by a word, not a label (design language rule 3): the word
/// `Coach` at 24 pt, and under it one state line written as a sentence in
/// Coach's own first-person voice (rule 7). Badges point rather than shout
/// (rule 4): a small accent count in the corner, and only when something is
/// actually waiting.
///
/// Extruded and tappable — one tap opens the seeded thread (rule 7), which is
/// why this is `.gs3DCardStyle` (it sinks) rather than `.gs3DCard`.
struct HomeCoachTile: View {
    @Environment(\.gsTheme) private var theme

    let sentence: String
    /// `nil` (or 0) = nothing waiting, so no badge at all.
    var waiting: Int?
    /// Tap → the Coach thread, seeded with this line.
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 8) {
                    Text("Coach")
                        .font(GSFont.heading(24, relativeTo: .title2))
                        .foregroundStyle(theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if let waiting, waiting > 0 {
                        badge(waiting)
                    }
                }

                Text(sentence)
                    .font(GSFont.body(12, relativeTo: .caption))
                    .foregroundStyle(theme.neutral700)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(15)
            .contentShape(Rectangle())
        }
        .buttonStyle(.gs3DCardStyle(cornerRadius: GSMetrics.radiusMd))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let waiting, waiting > 0 else { return "Coach. \(sentence)" }
        return "Coach, \(waiting) waiting. \(sentence)"
    }

    private func badge(_ count: Int) -> some View {
        Text("\(count)")
            .font(GSFont.bold(12, relativeTo: .caption))
            .monospacedDigit()
            .foregroundStyle(theme.bg)
            .frame(width: 26, height: 26)
            .background(Circle().fill(theme.accent))
    }
}
